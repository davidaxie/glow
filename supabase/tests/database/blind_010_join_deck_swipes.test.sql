-- X1 · Blind mode: opt in, the deck (eligibility both ways, blocks both ways, pause, ban, photo),
-- opaque per-viewer card IDs, the right-swipe cap (B4), silent swipes (B2) and one match per pair.
-- Ported from Double Blind's 002_swipes_eligibility and 110_c1_deck.
begin;
create extension if not exists pgtap with schema extensions;
select plan(47);

create schema tests;
-- A Glow person with a finished profile and an approved photo, optionally a Blind member.
create function tests.person(p_name text, p_gender public.gender, p_show_me public.gender[],
                             p_member boolean default true, p_photo boolean default true)
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
  if p_photo then
    insert into public.profile_photos (id, user_id, path, position, moderation_status)
    values (v_photo, v_id, v_id::text || '/' || v_photo::text || '.jpg', 0, 'approved');
  end if;
  if p_member then
    perform public.blind_join(v_id);
  end if;
  return v_id;
end $$;
-- The targets behind a viewer's deck (resolved on the test side; the app never sees these).
-- plpgsql, so the lookup sees the card rows blind_deck just made.
create function tests.deck_targets(p_viewer uuid) returns uuid[] language plpgsql as $$
declare v_deck jsonb := public.blind_deck(p_viewer, 20);
begin
  return (select coalesce(array_agg(c.target_id order by c.target_id), '{}')
            from jsonb_array_elements(v_deck -> 'cards') j
            join public.blind_cards c on c.card_id = (j ->> 'id')::uuid and c.viewer_id = p_viewer);
end $$;
create function tests.card(p_viewer uuid, p_target uuid) returns uuid language sql as $$
  select private.blind_card_for(p_viewer, p_target) $$;
create function tests.swipe(p_viewer uuid, p_target uuid, p_kind text) returns jsonb language sql as $$
  select public.blind_record_swipe(p_viewer, tests.card(p_viewer, p_target), p_kind) $$;
create temporary table ids (k text primary key, v uuid);
create function tests.id(p_key text) returns uuid language sql as $$ select v from ids where k = p_key $$;
create function tests.put(p_key text, p_value uuid) returns uuid language sql as $$
  insert into ids values (p_key, p_value) returning v $$;

-- Join ----------------------------------------------------------------------------------------
select tests.put('m', tests.person('Max', 'man', '{woman}'));
select tests.put('w', tests.person('Wren', 'woman', '{man}'));
select tests.put('w2', tests.person('Willa', 'woman', '{man}'));
select tests.put('wwoman', tests.person('Wanda', 'woman', '{woman}'));      -- wants women only
select tests.put('nm', tests.person('Nora', 'woman', '{man}', false));       -- not a member
select tests.put('nophoto', tests.person('Nia', 'woman', '{man}', true, false));

select is(public.blind_me(tests.id('nm')),
          '{"member": false, "hasPhoto": true, "rightRemaining": 20, "rightCount": 0, "canDrop": false}'::jsonb,
          'blind_me works for a non-member and says member false');
select is(public.blind_me(tests.id('m')) ->> 'member', 'true', 'blind_join makes a member');
select is(public.blind_join(tests.id('m')) ->> 'member', 'true', 'blind_join is idempotent');
select is(public.blind_me(tests.id('nophoto')) ->> 'hasPhoto', 'false', 'hasPhoto is false without an approved photo');

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                        raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('00000000-0000-0000-0000-000000000000', '7e570000-0000-4000-8000-0000000000b1', 'authenticated',
        'authenticated', 'pgtap-blind-half@glow.test', '', now(), '{}', '{}', now(), now());
select throws_ok($$ select public.blind_join('7e570000-0000-4000-8000-0000000000b1') $$, 'P0001',
                 'onboarding_incomplete', 'an unfinished Glow profile cannot join');
select throws_ok($$ select public.blind_deck(tests.id('nm'), 10) $$, 'P0001', 'not_found',
                 'a non-member asking for a deck is not_found (P11)');
select throws_ok($$ select public.blind_pool(tests.id('nm')) $$, 'P0001', 'not_found',
                 'a non-member asking for a pool is not_found');

