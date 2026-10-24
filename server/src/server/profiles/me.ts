/**
 * `GET /api/me`: the signed-in person's own profile, photos and onboarding step.
 * The only user ID it ever contains is their own (D20).
 */
import type { Me, ModerationStatus, MyPhoto, OnboardingStep } from '@/contracts';
import { unavailable, type RouteHandler } from '@/server/http';
import { logger } from '@/server/log';
import { serviceDb, type Db } from './db';
import { approvedCount, deriveStep, profileComplete, storeStep } from './onboarding';

export type ProfileRow = {
  readonly id: string;
  readonly first_name: string | null;
  readonly birthdate: string | null;
  readonly gender: 'woman' | 'man' | 'nonbinary' | null;
  readonly show_me: readonly ('woman' | 'man' | 'nonbinary')[];
  readonly paused: boolean;
  readonly onboarding_step: OnboardingStep;
  readonly viewer_code: string;
};

export type PhotoRow = {
  readonly id: string;
  readonly position: number;
  readonly moderation_status: ModerationStatus;
  readonly path: string;
};

const PROFILE_COLUMNS =
  'id, first_name, birthdate, gender, show_me, paused, onboarding_step, viewer_code';

/** The URL the app fetches one of its own photos from, with its bearer token. */
export const myPhotoUrl = (photoId: string) => `/api/me/photos/${photoId}`;

export function toMyPhoto(row: PhotoRow): MyPhoto {
  return {
    id: row.id,
    position: row.position,
    moderationStatus: row.moderation_status,
    url: myPhotoUrl(row.id),
  };
}

/** Builds `Me`, leaving out fields that aren't set (absent, not null). Rejected photos never show. */
export function toMe(
  profile: ProfileRow,
  photos: readonly PhotoRow[],
  isAdmin: boolean,
  step: OnboardingStep,
): Me {
  return {
    id: profile.id,
    profile: {
      ...(profile.first_name !== null ? { firstName: profile.first_name } : {}),
      ...(profile.birthdate !== null ? { birthdate: profile.birthdate } : {}),
      ...(profile.gender !== null ? { gender: profile.gender } : {}),
      showMe: [...profile.show_me],
      paused: profile.paused,
      viewerCode: profile.viewer_code,
    },
    photos: photos
      .filter((p) => p.moderation_status !== 'rejected')
      .toSorted((a, b) => a.position - b.position)
      .map(toMyPhoto),
    onboardingStep: step,
    isAdmin,
  };
}

export async function readProfile(db: Db, userId: string): Promise<ProfileRow> {
  const read = () => db.from('profiles').select(PROFILE_COLUMNS).eq('id', userId).maybeSingle();
  let { data, error } = await read();
  if (!error && !data) {
    // The sign-up trigger makes this row. If it's somehow missing, make it now.
    const insert = await db.from('profiles').upsert({ id: userId }, { ignoreDuplicates: true });
    if (insert.error) {
      logger.error('profiles.create_failed', { code: insert.error.code });
      throw unavailable();
    }
    ({ data, error } = await read());
  }
  if (error || !data) {
    logger.error('profiles.read_failed', { code: error?.code ?? 'missing' });
    throw unavailable();
  }
  return data as ProfileRow;
}

export async function readPhotos(db: Db, userId: string): Promise<PhotoRow[]> {
  const { data, error } = await db
    .from('profile_photos')
    .select('id, position, moderation_status, path')
    .eq('user_id', userId)
    .order('position');
  if (error) {
    logger.error('profiles.photos_read_failed', { code: error.code });
    throw unavailable();
  }
  return data as PhotoRow[];
}

async function readIsAdmin(db: Db, userId: string): Promise<boolean> {
  const { data, error } = await db
    .from('admins')
    .select('user_id')
    .eq('user_id', userId)
    .maybeSingle();
  if (error) throw unavailable();
  return data !== null;
}

/**
 * Reads everything about this person, moves their onboarding step to match what they've done,
 * and returns `Me`. Every B1 route that changes the profile ends with this.
 */
export async function loadMe(db: Db, userId: string): Promise<Me> {
  const [profile, photos, isAdmin] = await Promise.all([
    readProfile(db, userId),
    readPhotos(db, userId),
    readIsAdmin(db, userId),
  ]);
  const next = deriveStep(profile.onboarding_step, {
    profileComplete: profileComplete(profile),
    approvedPhotos: approvedCount(photos),
  });
  const step = await storeStep(db, userId, profile.onboarding_step, next);
  return toMe(profile, photos, isAdmin, step);
}

export const getMe: RouteHandler<'getMe'> = async ({ user }) => ({
  status: 200,
  body: await loadMe(serviceDb(), user.id),
});
