-- X1 · Blind mode: drops (B3, cap of 5, F-01 cutoff, replay), codenames (B11), the chat as each
-- side sees it (B1, B12), reveal both ways (B5), leaving (B6, the leaver gets 404), blocks both
-- ways and everywhere (B7, P7), reports into Glow's queue, Guess Who, and leaving Blind mode.
-- Ported from Double Blind's 003, 005, 0120, 0220, 0221, 130 and 140 suites.
begin;
create extension if not exists pgtap with schema extensions;
select plan(66);

create schema tests;
create function tests.person(p_name text, p_gender public.gender, p_show_me public.gender[])
returns uuid language plpgsql as $$
declare v_id uuid := gen_random_uuid(); v_photo uuid := gen_random_uuid();
begin
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                          raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated',
          'pgtap-blind-' || v_id || '@glow.test', '', now(), '{}', '{}', now(), now());
  update public.profiles
     set first_name = p_name, birthdate = date '1996-05-05', gender = p_gender, show_me = p_show_me,
         onboarding_step = 'complete'
   where id = v_id;
  insert into public.profile_photos (id, user_id, path, position, moderation_status)
  values (v_photo, v_id, v_id::text || '/' || v_photo::text || '.jpg', 0, 'approved');
  perform public.blind_join(v_id);
  return v_id;
end $$;
create function tests.card(p_viewer uuid, p_target uuid) returns uuid language sql as $$
  select private.blind_card_for(p_viewer, p_target) $$;
create function tests.swipe(p_viewer uuid, p_target uuid, p_kind text default 'like') returns jsonb language sql as $$
  select public.blind_record_swipe(p_viewer, tests.card(p_viewer, p_target), p_kind) $$;
create function tests.chat(p_x uuid, p_y uuid) returns uuid language sql as $$
  select id from public.blind_chats where user_a = least(p_x, p_y) and user_b = greatest(p_x, p_y) $$;
create temporary table ids (k text primary key, v uuid);
create function tests.id(p_key text) returns uuid language sql as $$ select v from ids where k = p_key $$;
create function tests.put(p_key text, p_value uuid) returns uuid language sql as $$
  insert into ids values (p_key, p_value) returning v $$;

-- A likes six women; each likes A back, in order, so the matches are oldest W1 to newest W6.
select tests.put('a', tests.person('Alex', 'man', '{woman}'));
do $$
declare i integer;
begin
  for i in 1 .. 6 loop
    perform tests.put('w' || i, tests.person('W' || i, 'woman', '{man}'));
  end loop;
  for i in 1 .. 4 loop
    perform tests.swipe(tests.id('a'), tests.id('w' || i));
    perform tests.swipe(tests.id('w' || i), tests.id('a'));
  end loop;
end $$;

-- B3: no drop below 5 right swipes -------------------------------------------------------------
select is(public.blind_run_drop(tests.id('a')), '{"opened": 0}'::jsonb, 'with 4 right swipes, a drop opens nothing (B3)');
select is(public.blind_drop_new_chats(tests.id('a')), '{"chats": []}'::jsonb, 'and shows nothing');
select is((select count(*)::integer from public.blind_matches where chat_id is null), 4, 'the 4 matches still wait');

do $$
declare i integer;
begin
  for i in 5 .. 6 loop
    perform tests.swipe(tests.id('a'), tests.id('w' || i));
    perform tests.swipe(tests.id('w' || i), tests.id('a'));
  end loop;
end $$;

-- F-01: outside demo mode only matches from before today's drop time open
select is(public.blind_run_drop(tests.id('a'), now() - interval '1 hour'), '{"opened": 0}'::jsonb,
          'a cutoff before the matches were made opens nothing (F-01)');

-- Cap of 5, oldest first -------------------------------------------------------------------------
select is(public.blind_run_drop(tests.id('a')), '{"opened": 5}'::jsonb, 'a drop opens at most 5 chats');
select is(private.blind_open_chat_count(tests.id('a')), 5, 'A has 5 open chats');
select is((select array_agg(k order by k) from ids
            where k like 'w%' and tests.chat(tests.id('a'), v) is null), '{w6}'::text[],
          'oldest matches first: the newest (W6) still waits');
