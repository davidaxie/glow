/**
 * Signed card image links (P4). A link is bound to one card, one viewer and one expiry:
 *
 *   /api/cards/{cardId}/image?exp={unix seconds}&sig={base64url HMAC-SHA256}
 *
 * The signature covers `{cardId}.{viewerId}.{exp}` with CARD_URL_SECRET. The viewer is
 * never in the link: the image route takes it from the bearer token, so a link copied to
 * someone else is useless to them, and the link itself carries no user ID (P1).
 *
 * B4's deck and B3's check-in both hand out links with `cardImageLink`.
 */
import { createHmac, timingSafeEqual } from 'node:crypto';
import { CARD_URL_TTL_SECONDS } from '@/contracts';
import { getEnv } from '@/env';

export type SignedImage = { readonly url: string; readonly expiresAt: string };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const SIG = /^[A-Za-z0-9_-]{43}$/;

function signature(cardId: string, viewerId: string, exp: number): Buffer {
  return createHmac('sha256', getEnv().CARD_URL_SECRET)
    .update(`${cardId}.${viewerId}.${exp}`)
    .digest();
}

/**
 * A link to `cardId`'s photo that works only for `viewerId`, for CARD_URL_TTL seconds.
 * IDs are lowercased first, so the same person and card always sign the same way.
 */
export function cardImageLink(cardId: string, viewerId: string, now = Date.now()): SignedImage {
  const card = cardId.toLowerCase();
  const viewer = viewerId.toLowerCase();
  if (!UUID.test(card) || !UUID.test(viewer)) throw new Error('cardImageLink needs two UUIDs');
  const exp = Math.floor(now / 1000) + CARD_URL_TTL_SECONDS;
  const sig = signature(card, viewer, exp).toString('base64url');
  return {
    url: `/api/cards/${card}/image?exp=${exp}&sig=${sig}`,
    expiresAt: new Date(exp * 1000).toISOString(),
  };
}

export type LinkCheck = {
  readonly cardId: string;
  readonly viewerId: string;
  readonly exp: number;
  readonly sig: string;
};

/**
 * True only if the signature matches this card and viewer, the link hasn't expired, and it
 * doesn't claim to live longer than CARD_URL_TTL from now (no link we make ever does).
 * Compared in constant time.
 */
export function isValidCardImageLink(
  { cardId, viewerId, exp, sig }: LinkCheck,
  now = Date.now(),
): boolean {
  const card = cardId.toLowerCase();
  const viewer = viewerId.toLowerCase();
  if (!UUID.test(card) || !UUID.test(viewer) || !SIG.test(sig)) return false;
  if (!Number.isSafeInteger(exp)) return false;
  const nowSeconds = Math.floor(now / 1000);
  if (exp <= nowSeconds || exp > nowSeconds + CARD_URL_TTL_SECONDS) return false;
  const expected = signature(card, viewer, exp);
  const given = Buffer.from(sig, 'base64url');
  return given.length === expected.length && timingSafeEqual(given, expected);
}
