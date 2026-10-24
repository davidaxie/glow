/**
 * Owner: B4. STAND-IN for B3's signed card links, until `server/src/server/images` merges
 * (AGENTS.md, "Mocks"). Swap the export in `../dependencies.ts`, then delete this file.
 *
 * It makes the exact link B3's image route checks (docs/CONTRACTS.md, "Card image links"):
 *
 *   /api/cards/{cardId}/image?exp={unix seconds}&sig={base64url HMAC-SHA256(CARD_URL_SECRET,
 *   "{cardId}.{viewerId}.{exp}")}
 *
 * The viewer is inside the signature, not the link, so the link carries no user ID (P1) and
 * works only with that viewer's bearer token.
 */
import { createHmac } from 'node:crypto';
import { CARD_URL_TTL_SECONDS, type SignedImage } from '@/contracts';
import { getEnv } from '@/env';

export function signCardImage(cardId: string, viewerId: string, now = Date.now()): SignedImage {
  const exp = Math.floor(now / 1000) + CARD_URL_TTL_SECONDS;
  const sig = createHmac('sha256', getEnv().CARD_URL_SECRET)
    .update(`${cardId}.${viewerId}.${exp}`)
    .digest('base64url');
  return {
    url: `/api/cards/${cardId}/image?exp=${exp}&sig=${sig}`,
    expiresAt: new Date(exp * 1000).toISOString(),
  };
}
