-- 0004_b4_deck_set_based.sql · B4 · The deck, set-based
--
-- Why: with 300 people checked in, get_deck spent about 25 ms per call, three quarters of it
-- calling private.active_checkin (and through it private.open_checkin) once per candidate,
-- 300 times, plus private.pair_eligible 300 times (pg_stat_user_functions, see the PR). Under
-- 50 concurrent deck requests that put p95 over 300 ms.
--
-- What: every deck rule from 0001's helpers is now written once, as three views, and both the
-- per-person helpers (used by record_tap, card_visible_to, Realtime and glow) and get_deck read
-- those same views. Postgres inlines a view into each query, so the helpers still do a few
-- index lookups for one card, and get_deck does one set-based join for the whole room:
--
--   private.open_checkins  not left, not expired, in a room that is live right now
--   private.active_cards   open, visible, and the person isn't paused, banned or onboarding
--   private.eligible_pairs show me both ways, no block either way, no active match
--
-- Nothing about who appears changes. A2's pgTAP suite (030_deck, 040_taps, 090_checkpoint1)
-- and B4's integration tests check the rules; B4's deck-rules test also checks that the deck
-- and card_visible_to agree on every card. get_deck is 0002's, with only the candidate query
-- (and the "seen today" lookup) rewritten.
--
-- The views read only server tables and are closed to clients like everything else (D28).
-- security_invoker means a view never grants more than its caller already has.

-------------------------------------------------------------------------------
-- The rules, once
-------------------------------------------------------------------------------

create view private.open_checkins with (security_invoker = true) as
select c.*
  from public.checkins c
  join public.rooms r on r.id = c.room_id
 where c.left_at is null
   and c.expires_at > now()
   and r.status = 'live'
   and r.starts_at <= now()
   and r.ends_at > now();

create view private.active_cards with (security_invoker = true) as
select o.*, p.gender
  from private.open_checkins o
  join public.profiles p on p.id = o.user_id
 where o.visible
   and not p.paused
   and p.banned_at is null
   and p.onboarding_step = 'complete';

-- Two NOT EXISTS for the two block directions (rather than one with OR), so the planner can
-- turn each into an anti-join when get_deck asks about a whole room at once.
create view private.eligible_pairs with (security_invoker = true) as
select v.id as viewer_id, o.id as other_id
  from public.profiles v
  join public.profiles o
    on o.id <> v.id
   and o.gender = any (v.show_me)
   and v.gender = any (o.show_me)
 where not exists (select 1 from public.blocks b where b.blocker_id = v.id and b.blocked_id = o.id)
   and not exists (select 1 from public.blocks b where b.blocker_id = o.id and b.blocked_id = v.id)
   and not exists (select 1 from public.matches m
                    where m.user_a = least(v.id, o.id)
                      and m.user_b = greatest(v.id, o.id)
                      and m.status <> 'ended');

revoke all on private.open_checkins, private.active_cards, private.eligible_pairs
  from public, anon, authenticated;
grant select on private.open_checkins, private.active_cards, private.eligible_pairs to service_role;

-------------------------------------------------------------------------------
-- 0001's helpers, now reading the views. Same names, arguments and answers.
-------------------------------------------------------------------------------

create or replace function private.open_checkin(p_user_id uuid, p_room_id uuid)
returns uuid
language sql stable
set search_path = ''
as $$
  select o.id from private.open_checkins o
   where o.user_id = p_user_id and o.room_id = p_room_id
   limit 1;
$$;

create or replace function private.active_checkin(p_user_id uuid, p_room_id uuid)
returns uuid
language sql stable
set search_path = ''
as $$
  select a.id from private.active_cards a
   where a.user_id = p_user_id and a.room_id = p_room_id
   limit 1;
$$;

create or replace function private.pair_eligible(p_viewer_id uuid, p_other_id uuid)
returns boolean
language sql stable
set search_path = ''
as $$
  select exists (select 1 from private.eligible_pairs e
                  where e.viewer_id = p_viewer_id and e.other_id = p_other_id);
$$;

-------------------------------------------------------------------------------
-- get_deck (replaced): 0002's function, with the candidates found in one set-based query.
-------------------------------------------------------------------------------

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
    -- Deck rules 1 to 4 for the whole room at once: the same views the helpers read.
    select c.id, c.user_id, c.card_path, c.top_color, c.hair_length, c.hair_color, c.extras,
           c.gender as other_gender,
           md5(p_viewer_id::text || ':' || p_room_id::text || ':' || v_day::text || ':' || c.id::text) as sort_key
      from private.active_cards c
      join private.eligible_pairs e on e.other_id = c.user_id
     where c.room_id = p_room_id
       and c.user_id <> p_viewer_id
       and e.viewer_id = p_viewer_id
  ), filtered as (
    select e.*,
           e.id in (select v.checkin_id from public.card_views v
                     where v.viewer_id = p_viewer_id and v.room_id = p_room_id and v.view_day = v_day) as seen
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
