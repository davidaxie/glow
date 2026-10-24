-- 0001_a2_init.sql · A2 · Glow schema
--
-- Everything that must never break lives here: tables, constraints, row level security,
-- the database functions from docs/SPEC.md (Database functions), private storage buckets
-- and Realtime channel authorization.
--
-- Ground rules for this file and every later migration:
--   * Every table has row level security on and NO client policies. The app holds only the
--     anon key, so it can never read or write a table directly. Only the server (service role)
--     touches data, and the rules live in security definer functions below.
--   * Every function is security definer with search_path = '' and fully qualified names.
--   * No user coordinates are stored anywhere (P2). Only rooms (public venues) have lat/lng.
--   * Shared numbers come from private.constants, which mirrors contracts/constants.json.
--     supabase/tests/database/000_constants.test.sql (generated) fails if they drift.
--   * Never edit this file after it merges. Add NNNN_{agent}_{what}.sql instead.

-------------------------------------------------------------------------------
-- Extensions and schemas
-------------------------------------------------------------------------------

create extension if not exists pgcrypto with schema extensions;

-- private: helpers, constants and internal tables. Not exposed through the Data API.
create schema if not exists private;
revoke all on schema private from public, anon;
-- authenticated needs USAGE only so the Realtime policy can call private.can_receive_topic().
grant usage on schema private to authenticated, service_role;

-------------------------------------------------------------------------------
-- Constants (mirror of contracts/constants.json)
-------------------------------------------------------------------------------

create table private.constants (
  name  text primary key check (name ~ '^[A-Z][A-Z0-9_]*$'),
  value numeric not null,
  unit  text not null check (unit in (
          'seconds', 'milliseconds', 'count', 'meters', 'characters', 'pixels', 'percent', 'bytes', 'years'))
);
alter table private.constants enable row level security;

insert into private.constants (name, value, unit) values
  ('CHECKIN_TTL',                 10800,   'seconds'),
  ('CHECKIN_EXPIRY_WARNING',      900,     'seconds'),
  ('TAP_TTL',                     86400,   'seconds'),
  ('TAPS_PER_ROOM_PER_DAY',       3,       'count'),
  ('CARD_VIEWS_PER_ROOM_PER_DAY', 50,      'count'),
  ('CARD_VIEW_RETENTION',         172800,  'seconds'),
  ('DECK_PAGE_SIZE',              10,      'count'),
  ('ROOM_RADIUS_DEFAULT',         200,     'meters'),
  ('GEO_MAX_ACCURACY',            500,     'meters'),
  ('GEO_ACCURACY_CREDIT',         100,     'meters'),
  ('GEO_FRESHNESS_FOR_GLOW',      120,     'seconds'),
  ('LOCATION_FIX_TIMEOUT',        10,      'seconds'),
  ('LOCATION_CHECK_RETENTION',    86400,   'seconds'),
  ('CHOICE_WINDOW',               600,     'seconds'),
  ('GLOW_TTL',                    900,     'seconds'),
  ('GLOW_ENDED_RETENTION',        600,     'seconds'),
  ('QR_ROTATION',                 30,      'seconds'),
  ('QR_ACCEPTED_WINDOWS',         2,       'count'),
  ('QR_TOKEN_LENGTH',             8,       'characters'),
  ('JOIN_TICKET_TTL',             600,     'seconds'),
  ('CARD_URL_TTL',                60,      'seconds'),
  ('MESSAGE_MAX_CHARS',           1000,    'characters'),
  ('MESSAGES_PAGE_SIZE',          50,      'count'),
  ('MODERATION_TIMEOUT',          2500,    'milliseconds'),
  ('PURGE_INTERVAL',              300,     'seconds'),
  ('MIN_AGE',                     18,      'years'),
  ('PROFILE_PHOTOS_MIN',          1,       'count'),
  ('PROFILE_PHOTOS_MAX',          3,       'count'),
  ('MEETING_SPOTS_MIN',           3,       'count'),
  ('MEETING_SPOTS_MAX',           5,       'count'),
  ('ROOM_CODE_LENGTH',            6,       'characters'),
  ('REPORT_DETAILS_MAX_CHARS',    1000,    'characters'),
  ('REPORT_EVIDENCE_MESSAGES',    20,      'count'),
  ('PHOTO_MAX_DIMENSION',         1920,    'pixels'),
  ('PHOTO_JPEG_QUALITY',          80,      'percent'),
  ('PHOTO_MAX_BYTES',             3000000, 'bytes'),
  ('FACE_BOX_GROWTH',             30,      'percent');

create function private.const(p_name text)
returns numeric
language plpgsql stable
set search_path = ''
as $$
declare
  v numeric;
begin
  select c.value into v from private.constants c where c.name = p_name;
  if v is null then
    raise exception 'unknown constant %', p_name;
  end if;
  return v;
end;
$$;

create function private.const_interval(p_name text)
returns interval
language sql stable
set search_path = ''
as $$
  select make_interval(secs => private.const(p_name)::double precision);
$$;

-------------------------------------------------------------------------------
-- Small helpers
-------------------------------------------------------------------------------

-- Random code from an alphabet whose length divides 256 (so there is no modulo bias).
create function private.random_code(p_length integer, p_alphabet text)
returns text
language plpgsql volatile
set search_path = ''
as $$
declare
  v_bytes bytea := extensions.gen_random_bytes(p_length);
  v_n     integer := length(p_alphabet);
  v_out   text := '';
begin
  if 256 % v_n <> 0 then
    raise exception 'alphabet length must divide 256';
  end if;
  for i in 0 .. p_length - 1 loop
    v_out := v_out || substr(p_alphabet, (get_byte(v_bytes, i) % v_n) + 1, 1);
  end loop;
  return v_out;
end;
$$;

-- 32 characters with no 0/O or 1/I, for codes people read or type.
create function private.human_alphabet()
returns text
language sql immutable
set search_path = ''
as $$ select 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'::text; $$;

-- RFC 4648 base32 alphabet, for QR tokens.
create function private.base32_alphabet()
returns text
language sql immutable
set search_path = ''
as $$ select 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'::text; $$;

create function private.lock_key(p_scope text, p_a uuid, p_b uuid default null)
returns bigint
language sql immutable
set search_path = ''
as $$
  select hashtextextended('glow:' || p_scope || ':' || p_a::text || ':' || coalesce(p_b::text, ''), 0);
$$;

-- The same key for (x, y) and (y, x).
create function private.pair_lock_key(p_x uuid, p_y uuid)
returns bigint
language sql immutable
set search_path = ''
as $$
  select private.lock_key('pair', least(p_x, p_y), greatest(p_x, p_y));
$$;

create function private.is_valid_timezone(p_tz text)
returns boolean
language sql stable
set search_path = ''
as $$
  select exists (select 1 from pg_catalog.pg_timezone_names where name = p_tz);
$$;

create function private.raise_error(p_code text)
returns void
language plpgsql
set search_path = ''
as $$
begin
  -- Every expected failure is SQLSTATE P0001 with the error code as the message.
  -- The server maps the code to an HTTP error (docs/CONTRACTS.md, "Database errors").
  raise exception using errcode = 'P0001', message = p_code;
end;
$$;

