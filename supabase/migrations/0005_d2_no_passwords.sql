-- 0005_d2_no_passwords.sql · D2 · Nobody signs in to Glow with a password
--
-- Glow signs people in with Sign in with Apple or a 6-digit email code, never a password
-- (docs/SPEC.md, Product flow). Supabase Auth still accepts email + password from anyone who
-- has the public anon key, and it has no project setting that turns passwords off while
-- keeping email codes. That allowed a pre-account takeover (docs/SECURITY_REVIEW.md, D2-F1):
--
--   1. An attacker calls POST /auth/v1/signup with the victim's address and a password.
--   2. Later the victim signs in with an email code and lands in that same auth user
--      (with "Confirm email" on or off: the code confirms the address).
--   3. The attacker's password still works, so they read the victim's matches, names,
--      profile photos and chat.
--
-- The same gap let anyone holding a signed-in phone for a moment set a password
-- (PUT /auth/v1/user, or the recovery flow) and keep access from anywhere.
--
-- Refusing passwords on auth.users doesn't work: Supabase Auth gives every new user a random
-- password of its own, email-code and admin sign-ups included. So this refuses the one thing
-- a password is for, a password session. Every session Supabase Auth creates records how it
-- was made in auth.mfa_amr_claims ('password', 'otp', 'magiclink', 'oauth', 'recovery' ...),
-- in the same transaction that issues the tokens. A 'password' claim is refused, so password
-- sign-in (POST /auth/v1/token?grant_type=password), and sign-up with a password when it
-- would sign in straight away, fail with no tokens. Setting, resetting or changing a password
-- or an address still "works", but the password can never open a session. Email codes,
-- magic links, Apple, recovery links and refresh tokens are unaffected.
--
-- The one exception is for local stacks only: when private.settings has
-- allow_test_passwords = 'on', people at the reserved test domain @glow.test may sign in with a
-- password (.test can't receive mail, so nobody can be a victim there). scripts/dev-token.sh and
-- the server's live tests rely on it. Only supabase/seed.sql turns it on, and seed.sql is never
-- loaded on the cloud project (docs/HANDOFFS.md, Needs David), so there every password session
-- is refused, @glow.test included: nobody gets an account without owning a mailbox.

create table private.settings (
  name  text primary key check (name ~ '^[a-z][a-z0-9_]*$'),
  value text not null
);
alter table private.settings enable row level security;
revoke all on table private.settings from public, anon, authenticated;
grant select on table private.settings to service_role;

-- Whether this address may open a password session.
create function private.password_session_allowed(p_email text)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select lower(coalesce(p_email, '')) ~ '^[a-z0-9._+-]+@glow\.test$'
     and exists (select 1 from private.settings s
                  where s.name = 'allow_test_passwords' and s.value = 'on');
$$;

create function private.refuse_password_sessions()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
declare
  v_email text;
begin
  if new.authentication_method is distinct from 'password' then
    return new;
  end if;
  select u.email into v_email
    from auth.sessions s
    join auth.users u on u.id = s.user_id
   where s.id = new.session_id;
  if private.password_session_allowed(v_email) then
    return new;
  end if;
  raise exception using
    errcode = 'P0001',
    message = 'password_sign_in_disabled',
    hint    = 'Glow signs in with Apple or an email code only (0005_d2_no_passwords.sql).';
end;
$$;

revoke all on function private.password_session_allowed(text) from public, anon, authenticated;
revoke all on function private.refuse_password_sessions() from public, anon, authenticated;

create trigger glow_refuse_password_sessions
  before insert or update of authentication_method on auth.mfa_amr_claims
  for each row execute function private.refuse_password_sessions();

-- Password sessions opened before this migration (by the attack above) end now. Their refresh
-- tokens go with them (auth.refresh_tokens references the session and cascades).
delete from auth.sessions s
 where exists (select 1 from auth.mfa_amr_claims c
                where c.session_id = s.id and c.authentication_method = 'password')
   and not private.password_session_allowed((select u.email from auth.users u where u.id = s.user_id));
