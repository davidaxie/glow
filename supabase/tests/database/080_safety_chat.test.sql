-- A2 · Blocks and reports from a card, match or chat ID (P7), chat rules, unmatch, match reads
-- and profile photos for matched people only (P1, P11).
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
create function tests.match(p_x uuid, p_y uuid, p_status public.match_status default 'chatting') returns uuid language sql as $$
  insert into public.matches (room_id, user_a, user_b, status, choice_deadline)
  values (tests.id('r'), least(p_x, p_y), greatest(p_x, p_y), p_status, now() + interval '10 minutes') returning id $$;

select tests.put('r', tests.room('safe-r'));
select tests.put('ana', tests.person('Ana', 'woman', '{man}'));
select tests.put('bo', tests.person('Bo', 'man', '{woman}'));
select tests.put('cy', tests.person('Cy', 'man', '{woman}'));
select tests.put('outsider', tests.person('Ozzy', 'man', '{woman}'));
select tests.put('ana_card', tests.check_in(tests.id('ana'), tests.id('r')));
select tests.put('bo_card', tests.check_in(tests.id('bo'), tests.id('r')));
select tests.put('cy_card', tests.check_in(tests.id('cy'), tests.id('r')));

-- Block from a card ---------------------------------------------------------------------------------
select throws_ok(format($$ select public.block_user(%L, 'card', %L) $$, tests.id('ana'), tests.id('bo_card')),
                 'P0001', 'not_found', 'you can only block from a card the deck has shown you');
select count(*) from unnest(tests.deck(tests.id('ana'), tests.id('r')));
select is(public.block_user(tests.id('ana'), 'card', tests.id('bo_card')) -> 'roomIds', jsonb_build_array(tests.id('r')),
          'blocking from a card works, and names the room whose decks changed');
select ok((select count(*) = 1 from public.blocks where blocker_id = tests.id('ana') and blocked_id = tests.id('bo')),
          'the block is stored against the person behind the card, worked out by the database');
select ok(not (tests.id('bo_card') = any (tests.deck(tests.id('ana'), tests.id('r'))))
          and not (tests.id('ana_card') = any (tests.deck(tests.id('bo'), tests.id('r')))),
          'a block hides both people from each other at once (P7)');
select lives_ok(format($$ select public.block_user(%L, 'card', %L) $$, tests.id('ana'), tests.id('bo_card')),
                'blocking twice is harmless');

-- Block from a match ends it ----------------------------------------------------------------------
select tests.put('m_cy', tests.match(tests.id('ana'), tests.id('cy')));
select public.send_message(tests.id('cy'), tests.id('m_cy'), 'hey', null);
select throws_ok(format($$ select public.block_user(%L, 'match', %L) $$, tests.id('outsider'), tests.id('m_cy')),
                 'P0001', 'not_found', 'you can''t block from someone else''s match (P11)');
select is(public.block_user(tests.id('cy'), 'chat', tests.id('m_cy')) -> 'endedMatchIds', jsonb_build_array(tests.id('m_cy')),
          'blocking from a chat ends the match');
select is((select status::text from public.matches where id = tests.id('m_cy')) || ' ' ||
          (select count(*)::text from public.messages where match_id = tests.id('m_cy')), 'ended 0',
          'the match is ended for both and the thread is deleted');
select throws_ok(format($$ select public.send_message(%L, %L, 'still there?', null) $$, tests.id('ana'), tests.id('m_cy')),
                 'P0001', 'not_found', 'nobody can send in a match a block ended');

-- Reports keep evidence, then block ------------------------------------------------------------------
select tests.put('dee', tests.person('Dee', 'woman', '{man}'));
select tests.put('eli', tests.person('Eli', 'man', '{woman}'));
select tests.put('m_de', tests.match(tests.id('dee'), tests.id('eli')));
select public.send_message(tests.id('eli'), tests.id('m_de'), 'first from eli', null);
select public.send_message(tests.id('dee'), tests.id('m_de'), 'from dee', null);
select public.send_message(tests.id('eli'), tests.id('m_de'), 'second from eli', null);
create temporary table report1 as
  select public.create_report(tests.id('dee'), 'chat', tests.id('m_de'), 'harassment', '  rude  ') as result;
select ok((select (result ->> 'reportId') is not null and result -> 'endedMatchIds' = jsonb_build_array(tests.id('m_de'))
             from report1), 'a report is saved and ends the match');
select is((select reported_id from public.reports where id = (select (result ->> 'reportId')::uuid from report1)), tests.id('eli'),
          'the reported person is worked out by the database, never sent by the app');
select is((select jsonb_agg(e ->> 'body' order by e ->> 'body') from public.reports, jsonb_array_elements(evidence) e
            where id = (select (result ->> 'reportId')::uuid from report1)),
          '["first from eli", "second from eli"]'::jsonb,
          'the report keeps only the reported person''s messages as evidence');
select is((select details from public.reports where id = (select (result ->> 'reportId')::uuid from report1)), 'rude',
          'details are trimmed');
select ok(exists (select 1 from public.blocks where blocker_id = tests.id('dee') and blocked_id = tests.id('eli')),
          'a report also blocks');
select throws_ok(format($$ select public.create_report(%L, 'card', %L, 'spam') $$, tests.id('outsider'), tests.id('cy_card')),
                 'P0001', 'not_found', 'you can''t report a card you were never shown');
select throws_ok(format($$ select public.create_report(%L, 'chat', %L, 'spam', %L) $$, tests.id('dee'), tests.id('m_de'), repeat('x', 1001)),
                 'P0001', 'invalid_input', 'report details have a limit (REPORT_DETAILS_MAX_CHARS)');

