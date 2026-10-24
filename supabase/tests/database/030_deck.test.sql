-- A2 · Who appears in your deck (docs/SPEC.md, Core rules and numbers), through get_deck and
-- card_visible_to: active check-ins, show me both ways, blocks both ways, no active match,
-- filters, the daily view cap and the stable daily shuffle. P1, P7, P8.
begin;
create extension if not exists pgtap with schema extensions;
select plan(42);

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
-- Every card ID in the viewer's deck, page by page, in order. Marks them shown, like the app would.
create function tests.deck(p_viewer uuid, p_room uuid, p_filters jsonb default '{}') returns uuid[]
language plpgsql as $$
declare v_page jsonb; v_offset integer := 0; v_ids uuid[] := '{}';
begin
  loop
    v_page := public.get_deck(p_viewer, p_room, p_filters, null, v_offset);
    v_ids := v_ids || array(select (c ->> 'id')::uuid from jsonb_array_elements(v_page -> 'cards') c);
    exit when not coalesce((v_page ->> 'hasMore')::boolean, false);
    v_offset := (v_page ->> 'nextOffset')::integer;
  end loop;
  return v_ids;
end $$;
create function tests.sorted(p uuid[]) returns uuid[] language sql as $$ select array(select x from unnest(p) x order by x) $$;

create temporary table ids (k text primary key, v uuid);
create function tests.id(p_key text) returns uuid language sql as $$ select v from ids where k = p_key $$;
create function tests.put(p_key text, p_value uuid) returns uuid language sql as $$
  insert into ids values (p_key, p_value) returning v $$;

-- Room R. The viewer V is a woman who wants to see men.
select tests.put('r', tests.room('deck-r'));
select tests.put('other_room', tests.room('deck-other'));
select tests.put('v', tests.person('Vee', 'woman', '{man}'));
select tests.put('v_card', tests.check_in(tests.id('v'), tests.id('r')));

-- Should appear.
select tests.put('m1', tests.person('Max', 'man', '{woman}'));
select tests.put('m1_card', tests.check_in(tests.id('m1'), tests.id('r'), '{"topColor": "green", "hairLength": "short", "hairColor": "brown", "extras": ["glasses", "hat"]}'));
select tests.put('m9', tests.person('Moe', 'man', '{woman,man}'));
select tests.put('m9_card', tests.check_in(tests.id('m9'), tests.id('r'), '{"topColor": "blue", "extras": ["glasses"]}'));