-- Times in function output are RFC 3339 UTC with milliseconds, exactly as the API sends them:
-- 2026-10-24T20:15:00.000Z. (The generated zod schemas reject offsets like +00:00.)
create function private.iso(p_at timestamptz)
returns text
language sql immutable
set search_path = ''
as $$
  select to_char(p_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
$$;

-------------------------------------------------------------------------------
-- Enums (mirrored in contracts/openapi.yaml)
-------------------------------------------------------------------------------

create type public.gender                 as enum ('woman', 'man', 'nonbinary');
create type public.onboarding_step        as enum ('profile', 'photos', 'notifications', 'complete');
create type public.moderation_status      as enum ('pending', 'approved', 'held', 'rejected');
create type public.apns_environment       as enum ('sandbox', 'production');
create type public.room_status            as enum ('live', 'paused', 'ended');
create type public.top_color              as enum ('black', 'white', 'gray', 'red', 'pink', 'orange',
                                                   'yellow', 'green', 'blue', 'purple');
create type public.hair_length            as enum ('short', 'medium', 'long');
create type public.hair_color             as enum ('black', 'brown', 'blonde', 'red', 'gray', 'dyed');
create type public.card_extra             as enum ('glasses', 'hat', 'beard', 'headphones', 'backpack');
create type public.match_status           as enum ('choosing', 'glowing', 'chatting', 'met', 'ended');
create type public.match_choice           as enum ('find', 'chat');
create type public.glow_color             as enum ('ember', 'rose', 'violet', 'sky', 'aqua', 'lime', 'sun', 'pearl');
create type public.glow_status            as enum ('active', 'met', 'canceled', 'expired');
create type public.message_moderation     as enum ('pending', 'passed', 'flagged');
create type public.report_context         as enum ('card', 'match', 'chat');
create type public.report_reason          as enum ('harassment', 'inappropriate_photo', 'underage', 'spam',
                                                   'unsafe', 'other');
create type public.report_status          as enum ('open', 'dismissed', 'actioned');
create type public.abuse_kind             as enum ('screenshot', 'recording');
create type public.location_check_purpose as enum ('join', 'find');
create type public.location_check_result  as enum ('pass', 'fail', 'demo_skip');
create type public.accuracy_bucket        as enum ('under_20m', 'under_50m', 'under_100m', 'under_500m', 'over_500m');
create type public.room_activity_kind     as enum ('checkin', 'card_view', 'tap', 'match', 'glow_started',
                                                   'glow_met', 'report');

-------------------------------------------------------------------------------
-- Tables
-------------------------------------------------------------------------------

-- profiles: one row per auth user, created by a trigger on auth.users.
create table public.profiles (
  id              uuid primary key references auth.users (id) on delete cascade,
  first_name      text check (first_name is null or char_length(btrim(first_name)) between 1 and 40),
  birthdate       date check (birthdate is null or birthdate >= date '1900-01-01'),
  gender          public.gender,
  show_me         public.gender[] not null default '{}',
  paused          boolean not null default false,
  onboarding_step public.onboarding_step not null default 'profile',
  -- Printed in watermarks so a leaked screenshot can be traced. Not a user ID.
  viewer_code     text not null unique
                  default private.random_code(8, private.human_alphabet())
                  check (viewer_code ~ '^[A-HJ-NP-Z2-9]{8}$'),
  banned_at       timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint profiles_complete_has_fields check (
    onboarding_step <> 'complete'
    or (first_name is not null and birthdate is not null and gender is not null and cardinality(show_me) > 0)
  )
);

create table public.profile_photos (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references public.profiles (id) on delete cascade,
  -- Object name inside the private profile-photos bucket.
  path              text not null unique,
  position          smallint not null check (position between 0 and 2),
  moderation_status public.moderation_status not null default 'pending',
  created_at        timestamptz not null default now(),
  constraint profile_photos_path_matches check (path = user_id::text || '/' || id::text || '.jpg'),
  constraint profile_photos_one_per_position unique (user_id, position) deferrable initially immediate
);

create table public.devices (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references public.profiles (id) on delete cascade,
  apns_token       text not null unique check (apns_token ~ '^[0-9a-f]{64,200}$'),
  apns_environment public.apns_environment not null,
  app_version      text check (app_version is null or char_length(app_version) <= 32),
  created_at       timestamptz not null default now(),
  last_ok_at       timestamptz
);
create index devices_user on public.devices (user_id);

create table public.admins (
  user_id    uuid primary key references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now()
);

create table public.rooms (
  id              uuid primary key default gen_random_uuid(),
  slug            text not null unique check (slug ~ '^[a-z0-9](?:[a-z0-9-]{0,38}[a-z0-9])?$'),
  name            text not null check (char_length(btrim(name)) between 1 and 80),
  code            text not null unique
                  default private.random_code(6, private.human_alphabet())
                  check (code ~ '^[A-HJ-NP-Z2-9]{6}$'),
  -- A room's own location is a public venue, so it's fine to store.
  lat             double precision not null check (lat between -90 and 90),
  lng             double precision not null check (lng between -180 and 180),
  radius_m        integer not null default private.const('ROOM_RADIUS_DEFAULT')::integer
                  check (radius_m between 10 and 5000),
  -- Days for the tap and view caps, and the deck shuffle, are counted in the room's timezone.
  timezone        text not null default 'America/Los_Angeles' check (private.is_valid_timezone(timezone)),
  -- HMAC key for rotating screen tokens: 32 random bytes, hex encoded.
  qr_secret       text not null default encode(extensions.gen_random_bytes(32), 'hex')
                  check (qr_secret ~ '^[0-9a-f]{64}$'),
  -- Long-lived token for printed posters. Accepted only when allow_static_qr is on.
  static_qr_token text not null unique
                  default private.random_code(16, private.base32_alphabet())
                  check (static_qr_token ~ '^[A-Z2-7]{16}$'),
  allow_static_qr boolean not null default false,
  demo_mode       boolean not null default false,
  status          public.room_status not null default 'live',
  starts_at       timestamptz not null,
  ends_at         timestamptz not null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint rooms_ends_after_start check (ends_at > starts_at)
);

create table public.meeting_spots (
  id      uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms (id) on delete cascade,
  name    text not null check (char_length(btrim(name)) between 1 and 60),
  sort    smallint not null default 0,
  constraint meeting_spots_unique_sort unique (room_id, sort) deferrable initially immediate
);

-- checkins: the ID is also the card ID, so a card never carries a user ID.
create table public.checkins (
  id               uuid primary key,
  room_id          uuid not null references public.rooms (id) on delete cascade,
  user_id          uuid not null references public.profiles (id) on delete cascade,
  -- Object name inside the private room-cards bucket: {roomId}/{cardId}.jpg
  card_path        text not null unique,
  top_color        public.top_color not null,
  hair_length      public.hair_length,
  hair_color       public.hair_color,
  extras           public.card_extra[] not null default '{}',
  visible          boolean not null default true,
  joined_at        timestamptz not null default now(),
  expires_at       timestamptz not null,
  left_at          timestamptz,
  expiry_warned_at timestamptz,
  constraint checkins_card_path_matches check (card_path = room_id::text || '/' || id::text || '.jpg'),
  constraint checkins_expires_after_join check (expires_at > joined_at)
);
-- One open check-in per person per room. create_checkin() closes the older one first.
create unique index checkins_one_open_per_person_room on public.checkins (room_id, user_id) where left_at is null;
create index checkins_room_expiry on public.checkins (room_id, expires_at) where left_at is null;
create index checkins_user on public.checkins (user_id);

-- card_views: for the daily view cap. checkin_id is deliberately not a foreign key, so views
-- still count after a card is purged. Rows are purged after CARD_VIEW_RETENTION.
create table public.card_views (
  viewer_id  uuid not null references public.profiles (id) on delete cascade,
  checkin_id uuid not null,
  room_id    uuid not null references public.rooms (id) on delete cascade,
  view_day   date not null,
  viewed_at  timestamptz not null default now(),
  primary key (viewer_id, checkin_id, view_day)
);
create index card_views_viewer_room_day on public.card_views (viewer_id, room_id, view_day);
create index card_views_checkin on public.card_views (checkin_id);
create index card_views_viewed_at on public.card_views (viewed_at);

-- matches: user_a sorts before user_b. One active (not ended) match per pair.
create table public.matches (
  id              uuid primary key default gen_random_uuid(),
  room_id         uuid not null references public.rooms (id) on delete cascade,
  user_a          uuid not null references public.profiles (id) on delete cascade,
  user_b          uuid not null references public.profiles (id) on delete cascade,
  status          public.match_status not null default 'choosing',
  a_choice        public.match_choice,
  b_choice        public.match_choice,
  choice_deadline timestamptz not null,
  created_at      timestamptz not null default now(),
  ended_at        timestamptz,
  constraint matches_ordered_pair check (user_a < user_b)
);
create unique index matches_one_active_per_pair on public.matches (user_a, user_b) where status <> 'ended';
create index matches_user_a on public.matches (user_a);
create index matches_user_b on public.matches (user_b);
create index matches_room on public.matches (room_id);
create index matches_choosing_deadline on public.matches (choice_deadline) where status = 'choosing';

-- taps: unique per room, from and to. Lasts TAP_TTL. match_id is set once the tap has been
-- used for a match, so an old tap can't make a second match after an unmatch.
create table public.taps (
  id         uuid primary key default gen_random_uuid(),
  room_id    uuid not null references public.rooms (id) on delete cascade,
  from_user  uuid not null references public.profiles (id) on delete cascade,
  to_user    uuid not null references public.profiles (id) on delete cascade,
  match_id   uuid references public.matches (id) on delete set null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  constraint taps_not_self check (from_user <> to_user),
  constraint taps_one_per_pair_per_room unique (room_id, from_user, to_user)
);
create index taps_room_target on public.taps (room_id, to_user);
create index taps_from_room_created on public.taps (from_user, room_id, created_at);
create index taps_to_user on public.taps (to_user);
create index taps_expires on public.taps (expires_at);
create index taps_match on public.taps (match_id) where match_id is not null;

create table public.glow_sessions (
  id         uuid primary key default gen_random_uuid(),
  match_id   uuid not null references public.matches (id) on delete cascade,
  room_id    uuid not null references public.rooms (id) on delete cascade,
  color      public.glow_color not null,
  code_word  text not null check (code_word ~ '^[a-z]{2,16}$'),
  spot_id    uuid references public.meeting_spots (id) on delete set null,
  started_at timestamptz not null default now(),
  ends_at    timestamptz not null,
  a_met      boolean not null default false,
  b_met      boolean not null default false,
  status     public.glow_status not null default 'active',
  ended_at   timestamptz,
  constraint glow_sessions_ends_after_start check (ends_at > started_at)
);
-- Color plus code word is unique among active sessions in a room.
create unique index glow_sessions_unique_color_word on public.glow_sessions (room_id, color, code_word)
  where status = 'active';
create unique index glow_sessions_one_active_per_match on public.glow_sessions (match_id) where status = 'active';
create index glow_sessions_match on public.glow_sessions (match_id);
create index glow_sessions_spot on public.glow_sessions (spot_id);

create table public.messages (
  id         uuid primary key default gen_random_uuid(),
  match_id   uuid not null references public.matches (id) on delete cascade,
  sender_id  uuid not null references public.profiles (id) on delete cascade,
  body       text not null,
  moderation public.message_moderation not null default 'pending',
  -- Optional idempotency key from the app, so a retried send doesn't duplicate.
  client_id  uuid,
  created_at timestamptz not null default now(),
  constraint messages_body_length check (
    char_length(btrim(body)) >= 1 and char_length(body) <= private.const('MESSAGE_MAX_CHARS'))
);
create unique index messages_client_id on public.messages (match_id, sender_id, client_id) where client_id is not null;
create index messages_match_created on public.messages (match_id, created_at desc);
create index messages_sender on public.messages (sender_id);

-- blocks: always checked in both directions.
create table public.blocks (
  blocker_id uuid not null references public.profiles (id) on delete cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint blocks_not_self check (blocker_id <> blocked_id)
);
create index blocks_blocked on public.blocks (blocked_id);

create table public.reports (
  id          uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles (id) on delete cascade,
  reported_id uuid not null references public.profiles (id) on delete cascade,
  room_id     uuid references public.rooms (id) on delete set null,
  context     public.report_context not null,
  context_id  uuid not null,
  reason      public.report_reason not null,
  details     text check (details is null or char_length(details) <= private.const('REPORT_DETAILS_MAX_CHARS')),
  -- For match and chat reports: the reported person's last messages in that thread, copied
  -- before the block deletes the thread. [{ "body": text, "createdAt": timestamptz }]
  evidence    jsonb not null default '[]'::jsonb check (jsonb_typeof(evidence) = 'array'),
  status      public.report_status not null default 'open',
  created_at  timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references public.profiles (id) on delete set null,
  constraint reports_not_self check (reporter_id <> reported_id)
);
create index reports_status_created on public.reports (status, created_at);
create index reports_reported on public.reports (reported_id);
create index reports_reporter on public.reports (reporter_id);
create index reports_resolved_by on public.reports (resolved_by);
create index reports_room on public.reports (room_id);

create table public.abuse_signals (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles (id) on delete cascade,
  room_id    uuid references public.rooms (id) on delete set null,
  kind       public.abuse_kind not null,
  created_at timestamptz not null default now()
);
create index abuse_signals_user_created on public.abuse_signals (user_id, created_at);
create index abuse_signals_room on public.abuse_signals (room_id);

-- location_checks: pass or fail and a rough accuracy bucket. Never coordinates (P2).
-- Also the log of demo-mode skips, and the source of GEO_FRESHNESS_FOR_GLOW.
create table public.location_checks (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references public.profiles (id) on delete cascade,
  room_id         uuid not null references public.rooms (id) on delete cascade,
  purpose         public.location_check_purpose not null,
  result          public.location_check_result not null,
  accuracy_bucket public.accuracy_bucket,
  created_at      timestamptz not null default now()
);
create index location_checks_user_room_created on public.location_checks (user_id, room_id, created_at desc);
create index location_checks_room on public.location_checks (room_id);
create index location_checks_created on public.location_checks (created_at);

-- room_activity: anonymous, append-only counters for the admin metrics page. No user IDs.
create table public.room_activity (
  id         bigint generated always as identity primary key,
  room_id    uuid not null references public.rooms (id) on delete cascade,
  kind       public.room_activity_kind not null,
  n          integer not null default 1 check (n > 0),
  created_at timestamptz not null default now()
);
create index room_activity_room_kind_created on public.room_activity (room_id, kind, created_at);

-------------------------------------------------------------------------------
-- Row level security: on for every table, with no policies. Only the service role
-- (which bypasses RLS) can read or write. The grants at the end of this file back this up.
-------------------------------------------------------------------------------

alter table public.profiles         enable row level security;
alter table public.profile_photos   enable row level security;
alter table public.devices          enable row level security;
alter table public.admins           enable row level security;
alter table public.rooms            enable row level security;
alter table public.meeting_spots    enable row level security;
alter table public.checkins         enable row level security;
alter table public.card_views       enable row level security;
alter table public.matches          enable row level security;
alter table public.taps             enable row level security;
alter table public.glow_sessions    enable row level security;
alter table public.messages         enable row level security;
alter table public.blocks           enable row level security;
alter table public.reports          enable row level security;
alter table public.abuse_signals    enable row level security;
alter table public.location_checks  enable row level security;
alter table public.room_activity    enable row level security;

-------------------------------------------------------------------------------
-- Triggers
-------------------------------------------------------------------------------

-- Every new auth user gets a profile row (onboarding_step = 'profile').
create function private.handle_new_auth_user()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id) values (new.id) on conflict (id) do nothing;
  return new;
