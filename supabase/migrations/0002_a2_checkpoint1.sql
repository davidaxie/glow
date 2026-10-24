-- 0002_a2_checkpoint1.sql · A2 · Checkpoint 1 fixes
--
-- Never edit 0001. Every fix here replaces functions with create or replace, adds objects, or
-- changes defaults. Numbers match the Checkpoint 1 review:
--   1. Later migrations' tables, sequences and functions are usable by service_role by default.
--   3. start_glow never leaves a match stuck in choosing: it opens the chat or says why it waits.
--   4. create_checkin needs a passed join location check, so a QR code alone never makes a card.
--   5. complete_onboarding, for people who decline push.
--   6. Functions that apply timeouts lazily say so ("settled"), so the server can notify both.
--   7. Taps never reach the metrics (P5).
--   8. Daily taps are counted apart from the per-pair tap row.
--   9. get_deck answers 404 only for an unknown room or one you haven't checked in to today.
--   (2, the match.recheck push, is in contracts/events.json; set_choice names who to send it to.)

-------------------------------------------------------------------------------
-- 1. service_role can use whatever later migrations create
-------------------------------------------------------------------------------

-- With auto_expose_new_tables = false (supabase/config.toml), new objects get no grants at all,
-- so a route would fail with "permission denied" while pgTAP (running as postgres) still passes.
-- Clients (anon, authenticated) still get nothing; 0001's revokes stay as they are.
alter default privileges in schema public  grant all     on tables    to service_role;
alter default privileges in schema public  grant all     on sequences to service_role;
alter default privileges in schema public  grant execute on functions to service_role;
alter default privileges in schema private grant select  on tables    to service_role;
alter default privileges in schema private grant execute on functions to service_role;

-------------------------------------------------------------------------------
-- 8 and 9. room_days: one row per person, room and room day
-------------------------------------------------------------------------------

-- taps_used counts today's taps on its own, apart from the per-pair tap row, so a re-tap after an
-- unmatch uses a tap like any other and tapsLeftToday is exact. The row itself also records that
-- the person checked in to the room today, so get_deck can tell "your check-in ended" from "you
-- were never here" after purge deletes the check-in. Purged after CARD_VIEW_RETENTION.
create table public.room_days (
  user_id   uuid not null references public.profiles (id) on delete cascade,
  room_id   uuid not null references public.rooms (id) on delete cascade,
  day       date not null,
  taps_used integer not null default 0 check (taps_used >= 0),
  primary key (user_id, room_id, day)
);
create index room_days_room on public.room_days (room_id);
create index room_days_day on public.room_days (day);
alter table public.room_days enable row level security;
revoke all on public.room_days from anon, authenticated;
grant all on public.room_days to service_role;

-- Carry over what already happened today.
insert into public.room_days (user_id, room_id, day, taps_used)
select t.from_user, t.room_id, private.room_day(t.room_id), count(*)::integer
  from public.taps t
 where t.created_at >= private.room_day_start(t.room_id)
 group by t.from_user, t.room_id
on conflict do nothing;
insert into public.room_days (user_id, room_id, day)
select distinct c.user_id, c.room_id, private.room_day(c.room_id)
  from public.checkins c
on conflict do nothing;

-------------------------------------------------------------------------------
-- 7. Taps never reach the metrics (P5)
-------------------------------------------------------------------------------

