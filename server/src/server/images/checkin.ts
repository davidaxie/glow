/**
 * POST /api/rooms/{id}/checkin (createCheckin): join ticket plus blurred photo plus tags
 * creates my card.
 *
 * 1. Rate limit (B8's `checkin` policy).
 * 2. The join ticket must be for this person and this room, and still fresh (B2). Otherwise
 *    422 `join_ticket_invalid`: the app sends them back through the location check.
 * 3. Moderation (B8) checks the photo as uploaded. Card photos fail closed: a rejection is
 *    422 `photo_rejected` with a `reason` the app turns into a retake message, and a timeout
 *    or outage is 503 `unavailable` (reason `moderation`). Nothing is stored before this.
 * 4. The server re-encodes the photo with no metadata at all (upload.ts), stores it privately
 *    as `room-cards/{roomId}/{cardId}.jpg` with a fresh random card ID, and calls
 *    `create_checkin`, which ends any older check-in of mine in this room.
 * 5. Photos of replaced check-ins are deleted at once; a photo whose check-in failed is too.
 */
import { randomUUID } from 'node:crypto';
import type { CardTags, MyCheckin } from '@/contracts';
import { unprocessable, type RouteHandler } from '@/server/http';
import { logger } from '@/server/log';
import { httpErrorFor } from './db-errors';
import { moderateImage, photoRejected, rateLimit, verifyJoinTicket } from './deps';
import { cardImageLink } from './signed-link';
import { CARD_BUCKET, serviceClient } from './supabase';
import { decodePhoto, normalizeCardPhoto } from './upload';

/** What `create_checkin` returns (docs/CONTRACTS.md). */
type CheckinRow = {
  readonly id: string;
  readonly roomId: string;
  readonly cardPath: string;
  readonly tags: CardTags;
  readonly visible: boolean;
  readonly joinedAt: string;
  readonly expiresAt: string;
};
type CreateCheckinResult = {
  readonly checkin: CheckinRow;
  readonly replacedCardPaths: readonly string[];
};

/** Tags in a stable order with duplicate extras dropped. */
export function normalizeTags(tags: CardTags): CardTags {
  return {
    topColor: tags.topColor,
    ...(tags.hairLength ? { hairLength: tags.hairLength } : {}),
    ...(tags.hairColor ? { hairColor: tags.hairColor } : {}),
    extras: [...new Set(tags.extras)],
  };
}

async function removeCardPhotos(paths: readonly string[]): Promise<void> {
  if (paths.length === 0) return;
  const { error } = await serviceClient()
    .storage.from(CARD_BUCKET)
    .remove([...paths]);
  // B8's purge deletes anything left behind within PURGE_INTERVAL.
  if (error) logger.warn('checkin.photo_remove_failed', { count: paths.length });
}

export const createCheckin: RouteHandler<'createCheckin'> = async ({ user, params, body }) => {
  const roomId = params.id;
  const userId = user.id;

  await rateLimit(userId, 'checkin');

  const ticket = await verifyJoinTicket(body.ticket, { userId, roomId });
  if (!ticket) {
    logger.info('checkin.refused', { roomId, outcome: 'join_ticket_invalid' });
    throw unprocessable('join_ticket_invalid', 'The room check has expired. Join again.');
  }

  // Moderate the bytes exactly as uploaded, before anything is stored. B8 throws its own 503.
  const uploaded = decodePhoto(body.photo);
  const verdict = await moderateImage('card', uploaded);
  if (verdict.decision !== 'approved') {
    const reason = verdict.reason;
    logger.info('checkin.refused', { roomId, outcome: 'photo_rejected', reason });
    throw photoRejected(reason);
  }

  const jpeg = await normalizeCardPhoto(uploaded);
  const db = serviceClient();
  const cardId = randomUUID();
  const cardPath = `${roomId}/${cardId}.jpg`;
  const stored = await db.storage.from(CARD_BUCKET).upload(cardPath, jpeg, {
    contentType: 'image/jpeg',
    cacheControl: 'no-store',
    upsert: false,
  });
  if (stored.error) {
    logger.error('checkin.store_failed', { roomId });
    throw httpErrorFor(null);
  }

  const { data, error } = await db.rpc('create_checkin', {
    p_user_id: userId,
    p_room_id: roomId,
    p_checkin_id: cardId,
    p_card_path: cardPath,
    p_tags: normalizeTags(body.tags),
  });
  if (error || !data) {
    await removeCardPhotos([cardPath]);
    logger.info('checkin.refused', { roomId, outcome: 'database' });
    throw httpErrorFor(error);
  }

  const { checkin, replacedCardPaths } = data as unknown as CreateCheckinResult;
  await removeCardPhotos(replacedCardPaths.filter((path) => path !== cardPath));
  logger.info('checkin.created', { roomId, cardId, replaced: replacedCardPaths.length });

  const reply: MyCheckin = {
    cardId: checkin.id,
    roomId: checkin.roomId,
    tags: checkin.tags,
    visible: checkin.visible,
    joinedAt: checkin.joinedAt,
    expiresAt: checkin.expiresAt,
    image: cardImageLink(checkin.id, userId),
  };
  return { status: 201, body: reply };
};
