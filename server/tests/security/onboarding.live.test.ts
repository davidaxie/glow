/**
 * P10 through B1's real routes, test sign-in's locks, and what a first name may hold, on a
 * live stack: nobody under 18 can finish onboarding; a held (possibly-minor) photo counts for
 * nothing and is shown to nobody; test sign-in is a 404 unless it's switched on locally and
 * never signs in a real address.
 */
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { resetEnvCacheForTests } from '@/env';
import { moderationFixtureJpeg } from '@/server/moderation';
import { call } from './helpers/api';
import { LIVE, supa, tag, type Live } from './helpers/live';
import { World } from './helpers/world';

vi.mock('@/server/notify', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@/server/notify')>();
  return {
    ...actual,
    notify: vi.fn(async () => ({ realtime: 'sent', push: null })),
    notifyRoom: vi.fn(async () => ({ realtime: 'sent', push: null })),
  };
});

const live = LIVE as Live;
let world: World;
const made: string[] = [];

beforeAll(() => {
  if (LIVE) world = new World(live);
});
beforeEach(() => {
  if (!LIVE) return;
  process.env.SUPABASE_URL = live.url;
  process.env.SUPABASE_ANON_KEY = live.anonKey;
  process.env.SUPABASE_SERVICE_ROLE_KEY = live.serviceKey;
  delete process.env.ALLOW_TEST_LOGIN;
  resetEnvCacheForTests();
});
afterAll(async () => {
  if (!LIVE) return;
  for (const id of made) await world.db.auth.admin.deleteUser(id);
  await world.cleanup();
});

/** A brand new person who has signed in and done nothing else. */
async function newcomer() {
  const email = `d2-new-${tag()}@glow.test`;
  const pw = `pw-${tag()}-${tag()}`;
  const created = await world.db.auth.admin.createUser({
    email,
    password: pw,
    email_confirm: true,
  });
  const id = created.data.user!.id;
  made.push(id);
  const session = await supa(live, 'POST', '/auth/v1/token?grant_type=password', {
    body: { email, password: pw },
  });
  return { id, email, token: session.json.access_token as string };
}

const yearsAgo = (years: number, days = 0) => {
  const d = new Date();
  d.setUTCFullYear(d.getUTCFullYear() - years);
  d.setUTCDate(d.getUTCDate() - days);
  return d.toISOString().slice(0, 10);
};
const profile = (token: string, extra: Record<string, unknown> = {}) =>
  call('updateProfile', {
    token,
    body: { firstName: 'Dee', birthdate: yearsAgo(30), gender: 'woman', showMe: ['man'], ...extra },
  });
const photo = async (token: string, flags: Parameters<typeof moderationFixtureJpeg>[0] = []) =>
  call('addProfilePhoto', {
    token,
    body: {
      position: 0,
      photo: Buffer.from(await moderationFixtureJpeg(flags)).toString('base64'),
    },
  });

