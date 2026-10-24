-- A2 · Realtime authorization: a person may join only user:{their id}, and room:{id} only with an
-- an open check-in there. Nobody sends from the app, and presence is never allowed.
-- Uses realtime.authorize, the same check the Realtime server runs when a client joins.
begin;
create extension if not exists pgtap with schema extensions;
select plan(14);

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
-- [receive broadcast, receive presence] and [send broadcast, send presence] for a person and topic.
create function tests.access(p_user uuid, p_topic text, out reads boolean[], out writes boolean[])
language sql as $$
  select read_allowed, write_allowed
  from realtime.authorize(
    case when p_user is null then 'anon' else 'authenticated' end,
    p_topic,
    case when p_user is null then '{"role": "anon"}'
         else json_build_object('sub', p_user, 'role', 'authenticated')::text end,
    coalesce(p_user::text, ''),
    '{}',
    array['broadcast', 'presence'],
    array['broadcast', 'presence']);
$$;

create temporary table ids (k text primary key, v uuid);
insert into ids values
  ('a', tests.person('Ada', 'woman', '{man}')),
  ('b', tests.person('Ben', 'man', '{woman}')),
  ('r', tests.room('rt-r')),
  ('s', tests.room('rt-s'));
create function tests.id(p_key text) returns uuid language sql as $$ select v from ids where k = p_key $$;
insert into ids values ('a_card', tests.check_in(tests.id('a'), tests.id('r')));

-- user:{id} ----------------------------------------------------------------------------------
select is((tests.access(tests.id('a'), 'user:' || tests.id('a'))).reads, array[true, false],
          'a person can receive broadcasts on their own user channel, but not presence');
select is((tests.access(tests.id('a'), 'user:' || tests.id('a'))).writes, array[false, false],
          'a person can''t send broadcasts or presence on their own user channel');
select is((tests.access(tests.id('b'), 'user:' || tests.id('a'))).reads, array[false, false],
          'one person can''t join another person''s user channel');
select is((tests.access(tests.id('a'), 'user:' || upper(tests.id('a')::text))).reads, array[false, false],
          'topics are lowercase UUIDs; an uppercase one is refused');
select is((tests.access(null, 'user:' || tests.id('a'))).reads, array[false, false],
          'anon can''t join a user channel');

-- room:{id} ----------------------------------------------------------------------------------
select is((tests.access(tests.id('a'), 'room:' || tests.id('r'))).reads, array[true, false],
          'a person with an open check-in can receive room broadcasts, but never presence');
select is((tests.access(tests.id('a'), 'room:' || tests.id('r'))).writes, array[false, false],
          'nobody can send on a room channel from the app');
select is((tests.access(tests.id('b'), 'room:' || tests.id('r'))).reads, array[false, false],
          'a person without a check-in there can''t join the room channel');
select is((tests.access(tests.id('a'), 'room:' || tests.id('s'))).reads, array[false, false],
          'a check-in in one room doesn''t open another room''s channel');
select is((tests.access(null, 'room:' || tests.id('r'))).reads, array[false, false],
          'anon can''t join a room channel');

update public.checkins set joined_at = now() - interval '4 hours', expires_at = now() - interval '1 minute'
 where id = tests.id('a_card');
select is((tests.access(tests.id('a'), 'room:' || tests.id('r'))).reads, array[false, false],
          'once the check-in expires, the room channel is closed to them');

update public.checkins set joined_at = now(), expires_at = now() + interval '1 hour', left_at = now()
 where id = tests.id('a_card');
select is((tests.access(tests.id('a'), 'room:' || tests.id('r'))).reads, array[false, false],
          'after leaving, the room channel is closed to them');

-- Anything else ------------------------------------------------------------------------------
select is((tests.access(tests.id('a'), 'room:not-a-uuid')).reads, array[false, false],
          'a malformed room topic is refused');
select is((tests.access(tests.id('a'), 'everyone')).reads, array[false, false],
          'any other topic is refused');

select * from finish();
rollback;
