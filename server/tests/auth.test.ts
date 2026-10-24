import { describe, expect, it, vi } from 'vitest';
import type { User } from '@supabase/supabase-js';
import { bearerToken, requireCron, requireUser } from '@/server/auth';
import { accept } from '@/server/auth/verify';
import { HttpError } from '@/server/http/errors';
import { LOCAL_ENV } from './helpers/env';
import { USER_ID, fakeAccessToken, mockVerify, valid } from './helpers/auth';

vi.mock('@/server/auth/verify', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@/server/auth/verify')>();
  return { ...actual, verifyAccessToken: vi.fn() };
});

const withAuth = (value?: string) =>
  new Request('http://localhost/api/me', value ? { headers: { authorization: value } } : {});

async function statusOf(promise: Promise<unknown>): Promise<number> {
  try {
    await promise;
    return 200;
  } catch (error) {
    if (error instanceof HttpError) return error.status;
    throw error;
  }
}

describe('bearerToken', () => {
  it('reads a Bearer token and nothing else', () => {
    expect(bearerToken(withAuth('Bearer abc.def.ghi'))).toBe('abc.def.ghi');
    expect(bearerToken(withAuth('bearer abc.def.ghi'))).toBe('abc.def.ghi');
    expect(bearerToken(withAuth('Basic dXNlcjpwYXNz'))).toBeNull();
    expect(bearerToken(withAuth('Bearer a b'))).toBeNull();
    expect(bearerToken(withAuth())).toBeNull();
  });
});

describe('requireUser', () => {
  it('returns the person when Supabase Auth confirms the token', async () => {
    await mockVerify(valid);
    await expect(requireUser(withAuth(`Bearer ${fakeAccessToken()}`))).resolves.toEqual(valid.user);
  });

  it('answers 401 with no token, without calling Supabase', async () => {
    const verify = await mockVerify();
    expect(await statusOf(requireUser(withAuth()))).toBe(401);
    expect(verify).not.toHaveBeenCalled();
  });

  it.each([
    ['not a JWT', 'nonsense'],
    ['expired', fakeAccessToken({}, { expiresInSeconds: -10 })],
    ['the anon key', fakeAccessToken({ role: 'anon', sub: undefined })],
    ['a service role key', fakeAccessToken({ role: 'service_role' })],
    ['the wrong audience', fakeAccessToken({ aud: 'something-else' })],
    ['oversized', `${fakeAccessToken()}${'a'.repeat(9000)}`],
  ])('answers 401 for %s, without calling Supabase', async (_label, token) => {
    const verify = await mockVerify();
    expect(await statusOf(requireUser(withAuth(`Bearer ${token}`)))).toBe(401);
    expect(verify).not.toHaveBeenCalled();
  });

  it('answers 401 when Supabase Auth rejects the token', async () => {
    await mockVerify({ kind: 'invalid' });
    expect(await statusOf(requireUser(withAuth(`Bearer ${fakeAccessToken()}`)))).toBe(401);
  });

  it('answers 401 when the token belongs to someone other than its subject', async () => {
    await mockVerify({
      kind: 'valid',
      user: { id: '00000000-0000-4000-8000-000000000000', email: null },
    });
    expect(await statusOf(requireUser(withAuth(`Bearer ${fakeAccessToken()}`)))).toBe(401);
  });

  it('answers 503, not 401, when Supabase Auth is unreachable, so the app keeps its session', async () => {
    await mockVerify({ kind: 'unavailable' });
    expect(await statusOf(requireUser(withAuth(`Bearer ${fakeAccessToken()}`)))).toBe(503);
  });
});

describe('accept', () => {
  const base = {
    id: USER_ID,
    aud: 'authenticated',
    role: 'authenticated',
    email: 'person@glow.test',
    app_metadata: {},
    user_metadata: {},
    created_at: new Date().toISOString(),
  } as User;

  it('accepts a normal signed-in person', () => {
    expect(accept(base)).toEqual(valid);
  });

  it('refuses anonymous Supabase users', () => {
    expect(accept({ ...base, is_anonymous: true }).kind).toBe('invalid');
  });

  it('refuses banned people until the ban ends', () => {
    const now = Date.now();
    const banned = { ...base, banned_until: new Date(now + 60_000).toISOString() } as User;
    expect(accept(banned, now).kind).toBe('invalid');
    expect(accept(banned, now + 120_000).kind).toBe('valid');
  });

  it('refuses a missing user or a non-UUID ID', () => {
    expect(accept(null).kind).toBe('invalid');
    expect(accept({ ...base, id: 'admin' }).kind).toBe('invalid');
  });
});

describe('requireCron', () => {
  it('accepts only the cron secret', async () => {
    expect(() => requireCron(withAuth(`Bearer ${LOCAL_ENV.CRON_SECRET}`))).not.toThrow();
    expect(
      await statusOf(Promise.resolve().then(() => requireCron(withAuth('Bearer wrong')))),
    ).toBe(401);
    expect(await statusOf(Promise.resolve().then(() => requireCron(withAuth())))).toBe(401);
  });
});