select is(public.blind_run_drop(tests.id('a')), '{"opened": 0}'::jsonb, 'a second drop at the cap opens nothing');

create temporary table drop1 as select public.blind_drop_new_chats(tests.id('a')) as j;
grant select on drop1 to postgres;
select is(jsonb_array_length((select j from drop1) -> 'chats'), 5, 'the drop shows A all 5 new chats');
select is((select array_agg(distinct k order by k) from drop1, jsonb_array_elements(j -> 'chats') c, jsonb_object_keys(c) k),
          '{codename,id}'::text[], 'drop chats carry only id and codename (B1)');
select is(public.blind_drop_new_chats(tests.id('a')), (select j from drop1),
          'a retry within the replay window shows the same chats');
update public.blind_drop_seen set seen_at = now() - interval '10 minutes' where user_id = tests.id('a');
select is(public.blind_drop_new_chats(tests.id('a')), '{"chats": []}'::jsonb,
          'after the replay window they are no longer new');
select is(public.blind_drop_new_chats(tests.id('w1')), '{"chats": []}'::jsonb,
          'W1 (1 right swipe) never sees a drop, even though A''s drop opened their chat (B3)');

-- B11 codenames ---------------------------------------------------------------------------------
select is((select count(distinct codename_a) from public.blind_chats where user_a = tests.id('a'))
          + (select count(distinct codename_b) from public.blind_chats where user_b = tests.id('a')),
          5::bigint, 'A sees five different codenames');
select ok(not exists (select 1 from public.blind_chats where codename_a = codename_b), 'the two sides never share a codename');
select is((select count(*)::integer from public.blind_codename_uses where user_id = tests.id('a') and kind = 'sees'), 5,
          'every name A uses is booked for A');
select is((select count(*)::integer from public.blind_codename_uses where user_id = tests.id('a') and kind = 'seen'), 5,
          'and every name used for A is booked too, so nobody reuses one for A');

-- The chat as each side sees it (B1, B12) -------------------------------------------------------
select tests.put('c1', tests.chat(tests.id('a'), tests.id('w1')));
select tests.put('c2', tests.chat(tests.id('a'), tests.id('w2')));
select tests.put('c3', tests.chat(tests.id('a'), tests.id('w3')));
select tests.put('c4', tests.chat(tests.id('a'), tests.id('w4')));
select tests.put('c5', tests.chat(tests.id('a'), tests.id('w5')));

select is((select array_agg(k order by k) from jsonb_object_keys(public.blind_get_chat(tests.id('a'), tests.id('c1'))) k),
          '{codename,id,iTappedReveal,status,theyLeft}'::text[], 'before reveal a chat has no partner (B1)');
select ok(position(tests.id('w1')::text in public.blind_get_chat(tests.id('a'), tests.id('c1'))::text) = 0
          and position('W1' in public.blind_get_chat(tests.id('a'), tests.id('c1'))::text) = 0,
          'nor the partner''s ID or name anywhere');
select ok(position(tests.id('w1')::text in public.blind_chat_list(tests.id('a'))::text) = 0,
          'the chat list carries no partner ID (B1)');
select throws_ok(format('select public.blind_get_chat(%L, %L)', tests.id('w2'), tests.id('c1')), 'P0001', 'not_found',
                 'someone else''s chat is not_found (P11)');
select is(public.blind_partner_photo_path(tests.id('a'), tests.id('c1'), 0), null, 'no partner photo before reveal');

select is((public.blind_send_message(tests.id('a'), tests.id('c1'), 'hi there') - 'id' - 'at'),
          '{"mine": true, "text": "hi there"}'::jsonb, 'sending answers my own message as mine');
select is((select side from public.blind_messages where chat_id = tests.id('c1')),
          (select case when user_a = tests.id('a') then 'a' else 'b' end::bpchar from public.blind_chats where id = tests.id('c1')),
          'messages store a side, never a sender (B12)');
select is((select (c -> 'unread')::boolean from jsonb_array_elements(public.blind_chat_list(tests.id('w1')) -> 'chats') c
            where c ->> 'id' = tests.id('c1')::text), true, 'W1 has an unread message');
