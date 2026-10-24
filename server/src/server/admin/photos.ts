/**
 * Profile photos B8's moderation held for a person to look at (for example, possibly under
 * 18). Held photos never count toward onboarding and are never shown to matches (D50, P10),
 * so a person stays in onboarding until an admin decides.
 *
 * Admins see only what needs a decision: held photos, and pending ones stuck in moderation.
 * Approved and rejected photos can't be listed or opened here (B7-D11).
 */
import type { AdminPhoto, ModerationStatus } from '@/contracts';
import { badRequest, notFound } from '@/server/http';
import { logger } from '@/server/log';
import { deps } from './context';
import { banPerson } from './reports';
import type { PhotoRecord } from './repo';
import { watermarkJpeg } from './watermark';

export type PhotoStatus = ModerationStatus;
export type PhotoDecision = 'approve' | 'reject' | 'ban';
export type AdminPhotoView = AdminPhoto;

const REVIEWABLE: readonly PhotoStatus[] = ['held', 'pending'];

function toView(photo: PhotoRecord, status: PhotoStatus = photo.moderationStatus): AdminPhotoView {
  return {
    id: photo.id,
    position: photo.position,
    moderationStatus: status,
    createdAt: photo.createdAt,
    viewerCode: photo.viewerCode,
    image: `/api/admin/photos/${photo.id}/image`,
  };
}

async function reviewable(id: string): Promise<PhotoRecord> {
  const photo = await deps().repo.findPhoto(id);
  if (!photo || !REVIEWABLE.includes(photo.moderationStatus)) throw notFound();
  return photo;
}

export async function listPhotos(status: PhotoStatus = 'held'): Promise<AdminPhotoView[]> {
  if (!REVIEWABLE.includes(status)) {
    throw badRequest('Only held and pending photos are listed here.');
  }
  return (await deps().repo.listPhotos(status)).map((p) => toView(p));
}

/** The photo, watermarked with the admin's own code. 404 once it's been decided. */
export async function photoImage(id: string, adminId: string): Promise<Buffer> {
  const { repo } = deps();
  const photo = await reviewable(id);
  const [bytes, code] = await Promise.all([
    repo.profilePhoto(photo.path),
    repo.viewerCode(adminId),
  ]);
  if (!bytes || !code) throw notFound();
  logger.info('admin.photo_viewed', { reviewItemId: id, adminId });
  return watermarkJpeg(bytes, code);
}

export async function reviewPhoto(
  id: string,
  decision: PhotoDecision,
  adminId: string,
): Promise<AdminPhotoView> {
  const { repo } = deps();
  const photo = await reviewable(id);
  if (decision === 'ban' && photo.userId === adminId) throw badRequest("You can't ban yourself.");
  if (decision === 'approve') {
    await repo.approvePhoto(id);
  } else {
    // Rejected or banned: the image is deleted, not kept (it may show a minor).
    await repo.deletePhoto(photo);
    if (decision === 'ban') await banPerson(photo.userId, adminId);
  }
  logger.info('admin.photo_reviewed', { reviewItemId: id, adminId, decision });
  return toView(photo, decision === 'approve' ? 'approved' : 'rejected');
}
