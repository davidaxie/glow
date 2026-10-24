-- A2 · Checkpoint 1 fixes (0002_a2_checkpoint1.sql), one block per fix.
begin;
create extension if not exists pgtap with schema extensions;
select plan(44);

-- Test helpers (rolled back with everything else) --------------------------------------------
create schema tests;
create function tests.person(p_name text, p_gender public.gender, p_show_me public.gender[])
returns uuid language plpgsql as $$
declare v_id uuid := gen_random_uuid();
begin
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                          raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated',
          'pgtap-' || v_id || '@glow.test', '', now(), '{}', '{}', now(), now());
  update public.profiles
     set first_name = p_name, birthdate = date '1996-05-05', gender = p_gender, show_me = p_show_me,
         onboarding_step = 'complete'
   where id = v_id;
  return v_id;
end $$;
create function tests.room(p_slug text) returns uuid language plpgsql as $$
declare v_id uuid;
begin
  insert into public.rooms (slug, name, lat, lng, starts_at, ends_at)
  values (p_slug, 'Test room ' || p_slug, 37.80, -122.45, now() - interval '1 hour', now() + interval '2 days')
  returning id into v_id;
  insert into public.meeting_spots (room_id, name, sort) values (v_id, 'Spot A', 0), (v_id, 'Spot B', 1), (v_id, 'Spot C', 2);
  return v_id;
end $$;
create function tests.check_in(p_user uuid, p_room uuid, p_tags jsonb default '{"topColor": "blue"}')
returns uuid language plpgsql as $$
declare v_id uuid := gen_random_uuid();
begin
  -- The join route's passed location check, which create_checkin requires.
  insert into public.location_checks (user_id, room_id, purpose, result, accuracy_bucket)
  values (p_user, p_room, 'join', 'pass', 'under_20m');
  perform public.create_checkin(p_user, p_room, v_id, p_room::text || '/' || v_id::text || '.jpg', p_tags);
  return v_id;
end $$;
create function tests.deck(p_viewer uuid, p_room uuid) returns uuid[] language plpgsql as $$
declare v_page jsonb; v_offset integer := 0; v_ids uuid[] := '{}';
begin
  loop
    v_page := public.get_deck(p_viewer, p_room, '{}', null, v_offset);
    v_ids := v_ids || array(select (c ->> 'id')::uuid from jsonb_array_elements(v_page -> 'cards') c);
    exit when not coalesce((v_page ->> 'hasMore')::boolean, false);
    v_offset := (v_page ->> 'nextOffset')::integer;
  end loop;
  return v_ids;
end $$;
create temporary table ids (k text primary key, v uuid);
create function tests.id(p_key text) returns uuid language sql as $$ select v from ids where k = p_key $$;
create function tests.put(p_key text, p_value uuid) returns uuid language sql as $$
  insert into ids values (p_key, p_value) returning v $$;
create function tests.located(p_user uuid, p_room uuid, p_ago interval default '0 seconds') returns void language sql as $$
  insert into public.location_checks (user_id, room_id, purpose, result, accuracy_bucket, created_at)
  values (p_user, p_room, 'find', 'pass', 'under_20m', now() - p_ago) $$;
-- A checked-in pair with a fresh match whose join checks were minutes ago.
create function tests.pair(p_key text, p_room uuid) returns uuid language plpgsql as $$
declare a uuid := tests.person(p_key || ' A', 'woman', '{man}'); b uuid := tests.person(p_key || ' B', 'man', '{woman}'); m uuid;
begin
  perform tests.check_in(a, p_room);
  perform tests.check_in(b, p_room);
  update public.location_checks set created_at = now() - interval '5 minutes' where user_id in (a, b);
  insert into public.matches (room_id, user_a, user_b, choice_deadline)
  values (p_room, least(a, b), greatest(a, b), now() + interval '10 minutes') returning id into m;
  perform tests.put(p_key, m);
  perform tests.put(p_key || '_a', least(a, b));
  perform tests.put(p_key || '_b', greatest(a, b));
  return m;
end $$;

select tests.put('r', tests.room('cp1-r'));

-- 1. service_role can use what later migrations create ----------------------------------------
create table public.pgtap_later (id bigint generated always as identity primary key, note text);
create sequence public.pgtap_later_seq;
create function public.pgtap_later_fn() returns integer language sql as $$ select 42 $$;
create table private.pgtap_later_private (id integer);
create function private.pgtap_later_helper() returns integer language sql as $$ select 7 $$;

