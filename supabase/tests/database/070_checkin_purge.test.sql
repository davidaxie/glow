-- A2 · Check-ins (one active per person per room, CHECKIN_TTL), the 18+ rule (P10), and expiry
-- cleanup through purge_expired (P9).
begin;
create extension if not exists pgtap with schema extensions;
select plan(35);

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
create function tests.room(p_slug text, p_ends interval default '2 days') returns uuid language plpgsql as $$
declare v_id uuid;
begin
  insert into public.rooms (slug, name, lat, lng, starts_at, ends_at)
  values (p_slug, 'Test room ' || p_slug, 37.80, -122.45, now() - interval '1 hour', now() + p_ends)
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
create temporary table ids (k text primary key, v uuid);
create function tests.id(p_key text) returns uuid language sql as $$ select v from ids where k = p_key $$;
create function tests.put(p_key text, p_value uuid) returns uuid language sql as $$
  insert into ids values (p_key, p_value) returning v $$;
create function tests.path(p_card text) returns text language sql as $$
  select card_path from public.checkins where id = tests.id(p_card) $$;

select tests.put('r', tests.room('ci-r'));
select tests.put('s', tests.room('ci-s'));
select tests.put('short', tests.room('ci-short', '1 hour'));
select tests.put('ann', tests.person('Ann', 'woman', '{man}'));

-- create_checkin ---------------------------------------------------------------------------------
select tests.put('c1', tests.check_in(tests.id('ann'), tests.id('r')));
select is((select expires_at - joined_at from public.checkins where id = tests.id('c1')), interval '3 hours',
          'a check-in lasts CHECKIN_TTL (3 hours)');
create temporary table second_checkin as
  select public.create_checkin(tests.id('ann'), tests.id('r'), 'c2c2c2c2-0000-4000-8000-000000000001',
                               tests.id('r')::text || '/c2c2c2c2-0000-4000-8000-000000000001.jpg', '{"topColor": "red"}') as result;
select is((select count(*)::integer from public.checkins
            where user_id = tests.id('ann') and room_id = tests.id('r') and left_at is null), 1,
          'checking in again leaves exactly one active check-in in that room');
select ok((select left_at is not null from public.checkins where id = tests.id('c1')), 'the older check-in ended');
select is((select result -> 'replacedCardPaths' from second_checkin), jsonb_build_array(tests.path('c1')),
          'and its photo path comes back, to delete now');
select is((select result -> 'checkin' ->> 'id' from second_checkin),
          (public.create_checkin(tests.id('ann'), tests.id('r'), 'c2c2c2c2-0000-4000-8000-000000000001',
                                 tests.id('r')::text || '/c2c2c2c2-0000-4000-8000-000000000001.jpg', '{"topColor": "red"}')
             -> 'checkin' ->> 'id'),
          'retrying with the same card ID returns the same check-in');
select tests.put('cs', tests.check_in(tests.id('ann'), tests.id('s')));
select is((select count(*)::integer from public.checkins where user_id = tests.id('ann') and left_at is null), 2,
          'a check-in in another room is separate');
select throws_ok(format($$ insert into public.checkins (id, room_id, user_id, card_path, top_color, expires_at)
                          values ('c3c3c3c3-0000-4000-8000-000000000001', %L, %L, %L, 'blue', now() + interval '1 hour') $$,
                        tests.id('r'), tests.id('ann'), tests.id('r')::text || '/c3c3c3c3-0000-4000-8000-000000000001.jpg'),
                 '23505', null, 'a unique index backs up one active check-in per person per room');
select tests.put('cshort', tests.check_in(tests.id('ann'), tests.id('short')));
select is((select c.expires_at = r.ends_at from public.checkins c join public.rooms r on r.id = c.room_id
            where c.id = tests.id('cshort')), true,
          'a check-in never outlasts its room');
select is((select result -> 'checkin' -> 'tags' from second_checkin), '{"topColor": "red", "extras": []}'::jsonb,
          'missing tags are left out, never null');
select ok((select (result -> 'checkin' ->> 'expiresAt') ~ '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$' from second_checkin),
          'times come back as RFC 3339 UTC with milliseconds');

select throws_ok(format('select tests.check_in(%L, %L, %L)', tests.id('ann'), tests.id('r'), '{"hairColor": "brown"}'),
                 'P0001', 'invalid_input', 'a top color is required');
select throws_ok(format('select tests.check_in(%L, %L, %L)', tests.id('ann'), tests.id('r'), '{"topColor": "tartan"}'),
                 'P0001', 'invalid_input', 'unknown tag values are invalid input');
