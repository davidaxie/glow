-- 0101_x1_blind.sql · X1 · Blind mode (docs/briefs/blind-mode.md)
--
-- Double Blind as a second mode inside Glow, on the same accounts, profiles, photos and blocks.
-- Ported from the Double Blind repo's supabase/migrations (0001, 0110, 0120, 0130, 0140, 0150,
-- 0220, 0221), with every table and function prefixed blind_ and these changes:
--
--   * Opt in: only blind_members appear in a Blind deck or can swipe, drop or chat.
--   * Profiles are Glow's: first_name, birthdate, gender and show_me (fit both ways), paused and
--     banned_at exclude, onboarding must be complete. A card photo is the member's first
--     approved profile_photos row (lowest position). Members without one are in nobody's deck.
--   * Card IDs are opaque and per viewer (blind_cards): the app never sees a Glow user ID, not
--     even on a Blind card. Swipes and guesses resolve through blind_cards.
--   * Blocks are Glow's public.blocks, both ways. A block anywhere (Rooms or Blind) closes every
--     Blind chat between the two (trigger below), and a Blind block is a Glow block
--     (private.block_pair, which also ends any Glow match between them).
--   * Reports go to public.reports with context 'blind_chat' (0100) and also block, as in Glow.
--
-- Blindness rules (Double Blind B1 to B12) hold here too: before both tap Reveal, nothing about a
-- chat partner leaves these functions except the chat ID, the caller's codename for them and
-- "they left". Every function is security definer with search_path = '' and service role only.

-------------------------------------------------------------------------------
-- Constants (mirror contracts/constants.json)
-------------------------------------------------------------------------------

insert into private.constants (name, value, unit) values
  ('BLIND_RIGHT_SWIPES_PER_DAY',  20,  'count'),
  ('BLIND_DROP_MIN_RIGHT_SWIPES', 5,   'count'),
  ('BLIND_MAX_OPEN_CHATS',        5,   'count'),
  ('BLIND_DECK_PAGE_MAX',         20,  'count'),
  ('BLIND_REPORT_MAX_CHARS',      500, 'characters'),
  ('BLIND_DROP_REPLAY_WINDOW',    300, 'seconds')
on conflict (name) do update set value = excluded.value, unit = excluded.unit;

-------------------------------------------------------------------------------
-- Tables
-------------------------------------------------------------------------------