select ok(has_table_privilege('service_role', 'public.pgtap_later', 'SELECT')
          and has_table_privilege('service_role', 'public.pgtap_later', 'INSERT')
          and has_table_privilege('service_role', 'public.pgtap_later', 'UPDATE')
          and has_table_privilege('service_role', 'public.pgtap_later', 'DELETE'),
          'service_role can read and write a table a later migration adds');
select ok(has_sequence_privilege('service_role', 'public.pgtap_later_seq', 'USAGE'),
          'and use its sequences');
select ok(has_function_privilege('service_role', 'public.pgtap_later_fn()', 'EXECUTE')
          and has_function_privilege('service_role', 'private.pgtap_later_helper()', 'EXECUTE')
          and has_table_privilege('service_role', 'private.pgtap_later_private', 'SELECT'),
          'and call its functions, in public and private');
set local role service_role;
select lives_ok($$ insert into public.pgtap_later (note) values ('from a route') $$,
                'as service_role, inserting into the new table works');
select is((select public.pgtap_later_fn()), 42, 'as service_role, calling the new function works');
reset role;
select ok(not has_table_privilege('anon', 'public.pgtap_later', 'SELECT, INSERT, UPDATE, DELETE')
          and not has_table_privilege('authenticated', 'public.pgtap_later', 'SELECT, INSERT, UPDATE, DELETE')
          and not has_sequence_privilege('authenticated', 'public.pgtap_later_seq', 'USAGE, SELECT, UPDATE'),
          'clients still get nothing on new tables and sequences');
select ok(not has_function_privilege('anon', 'public.pgtap_later_fn()', 'EXECUTE')
          and not has_function_privilege('authenticated', 'public.pgtap_later_fn()', 'EXECUTE'),
          'clients still can''t call new functions');

-- 2. Find re-send: set_choice names who needs match.recheck -------------------------------------
select tests.pair('rc', tests.id('r'));
select tests.located(tests.id('rc_a'), tests.id('r'));
select public.set_choice(tests.id('rc_a'), tests.id('rc'), 'find');
update public.location_checks set created_at = now() - interval '3 minutes' where user_id = tests.id('rc_a');
select tests.located(tests.id('rc_b'), tests.id('r'));
create temporary table recheck as select public.set_choice(tests.id('rc_b'), tests.id('rc'), 'find') as result;
select is((select result ->> 'reason' from recheck), 'other_location_stale', 'the first chooser''s check went stale');
select is((select result -> 'recheckUserIds' from recheck), jsonb_build_array(tests.id('rc_a')),
          'set_choice names who to send match.recheck to: the person whose check is stale');

-- 3. start_glow opens the chat instead of leaving the match stuck ----------------------------------
select tests.pair('nc', tests.id('r'));
select tests.located(tests.id('nc_a'), tests.id('r'));
select tests.located(tests.id('nc_b'), tests.id('r'));
select public.set_choice(tests.id('nc_a'), tests.id('nc'), 'find');
select public.set_choice(tests.id('nc_b'), tests.id('nc'), 'find');
update public.checkins set left_at = now() where user_id = tests.id('nc_a');
create temporary table no_glow as select public.start_glow(tests.id('nc'), '{otter}') as result;
select is((select (result ->> 'result') || '/' || (result ->> 'reason') from no_glow), 'chat/not_checked_in',
          'start_glow answers chat instead of raising when someone left the room');
select is((select status::text from public.matches where id = tests.id('nc')), 'chatting',
          'and the match is chatting, not stuck in choosing');
select lives_ok(format($$ select public.send_message(%L, %L, 'shall we chat?', null) $$, tests.id('nc_b'), tests.id('nc')),
                'so the chat works right away');
select is(public.set_choice(tests.id('nc_b'), tests.id('nc'), 'find') ->> 'next', 'chat',
          'and set_choice stops answering glow');
select tests.pair('ls', tests.id('r'));
select tests.located(tests.id('ls_a'), tests.id('r'));
select tests.located(tests.id('ls_b'), tests.id('r'));
select public.set_choice(tests.id('ls_a'), tests.id('ls'), 'find');
select public.set_choice(tests.id('ls_b'), tests.id('ls'), 'find');
update public.location_checks set created_at = now() - interval '3 minutes' where user_id = tests.id('ls_b');
select is((select (r ->> 'result') || ' ' || (r -> 'staleUserIds')::text || ' ' || (r ->> 'status')
             from (select public.start_glow(tests.id('ls'), '{otter}') as r) x),
          'waiting ' || jsonb_build_array(tests.id('ls_b'))::text || ' choosing',
          'a stale location check makes start_glow wait and name who to recheck, changing nothing');

