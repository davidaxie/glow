-- A2 · Choosing and glow: CHOICE_WINDOW, Find only when both chose it in time and both are
-- checked in with a location check in the last GEO_FRESHNESS_FOR_GLOW, GLOW_TTL, We met and
-- cancel, and color plus code word unique among active glows in a room.
begin;
create extension if not exists pgtap with schema extensions;
select plan(34);

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
  perform public.create_checkin(p_user, p_room, v_id, p_room::text || '/' || v_id::text || '.jpg', p_tags);
  return v_id;
end $$;
create temporary table ids (k text primary key, v uuid);
create function tests.id(p_key text) returns uuid language sql as $$ select v from ids where k = p_key $$;
create function tests.put(p_key text, p_value uuid) returns uuid language sql as $$
  insert into ids values (p_key, p_value) returning v $$;
-- A checked-in pair with a fresh match in room p_room.
create function tests.pair(p_key text, p_room uuid) returns uuid language plpgsql as $$
declare a uuid := tests.person(p_key || ' A', 'woman', '{man}'); b uuid := tests.person(p_key || ' B', 'man', '{woman}'); m uuid;
begin
  perform tests.check_in(a, p_room);
  perform tests.check_in(b, p_room);
  insert into public.matches (room_id, user_a, user_b, choice_deadline)
  values (p_room, least(a, b), greatest(a, b), now() + interval '10 minutes') returning id into m;
  perform tests.put(p_key || '_a', least(a, b));
  perform tests.put(p_key || '_b', greatest(a, b));
  return m;
end $$;
create function tests.located(p_user uuid, p_room uuid, p_ago interval default '0 seconds') returns void language sql as $$
  insert into public.location_checks (user_id, room_id, purpose, result, accuracy_bucket, created_at)
  values (p_user, p_room, 'find', 'pass', 'under_20m', now() - p_ago) $$;
create function tests.choose(p_key text, p_side text, p_choice public.match_choice) returns jsonb language sql as $$
  select public.set_choice(tests.id(p_key || '_' || p_side), tests.id(p_key), p_choice) $$;
create function tests.next(p jsonb) returns text language sql as $$ select (p ->> 'next') || '/' || (p ->> 'reason') $$;

select tests.put('r', tests.room('glow-r'));
create temporary table words as select array['otter', 'maple', 'comet'] as list;

-- Find and Find --------------------------------------------------------------------------------
select tests.put('ff', tests.pair('ff', tests.id('r')));
select throws_ok($$ select tests.choose('ff', 'a', 'find') $$, 'P0001', 'location_required',
                 'Find needs a passed location check first');
select tests.located(tests.id('ff_a'), tests.id('r'));
select tests.located(tests.id('ff_b'), tests.id('r'));
select is(tests.next(tests.choose('ff', 'a', 'find')), 'waiting/other_undecided', 'first Find waits for the other person');
select is(tests.choose('ff', 'b', 'find') -> 'match' ->> 'otherHasChosen', 'true', 'the second chooser sees the other has chosen');
select is(tests.next(tests.choose('ff', 'b', 'find')), 'glow/both_find', 'both chose Find, checked in and located: glow');
select tests.put('ff_glow', (public.start_glow(tests.id('ff'), (select list from words)) ->> 'id')::uuid);
select is((select status::text from public.matches where id = tests.id('ff')), 'glowing', 'start_glow moves the match to glowing');
select is((select ends_at - started_at from public.glow_sessions where id = tests.id('ff_glow')), interval '15 minutes',
          'a glow lasts GLOW_TTL (15 minutes)');
select ok((select code_word = any (array['otter', 'maple', 'comet']) and spot_id is not null
             from public.glow_sessions where id = tests.id('ff_glow')),
          'the code word comes from the server''s list, and there is a meeting spot');
select is((public.start_glow(tests.id('ff'), (select list from words)) ->> 'id')::uuid, tests.id('ff_glow'),
          'start_glow is idempotent: calling it again returns the same glow');
