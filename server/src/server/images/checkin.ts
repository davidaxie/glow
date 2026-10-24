/**
 * POST /api/rooms/{id}/checkin (createCheckin): join ticket plus blurred photo plus tags
 * creates my card.
 *
 * 1. The join ticket must be for this person and this room (B2), still fresh.
 * 2. The photo is decoded and re-encoded with no metadata (upload.ts).
 * 3. Moderation (B8) must approve it, within MODERATION_TIMEOUT. Card photos fail closed: a
 *    rejection is 422 `photo_rejected` with a `reason` the app turns into a retake message,
 *    and an outage is 503 `unavailable` with reason `moderation`.
 * 4. The photo goes to the private `room-cards` bucket as `{roomId}/{cardId}.jpg`, with a
 *    fresh random card ID, and `create_checkin` starts the check-in (ending any older one).
 * 5. Photos of replaced check-ins are deleted at once.
 */
import { randomUUID } from 'node:crypto';
import { MODERATION_TIMEOUT_MS, type CardTags, type MyCheckin } from '@/contracts';
import { unavailable, unprocessable, type RouteHandler } from '@/server/http';
import { logger } from '@/server/log';
import { httpErrorFor } from './db-errors';
import {
  ModerationUnavailableError,
  moderateImage,
  verifyJoinTicket,
  type ModerationVerdict,
  type PhotoRejectReason,
} from './deps';
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
type CreateCheckinResult = { readonly checkin: CheckinRow; readonly replacedCardPaths: string[] };

/** Plain words for logs. The app shows its own copy per `reason`. */
const REJECTED_MESSAGES: Readonly<Record<PhotoRejectReason, string>> = {
  face_visible: 'A face is visible.',
  nudity: 'The photo is not allowed.',
  no_outfit: 'No outfit is visible.',
  no_person: 'Nobody is in the photo.',
  possibly_minor: 'The photo is not allowed.',
  unreadable: 'The photo could not be read.',
};

/** B8's verdict, or `null` if moderation didn't answer in time (fail closed). */
async function moderate(jpeg: Buffer): Promise<ModerationVerdict | null> {
  let timer: NodeJS.Timeout | undefined;
  const timeout = new Promise<null>((resolve) => {
    // A little longer than B8's own MODERATION_TIMEOUT, so its answer wins when it has one.
    timer = setTimeout(() => resolve(null), MODERATION_TIMEOUT_MS + 500);
  });
  try {
    return await Promise.race([moderateImage('card', jpeg), timeout]);
  } catch (error) {
    if (!(error instanceof ModerationUnavailableError)) {
      logger.warn('checkin.moderation_error', {
        errorClass: error instanceof Error ? error.name : typeof error,
      });
    }
    return null;
  } finally {
    clearTimeout(timer);
  }
}

/** Tags in a stable order with duplicate extras dropped. */
function normalizeTags(tags: CardTags): CardTags {
  return {
    topColor: tags.topColor,
    ...(tags.hairLength ? { hairLength: tags.hairLength } : {}),
    ...(tags.hairColor ? { hairColor: tags.hairColor } : {}),
    extras: [...new Set(tags.extras)],
  };
}

async function removeCardPhotos(paths: readonly string[]): Promise<void> {
  if (paths.length === 0) return;
  const { error } = await serviceClient().storage.from(CARD_BUCKET).remove([...paths]);
  // Purge (B8) deletes anything left behind within PURGE_INTERVAL.
  if (error) logger.warn('checkin.photo_remove_failed', { count: paths.length });
}

export const createCheckin: RouteHandler<'createCheckin'> = async ({ user, params, body }) => {
  const roomId = params.id;
  const userId = user.id;

  if (!(await verifyJoinTicket(body.ticket, { userId, roomId }))) {
    logger.info('checkin.refused', { roomId, outcome: 'join_ticket_invalid' });
    return errorReply(422, 'join_ticket_invalid', 'The join ticket is not valid. Join again.');
  }

  const jpeg = await normalizeCardPhoto(decodePhoto(body.photo));

  const verdict = await moderate(jpeg);
  if (!verdict) {
    logger.warn('checkin.refused', { roomId, outcome: 'moderation_unavailable' });
    return errorReply(503, 'unavailable', 'Photo checks are briefly unavailable.', 'moderation');
  }
  if (!verdict.ok) {
    logger.info('checkin.refused', { roomId, outcome: 'photo_rejected', reason: verdict.reason });
    return errorReply(422, 'photo_rejected', REJECTED_MESSAGES[verdict.reason], verdict.reason);
  }

  const db = serviceClient();
  const cardId = randomUUID();
  const cardPath = `${roomId}/${cardId}.jpg`;
  const uploaded = await db.storage.from(CARD_BUCKET).upload(cardPath, jpeg, {
    contentType: 'image/jpeg',
    cacheControl: 'no-store',
    upsert: false,
  });
  if (uploaded.error) {
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