end;
$$;

create trigger glow_on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_auth_user();

-- Nobody under MIN_AGE can be stored (P10). "Today" is taken in the last timezone on Earth
-- (UTC-12), so nobody counts as 18 anywhere before it's their birthday everywhere.
create function private.profiles_before_write()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
begin
  if new.birthdate is not null
     and new.birthdate > ((now() at time zone 'Etc/GMT+12')::date
                          - make_interval(years => private.const('MIN_AGE')::integer))::date then
    perform private.raise_error('under_18');
  end if;
  new.show_me := coalesce((select array_agg(distinct g order by g) from unnest(new.show_me) g), '{}');
  if new.first_name is not null then
    new.first_name := btrim(new.first_name);
  end if;
  new.updated_at := now();
  return new;
end;
$$;

create trigger glow_profiles_before_write
  before insert or update on public.profiles
  for each row execute function private.profiles_before_write();

create function private.rooms_before_write()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
begin
  new.code := upper(new.code);
  new.updated_at := now();
  return new;
end;
$$;

create trigger glow_rooms_before_write
  before insert or update on public.rooms
  for each row execute function private.rooms_before_write();

-------------------------------------------------------------------------------
-- Rule helpers. Every deck rule in docs/SPEC.md "Core rules and numbers" is written once,
-- here, and reused by get_deck, card_visible_to and record_tap.
-------------------------------------------------------------------------------