-- Deck: eligibility both ways ------------------------------------------------------------------
select is(tests.deck_targets(tests.id('m')),
          (select array_agg(x order by x) from unnest(array[tests.id('w'), tests.id('w2')]) x),
          'the deck holds members whose gender and show me fit mine both ways, with a photo');
select ok(not (tests.id('wwoman') = any (tests.deck_targets(tests.id('m')))),
          'someone who does not want my gender is not in my deck');
select ok(not (tests.id('m') = any (tests.deck_targets(tests.id('wwoman')))),
          'and I am not in theirs');
select ok(not (tests.id('nm') = any (tests.deck_targets(tests.id('m')))), 'a non-member is never in a deck');
select ok(not (tests.id('nophoto') = any (tests.deck_targets(tests.id('m')))),
          'a member without an approved photo is in nobody''s deck');
select is(tests.deck_targets(tests.id('nophoto')), '{}'::uuid[],
          'and sees an empty deck (no browsing without being visible)');
select ok(tests.id('m') = any (tests.deck_targets(tests.id('w'))), 'eligibility is symmetric');

-- Opaque card IDs
select ok(not exists (select 1 from jsonb_array_elements(public.blind_deck(tests.id('m'), 20) -> 'cards') j
                       where (j ->> 'id')::uuid in (select id from public.profiles)),
          'deck card IDs are never user IDs');
select is((select array_agg(k order by k) from jsonb_array_elements(public.blind_deck(tests.id('m'), 20) -> 'cards') j,
                  jsonb_object_keys(j) k), '{id,id}'::text[],
          'deck cards carry only an id (the route adds the signed photo link)');
select isnt(tests.card(tests.id('m'), tests.id('w')), tests.card(tests.id('w2'), tests.id('w')),
            'two viewers get different card IDs for the same person');
select is(tests.card(tests.id('m'), tests.id('w')), tests.card(tests.id('m'), tests.id('w')),
          'a viewer''s card ID for someone is stable');
select is(private.blind_card_target(tests.id('w2'), tests.card(tests.id('m'), tests.id('w'))), null,
          'a card ID resolves only for the viewer it was made for');
select throws_ok(format('select public.blind_record_swipe(%L, %L, %L)', tests.id('w2'),
                        tests.card(tests.id('m'), tests.id('w')), 'like'),
                 'P0001', 'not_found', 'swiping someone else''s card is not_found');
select throws_ok(format('select public.blind_record_swipe(%L, %L, %L)', tests.id('m'), gen_random_uuid(), 'like'),
                 'P0001', 'not_found', 'an unknown card is not_found');
select throws_ok(format('select public.blind_record_swipe(%L, %L, %L)', tests.id('m'),
                        tests.card(tests.id('m'), tests.id('w')), 'superlike'),
                 'P0001', 'invalid_input', 'an unknown kind is invalid_input');

-- Blocks both ways (Glow blocks), pause, ban, Blind pause, limit ------------------------------
select tests.put('w3', tests.person('Wynn', 'woman', '{man}'));
select tests.put('w4', tests.person('Wilma', 'woman', '{man}'));
select tests.put('w5', tests.person('Winona', 'woman', '{man}'));
select tests.put('w6', tests.person('Wendy', 'woman', '{man}'));
insert into public.blocks (blocker_id, blocked_id) values (tests.id('m'), tests.id('w3'));
insert into public.blocks (blocker_id, blocked_id) values (tests.id('w4'), tests.id('m'));
update public.profiles set paused = true where id = tests.id('w5');
update public.profiles set banned_at = now() where id = tests.id('w6');
select ok(not (tests.id('w3') = any (tests.deck_targets(tests.id('m')))), 'someone I blocked (in Glow) is not in my deck');
select ok(not (tests.id('m') = any (tests.deck_targets(tests.id('w3')))), 'and I am not in theirs');
select ok(not (tests.id('w4') = any (tests.deck_targets(tests.id('m')))), 'someone who blocked me is not in my deck');
select ok(not (tests.id('m') = any (tests.deck_targets(tests.id('w4')))), 'and I am not in theirs (P7)');
select ok(not (tests.id('w5') = any (tests.deck_targets(tests.id('m')))), 'a paused Glow profile is not in any deck');
select ok(not (tests.id('w6') = any (tests.deck_targets(tests.id('m')))), 'a banned profile is not in any deck');
update public.blind_members set paused = true where user_id = tests.id('w2');
select ok(not (tests.id('w2') = any (tests.deck_targets(tests.id('m')))), 'a Blind-paused member is not in any deck');
update public.blind_members set paused = false where user_id = tests.id('w2');
select is(jsonb_array_length(public.blind_deck(tests.id('m'), 1) -> 'cards'), 1, 'the limit is honoured');