-- A tap count over a short window lets an admin standing in the room time someone's one-sided
-- tap. The enum value stays (Postgres can't drop one), but no row may use it.
delete from public.room_activity where kind = 'tap';
alter table public.room_activity add constraint room_activity_no_taps check (kind <> 'tap');

-------------------------------------------------------------------------------
-- 6. Settled transitions
-------------------------------------------------------------------------------

-- Retire active glows whose time ran out, and move their matches to chatting.
-- Returns [{ matchId, kind: "glow_expired", userIds }] for glow.ended events.
create or replace function private.expire_glows(p_room_id uuid default null)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  with expired as (
    update public.glow_sessions g
       set status = 'expired', ended_at = g.ends_at
     where g.status = 'active'
       and g.ends_at <= now()
       and (p_room_id is null or g.room_id = p_room_id)
    returning g.match_id
  ), moved as (
    update public.matches m
       set status = 'chatting'
      from expired e
     where m.id = e.match_id and m.status = 'glowing'
    returning m.id
  )
  select coalesce(jsonb_agg(jsonb_build_object('matchId', m.id, 'kind', 'glow_expired', 'userIds', jsonb_build_array(m.user_a, m.user_b))),
                  '[]'::jsonb)
    into v_result
    from expired e
    join public.matches m on m.id = e.match_id;
  return v_result;
end;
$$;

-- Apply time-based changes to one match, and say what changed:
-- [{ matchId, kind: "choice_timeout" | "glow_expired", userIds }]. The caller must notify both
-- people: choice_timeout → match.choice (the chat opened), glow_expired → glow.ended.
-- Call with the match row locked.
create function private.settle_match_events(p_match_id uuid)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_m      public.matches;
  v_events jsonb := '[]'::jsonb;
begin
  select * into v_m from public.matches where id = p_match_id;
  if not found then
    return v_events;
  end if;

  update public.glow_sessions g
     set status = 'expired', ended_at = g.ends_at
   where g.match_id = p_match_id and g.status = 'active' and g.ends_at <= now();
  if found then
    update public.matches set status = 'chatting' where id = p_match_id and status = 'glowing';
    v_events := v_events || jsonb_build_array(jsonb_build_object(
      'matchId', p_match_id, 'kind', 'glow_expired', 'userIds', jsonb_build_array(v_m.user_a, v_m.user_b)));
  end if;

  update public.matches
     set status = 'chatting'
   where id = p_match_id and status = 'choosing' and choice_deadline <= now();
  if found then
    v_events := v_events || jsonb_build_array(jsonb_build_object(
      'matchId', p_match_id, 'kind', 'choice_timeout', 'userIds', jsonb_build_array(v_m.user_a, v_m.user_b)));
  end if;

  return v_events;
end;
$$;

-- get_match (replaced): adds settled.
-- Returns MatchDetail plus userIds and settled (both server only). Raises not_found.
create or replace function public.get_match(p_user_id uuid, p_match_id uuid)
returns jsonb
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_m       public.matches;
  v_settled jsonb;
begin
  select * into v_m from public.matches where id = p_match_id for update;
  if not found or p_user_id is null or p_user_id not in (v_m.user_a, v_m.user_b) or v_m.status = 'ended' then
    perform private.raise_error('not_found');
  end if;
  v_settled := private.settle_match_events(p_match_id);
  select * into v_m from public.matches where id = p_match_id;
  return private.match_json(v_m, p_user_id) || jsonb_build_object('settled', v_settled);
end;
$$;

-- list_matches (replaced): adds settled. Returns { matches, settled }.
create or replace function public.list_matches(p_user_id uuid)
returns jsonb
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_id      uuid;
  v_result  jsonb;
  v_settled jsonb := '[]'::jsonb;
begin
  for v_id in
    select m.id from public.matches m
     where (m.user_a = p_user_id or m.user_b = p_user_id) and m.status in ('choosing', 'glowing')
     order by m.id
       for update
  loop
    v_settled := v_settled || private.settle_match_events(v_id);
  end loop;

  select coalesce(jsonb_agg(private.match_json(m, p_user_id) order by m.created_at desc), '[]'::jsonb)
    into v_result
    from public.matches m
   where (m.user_a = p_user_id or m.user_b = p_user_id) and m.status <> 'ended';
  return jsonb_build_object('matches', v_result, 'settled', v_settled);
end;
$$;

drop function private.settle_match(uuid);

-- set_choice (replaced): applies timeouts first and reports them in settled. When the other
-- person's location check has gone stale, recheckUserIds names them: send them match.recheck,
-- the push that asks them to open Glow so their app sends Find again with a fresh fix.
create or replace function public.set_choice(p_user_id uuid, p_match_id uuid, p_choice public.match_choice)
returns jsonb
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_m            public.matches;
  v_is_a         boolean;
  v_other        uuid;
  v_other_choice public.match_choice;
  v_settled      jsonb;
begin
  if p_user_id is null or p_match_id is null or p_choice is null then
    perform private.raise_error('invalid_input');
  end if;

  select * into v_m from public.matches where id = p_match_id for update;
  if not found or p_user_id not in (v_m.user_a, v_m.user_b) or v_m.status = 'ended' then
    perform private.raise_error('not_found');
  end if;
  v_settled := private.settle_match_events(p_match_id);
  select * into v_m from public.matches where id = p_match_id;
  v_is_a  := p_user_id = v_m.user_a;
  v_other := case when v_is_a then v_m.user_b else v_m.user_a end;

  if v_settled @> '[{"kind": "choice_timeout"}]'::jsonb then
    return jsonb_build_object('settled', v_settled) || private.choice_json(v_m, p_user_id, 'chat', 'timeout');
  end if;

  if v_m.status <> 'choosing' then
    return jsonb_build_object('settled', v_settled) || private.choice_json(v_m, p_user_id,
                               case when v_m.status = 'glowing' then 'glow' else 'chat' end, 'already_decided');
  end if;

  if p_choice = 'find' and not private.location_fresh(p_user_id, v_m.room_id) then
    perform private.raise_error('location_required');
  end if;

  update public.matches
     set a_choice = case when v_is_a then p_choice else a_choice end,
         b_choice = case when v_is_a then b_choice else p_choice end,
         status   = case when p_choice = 'chat' then 'chatting'::public.match_status else status end
   where id = p_match_id
  returning * into v_m;

  if p_choice = 'chat' then
    return jsonb_build_object('settled', v_settled) || private.choice_json(v_m, p_user_id, 'chat', 'chose_chat');
  end if;

  v_other_choice := case when v_is_a then v_m.b_choice else v_m.a_choice end;
  if v_other_choice is null then
    return jsonb_build_object('settled', v_settled) || private.choice_json(v_m, p_user_id, 'waiting', 'other_undecided');
  end if;

  if private.open_checkin(v_m.user_a, v_m.room_id) is null
     or private.open_checkin(v_m.user_b, v_m.room_id) is null then
    update public.matches set status = 'chatting' where id = p_match_id returning * into v_m;
    return jsonb_build_object('settled', v_settled) || private.choice_json(v_m, p_user_id, 'chat', 'not_checked_in');
  end if;

  if not private.location_fresh(v_other, v_m.room_id) then
    return jsonb_build_object('settled', v_settled, 'recheckUserIds', jsonb_build_array(v_other))
           || private.choice_json(v_m, p_user_id, 'waiting', 'other_location_stale');
  end if;

  return jsonb_build_object('settled', v_settled) || private.choice_json(v_m, p_user_id, 'glow', 'both_find');
end;
$$;

-- glow_met (replaced): a glow whose time ran out is reported in settled.
create or replace function public.glow_met(p_user_id uuid, p_match_id uuid)
returns jsonb
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_m       public.matches;
  v_g       public.glow_sessions;
  v_settled jsonb := '[]'::jsonb;
begin
  select * into v_m from public.matches where id = p_match_id for update;
  if not found or p_user_id is null or p_user_id not in (v_m.user_a, v_m.user_b) or v_m.status = 'ended' then
    perform private.raise_error('not_found');
  end if;

  select * into v_g from public.glow_sessions where match_id = p_match_id and status = 'active' for update;
  if not found then
    select * into v_g from public.glow_sessions where match_id = p_match_id order by started_at desc limit 1;
    if not found then
      perform private.raise_error('not_found');
    end if;
    return private.glow_json(v_g, p_user_id) || jsonb_build_object('settled', v_settled);
  end if;

  if v_g.ends_at <= now() then
    update public.glow_sessions set status = 'expired', ended_at = ends_at where id = v_g.id returning * into v_g;
    update public.matches set status = 'chatting' where id = p_match_id and status = 'glowing';
    v_settled := jsonb_build_array(jsonb_build_object(
      'matchId', p_match_id, 'kind', 'glow_expired', 'userIds', jsonb_build_array(v_m.user_a, v_m.user_b)));
    return private.glow_json(v_g, p_user_id) || jsonb_build_object('settled', v_settled);
  end if;

  update public.glow_sessions
     set a_met = a_met or p_user_id = v_m.user_a,
         b_met = b_met or p_user_id = v_m.user_b
   where id = v_g.id
  returning * into v_g;

  if v_g.a_met and v_g.b_met then
    update public.glow_sessions set status = 'met', ended_at = now() where id = v_g.id returning * into v_g;
    update public.matches set status = 'met' where id = p_match_id;
    perform private.log_activity(v_g.room_id, 'glow_met');
  end if;

  return private.glow_json(v_g, p_user_id) || jsonb_build_object('settled', v_settled);
end;
$$;

-------------------------------------------------------------------------------
-- 3. start_glow never raises for a match it can't start
-------------------------------------------------------------------------------

create function private.start_glow_result(
  p_result  text,
  p_reason  text,
  p_match   public.matches,
  p_settled jsonb,
  p_stale   jsonb default null)
returns jsonb
language sql immutable
set search_path = ''
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'result',       p_result,
    'reason',       p_reason,
    'matchId',      p_match.id,
    'status',       p_match.status,
    'userIds',      jsonb_build_array(p_match.user_a, p_match.user_b),
    'staleUserIds', p_stale)) || jsonb_build_object('settled', p_settled);
