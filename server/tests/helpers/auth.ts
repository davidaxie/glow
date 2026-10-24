import { vi } from 'vitest';
import type { VerifyOutcome } from '@/server/auth/verify';

export const USER_ID = '6a1e5c1e-7f0b-4c55-9a38-2d1f7c3b9e01';

/** An unsigned token with the claims a Supabase access token carries. Test value only. */
export function fakeAccessToken(
  claims: Record<string, unknown> = {},
  { expiresInSeconds = 3600 }: { expiresInSeconds?: number } = {},
): string {
  const header = Buffer.from(JSON.stringify({ alg: 'ES256', typ: 'JWT' })).toString('base64url');
  const payload = Buffer.from(
    JSON.stringify({
      sub: USER_ID,
      aud: 'authenticated',
      role: 'authenticated',
      exp: Math.floor(Date.now() / 1000) + expiresInSeconds,
      ...claims,
    }),
  ).toString('base64url');
  return `${header}.${payload}.c2lnbmF0dXJl`;
}

export const valid = {
  kind: 'valid',
  user: { id: USER_ID, email: 'person@glow.test' },
} as const satisfies VerifyOutcome;

/** Mocks Supabase Auth's answer. Call inside a test after `vi.mock('@/server/auth/verify')`. */
export async function mockVerify(outcome: VerifyOutcome = valid) {
  const verify = await import('@/server/auth/verify');
  return vi.mocked(verify.verifyAccessToken).mockResolvedValue(outcome);
}