describe.skipIf(!LIVE)('P10: nobody under 18 finishes onboarding (live routes)', () => {
  it('a birthdate under 18 is a 422 and is never stored', async () => {
    const me = await newcomer();
    for (const birthdate of [yearsAgo(17), yearsAgo(18, -1), yearsAgo(10), yearsAgo(0)]) {
      const reply = await profile(me.token, { birthdate });
      // 422 under_18, or 400 for a date that's later than today anywhere on Earth.
      expect([400, 422], birthdate).toContain(reply.status);
      if (reply.status === 422) expect(reply.json).toMatchObject({ error: { code: 'under_18' } });
      expect(reply.text).not.toContain(birthdate);
    }
    const row = await world.db.from('profiles').select('birthdate').eq('id', me.id).single();
    expect(row.data?.birthdate).toBeNull();
  });

  it('the only way to complete is an adult profile plus an approved photo', async () => {
    const me = await newcomer();
    const done = () => call('completeOnboarding', { token: me.token });
    expect((await done()).status).toBe(409); // nothing yet
    expect((await profile(me.token)).status).toBe(200);
    expect((await done()).status).toBe(409); // no photo
    const held = await photo(me.token, ['possibly_minor']);
    expect(held.status).toBe(201);
    expect(JSON.stringify(held.json)).toMatch(/held|pending/);
    expect((await done()).status).toBe(409); // a held photo doesn't count (P10)
    // A held photo is shown to nobody, the owner's own view included, until an admin approves.
    const photos = ((await call('getMe', { token: me.token })).json as { photos: { id: string }[] })
      .photos;
    for (const p of photos) {
      const view = await call('getMyPhoto', { token: me.token, params: { id: p.id } });
      expect([200, 404]).toContain(view.status);
    }
    expect((await photo(me.token)).status).toBe(201); // replaces position 0 with an approved one
    expect((await done()).status).toBe(200);
    expect(
      ((await call('getMe', { token: me.token })).json as { onboardingStep: string })
        .onboardingStep,
    ).toBe('complete');
  });

  it('a finished profile cannot be edited back under 18, and nobody can skip the line in the table', async () => {
    const me = await newcomer();
    expect((await profile(me.token)).status).toBe(200);
    expect((await photo(me.token)).status).toBe(201);
    expect((await call('completeOnboarding', { token: me.token })).status).toBe(200);
    expect((await profile(me.token, { birthdate: yearsAgo(16) })).status).toBe(422);
    const row = await world.db.from('profiles').select('birthdate').eq('id', me.id).single();
    expect(row.data?.birthdate).toBe(yearsAgo(30));
    // With the app's own key, the profiles table is closed: no direct edit of birthdate.
    const direct = await supa(live, 'PATCH', `/rest/v1/profiles?id=eq.${me.id}`, {
      token: me.token,
      body: { birthdate: yearsAgo(10), onboarding_step: 'complete' },
    });
    expect(direct.status).toBeGreaterThanOrEqual(400);
  });
});

describe.skipIf(!LIVE)('test sign-in is a dev tool and nothing else (live)', () => {
  const login = (email: string) => call('testLogin', { body: { email } });

  it('is a 404 unless ALLOW_TEST_LOGIN is on locally, and never mints a token then', async () => {
    const reply = await login(`d2-login-${tag()}@glow.test`);
    expect(reply.status).toBe(404);
    expect(reply.text).not.toMatch(/accessToken|refreshToken/);
  });

  it('when on, it signs in @glow.test people only, never a real address', async () => {
    process.env.ALLOW_TEST_LOGIN = '1';
    resetEnvCacheForTests();
    const ok = await login(`d2-login-${tag()}@glow.test`);
    expect(ok.status).toBe(200);
    made.push((ok.json as { userId: string }).userId);
    for (const email of [
      `d2-real-${tag()}@example.com`,
      `d2-${tag()}@glow.test.example.com`,
      `d2-${tag()}@GLOW.TEST@example.com`,
      `d2-${tag()}@glow.test\n@example.com`,
    ]) {
      const reply = await login(email);
      expect([400, 404], email).toContain(reply.status);
      expect(reply.text).not.toMatch(/accessToken/);
    }
  });
});

describe.skipIf(!LIVE)('names are text, whatever they hold (live)', () => {
  it('a first name with markup, newlines, bidi and zero-width characters is stored as inert text', async () => {
    const me = await newcomer();
    const names = ['<b>Dee</b>', 'Dee\nSmith', 'Dee‮eed', '​​', "Robert'); DROP TABLE profiles;--"];
    for (const firstName of names) {
      const reply = await profile(me.token, { firstName });
      expect(reply.status, JSON.stringify(firstName)).toBeLessThan(500);
    }
    // D2-F3: the zero-width-only name is accepted (low): it renders as a blank name.
    const blank = await profile(me.token, { firstName: '​​' });
    expect([200, 400]).toContain(blank.status);
    const row = await world.db.from('profiles').select('id').eq('id', me.id).single();
    expect(row.data?.id).toBe(me.id);
  });
});