-- The room's calendar day, in the room's timezone.
create function private.room_day(p_room_id uuid)
returns date
language sql stable
set search_path = ''
as $$
  select (now() at time zone r.timezone)::date from public.rooms r where r.id = p_room_id;
$$;

-- Midnight at the start of the room's current day.
create function private.room_day_start(p_room_id uuid)
returns timestamptz
language sql stable
set search_path = ''
as $$
  select ((now() at time zone r.timezone)::date)::timestamp at time zone r.timezone
  from public.rooms r where r.id = p_room_id;
$$;

-- Open check-in: not left, not expired, in a room that is live right now.
-- Enough to listen on room:{id} and to start a glow.
create function private.open_checkin(p_user_id uuid, p_room_id uuid)
returns uuid
language sql stable
set search_path = ''
as $$
  select c.id
  from public.checkins c
  join public.rooms r on r.id = c.room_id
  where c.user_id = p_user_id
    and c.room_id = p_room_id
    and c.left_at is null
    and c.expires_at > now()
    and r.status = 'live'
    and r.starts_at <= now()
    and r.ends_at > now()
  limit 1;
$$;

-- Active check-in: open, the card is visible, and the person is not paused or banned.
-- Deck rule 1: both people need one.
create function private.active_checkin(p_user_id uuid, p_room_id uuid)
returns uuid
language sql stable
set search_path = ''
as $$
  select c.id
  from public.checkins c
  join public.profiles p on p.id = c.user_id
  where c.id = private.open_checkin(p_user_id, p_room_id)
    and c.visible
    and not p.paused
    and p.banned_at is null
    and p.onboarding_step = 'complete';
$$;

-- Deck rules 2 to 4 for a pair of people: show me in both directions, no block in either
-- direction, and no active match between them.
create function private.pair_eligible(p_viewer_id uuid, p_other_id uuid)
returns boolean
language sql stable
set search_path = ''
as $$
  select p_viewer_id <> p_other_id
    and exists (
      select 1
      from public.profiles v, public.profiles o
      where v.id = p_viewer_id
        and o.id = p_other_id
        and o.gender = any (v.show_me)
        and v.gender = any (o.show_me))
    and not exists (
      select 1 from public.blocks b
      where (b.blocker_id = p_viewer_id and b.blocked_id = p_other_id)
         or (b.blocker_id = p_other_id and b.blocked_id = p_viewer_id))
    and not exists (
      select 1 from public.matches m
      where m.user_a = least(p_viewer_id, p_other_id)
        and m.user_b = greatest(p_viewer_id, p_other_id)
        and m.status <> 'ended');
$$;

-- A card is in the viewer's deck right now (before filters and the view cap).
create function private.card_in_deck(p_viewer_id uuid, p_checkin_id uuid)
returns boolean
language sql stable
set search_path = ''
as $$
  select exists (
    select 1
    from public.checkins c
    where c.id = p_checkin_id
      and c.user_id <> p_viewer_id
      and private.active_checkin(c.user_id, c.room_id) = c.id
      and private.active_checkin(p_viewer_id, c.room_id) is not null
      and private.pair_eligible(p_viewer_id, c.user_id));
$$;

-- The deck has shown this card to the viewer (get_deck writes card_views).
create function private.card_was_shown(p_viewer_id uuid, p_checkin_id uuid)
returns boolean
language sql stable
set search_path = ''
as $$
  select exists (
    select 1 from public.card_views v where v.viewer_id = p_viewer_id and v.checkin_id = p_checkin_id);
$$;

-- A passed (or demo-skipped) location check in this room within GEO_FRESHNESS_FOR_GLOW.
create function private.location_fresh(p_user_id uuid, p_room_id uuid)
returns boolean
language sql stable
set search_path = ''
as $$
  select exists (
    select 1 from public.location_checks l
    where l.user_id = p_user_id
      and l.room_id = p_room_id
      and l.result in ('pass', 'demo_skip')
      and l.created_at > now() - private.const_interval('GEO_FRESHNESS_FOR_GLOW'));
$$;

create function private.log_activity(p_room_id uuid, p_kind public.room_activity_kind, p_n integer default 1)
returns void
language sql
set search_path = ''
as $$
  insert into public.room_activity (room_id, kind, n)
  select p_room_id, p_kind, p_n
  where p_n > 0;
$$;

-- jsonb array of strings to a sorted, distinct text[]. NULL, JSON null or [] mean "no filter".
create function private.jsonb_text_array(p_value jsonb)
returns text[]
language plpgsql immutable
set search_path = ''
as $$
begin
  if p_value is null or jsonb_typeof(p_value) = 'null' then
    return null;
  end if;
  if jsonb_typeof(p_value) <> 'array' then
    perform private.raise_error('invalid_input');
  end if;
  if jsonb_array_length(p_value) = 0 then
    return null;
  end if;
  return array(select distinct x from jsonb_array_elements_text(p_value) x order by 1);
end;
$$;

create function private.tags_json(p_checkin public.checkins)
returns jsonb
language sql immutable
set search_path = ''
as $$
  select jsonb_build_object(
    'topColor',   p_checkin.top_color,
    'hairLength', p_checkin.hair_length,
    'hairColor',  p_checkin.hair_color,
    'extras',     to_jsonb(p_checkin.extras));
$$;

