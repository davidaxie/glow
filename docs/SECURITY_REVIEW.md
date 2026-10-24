# Security and privacy review

Owner: D2 (Wave 3). The full review lands with D2's PR on `w3/d2-security`; this file starts with the finding fixed in `w3/d2-fix-passwords`.

Every finding has a severity (critical, high, medium, low, info), a repro, a fix and a status. High and critical findings are fixed through small `security` + `cross-owner` PRs on the owner's files and retested here.

## Findings

<a id="d2-f1"></a>

### D2-F1 · High · Pre-account takeover through password sign-up

**Status:** fixed in `w3/d2-fix-passwords` (migration `0005_d2_no_passwords.sql`), retested.

**What.** Glow signs in with Apple or a 6-digit email code. Supabase Auth also accepts email and password from anyone with the public anon key, and it puts a sign-up and a later email-code sign-in for the same address into the same auth user.

**Repro** (D2's own stack, `curl` or `server/tests/security/no-passwords.live.test.ts` with the trigger disabled):

1. The attacker sends `POST /auth/v1/signup` with `{ "email": "<victim's address>", "password": "<theirs>" }` and the anon key.
2. The victim later signs in with an email code, which works and confirms the address.
3. `POST /auth/v1/token?grant_type=password` with the attacker's password returns a session for the victim's account. From there the attacker can read the victim's matches (first names and profile photos) and chat. This works with "Confirm email" on or off.

The same gap lets anyone holding a signed-in phone for a moment set a password (`PUT /auth/v1/user`, or the recovery flow) and keep access from anywhere.

**Fix.** Supabase has no setting that turns off passwords but keeps email codes, and it gives every new user a random password, so refusing passwords on `auth.users` would break every sign-up (D2 tried it; that version failed). Instead, a trigger on `auth.mfa_amr_claims` refuses any session made with a password. Supabase writes that row in the same transaction that issues the tokens.

- Email codes, magic links, Apple, recovery links and refresh tokens are unchanged.
- "Confirm email" must stay on, and is now on in local `config.toml` too.
- Local stacks only: `@glow.test` people can still sign in with a password when `private.settings.allow_test_passwords = 'on'`. Only `seed.sql` sets it.
- Password sessions that existed before the migration are deleted (D2-D1).

**Tests.**

- `supabase/tests/database/100_d2_no_passwords.test.sql` covers the setting off (cloud) and on (local): sign-in, sign-up that signs in, relabeling a session, look-alike domains, and moving a test account to a real address.
- `server/tests/security/no-passwords.live.test.ts` runs through the real Auth API:
  - email-code sign-up still works
  - the pre-registration attack fails before and after the victim arrives
  - a password set through `PUT /auth/v1/user`, the recovery flow or the admin API never signs in
  - the `@glow.test` path that dev-token and CI smoke rely on still works
  - B1's test sign-in flow still works
- Positive control: with the trigger disabled, 5 of the 7 live tests fail.

**Cloud settings.** D2 found no hosted toggle that rejects password sign-up on its own. Under Providers → Email there's only the provider on/off, Confirm email, Secure email change, Secure password change, the password rules and OTP length and expiry. D2 can't check a cloud project (there isn't one).

A Password Verification Attempt Auth Hook could reject every password, but as far as D2 knows it's limited to some plans. The migration works on any plan. Recommended settings are in `docs/HANDOFFS.md` (Needs David):

- Confirm email on
- Secure email change on
- Email OTP expiry 600 s
- Anonymous sign-ins, phone and manual linking off
- Optional CAPTCHA