select is((select jsonb_agg(m - 'id' - 'at') from jsonb_array_elements(public.blind_list_messages(tests.id('w1'), tests.id('c1')) -> 'messages') m),
          '[{"mine": false, "text": "hi there"}]'::jsonb, 'W1 reads it as not mine');
select is((select (c -> 'unread')::boolean from jsonb_array_elements(public.blind_chat_list(tests.id('w1')) -> 'chats') c
            where c ->> 'id' = tests.id('c1')::text), false, 'reading marks it read');
select is(jsonb_array_length(public.blind_list_messages(tests.id('w1'), tests.id('c1'),
                             (select max(id) from public.blind_messages)) -> 'messages'), 0,
          'after= the last ID returns nothing new');
select is((select c -> 'lastMessage' ->> 'text' from jsonb_array_elements(public.blind_chat_list(tests.id('a')) -> 'chats') c
            where c ->> 'id' = tests.id('c1')::text), 'hi there', 'the list shows the last message');
select is((select count(*)::integer from jsonb_array_elements(public.blind_chat_list(tests.id('a')) -> 'chats') c
            where c ->> 'id' = tests.id('c2')::text and not (c ? 'lastMessage')), 1,
          'a chat with no messages has no lastMessage');
select throws_ok(format('select public.blind_send_message(%L, %L, %L)', tests.id('a'), tests.id('c1'), '   '),
                 'P0001', 'invalid_input', 'a blank message is invalid_input');

-- Guess Who --------------------------------------------------------------------------------------
select is(jsonb_array_length(public.blind_pool_cards(tests.id('a')) -> 'cards'), 6, 'A''s pool holds the 6 people A liked');
select ok(not exists (select 1 from jsonb_array_elements(public.blind_pool_cards(tests.id('a')) -> 'cards') c
                       where (c ->> 'id')::uuid in (select id from public.profiles)), 'pool card IDs are not user IDs');
select is(public.blind_record_guess(tests.id('a'), tests.id('c1'), tests.card(tests.id('a'), tests.id('w1'))),
          '{"ok": true}'::jsonb, 'a right guess answers only ok');
select is(public.blind_record_guess(tests.id('w1'), tests.id('c1'), tests.card(tests.id('w1'), tests.id('a'))),
          '{"ok": true}'::jsonb, 'and so does the other side''s guess');
select throws_ok(format('select public.blind_record_guess(%L, %L, %L)', tests.id('w2'), tests.id('c2'),
                        tests.card(tests.id('w2'), tests.id('w3'))),
                 'P0001', 'not_found', 'guessing someone not in my pool is not_found');

-- Reveal both ways (B5) ----------------------------------------------------------------------------
select is(public.blind_tap_reveal(tests.id('a'), tests.id('c1')), '{"status": "open"}'::jsonb,
          'a one-sided Reveal tap answers open');
select is(public.blind_get_chat(tests.id('w1'), tests.id('c1')) - 'id' - 'codename',
          '{"status": "open", "iTappedReveal": false, "theyLeft": false}'::jsonb,
          'the other person can''t tell I tapped (B5)');
select is(public.blind_get_chat(tests.id('a'), tests.id('c1')) ->> 'iTappedReveal', 'true', 'I can see my own tap');
select is(public.blind_tap_reveal(tests.id('w1'), tests.id('c1')), '{"status": "revealed"}'::jsonb,
          'the second tap reveals');
select is(public.blind_get_chat(tests.id('a'), tests.id('c1')) -> 'partner', '{"name": "W1", "photoCount": 1}'::jsonb,
          'after reveal the chat names the partner');
select is(public.blind_get_chat(tests.id('w1'), tests.id('c1')) -> 'partner', '{"name": "Alex", "photoCount": 1}'::jsonb,
          'both ways');
select is(public.blind_get_chat(tests.id('a'), tests.id('c1')) ->> 'guessCorrect', 'true', 'guessCorrect after reveal');
select is(public.blind_partner_photo_path(tests.id('a'), tests.id('c1'), 0),
          (select path from public.profile_photos where user_id = tests.id('w1')), 'the revealed partner''s photo');
select is(public.blind_partner_photo_path(tests.id('a'), tests.id('c1'), 1), null, 'only photos that exist');
select ok(not (public.blind_get_chat(tests.id('a'), tests.id('c2')) ? 'guessCorrect'), 'no guessCorrect before reveal');

