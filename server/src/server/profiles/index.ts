/**
 * B1's profiles module: the signed-in person's own profile, photos and onboarding step.
 *
 * For other agents' routes:
 *
 *   import { assertOnboardingComplete } from '@/server/profiles';
 *   await assertOnboardingComplete(user.id); // 409 onboarding_incomplete until it's finished
 *
 * Rooms can't be opened until onboarding is complete: B2's resolve and join, B3's check-in
 * and B4's deck and taps should call this first. The database's `create_checkin` checks too.
 */
export { assertOnboardingComplete, onboardingIncomplete } from './onboarding';
export { isAdult, latestAdultBirthdate } from './age';
export { getMe, loadMe } from './me';
export { updateProfile } from './profile';
export { addProfilePhoto, deleteProfilePhoto, getMyPhoto } from './photos';
export { finishOnboarding } from './finish';
export { testLogin } from './test-login';
