import { describe, expect, it } from 'vitest';
import type { OnboardingStep } from '@/contracts';
import {
  approvedCount,
  canFinish,
  deriveStep,
  profileComplete,
} from '@/server/profiles/onboarding';

const done = { profileComplete: true, approvedPhotos: 1 };

describe('onboarding state machine', () => {
  it.each<[OnboardingStep, boolean, number, OnboardingStep]>([
    ['profile', false, 0, 'profile'],
    ['profile', true, 0, 'photos'],
    ['profile', true, 1, 'notifications'],
    ['photos', true, 0, 'photos'],
    ['photos', true, 1, 'notifications'],
    ['notifications', true, 1, 'notifications'],
    // Going back before the end: removing the only approved photo returns to photos.
    ['notifications', true, 0, 'photos'],
    ['photos', false, 1, 'profile'],
    // Finished stays finished.
    ['complete', true, 0, 'complete'],
    ['complete', false, 0, 'complete'],
  ])(
    'from %s with profile=%s and %i approved photos goes to %s',
    (stored, profile, photos, next) => {
      expect(deriveStep(stored, { profileComplete: profile, approvedPhotos: photos })).toBe(next);
    },
  );

  it('never reaches complete on its own: the notifications step has to finish it', () => {
    expect(deriveStep('notifications', done)).toBe('notifications');
    expect(canFinish(done)).toBe(true);
  });

  it('cannot finish without a full profile and an approved photo', () => {
    expect(canFinish({ profileComplete: false, approvedPhotos: 3 })).toBe(false);
    expect(canFinish({ profileComplete: true, approvedPhotos: 0 })).toBe(false);
  });

  it('counts only approved photos: held (possibly under 18) and pending never count (P10)', () => {
    expect(
      approvedCount([
        { moderation_status: 'held' },
        { moderation_status: 'pending' },
        { moderation_status: 'rejected' },
      ]),
    ).toBe(0);
    expect(approvedCount([{ moderation_status: 'approved' }, { moderation_status: 'held' }])).toBe(
      1,
    );
  });

  it('needs every profile field', () => {
    const full = {
      first_name: 'Robin',
      birthdate: '1999-04-12',
      gender: 'woman',
      show_me: ['man'],
    };
    expect(profileComplete(full)).toBe(true);
    expect(profileComplete({ ...full, first_name: null })).toBe(false);
    expect(profileComplete({ ...full, birthdate: null })).toBe(false);
    expect(profileComplete({ ...full, gender: null })).toBe(false);
    expect(profileComplete({ ...full, show_me: [] })).toBe(false);
  });
});
