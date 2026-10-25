/**
 * Owner: X1. Signed Blind image links (P4), the same scheme as Glow's card links
 * (`images/signed-link.ts`, CARD_URL_SECRET, CARD_URL_TTL), with their own prefix so a Blind
 * link can never be used on a Glow route or the other way round. The viewer is never in the
 * link: the image route takes it from the bearer token.
 *
 *   /api/blind/cards/{cardId}/image?exp&sig        sig over blind-card.{cardId}.{viewer}.{exp}
 *   /api/blind/chats/{chatId}/photos/{n}?exp&sig   sig over blind-photo.{chatId}.{n}.{viewer}.{exp}
 */
import { createHmac, timingSafeEqual } from 'node:crypto';
import { CARD_URL_TTL_SECONDS } from '@/contracts';
import { getEnv } from '@/env';

const SIG = /^[A-Za-z0-9_-]{43}$/;

function sign(payload: string): Buffer {
  return createHmac('sha256', getEnv().CARD_URL_SECRET).update(payload).digest();
}

function expiry(now: number): number {
  return Math.floor(now / 1000) + CARD_URL_TTL_SECONDS;
}

export function blindCardLink(cardId: string, viewerId: string, now = Date.now()): string {
  const card = cardId.toLowerCase();
  const exp = expiry(now);
  const sig = sign(`blind-card.${card}.${viewerId.toLowerCase()}.${exp}`).toString('base64url');
  return `/api/blind/cards/${card}/image?exp=${exp}&sig=${sig}`;
}

export function blindPhotoLink(
  chatId: string,
  n: number,
  viewerId: string,
  now = Date.now(),
): string {
  const chat = chatId.toLowerCase();
  const exp = expiry(now);
  const sig = sign(`blind-photo.${chat}.${n}.${viewerId.toLowerCase()}.${exp}`).toString(
    'base64url',
  );
  return `/api/blind/chats/${chat}/photos/${n}?exp=${exp}&sig=${sig}`;
}

function valid(payload: string, exp: number, sig: string, now: number): boolean {
  if (!SIG.test(sig) || !Number.isSafeInteger(exp)) return false;
  const nowSeconds = Math.floor(now / 1000);
  if (exp <= nowSeconds || exp > nowSeconds + CARD_URL_TTL_SECONDS) return false;
  const expected = sign(payload);
  const given = Buffer.from(sig, 'base64url');
  return given.length === expected.length && timingSafeEqual(given, expected);
}

export function isValidBlindCardLink(
  cardId: string,
  viewerId: string,
  exp: number,
  sig: string,
  now = Date.now(),
): boolean {
  return valid(
    `blind-card.${cardId.toLowerCase()}.${viewerId.toLowerCase()}.${exp}`,
    exp,
    sig,
    now,
  );
}

export function isValidBlindPhotoLink(
  chatId: string,
  n: number,
  viewerId: string,
  exp: number,
  sig: string,
  now = Date.now(),
): boolean {
  return valid(
    `blind-photo.${chatId.toLowerCase()}.${n}.${viewerId.toLowerCase()}.${exp}`,
    exp,
    sig,
    now,
  );
}