-- Opt in. paused is Blind-only (Glow's profiles.paused hides someone everywhere).
create table public.blind_members (
  user_id   uuid primary key references public.profiles (id) on delete cascade,
  joined_at timestamptz not null default now(),
  paused    boolean not null default false
);

-- Opaque card IDs: what viewer_id's app calls target_id. One per pair and viewer, so a deck card
-- and the same person's Guess Who card share an ID (both only ever seen by viewer_id).
create table public.blind_cards (
  viewer_id  uuid not null references public.profiles (id) on delete cascade,
  target_id  uuid not null references public.profiles (id) on delete cascade,
  card_id    uuid not null default gen_random_uuid() unique,
  created_at timestamptz not null default now(),
  primary key (viewer_id, target_id),
  constraint blind_cards_not_self check (viewer_id <> target_id)
);
create index blind_cards_target on public.blind_cards (target_id);

create table public.blind_swipes (
  swiper_id  uuid not null references public.profiles (id) on delete cascade,
  target_id  uuid not null references public.profiles (id) on delete cascade,
  kind       text not null check (kind in ('pass', 'like', 'love')),
  created_at timestamptz not null default now(),
  primary key (swiper_id, target_id),
  constraint blind_swipes_not_self check (swiper_id <> target_id)
);
-- Right swipes by this person today (the daily cap), and who right-swiped me (mutual lookup).
create index blind_swipes_right_by_day on public.blind_swipes (swiper_id, created_at) where kind <> 'pass';
create index blind_swipes_target on public.blind_swipes (target_id, swiper_id) where kind <> 'pass';

create table public.blind_codenames (
  name text primary key check (name ~ '^[A-Z][a-z]+$')
);

create table public.blind_chats (
  id          uuid primary key default gen_random_uuid(),
  user_a      uuid not null references public.profiles (id) on delete cascade,
  user_b      uuid not null references public.profiles (id) on delete cascade,
  -- codename_a = what user_a calls the OTHER person; codename_b = what user_b calls the other.
  codename_a  text not null references public.blind_codenames (name),
  codename_b  text not null references public.blind_codenames (name),
  status      text not null default 'open' check (status in ('open', 'left', 'revealed')),
  reveal_a    boolean not null default false,
  reveal_b    boolean not null default false,
  left_by     uuid references public.profiles (id) on delete set null,
  guess_a     uuid references public.profiles (id) on delete set null,
  guess_b     uuid references public.profiles (id) on delete set null,
  -- Message-ID read cursors, for unread.
  read_a      bigint not null default 0,
  read_b      bigint not null default 0,
  opened_at   timestamptz not null default now(),
  revealed_at timestamptz,
  constraint blind_chats_ordered_pair check (user_a < user_b),
  constraint blind_chats_codenames_differ check (codename_a <> codename_b),
  constraint blind_chats_one_per_pair unique (user_a, user_b)
);
create index blind_chats_user_a on public.blind_chats (user_a, status);
create index blind_chats_user_b on public.blind_chats (user_b, status);
create index blind_chats_left_by on public.blind_chats (left_by);
create index blind_chats_guess_a on public.blind_chats (guess_a);
create index blind_chats_guess_b on public.blind_chats (guess_b);
create index blind_chats_codename_a on public.blind_chats (codename_a);
create index blind_chats_codename_b on public.blind_chats (codename_b);

-- A hidden mutual match. chat_id stays null until a drop opens it.
create table public.blind_matches (
  id         uuid primary key default gen_random_uuid(),
  user_a     uuid not null references public.profiles (id) on delete cascade,
  user_b     uuid not null references public.profiles (id) on delete cascade,
  -- Real time, so "oldest first" is strict inside one transaction too.
  created_at timestamptz not null default clock_timestamp(),
  chat_id    uuid unique references public.blind_chats (id) on delete set null,
  constraint blind_matches_ordered_pair check (user_a < user_b),
  constraint blind_matches_one_per_pair unique (user_a, user_b)
);
create index blind_matches_waiting on public.blind_matches (created_at) where chat_id is null;
create index blind_matches_user_b on public.blind_matches (user_b);

-- Codename bookkeeping (B11). 'sees' = a name this person uses for someone else; 'seen' = a
-- name someone else uses for this person. Never the same name twice either way.
create table public.blind_codename_uses (
  user_id  uuid not null references public.profiles (id) on delete cascade,
  codename text not null references public.blind_codenames (name),
  kind     text not null check (kind in ('sees', 'seen')),
  chat_id  uuid not null references public.blind_chats (id) on delete cascade,
  primary key (user_id, codename, kind)
);
create index blind_codename_uses_chat on public.blind_codename_uses (chat_id);
create index blind_codename_uses_codename on public.blind_codename_uses (codename);

-- Messages store a side (a or b), never a sender ID (B12).
create table public.blind_messages (
  id         bigint generated always as identity primary key,
  chat_id    uuid not null references public.blind_chats (id) on delete cascade,
  side       char(1) not null check (side in ('a', 'b')),
  body       text not null,
  created_at timestamptz not null default now(),
  constraint blind_messages_body_length check (
    char_length(btrim(body)) >= 1 and char_length(body) <= private.const('MESSAGE_MAX_CHARS'))
);
create index blind_messages_chat on public.blind_messages (chat_id, id);

create table public.blind_drops (
  id           bigint generated always as identity primary key,
  user_id      uuid not null references public.profiles (id) on delete cascade,
  opened_count integer not null check (opened_count >= 0),
  created_at   timestamptz not null default now()
);
create index blind_drops_user on public.blind_drops (user_id, created_at);

-- First sight of a chat in a drop, per person (Double Blind E3).
create table public.blind_drop_seen (
  user_id uuid not null references public.profiles (id) on delete cascade,
  chat_id uuid not null references public.blind_chats (id) on delete cascade,
  seen_at timestamptz not null default now(),
  primary key (user_id, chat_id)
);
create index blind_drop_seen_chat on public.blind_drop_seen (chat_id);

-- Everyone who left or blocked a chat: it's gone from their list and 404 for them (Double Blind E3).
create table public.blind_chat_exits (
  chat_id    uuid not null references public.blind_chats (id) on delete cascade,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (chat_id, user_id)
);
create index blind_chat_exits_user on public.blind_chat_exits (user_id);

alter table public.blind_members       enable row level security;
alter table public.blind_cards         enable row level security;
alter table public.blind_swipes        enable row level security;
alter table public.blind_codenames     enable row level security;
alter table public.blind_chats         enable row level security;
alter table public.blind_matches       enable row level security;
alter table public.blind_codename_uses enable row level security;
alter table public.blind_messages      enable row level security;
alter table public.blind_drops         enable row level security;
alter table public.blind_drop_seen     enable row level security;
alter table public.blind_chat_exits    enable row level security;

-- Calm animals, weather and plants, no emoji. 90 names.
insert into public.blind_codenames (name)
select unnest(string_to_array(
  'Fox Comet Otter Ember Heron Juniper Willow Falcon Drizzle Harbor Maple Lynx Aurora Badger Breeze '
  'Cedar Cricket Dune Finch Fjord Flint Gale Glacier Hazel Ibis Indigo Jackal Kestrel Lark Lichen '
  'Lotus Magpie Marten Meadow Mistral Monsoon Moth Newt Nimbus Oriole Osprey Panda Pebble Pika '
  'Plover Puma Quail Quartz Raven Reed Robin Sable Sage Sparrow Squall Stoat Sunbeam Swift '
  'Tamarack Tern Thistle Thunder Tundra Vole Wren Yarrow Zephyr Aspen Birch Bison Coyote Dingo '
  'Egret Gecko Heather Ivy Kite Lemming Mallard Ocelot Petrel Sleet Starling Twilight Walrus Cinder',
  ' '));

-------------------------------------------------------------------------------
-- Rule helpers
-------------------------------------------------------------------------------

-- Serializes everything that opens or closes blind chats. Rare, cheap operations.
create function private.blind_lock_drops()
returns void
language sql
set search_path = ''
as $$
  select pg_advisory_xact_lock(private.lock_key('blind_drops', '00000000-0000-0000-0000-000000000000'::uuid));
$$;

create function private.blind_is_member(p_user_id uuid)
returns boolean
language sql stable
set search_path = ''
as $$
  select exists (select 1 from public.blind_members m where m.user_id = p_user_id);
$$;

-- Every Blind function except me and join: not a member is not_found (P11).
create function private.blind_require_member(p_user_id uuid)
returns void
language plpgsql stable
set search_path = ''
as $$
begin
  if p_user_id is null or not private.blind_is_member(p_user_id) then
    perform private.raise_error('not_found');
  end if;
end;
$$;

-- The person's card photo: their first approved profile photo. Null without one.
create function private.blind_photo_path(p_user_id uuid)
returns text
language sql stable
set search_path = ''
as $$
  select pp.path from public.profile_photos pp
   where pp.user_id = p_user_id and pp.moderation_status = 'approved'
   order by pp.position
   limit 1;
$$;

-- Can these two be shown to each other, matched, or get a chat? Symmetric in every rule: both
-- members and not Blind-paused, both Glow profiles complete, not paused, not banned, with an
-- approved photo, gender and show me fit both ways, and no block either way.
create function private.blind_eligible(p_viewer_id uuid, p_target_id uuid)
returns boolean
language sql stable
set search_path = ''
as $$
  select coalesce((
    select p_viewer_id <> p_target_id
       and not vm.paused and not tm.paused
       and v.onboarding_step = 'complete' and t.onboarding_step = 'complete'
       and not v.paused and not t.paused
       and v.banned_at is null and t.banned_at is null
       and t.gender = any (v.show_me)
       and v.gender = any (t.show_me)
       and private.blind_photo_path(p_viewer_id) is not null
       and private.blind_photo_path(p_target_id) is not null
       and not exists (
         select 1 from public.blocks b
          where (b.blocker_id = p_viewer_id and b.blocked_id = p_target_id)
             or (b.blocker_id = p_target_id and b.blocked_id = p_viewer_id))
      from public.blind_members vm, public.blind_members tm, public.profiles v, public.profiles t
     where vm.user_id = p_viewer_id and tm.user_id = p_target_id
       and v.id = p_viewer_id and t.id = p_target_id
  ), false);
$$;

-- The viewer's opaque card ID for target, made on first use.
create function private.blind_card_for(p_viewer_id uuid, p_target_id uuid)
returns uuid
language plpgsql volatile
set search_path = ''
as $$
declare
  v_card uuid;
begin
  insert into public.blind_cards (viewer_id, target_id)
  values (p_viewer_id, p_target_id)
  on conflict (viewer_id, target_id) do nothing;
  select c.card_id into v_card from public.blind_cards c
   where c.viewer_id = p_viewer_id and c.target_id = p_target_id;
  return v_card;
end;
$$;

-- Who a card means, only for the viewer it was made for. Null otherwise.
create function private.blind_card_target(p_viewer_id uuid, p_card_id uuid)
returns uuid
language sql stable
set search_path = ''
as $$
  select c.target_id from public.blind_cards c
   where c.card_id = p_card_id and c.viewer_id = p_viewer_id;
$$;

-- Lifetime right swipes (like or love): the person's pool size.
create function private.blind_right_count(p_user_id uuid)
returns integer
language sql stable
set search_path = ''
as $$
  select count(*)::integer from public.blind_swipes s where s.swiper_id = p_user_id and s.kind <> 'pass';
$$;

-- Right swipes still available today (UTC day).
create function private.blind_right_remaining(p_user_id uuid)
returns integer
language sql stable
set search_path = ''
as $$
  select greatest(
    private.const('BLIND_RIGHT_SWIPES_PER_DAY')::integer - (
      select count(*)::integer from public.blind_swipes s
       where s.swiper_id = p_user_id and s.kind <> 'pass'
         and s.created_at >= (date_trunc('day', now() at time zone 'utc') at time zone 'utc')),
    0);
$$;

create function private.blind_open_chat_count(p_user_id uuid)
returns integer
language sql stable
set search_path = ''
as $$
  select count(*)::integer from public.blind_chats c
   where c.status = 'open' and (c.user_a = p_user_id or c.user_b = p_user_id);
$$;

-- The chat, only for a member of it who hasn't left or blocked it. Null otherwise (404).
create function private.blind_chat_for(p_user_id uuid, p_chat_id uuid)
returns public.blind_chats
language sql stable
set search_path = ''
as $$
  select c.* from public.blind_chats c
   where c.id = p_chat_id and p_user_id in (c.user_a, c.user_b)
     and not exists (select 1 from public.blind_chat_exits e where e.chat_id = c.id and e.user_id = p_user_id);
$$;

-- A codename for "viewer calls subject <name>" that viewer never used for anyone and nobody ever
-- used for subject (B11). Null if the pool is exhausted.
create function private.blind_pick_codename(p_viewer_id uuid, p_subject_id uuid, p_exclude text)
returns text
language sql volatile
set search_path = ''
as $$
  select c.name from public.blind_codenames c
   where c.name is distinct from p_exclude
     and not exists (select 1 from public.blind_codename_uses u
                      where u.user_id = p_viewer_id and u.codename = c.name and u.kind = 'sees')
     and not exists (select 1 from public.blind_codename_uses u
                      where u.user_id = p_subject_id and u.codename = c.name and u.kind = 'seen')
   order by random()
   limit 1;
$$;

-- Open the chat for one waiting match if both people are still eligible and have room under
-- BLIND_MAX_OPEN_CHATS. The caller holds blind_lock_drops(). True if a chat was created.
create function private.blind_open_chat_for_match(p_match_id uuid)
returns boolean
language plpgsql volatile
set search_path = ''
as $$
declare
  m        public.blind_matches;
  v_name_a text;
  v_name_b text;
  v_chat   uuid;
  v_cap    integer := private.const('BLIND_MAX_OPEN_CHATS')::integer;
begin
  select * into m from public.blind_matches where id = p_match_id and chat_id is null for update;
  if not found then return false; end if;
  if not private.blind_eligible(m.user_a, m.user_b) then return false; end if;
  if private.blind_open_chat_count(m.user_a) >= v_cap or private.blind_open_chat_count(m.user_b) >= v_cap then
    return false;
  end if;
  -- An older chat between the two (one of them left it) blocks a second one: unique pair.
  if exists (select 1 from public.blind_chats c where c.user_a = m.user_a and c.user_b = m.user_b) then
    return false;
  end if;

  v_name_a := private.blind_pick_codename(m.user_a, m.user_b, null);
  v_name_b := private.blind_pick_codename(m.user_b, m.user_a, v_name_a);
  if v_name_a is null or v_name_b is null then return false; end if;

  insert into public.blind_chats (user_a, user_b, codename_a, codename_b)
  values (m.user_a, m.user_b, v_name_a, v_name_b)
  returning id into v_chat;

  insert into public.blind_codename_uses (user_id, codename, kind, chat_id) values
    (m.user_a, v_name_a, 'sees', v_chat),
    (m.user_b, v_name_a, 'seen', v_chat),
    (m.user_b, v_name_b, 'sees', v_chat),
    (m.user_a, v_name_b, 'seen', v_chat);

  update public.blind_matches set chat_id = v_chat where id = m.id;
  return true;
end;
$$;

-- Close every Blind chat between two people: status left, and gone for the person who acted.
create function private.blind_close_pair(p_actor_id uuid, p_other_id uuid)
returns void
language plpgsql volatile
set search_path = ''
as $$
declare
  v_chat public.blind_chats;
begin
  for v_chat in
    select * from public.blind_chats c
     where c.user_a = least(p_actor_id, p_other_id) and c.user_b = greatest(p_actor_id, p_other_id)
     for update
  loop
    if v_chat.status <> 'left' then
      update public.blind_chats set status = 'left', left_by = p_actor_id where id = v_chat.id;
    end if;
    insert into public.blind_chat_exits (chat_id, user_id) values (v_chat.id, p_actor_id)
    on conflict do nothing;
  end loop;
end;
$$;

-- A Glow block anywhere (a card, a match, a chat or a Blind chat) closes their Blind chats (P7).
create function private.blind_after_block()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
begin
  perform private.blind_lock_drops();
  perform private.blind_close_pair(new.blocker_id, new.blocked_id);
  return new;
end;
$$;

create trigger glow_blocks_close_blind_chats
  after insert on public.blocks
  for each row execute function private.blind_after_block();

create function private.blind_me_json(p_user_id uuid)
returns jsonb
language sql stable
set search_path = ''
as $$
  select jsonb_build_object(
    'member',         private.blind_is_member(p_user_id),
    'hasPhoto',       private.blind_photo_path(p_user_id) is not null,
    'rightRemaining', private.blind_right_remaining(p_user_id),
    'rightCount',     private.blind_right_count(p_user_id),
    'canDrop',        private.blind_right_count(p_user_id) >= private.const('BLIND_DROP_MIN_RIGHT_SWIPES'));
$$;

-------------------------------------------------------------------------------
-- Database functions. Server only. Errors: SQLSTATE P0001 with message = an error code
-- (not_found, onboarding_incomplete, invalid_input, right_cap_reached, chat_closed).
-------------------------------------------------------------------------------

-- blind_me: { member, hasPhoto, rightRemaining, rightCount, canDrop }. Anyone signed in.
create function public.blind_me(p_user_id uuid)
returns jsonb
language sql stable security definer
set search_path = ''
as $$
  select private.blind_me_json(p_user_id);
$$;

-- blind_join: opt in. Idempotent. Needs a finished Glow profile. Returns blind_me.
create function public.blind_join(p_user_id uuid)
returns jsonb
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_p public.profiles;
begin
  select * into v_p from public.profiles where id = p_user_id;
  if not found or v_p.banned_at is not null then
    perform private.raise_error('not_found');
  end if;
  if v_p.onboarding_step <> 'complete' then
    perform private.raise_error('onboarding_incomplete');
  end if;
  insert into public.blind_members (user_id) values (p_user_id) on conflict (user_id) do nothing;
  return private.blind_me_json(p_user_id);
end;
$$;

-- blind_leave: leave Blind mode. Idempotent. Deletes my Blind swipes (both ways), cards (both
-- ways), matches, chats (their messages and codename bookkeeping cascade) and drops.
create function public.blind_leave(p_user_id uuid)
returns jsonb
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_chats integer;
begin
  if p_user_id is null then
    perform private.raise_error('invalid_input');
  end if;
  perform private.blind_lock_drops();
  delete from public.blind_chats where p_user_id in (user_a, user_b);
  get diagnostics v_chats = row_count;
  delete from public.blind_matches where p_user_id in (user_a, user_b);
  delete from public.blind_swipes where p_user_id in (swiper_id, target_id);
  delete from public.blind_cards where p_user_id in (viewer_id, target_id);
  delete from public.blind_drop_seen where user_id = p_user_id;
  delete from public.blind_drops where user_id = p_user_id;
  delete from public.blind_members where user_id = p_user_id;
  return jsonb_build_object('chatsDeleted', v_chats);
end;
$$;

-- blind_deck: up to p_limit (1..BLIND_DECK_PAGE_MAX, default 10) cards I haven't swiped, in a
-- random order. Returns { cards: [{ id }] }: opaque card IDs only. The route signs each photo.
create function public.blind_deck(p_viewer_id uuid, p_limit integer default 10)
returns jsonb
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_limit integer := greatest(least(coalesce(p_limit, 10), private.const('BLIND_DECK_PAGE_MAX')::integer), 1);
  v_cards jsonb;
begin
  perform private.blind_require_member(p_viewer_id);
  select coalesce(jsonb_agg(jsonb_build_object('id', private.blind_card_for(p_viewer_id, x.id))), '[]'::jsonb)
    into v_cards
    from (select p.id
            from public.blind_members bm
            join public.profiles p on p.id = bm.user_id
           where bm.user_id <> p_viewer_id
             and private.blind_eligible(p_viewer_id, bm.user_id)
             and not exists (select 1 from public.blind_swipes s
                              where s.swiper_id = p_viewer_id and s.target_id = bm.user_id)
           order by random()
           limit v_limit) x;
  return jsonb_build_object('cards', v_cards);
end;
$$;

-- blind_record_swipe: swipe one of my cards. Returns { rightRemaining, rightCount } and NOTHING
-- about matches (B2). Daily cap (B4) raises right_cap_reached. A card that isn't mine is
-- not_found. A swipe on someone no longer eligible is silently ignored and answers the same.
-- Repeating a swipe changes nothing. A pair lock makes two simultaneous mutual swipes create
-- exactly one match.
create function public.blind_record_swipe(p_swiper_id uuid, p_card_id uuid, p_kind text)
returns jsonb
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_target uuid;
  v_a      uuid;
  v_b      uuid;
  v_used   integer;
begin
  if p_swiper_id is null or p_card_id is null or p_kind is null or p_kind not in ('pass', 'like', 'love') then
    perform private.raise_error('invalid_input');
  end if;
  perform private.blind_require_member(p_swiper_id);
  v_target := private.blind_card_target(p_swiper_id, p_card_id);
  if v_target is null then
    perform private.raise_error('not_found');
  end if;

  -- One person's concurrent swipes can't overshoot the cap; two people swiping each other at
  -- once are serialized, so the match row is made exactly once.
  perform pg_advisory_xact_lock(private.lock_key('blind_swiper', p_swiper_id));
  v_a := least(p_swiper_id, v_target);
  v_b := greatest(p_swiper_id, v_target);
  perform pg_advisory_xact_lock(private.lock_key('blind_pair', v_a, v_b));

  if exists (select 1 from public.blind_swipes where swiper_id = p_swiper_id and target_id = v_target) then
    null; -- idempotent
  elsif not private.blind_eligible(p_swiper_id, v_target) then
    null; -- silently ignored
  else
    if p_kind <> 'pass' then
      select count(*) into v_used from public.blind_swipes
       where swiper_id = p_swiper_id and kind <> 'pass'
         and created_at >= (date_trunc('day', now() at time zone 'utc') at time zone 'utc');
      if v_used >= private.const('BLIND_RIGHT_SWIPES_PER_DAY') then
        perform private.raise_error('right_cap_reached');
      end if;
    end if;

    insert into public.blind_swipes (swiper_id, target_id, kind) values (p_swiper_id, v_target, p_kind);

    if p_kind <> 'pass' and exists (
      select 1 from public.blind_swipes
       where swiper_id = v_target and target_id = p_swiper_id and kind <> 'pass') then
      insert into public.blind_matches (user_a, user_b) values (v_a, v_b) on conflict (user_a, user_b) do nothing;
    end if;
  end if;

  return jsonb_build_object(
    'rightRemaining', private.blind_right_remaining(p_swiper_id),
    'rightCount',     private.blind_right_count(p_swiper_id));
end;
$$;

-- blind_pool: { rightCount, rightRemaining, canDrop }.
create function public.blind_pool(p_user_id uuid)
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
begin
  perform private.blind_require_member(p_user_id);
  return jsonb_build_object(
    'rightCount',     private.blind_right_count(p_user_id),
    'rightRemaining', private.blind_right_remaining(p_user_id),
    'canDrop',        private.blind_right_count(p_user_id) >= private.const('BLIND_DROP_MIN_RIGHT_SWIPES'));
end;
$$;

-- blind_pool_cards: my own right swipes as cards, newest first: { cards: [{ id }] }. Deliberately
-- NOT filtered by blocks, pauses or chats: a card vanishing when I block a chat would tell me who
-- the chat partner was (B1, B7). Only people with an approved photo who aren't banned.
create function public.blind_pool_cards(p_user_id uuid, p_limit integer default 100)
returns jsonb
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_cards jsonb;
begin
  perform private.blind_require_member(p_user_id);
  select coalesce(jsonb_agg(jsonb_build_object('id', private.blind_card_for(p_user_id, x.target_id))
                            order by x.created_at desc, x.target_id), '[]'::jsonb)
    into v_cards
    from (select s.target_id, s.created_at
            from public.blind_swipes s
            join public.profiles p on p.id = s.target_id
           where s.swiper_id = p_user_id and s.kind <> 'pass'
             and p.banned_at is null
             and private.blind_photo_path(s.target_id) is not null
           order by s.created_at desc, s.target_id
           limit greatest(least(coalesce(p_limit, 100), 200), 1)) x;
  return jsonb_build_object('cards', v_cards);
end;
$$;

-- blind_card_photo_path: the photo behind one of my cards, for the image route. Null unless the
-- card is mine, I'm a member, and the person is still in my deck (eligible) or in my pool (I
-- right-swiped them; the pool is never filtered, see blind_pool_cards).
create function public.blind_card_photo_path(p_viewer_id uuid, p_card_id uuid)
returns text
language sql stable security definer
set search_path = ''
as $$
  select private.blind_photo_path(c.target_id)
    from public.blind_cards c
    join public.profiles t on t.id = c.target_id
   where c.card_id = p_card_id and c.viewer_id = p_viewer_id
     and private.blind_is_member(p_viewer_id)
     and t.banned_at is null
     and (private.blind_eligible(p_viewer_id, c.target_id)
          or exists (select 1 from public.blind_swipes s
                      where s.swiper_id = p_viewer_id and s.target_id = c.target_id and s.kind <> 'pass'));