-- 4. create_checkin needs a passed join check ------------------------------------------------------
select tests.put('cj', tests.person('Cee', 'woman', '{man}'));
create function tests.checkin_sql(p_user uuid, p_room uuid) returns text language sql as $$
  select format($f$ select public.create_checkin(%L, %L, %L, %L, '{"topColor": "blue"}') $f$,
                p_user, p_room, 'd0d0d0d0-0000-4000-8000-000000000001',
                p_room::text || '/d0d0d0d0-0000-4000-8000-000000000001.jpg') $$;
select throws_ok(tests.checkin_sql(tests.id('cj'), tests.id('r')), 'P0001', 'location_required',
                 'a QR code alone can''t make a card: no location check, no check-in');
insert into public.location_checks (user_id, room_id, purpose, result, accuracy_bucket)
values (tests.id('cj'), tests.id('r'), 'join', 'fail', 'over_500m');
select throws_ok(tests.checkin_sql(tests.id('cj'), tests.id('r')), 'P0001', 'location_required', 'a failed check doesn''t count');
insert into public.location_checks (user_id, room_id, purpose, result, accuracy_bucket, created_at)
values (tests.id('cj'), tests.id('r'), 'join', 'pass', 'under_20m', now() - interval '11 minutes');
select throws_ok(tests.checkin_sql(tests.id('cj'), tests.id('r')), 'P0001', 'location_required',
                 'a pass older than JOIN_TICKET_TTL (10 minutes) doesn''t count');
insert into public.location_checks (user_id, room_id, purpose, result, accuracy_bucket)
values (tests.id('cj'), tests.id('r'), 'find', 'pass', 'under_20m');
select throws_ok(tests.checkin_sql(tests.id('cj'), tests.id('r')), 'P0001', 'location_required',
                 'a Find check isn''t a join check');
insert into public.location_checks (user_id, room_id, purpose, result)
values (tests.id('cj'), tests.id('r'), 'join', 'demo_skip');
select lives_ok(tests.checkin_sql(tests.id('cj'), tests.id('r')), 'a demo-mode skip by an admin counts as a pass');

-- 5. complete_onboarding --------------------------------------------------------------------------
select tests.put('ob', tests.person('Obi', 'man', '{woman}'));
update public.profiles set onboarding_step = 'notifications' where id = tests.id('ob');
select throws_ok(format('select public.complete_onboarding(%L)', tests.id('ob')), 'P0001', 'onboarding_incomplete',
                 'onboarding can''t finish without an approved photo');
insert into public.profile_photos (id, user_id, path, position, moderation_status)
values ('e0e0e0e0-0000-4000-8000-000000000001', tests.id('ob'), tests.id('ob') || '/e0e0e0e0-0000-4000-8000-000000000001.jpg', 0, 'held');
select throws_ok(format('select public.complete_onboarding(%L)', tests.id('ob')), 'P0001', 'onboarding_incomplete',
                 'a photo held for review (possibly under 18) doesn''t count (P10)');
update public.profile_photos set moderation_status = 'approved' where id = 'e0e0e0e0-0000-4000-8000-000000000001';
select is(public.complete_onboarding(tests.id('ob')) ->> 'onboardingStep', 'complete',
          'with an approved photo, onboarding finishes from the notifications step, push or no push');
select is((select onboarding_step::text from public.profiles where id = tests.id('ob')), 'complete', 'and it''s stored');
select is(public.complete_onboarding(tests.id('ob')) ->> 'onboardingStep', 'complete', 'calling it again is harmless');
select tests.put('ob2', tests.person('Ola', 'woman', '{man}'));
update public.profiles set onboarding_step = 'photos', first_name = null where id = tests.id('ob2');
insert into public.profile_photos (id, user_id, path, position, moderation_status)
values ('e0e0e0e0-0000-4000-8000-000000000002', tests.id('ob2'), tests.id('ob2') || '/e0e0e0e0-0000-4000-8000-000000000002.jpg', 0, 'approved');
select throws_ok(format('select public.complete_onboarding(%L)', tests.id('ob2')), 'P0001', 'onboarding_incomplete',
                 'onboarding can''t finish with the profile unfilled');
