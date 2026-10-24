/**
 * Owner: B4. STAND-IN for B3's `cardImageLink(cardId, viewerId)` in
 * `server/src/server/images/signed-link.ts` (draft PR #7), until it merges (AGENTS.md,
 * "Mocks"). Same signature and same output. When #7 merges, point `../dependencies.ts` at
 * `@/server/images/signed-link` and delete this file.
 *
 *   /api/cards/{cardId}/image?exp={unix seconds}&sig={base64url HMAC-SHA256(CARD_URL_SECRET,
 *   "{cardId}.{viewerId}.{exp}")}
 *
 * The viewer is inside the signature, not the link, so the link carries no user ID (P1) and
 * works only with that viewer's bearer token.
 */
import { createHmac } from 'node:crypto';
import { CARD_URL_TTL_SECONDS } from '@/contracts';
import { getEnv } from '@/env';

export type SignedImage = { readonly url: string; readonly expiresAt: string };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

export function cardImageLink(cardId: string, viewerId: string, now = Date.now()): SignedImage {
  const card = cardId.toLowerCase();
  const viewer = viewerId.toLowerCase();
  if (!UUID.test(card) || !UUID.test(viewer)) throw new Error('cardImageLink needs two UUIDs');
  const exp = Math.floor(now / 1000) + CARD_URL_TTL_SECONDS;
  const sig = createHmac('sha256', getEnv().CARD_URL_SECRET)
    .update(`${card}.${viewer}.${exp}`)
    .digest('base64url');
  return {
    url: `/api/cards/${card}/image?exp=${exp}&sig=${sig}`,
    expiresAt: new Date(exp * 1000).toISOString(),
  };
}