$$;

-- start_glow (replaced): pick a color, code word and meeting spot, and start the glow, or say why
-- not. It no longer raises glow_not_ready or no_code_word, so a match is never left choosing with
-- both on Find. Returns one of:
--   { result: "started", glow: Glow plus userIds, settled }
--   { result: "chat", reason: "not_checked_in" | "no_code_word" | "already_decided", matchId,
--     status: "chatting" | "met", userIds, settled }
--       The match is chatting now (or already was). Send match.choice to both so the chat opens.
--   { result: "waiting", reason: "location_stale" | "not_both_find", matchId, status: "choosing",
--     userIds, staleUserIds?, settled }
--       Nothing changed. For location_stale, send match.recheck to everyone in staleUserIds.
-- settled lists every glow this call ended by time, this match's or others' in the room: send
-- glow.ended for each. Color, code word and spot rules are as in 0001.
-- Raises not_found (no such match, or it ended) or invalid_input.
create or replace function public.start_glow(p_match_id uuid, p_code_words text[])
returns jsonb
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_m       public.matches;
  v_g       public.glow_sessions;
  v_color   public.glow_color;
  v_word    text;
  v_spot    uuid;
  v_settled jsonb;
  v_stale   jsonb;
begin
  if p_match_id is null or p_code_words is null or cardinality(p_code_words) = 0 then
    perform private.raise_error('invalid_input');
  end if;

  select * into v_m from public.matches where id = p_match_id for update;
  if not found or v_m.status = 'ended' then
    perform private.raise_error('not_found');
  end if;
  v_settled := private.settle_match_events(p_match_id);
  select * into v_m from public.matches where id = p_match_id;

  if v_m.status = 'glowing' then
    select * into v_g from public.glow_sessions where match_id = p_match_id and status = 'active';
    if found then
      return jsonb_build_object('result', 'started', 'glow', private.glow_json(v_g), 'settled', v_settled);
    end if;
  end if;

  if v_m.status <> 'choosing' then
    return private.start_glow_result('chat', 'already_decided', v_m, v_settled);
  end if;

  if v_m.a_choice is distinct from 'find' or v_m.b_choice is distinct from 'find' then
    return private.start_glow_result('waiting', 'not_both_find', v_m, v_settled);
  end if;

  if private.open_checkin(v_m.user_a, v_m.room_id) is null
     or private.open_checkin(v_m.user_b, v_m.room_id) is null then
    update public.matches set status = 'chatting' where id = p_match_id returning * into v_m;
    return private.start_glow_result('chat', 'not_checked_in', v_m, v_settled);
  end if;

  select coalesce(jsonb_agg(u), '[]'::jsonb) into v_stale
    from unnest(array[v_m.user_a, v_m.user_b]) u
   where not private.location_fresh(u, v_m.room_id);
  if jsonb_array_length(v_stale) > 0 then
    return private.start_glow_result('waiting', 'location_stale', v_m, v_settled, v_stale);
  end if;

  -- One allocation at a time per room.
  perform pg_advisory_xact_lock(private.lock_key('glow', v_m.room_id));
  v_settled := v_settled || private.expire_glows(v_m.room_id);

  select c into v_color
    from unnest(enum_range(null::public.glow_color)) c
   order by (select count(*) from public.glow_sessions g
              where g.room_id = v_m.room_id and g.status = 'active' and g.color = c),
            random()
   limit 1;

  select w into v_word
    from (select distinct lower(btrim(x)) as w from unnest(p_code_words) x) words
   where w ~ '^[a-z]{2,16}$'
     and not exists (select 1 from public.glow_sessions g
                      where g.room_id = v_m.room_id and g.status = 'active'
                        and g.color = v_color and g.code_word = w)
   order by (select count(*) from public.glow_sessions g
              where g.room_id = v_m.room_id and g.status = 'active' and g.code_word = w),
            random()
   limit 1;
  if v_word is null then
    update public.matches set status = 'chatting' where id = p_match_id returning * into v_m;
    return private.start_glow_result('chat', 'no_code_word', v_m, v_settled);
  end if;

  select s.id into v_spot
    from public.meeting_spots s
   where s.room_id = v_m.room_id
   order by (select count(*) from public.glow_sessions g where g.spot_id = s.id and g.status = 'active'),
            random()
   limit 1;

  insert into public.glow_sessions (match_id, room_id, color, code_word, spot_id, ends_at)
  values (p_match_id, v_m.room_id, v_color, v_word, v_spot, now() + private.const_interval('GLOW_TTL'))
  returning * into v_g;

  update public.matches set status = 'glowing' where id = p_match_id;
  perform private.log_activity(v_m.room_id, 'glow_started');

  return jsonb_build_object('result', 'started', 'glow', private.glow_json(v_g), 'settled', v_settled);