create function private.checkin_json(p_checkin public.checkins)
returns jsonb
language sql immutable
set search_path = ''
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'id',        p_checkin.id,
    'roomId',    p_checkin.room_id,
    'cardPath',  p_checkin.card_path,
    'tags',      private.tags_json(p_checkin),
    'visible',   p_checkin.visible,
    'joinedAt',  private.iso(p_checkin.joined_at),
    'expiresAt', private.iso(p_checkin.expires_at),
    'leftAt',    private.iso(p_checkin.left_at)));
$$;

create function private.glow_json(p_glow public.glow_sessions, p_user_id uuid default null)
returns jsonb
language sql stable
set search_path = ''
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'id',          p_glow.id,
    'matchId',     p_glow.match_id,
    'roomId',      p_glow.room_id,
    'status',      p_glow.status,
    'color',       p_glow.color,
    'codeWord',    p_glow.code_word,
    'meetingSpot', (select jsonb_build_object('id', s.id, 'name', s.name)
                    from public.meeting_spots s where s.id = p_glow.spot_id),
    'startedAt',   private.iso(p_glow.started_at),
    'endsAt',      private.iso(p_glow.ends_at),
    'endedAt',     private.iso(p_glow.ended_at),
    'youMet',      case when p_user_id = m.user_a then p_glow.a_met
                        when p_user_id = m.user_b then p_glow.b_met
                        else false end,
    'theyMet',     case when p_user_id = m.user_a then p_glow.b_met
                        when p_user_id = m.user_b then p_glow.a_met
                        else false end,
    'userIds',     jsonb_build_array(m.user_a, m.user_b)))
  from public.matches m
  where m.id = p_glow.match_id;
$$;

-- A match from one person's side. firstName and photoCount are the OTHER person's, and only
-- ever leave the database once a match exists (P1). photoCount counts approved photos.
-- glow is the latest glow session (active, or ended within GLOW_ENDED_RETENTION), or null.
-- userIds is for the server's notify() and must never be sent to an app.
create function private.match_json(p_match public.matches, p_user_id uuid)
returns jsonb
language sql stable
set search_path = ''
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'id',             p_match.id,
    'status',         p_match.status,
    'firstName',      o.first_name,
    'photoCount',     (select count(*) from public.profile_photos pp
                        where pp.user_id = o.id and pp.moderation_status = 'approved'),
    'roomId',         p_match.room_id,
    'roomName',       r.name,
    'createdAt',      private.iso(p_match.created_at),
    'choiceDeadline', private.iso(p_match.choice_deadline),
    'yourChoice',     case when p_user_id = p_match.user_a then p_match.a_choice else p_match.b_choice end,
    'otherHasChosen', (case when p_user_id = p_match.user_a then p_match.b_choice else p_match.a_choice end) is not null,
    'glow',           (select private.glow_json(g, p_user_id) from public.glow_sessions g
                        where g.match_id = p_match.id order by g.started_at desc limit 1),
    'lastMessageAt',  (select private.iso(max(msg.created_at)) from public.messages msg where msg.match_id = p_match.id),
    'userIds',        jsonb_build_array(p_match.user_a, p_match.user_b)))
  from public.profiles o
  join public.rooms r on r.id = p_match.room_id
  where o.id = case when p_user_id = p_match.user_a then p_match.user_b else p_match.user_a end;
$$;

create function private.choice_json(p_match public.matches, p_user_id uuid, p_next text, p_reason text)
returns jsonb
language sql stable
set search_path = ''
as $$
  select jsonb_build_object(
    'next',   p_next,
    'reason', p_reason,
    'match',  private.match_json(p_match, p_user_id));
$$;

-- Apply time-based changes to one match: a choice window that ran out opens the chat, and a
-- glow whose time ran out expires. Call with the match row locked.
create function private.settle_match(p_match_id uuid)
returns public.matches
language plpgsql
set search_path = ''
as $$
declare
  v_m public.matches;
begin
  update public.glow_sessions g
     set status = 'expired', ended_at = g.ends_at
   where g.match_id = p_match_id and g.status = 'active' and g.ends_at <= now();
  if found then
    update public.matches set status = 'chatting' where id = p_match_id and status = 'glowing';
  end if;
  update public.matches
     set status = 'chatting'
   where id = p_match_id and status = 'choosing' and choice_deadline <= now();
  select * into v_m from public.matches where id = p_match_id;
  return v_m;
end;
$$;

-- Retire active glows whose time ran out, and move their matches to chatting.
-- Returns [{ matchId, userIds }] for glow.ended events.
create function private.expire_glows(p_room_id uuid default null)
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
  select coalesce(jsonb_agg(jsonb_build_object('matchId', m.id, 'userIds', jsonb_build_array(m.user_a, m.user_b))),
                  '[]'::jsonb)
    into v_result
    from expired e
    join public.matches m on m.id = e.match_id;
  return v_result;
end;
$$;

-- End a match for both people: cancel any glow and delete the thread.
-- The taps that made it keep their match_id, so they can't make another match.
create function private.end_match(p_match_id uuid)
returns void
language plpgsql
set search_path = ''
as $$
begin
  update public.glow_sessions
     set status = 'canceled', ended_at = now()
   where match_id = p_match_id and status = 'active';
  delete from public.messages where match_id = p_match_id;
  update public.matches
     set status = 'ended', ended_at = now()
   where id = p_match_id and status <> 'ended';
end;
$$;

-- Block p_blocked for p_blocker, end every active match between them, and return the rooms
-- whose decks changed. Blocks are checked in both directions everywhere (P7).
create function private.block_pair(p_blocker_id uuid, p_blocked_id uuid)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_match_ids uuid[];
  v_room_ids  uuid[];
  v_id        uuid;
begin
  if p_blocker_id is null or p_blocked_id is null or p_blocker_id = p_blocked_id then
    perform private.raise_error('invalid_input');
  end if;
  perform pg_advisory_xact_lock(private.pair_lock_key(p_blocker_id, p_blocked_id));

  insert into public.blocks (blocker_id, blocked_id)
  values (p_blocker_id, p_blocked_id)
  on conflict do nothing;

  select coalesce(array_agg(m.id), '{}') into v_match_ids
    from public.matches m
   where m.user_a = least(p_blocker_id, p_blocked_id)
     and m.user_b = greatest(p_blocker_id, p_blocked_id)
     and m.status <> 'ended';

  foreach v_id in array v_match_ids loop
    perform 1 from public.matches where id = v_id for update;
    perform private.end_match(v_id);
  end loop;

  select coalesce(array_agg(distinct c.room_id), '{}') into v_room_ids
    from public.checkins c
   where c.user_id in (p_blocker_id, p_blocked_id)
     and c.left_at is null
     and c.expires_at > now();

  return jsonb_build_object('endedMatchIds', to_jsonb(v_match_ids), 'roomIds', to_jsonb(v_room_ids));
end;
$$;

-- Work out the other person from a card, match or chat ID, on the server.
-- card: a card the caller has been shown. match and chat: a match the caller is in.
create function private.resolve_context(
  p_user_id    uuid,
  p_context    public.report_context,
  p_context_id uuid,
  out o_target_id uuid,
  out o_room_id   uuid,
  out o_match_id  uuid)
language plpgsql stable
set search_path = ''
as $$
begin
  if p_context = 'card' then
    select c.user_id, c.room_id
      into o_target_id, o_room_id
      from public.checkins c
     where c.id = p_context_id
       and c.user_id <> p_user_id
       and private.card_was_shown(p_user_id, c.id);
  else
    select case when m.user_a = p_user_id then m.user_b else m.user_a end, m.room_id, m.id
      into o_target_id, o_room_id, o_match_id
      from public.matches m
     where m.id = p_context_id
       and p_user_id in (m.user_a, m.user_b);
  end if;
  if o_target_id is null then
    perform private.raise_error('not_found');
  end if;
