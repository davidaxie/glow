/**
 * GET /api/cards/{cardId}/image (getCardImage): a watermarked card photo through a signed
 * 60-second link (P4).
 *
 * In order, each failing as the same 404 (P11):
 * 1. The signature must be for this card and for the signed-in viewer, and unexpired. A link
 *    someone else made, or one past `exp`, fails here without touching the database.
 * 2. `card_visible_to(viewer, card)`: the card is in the viewer's deck right now and the deck
 *    has shown it to them, or it's their own open card.
 * 3. The photo is read from the private bucket, watermarked with the viewer's code, and sent
 *    with `Cache-Control: no-store`.
 */
import { notFound, type RouteHandler } from '@/server/http';
import { logger } from '@/server/log';
import { httpErrorFor } from './db-errors';
import { readPrivateObject, viewerCodeOf, watermarkedResponse } from './serve';
import { isValidCardImageLink } from './signed-link';
import { CARD_BUCKET, serviceClient } from './supabase';

export const getCardImage: RouteHandler<'getCardImage'> = async ({ user, params, query }) => {
  const cardId = params.cardId;
  const linkOk = isValidCardImageLink({
    cardId,
    viewerId: user.id,
    exp: query.exp,
    sig: query.sig,
  });
  if (!linkOk) {
    logger.info('card_image.refused', { outcome: 'link' });
    throw notFound();
  }

  const db = serviceClient();
  const visible = await db.rpc('card_visible_to', {
    p_viewer_id: user.id,
    p_checkin_id: cardId,
  });
  if (visible.error) throw httpErrorFor(visible.error);
  if (visible.data !== true) {
    logger.info('card_image.refused', { outcome: 'not_visible' });
    throw notFound();
  }

  const card = await db.from('checkins').select('card_path').eq('id', cardId).maybeSingle();
  if (card.error) throw httpErrorFor(null);
  if (!card.data) throw notFound();

  const [bytes, code] = await Promise.all([
    readPrivateObject(CARD_BUCKET, card.data.card_path, db),
    viewerCodeOf(user.id, db),
  ]);
  return watermarkedResponse(bytes, code);
};