end;
$$;

-------------------------------------------------------------------------------
-- 4. create_checkin needs a passed join location check
-------------------------------------------------------------------------------

-- create_checkin (replaced): also requires a location_checks row (purpose join, result pass or
-- demo_skip) for this person and room from the last JOIN_TICKET_TTL, written by the join route.
-- A QR code or room code alone can never make a card. Raises location_required otherwise.
-- It also records the room day in room_days.
create or replace function public.create_checkin(
  p_user_id    uuid,
  p_room_id    uuid,
  p_checkin_id uuid,
  p_card_path  text,
  p_tags       jsonb)
returns jsonb
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_room     public.rooms;
  v_profile  public.profiles;
  v_row      public.checkins;
  v_replaced text[];
  v_top      public.top_color;
  v_length   public.hair_length;
  v_color    public.hair_color;
  v_extras   public.card_extra[];
begin
  if p_user_id is null or p_room_id is null or p_checkin_id is null
     or p_tags is null or jsonb_typeof(p_tags) <> 'object'
     or p_card_path is distinct from p_room_id::text || '/' || p_checkin_id::text || '.jpg' then
    perform private.raise_error('invalid_input');
  end if;

  begin
    v_top    := (p_tags ->> 'topColor')::public.top_color;
    v_length := (p_tags ->> 'hairLength')::public.hair_length;
    v_color  := (p_tags ->> 'hairColor')::public.hair_color;
    v_extras := coalesce(private.jsonb_text_array(p_tags -> 'extras')::public.card_extra[], '{}');
  exception when others then
    perform private.raise_error('invalid_input');
  end;
  if v_top is null then
    perform private.raise_error('invalid_input');
  end if;

  select * into v_room from public.rooms where id = p_room_id;
  if not found then
    perform private.raise_error('not_found');
  end if;
  if v_room.status <> 'live' or now() < v_room.starts_at or now() >= v_room.ends_at then
    perform private.raise_error('room_not_live');
  end if;

  select * into v_profile from public.profiles where id = p_user_id;
  if not found or v_profile.banned_at is not null then
    perform private.raise_error('not_found');
  end if;
  if v_profile.onboarding_step <> 'complete' then
    perform private.raise_error('onboarding_incomplete');
  end if;

  -- A passed (or demo-skipped) join check for this room within JOIN_TICKET_TTL.
  if not exists (
    select 1 from public.location_checks l
     where l.user_id = p_user_id
       and l.room_id = p_room_id
       and l.purpose = 'join'
       and l.result in ('pass', 'demo_skip')
       and l.created_at > now() - private.const_interval('JOIN_TICKET_TTL')) then
    perform private.raise_error('location_required');
  end if;

  perform pg_advisory_xact_lock(private.lock_key('checkin', p_user_id, p_room_id));

  -- A retried request with the same card ID gets the same answer.
  select * into v_row from public.checkins where id = p_checkin_id;
  if found then
    if v_row.user_id = p_user_id and v_row.room_id = p_room_id and v_row.left_at is null then
      return jsonb_build_object('checkin', private.checkin_json(v_row), 'replacedCardPaths', '[]'::jsonb);
    end if;
    perform private.raise_error('invalid_input');
  end if;

  with closed as (
    update public.checkins
       set left_at = now()
     where user_id = p_user_id and room_id = p_room_id and left_at is null
    returning card_path
  )
  select coalesce(array_agg(card_path), '{}') into v_replaced from closed;

  insert into public.checkins (id, room_id, user_id, card_path, top_color, hair_length, hair_color, extras, expires_at)
  values (p_checkin_id, p_room_id, p_user_id, p_card_path, v_top, v_length, v_color, v_extras,
          least(now() + private.const_interval('CHECKIN_TTL'), v_room.ends_at))
  returning * into v_row;

  perform private.log_activity(p_room_id, 'checkin');
  insert into public.room_days (user_id, room_id, day)
  values (p_user_id, p_room_id, private.room_day(p_room_id))
  on conflict do nothing;

  return jsonb_build_object('checkin', private.checkin_json(v_row), 'replacedCardPaths', to_jsonb(v_replaced));