-- Leaving a chat (B6) --------------------------------------------------------------------------------
select is(public.blind_leave_chat(tests.id('w3'), tests.id('c3')), '{"ok": true}'::jsonb, 'W3 leaves');
select throws_ok(format('select public.blind_get_chat(%L, %L)', tests.id('w3'), tests.id('c3')), 'P0001', 'not_found',
                 'the leaver gets 404 for it');
select throws_ok(format('select public.blind_list_messages(%L, %L)', tests.id('w3'), tests.id('c3')), 'P0001', 'not_found',
                 'messages too');
select is(public.blind_get_chat(tests.id('a'), tests.id('c3')) - 'id' - 'codename',
          '{"status": "left", "iTappedReveal": false, "theyLeft": true}'::jsonb, 'A sees only that they left (B6)');
select throws_ok(format('select public.blind_send_message(%L, %L, %L)', tests.id('a'), tests.id('c3'), 'still there?'),
                 'P0001', 'chat_closed', 'nobody can write in a left chat');
select is(public.blind_leave_chat(tests.id('a'), tests.id('c3')), '{"ok": true}'::jsonb, 'A can leave it too');
select ok(not exists (select 1 from jsonb_array_elements(public.blind_chat_list(tests.id('a')) -> 'chats') c
                       where c ->> 'id' = tests.id('c3')::text), 'and then it is gone from A''s list');

-- Blocks (B7, P7) ----------------------------------------------------------------------------------
select is(public.blind_block(tests.id('a'), tests.id('c4')) ?& array['endedMatchIds', 'roomIds'], true,
          'a Blind block answers what a Glow block answers');
select ok(exists (select 1 from public.blocks where blocker_id = tests.id('a') and blocked_id = tests.id('w4')),
          'it is a Glow block, so it applies in Rooms too');
select throws_ok(format('select public.blind_get_chat(%L, %L)', tests.id('a'), tests.id('c4')), 'P0001', 'not_found',
                 'the blocker gets 404 for the chat');
select is(public.blind_get_chat(tests.id('w4'), tests.id('c4')) ->> 'theyLeft', 'true',
          'the blocked person sees only that they left');
select is(jsonb_array_length(public.blind_pool_cards(tests.id('a')) -> 'cards'), 6,
          'the pool is not filtered by blocks, so it can''t tell who the chat was');
-- A block made in Rooms closes their Blind chat too.
insert into public.blocks (blocker_id, blocked_id) values (tests.id('w5'), tests.id('a'));
select is((select status from public.blind_chats where id = tests.id('c5')), 'left', 'a Glow block closes the Blind chat');
select throws_ok(format('select public.blind_get_chat(%L, %L)', tests.id('w5'), tests.id('c5')), 'P0001', 'not_found',
                 'and it is gone for the blocker');

-- Reports -----------------------------------------------------------------------------------------
select is(public.blind_report(tests.id('w1'), tests.id('c1'), 'rude', 'harassment') ?& array['reportId', 'endedMatchIds'], true,
          'a Blind report answers like a Glow report');
select is((select context::text || ' ' || reason::text || ' ' || details || ' ' || jsonb_array_length(evidence)
             from public.reports where reporter_id = tests.id('w1') and context_id = tests.id('c1')),
          'blind_chat harassment rude 1', 'it lands in Glow''s queue with context blind_chat and the evidence');
select ok(exists (select 1 from public.blocks where blocker_id = tests.id('w1') and blocked_id = tests.id('a')),
          'a report also blocks');

-- The nightly drop and leaving Blind mode -------------------------------------------------------
select is((public.blind_run_drop_all() ->> 'opened')::integer, 1, 'run_drop_all opens the waiting W6 match now that A has room');
select is(public.blind_leave(tests.id('w2')) ->> 'chatsDeleted', '1', 'leaving Blind deletes my chats');
select is((select count(*)::integer from public.blind_swipes where tests.id('w2') in (swiper_id, target_id))
          + (select count(*)::integer from public.blind_cards where tests.id('w2') in (viewer_id, target_id))
          + (select count(*)::integer from public.blind_members where user_id = tests.id('w2')), 0,
          'and my swipes, cards and membership, both ways');

select * from finish();
rollback;
