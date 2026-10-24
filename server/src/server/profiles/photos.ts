/**
 * My own profile photos: add (moderated), view and remove.
 *
 * Photos live in the private `profile-photos` bucket as `{userId}/{photoId}.jpg`, with no
 * storage policies, so only these routes and B3's match photo route ever read them (P4).
 * Profile photos are only ever shown to people with an active match (P1), and only approved
 * ones. A photo held by moderation (possibly under 18) is stored but shown to nobody and
 * doesn't count toward finishing onboarding (P10).
 */
import { PHOTO_MAX_BYTES, PHOTO_MAX_DIMENSION_PX, PROFILE_PHOTOS_MIN } from '@/contracts';
import {
  HttpError,
  badRequest,
  conflict,
  notFound,
  unavailable,
  type RouteHandler,
} from '@/server/http';
import { logger } from '@/server/log';
import { moderateImage, photoRejected } from '@/server/moderation';
import { rateLimit } from '@/server/ratelimit';
import { PROFILE_PHOTOS_BUCKET, serviceDb, type Db } from './db';
import { InvalidJpegError, stripJpegMetadata } from './jpeg';
import { readPhotos, readProfile, toMyPhoto, type PhotoRow } from './me';
import { approvedCount, deriveStep, profileComplete, storeStep } from './onboarding';

/** The app crops to 4:5. Allow a pixel or two of rounding either way. */
const ASPECT = 4 / 5;
const ASPECT_TOLERANCE = 0.02;

const BASE64 = /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/;

const photoPath = (userId: string, photoId: string) => `${userId}/${photoId}.jpg`;

const tooLarge = () => new HttpError(413, 'payload_too_large', 'That photo is too large.');

const invalidPhoto = (message: string) =>
  badRequest('The body is not valid.', [{ path: 'body.photo', code: 'invalid_value', message }]);

/** Decodes and checks the upload. Never logs or echoes the bytes. */
export function decodeUpload(base64: string): Uint8Array {
  if (!BASE64.test(base64)) throw invalidPhoto('Send the photo as base64.');
  const bytes = new Uint8Array(Buffer.from(base64, 'base64'));
  if (bytes.byteLength > PHOTO_MAX_BYTES) throw tooLarge();
  return bytes;
}

/** Strips metadata and checks the size and shape. Throws 400 or 422 `photo_rejected`. */
export function cleanUpload(bytes: Uint8Array): Uint8Array {
  let cleaned: ReturnType<typeof stripJpegMetadata>;
  try {
    cleaned = stripJpegMetadata(bytes);
  } catch (error) {
    if (error instanceof InvalidJpegError) throw photoRejected('unreadable');
    throw error;
  }
  const { width, height } = cleaned.info;
  if (Math.max(width, height) > PHOTO_MAX_DIMENSION_PX) {
    throw invalidPhoto(`The longest side can be at most ${PHOTO_MAX_DIMENSION_PX} pixels.`);
  }
  if (Math.abs(width / height - ASPECT) > ASPECT_TOLERANCE) {
    throw invalidPhoto('Crop the photo to 4:5.');
  }
  return cleaned.bytes;
}

/** Moves the onboarding step after the photos changed. */
async function syncStep(db: Db, userId: string): Promise<void> {
  const [profile, photos] = await Promise.all([readProfile(db, userId), readPhotos(db, userId)]);
  const next = deriveStep(profile.onboarding_step, {
    profileComplete: profileComplete(profile),
    approvedPhotos: approvedCount(photos),
  });
  await storeStep(db, userId, profile.onboarding_step, next);
}

async function removeObject(db: Db, path: string, why: string): Promise<void> {
  const { error } = await db.storage.from(PROFILE_PHOTOS_BUCKET).remove([path]);
  // A leftover object is unreachable (no row points at it, and no route serves it without
  // one), but count it so it can be cleaned up.
  if (error) logger.warn('profiles.photo_object_left', { why });
}