end;
$$;

-------------------------------------------------------------------------------
-- 8 and 9. Taps counted per day; the deck after purge
-------------------------------------------------------------------------------

-- get_deck (replaced): 404 only when the room doesn't exist, or the viewer has no check-in there
-- and hasn't checked in there today. After purge deletes an expired check-in, the same day still
-- answers emptyReason checkin_ended.
create or replace function public.get_deck(
  p_viewer_id uuid,
  p_room_id   uuid,
  p_filters   jsonb default '{}'::jsonb,
  p_limit     integer default null,
  p_offset    integer default 0)
returns jsonb
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_page_size     integer := private.const('DECK_PAGE_SIZE')::integer;
  v_cap           integer := private.const('CARD_VIEWS_PER_ROOM_PER_DAY')::integer;
  v_filters       jsonb := coalesce(p_filters, '{}'::jsonb);
  v_limit         integer;
  v_offset        integer;
  f_gender        public.gender[];
  f_top           public.top_color[];
  f_hair_length   public.hair_length[];
  f_hair_color    public.hair_color[];
  f_extras        public.card_extra[];
  v_day           date;
  v_viewed_today  integer;
  v_budget        integer;
  v_eligible      integer;
  v_filtered      integer;
  v_viewable      integer;
  v_cards         jsonb;
  v_new_ids       uuid[];
  v_new           integer;
  v_paused        boolean;
  v_empty         text;