update public.profiles set banned_at = now(), first_name = 'Ola' where id = tests.id('ob2');
select throws_ok(format('select public.complete_onboarding(%L)', tests.id('ob2')), 'P0001', 'not_found',
                 'banned people can''t finish onboarding');

-- 6. Lazy timeouts are reported, so the caller can notify -----------------------------------------
select tests.pair('lt', tests.id('r'));
update public.matches set choice_deadline = now() - interval '1 second' where id = tests.id('lt');
select is((select jsonb_agg(e ->> 'kind') from jsonb_array_elements(public.get_match(tests.id('lt_a'), tests.id('lt')) -> 'settled') e),
          '["choice_timeout"]'::jsonb, 'get_match reports the choice timeout it applied');
select is(public.get_match(tests.id('lt_a'), tests.id('lt')) -> 'settled', '[]'::jsonb, 'only once');
select is((select (p -> 'choiceTimeouts') from (select public.purge_expired() as p) x), '[]'::jsonb,
          'purge then skips it, which is why the route that settled it must notify');
select tests.pair('lt2', tests.id('r'));
update public.matches set choice_deadline = now() - interval '1 second' where id = tests.id('lt2');
select is((select jsonb_agg(e ->> 'matchId') from jsonb_array_elements(public.list_matches(tests.id('lt2_b')) -> 'settled') e),
          jsonb_build_array(tests.id('lt2')), 'list_matches reports what it settled');
select tests.pair('lt3', tests.id('r'));
update public.matches set choice_deadline = now() - interval '1 second' where id = tests.id('lt3');
select is((select (r ->> 'reason') || ' ' || (r -> 'settled' -> 0 ->> 'kind')
             from (select public.set_choice(tests.id('lt3_a'), tests.id('lt3'), 'chat') as r) x),
          'timeout choice_timeout', 'set_choice reports the timeout in settled too');
-- Two glows in one room: one ran out. glow_met on it, and start_glow for a third pair, both report it.
select tests.pair('g1', tests.id('r'));
select tests.located(tests.id('g1_a'), tests.id('r'));
select tests.located(tests.id('g1_b'), tests.id('r'));
select public.set_choice(tests.id('g1_a'), tests.id('g1'), 'find');
select public.set_choice(tests.id('g1_b'), tests.id('g1'), 'find');
select public.start_glow(tests.id('g1'), '{otter}');
update public.glow_sessions set started_at = now() - interval '16 minutes', ends_at = now() - interval '1 minute'
 where match_id = tests.id('g1');
select tests.pair('g2', tests.id('r'));
select tests.located(tests.id('g2_a'), tests.id('r'));
select tests.located(tests.id('g2_b'), tests.id('r'));
select public.set_choice(tests.id('g2_a'), tests.id('g2'), 'find');
select public.set_choice(tests.id('g2_b'), tests.id('g2'), 'find');
create temporary table g2_start as select public.start_glow(tests.id('g2'), '{otter,maple}') as result;
select is((select (result ->> 'result') || ' ' || (result -> 'settled' -> 0 ->> 'matchId') || ' ' || (result -> 'settled' -> 0 ->> 'kind')
             from g2_start),
          'started ' || tests.id('g1')::text || ' glow_expired',
          'start_glow reports another pair''s glow it ended by time, for glow.ended');
select tests.pair('g3', tests.id('r'));
select tests.located(tests.id('g3_a'), tests.id('r'));
select tests.located(tests.id('g3_b'), tests.id('r'));
select public.set_choice(tests.id('g3_a'), tests.id('g3'), 'find');
select public.set_choice(tests.id('g3_b'), tests.id('g3'), 'find');
select public.start_glow(tests.id('g3'), '{comet}');
update public.glow_sessions set started_at = now() - interval '16 minutes', ends_at = now() - interval '1 minute'
 where match_id = tests.id('g3');
select is((select (r ->> 'status') || ' ' || (r -> 'settled' -> 0 ->> 'kind') from (select public.glow_met(tests.id('g3_a'), tests.id('g3')) as r) x),
          'expired glow_expired', 'glow_met reports a glow it found expired');

