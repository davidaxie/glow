-- D2 · 0005_d2_no_passwords.sql: no password session is ever opened, except for @glow.test
-- people on a local stack with allow_test_passwords on (seed.sql). Supabase Auth records how
-- every session was made in auth.mfa_amr_claims; these tests write those rows the way it does,
-- with the setting off (the cloud project) and on (local). Everything is rolled back.
-- server/tests/security/no-passwords.live.test.ts checks the same through the real Auth API.
begin;
create extension if not exists pgtap with schema extensions;
select plan(14);

create schema tests;
create function tests.add_user(p_email text) returns uuid
language plpgsql as $$
declare v_id uuid := gen_random_uuid();
begin
  -- Supabase Auth gives every user a random password, email-code sign-ups included.
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                          raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated',
          p_email, '$2a$10$' || repeat('x', 53), now(), '{}', '{}', now(), now());
  return v_id;
end $$;
-- A session for p_user made with p_method, as Supabase Auth issues one.
create function tests.sign_in(p_user uuid, p_method text) returns uuid
language plpgsql as $$
declare v_session uuid := gen_random_uuid();
begin
  insert into auth.sessions (id, user_id, created_at, updated_at, aal)
  values (v_session, p_user, now(), now(), 'aal1');
  insert into auth.mfa_amr_claims (id, session_id, created_at, updated_at, authentication_method)
  values (gen_random_uuid(), v_session, now(), now(), p_method);
  return v_session;
end $$;

create temporary table t_people on commit drop as
  select tests.add_user('real@example.com') as real_id,
         tests.add_user('tester@glow.test') as test_id,
         tests.add_user('evil@glow.test.example.com') as lookalike_id;

-- Setting off (the cloud project) ------------------------------------------------------------
delete from private.settings where name = 'allow_test_passwords';

select throws_ok($$ select tests.sign_in((select real_id from t_people), 'password') $$,
                 'P0001', 'password_sign_in_disabled',
                 'setting off: a password sign-in (or sign-up that signs in) is refused');
select throws_ok($$ select tests.sign_in((select test_id from t_people), 'password') $$,
                 'P0001', 'password_sign_in_disabled',
                 'setting off: @glow.test can''t sign in with a password either');
select lives_ok($$ select tests.sign_in((select real_id from t_people), 'otp') $$,
                'setting off: email codes still sign in');
select lives_ok($$ select tests.sign_in((select real_id from t_people), 'magiclink') $$,
                'setting off: magic links still sign in');
select lives_ok($$ select tests.sign_in((select real_id from t_people), 'oauth') $$,
                'setting off: Sign in with Apple still signs in');
select lives_ok($$ select tests.sign_in((select real_id from t_people), 'recovery') $$,
                'setting off: a recovery link still signs in (the password it may set never will)');

create temporary table t_session on commit drop as
  select tests.sign_in((select real_id from t_people), 'otp') as id;
select throws_ok($$ update auth.mfa_amr_claims set authentication_method = 'password'
                     where session_id = (select id from t_session) $$,
                 'P0001', 'password_sign_in_disabled',
                 'setting off: an existing session can''t be relabeled as a password session');

-- Setting on (local stacks, seed.sql) --------------------------------------------------------
insert into private.settings (name, value) values ('allow_test_passwords', 'on');

select lives_ok($$ select tests.sign_in((select test_id from t_people), 'password') $$,
                'setting on: @glow.test signs in with a password (dev-token, live tests)');
select throws_ok($$ select tests.sign_in((select real_id from t_people), 'password') $$,
                 'P0001', 'password_sign_in_disabled',
                 'setting on: every other address is still refused');
select throws_ok($$ select tests.sign_in((select lookalike_id from t_people), 'password') $$,
                 'P0001', 'password_sign_in_disabled',
                 'setting on: a look-alike domain is refused');

-- An attacker's test account can't carry a password over to a real address.
update auth.users set email = 'moved@example.com' where id = (select test_id from t_people);
select throws_ok($$ select tests.sign_in((select test_id from t_people), 'password') $$,
                 'P0001', 'password_sign_in_disabled',
                 'setting on: after an email change to a real address, the password stops working');

update private.settings set value = 'off' where name = 'allow_test_passwords';
select throws_ok($$ select tests.sign_in((select lookalike_id from t_people), 'password') $$,
                 'P0001', 'password_sign_in_disabled',
                 'any value but ''on'' counts as off');

select ok(not has_table_privilege('authenticated', 'private.settings', 'SELECT, INSERT, UPDATE, DELETE')
          and not has_table_privilege('anon', 'private.settings', 'SELECT, INSERT, UPDATE, DELETE'),
          'no client can read or change the setting');
select ok(not has_function_privilege('authenticated', 'private.password_session_allowed(text)', 'EXECUTE')
          and not has_function_privilege('anon', 'private.password_session_allowed(text)', 'EXECUTE'),
          'no client can call the check');

select * from finish();
rollback;
