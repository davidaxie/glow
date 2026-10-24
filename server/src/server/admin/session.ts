/**
 * Admin web sign-in. The admin signs in with a 6-digit email code (Supabase Auth), and the
 * Supabase session lives in httpOnly cookies, so page JavaScript never sees a token. Every
 * page and server action checks the access token with Supabase Auth (D3) and the `admins`
 * table, and anyone who isn't an admin gets the same 404 as a page that doesn't exist.
 *
 * Only server components, server actions and route handlers import this file.
 */
import { cookies } from 'next/headers';
import { cache } from 'react';
import type { Session } from '@supabase/supabase-js';
import { getEnv } from '@/env';
import { requireUser, unverifiedClaims } from '@/server/auth';
import { HttpError } from '@/server/http';
import { logger } from '@/server/log';
import { isAdmin } from './access';
import { anonAuth, serviceDb } from './db';

const ACCESS = 'glow_admin_at';
const REFRESH = 'glow_admin_rt';
const SINCE = 'glow_admin_since';
/**
 * Set only after an admin signs in, and kept after the session ends, so this browser's 404
 * page can offer the sign-in link. Holds no token and nothing about the person.
 */
const HINT = 'glow_admin_hint';
const HINT_DAYS = 30;

/** A sign-in lasts this long, however often the access token is refreshed. */
export const SESSION_HOURS = 24;
const SESSION_MS = SESSION_HOURS * 3600 * 1000;

export type AdminSession = { readonly userId: string };

const TEST_EMAIL = /^[a-z0-9._+-]+@glow\.test$/;

function cookieOptions(expires: Date) {
  return {
    httpOnly: true,
    // Lax keeps the cookie off cross-site POSTs; Next.js also checks Origin on every action.
    sameSite: 'lax' as const,
    secure: getEnv().profile !== 'local',
    path: '/',
    expires,
  };
}

/** The signed-in admin for this request, or null. Checked once per request. */
export const currentAdmin = cache(async (): Promise<AdminSession | null> => {
  const jar = await cookies();
  const token = jar.get(ACCESS)?.value;
  if (!token) return null;
  let userId: string;
  try {
    const user = await requireUser(
      new Request('http://admin.invalid/', { headers: { authorization: `Bearer ${token}` } }),
    );
    userId = user.id;
  } catch (error) {
    // 401: expired or revoked. A 503 (Auth unreachable) is a real error, not "not an admin".
    if (error instanceof HttpError && error.status === 401) return null;
    throw error;
  }
  return (await isAdmin(userId)) ? { userId } : null;
});

async function store(session: Session, since: number): Promise<void> {
  const jar = await cookies();
  const options = cookieOptions(new Date(since + SESSION_MS));
  jar.set(ACCESS, session.access_token, options);
  jar.set(REFRESH, session.refresh_token, options);
  jar.set(SINCE, String(since), options);
  jar.set(HINT, '1', cookieOptions(new Date(Date.now() + HINT_DAYS * 86400 * 1000)));
}

/** Whether this browser has signed in as an admin before (for the 404 page). */
export async function hasAdminHint(): Promise<boolean> {
  return (await cookies()).get(HINT)?.value === '1';
}

async function forget(): Promise<void> {
  const jar = await cookies();
  for (const name of [ACCESS, REFRESH, SINCE]) jar.delete(name);
}

/** Ends a Supabase session on the server, so its refresh token can't be used again. */
async function revoke(accessToken: string): Promise<void> {
  const { error } = await serviceDb().auth.admin.signOut(accessToken, 'local');
  if (error) logger.warn('admin.sign_out_failed', { status: error.status ?? 0 });
}

/**
 * Keeps the session only if it belongs to an admin. Anyone else's session is revoked at
 * once and nothing is stored, so a non-admin never holds an admin cookie.
 */
async function establish(session: Session, since: number): Promise<boolean> {
  if (!(await isAdmin(session.user.id))) {
    await revoke(session.access_token);
    logger.info('admin.sign_in', { outcome: 'not_admin' });
    return false;
  }
  await store(session, since);
  logger.info('admin.sign_in', { outcome: 'ok', adminId: session.user.id });
  return true;
}

export type SendCodeResult = 'sent' | 'rate_limited';

/**
 * Sends a sign-in code. Never creates an account, and answers the same whether or not the
 * address has one, so the form can't be used to find out who uses Glow.
 */
export async function sendCode(email: string): Promise<SendCodeResult> {
  const { error } = await anonAuth().signInWithOtp({
    email,
    options: { shouldCreateUser: false },
  });
  if (error?.status === 429) return 'rate_limited';
  if (error && error.status !== undefined && error.status >= 500) {
    throw new HttpError(503, 'unavailable', 'Sign-in is briefly unavailable.');
  }
  return 'sent';
}

export type VerifyResult = 'ok' | 'invalid';

/** Checks a code. A right code for someone who isn't an admin reads as a wrong one. */
export async function verifyCode(email: string, code: string): Promise<VerifyResult> {
  const { data, error } = await anonAuth().verifyOtp({ email, token: code, type: 'email' });
  if (error || !data.session) return 'invalid';
  return (await establish(data.session, Date.now())) ? 'ok' : 'invalid';
}

/** Local test sign-in: only with ALLOW_TEST_LOGIN, a local Supabase and a @glow.test address. */
export function testSignInAllowed(): boolean {
  const env = getEnv();
  return env.profile === 'local' && env.ALLOW_TEST_LOGIN;
}

export async function testSignIn(email: string): Promise<VerifyResult> {
  if (!testSignInAllowed() || !TEST_EMAIL.test(email)) return 'invalid';
  // A one-time link made on the server and used at once: no email is sent.
  const { data, error } = await serviceDb().auth.admin.generateLink({ type: 'magiclink', email });
  const tokenHash = data?.properties?.hashed_token;
  if (error || !tokenHash) return 'invalid';
  const verified = await anonAuth().verifyOtp({ token_hash: tokenHash, type: 'magiclink' });
  if (verified.error || !verified.data.session) return 'invalid';
  return (await establish(verified.data.session, Date.now())) ? 'ok' : 'invalid';
}

/**
 * Swaps the refresh token for a fresh session when the access token is missing or close to
 * expiring. True when there is now a valid admin session.
 */
export async function refreshSession(): Promise<boolean> {
  const jar = await cookies();
  const refreshToken = jar.get(REFRESH)?.value;
  const since = Number(jar.get(SINCE)?.value ?? NaN);
  if (!refreshToken || !Number.isFinite(since)) return false;
  if (Date.now() - since > SESSION_MS) {
    await forget();
    return false;
  }
  const access = jar.get(ACCESS)?.value;
  const exp = access ? unverifiedClaims(access)?.exp : undefined;
  // Still good for 15 minutes or more: nothing to do.
  if (typeof exp === 'number' && exp * 1000 - Date.now() > 15 * 60 * 1000) {
    return (await currentAdmin()) !== null;
  }
  const { data, error } = await anonAuth().refreshSession({ refresh_token: refreshToken });
  if (error || !data.session) {
    if (error?.status !== undefined && error.status >= 500) return false;
    await forget();
    return false;
  }
  if (!(await establish(data.session, since))) {
    await forget();
    return false;
  }
  return true;
}

export async function signOut(): Promise<void> {
  const jar = await cookies();
  const access = jar.get(ACCESS)?.value;
  if (access) await revoke(access);
  await forget();
  jar.delete(HINT);
}