-- 7. Taps never reach the metrics (P5) -------------------------------------------------------------
select tests.put('tm', tests.room('cp1-taps'));
select tests.put('tm_a', tests.person('Tia', 'woman', '{man}'));
select tests.put('tm_b', tests.person('Tom', 'man', '{woman}'));
select tests.put('tm_b_card', tests.check_in(tests.id('tm_b'), tests.id('tm')));
select tests.check_in(tests.id('tm_a'), tests.id('tm'));
select count(*) from unnest(tests.deck(tests.id('tm_a'), tests.id('tm')));
select public.record_tap(tests.id('tm_a'), tests.id('tm'), tests.id('tm_b_card'));
select is((select count(*)::integer from public.room_activity where room_id = tests.id('tm') and kind = 'tap'), 0,
          'a tap leaves no activity row, so no metric can time a one-sided tap');
select throws_ok($$ insert into public.room_activity (room_id, kind) select id, 'tap' from public.rooms limit 1 $$,
                 '23514', null, 'and no tap activity row can be written at all');

-- 8. Today's taps are counted apart from the per-pair tap row ---------------------------------------
select tests.put('rt', tests.room('cp1-retap'));
select tests.put('ana', tests.person('Ana', 'woman', '{man}'));
select tests.put('ana_card', tests.check_in(tests.id('ana'), tests.id('rt')));
select tests.put('bo', tests.person('Bo', 'man', '{woman}'));
select tests.put('bo_card', tests.check_in(tests.id('bo'), tests.id('rt')));
select tests.put('cy', tests.person('Cy', 'man', '{woman}'));
select tests.put('cy_card', tests.check_in(tests.id('cy'), tests.id('rt')));
select tests.put('di', tests.person('Di', 'man', '{woman}'));
select tests.put('di_card', tests.check_in(tests.id('di'), tests.id('rt')));
select count(*) from unnest(tests.deck(tests.id('ana'), tests.id('rt')));
select count(*) from unnest(tests.deck(tests.id('bo'), tests.id('rt')));
select public.record_tap(tests.id('ana'), tests.id('rt'), tests.id('bo_card'));
select public.record_tap(tests.id('ana'), tests.id('rt'), tests.id('cy_card'));
select tests.put('m_ab', (public.record_tap(tests.id('bo'), tests.id('rt'), tests.id('ana_card')) ->> 'matchId')::uuid);
select public.unmatch(tests.id('ana'), tests.id('m_ab'));
select is(public.record_tap(tests.id('ana'), tests.id('rt'), tests.id('bo_card')) ->> 'tapsLeftToday', '0',
          'a re-tap after an unmatch is a new tap: its reply counts it exactly (3 of 3 used)');
select is(public.get_room_state(tests.id('ana'), tests.id('rt')) ->> 'tapsLeftToday', '0', 'and the room state agrees');
select throws_ok(format('select public.record_tap(%L, %L, %L)', tests.id('ana'), tests.id('rt'), tests.id('di_card')),
                 'P0001', 'tap_limit_reached', 'so a fourth tap that day is refused');
select is(public.record_tap(tests.id('ana'), tests.id('rt'), tests.id('cy_card')) ->> 'result', 'sent',
          'tapping someone you already tapped is still free at the cap');

-- 9. The deck after purge ----------------------------------------------------------------------------
select tests.put('dp', tests.room('cp1-purge'));
select tests.put('dp_v', tests.person('Dot', 'woman', '{man}'));
select tests.put('dp_card', tests.check_in(tests.id('dp_v'), tests.id('dp')));
update public.checkins set joined_at = now() - interval '4 hours', expires_at = now() - interval '1 minute'
 where id = tests.id('dp_card');
select public.purge_expired();
select is((select count(*)::integer from public.checkins where id = tests.id('dp_card')), 0, 'purge deleted the expired check-in');
select is(public.get_deck(tests.id('dp_v'), tests.id('dp')) ->> 'emptyReason', 'checkin_ended',
          'the same day, the deck still says your check-in ended instead of not found');
select throws_ok(format('select public.get_deck(%L, %L)', tests.id('dp_v'), tests.id('rt')), 'P0001', 'not_found',
                 'a room you never checked in to is not found');
select throws_ok(format('select public.get_deck(%L, %L)', tests.id('dp_v'), 'f0f0f0f0-0000-4000-8000-000000000002'),
                 'P0001', 'not_found', 'a room that doesn''t exist is not found');
update public.room_days set day = day - 1 where user_id = tests.id('dp_v') and room_id = tests.id('dp');
select throws_ok(format('select public.get_deck(%L, %L)', tests.id('dp_v'), tests.id('dp')), 'P0001', 'not_found',
                 'a check-in from an earlier day, already purged, is not found');

select * from finish();
rollback;
