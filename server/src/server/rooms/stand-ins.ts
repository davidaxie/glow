/**
 * Stand-ins for modules other Wave 1 agents are still building. Owner: B2.
 *
 * Each one follows the contract exactly, so swapping in the real export changes no
 * behavior. When the owner's PR merges, B2 replaces the body with a call to theirs
 * (docs/HANDOFFS.md, B2 · Still mocked):
 *
 * - `sendDeckChanged`  → B5's `notify()` in `server/src/server/notify/`
 * - `signedCardImage`  → B3's link signer in `server/src/server/images/`
 */
import { createHmac } from 'node:crypto';
import { CARD_URL_TTL_SECONDS, roomTopic, type SignedImage } from '@/contracts';
import { getEnv } from '@/env';
import { logger } from '@/server/log';

/**
 * Tells everyone checked into the room to refetch their deck. Payload is only the
 * type and the room ID (P1). Best effort: a failed broadcast never fails the request,
 * because the deck is rechecked on every fetch anyway.
 */
export async function sendDeckChanged(roomId: string): Promise<void> {
  const env = getEnv();
  try {
    const res = await fetch(new URL('/realtime/v1/api/broadcast', env.SUPABASE_URL), {
      method: 'POST',
      headers: {
        apikey: env.SUPABASE_SERVICE_ROLE_KEY,
        authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
        'content-type': 'application/json',
      },
      body: JSON.stringify({
        messages: [
          {
            topic: roomTopic(roomId),
            event: 'deck.changed',
            payload: { type: 'deck.changed', roomId },
            private: true,
          },
        ],
      }),
      signal: AbortSignal.timeout(2000),
    });
    if (!res.ok) logger.warn('rooms.deck_changed_failed', { roomId, status: res.status });
  } catch (error) {
    logger.warn('rooms.deck_changed_failed', {
      roomId,
      errorClass: error instanceof Error ? error.name : typeof error,
    });
  }
}

/**
 * A card image link for this viewer, per docs/CONTRACTS.md: `/api/cards/{cardId}/image
 * ?exp={unix seconds}&sig={base64url HMAC-SHA256(CARD_URL_SECRET, "{cardId}.{viewerId}.{exp}")}`.
 */
export function signedCardImage(cardId: string, viewerId: string, now = new Date()): SignedImage {
  const exp = Math.floor(now.getTime() / 1000) + CARD_URL_TTL_SECONDS;
  const sig = createHmac('sha256', getEnv().CARD_URL_SECRET)
    .update(`${cardId}.${viewerId}.${exp}`)
    .digest('base64url');
  return {
    url: `/api/cards/${cardId}/image?exp=${exp}&sig=${sig}`,
    expiresAt: new Date(exp * 1000).toISOString(),
  };
}