end;
$$;

-------------------------------------------------------------------------------
-- Database functions (docs/SPEC.md, "Database functions"). Server only.
-- Errors: SQLSTATE P0001 with message = an error code. See docs/CONTRACTS.md.
-------------------------------------------------------------------------------

-- create_checkin: end any older check-in for this person in this room and start a new one.
-- The server generates the card ID, uploads the blurred photo to room-cards/{roomId}/{cardId}.jpg,
-- then calls this. Expiry is CHECKIN_TTL, cut short if the room ends sooner.
-- p_tags: { "topColor": TopColor, "hairLength"?: HairLength, "hairColor"?: HairColor, "extras"?: [CardExtra] }
-- Returns { checkin: Checkin, replacedCardPaths: [text] } (delete those photos now).
-- Raises invalid_input, not_found, room_not_live or onboarding_incomplete.
create function public.create_checkin(
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

  return jsonb_build_object('checkin', private.checkin_json(v_row), 'replacedCardPaths', to_jsonb(v_replaced));
end;
$$;

-- get_deck: eligible cards in a shuffled order that stays the same for the viewer all day.
-- Applies every deck rule, the filters, and the daily view cap, and records the views.
-- p_filters (each optional, [] means any): { gender: [Gender], topColor: [TopColor],
--   hairLength: [HairLength], hairColor: [HairColor], extras: [CardExtra] }
--   A card matches when each listed attribute is one of the listed values, and it has every
--   listed extra. A card with no hair tag doesn't match a hair filter.
-- Returns { cards: [{ id, cardPath, tags, tappedByMe }], viewsLeftToday, hasMore, nextOffset,
--   emptyReason: null | quiet | no_match | view_limit_reached | paused | checkin_ended }
-- Raises not_found if the viewer has no check-in row in this room at all, or invalid_input.
create function public.get_deck(
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

  if not exists (select 1 from public.checkins c where c.user_id = p_viewer_id and c.room_id = p_room_id) then
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

-- card_visible_to: yes or no, for the card image route. Same rules as the deck: the card is in
-- the viewer's deck right now and the deck has shown it to them. Owners can see their own card.
create function public.card_visible_to(p_viewer_id uuid, p_checkin_id uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select coalesce(
    exists (select 1 from public.checkins c
             where c.id = p_checkin_id and c.user_id = p_viewer_id
               and c.left_at is null and c.expires_at > now())
    or (private.card_in_deck(p_viewer_id, p_checkin_id) and private.card_was_shown(p_viewer_id, p_checkin_id)),
    false);
$$;

-- record_tap: check the card is in the viewer's deck and the daily cap, save the tap, and make
-- the match if the other person already tapped back, all in one transaction. An advisory lock
-- on the pair means two taps at the same moment make exactly one match.
-- Tapping the same card again is a no-op that doesn't use a tap.
-- Returns { result: "sent" | "mutual", tapsLeftToday, matchId (null unless mutual) }.
-- Raises not_found (card not in the viewer's deck), tap_limit_reached or invalid_input.
create function public.record_tap(p_viewer_id uuid, p_room_id uuid, p_checkin_id uuid)
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

  select count(*) into v_used
    from public.taps
   where from_user = p_viewer_id and room_id = p_room_id and created_at >= private.room_day_start(p_room_id);

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
    perform private.log_activity(p_room_id, 'tap');
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

-- set_choice: save Find or Chat and say what happens next.
-- Find needs a passed location check in the last GEO_FRESHNESS_FOR_GLOW (the server writes
-- location_checks first). Chat, a timeout, or a person no longer checked in opens the chat.
-- Returns { next: "waiting" | "glow" | "chat", reason, matchId, status, yourChoice,
--   otherHasChosen, choiceDeadline, userIds }.
--   next = "glow": call start_glow. reason = "other_location_stale" with next = "waiting":
--   send match.choice to the other person so their app re-sends Find with a fresh fix.
-- Raises not_found, location_required or invalid_input.
create function public.set_choice(p_user_id uuid, p_match_id uuid, p_choice public.match_choice)
returns jsonb
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_m            public.matches;
  v_is_a         boolean;
  v_other        uuid;
  v_other_choice public.match_choice;
begin
  if p_user_id is null or p_match_id is null or p_choice is null then
    perform private.raise_error('invalid_input');
  end if;

  select * into v_m from public.matches where id = p_match_id for update;
  if not found or p_user_id not in (v_m.user_a, v_m.user_b) or v_m.status = 'ended' then
    perform private.raise_error('not_found');
  end if;
  v_is_a  := p_user_id = v_m.user_a;
  v_other := case when v_is_a then v_m.user_b else v_m.user_a end;

  if v_m.status <> 'choosing' then
    return private.choice_json(v_m, p_user_id,
                               case when v_m.status = 'glowing' then 'glow' else 'chat' end, 'already_decided');
  end if;

  if now() >= v_m.choice_deadline then
    update public.matches set status = 'chatting' where id = p_match_id returning * into v_m;
    return private.choice_json(v_m, p_user_id, 'chat', 'timeout');
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
    return private.choice_json(v_m, p_user_id, 'chat', 'chose_chat');
  end if;

  v_other_choice := case when v_is_a then v_m.b_choice else v_m.a_choice end;
  if v_other_choice is null then
    return private.choice_json(v_m, p_user_id, 'waiting', 'other_undecided');
  end if;

  if private.open_checkin(v_m.user_a, v_m.room_id) is null
     or private.open_checkin(v_m.user_b, v_m.room_id) is null then
    update public.matches set status = 'chatting' where id = p_match_id returning * into v_m;
    return private.choice_json(v_m, p_user_id, 'chat', 'not_checked_in');
  end if;

  if not private.location_fresh(v_other, v_m.room_id) then
    return private.choice_json(v_m, p_user_id, 'waiting', 'other_location_stale');
  end if;

  return private.choice_json(v_m, p_user_id, 'glow', 'both_find');
end;
$$;

-- start_glow: pick a color, code word and meeting spot, and start the glow.
-- Color: one no other active glow in the room uses, if any is free. Code word: from
-- p_code_words (lowercase letters, 2 to 16), preferring words no active glow in the room uses;
-- color plus code word is always unique among active glows in the room (a unique partial
-- index backs this up). Meeting spot: the least used one. Idempotent: a match that is already
-- glowing returns its active session.
-- Returns Glow: { id, matchId, roomId, status, color, codeWord, meetingSpot, startedAt, endsAt,
--   endedAt, youMet, theyMet, userIds }.
-- Raises not_found, glow_not_ready (not both Find, or not both checked in with a fresh
-- location check), no_code_word or invalid_input.
create function public.start_glow(p_match_id uuid, p_code_words text[])
returns jsonb
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_m     public.matches;
  v_g     public.glow_sessions;
  v_color public.glow_color;
  v_word  text;
  v_spot  uuid;
begin
  if p_match_id is null or p_code_words is null or cardinality(p_code_words) = 0 then
    perform private.raise_error('invalid_input');
  end if;

  select * into v_m from public.matches where id = p_match_id for update;
  if not found or v_m.status = 'ended' then
    perform private.raise_error('not_found');
  end if;

  if v_m.status = 'glowing' then
    select * into v_g from public.glow_sessions where match_id = p_match_id and status = 'active';
    if found then
      return private.glow_json(v_g);
    end if;
  end if;

  if v_m.status <> 'choosing'
     or v_m.a_choice is distinct from 'find' or v_m.b_choice is distinct from 'find'
     or private.open_checkin(v_m.user_a, v_m.room_id) is null
     or private.open_checkin(v_m.user_b, v_m.room_id) is null
     or not private.location_fresh(v_m.user_a, v_m.room_id)
     or not private.location_fresh(v_m.user_b, v_m.room_id) then
    perform private.raise_error('glow_not_ready');
  end if;

  -- One allocation at a time per room.
  perform pg_advisory_xact_lock(private.lock_key('glow', v_m.room_id));
  perform private.expire_glows(v_m.room_id);

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
    perform private.raise_error('no_code_word');
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

  return private.glow_json(v_g);
end;
$$;

-- glow_met: this person tapped We met. When both have, the glow ends as met and the match is met.
-- A glow whose time ran out is expired instead. Returns Glow from this person's side.
-- Raises not_found.
create function public.glow_met(p_user_id uuid, p_match_id uuid)
returns jsonb
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_m public.matches;
  v_g public.glow_sessions;
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
    return private.glow_json(v_g, p_user_id);
  end if;

  if v_g.ends_at <= now() then
    update public.glow_sessions set status = 'expired', ended_at = ends_at where id = v_g.id returning * into v_g;
    update public.matches set status = 'chatting' where id = p_match_id and status = 'glowing';
    return private.glow_json(v_g, p_user_id);
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

  return private.glow_json(v_g, p_user_id);
end;
$$;

-- cancel_glow: either person ends the glow (Cancel or Switch to chat). The chat opens.
-- Returns Glow from this person's side. Raises not_found.
create function public.cancel_glow(p_user_id uuid, p_match_id uuid)
returns jsonb
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_m public.matches;
  v_g public.glow_sessions;
begin
  select * into v_m from public.matches where id = p_match_id for update;
  if not found or p_user_id is null or p_user_id not in (v_m.user_a, v_m.user_b) or v_m.status = 'ended' then
    perform private.raise_error('not_found');
  end if;

  update public.glow_sessions
     set status = 'canceled', ended_at = now()
   where match_id = p_match_id and status = 'active'
  returning * into v_g;

  if v_g.id is null then
    select * into v_g from public.glow_sessions where match_id = p_match_id order by started_at desc limit 1;
    if not found then
      perform private.raise_error('not_found');
    end if;
  else
    update public.matches set status = 'chatting' where id = p_match_id and status = 'glowing';
  end if;

  return private.glow_json(v_g, p_user_id);
end;
$$;

-- unmatch: end the match for both people and delete the thread.
-- Returns { matchId, roomId, userIds } (send match.ended to both). Raises not_found.
create function public.unmatch(p_user_id uuid, p_match_id uuid)
returns jsonb
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_m public.matches;
begin
  select * into v_m from public.matches where id = p_match_id for update;
  if not found or p_user_id is null or p_user_id not in (v_m.user_a, v_m.user_b) or v_m.status = 'ended' then
    perform private.raise_error('not_found');
  end if;
  perform private.end_match(p_match_id);
  return jsonb_build_object('matchId', v_m.id, 'roomId', v_m.room_id,
                            'userIds', jsonb_build_array(v_m.user_a, v_m.user_b));
end;
$$;

-- block_user: block the person behind a card, match or chat ID (a chat ID is its match ID).
-- Ends any match between the two. Returns { endedMatchIds, roomIds } for match.ended and
-- deck.changed events. Raises not_found or invalid_input.
create function public.block_user(p_user_id uuid, p_context public.report_context, p_context_id uuid)
returns jsonb
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_ctx record;
begin
  if p_user_id is null or p_context is null or p_context_id is null then
    perform private.raise_error('invalid_input');
  end if;
  select * into v_ctx from private.resolve_context(p_user_id, p_context, p_context_id);
  return private.block_pair(p_user_id, v_ctx.o_target_id);
end;
$$;

-- create_report: report the person behind a card, match or chat ID. This also blocks them.
-- For match and chat reports, their last REPORT_EVIDENCE_MESSAGES messages in the thread are
-- kept on the report before the block deletes the thread.
-- Returns { reportId, endedMatchIds, roomIds }. Raises not_found or invalid_input.
create function public.create_report(
  p_reporter_id uuid,
  p_context     public.report_context,
  p_context_id  uuid,
  p_reason      public.report_reason,
  p_details     text default null)
returns jsonb
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_ctx       record;
  v_evidence  jsonb := '[]'::jsonb;
  v_report_id uuid;
  v_block     jsonb;
begin
  if p_reporter_id is null or p_context is null or p_context_id is null or p_reason is null
     or char_length(coalesce(p_details, '')) > private.const('REPORT_DETAILS_MAX_CHARS') then
    perform private.raise_error('invalid_input');
  end if;
  select * into v_ctx from private.resolve_context(p_reporter_id, p_context, p_context_id);

  if v_ctx.o_match_id is not null then
    select coalesce(jsonb_agg(jsonb_build_object('body', x.body, 'createdAt', private.iso(x.created_at)) order by x.created_at),
                    '[]'::jsonb)
      into v_evidence
      from (select m.body, m.created_at
              from public.messages m
             where m.match_id = v_ctx.o_match_id and m.sender_id = v_ctx.o_target_id
             order by m.created_at desc
             limit private.const('REPORT_EVIDENCE_MESSAGES')::integer) x;
  end if;

  insert into public.reports (reporter_id, reported_id, room_id, context, context_id, reason, details, evidence)
  values (p_reporter_id, v_ctx.o_target_id, v_ctx.o_room_id, p_context, p_context_id, p_reason,
          nullif(btrim(p_details), ''), v_evidence)
  returning id into v_report_id;

  if v_ctx.o_room_id is not null then
    perform private.log_activity(v_ctx.o_room_id, 'report');
  end if;

  v_block := private.block_pair(p_reporter_id, v_ctx.o_target_id);
  return v_block || jsonb_build_object('reportId', v_report_id);
end;
$$;

-- send_message: add a chat message. The chat opens once choosing is over (glowing, chatting
-- or met). A retry with the same client ID returns the first message.
-- Returns { id, matchId, body, moderation, createdAt, clientId, recipientId }.
-- Raises not_found (no match, not yours, or ended), chat_not_open or invalid_input.
create function public.send_message(p_sender_id uuid, p_match_id uuid, p_body text, p_client_id uuid default null)
returns jsonb
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_m   public.matches;
  v_msg public.messages;
begin
  if p_sender_id is null or p_match_id is null or p_body is null
     or char_length(btrim(p_body)) = 0 or char_length(p_body) > private.const('MESSAGE_MAX_CHARS') then
    perform private.raise_error('invalid_input');
  end if;

  -- FOR SHARE: a block or unmatch (FOR UPDATE) waits for this send, or this send waits for it.
  select * into v_m from public.matches where id = p_match_id for share;
  if not found or p_sender_id not in (v_m.user_a, v_m.user_b) or v_m.status = 'ended' then
    perform private.raise_error('not_found');
  end if;
  if v_m.status = 'choosing' then
    perform private.raise_error('chat_not_open');
  end if;

  insert into public.messages (match_id, sender_id, body, client_id)
  values (p_match_id, p_sender_id, p_body, p_client_id)
  on conflict (match_id, sender_id, client_id) where client_id is not null do nothing
  returning * into v_msg;

  if v_msg.id is null then
    select * into v_msg from public.messages
     where match_id = p_match_id and sender_id = p_sender_id and client_id = p_client_id;
  end if;

  return jsonb_strip_nulls(jsonb_build_object(
    'id',          v_msg.id,
    'matchId',     v_msg.match_id,
    'body',        v_msg.body,
    'moderation',  v_msg.moderation,
    'createdAt',   private.iso(v_msg.created_at),
    'clientId',    v_msg.client_id,
    'recipientId', case when p_sender_id = v_m.user_a then v_m.user_b else v_m.user_a end));
end;
$$;

-- purge_expired: called by the cron route every PURGE_INTERVAL.
-- Ends timed-out glows and choices, marks check-ins that end within CHECKIN_EXPIRY_WARNING
-- (once each), and deletes expired and left check-ins, old taps, ended glows, old card views
-- and old location checks.
-- Returns { cardPaths: [room-cards object names to delete now], expiringCheckins: [{ userId,
--   roomId, checkinId }], endedGlows: [{ matchId, userIds }], choiceTimeouts: [{ matchId,
--   userIds }], deleted: { checkins, taps, glowSessions, cardViews, locationChecks } }.
create function public.purge_expired()
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

  return jsonb_build_object(
    'cardPaths',        to_jsonb(v_paths),
    'expiringCheckins', v_expiring,
    'endedGlows',       v_ended_glows,
    'choiceTimeouts',   v_timeouts,
    'deleted',          jsonb_build_object('checkins', v_checkins, 'taps', v_taps, 'glowSessions', v_glows,
                                           'cardViews', v_views, 'locationChecks', v_checks));
end;
$$;

-- get_room_state: the room, my open check-in there (or null), and my taps and card views left
-- today. Returns { room: { id, slug, name, status, startsAt, endsAt }, checkin: Checkin | null,
--   tapsLeftToday, viewsLeftToday }. Raises not_found if the room doesn't exist.
create function public.get_room_state(p_user_id uuid, p_room_id uuid)
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

  select count(*) into v_taps from public.taps t
   where t.from_user = p_user_id and t.room_id = p_room_id and t.created_at >= private.room_day_start(p_room_id);
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

-- get_match: one match from this person's side, after applying any timeout (choice window or
-- glow time). Returns MatchDetail plus userIds (server only). Raises not_found for ended
-- matches and matches the person isn't in (P11).
create function public.get_match(p_user_id uuid, p_match_id uuid)
returns jsonb
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_m public.matches;
begin
  select * into v_m from public.matches where id = p_match_id for update;
  if not found or p_user_id is null or p_user_id not in (v_m.user_a, v_m.user_b) or v_m.status = 'ended' then
    perform private.raise_error('not_found');
  end if;
  v_m := private.settle_match(p_match_id);
  return private.match_json(v_m, p_user_id);
end;
$$;

-- list_matches: my matches that haven't ended, newest first, after applying timeouts.
-- Returns { matches: [MatchDetail plus userIds] }.
create function public.list_matches(p_user_id uuid)
returns jsonb
language plpgsql volatile security definer
set search_path = ''
as $$
declare
  v_id     uuid;
  v_result jsonb;
begin
  for v_id in
    select m.id from public.matches m
     where (m.user_a = p_user_id or m.user_b = p_user_id) and m.status in ('choosing', 'glowing')
     order by m.id
       for update
  loop
    perform private.settle_match(v_id);
  end loop;

  select coalesce(jsonb_agg(private.match_json(m, p_user_id) order by m.created_at desc), '[]'::jsonb)
    into v_result
    from public.matches m
   where (m.user_a = p_user_id or m.user_b = p_user_id) and m.status <> 'ended';
  return jsonb_build_object('matches', v_result);
end;
$$;

-- match_photo_path: the profile-photos object name of the other person's nth approved photo
-- (0-based, by position), for a match that hasn't ended. Raises not_found otherwise (P1, P11).
create function public.match_photo_path(p_viewer_id uuid, p_match_id uuid, p_n integer)
returns text
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_m    public.matches;
  v_path text;
begin
  select * into v_m from public.matches where id = p_match_id;
  if not found or p_viewer_id is null or p_viewer_id not in (v_m.user_a, v_m.user_b)
     or v_m.status = 'ended' or p_n is null or p_n < 0 then
    perform private.raise_error('not_found');
  end if;
  select pp.path into v_path
    from public.profile_photos pp
   where pp.user_id = case when p_viewer_id = v_m.user_a then v_m.user_b else v_m.user_a end
     and pp.moderation_status = 'approved'
   order by pp.position
   offset p_n limit 1;
  if v_path is null then
    perform private.raise_error('not_found');
  end if;
  return v_path;
end;
$$;

-------------------------------------------------------------------------------
-- Realtime authorization
-- Private channels only. A person may receive broadcasts on user:{their id} (lowercase UUID),
-- and on room:{id} only while they have an open check-in there. Nobody may send from the app
-- (no INSERT policy), and presence is never allowed, so a room never lists who is in it.
-------------------------------------------------------------------------------

create function private.can_receive_topic(p_topic text)
returns boolean
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null or p_topic is null then
    return false;
  end if;
  if p_topic = 'user:' || v_uid::text then
    return true;
  end if;
  if p_topic ~ '^room:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return private.open_checkin(v_uid, substr(p_topic, 6)::uuid) is not null;
  end if;
  return false;
end;
$$;

create policy glow_receive_own_broadcasts
  on realtime.messages
  for select
  to authenticated
  using (
    realtime.messages.extension = 'broadcast'
    and private.can_receive_topic((select realtime.topic()))
  );

-------------------------------------------------------------------------------
-- Storage: private buckets, no policies. Only the server reads or writes objects, and every
-- image is served through an API route that checks the viewer (P4).
-------------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('profile-photos', 'profile-photos', false, private.const('PHOTO_MAX_BYTES')::bigint, array['image/jpeg']),
  ('room-cards',     'room-cards',     false, private.const('PHOTO_MAX_BYTES')::bigint, array['image/jpeg'])
on conflict (id) do update
  set public             = false,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-------------------------------------------------------------------------------
-- Grants. anon and authenticated get nothing in public or private (except the one Realtime
-- helper). Default privileges make later migrations' tables and functions closed too.
-------------------------------------------------------------------------------

revoke all on all tables    in schema public  from anon, authenticated;
revoke all on all sequences in schema public  from anon, authenticated;
revoke all on all functions in schema public  from public, anon, authenticated;
revoke all on all tables    in schema private from public, anon, authenticated;
revoke all on all sequences in schema private from public, anon, authenticated;
revoke all on all functions in schema private from public, anon, authenticated;

alter default privileges in schema public  revoke all on tables    from anon, authenticated;
alter default privileges in schema public  revoke all on sequences from anon, authenticated;
alter default privileges in schema public  revoke all on functions from public, anon, authenticated;
alter default privileges in schema private revoke all on tables    from public, anon, authenticated;
alter default privileges in schema private revoke all on functions from public, anon, authenticated;

grant all     on all tables    in schema public  to service_role;
grant all     on all sequences in schema public  to service_role;
grant execute on all functions in schema public  to service_role;
grant select  on all tables    in schema private to service_role;
grant execute on all functions in schema private to service_role;

grant execute on function private.can_receive_topic(text) to authenticated;
