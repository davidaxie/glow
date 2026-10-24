/**
 * Finishing onboarding: the notifications step is the last one, and it ends the same way
 * whether the person allowed notifications or not (declining must never block anyone).
 *
 * The route is `POST /api/me/onboarding/complete`, arriving with A2's contract change
 * (migration 0002). Until its operation is in the registry, this is the handler's logic, and
 * it's tested on its own.
 */
import type { Me } from '@/contracts';
import { unavailable } from '@/server/http';
import { logger } from '@/server/log';
import type { Db } from './db';
import { loadMe, readPhotos, readProfile } from './me';
import { approvedCount, canFinish, onboardingIncomplete, profileComplete } from './onboarding';

/**
 * Marks onboarding complete if everything before it is done: a full 18+ profile and
 * PROFILE_PHOTOS_MIN approved photos. Otherwise 409 `onboarding_incomplete`. Idempotent.
 */
export async function finishOnboarding(db: Db, userId: string): Promise<Me> {
  const [profile, photos] = await Promise.all([readProfile(db, userId), readPhotos(db, userId)]);
  if (profile.onboarding_step !== 'complete') {
    const facts = { profileComplete: profileComplete(profile), approvedPhotos: approvedCount(photos) };
    if (!canFinish(facts)) throw onboardingIncomplete();
    const { error } = await db
      .from('profiles')
      .update({ onboarding_step: 'complete' })
      .eq('id', userId)
      .neq('onboarding_step', 'complete');
    if (error) {
      // The database's own check (profiles_complete_has_fields) is the backstop.
      logger.error('profiles.finish_failed', { code: error.code });
      throw error.code === '23514' ? onboardingIncomplete() : unavailable();
    }
    logger.info('profiles.onboarding_step', { from: profile.onboarding_step, to: 'complete' });
  }
  return loadMe(db, userId);
}