$$;

-- blind_run_drop: open my waiting chats, oldest match first, never above BLIND_MAX_OPEN_CHATS for
-- either person. Nothing opens below BLIND_DROP_MIN_RIGHT_SWIPES right swipes (B3). With a cutoff
-- (outside demo mode), only matches made at or before it open (Double Blind F-01: otherwise
-- "swipe, then drop" tells me which swipe was mutual). Returns { opened }.
create function public.blind_run_drop(p_user_id uuid, p_cutoff timestamptz default null)
returns jsonb
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_opened integer := 0;
  v_match  uuid;
  v_cap    integer := private.const('BLIND_MAX_OPEN_CHATS')::integer;
begin
  perform private.blind_require_member(p_user_id);
  perform private.blind_lock_drops();

  if private.blind_right_count(p_user_id) >= private.const('BLIND_DROP_MIN_RIGHT_SWIPES') then
    for v_match in
      select m.id from public.blind_matches m
       where m.chat_id is null and p_user_id in (m.user_a, m.user_b)
         and (p_cutoff is null or m.created_at <= p_cutoff)
       order by m.created_at, m.id
    loop
      exit when private.blind_open_chat_count(p_user_id) >= v_cap;
      if private.blind_open_chat_for_match(v_match) then
        v_opened := v_opened + 1;
      end if;
    end loop;
  end if;

  if v_opened > 0 then
    insert into public.blind_drops (user_id, opened_count) values (p_user_id, v_opened);
  end if;
  return jsonb_build_object('opened', v_opened);