-- Shouldn't appear, each for one reason.
select tests.put('m2', tests.person('Mo', 'man', '{man}'));                      -- doesn't want to see women
select tests.put('m2_card', tests.check_in(tests.id('m2'), tests.id('r')));
select tests.put('w1', tests.person('Wren', 'woman', '{man}'));                  -- V doesn't want to see women
select tests.put('w1_card', tests.check_in(tests.id('w1'), tests.id('r')));
select tests.put('m3', tests.person('Mack', 'man', '{woman}'));                  -- paused
select tests.put('m3_card', tests.check_in(tests.id('m3'), tests.id('r')));
update public.profiles set paused = true where id = tests.id('m3');
select tests.put('m4', tests.person('Milo', 'man', '{woman}'));                  -- check-in expired
select tests.put('m4_card', tests.check_in(tests.id('m4'), tests.id('r')));
update public.checkins set joined_at = now() - interval '4 hours', expires_at = now() - interval '1 second' where id = tests.id('m4_card');
select tests.put('m5', tests.person('Mika', 'man', '{woman}'));                  -- left the room
select tests.put('m5_card', tests.check_in(tests.id('m5'), tests.id('r')));
update public.checkins set left_at = now() where id = tests.id('m5_card');
select tests.put('m6', tests.person('Marc', 'man', '{woman}'));                  -- V blocked him
select tests.put('m6_card', tests.check_in(tests.id('m6'), tests.id('r')));
insert into public.blocks (blocker_id, blocked_id) values (tests.id('v'), tests.id('m6'));
select tests.put('m7', tests.person('Matt', 'man', '{woman}'));                  -- he blocked V
select tests.put('m7_card', tests.check_in(tests.id('m7'), tests.id('r')));
insert into public.blocks (blocker_id, blocked_id) values (tests.id('m7'), tests.id('v'));
select tests.put('m8', tests.person('Mats', 'man', '{woman}'));                  -- already matched with V
select tests.put('m8_card', tests.check_in(tests.id('m8'), tests.id('r')));
insert into public.matches (room_id, user_a, user_b, status, choice_deadline)
values (tests.id('r'), least(tests.id('v'), tests.id('m8')), greatest(tests.id('v'), tests.id('m8')), 'chatting', now());
select tests.put('m10', tests.person('Mike', 'man', '{woman}'));                 -- card removed by an admin
select tests.put('m10_card', tests.check_in(tests.id('m10'), tests.id('r')));
update public.checkins set visible = false where id = tests.id('m10_card');
select tests.put('m11', tests.person('Mal', 'man', '{woman}'));                  -- banned
select tests.put('m11_card', tests.check_in(tests.id('m11'), tests.id('r')));
update public.profiles set banned_at = now() where id = tests.id('m11');
select tests.put('m12', tests.person('Mo B', 'man', '{woman}'));                 -- in another room
select tests.put('m12_card', tests.check_in(tests.id('m12'), tests.id('other_room')));

-- A match that ended (unmatched) doesn't hide anyone.
select tests.put('m13', tests.person('Mano', 'man', '{woman}'));
select tests.put('m13_card', tests.check_in(tests.id('m13'), tests.id('r'), '{"topColor": "red", "hairLength": "long", "hairColor": "black"}'));
insert into public.matches (room_id, user_a, user_b, status, choice_deadline, ended_at)
values (tests.id('r'), least(tests.id('v'), tests.id('m13')), greatest(tests.id('v'), tests.id('m13')), 'ended', now(), now());

-- The rules ----------------------------------------------------------------------------------
select is(tests.sorted(tests.deck(tests.id('v'), tests.id('r'))),
          tests.sorted(array[tests.id('m1_card'), tests.id('m9_card'), tests.id('m13_card')]),
          'the deck holds exactly the people who fit every rule');

select ok(not (tests.id('m2_card') = any (tests.deck(tests.id('v'), tests.id('r')))),
          'show me, their side: someone who doesn''t want to see you isn''t in your deck');
select ok(not (tests.id('w1_card') = any (tests.deck(tests.id('v'), tests.id('r')))),
          'show me, your side: someone you don''t want to see isn''t in your deck');
select ok(not (tests.id('v_card') = any (tests.deck(tests.id('m2'), tests.id('r')))),
          'show me both ways: you aren''t in the deck of someone who doesn''t want to see you');
select ok(tests.id('v_card') = any (tests.deck(tests.id('m1'), tests.id('r'))),
          'show me both ways: when both want to see each other, each is in the other''s deck');
select ok(not (tests.id('m3_card') = any (tests.deck(tests.id('v'), tests.id('r')))), 'paused people are hidden (P8)');
select ok(not (tests.id('m4_card') = any (tests.deck(tests.id('v'), tests.id('r')))), 'expired check-ins are hidden');
select ok(not (tests.id('m5_card') = any (tests.deck(tests.id('v'), tests.id('r')))), 'people who left are hidden (P8)');
select ok(not (tests.id('m6_card') = any (tests.deck(tests.id('v'), tests.id('r')))), 'blocks, your side: someone you blocked is hidden (P7)');
select ok(not (tests.id('m7_card') = any (tests.deck(tests.id('v'), tests.id('r')))), 'blocks, their side: someone who blocked you is hidden (P7)');
select ok(not (tests.id('v_card') = any (tests.deck(tests.id('m6'), tests.id('r'))))
          and not (tests.id('v_card') = any (tests.deck(tests.id('m7'), tests.id('r')))),
          'blocks both ways: you''re hidden from them too (P7)');