begin
  if p_viewer_id is null or p_room_id is null or jsonb_typeof(v_filters) <> 'object' then
    perform private.raise_error('invalid_input');
  end if;
  v_limit  := least(greatest(coalesce(p_limit, v_page_size), 1), v_page_size);
  v_offset := greatest(coalesce(p_offset, 0), 0);

  begin
    f_gender      := private.jsonb_text_array(v_filters -> 'gender')::public.gender[];
    f_top         := private.jsonb_text_array(v_filters -> 'topColor')::public.top_color[];
    f_hair_length := private.jsonb_text_array(v_filters -> 'hairLength')::public.hair_length[];
    f_hair_color  := private.jsonb_text_array(v_filters -> 'hairColor')::public.hair_color[];
    f_extras      := private.jsonb_text_array(v_filters -> 'extras')::public.card_extra[];
  exception when others then
    perform private.raise_error('invalid_input');
  end;

  if not exists (select 1 from public.rooms r where r.id = p_room_id)
     or (not exists (select 1 from public.checkins c where c.user_id = p_viewer_id and c.room_id = p_room_id)
         and not exists (select 1 from public.room_days d
                          where d.user_id = p_viewer_id and d.room_id = p_room_id
                            and d.day = private.room_day(p_room_id))) then
    perform private.raise_error('not_found');
  end if;

  -- One deck request at a time per viewer and room, so parallel requests can't beat the cap.
  perform pg_advisory_xact_lock(private.lock_key('deck', p_viewer_id, p_room_id));

  v_day := private.room_day(p_room_id);
  select count(*) into v_viewed_today
    from public.card_views
   where viewer_id = p_viewer_id and room_id = p_room_id and view_day = v_day;
  v_budget := greatest(v_cap - v_viewed_today, 0);

  if private.active_checkin(p_viewer_id, p_room_id) is null then
    select p.paused into v_paused from public.profiles p where p.id = p_viewer_id;
    return jsonb_strip_nulls(jsonb_build_object(
      'cards', '[]'::jsonb,
      'viewsLeftToday', v_budget,
      'hasMore', false,
      'nextOffset', null,
      'emptyReason', case when v_paused and private.open_checkin(p_viewer_id, p_room_id) is not null
                          then 'paused' else 'checkin_ended' end));
  end if;

  -- Remember the viewer was checked in here today, for after purge deletes the check-in.
  insert into public.room_days (user_id, room_id, day) values (p_viewer_id, p_room_id, v_day)
  on conflict do nothing;

  with eligible as (
    select c.id, c.user_id, c.card_path, c.top_color, c.hair_length, c.hair_color, c.extras,
           o.gender as other_gender,
           md5(p_viewer_id::text || ':' || p_room_id::text || ':' || v_day::text || ':' || c.id::text) as sort_key
      from public.checkins c
      join public.profiles o on o.id = c.user_id
     where c.room_id = p_room_id
       and c.user_id <> p_viewer_id
       and c.left_at is null
       and c.expires_at > now()
       and private.active_checkin(c.user_id, p_room_id) = c.id
       and private.pair_eligible(p_viewer_id, c.user_id)
  ), filtered as (
    select e.*,
           exists (select 1 from public.card_views v
                    where v.viewer_id = p_viewer_id and v.checkin_id = e.id and v.view_day = v_day) as seen
      from eligible e
     where (f_gender      is null or e.other_gender = any (f_gender))
       and (f_top         is null or e.top_color    = any (f_top))
       and (f_hair_length is null or e.hair_length  = any (f_hair_length))
       and (f_hair_color  is null or e.hair_color   = any (f_hair_color))
       and (f_extras      is null or e.extras @> f_extras)
  ), ranked as (
    select f.*,
           count(*) filter (where not f.seen)
             over (order by f.sort_key rows between unbounded preceding and current row) as unseen_rank
      from filtered f
  ), viewable as (
    -- Cards already seen today are free. New cards only up to today's remaining budget.
    select r.*, row_number() over (order by r.sort_key) as vpos
      from ranked r
     where r.seen or r.unseen_rank <= v_budget
  ), page as (
    select * from viewable where vpos > v_offset and vpos <= v_offset + v_limit
  )
  select
    (select count(*) from eligible),
    (select count(*) from filtered),
    (select count(*) from viewable),
    coalesce((select jsonb_agg(jsonb_build_object(
                'id',         p.id,
                'cardPath',   p.card_path,
                'tags',       jsonb_build_object('topColor', p.top_color, 'hairLength', p.hair_length,
                                                 'hairColor', p.hair_color, 'extras', to_jsonb(p.extras)),
                'tappedByMe', exists (select 1 from public.taps t
                                       where t.room_id = p_room_id and t.from_user = p_viewer_id
                                         and t.to_user = p.user_id and t.expires_at > now()
                                         and t.match_id is null))
              order by p.vpos)
              from page p), '[]'::jsonb),
    coalesce((select array_agg(p.id) from page p where not p.seen), '{}')
  into v_eligible, v_filtered, v_viewable, v_cards, v_new_ids;

  insert into public.card_views (viewer_id, checkin_id, room_id, view_day)
  select p_viewer_id, x, p_room_id, v_day from unnest(v_new_ids) x
  on conflict do nothing;
  get diagnostics v_new = row_count;
  perform private.log_activity(p_room_id, 'card_view', v_new);

  v_empty := case
    when jsonb_array_length(v_cards) > 0 then null
    when v_eligible = 0 then 'quiet'
    when v_filtered = 0 then 'no_match'
    when v_viewable < v_filtered then 'view_limit_reached'
    else null
  end;

  return jsonb_strip_nulls(jsonb_build_object(
    'cards',          v_cards,
    'viewsLeftToday', v_budget - v_new,
    'hasMore',        v_viewable > v_offset + v_limit,
    'nextOffset',     case when v_viewable > v_offset + v_limit then v_offset + v_limit end,
    'emptyReason',    v_empty));
end;
$$;