end;
$$;

-- blind_run_drop_all: the nightly drop and the admin button. Every waiting match where at least
-- one person has BLIND_DROP_MIN_RIGHT_SWIPES right swipes, oldest first across everyone.
-- Returns { opened } (chats opened in total).
create function public.blind_run_drop_all()
returns jsonb
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_match    record;
  v_total    integer := 0;
  v_per_user jsonb := '{}'::jsonb;
  v_min      integer := private.const('BLIND_DROP_MIN_RIGHT_SWIPES')::integer;
  u          uuid;
begin
  perform private.blind_lock_drops();
  for v_match in
    select m.id, m.user_a, m.user_b from public.blind_matches m
     where m.chat_id is null
       and (private.blind_right_count(m.user_a) >= v_min or private.blind_right_count(m.user_b) >= v_min)
     order by m.created_at, m.id
  loop
    if private.blind_open_chat_for_match(v_match.id) then
      v_total := v_total + 1;
      foreach u in array array[v_match.user_a, v_match.user_b] loop
        v_per_user := jsonb_set(v_per_user, array[u::text],
                                to_jsonb(coalesce((v_per_user ->> u::text)::integer, 0) + 1));
      end loop;
    end if;
  end loop;

  insert into public.blind_drops (user_id, opened_count)
  select key::uuid, value::integer from jsonb_each_text(v_per_user);
  return jsonb_build_object('opened', v_total);