select is(public.get_match(tests.id('ff_a'), tests.id('ff')) -> 'glow' ->> 'codeWord',
          public.get_match(tests.id('ff_b'), tests.id('ff')) -> 'glow' ->> 'codeWord',
          'both people see the same code word');

-- We met -------------------------------------------------------------------------------------
select is(public.glow_met(tests.id('ff_a'), tests.id('ff')) ->> 'status', 'active', 'one We met keeps the glow on');
select is(public.glow_met(tests.id('ff_a'), tests.id('ff')) ->> 'youMet' || ' ' || (public.glow_met(tests.id('ff_b'), tests.id('ff')) ->> 'theyMet'),
          'true true', 'each side sees who has tapped We met');
select is((select status::text from public.glow_sessions where id = tests.id('ff_glow')) || ' ' ||
          (select status::text from public.matches where id = tests.id('ff')), 'met met',
          'when both tap We met, the glow and the match are met');

-- Find and Chat, Chat and Chat --------------------------------------------------------------------
select tests.put('fc', tests.pair('fc', tests.id('r')));
select tests.located(tests.id('fc_a'), tests.id('r'));
select is(tests.next(tests.choose('fc', 'a', 'find')), 'waiting/other_undecided', 'Find, then...');
select is(tests.next(tests.choose('fc', 'b', 'chat')), 'chat/chose_chat', '...Chat opens the chat');
select is(tests.next(tests.choose('fc', 'a', 'find')), 'chat/already_decided', 'and it stays chat for both');
select throws_ok(format('select public.start_glow(%L, %L)', tests.id('fc'), '{otter}'), 'P0001', 'glow_not_ready',
                 'no glow unless both chose Find');

select tests.put('cc', tests.pair('cc', tests.id('r')));
select is(tests.next(tests.choose('cc', 'a', 'chat')), 'chat/chose_chat', 'Chat and Chat: chat');
select is((select status::text from public.matches where id = tests.id('cc')), 'chatting', 'the match is chatting');

-- The 10-minute window -------------------------------------------------------------------------
select tests.put('to', tests.pair('to', tests.id('r')));
update public.matches set choice_deadline = now() - interval '1 second' where id = tests.id('to');
select tests.located(tests.id('to_a'), tests.id('r'));
select is(tests.next(tests.choose('to', 'a', 'find')), 'chat/timeout', 'a choice after CHOICE_WINDOW opens the chat');
select tests.put('to2', tests.pair('to2', tests.id('r')));
update public.matches set choice_deadline = now() - interval '1 second' where id = tests.id('to2');
select is(public.get_match(tests.id('to2_a'), tests.id('to2')) ->> 'status', 'chatting',
          'reading a match applies the timeout even if nobody chose');

-- Freshness and still being checked in ---------------------------------------------------------------
select tests.put('st', tests.pair('st', tests.id('r')));
select tests.located(tests.id('st_a'), tests.id('r'), '3 minutes');
select tests.located(tests.id('st_b'), tests.id('r'));
select throws_ok($$ select tests.choose('st', 'a', 'find') $$, 'P0001', 'location_required',
                 'a location check older than GEO_FRESHNESS_FOR_GLOW (2 minutes) doesn''t count');
select tests.located(tests.id('st_a'), tests.id('r'));
select tests.choose('st', 'a', 'find');
update public.location_checks set created_at = now() - interval '3 minutes' where user_id = tests.id('st_a');
select is(tests.next(tests.choose('st', 'b', 'find')), 'waiting/other_location_stale',
          'if the other person''s check went stale while waiting, wait for them to re-check');
select throws_ok(format('select public.start_glow(%L, %L)', tests.id('st'), '{otter}'), 'P0001', 'glow_not_ready',
                 'start_glow refuses while one location check is stale');
select tests.located(tests.id('st_a'), tests.id('r'));
select is(tests.next(tests.choose('st', 'a', 'find')), 'glow/both_find', 'once they re-check, the glow can start');

