/**
 * `POST /api/me/onboarding/complete`: finishing onboarding. The notifications step is the last
 * one, and it ends the same way whether the person allowed notifications or not, so declining
 * push never blocks anyone.
 *
 * The database's `complete_onboarding` (A2, migration 0002) makes the decision under a row
 * lock: a full 18+ profile and PROFILE_PHOTOS_MIN approved photos, or `onboarding_incomplete`.
 * Held photos (possibly under 18) don't count (P10).
 */
import type { Me } from '@/contracts';
import { notFound, unavailable, type RouteHandler } from '@/server/http';
import { logger } from '@/server/log';
import { rateLimit } from '@/server/ratelimit';
import { serviceDb, type Db } from './db';
import { loadMe } from './me';
import { onboardingIncomplete } from './onboarding';

/** Marks onboarding complete, or throws 409 `onboarding_incomplete`. Calling it again is harmless. */
export async function finishOnboarding(db: Db, userId: string): Promise<Me> {
  // Bring the stored step up to date first (a held photo may have been approved since).
  await loadMe(db, userId);
  const { error } = await db.rpc('complete_onboarding', { p_user_id: userId });
  if (error) {
    if (error.message === 'onboarding_incomplete') throw onboardingIncomplete();
    // No profile, or banned: nothing the caller can see (P11).
    if (error.message === 'not_found') throw notFound();
    logger.error('profiles.finish_failed', { code: error.code });
    throw unavailable();
  }
  logger.info('profiles.onboarding_finished');
  return loadMe(db, userId);
}

export const completeOnboarding: RouteHandler<'completeOnboarding'> = async ({ user }) => {
  await rateLimit(user.id, 'account');
  return { status: 200, body: await finishOnboarding(serviceDb(), user.id) };
};