end;
$$;

-- blind_drop_new_chats: the chats a drop shows me: my open chats that no drop has shown me yet
-- (whoever's drop opened them), plus those first shown within BLIND_DROP_REPLAY_WINDOW, oldest
-- first. Says nothing my chat list doesn't (same IDs, same codenames). Empty below
-- BLIND_DROP_MIN_RIGHT_SWIPES right swipes (B3). Returns { chats: [{ id, codename }] }.
create function public.blind_drop_new_chats(p_user_id uuid)
returns jsonb
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_chats jsonb;
begin
  perform private.blind_require_member(p_user_id);
  if private.blind_right_count(p_user_id) < private.const('BLIND_DROP_MIN_RIGHT_SWIPES') then
    return jsonb_build_object('chats', '[]'::jsonb);
  end if;

  insert into public.blind_drop_seen (user_id, chat_id)
  select p_user_id, c.id from public.blind_chats c
   where p_user_id in (c.user_a, c.user_b) and c.status = 'open'
  on conflict (user_id, chat_id) do nothing;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', c.id,
           'codename', case when c.user_a = p_user_id then c.codename_a else c.codename_b end)
         order by c.opened_at, c.id), '[]'::jsonb)
    into v_chats
    from public.blind_chats c
    join public.blind_drop_seen s on s.chat_id = c.id and s.user_id = p_user_id
   where p_user_id in (c.user_a, c.user_b)
     and c.status = 'open'
     and not exists (select 1 from public.blind_chat_exits e where e.chat_id = c.id and e.user_id = p_user_id)
     and s.seen_at > now() - private.const_interval('BLIND_DROP_REPLAY_WINDOW');
  return jsonb_build_object('chats', v_chats);