export const addProfilePhoto: RouteHandler<'addProfilePhoto'> = async ({ user, body }) => {
  await rateLimit(user.id, 'photos');
  const uploaded = decodeUpload(body.photo);
  const stored = cleanUpload(uploaded);

  // Moderate the photo as it was sent: B8's fake reads its test markers from it, and the real
  // model only ever gets B8's own downscaled, metadata-free copy. A moderation outage throws
  // a 503 here and nothing is stored (profile photos fail closed).
  const verdict = await moderateImage('profile', uploaded);
  if (verdict.decision === 'rejected') {
    logger.info('profiles.photo_rejected', { reason: verdict.reason });
    throw photoRejected(verdict.reason);
  }

  const db = serviceDb();
  const photoId = crypto.randomUUID();
  const path = photoPath(user.id, photoId);
  const upload = await db.storage
    .from(PROFILE_PHOTOS_BUCKET)
    .upload(path, stored, { contentType: 'image/jpeg', upsert: false });
  if (upload.error) {
    logger.error('profiles.photo_upload_failed', { status: 'storage' });
    throw unavailable();
  }

  const existing = await db
    .from('profile_photos')
    .select('id, path')
    .eq('user_id', user.id)
    .eq('position', body.position)
    .maybeSingle();
  if (existing.error) {
    await removeObject(db, path, 'read_failed');
    throw unavailable();
  }

  const row = {
    id: photoId,
    user_id: user.id,
    path,
    position: body.position,
    moderation_status: verdict.decision,
  };
  // Replacing swaps the row in one statement (id and path change together, as the path
  // check needs), so the position is never empty and never has two photos.
  const write = existing.data
    ? await db
        .from('profile_photos')
        .update(row)
        .eq('id', existing.data.id)
        .eq('user_id', user.id)
        .select('id')
    : await db.from('profile_photos').insert(row).select('id');
  if (write.error || write.data.length !== 1) {
    await removeObject(db, path, 'write_failed');
    // Two uploads to the same position at once: the other one won.
    if (write.error?.code === '23505' || (!write.error && write.data.length === 0)) {
      throw conflict('conflict', 'Another photo was just saved there. Try again.');
    }
    logger.error('profiles.photo_write_failed', { code: write.error?.code ?? 'none' });
    throw unavailable();
  }
  if (existing.data) await removeObject(db, existing.data.path, 'replaced');

  await syncStep(db, user.id);
  logger.info('profiles.photo_added', {
    position: body.position,
    status: verdict.decision,
    replaced: existing.data !== null,
  });
  return {
    status: 201,
    body: toMyPhoto({ id: photoId, position: body.position, moderation_status: verdict.decision, path }),
  };
};

async function findMine(db: Db, userId: string, photoId: string): Promise<PhotoRow> {
  const { data, error } = await db
    .from('profile_photos')
    .select('id, position, moderation_status, path')
    .eq('id', photoId)
    .eq('user_id', userId)
    .maybeSingle();
  if (error) throw unavailable();
  // Someone else's photo is exactly as missing as one that doesn't exist (P11).
  if (!data) throw notFound();
  return data as PhotoRow;
}

export const getMyPhoto: RouteHandler<'getMyPhoto'> = async ({ user, params }) => {
  const db = serviceDb();
  const photo = await findMine(db, user.id, params.id);
  const { data, error } = await db.storage.from(PROFILE_PHOTOS_BUCKET).download(photo.path);
  if (error || !data) {
    logger.error('profiles.photo_download_failed', { status: 'storage' });
    throw unavailable();
  }
  return new Response(await data.arrayBuffer(), {
    status: 200,
    headers: {
      'content-type': 'image/jpeg',
      'cache-control': 'no-store, max-age=0',
      'x-content-type-options': 'nosniff',
    },
  });
};

export const lastPhoto = () =>
  conflict('last_photo', 'Add another photo before removing this one.');

export const deleteProfilePhoto: RouteHandler<'deleteProfilePhoto'> = async ({
  user,
  params,
}) => {
  await rateLimit(user.id, 'photos');
  const db = serviceDb();
  const [photo, profile, photos] = await Promise.all([
    findMine(db, user.id, params.id),
    readProfile(db, user.id),
    readPhotos(db, user.id),
  ]);

  // A finished profile always keeps PROFILE_PHOTOS_MIN approved photos, so a match never
  // sees an empty profile. Replace a photo instead (upload to its position).
  if (profile.onboarding_step === 'complete') {
    const approvedAfter = approvedCount(photos.filter((p) => p.id !== photo.id));
    if (approvedAfter < PROFILE_PHOTOS_MIN) throw lastPhoto();
  }

  const { error } = await db
    .from('profile_photos')
    .delete()
    .eq('id', photo.id)
    .eq('user_id', user.id);
  if (error) throw unavailable();
  await removeObject(db, photo.path, 'deleted');
  await syncStep(db, user.id);
  logger.info('profiles.photo_removed', { position: photo.position });
  return { status: 204 };
};
