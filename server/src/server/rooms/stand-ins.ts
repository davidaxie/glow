/**
 * What the rooms module uses from other owners. Owner: B2.
 *
 * These were stand-ins until the owners' PRs merged; each is now a thin call to the real
 * export (D1's `integration` PR):
 *
 * - `sendDeckChanged`  → B5's `notifyRoom()` from `@/server/notify`
 * - `signedCardImage`  → B3's `cardImageLink()` from `@/server/images`
 */
import type { SignedImage } from '@/contracts';
import { cardImageLink } from '@/server/images/signed-link';
import { notifyRoom } from '@/server/notify';

/**
 * Tells everyone checked into the room to refetch their deck. Payload is only the type and
 * the room ID (P1). Never throws: `notifyRoom` logs a failed broadcast, and the deck is
 * rechecked on every fetch anyway.
 */
export async function sendDeckChanged(roomId: string): Promise<void> {
  await notifyRoom(roomId, { type: 'deck.changed', roomId });
}

/** A 60-second card image link that works only for this viewer (B3's signer, P4). */
export function signedCardImage(cardId: string, viewerId: string, now = new Date()): SignedImage {
  return cardImageLink(cardId, viewerId, now.getTime());
}
