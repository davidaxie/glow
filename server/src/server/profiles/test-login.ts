/**
 * `POST /api/dev/test-login`: a Debug-only sign-in for Simulator automation (D6, D22).
 *
 * Four locks, any one of which keeps it shut:
 * 1. env.ts refuses `ALLOW_TEST_LOGIN` on Vercel and with a non-local Supabase.
 * 2. `proxy.ts` answers 404 for `/api/dev/*` unless test sign-in is on in a local profile.
 * 3. This handler checks both again and answers the same 404.
 * 4. Only `@glow.test` addresses are accepted (the contract's pattern), so it can never sign
 *    in a real account. The app's call is compiled out of Release builds.
 *
 * It mints a session without a password and without sending an email: the admin API makes a
 * one-time token for the address (creating the test person if needed), and redeeming it gives
 * a normal Supabase session, exactly like the email code would.
 */
import { createClient } from '@supabase/supabase-js';
import { getEnv } from '@/env';
import { notFound, unavailable, type RouteHandler } from '@/server/http';
import { logger } from '@/server/log';
import { serviceDb } from './db';

export const TEST_EMAIL_DOMAIN = '@glow.test';

export function testLoginAllowed(): boolean {
  const env = getEnv();
  return env.profile === 'local' && env.ALLOW_TEST_LOGIN;
}

export const testLogin: RouteHandler<'testLogin'> = async ({ body }) => {
  if (!testLoginAllowed()) throw notFound();
  const email = body.email.toLowerCase();
  if (!email.endsWith(TEST_EMAIL_DOMAIN)) throw notFound();

  const admin = serviceDb();
  const link = await admin.auth.admin.generateLink({ type: 'magiclink', email });
  const tokenHash = link.data.properties?.hashed_token;
  if (link.error || !tokenHash) {
    logger.error('dev.test_login_failed', { step: 'token', status: link.error?.status ?? 0 });
    throw unavailable();
  }

  const env = getEnv();
  const anon = createClient(env.SUPABASE_URL, env.SUPABASE_ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
  const verified = await anon.auth.verifyOtp({ type: 'email', token_hash: tokenHash });
  const session = verified.data.session;
  if (verified.error || !session || !verified.data.user) {
    logger.error('dev.test_login_failed', { step: 'verify', status: verified.error?.status ?? 0 });
    throw unavailable();
  }

  logger.info('dev.test_login');
  return {
    status: 200,
    body: {
      accessToken: session.access_token,
      refreshToken: session.refresh_token,
      expiresIn: session.expires_in,
      userId: verified.data.user.id,
    },
  };
};