select throws_ok(format($$ select public.create_checkin(%L, %L, gen_random_uuid(), 'somewhere/else.jpg', '{"topColor": "blue"}') $$,
                        tests.id('ann'), tests.id('r')),
                 'P0001', 'invalid_input', 'the card path must be room-cards/{roomId}/{cardId}.jpg');
select throws_ok(format($$ select public.create_checkin(%L, 'f0f0f0f0-0000-4000-8000-000000000001',
                                 'c4c4c4c4-0000-4000-8000-000000000001',
                                 'f0f0f0f0-0000-4000-8000-000000000001/c4c4c4c4-0000-4000-8000-000000000001.jpg',
                                 '{"topColor": "blue"}') $$, tests.id('ann')),
                 'P0001', 'not_found', 'an unknown room is not found');
update public.rooms set status = 'paused' where id = tests.id('s');
select throws_ok(format('select tests.check_in(%L, %L)', tests.id('ann'), tests.id('s')), 'P0001', 'room_not_live',
                 'a paused room takes no check-ins');
update public.rooms set status = 'live', starts_at = now() + interval '1 hour' where id = tests.id('s');
select throws_ok(format('select tests.check_in(%L, %L)', tests.id('ann'), tests.id('s')), 'P0001', 'room_not_live',
                 'a room that hasn''t started takes no check-ins');
select tests.put('newbie', tests.person('Newbie', 'man', '{woman}'));
update public.profiles set onboarding_step = 'photos' where id = tests.id('newbie');
select throws_ok(format('select tests.check_in(%L, %L)', tests.id('newbie'), tests.id('r')), 'P0001', 'onboarding_incomplete',
                 'people who haven''t finished onboarding can''t check in');
select tests.put('banned', tests.person('Banned', 'man', '{woman}'));
update public.profiles set banned_at = now() where id = tests.id('banned');
select throws_ok(format('select tests.check_in(%L, %L)', tests.id('banned'), tests.id('r')), 'P0001', 'not_found',
                 'banned people can''t check in');

-- 18 and over (P10) ----------------------------------------------------------------------------------
select throws_ok(format($$ update public.profiles set birthdate = (current_date - interval '17 years')::date where id = %L $$,
                        tests.id('ann')), 'P0001', 'under_18', 'a birthdate under 18 is refused');
select throws_ok(format($$ update public.profiles
                           set birthdate = ((now() at time zone 'Etc/GMT+12')::date - interval '18 years' + interval '1 day')::date
                           where id = %L $$, tests.id('ann')),
                 'P0001', 'under_18', 'turning 18 tomorrow anywhere on Earth is still under 18');
select lives_ok(format($$ update public.profiles
                          set birthdate = ((now() at time zone 'Etc/GMT+12')::date - interval '18 years')::date
                          where id = %L $$, tests.id('ann')),
                'turning 18 today everywhere is allowed');
select throws_ok(format($$ update public.profiles set first_name = null where id = %L $$, tests.id('ann')),
                 '23514', null, 'a finished profile always has a first name, birthday, gender and show me');

-- purge_expired (P9) --------------------------------------------------------------------------------
select tests.put('p', tests.room('ci-purge'));
select tests.put('x', tests.person('Xan', 'man', '{woman}'));
select tests.put('y', tests.person('Yul', 'man', '{woman}'));
select tests.put('z', tests.person('Zed', 'man', '{woman}'));
select tests.put('w', tests.person('Wes', 'man', '{woman}'));
select tests.put('xc', tests.check_in(tests.id('x'), tests.id('p')));
select tests.put('yc', tests.check_in(tests.id('y'), tests.id('p')));
select tests.put('zc', tests.check_in(tests.id('z'), tests.id('p')));
select tests.put('wc', tests.check_in(tests.id('w'), tests.id('p')));
update public.checkins set joined_at = now() - interval '4 hours', expires_at = now() - interval '1 minute' where id = tests.id('xc');
update public.checkins set left_at = now() - interval '1 minute' where id = tests.id('yc');
update public.checkins set joined_at = now() - interval '2 hours 50 minutes', expires_at = now() + interval '10 minutes' where id = tests.id('zc');

insert into public.taps (room_id, from_user, to_user, created_at, expires_at) values
  (tests.id('p'), tests.id('z'), tests.id('w'), now() - interval '25 hours', now() - interval '1 hour'),
  (tests.id('p'), tests.id('w'), tests.id('z'), now(), now() + interval '24 hours');
insert into public.card_views (viewer_id, checkin_id, room_id, view_day, viewed_at) values
  (tests.id('w'), tests.id('zc'), tests.id('p'), current_date - 3, now() - interval '49 hours'),
  (tests.id('z'), tests.id('wc'), tests.id('p'), current_date, now());