-- A swipe on someone no longer eligible is silently ignored
select is(tests.swipe(tests.id('m'), tests.id('w3'), 'like'),
          '{"rightRemaining": 20, "rightCount": 0}'::jsonb,
          'a swipe on a blocked person answers like any swipe and changes nothing');
select is((select count(*)::integer from public.blind_swipes where swiper_id = tests.id('m')), 0,
          'nothing was stored for it');

-- Swipes, B2, mutual match ---------------------------------------------------------------------
select is(tests.swipe(tests.id('m'), tests.id('w'), 'like'),
          '{"rightRemaining": 19, "rightCount": 1}'::jsonb, 'a like answers only the two counters (B2)');
select is(tests.swipe(tests.id('m'), tests.id('w'), 'love'),
          '{"rightRemaining": 19, "rightCount": 1}'::jsonb, 'repeating a swipe changes nothing (first swipe wins)');
select is((select count(*)::integer from public.blind_matches), 0, 'a one-sided like makes no match');
select is(tests.swipe(tests.id('w'), tests.id('m'), 'love'),
          '{"rightRemaining": 19, "rightCount": 1}'::jsonb, 'the mutual swipe answers exactly the same (B2)');
select is((select count(*)::integer from public.blind_matches
            where user_a = least(tests.id('m'), tests.id('w')) and user_b = greatest(tests.id('m'), tests.id('w'))
              and chat_id is null), 1, 'a mutual right swipe makes exactly one waiting match, with no chat (B3)');
select is((select count(*)::integer from public.blind_chats), 0, 'no chat opens on a swipe (B3)');
select ok(not (tests.id('w') = any (tests.deck_targets(tests.id('m')))), 'someone I swiped leaves my deck');
select is(tests.swipe(tests.id('m'), tests.id('w2'), 'pass'),
          '{"rightRemaining": 19, "rightCount": 1}'::jsonb, 'a pass uses no right swipe');

-- The daily cap (B4) -----------------------------------------------------------------------------
do $$
declare i integer; v uuid;
begin
  for i in 1 .. 20 loop
    v := tests.person('Cap' || i, 'woman', '{man}');
    perform tests.put('cap' || i, v);
  end loop;
  -- 19 more likes reach the cap of 20 (one like on w already today).
  for i in 1 .. 19 loop
    perform tests.swipe(tests.id('m'), tests.id('cap' || i), 'like');
  end loop;
end $$;
select is((public.blind_me(tests.id('m')) ->> 'rightRemaining')::integer, 0, '20 right swipes today leaves 0');
select throws_ok(format('select tests.swipe(%L, %L, %L)', tests.id('m'), tests.id('cap20'), 'like'),
                 'P0001', 'right_cap_reached', 'the 21st right swipe of the day is right_cap_reached');
select is(tests.swipe(tests.id('m'), tests.id('cap20'), 'pass'),
          '{"rightRemaining": 0, "rightCount": 20}'::jsonb, 'a pass still works at the cap');
update public.blind_swipes set created_at = now() - interval '1 day' where swiper_id = tests.id('m');
select is((public.blind_me(tests.id('m')) ->> 'rightRemaining')::integer, 20, 'the cap resets on the next UTC day');
select is((public.blind_me(tests.id('m')) ->> 'canDrop')::boolean, true, 'canDrop with at least 5 right swipes');

-- Lockdown ------------------------------------------------------------------------------------
select is(array(select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname in ('public', 'private') and p.proname like 'blind\_%'
                   and (has_function_privilege('anon', p.oid, 'EXECUTE')
                        or has_function_privilege('authenticated', p.oid, 'EXECUTE'))),
          '{}'::text[], 'no blind_ function is callable by anon or authenticated');
select ok(has_function_privilege('service_role', 'public.blind_record_swipe(uuid,uuid,text)', 'EXECUTE'),
          'the server can call the blind functions');

select * from finish();
rollback;
