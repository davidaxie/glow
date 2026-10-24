-- A2 · The app can never read or write a table directly (RLS on, no client policies, no grants),
-- can't call any database function, and can't read storage. P1, P2, P4.
begin;
create extension if not exists pgtap with schema extensions;

create temporary table glow_tables on commit drop as
  select c.oid::regclass as tbl, n.nspname::text as schema_name, c.relname::text as table_name,
         c.relrowsecurity as rls,
         (select a.attname::text from pg_attribute a
           where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
             and a.attidentity = '' and a.attgenerated = ''
           order by a.attnum limit 1) as first_column
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname in ('public', 'private') and c.relkind in ('r', 'p');
grant select on glow_tables to anon, authenticated;

select plan(15 + 8 * (select count(*)::integer from glow_tables));

-- Structure ------------------------------------------------------------------------------------

select ok((select count(*) from glow_tables) >= 18, 'every table in the data model exists');

select is(array(select table_name from glow_tables where not rls order by 1), '{}'::text[],
          'row level security is on for every table');

select is((select count(*)::integer from pg_policies where schemaname in ('public', 'private')), 0,
          'no table has a policy, so no client can ever match one');

select is(array(select t.table_name from glow_tables t
                 where has_table_privilege('anon', t.tbl, 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
                 order by 1), '{}'::text[],
          'anon has no privilege on any table');

select is(array(select t.table_name from glow_tables t
                 where has_table_privilege('authenticated', t.tbl, 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
                 order by 1), '{}'::text[],
          'authenticated has no privilege on any table');

select is(array(select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname in ('public', 'private')
                   and (has_function_privilege('anon', p.oid, 'EXECUTE')
                        or (has_function_privilege('authenticated', p.oid, 'EXECUTE')
                            and p.oid <> 'private.can_receive_topic(text)'::regprocedure))
                 order by 1), '{}'::text[],
          'neither anon nor authenticated can call any database function (except the Realtime check)');

select ok(has_function_privilege('service_role', 'public.record_tap(uuid,uuid,uuid)', 'EXECUTE'),
          'the service role (the server) can call the database functions');

select is(array(select c.relname::text from pg_class c join pg_namespace n on n.oid = c.relnamespace
                 where n.nspname in ('public', 'private') and c.relkind = 'S'
                   and (has_sequence_privilege('anon', c.oid, 'USAGE, SELECT, UPDATE')
                        or has_sequence_privilege('authenticated', c.oid, 'USAGE, SELECT, UPDATE'))),
          '{}'::text[], 'no client can use any sequence');

-- P2: user coordinates are never stored. Only rooms (public venues) have a location.
select is(array(select table_name || '.' || column_name from information_schema.columns
                 where table_schema in ('public', 'private') and table_name <> 'rooms'
                   and column_name ~ '(^|_)(lat|lng|lon|latitude|longitude|coord|coords|coordinates|geo|location|accuracy|distance)($|_)'
                   and column_name <> 'accuracy_bucket'
                 order by 1), '{}'::text[],
          'no table outside rooms has a coordinate, accuracy or distance column (P2)');

-- Later migrations stay closed by default.
create table public.pgtap_future_table (id integer);
create function public.pgtap_future_fn() returns integer language sql as $$ select 1 $$;
select ok(not has_table_privilege('authenticated', 'public.pgtap_future_table', 'SELECT, INSERT, UPDATE, DELETE')
          and not has_table_privilege('anon', 'public.pgtap_future_table', 'SELECT, INSERT, UPDATE, DELETE'),
          'a table added by a later migration is closed to clients by default');
select ok(not has_function_privilege('authenticated', 'public.pgtap_future_fn()', 'EXECUTE')
          and not has_function_privilege('anon', 'public.pgtap_future_fn()', 'EXECUTE'),
          'a function added by a later migration is closed to clients by default');
drop function public.pgtap_future_fn();
drop table public.pgtap_future_table;

-- Storage (P4) --------------------------------------------------------------------------------

select is(array(select id || '=' || public::text from storage.buckets
                 where id in ('profile-photos', 'room-cards') order by id),
          array['profile-photos=false', 'room-cards=false'],
          'both buckets exist and are private');

insert into storage.objects (bucket_id, name) values
  ('room-cards', 'de000000-0000-4000-8000-000000000001/pgtap.jpg'),
  ('profile-photos', '7e570000-0000-4000-8000-000000000001/pgtap.jpg');

set local role authenticated;
set local request.jwt.claims to '{"sub": "7e570000-0000-4000-8000-000000000001", "role": "authenticated"}';

select is((select count(*)::integer from storage.objects where bucket_id in ('room-cards', 'profile-photos')), 0,
          'a signed-in person sees no object in either bucket, not even their own');

select throws_ok($$ insert into storage.objects (bucket_id, name) values ('room-cards', 'x/y.jpg') $$, '42501', null,
                 'a signed-in person cannot upload to a bucket directly');

-- Direct table access, as a signed-in person and as anon -------------------------------------

select throws_ok(format('select * from %s limit 1', t.tbl), '42501', null,
                 format('signed in: can''t read %s.%s', t.schema_name, t.table_name))
  from glow_tables t order by t.schema_name, t.table_name;
select throws_ok(format('insert into %s default values', t.tbl), '42501', null,
                 format('signed in: can''t insert into %s.%s', t.schema_name, t.table_name))
  from glow_tables t order by t.schema_name, t.table_name;
select throws_ok(format('update %s set %I = %I', t.tbl, t.first_column, t.first_column), '42501', null,
                 format('signed in: can''t update %s.%s', t.schema_name, t.table_name))
  from glow_tables t order by t.schema_name, t.table_name;
select throws_ok(format('delete from %s', t.tbl), '42501', null,
                 format('signed in: can''t delete from %s.%s', t.schema_name, t.table_name))
  from glow_tables t order by t.schema_name, t.table_name;

reset role;
set local role anon;
set local request.jwt.claims to '{"role": "anon"}';

select throws_ok(format('select * from %s limit 1', t.tbl), '42501', null,
                 format('anon: can''t read %s.%s', t.schema_name, t.table_name))
  from glow_tables t order by t.schema_name, t.table_name;
select throws_ok(format('insert into %s default values', t.tbl), '42501', null,
                 format('anon: can''t insert into %s.%s', t.schema_name, t.table_name))
  from glow_tables t order by t.schema_name, t.table_name;
select throws_ok(format('update %s set %I = %I', t.tbl, t.first_column, t.first_column), '42501', null,
                 format('anon: can''t update %s.%s', t.schema_name, t.table_name))
  from glow_tables t order by t.schema_name, t.table_name;
select throws_ok(format('delete from %s', t.tbl), '42501', null,
                 format('anon: can''t delete from %s.%s', t.schema_name, t.table_name))
  from glow_tables t order by t.schema_name, t.table_name;

reset role;

select throws_ok($$ set local role anon; select public.get_deck('7e570000-0000-4000-8000-000000000001',
                                                               'de000000-0000-4000-8000-000000000001') $$,
                 '42501', null, 'anon cannot call a database function');

select * from finish();
rollback;
