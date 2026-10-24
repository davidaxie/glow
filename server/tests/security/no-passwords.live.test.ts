/**
 * D2-F1 (docs/SECURITY_REVIEW.md): nobody can sign in to Glow with a password, so nobody can
 * pre-register someone else's address and wait for them to arrive. Every attack goes through
 * the real Supabase Auth API with the app's public anon key, on a local stack that has
 * 0005_d2_no_passwords.sql and the seed (allow_test_passwords on, so the @glow.test exception
 * CI's smoke test and dev-token rely on is checked too). The same rules with the setting off,
 * as on the cloud project, are in supabase/tests/database/100_d2_no_passwords.test.sql.
 */
import { afterAll, describe, expect, it } from 'vitest';
import { LIVE, supa, tag, type Live } from './helpers/live';

const live = LIVE as Live;
const made: string[] = [];

afterAll(async () => {
  if (!LIVE) return;
  for (const id of made)
    await supa(live, 'DELETE', `/auth/v1/admin/users/${id}`, { key: 'service' });
});

const password = () => `Attacker-${tag()}-${tag()}`;

async function remember(email: string): Promise<string | null> {
  const list = await supa(live, 'GET', `/auth/v1/admin/users?per_page=1000`, { key: 'service' });
  const users = (list.json.users ?? []) as { id: string; email?: string }[];
  const id = users.find((u) => u.email === email)?.id ?? null;
  if (id && !made.includes(id)) made.push(id);
  return id;
}

/** What the victim's email would bring: a 6-digit code, minted with the admin API. */
async function emailCodeSignIn(email: string): Promise<{ id: string; token: string }> {
  const ask = await supa(live, 'POST', '/auth/v1/otp', { body: { email, create_user: true } });
  expect([200, 429]).toContain(ask.status); // 429: Auth's resend interval; the code below works
  const link = await supa(live, 'POST', '/auth/v1/admin/generate_link', {
    key: 'service',
    body: { type: 'magiclink', email },
  });
  expect(link.status).toBe(200);
  const code = (link.json.email_otp ??
    (link.json.properties as Record<string, unknown>)?.email_otp) as string;
  const verified = await supa(live, 'POST', '/auth/v1/verify', {
    body: { type: 'email', email, token: code },
  });
  expect(verified.status).toBe(200);
  const user = verified.json.user as { id: string };
  if (!made.includes(user.id)) made.push(user.id);
  return { id: user.id, token: verified.json.access_token as string };
}

async function passwordSignIn(email: string, pw: string): Promise<Reply> {
  return supa(live, 'POST', '/auth/v1/token?grant_type=password', {
    body: { email, password: pw },
  });
}
type Reply = Awaited<ReturnType<typeof supa>>;

describe.skipIf(!LIVE)('D2-F1: no password sign-in (live Supabase Auth)', () => {
  it('a new person can still sign up with an email code', async () => {
    const email = `d2-new-${tag()}@example.com`;
    const me = await emailCodeSignIn(email);
    expect(me.token).toMatch(/^ey/);
  });

  it('pre-registering the victim with a password gives the attacker nothing, before or after', async () => {
    const victim = `d2-victim-${tag()}@example.com`;
    const pw = password();

    const signup = await supa(live, 'POST', '/auth/v1/signup', {
      body: { email: victim, password: pw },
    });
    expect(signup.json.access_token).toBeUndefined();
    await remember(victim);
    expect((await passwordSignIn(victim, pw)).json.access_token).toBeUndefined();

    // The victim arrives later and signs in with an email code, into the same auth user.
    const me = await emailCodeSignIn(victim);
    expect(me.token).toMatch(/^ey/);

    const later = await passwordSignIn(victim, pw);
    expect(later.status).not.toBe(200);
    expect(later.json.access_token).toBeUndefined();
  });

  it('a signed-in person (or whoever holds their phone) can set a password, but never use it', async () => {
    const email = `d2-phone-${tag()}@example.com`;
    const me = await emailCodeSignIn(email);
    const pw = password();
    await supa(live, 'PUT', '/auth/v1/user', { token: me.token, body: { password: pw } });
    const attempt = await passwordSignIn(email, pw);
    expect(attempt.status).not.toBe(200);
    expect(attempt.json.access_token).toBeUndefined();
  });

  it('the recovery flow can set a password, but never use it', async () => {
    const email = `d2-recover-${tag()}@example.com`;
    await emailCodeSignIn(email);
    expect([200, 429]).toContain(
      (await supa(live, 'POST', '/auth/v1/recover', { body: { email } })).status,
    );
    const link = await supa(live, 'POST', '/auth/v1/admin/generate_link', {
      key: 'service',
      body: { type: 'recovery', email },
    });
    const code = (link.json.email_otp ??
      (link.json.properties as Record<string, unknown>)?.email_otp) as string;
    const recovered = await supa(live, 'POST', '/auth/v1/verify', {
      body: { type: 'recovery', email, token: code },
    });
    expect(recovered.status).toBe(200);
    const pw = password();
    await supa(live, 'PUT', '/auth/v1/user', {
      token: recovered.json.access_token as string,
      body: { password: pw },
    });
    expect((await passwordSignIn(email, pw)).json.access_token).toBeUndefined();
  });

  it("an account the admin API makes with a password for a real address can't use it", async () => {
    const email = `d2-admin-${tag()}@example.com`;
    const pw = password();
    const created = await supa(live, 'POST', '/auth/v1/admin/users', {
      key: 'service',
      body: { email, password: pw, email_confirm: true },
    });
    if (created.json.id) made.push(created.json.id as string);
    expect((await passwordSignIn(email, pw)).json.access_token).toBeUndefined();
  });

  it('local stacks only: a @glow.test person signs in with a password (dev-token, CI smoke)', async () => {
    const email = `d2-test-${tag()}@glow.test`;
    const pw = password();
    const created = await supa(live, 'POST', '/auth/v1/admin/users', {
      key: 'service',
      body: { email, password: pw, email_confirm: true },
    });
    expect(created.status).toBe(200);
    made.push(created.json.id as string);
    const ok = await passwordSignIn(email, pw);
    expect(ok.status).toBe(200);
    expect(ok.json.access_token).toMatch(/^ey/);

    // Moved to a real address, the password stops working.
    const real = `d2-moved-${tag()}@example.com`;
    await supa(live, 'PUT', `/auth/v1/admin/users/${created.json.id as string}`, {
      key: 'service',
      body: { email: real, email_confirm: true },
    });
    expect((await passwordSignIn(real, pw)).json.access_token).toBeUndefined();
  });

  it("the test sign-in route's flow (admin magic link, then verify) still works", async () => {
    const email = `d2-testlogin-${tag()}@glow.test`;
    const link = await supa(live, 'POST', '/auth/v1/admin/generate_link', {
      key: 'service',
      body: { type: 'magiclink', email },
    });
    expect(link.status).toBe(200);
    const hash = (link.json.hashed_token ??
      (link.json.properties as Record<string, unknown>)?.hashed_token) as string;
    const verified = await supa(live, 'POST', '/auth/v1/verify', {
      body: { type: 'email', token_hash: hash },
    });
    expect(verified.status).toBe(200);
    made.push((verified.json.user as { id: string }).id);
  });
});