select tests.put('lv', tests.pair('lv', tests.id('r')));
select tests.located(tests.id('lv_a'), tests.id('r'));
select tests.located(tests.id('lv_b'), tests.id('r'));
select tests.choose('lv', 'a', 'find');
update public.checkins set left_at = now() where user_id = tests.id('lv_a');
select is(tests.next(tests.choose('lv', 'b', 'find')), 'chat/not_checked_in', 'if one person left the room, the chat opens');

-- Cancel and time running out ------------------------------------------------------------------------
select tests.put('cn', tests.pair('cn', tests.id('r')));
select tests.located(tests.id('cn_a'), tests.id('r'));
select tests.located(tests.id('cn_b'), tests.id('r'));
select tests.choose('cn', 'a', 'find');
select tests.choose('cn', 'b', 'find');
select public.start_glow(tests.id('cn'), (select list from words));
select is(public.cancel_glow(tests.id('cn_b'), tests.id('cn')) ->> 'status', 'canceled', 'either person can cancel the glow');
select is((select status::text from public.matches where id = tests.id('cn')), 'chatting', 'cancel opens the chat');

select tests.put('ex', tests.pair('ex', tests.id('r')));
select tests.located(tests.id('ex_a'), tests.id('r'));
select tests.located(tests.id('ex_b'), tests.id('r'));
select tests.choose('ex', 'a', 'find');
select tests.choose('ex', 'b', 'find');
select public.start_glow(tests.id('ex'), (select list from words));
update public.glow_sessions set started_at = now() - interval '16 minutes', ends_at = now() - interval '1 minute'
 where match_id = tests.id('ex');
select is(public.glow_met(tests.id('ex_a'), tests.id('ex')) ->> 'status', 'expired', 'after GLOW_TTL the glow has expired');
select is((select status::text from public.matches where id = tests.id('ex')), 'chatting', 'and the chat opens');

-- Unique color plus code word among active glows in a room -------------------------------------------
select tests.put('busy', tests.room('glow-busy'));
create function tests.glowing_pair(p_key text) returns jsonb language plpgsql as $$
declare m uuid := tests.put(p_key, tests.pair(p_key, tests.id('busy')));
begin
  perform tests.located(tests.id(p_key || '_a'), tests.id('busy'));
  perform tests.located(tests.id(p_key || '_b'), tests.id('busy'));
  perform tests.choose(p_key, 'a', 'find');
  perform tests.choose(p_key, 'b', 'find');
  return public.start_glow(m, (select list from words));
end $$;
create temporary table busy_glows as select i, tests.glowing_pair('busy' || i) as glow from generate_series(1, 8) i;
select is((select count(distinct glow ->> 'color')::integer from busy_glows), 8,
          'the first 8 glows in a room get 8 different colors');
insert into busy_glows select i, tests.glowing_pair('busy' || i) from generate_series(9, 24) i;
select is((select count(distinct (glow ->> 'color', glow ->> 'codeWord'))::integer from busy_glows), 24,
          '24 active glows in one room never share a color and code word');
select throws_ok($$ select tests.glowing_pair('busy25') $$, 'P0001', 'no_code_word',
                 'with 8 colors and 3 words, a 25th active glow can''t get a unique pair');
select throws_ok($$ insert into public.glow_sessions (match_id, room_id, color, code_word, ends_at)
                    select match_id, room_id, color, code_word, ends_at from public.glow_sessions
                     where room_id = tests.id('busy') and status = 'active' limit 1 $$,
                 '23505', null, 'a unique index backs it up: a duplicate active color and code word can''t be stored');

-- P1: a match shows only the other person's first name, never their user ID, before or after
select is((select array_agg(k order by k) from jsonb_object_keys(public.get_match(tests.id('cc_a'), tests.id('cc'))) k),
          array['choiceDeadline', 'createdAt', 'firstName', 'id', 'otherHasChosen', 'photoCount', 'roomId', 'roomName',
                'status', 'userIds', 'yourChoice'],
          'get_match returns the contract''s fields plus userIds, which the route helper drops (MatchDetail has none)');

select * from finish();
rollback;
