-- A2 · Taps and matches through record_tap: only cards in your deck, TAPS_PER_ROOM_PER_DAY,
-- TAP_TTL, the same room, and the match in the same transaction. One-sided taps stay secret (P5).
begin;
create extension if not exists pgtap with schema extensions;
select plan(25);

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
create temporary table ids (k text primary key, v uuid);
create function tests.id(p_key text) returns uuid language sql as $$ select v from ids where k = p_key $$;
create function tests.put(p_key text, p_value uuid) returns uuid language sql as $$
  insert into ids values (p_key, p_value) returning v $$;
create function tests.tap(p_viewer text, p_card text, p_room text default 'r') returns jsonb language sql as $$
  select public.record_tap(tests.id(p_viewer), tests.id(p_room), tests.id(p_card)) $$;

-- Room R: Ana (woman, wants men) and four men who want women.
select tests.put('r', tests.room('taps-r'));
select tests.put('s', tests.room('taps-s'));
select tests.put('ana', tests.person('Ana', 'woman', '{man}'));
select tests.put('ana_card', tests.check_in(tests.id('ana'), tests.id('r')));
select tests.put('ana_card_s', tests.check_in(tests.id('ana'), tests.id('s')));
select tests.put('bo', tests.person('Bo', 'man', '{woman}'));
select tests.put('bo_card', tests.check_in(tests.id('bo'), tests.id('r')));
select tests.put('bo_card_s', tests.check_in(tests.id('bo'), tests.id('s')));
select tests.put('cy', tests.person('Cy', 'man', '{woman}'));
select tests.put('cy_card', tests.check_in(tests.id('cy'), tests.id('r')));
select tests.put('di', tests.person('Di', 'man', '{woman}'));
select tests.put('di_card', tests.check_in(tests.id('di'), tests.id('r')));
select tests.put('ed', tests.person('Ed', 'man', '{woman}'));
select tests.put('ed_card', tests.check_in(tests.id('ed'), tests.id('r')));
select tests.put('fay', tests.person('Fay', 'woman', '{woman}'));
select tests.put('fay_card', tests.check_in(tests.id('fay'), tests.id('r')));

-- Only cards in your deck ----------------------------------------------------------------------
select throws_ok($$ select tests.tap('ana', 'bo_card') $$, 'P0001', 'not_found',
                 'you can''t tap a card the deck hasn''t shown you');
select count(*) from unnest(tests.deck(tests.id('ana'), tests.id('r')));
select throws_ok($$ select tests.tap('ana', 'fay_card') $$, 'P0001', 'not_found',
                 'you can''t tap someone who isn''t in your deck');
select throws_ok($$ select tests.tap('ana', 'ana_card') $$, 'P0001', 'not_found', 'you can''t tap your own card');
select throws_ok($$ select tests.tap('ana', 'bo_card', 's') $$, 'P0001', 'not_found',
                 'a card ID only works in its own room');

-- P5: a one-sided tap changes nothing the other person can see -------------------------------
select count(*) from unnest(tests.deck(tests.id('bo'), tests.id('r')));
create temporary table bo_before as select public.get_deck(tests.id('bo'), tests.id('r')) as deck;
select is(tests.tap('ana', 'bo_card'), '{"result": "sent", "tapsLeftToday": 2}'::jsonb,
          'a tap is sent, secretly, and uses one of today''s 3 taps');
select is(public.get_deck(tests.id('bo'), tests.id('r')), (select deck from bo_before),
          'their deck is exactly the same after you tap them (P5)');
select is((select count(*)::integer from jsonb_array_elements(public.get_deck(tests.id('ana'), tests.id('r')) -> 'cards') c
            where (c ->> 'tappedByMe')::boolean), 1,
          'your own deck marks the card you tapped, and only that one');
select is(tests.tap('ana', 'bo_card'), '{"result": "sent", "tapsLeftToday": 2}'::jsonb,
          'tapping the same card again is free and says the same thing');