end;
$$;

-- blind_chat_list: my chats, newest activity first: { chats: [{ id, codename, status, unread,
-- lastMessage? }] }. Nothing that identifies the other person (B1). Chats I left or blocked are
-- gone; the other person sees status left.
create function public.blind_chat_list(p_user_id uuid)
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_chats jsonb;
begin
  perform private.blind_require_member(p_user_id);
  select coalesce(jsonb_agg(x.j order by x.sort_at desc, x.id), '[]'::jsonb) into v_chats
    from (
      select c.id,
             coalesce(lm.created_at, c.opened_at) as sort_at,
             jsonb_strip_nulls(jsonb_build_object(
               'id', c.id,
               'codename', case when c.user_a = p_user_id then c.codename_a else c.codename_b end,
               'status', c.status,
               'unread', exists (
                  select 1 from public.blind_messages m
                   where m.chat_id = c.id
                     and m.side <> case when c.user_a = p_user_id then 'a' else 'b' end
                     and m.id > case when c.user_a = p_user_id then c.read_a else c.read_b end),
               'lastMessage', case when lm.id is null then null else jsonb_build_object(
                  'mine', lm.side = case when c.user_a = p_user_id then 'a' else 'b' end,
                  'text', lm.body,
                  'at', private.iso(lm.created_at)) end)) as j
        from public.blind_chats c
        left join lateral (
          select m.id, m.side, m.body, m.created_at from public.blind_messages m
           where m.chat_id = c.id order by m.id desc limit 1) lm on true
       where p_user_id in (c.user_a, c.user_b)
         and not exists (select 1 from public.blind_chat_exits e where e.chat_id = c.id and e.user_id = p_user_id)
    ) x;
  return jsonb_build_object('chats', v_chats);
end;
$$;

-- blind_get_chat: one chat as I see it: { id, codename, status, iTappedReveal, theyLeft } plus,
-- ONLY when revealed, partner { name, photoCount } and guessCorrect (when I guessed). The route
-- turns photoCount into signed links. Raises not_found (not mine, left or blocked by me).
create function public.blind_get_chat(p_user_id uuid, p_chat_id uuid)
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  c       public.blind_chats;
  v_is_a  boolean;
  v_other uuid;
  v_guess uuid;
  v_out   jsonb;
begin
  perform private.blind_require_member(p_user_id);
  c := private.blind_chat_for(p_user_id, p_chat_id);
  if c.id is null then
    perform private.raise_error('not_found');
  end if;
  v_is_a := c.user_a = p_user_id;
  v_other := case when v_is_a then c.user_b else c.user_a end;
  v_guess := case when v_is_a then c.guess_a else c.guess_b end;

  v_out := jsonb_build_object(
    'id', c.id,
    'codename', case when v_is_a then c.codename_a else c.codename_b end,
    'status', c.status,
    'iTappedReveal', case when v_is_a then c.reveal_a else c.reveal_b end,
    'theyLeft', c.status = 'left' and c.left_by is distinct from p_user_id);

  if c.status = 'revealed' then
    v_out := v_out || jsonb_build_object(
      'partner', jsonb_build_object(
        'name', coalesce((select p.first_name from public.profiles p where p.id = v_other), ''),
        'photoCount', (select count(*)::integer from public.profile_photos pp
                        join public.profiles p on p.id = pp.user_id
                        where pp.user_id = v_other and pp.moderation_status = 'approved'
                          and p.banned_at is null)));
    if v_guess is not null then
      v_out := v_out || jsonb_build_object('guessCorrect', v_guess = v_other);
    end if;
  end if;
  return v_out;
