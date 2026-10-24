-- seed.sql · A2 · LOCAL DEVELOPMENT ONLY. TEST DATA. Never run against a real project.
--
-- `supabase db reset` loads this after the migrations. Everything here is fake:
--   * one demo room, slug "demo", at a PLACEHOLDER venue (see docs/DECISIONS.md, "Placeholder venue")
--   * its meeting spots
--   * test people, all with @glow.test emails and first names starting with "Test"
--
-- Fixed values other tools rely on (also in docs/HANDOFFS.md):
--   room id          de000000-0000-4000-8000-000000000001
--   slug             demo
--   code             HACK26
--   static QR token  DEMOSTATICTOKEN2   (allow_static_qr is on)
--   qr_secret (hex)  00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff
--   center           37.8029, -122.4484  (radius 200 m, America/Los_Angeles)
--   link             https://{DOMAIN}/r/demo?t=DEMOSTATICTOKEN2   or   glow://r/demo?t=DEMOSTATICTOKEN2

-------------------------------------------------------------------------------
-- Demo room (placeholder venue: Palace of Fine Arts, San Francisco)
-------------------------------------------------------------------------------

insert into public.rooms (
  id, slug, name, code, lat, lng, radius_m, timezone,
  qr_secret, static_qr_token, allow_static_qr, demo_mode, status, starts_at, ends_at)
values (
  'de000000-0000-4000-8000-000000000001',
  'demo',
  'Glow demo room (test data)',
  'HACK26',
  37.8029, -122.4484, 200, 'America/Los_Angeles',
  '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff',
  'DEMOSTATICTOKEN2',
  true,
  false,
  'live',
  now() - interval '1 day',
  now() + interval '30 days');

insert into public.meeting_spots (id, room_id, name, sort) values
  ('de000000-0000-4000-8000-0000000005f1', 'de000000-0000-4000-8000-000000000001', 'Main entrance',  0),
  ('de000000-0000-4000-8000-0000000005f2', 'de000000-0000-4000-8000-000000000001', 'Food line',      1),
  ('de000000-0000-4000-8000-0000000005f3', 'de000000-0000-4000-8000-000000000001', 'Water station',  2),
  ('de000000-0000-4000-8000-0000000005f4', 'de000000-0000-4000-8000-000000000001', 'Stage left',     3);

-------------------------------------------------------------------------------
-- Test people. IDs start with 7e570000 ("test"). No passwords: sign in with the email code
-- (codes show up in Mailpit at http://127.0.0.1:54424) or B1's Debug test sign-in.
-- The auth trigger creates each profile; the update below fills it in.
-------------------------------------------------------------------------------

with people (id, email) as (
  values
    ('7e570000-0000-4000-8000-000000000001'::uuid, 'alex@glow.test'),
    ('7e570000-0000-4000-8000-000000000002'::uuid, 'blake@glow.test'),
    ('7e570000-0000-4000-8000-000000000003'::uuid, 'casey@glow.test'),
    ('7e570000-0000-4000-8000-000000000004'::uuid, 'drew@glow.test'),
    ('7e570000-0000-4000-8000-000000000005'::uuid, 'admin@glow.test'),
    ('7e570000-0000-4000-8000-000000000006'::uuid, 'new@glow.test')
)
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  confirmation_token, recovery_token, email_change_token_new, email_change,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at, is_sso_user, is_anonymous)
select
  '00000000-0000-0000-0000-000000000000', p.id, 'authenticated', 'authenticated', p.email, '', now(),
  '', '', '', '',
  '{"provider": "email", "providers": ["email"]}'::jsonb,
  '{"glow_test_data": true}'::jsonb,
  now(), now(), false, false
from people p;

insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
select u.id::text, u.id,
       jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
       'email', now(), now(), now()
from auth.users u
where u.email like '%@glow.test';

update public.profiles p
   set first_name      = v.first_name,
       birthdate       = v.birthdate,
       gender          = v.gender,
       show_me         = v.show_me,
       onboarding_step = v.step
  from (values
    ('7e570000-0000-4000-8000-000000000001'::uuid, 'Test Alex',  date '1999-04-12',
      'woman'::public.gender,     array['man']::public.gender[],                        'complete'::public.onboarding_step),
    ('7e570000-0000-4000-8000-000000000002'::uuid, 'Test Blake', date '1998-09-30',
      'man'::public.gender,       array['woman']::public.gender[],                      'complete'::public.onboarding_step),
    ('7e570000-0000-4000-8000-000000000003'::uuid, 'Test Casey', date '2001-01-05',
      'nonbinary'::public.gender, array['woman', 'man', 'nonbinary']::public.gender[],  'complete'::public.onboarding_step),
    ('7e570000-0000-4000-8000-000000000004'::uuid, 'Test Drew',  date '2000-06-21',
      'woman'::public.gender,     array['woman', 'nonbinary']::public.gender[],         'complete'::public.onboarding_step),
    ('7e570000-0000-4000-8000-000000000005'::uuid, 'Test Admin', date '1995-11-02',
      'man'::public.gender,       array['woman']::public.gender[],                      'complete'::public.onboarding_step),
    ('7e570000-0000-4000-8000-000000000006'::uuid, null,         null,
      null,                       array[]::public.gender[],                             'profile'::public.onboarding_step)
  ) as v (id, first_name, birthdate, gender, show_me, step)
 where p.id = v.id;

insert into public.admins (user_id) values ('7e570000-0000-4000-8000-000000000005');

-- Local stacks only: @glow.test people may sign in with a password, for scripts/dev-token.sh and the
-- server's live tests (0005_d2_no_passwords.sql). Never set on the cloud project, which
-- doesn't load this file, so there every password sign-in is refused.
insert into private.settings (name, value) values ('allow_test_passwords', 'on')
on conflict (name) do update set value = excluded.value;
