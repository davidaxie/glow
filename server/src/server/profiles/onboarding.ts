/**
 * The onboarding state machine (`profiles.onboarding_step`), so the app always resumes at the
 * right step:
 *
 *   profile ──(first name, 18+ birthday, gender, show me)──▶ photos
 *   photos ──(PROFILE_PHOTOS_MIN approved photos)──▶ notifications
 *   notifications ──(the app says it asked, whatever the answer)──▶ complete
 *
 * Before `complete`, the step is always worked out again from the facts, so it can go back too
 * (removing your only approved photo returns you to `photos`). Once `complete`, it stays complete:
 * the routes keep a finished profile finished instead (`last_photo`).
 *
 * Only approved photos count. A held photo (B8 holds possibly-under-18 photos for a person to
 * review) never lets anyone finish onboarding (P10, D-B1 in docs/DECISIONS.md).
 */
import { PROFILE_PHOTOS_MIN, type ModerationStatus, type OnboardingStep } from '@/contracts';
import { HttpError, unavailable } from '@/server/http';
import { logger } from '@/server/log';
import { serviceDb, type Db } from './db';

export type ProfileFacts = {
  readonly first_name: string | null;
  readonly birthdate: string | null;
  readonly gender: string | null;
  readonly show_me: readonly string[];
};

export type OnboardingFacts = {
  readonly profileComplete: boolean;
  readonly approvedPhotos: number;
};

export function profileComplete(profile: ProfileFacts): boolean {
  return (
    profile.first_name !== null &&
    profile.birthdate !== null &&
    profile.gender !== null &&
    profile.show_me.length > 0
  );
}

export function approvedCount(photos: readonly { moderation_status: ModerationStatus }[]): number {
  return photos.filter((p) => p.moderation_status === 'approved').length;
}

/** The furthest step this person can be on without finishing. */
function earliestUnmet(facts: OnboardingFacts): Exclude<OnboardingStep, 'complete'> {
  if (!facts.profileComplete) return 'profile';
  if (facts.approvedPhotos < PROFILE_PHOTOS_MIN) return 'photos';
  return 'notifications';
}

/** The step a person is on, given what they've done. `complete` never goes back. */
export function deriveStep(stored: OnboardingStep, facts: OnboardingFacts): OnboardingStep {
  if (stored === 'complete') return 'complete';
  return earliestUnmet(facts);
}

/** Whether this person may finish onboarding now (the notifications step is the last one). */
export function canFinish(facts: OnboardingFacts): boolean {
  return earliestUnmet(facts) === 'notifications';
}

export const onboardingIncomplete = () =>
  new HttpError(409, 'onboarding_incomplete', 'Finish your profile first.');

/** Writes the step if it changed. Returns the step that is now stored. */
export async function storeStep(
  db: Db,
  userId: string,
  stored: OnboardingStep,
  next: OnboardingStep,
): Promise<OnboardingStep> {
  if (next === stored) return stored;
  // Only move from the step we read, so two requests at once can't undo each other, and
  // never move a finished profile backwards.
  const { error } = await db
    .from('profiles')
    .update({ onboarding_step: next })
    .eq('id', userId)
    .eq('onboarding_step', stored)
    .neq('onboarding_step', 'complete');
  if (error) {
    logger.error('profiles.step_write_failed', { code: error.code });
    throw unavailable();
  }
  logger.info('profiles.onboarding_step', { from: stored, to: next });
  return next;
}

/**
 * For other agents' routes (B2 join and resolve, B3 check-in, B4 deck and taps): throws 409
 * `onboarding_incomplete` unless this person has finished onboarding. The database's
 * `create_checkin` checks again.
 *
 *   import { assertOnboardingComplete } from '@/server/profiles';
 *   await assertOnboardingComplete(user.id);
 */
export async function assertOnboardingComplete(userId: string, db: Db = serviceDb()): Promise<void> {
  const { data, error } = await db
    .from('profiles')
    .select('onboarding_step')
    .eq('id', userId)
    .maybeSingle();
  if (error) throw unavailable();
  if (!data || data.onboarding_step !== 'complete') throw onboardingIncomplete();
}