end;
$$;

-- blind_partner_photo_path: the revealed partner's nth approved photo (0-based), for the photo
-- route. Null unless the chat is mine, still listed for me, and revealed (B1).
create function public.blind_partner_photo_path(p_viewer_id uuid, p_chat_id uuid, p_n integer)
returns text
language plpgsql stable security definer
set search_path = ''
as $$
declare
  c       public.blind_chats;
  v_other uuid;
begin
  if p_n is null or p_n < 0 or not private.blind_is_member(p_viewer_id) then
    return null;
  end if;
  c := private.blind_chat_for(p_viewer_id, p_chat_id);
  if c.id is null or c.status <> 'revealed' then
    return null;
  end if;
  v_other := case when c.user_a = p_viewer_id then c.user_b else c.user_a end;
  return (select pp.path from public.profile_photos pp
            join public.profiles p on p.id = pp.user_id
           where pp.user_id = v_other and pp.moderation_status = 'approved' and p.banned_at is null
           order by pp.position
           offset p_n limit 1);
end;
$$;

-- blind_list_messages: { messages: [{ id, mine, text, at }] } after p_after, oldest first, at
-- most p_limit (1..500). mine comes from the stored side; no sender leaves (B12). Marks them read.
create function public.blind_list_messages(p_user_id uuid, p_chat_id uuid, p_after bigint default 0,
                                           p_limit integer default 200)
returns jsonb
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  c       public.blind_chats;
  v_side  char(1);
  v_limit integer := least(greatest(coalesce(p_limit, 200), 1), 500);
  v_after bigint := greatest(coalesce(p_after, 0), 0);
  v_rows  jsonb;
  v_max   bigint;
begin
  perform private.blind_require_member(p_user_id);
  c := private.blind_chat_for(p_user_id, p_chat_id);
  if c.id is null then
    perform private.raise_error('not_found');
  end if;
  v_side := case when c.user_a = p_user_id then 'a' else 'b' end;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', m.id, 'mine', m.side = v_side, 'text', m.body, 'at', private.iso(m.created_at))
         order by m.id), '[]'::jsonb),
         max(m.id)
    into v_rows, v_max
    from (select * from public.blind_messages
           where chat_id = c.id and id > v_after order by id limit v_limit) m;

  if v_max is not null then
    if v_side = 'a' then
      update public.blind_chats set read_a = greatest(read_a, v_max) where id = c.id;
    else
      update public.blind_chats set read_b = greatest(read_b, v_max) where id = c.id;
    end if;
  end if;
  return jsonb_build_object('messages', v_rows);
end;
$$;

-- blind_send_message: add a message as my side. Returns { id, mine: true, text, at }. Raises
-- not_found, chat_closed (the chat ended) or invalid_input. The text is never logged.
create function public.blind_send_message(p_user_id uuid, p_chat_id uuid, p_body text)
returns jsonb
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  c     public.blind_chats;
  v_row public.blind_messages;
begin
  if p_body is null or char_length(btrim(p_body)) = 0 or char_length(p_body) > private.const('MESSAGE_MAX_CHARS') then
    perform private.raise_error('invalid_input');
  end if;
  perform private.blind_require_member(p_user_id);
  select * into c from public.blind_chats ch
   where ch.id = p_chat_id and p_user_id in (ch.user_a, ch.user_b)
     and not exists (select 1 from public.blind_chat_exits e where e.chat_id = ch.id and e.user_id = p_user_id)
   for share;
  if not found then
    perform private.raise_error('not_found');
  end if;
  if c.status = 'left' then
    perform private.raise_error('chat_closed');
  end if;
  insert into public.blind_messages (chat_id, side, body)
  values (c.id, case when c.user_a = p_user_id then 'a' else 'b' end, p_body)
  returning * into v_row;
  return jsonb_build_object('id', v_row.id, 'mine', true, 'text', v_row.body, 'at', private.iso(v_row.created_at));
end;
$$;

-- blind_tap_reveal: my Reveal tap. Returns { status }: open until both tapped, whether or not the
-- other person did (B5); revealed once both did; left if the chat ended.
create function public.blind_tap_reveal(p_user_id uuid, p_chat_id uuid)
returns jsonb
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  c public.blind_chats;
begin
  perform private.blind_require_member(p_user_id);
  select * into c from public.blind_chats ch
   where ch.id = p_chat_id and p_user_id in (ch.user_a, ch.user_b)
     and not exists (select 1 from public.blind_chat_exits e where e.chat_id = ch.id and e.user_id = p_user_id)
   for update;
  if not found then
    perform private.raise_error('not_found');
  end if;
  if c.status = 'open' then
    if c.user_a = p_user_id then
      update public.blind_chats set reveal_a = true where id = c.id returning * into c;
    else
      update public.blind_chats set reveal_b = true where id = c.id returning * into c;
    end if;
    if c.reveal_a and c.reveal_b then
      update public.blind_chats set status = 'revealed', revealed_at = now() where id = c.id returning * into c;
    end if;
  end if;
  return jsonb_build_object('status', c.status);
end;
$$;

-- blind_leave_chat: leave without being revealed (B6). Idempotent. The other person sees only
-- status left. A revealed chat can't be left (only blocked), so it stays listed.
create function public.blind_leave_chat(p_user_id uuid, p_chat_id uuid)
returns jsonb
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  c public.blind_chats;
begin
  perform private.blind_require_member(p_user_id);
  select * into c from public.blind_chats ch
   where ch.id = p_chat_id and p_user_id in (ch.user_a, ch.user_b)
     and not exists (select 1 from public.blind_chat_exits e where e.chat_id = ch.id and e.user_id = p_user_id)
   for update;
  if not found then
    perform private.raise_error('not_found');
  end if;
  if c.status = 'open' then
    update public.blind_chats set status = 'left', left_by = p_user_id where id = c.id;
  end if;
  if c.status in ('open', 'left') then
    insert into public.blind_chat_exits (chat_id, user_id) values (c.id, p_user_id) on conflict do nothing;
  end if;
  return jsonb_build_object('ok', true);