select ok(not (tests.id('m8_card') = any (tests.deck(tests.id('v'), tests.id('r')))), 'someone you have an active match with is hidden');
select ok(not (tests.id('m10_card') = any (tests.deck(tests.id('v'), tests.id('r')))), 'a card an admin removed is hidden');
select ok(not (tests.id('m11_card') = any (tests.deck(tests.id('v'), tests.id('r')))), 'banned people are hidden');
select ok(not (tests.id('m12_card') = any (tests.deck(tests.id('v'), tests.id('r')))), 'people in other rooms are hidden');

-- The viewer's own state
select throws_ok(format('select public.get_deck(%L, %L)', tests.id('m12'), tests.id('r')), 'P0001', 'not_found',
                 'a deck for a room you never checked in to is not found (P11)');
update public.profiles set paused = true where id = tests.id('v');
select is(public.get_deck(tests.id('v'), tests.id('r')) ->> 'emptyReason', 'paused', 'a paused viewer gets an empty deck, reason paused');
select is(jsonb_array_length(public.get_deck(tests.id('v'), tests.id('r')) -> 'cards'), 0, 'a paused viewer sees nobody');
update public.profiles set paused = false where id = tests.id('v');
select is(public.get_deck(tests.id('m4'), tests.id('r')) ->> 'emptyReason', 'checkin_ended',
          'a viewer whose check-in expired gets an empty deck, reason checkin_ended');

-- Filters
select is(tests.deck(tests.id('v'), tests.id('r'), '{"topColor": ["green"]}'), array[tests.id('m1_card')],
          'filter: top color');
select is(tests.sorted(tests.deck(tests.id('v'), tests.id('r'), '{"topColor": ["green", "blue"]}')),
          tests.sorted(array[tests.id('m1_card'), tests.id('m9_card')]), 'filter: any of several top colors');
select is(tests.deck(tests.id('v'), tests.id('r'), '{"hairLength": ["short"]}'), array[tests.id('m1_card')],
          'filter: a card with no hair tag doesn''t match a hair filter');
select is(tests.sorted(tests.deck(tests.id('v'), tests.id('r'), '{"extras": ["glasses"]}')),
          tests.sorted(array[tests.id('m1_card'), tests.id('m9_card')]), 'filter: extras');
select is(tests.deck(tests.id('v'), tests.id('r'), '{"extras": ["glasses", "hat"]}'), array[tests.id('m1_card')],
          'filter: a card must have every listed extra');
select is(tests.deck(tests.id('v'), tests.id('r'), '{"gender": ["woman"]}'), '{}'::uuid[],
          'filter: gender only narrows within show me');
select is(tests.sorted(tests.deck(tests.id('v'), tests.id('r'), '{"topColor": [], "extras": []}')),
          tests.sorted(array[tests.id('m1_card'), tests.id('m9_card'), tests.id('m13_card')]), 'filter: empty lists mean any');
select is(public.get_deck(tests.id('v'), tests.id('r'), '{"topColor": ["purple"]}') ->> 'emptyReason', 'no_match',
          'nobody fits the filters: reason no_match');
select throws_ok(format('select public.get_deck(%L, %L, %L)', tests.id('v'), tests.id('r'), '{"topColor": ["plaid"]}'),
                 'P0001', 'invalid_input', 'an unknown filter value is invalid input');

-- P1: no user ID, name or anything else about a person in a deck
select is((select array_agg(distinct k order by k) from jsonb_array_elements(public.get_deck(tests.id('v'), tests.id('r')) -> 'cards') c,
                  jsonb_object_keys(c) k),
          array['cardPath', 'id', 'tags', 'tappedByMe'], 'cards carry only an ID, the photo path, tags and tappedByMe (P1)');