-- Chat ------------------------------------------------------------------------------------------------
select tests.put('fay', tests.person('Fay', 'woman', '{man}'));
select tests.put('gus', tests.person('Gus', 'man', '{woman}'));
select tests.put('m_fg', tests.match(tests.id('fay'), tests.id('gus'), 'choosing'));
select throws_ok(format($$ select public.send_message(%L, %L, 'hi', null) $$, tests.id('fay'), tests.id('m_fg')),
                 'P0001', 'chat_not_open', 'the chat opens only after choosing');
update public.matches set status = 'chatting' where id = tests.id('m_fg');
create temporary table msg1 as
  select public.send_message(tests.id('fay'), tests.id('m_fg'), 'hi there', 'cccccccc-0000-4000-8000-000000000001') as result;
select is((select result ->> 'recipientId' from msg1), tests.id('gus')::text, 'a message goes to the other person');
select is((select public.send_message(tests.id('fay'), tests.id('m_fg'), 'hi there', 'cccccccc-0000-4000-8000-000000000001') ->> 'id'),
          (select result ->> 'id' from msg1), 'a retry with the same client ID returns the same message');
select is((select count(*)::integer from public.messages where match_id = tests.id('m_fg')), 1, 'and stores it once');
select throws_ok(format($$ select public.send_message(%L, %L, %L, null) $$, tests.id('fay'), tests.id('m_fg'), repeat('x', 1001)),
                 'P0001', 'invalid_input', 'messages are at most MESSAGE_MAX_CHARS (1,000)');
select throws_ok(format($$ select public.send_message(%L, %L, '   ', null) $$, tests.id('fay'), tests.id('m_fg')),
                 'P0001', 'invalid_input', 'empty messages are refused');
select throws_ok(format($$ select public.send_message(%L, %L, 'hello?', null) $$, tests.id('outsider'), tests.id('m_fg')),
                 'P0001', 'not_found', 'someone outside the match can''t send in it (P11)');

-- Match reads and profile photos (P1) -------------------------------------------------------------------
insert into public.profile_photos (id, user_id, path, position, moderation_status) values
  ('99000000-0000-4000-8000-000000000001', tests.id('gus'), tests.id('gus') || '/99000000-0000-4000-8000-000000000001.jpg', 0, 'approved'),
  ('99000000-0000-4000-8000-000000000002', tests.id('gus'), tests.id('gus') || '/99000000-0000-4000-8000-000000000002.jpg', 1, 'held'),
  ('99000000-0000-4000-8000-000000000003', tests.id('gus'), tests.id('gus') || '/99000000-0000-4000-8000-000000000003.jpg', 2, 'approved');
select is(public.get_match(tests.id('fay'), tests.id('m_fg')) ->> 'firstName' || ' ' ||
          (public.get_match(tests.id('fay'), tests.id('m_fg')) ->> 'photoCount'), 'Gus 2',
          'a match shows the other person''s first name and how many approved photos they have');
select is(public.match_photo_path(tests.id('fay'), tests.id('m_fg'), 1),
          tests.id('gus') || '/99000000-0000-4000-8000-000000000003.jpg',
          'photo n is the nth approved photo; photos held for review are skipped');
select throws_ok(format('select public.match_photo_path(%L, %L, 2)', tests.id('fay'), tests.id('m_fg')), 'P0001', 'not_found',
                 'asking past the last approved photo is not found');
select throws_ok(format('select public.match_photo_path(%L, %L, 0)', tests.id('outsider'), tests.id('m_fg')), 'P0001', 'not_found',
                 'someone outside the match can''t see the photos (P1, P11)');
select throws_ok(format('select public.get_match(%L, %L)', tests.id('outsider'), tests.id('m_fg')), 'P0001', 'not_found',
                 'someone outside the match can''t read it (P11)');
select is((select jsonb_agg(m ->> 'firstName') from jsonb_array_elements(public.list_matches(tests.id('gus')) -> 'matches') m),
          '["Fay"]'::jsonb, 'list_matches shows my matches');

-- Unmatch ------------------------------------------------------------------------------------------
select is(public.unmatch(tests.id('gus'), tests.id('m_fg')) -> 'userIds',
          jsonb_build_array(least(tests.id('fay'), tests.id('gus')), greatest(tests.id('fay'), tests.id('gus'))),
          'unmatch tells the server who to send match.ended to');
select is((select count(*)::integer from public.messages where match_id = tests.id('m_fg')), 0,
          'unmatching deletes the thread for both');
select ok(jsonb_array_length(public.list_matches(tests.id('fay')) -> 'matches') = 0
          and jsonb_array_length(public.list_matches(tests.id('gus')) -> 'matches') = 0,
          'an ended match disappears from both lists');
select throws_ok(format('select public.match_photo_path(%L, %L, 0)', tests.id('fay'), tests.id('m_fg')), 'P0001', 'not_found',
                 'profile photos stop being served once the match ends (P1)');

-- Room state -----------------------------------------------------------------------------------------
select is((select (s ->> 'tapsLeftToday') || ' ' || (s -> 'room' ->> 'slug') || ' ' || ((s -> 'checkin' ->> 'id') = tests.id('ana_card')::text)::text
             from (select public.get_room_state(tests.id('ana'), tests.id('r')) as s) x),
          '3 safe-r true', 'get_room_state has my check-in and what I have left today');

select * from finish();
rollback;