insert into public.location_checks (user_id, room_id, purpose, result, accuracy_bucket, created_at) values
  (tests.id('z'), tests.id('p'), 'join', 'pass', 'under_50m', now() - interval '25 hours'),
  (tests.id('w'), tests.id('p'), 'join', 'pass', 'under_50m', now());

insert into public.matches (id, room_id, user_a, user_b, status, choice_deadline) values
  ('aa000000-0000-4000-8000-000000000001', tests.id('p'), least(tests.id('x'), tests.id('y')), greatest(tests.id('x'), tests.id('y')), 'choosing', now() - interval '1 second'),
  ('aa000000-0000-4000-8000-000000000002', tests.id('p'), least(tests.id('z'), tests.id('w')), greatest(tests.id('z'), tests.id('w')), 'glowing', now()),
  ('aa000000-0000-4000-8000-000000000003', tests.id('p'), least(tests.id('x'), tests.id('w')), greatest(tests.id('x'), tests.id('w')), 'met', now()),
  ('aa000000-0000-4000-8000-000000000004', tests.id('p'), least(tests.id('y'), tests.id('w')), greatest(tests.id('y'), tests.id('w')), 'chatting', now());
insert into public.glow_sessions (match_id, room_id, color, code_word, started_at, ends_at, status, ended_at) values
  ('aa000000-0000-4000-8000-000000000002', tests.id('p'), 'aqua', 'otter', now() - interval '16 minutes', now() - interval '1 minute', 'active', null),
  ('aa000000-0000-4000-8000-000000000003', tests.id('p'), 'lime', 'maple', now() - interval '30 minutes', now() - interval '15 minutes', 'met', now() - interval '20 minutes'),
  ('aa000000-0000-4000-8000-000000000004', tests.id('p'), 'sun', 'comet', now() - interval '10 minutes', now() + interval '5 minutes', 'canceled', now() - interval '5 minutes');

create temporary table purge1 as select public.purge_expired() as result;

select set_eq(format($$ select p from purge1, jsonb_array_elements_text(result -> 'cardPaths') p where p like '%s/%%' $$, tests.id('p')),
              format('values (%L), (%L)', tests.id('p') || '/' || tests.id('xc') || '.jpg',
                                          tests.id('p') || '/' || tests.id('yc') || '.jpg'),
              'purge returns the photo paths of expired and left check-ins, to delete');
select is((select count(*)::integer from public.checkins where id in (tests.id('xc'), tests.id('yc'))), 0,
          'expired and left check-ins are deleted (P9)');
select is((select count(*)::integer from public.checkins where id in (tests.id('zc'), tests.id('wc'))), 2,
          'active check-ins are kept');
select is((select jsonb_agg(e ->> 'userId') from purge1, jsonb_array_elements(result -> 'expiringCheckins') e
            where e ->> 'roomId' = tests.id('p')::text),
          jsonb_build_array(tests.id('z')), 'a check-in ending within CHECKIN_EXPIRY_WARNING is flagged for checkin.expiring');
select is((select jsonb_array_length(public.purge_expired() -> 'expiringCheckins')), 0,
          'and only once');
select is((select count(*)::integer from public.taps where room_id = tests.id('p')), 1, 'expired taps are deleted, live ones kept');
select is((select count(*)::integer from public.card_views where room_id = tests.id('p')), 1,
          'card views older than CARD_VIEW_RETENTION (48 hours) are deleted');
select is((select (count(*) filter (where created_at <= now() - interval '24 hours'))::text || ' ' || (count(*) > 0)::text
             from public.location_checks where room_id = tests.id('p')), '0 true',
          'location checks older than LOCATION_CHECK_RETENTION are deleted, recent ones kept');
select is((select result -> 'endedGlows' -> 0 ->> 'matchId' from purge1), 'aa000000-0000-4000-8000-000000000002',
          'a glow whose time ran out is ended and returned, for glow.ended');
select is((select status::text from public.matches where id = 'aa000000-0000-4000-8000-000000000002'), 'chatting',
          'its match moves to chatting');
select is((select array_agg(status::text order by code_word) from public.glow_sessions where room_id = tests.id('p')),
          array['canceled', 'expired'],
          'glows that ended longer ago than GLOW_ENDED_RETENTION are deleted; recent ones are kept a little while');
select is((select result -> 'choiceTimeouts' -> 0 ->> 'matchId' from purge1), 'aa000000-0000-4000-8000-000000000001',
          'a match whose CHOICE_WINDOW ran out is returned');
select is((select status::text from public.matches where id = 'aa000000-0000-4000-8000-000000000001'), 'chatting',
          'and its chat opens');

select * from finish();
rollback;