select ok((select bool_and(position(p.id::text in public.get_deck(tests.id('v'), tests.id('r'))::text) = 0
                           and position('"' || p.first_name || '"' in public.get_deck(tests.id('v'), tests.id('r'))::text) = 0)
             from public.profiles p where p.first_name is not null),
          'no user ID or first name appears anywhere in a deck (P1)');

-- card_visible_to
select ok(public.card_visible_to(tests.id('v'), tests.id('m1_card')), 'card_visible_to: yes for a card the deck showed you');
select ok(not public.card_visible_to(tests.id('v'), tests.id('m6_card')), 'card_visible_to: no for someone you blocked');
select ok(public.card_visible_to(tests.id('v'), tests.id('v_card')), 'card_visible_to: yes for your own card');
select tests.put('m14', tests.person('Moss', 'man', '{woman}'));
select tests.put('m14_card', tests.check_in(tests.id('m14'), tests.id('r')));
select ok(not public.card_visible_to(tests.id('v'), tests.id('m14_card')),
          'card_visible_to: no for a card the deck hasn''t shown you yet');
update public.profiles set paused = true where id = tests.id('m1');
select ok(not public.card_visible_to(tests.id('v'), tests.id('m1_card'))
          and not (tests.id('m1_card') = any (tests.deck(tests.id('v'), tests.id('r')))),
          'pausing takes someone out of every deck and image check at once (P8)');
update public.profiles set paused = false where id = tests.id('m1');

-- Quiet room
select tests.put('q', tests.room('deck-quiet'));
select tests.put('q_card', tests.check_in(tests.id('v'), tests.id('q')));
select is(public.get_deck(tests.id('v'), tests.id('q')) ->> 'emptyReason', 'quiet', 'nobody else here: reason quiet');

-- The daily view cap and the stable shuffle, in a room of 55 ------------------------------------
select tests.put('big', tests.room('deck-big'));
select tests.put('vb', tests.person('Viv', 'woman', '{man}'));
select tests.put('vb_card', tests.check_in(tests.id('vb'), tests.id('big')));
select tests.put('vc', tests.person('Val', 'woman', '{man}'));
select tests.put('vc_card', tests.check_in(tests.id('vc'), tests.id('big')));
select count(tests.check_in(tests.person('Man ' || i, 'man', '{woman}'), tests.id('big'))) from generate_series(1, 55) i;

create temporary table first_page as select public.get_deck(tests.id('vb'), tests.id('big')) as page;
select is((select (page ->> 'viewsLeftToday')::integer from first_page), 40, 'each new card shown uses one of today''s 50 views');
select is(public.get_deck(tests.id('vb'), tests.id('big')), (select page from first_page),
          'asking again gives the same cards in the same order, and seeing them again is free');
select is(cardinality(tests.deck(tests.id('vb'), tests.id('big'))), 50,
          'paging through 55 people shows only CARD_VIEWS_PER_ROOM_PER_DAY (50) different cards a day');
select is(public.get_deck(tests.id('vb'), tests.id('big'), '{}', null, 50) ->> 'emptyReason', 'view_limit_reached',
          'past today''s views: reason view_limit_reached');
select ok(tests.deck(tests.id('vb'), tests.id('big')) <> tests.deck(tests.id('vc'), tests.id('big')),
          'two people get different shuffles of the same room');
select is(tests.deck(tests.id('vb'), tests.id('big')),
          array(select c.id from public.checkins c
                 where c.room_id = tests.id('big') and c.user_id <> tests.id('vb')
                   and c.user_id <> tests.id('vc')
                 order by md5(tests.id('vb')::text || ':' || tests.id('big')::text || ':'
                              || (now() at time zone 'America/Los_Angeles')::date::text || ':' || c.id::text)
                 limit 50),
          'the order is the md5 of viewer, room, the room''s date and card: stable all day, not arrival order');

select * from finish();
rollback;