-- record_tap (replaced): today's taps come from room_days, and a tap writes no activity row (P5).
create or replace function public.record_tap(p_viewer_id uuid, p_room_id uuid, p_checkin_id uuid)
returns jsonb
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_cap      integer := private.const('TAPS_PER_ROOM_PER_DAY')::integer;
  v_target   uuid;
  v_used     integer;
  v_existing public.taps;
  v_my_tap   uuid;
  v_back_tap uuid;
  v_match_id uuid;
begin
  if p_viewer_id is null or p_room_id is null or p_checkin_id is null then
    perform private.raise_error('invalid_input');
  end if;

  -- One tap at a time per viewer and room, so parallel requests can't beat the cap.
  perform pg_advisory_xact_lock(private.lock_key('taps', p_viewer_id, p_room_id));

  select c.user_id into v_target
    from public.checkins c
   where c.id = p_checkin_id and c.room_id = p_room_id;
  if v_target is null or v_target = p_viewer_id then
    perform private.raise_error('not_found');
  end if;

  -- One decision at a time per pair. Every statement after this sees the other person's
  -- committed tap, so exactly one of two simultaneous taps makes the match.
  perform pg_advisory_xact_lock(private.pair_lock_key(p_viewer_id, v_target));

  if not private.card_in_deck(p_viewer_id, p_checkin_id)
     or not private.card_was_shown(p_viewer_id, p_checkin_id) then
    perform private.raise_error('not_found');
  end if;

  select coalesce((select d.taps_used from public.room_days d
                    where d.user_id = p_viewer_id and d.room_id = p_room_id
                      and d.day = private.room_day(p_room_id)), 0)
    into v_used;

  select * into v_existing
    from public.taps
   where room_id = p_room_id and from_user = p_viewer_id and to_user = v_target
     for update;

  if found and v_existing.expires_at > now() and v_existing.match_id is null then
    v_my_tap := v_existing.id;
  else
    if v_used >= v_cap then
      perform private.raise_error('tap_limit_reached');
    end if;
    if v_existing.id is not null then
      update public.taps
         set created_at = now(), expires_at = now() + private.const_interval('TAP_TTL'), match_id = null
       where id = v_existing.id
      returning id into v_my_tap;
    else
      insert into public.taps (room_id, from_user, to_user, expires_at)
      values (p_room_id, p_viewer_id, v_target, now() + private.const_interval('TAP_TTL'))
      returning id into v_my_tap;
    end if;
    v_used := v_used + 1;
    -- Counted apart from the tap row, so a re-tap after an unmatch uses a tap like any other.
    -- No activity row: tap counts are never shown, even to admins (P5).
    insert into public.room_days (user_id, room_id, day, taps_used)
    values (p_viewer_id, p_room_id, private.room_day(p_room_id), 1)
    on conflict (user_id, room_id, day) do update set taps_used = public.room_days.taps_used + 1;
  end if;

  select t.id into v_back_tap
    from public.taps t
   where t.room_id = p_room_id
     and t.from_user = v_target
     and t.to_user = p_viewer_id
     and t.expires_at > now()
     and t.match_id is null
     for update;

  if v_back_tap is not null then
    insert into public.matches (room_id, user_a, user_b, choice_deadline)
    values (p_room_id, least(p_viewer_id, v_target), greatest(p_viewer_id, v_target),
            now() + private.const_interval('CHOICE_WINDOW'))
    returning id into v_match_id;
    update public.taps set match_id = v_match_id where id in (v_my_tap, v_back_tap);
    perform private.log_activity(p_room_id, 'match');
  end if;

  return jsonb_strip_nulls(jsonb_build_object(
    'result',        case when v_match_id is null then 'sent' else 'mutual' end,
    'tapsLeftToday', greatest(v_cap - v_used, 0),
    'matchId',       v_match_id));
end;
$$;

-- get_room_state (replaced): taps left today come from room_days.
create or replace function public.get_room_state(p_user_id uuid, p_room_id uuid)
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_room    public.rooms;
  v_checkin public.checkins;
  v_taps    integer;
  v_views   integer;
begin
  select * into v_room from public.rooms where id = p_room_id;
  if not found or p_user_id is null then
    perform private.raise_error('not_found');
  end if;

  select * into v_checkin from public.checkins c
   where c.user_id = p_user_id and c.room_id = p_room_id and c.left_at is null and c.expires_at > now();

  select coalesce((select d.taps_used from public.room_days d
                    where d.user_id = p_user_id and d.room_id = p_room_id
                      and d.day = private.room_day(p_room_id)), 0)
    into v_taps;
  select count(*) into v_views from public.card_views v
   where v.viewer_id = p_user_id and v.room_id = p_room_id and v.view_day = private.room_day(p_room_id);

  return jsonb_strip_nulls(jsonb_build_object(
    'room', jsonb_build_object('id', v_room.id, 'slug', v_room.slug, 'name', v_room.name, 'status', v_room.status,
                               'startsAt', private.iso(v_room.starts_at), 'endsAt', private.iso(v_room.ends_at)),
    'checkin', case when v_checkin.id is null then null else private.checkin_json(v_checkin) end,
    'tapsLeftToday', greatest(private.const('TAPS_PER_ROOM_PER_DAY')::integer - v_taps, 0),
    'viewsLeftToday', greatest(private.const('CARD_VIEWS_PER_ROOM_PER_DAY')::integer - v_views, 0)));