end;
$$;

-- blind_record_guess: Guess Who. p_card_id is one of my pool cards (someone I right-swiped).
-- Returns { ok } and never says whether it's right. Locked after reveal. Raises not_found.
create function public.blind_record_guess(p_user_id uuid, p_chat_id uuid, p_card_id uuid)
returns jsonb
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  c        public.blind_chats;
  v_target uuid;
begin
  perform private.blind_require_member(p_user_id);
  select * into c from public.blind_chats ch
   where ch.id = p_chat_id and p_user_id in (ch.user_a, ch.user_b)
     and not exists (select 1 from public.blind_chat_exits e where e.chat_id = ch.id and e.user_id = p_user_id)
   for update;
  if not found then
    perform private.raise_error('not_found');
  end if;
  v_target := private.blind_card_target(p_user_id, p_card_id);
  if v_target is null or not exists (
       select 1 from public.blind_swipes s
        where s.swiper_id = p_user_id and s.target_id = v_target and s.kind <> 'pass') then
    perform private.raise_error('not_found');
  end if;
  if c.status <> 'revealed' then
    if c.user_a = p_user_id then
      update public.blind_chats set guess_a = v_target where id = c.id;
    else
      update public.blind_chats set guess_b = v_target where id = c.id;
    end if;
  end if;
  return jsonb_build_object('ok', true);
end;
$$;

-- blind_block: block the person behind a chat without learning who (B7). A Glow block: both
-- ways, Blind and Rooms (P7), and it ends any Glow match between the two. The chat closes and is
-- gone for me. Returns { endedMatchIds, roomIds } (from private.block_pair) for Glow's events.
create function public.blind_block(p_user_id uuid, p_chat_id uuid)
returns jsonb
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  c       public.blind_chats;
  v_other uuid;
  v_out   jsonb;
begin
  perform private.blind_require_member(p_user_id);
  perform private.blind_lock_drops();
  select * into c from public.blind_chats ch
   where ch.id = p_chat_id and p_user_id in (ch.user_a, ch.user_b)
     and not exists (select 1 from public.blind_chat_exits e where e.chat_id = ch.id and e.user_id = p_user_id)
   for update;
  if not found then
    perform private.raise_error('not_found');
  end if;
  v_other := case when c.user_a = p_user_id then c.user_b else c.user_a end;
  v_out := private.block_pair(p_user_id, v_other);
  -- The blocks trigger closes the chat on a new block; do it here too for an existing one.
  perform private.blind_close_pair(p_user_id, v_other);
  return v_out;
end;
$$;

-- blind_report: report the person behind a chat. Goes to public.reports (context blind_chat,
-- context_id = the chat), with their last REPORT_EVIDENCE_MESSAGES messages in this chat as
-- evidence, and also blocks them (as every Glow report does). Works on a chat I already left or
-- blocked. Returns { reportId, endedMatchIds, roomIds }. Raises not_found or invalid_input.
create function public.blind_report(p_user_id uuid, p_chat_id uuid, p_details text,
                                    p_reason public.report_reason default 'other')
returns jsonb
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  c          public.blind_chats;
  v_other    uuid;
  v_side     char(1);
  v_evidence jsonb;
  v_report   uuid;
  v_block    jsonb;
begin
  if p_details is null or char_length(btrim(p_details)) = 0
     or char_length(p_details) > private.const('BLIND_REPORT_MAX_CHARS') then
    perform private.raise_error('invalid_input');
  end if;
  perform private.blind_require_member(p_user_id);
  perform private.blind_lock_drops();
  select * into c from public.blind_chats ch
   where ch.id = p_chat_id and p_user_id in (ch.user_a, ch.user_b) for update;
  if not found then
    perform private.raise_error('not_found');
  end if;
  v_other := case when c.user_a = p_user_id then c.user_b else c.user_a end;
  v_side := case when c.user_a = p_user_id then 'b' else 'a' end;

  select coalesce(jsonb_agg(jsonb_build_object('body', x.body, 'createdAt', private.iso(x.created_at))
                            order by x.created_at), '[]'::jsonb)
    into v_evidence
    from (select m.body, m.created_at from public.blind_messages m
           where m.chat_id = c.id and m.side = v_side
           order by m.id desc
           limit private.const('REPORT_EVIDENCE_MESSAGES')::integer) x;

  insert into public.reports (reporter_id, reported_id, room_id, context, context_id, reason, details, evidence)
  values (p_user_id, v_other, null, 'blind_chat', c.id, coalesce(p_reason, 'other'), btrim(p_details), v_evidence)
  returning id into v_report;

  v_block := private.block_pair(p_user_id, v_other);
  perform private.blind_close_pair(p_user_id, v_other);
  return v_block || jsonb_build_object('reportId', v_report);
end;
$$;

-------------------------------------------------------------------------------
-- Grants: service role only, for every blind_ function (the default privileges already keep
-- anon and authenticated out; this says so explicitly). 010_lockdown checks.
-------------------------------------------------------------------------------

do $$
declare
  f record;
begin
  for f in
    select p.oid::regprocedure as sig
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('public', 'private') and p.proname like 'blind\_%'
  loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    execute format('grant execute on function %s to service_role', f.sig);
  end loop;
end;
$$;

revoke all on public.blind_members, public.blind_cards, public.blind_swipes, public.blind_codenames,
              public.blind_chats, public.blind_matches, public.blind_codename_uses, public.blind_messages,
              public.blind_drops, public.blind_drop_seen, public.blind_chat_exits
  from anon, authenticated;
grant all on public.blind_members, public.blind_cards, public.blind_swipes, public.blind_codenames,
             public.blind_chats, public.blind_matches, public.blind_codename_uses, public.blind_messages,
             public.blind_drops, public.blind_drop_seen, public.blind_chat_exits
  to service_role;
grant usage, select on all sequences in schema public to service_role;