-- The daily cap --------------------------------------------------------------------------------
select is(tests.tap('ana', 'cy_card') ->> 'tapsLeftToday', '1', 'second tap: 1 left');
select is(tests.tap('ana', 'di_card') ->> 'tapsLeftToday', '0', 'third tap: none left');
select throws_ok($$ select tests.tap('ana', 'ed_card') $$, 'P0001', 'tap_limit_reached',
                 'a fourth tap in the same room and day is refused (TAPS_PER_ROOM_PER_DAY)');
select is(tests.tap('ana', 'cy_card') ->> 'result', 'sent', 're-tapping someone at the cap still works, and is free');
select is((select count(*)::integer from public.taps where from_user = tests.id('ana') and room_id = tests.id('r')), 3,
          'only three taps were stored');

-- Mutual: the match is made in the same transaction as the second tap ------------------------
select count(*) from unnest(tests.deck(tests.id('cy'), tests.id('r')));
select tests.put('match_ac', (tests.tap('cy', 'ana_card') ->> 'matchId')::uuid);
select isnt(tests.id('match_ac'), null, 'tapping someone who tapped you makes a mutual match right away');
select is((select status::text || ' ' || (user_a < user_b)::text || ' ' || (choice_deadline = now() + interval '10 minutes')::text
             from public.matches where id = tests.id('match_ac')),
          'choosing true true', 'the match is choosing, its pair is sorted, and it has the 10-minute CHOICE_WINDOW');
select is((select count(*)::integer from public.taps where match_id = tests.id('match_ac')), 2,
          'both taps are marked as used by the match');
select ok(not (tests.id('cy_card') = any (tests.deck(tests.id('ana'), tests.id('r'))))
          and not (tests.id('ana_card') = any (tests.deck(tests.id('cy'), tests.id('r')))),
          'a matched pair leaves each other''s decks');
select throws_ok($$ select tests.tap('ana', 'cy_card') $$, 'P0001', 'not_found',
                 'and can''t tap each other again while matched');

-- Same room only --------------------------------------------------------------------------------
select count(*) from unnest(tests.deck(tests.id('bo'), tests.id('s')));
select is(tests.tap('bo', 'ana_card_s', 's') ->> 'result', 'sent',
          'a tap back in a different room doesn''t make a match: taps only count in the same room');

-- TAP_TTL: a tap older than 24 hours is gone ----------------------------------------------------
update public.taps set created_at = now() - interval '25 hours', expires_at = now() - interval '1 hour'
 where from_user = tests.id('ana') and to_user = tests.id('di');
select count(*) from unnest(tests.deck(tests.id('di'), tests.id('r')));
select is(tests.tap('di', 'ana_card') ->> 'result', 'sent',
          'a tap back after the first tap expired doesn''t make a match (TAP_TTL)');

-- A new day in the room's timezone gives three new taps ----------------------------------------
update public.taps set created_at = private.room_day_start(tests.id('r')) - interval '1 minute'
 where from_user = tests.id('ana') and room_id = tests.id('r');
select is(tests.tap('ana', 'ed_card') ->> 'tapsLeftToday', '2',
          'taps from yesterday (in the room''s timezone) don''t count against today');

-- After an unmatch, old taps can't make a match again -------------------------------------------
select public.unmatch(tests.id('ana'), tests.id('match_ac'));
select ok(tests.id('cy_card') = any (tests.deck(tests.id('ana'), tests.id('r'))), 'after an unmatch they can see each other again');
select is(tests.tap('ana', 'cy_card') ->> 'result', 'sent',
          'tapping again after an unmatch doesn''t reuse their old tap: no instant re-match');
select count(*) from unnest(tests.deck(tests.id('cy'), tests.id('r')));
select is(tests.tap('cy', 'ana_card') ->> 'result', 'mutual',
          'only a fresh tap from both makes a new match');

-- Nothing in a tap result names anyone (P1, P5)
select is((select array_agg(k order by k) from jsonb_object_keys(tests.tap('ana', 'bo_card')) k),
          array['result', 'tapsLeftToday'], 'a sent tap says only sent and how many taps are left');

select * from finish();
rollback;