end;
$$;

-- purge_expired (replaced): also purges room_days older than CARD_VIEW_RETENTION.
create or replace function public.purge_expired()
returns jsonb
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_ended_glows jsonb;
  v_timeouts    jsonb;
  v_expiring    jsonb;
  v_paths       text[];
  v_checkins    integer;
  v_taps        integer;
  v_glows       integer;
  v_views       integer;
  v_checks      integer;
  v_days        integer;
begin
  v_ended_glows := private.expire_glows(null);

  with t as (
    update public.matches
       set status = 'chatting'
     where status = 'choosing' and choice_deadline <= now()
    returning id, user_a, user_b
  )
  select coalesce(jsonb_agg(jsonb_build_object('matchId', id, 'userIds', jsonb_build_array(user_a, user_b))),
                  '[]'::jsonb)
    into v_timeouts from t;

  with w as (
    update public.checkins
       set expiry_warned_at = now()
     where left_at is null
       and expiry_warned_at is null
       and expires_at > now()
       and expires_at <= now() + private.const_interval('CHECKIN_EXPIRY_WARNING')
    returning user_id, room_id, id
  )
  select coalesce(jsonb_agg(jsonb_build_object('userId', user_id, 'roomId', room_id, 'checkinId', id)),
                  '[]'::jsonb)
    into v_expiring from w;

  with d as (
    delete from public.checkins
     where left_at is not null or expires_at <= now()
    returning card_path
  )
  select coalesce(array_agg(card_path), '{}'), count(*) into v_paths, v_checkins from d;

  delete from public.taps where expires_at <= now();
  get diagnostics v_taps = row_count;

  delete from public.glow_sessions
   where status <> 'active'
     and coalesce(ended_at, ends_at) <= now() - private.const_interval('GLOW_ENDED_RETENTION');
  get diagnostics v_glows = row_count;

  delete from public.card_views where viewed_at <= now() - private.const_interval('CARD_VIEW_RETENTION');
  get diagnostics v_views = row_count;

  delete from public.location_checks where created_at <= now() - private.const_interval('LOCATION_CHECK_RETENTION');
  get diagnostics v_checks = row_count;

  delete from public.room_days where day < (now() - private.const_interval('CARD_VIEW_RETENTION'))::date;
  get diagnostics v_days = row_count;

  return jsonb_build_object(
    'cardPaths',        to_jsonb(v_paths),
    'expiringCheckins', v_expiring,
    'endedGlows',       v_ended_glows,
    'choiceTimeouts',   v_timeouts,
    'deleted',          jsonb_build_object('checkins', v_checkins, 'taps', v_taps, 'glowSessions', v_glows,
                                           'cardViews', v_views, 'locationChecks', v_checks,
                                           'roomDays', v_days));
end;
$$;

-------------------------------------------------------------------------------
-- 5. complete_onboarding
-------------------------------------------------------------------------------

-- complete_onboarding: finish onboarding once the profile is filled in and at least
-- PROFILE_PHOTOS_MIN photos are approved. Notifications are optional, so declining push never
-- blocks anyone. Photos held for review (possibly under 18) don't count. The profiles trigger
-- already refuses under-18 birthdates (P10).
-- Returns { onboardingStep: "complete" }. Raises not_found (no profile, or banned) or
-- onboarding_incomplete.
create function public.complete_onboarding(p_user_id uuid)
returns jsonb
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_p public.profiles;
begin
  select * into v_p from public.profiles where id = p_user_id for update;
  if not found or v_p.banned_at is not null then
    perform private.raise_error('not_found');
  end if;
  if v_p.onboarding_step = 'complete' then
    return jsonb_build_object('onboardingStep', 'complete');
  end if;
  if v_p.first_name is null or v_p.birthdate is null or v_p.gender is null or cardinality(v_p.show_me) = 0
     or (select count(*) from public.profile_photos pp
          where pp.user_id = p_user_id and pp.moderation_status = 'approved')
        < private.const('PROFILE_PHOTOS_MIN') then
    perform private.raise_error('onboarding_incomplete');
  end if;
  update public.profiles set onboarding_step = 'complete' where id = p_user_id;
  return jsonb_build_object('onboardingStep', 'complete');
end;
$$;

-------------------------------------------------------------------------------
-- Grants for what this migration added (the default privileges above cover them too)
-------------------------------------------------------------------------------

revoke all on function private.settle_match_events(uuid) from public, anon, authenticated;
revoke all on function private.start_glow_result(text, text, public.matches, jsonb, jsonb) from public, anon, authenticated;
revoke all on function public.complete_onboarding(uuid) from public, anon, authenticated;
grant execute on function private.settle_match_events(uuid) to service_role;
grant execute on function private.start_glow_result(text, text, public.matches, jsonb, jsonb) to service_role;
grant execute on function public.complete_onboarding(uuid) to service_role;
