/**
 * TEMPORARY stand-ins for two modules other agents own, so check-in works before they merge.
 * Each is one function with the shape the owner settled on; when the real module lands, this
 * file re-exports it instead and the stub goes.
 *
 * - `verifyJoinTicket`: B2's join ticket check (server/src/server/rooms).
 * - `moderateImage(kind, bytes)`: B8's photo moderation (server/src/server/moderation).
 *
 * Both fail closed: a stub never lets a photo through outside local development.
 */
import { createHmac, timingSafeEqual } from 'node:crypto';
import { JOIN_TICKET_TTL_SECONDS } from '@/contracts';
import { getEnv } from '@/env';

// ---------------------------------------------------------------------------- join tickets

export type JoinTicketExpectation = { readonly userId: string; readonly roomId: string };

type TicketClaims = { v: 1; sub: string; room: string; exp: number };

function ticketSignature(payload: string): Buffer {
  return createHmac('sha256', getEnv().JOIN_TICKET_SECRET).update(`join.${payload}`).digest();
}

/**
 * STUB for B2. A ticket is `base64url(claims).base64url(HMAC-SHA256(JOIN_TICKET_SECRET))`,
 * claims `{ v: 1, sub, room, exp }`. True only for this person and room, before it expires.
 * The database (migration 0002) separately requires a passed location check within
 * JOIN_TICKET_TTL, so a ticket alone never gets anyone in.
 */
export async function verifyJoinTicket(
  ticket: string,
  expected: JoinTicketExpectation,
  now = Date.now(),
): Promise<boolean> {
  if (ticket.length > 1024) return false;
  const [payload, sig, extra] = ticket.split('.');
  if (!payload || !sig || extra !== undefined) return false;
  const expectedSig = ticketSignature(payload);
  const givenSig = Buffer.from(sig, 'base64url');
  if (givenSig.length !== expectedSig.length || !timingSafeEqual(givenSig, expectedSig)) {
    return false;
  }
  let claims: Partial<TicketClaims>;
  try {
    claims = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8')) as Partial<TicketClaims>;
  } catch {
    return false;
  }
  return (
    claims.v === 1 &&
    claims.sub === expected.userId.toLowerCase() &&
    claims.room === expected.roomId.toLowerCase() &&
    typeof claims.exp === 'number' &&
    claims.exp * 1000 > now &&
    claims.exp * 1000 <= now + JOIN_TICKET_TTL_SECONDS * 1000
  );
}

/** For tests and local scripts only: a ticket the stub accepts. */
export function signJoinTicketForTests(
  { userId, roomId }: JoinTicketExpectation,
  now = Date.now(),
): string {
  const claims: TicketClaims = {
    v: 1,
    sub: userId.toLowerCase(),
    room: roomId.toLowerCase(),
    exp: Math.floor(now / 1000) + JOIN_TICKET_TTL_SECONDS,
  };
  const payload = Buffer.from(JSON.stringify(claims)).toString('base64url');
  return `${payload}.${ticketSignature(payload).toString('base64url')}`;
}

// ---------------------------------------------------------------------------- moderation

/** Why a photo was refused (ErrorBody.reason for `photo_rejected`). */
export type PhotoRejectReason =
  | 'face_visible'
  | 'nudity'
  | 'no_outfit'
  | 'no_person'
  | 'possibly_minor'
  | 'unreadable';

export type ModerationVerdict =
  | { readonly ok: true }
  | { readonly ok: false; readonly reason: PhotoRejectReason };

/** Moderation couldn't answer within MODERATION_TIMEOUT. Card photos fail closed (503). */
export class ModerationUnavailableError extends Error {
  override readonly name = 'ModerationUnavailableError';
}

/**
 * STUB for B8's `moderateImage(kind, bytes)`. In local development (no Anthropic key, the
 * `local` profile) it approves everything, like B8's deterministic dev fake. Anywhere else it
 * refuses to answer, so a card photo can never skip moderation on a deployed server.
 */
export async function moderateImage(
  _kind: 'card' | 'profile',
  _bytes: Uint8Array,
): Promise<ModerationVerdict> {
  if (getEnv().profile !== 'local') throw new ModerationUnavailableError();
  return { ok: true };
}
