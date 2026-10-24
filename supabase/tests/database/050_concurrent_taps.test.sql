-- A2 · 50 pairs tapping each other at the same moment make exactly 50 matches.
--
-- Real concurrency needs real sessions, so this test uses dblink: it commits its own test data
-- through a separate connection (pgTAP's transaction is invisible to other sessions), opens 100
-- connections, queues one record_tap on each behind an advisory-lock gate, waits until all 100
-- are blocked on the gate, then opens it so every tap starts at once. Afterwards it deletes the
-- test data again. Needs max_connections above 100 (supabase/config.toml sets 200).
begin;
create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;
select plan(9);

-- dblink needs a password login, which the database only asks for on its network address.
create function pg_temp.connstr() returns text language sql as $$
  select format('host=%s port=%s dbname=%s user=postgres password=postgres connect_timeout=10',
                coalesce(host(inet_server_addr()), '127.0.0.1'), coalesce(inet_server_port(), 5432),
                current_database());
$$;

create function pg_temp.cleanup_sql() returns text language sql as $$ select $cleanup$
  delete from auth.users where email like 'pgtap-race-%@glow.test';
  delete from public.rooms where id = 'ace00000-0000-4000-8000-000000000001';
$cleanup$ $$;

create function pg_temp.setup_sql() returns text language sql as $$ select pg_temp.cleanup_sql() || $setup$
do $do$
declare
  v_room uuid := 'ace00000-0000-4000-8000-000000000001';
  a uuid; b uuid; ca uuid; cb uuid;
begin
  insert into public.rooms (id, slug, name, lat, lng, starts_at, ends_at)
  values (v_room, 'pgtap-race', 'Race test (pgTAP)', 37.80, -122.45, now() - interval '1 hour', now() + interval '1 day');
  for i in 1..50 loop
    a  := format('aaa00000-0000-4000-8000-%s', lpad(i::text, 12, '0'))::uuid;
    b  := format('bbb00000-0000-4000-8000-%s', lpad(i::text, 12, '0'))::uuid;
    ca := format('caa00000-0000-4000-8000-%s', lpad(i::text, 12, '0'))::uuid;
    cb := format('cbb00000-0000-4000-8000-%s', lpad(i::text, 12, '0'))::uuid;
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                            raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    values ('00000000-0000-0000-0000-000000000000', a, 'authenticated', 'authenticated',
            'pgtap-race-a' || i || '@glow.test', '', now(), '{}', '{}', now(), now()),
           ('00000000-0000-0000-0000-000000000000', b, 'authenticated', 'authenticated',
            'pgtap-race-b' || i || '@glow.test', '', now(), '{}', '{}', now(), now());
    update public.profiles set first_name = 'Racer A' || i, birthdate = date '1996-05-05', gender = 'woman',
                               show_me = '{man}', onboarding_step = 'complete' where id = a;
    update public.profiles set first_name = 'Racer B' || i, birthdate = date '1996-05-05', gender = 'man',
                               show_me = '{woman}', onboarding_step = 'complete' where id = b;
    insert into public.location_checks (user_id, room_id, purpose, result, accuracy_bucket)
    values (a, v_room, 'join', 'pass', 'under_20m'), (b, v_room, 'join', 'pass', 'under_20m');
    perform public.create_checkin(a, v_room, ca, v_room::text || '/' || ca::text || '.jpg', '{"topColor": "blue"}');
    perform public.create_checkin(b, v_room, cb, v_room::text || '/' || cb::text || '.jpg', '{"topColor": "red"}');
    -- Each has been shown the other's card, as get_deck would record it.
    insert into public.card_views (viewer_id, checkin_id, room_id, view_day)
    values (a, cb, v_room, private.room_day(v_room)), (b, ca, v_room, private.room_day(v_room));
  end loop;
end $do$;
$setup$ $$;

create temporary table race_results (pair integer, side text, result jsonb);
create temporary table race_gate (queued integer);

create function pg_temp.race() returns void language plpgsql as $$
declare
  v_conn   text := pg_temp.connstr();
  v_room   uuid := 'ace00000-0000-4000-8000-000000000001';
  v_queued integer := 0;
  v_tries  integer := 0;
  v_result text;
  a uuid; b uuid; ca uuid; cb uuid;
begin
  perform dblink_connect('race_gate', v_conn);
  perform dblink_exec('race_gate', pg_temp.setup_sql());
  -- Close the gate.
  perform * from dblink('race_gate', 'select pg_advisory_lock(7351001)::text') as t(x text);

  for i in 1..50 loop
    a  := format('aaa00000-0000-4000-8000-%s', lpad(i::text, 12, '0'))::uuid;
    b  := format('bbb00000-0000-4000-8000-%s', lpad(i::text, 12, '0'))::uuid;
    ca := format('caa00000-0000-4000-8000-%s', lpad(i::text, 12, '0'))::uuid;
    cb := format('cbb00000-0000-4000-8000-%s', lpad(i::text, 12, '0'))::uuid;
    perform dblink_connect('race_a' || i, v_conn);
    perform dblink_connect('race_b' || i, v_conn);
    -- Each tap is its own transaction, like a PostgREST rpc call, and waits at the gate first.
    perform dblink_send_query('race_a' || i, format(
      'select public.record_tap(%L, %L, %L)::text from (select pg_advisory_xact_lock_shared(7351001)) gate', a, v_room, cb));
    perform dblink_send_query('race_b' || i, format(
      'select public.record_tap(%L, %L, %L)::text from (select pg_advisory_xact_lock_shared(7351001)) gate', b, v_room, ca));
  end loop;

  -- Wait until all 100 taps are blocked on the gate.
  loop
    select count(*) into v_queued from pg_locks
     where locktype = 'advisory' and classid = 0 and objid = 7351001 and not granted;
    exit when v_queued >= 100 or v_tries >= 400;
    perform pg_sleep(0.05);
    v_tries := v_tries + 1;
  end loop;
  insert into race_gate values (v_queued);

  -- Open the gate: every tap starts at the same moment.
  perform * from dblink('race_gate', 'select pg_advisory_unlock(7351001)::text') as t(x text);

  for i in 1..50 loop
    select x into v_result from dblink_get_result('race_a' || i) as t(x text);
    insert into race_results values (i, 'a', v_result::jsonb);
    perform * from dblink_get_result('race_a' || i) as t(x text);
    select x into v_result from dblink_get_result('race_b' || i) as t(x text);
    insert into race_results values (i, 'b', v_result::jsonb);
    perform * from dblink_get_result('race_b' || i) as t(x text);
    perform dblink_disconnect('race_a' || i);
    perform dblink_disconnect('race_b' || i);
  end loop;
  perform dblink_disconnect('race_gate');
end $$;

select pg_temp.race();

select is((select queued from race_gate), 100, 'all 100 taps were waiting at the gate and started together');
select is((select count(*)::integer from race_results where result is not null), 100, 'every tap returned a result');
select is((select count(*)::integer from public.matches where room_id = 'ace00000-0000-4000-8000-000000000001'), 50,
          '50 pairs tapping each other at the same moment make exactly 50 matches');
select is((select count(distinct (user_a, user_b))::integer from public.matches
            where room_id = 'ace00000-0000-4000-8000-000000000001'), 50,
          'one match per pair, never two');
select is((select count(*)::integer from race_results where result ->> 'result' = 'mutual'), 50,
          'exactly one tap of each pair saw the other and said mutual');
select is((select count(*)::integer from (
             select pair from race_results group by pair
             having count(*) filter (where result ->> 'result' = 'mutual') = 1
                and count(*) filter (where result ->> 'result' = 'sent') = 1) x), 50,
          'in every pair, one tap says sent and the other says mutual');
select set_eq($$ select (result ->> 'matchId')::uuid from race_results where result ->> 'result' = 'mutual' $$,
              $$ select id from public.matches where room_id = 'ace00000-0000-4000-8000-000000000001' $$,
              'the match IDs handed back are exactly the matches made');
select is((select count(*)::integer from public.taps
            where room_id = 'ace00000-0000-4000-8000-000000000001' and match_id is not null), 100,
          'all 100 taps are marked as used by their match');

select dblink_exec(pg_temp.connstr(), pg_temp.cleanup_sql());
select is((select count(*)::integer from auth.users where email like 'pgtap-race-%@glow.test'), 0,
          'the test removed its data');

select * from finish();
rollback;
