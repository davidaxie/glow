/**
 * TEMPORARY stand-ins for two modules other agents own, so check-in works before they merge.
 * Each has exactly the shape its owner settled on; when the real module lands, this file
 * re-exports it instead and the stub goes.
 *
 * - `verifyJoinTicket`: B2's join ticket check (`@/server/rooms`, server/src/server/rooms/ticket.ts).
 * - `moderateImage(kind, bytes)`: B8's photo moderation (`@/server/moderation`).
 *
 * Both fail closed: a stub never lets a photo through on a deployed server.
 */
import { createHmac, timingSafeEqual } from 'node:crypto';
import { JOIN_TICKET_TTL_SECONDS } from '@/contracts';
import { getEnv } from '@/env';

// ---------------------------------------------------------------------------- join tickets

/** B2's shape. */
export type JoinTicketExpectation = {
  readonly userId: string;
  readonly roomId: string;
  readonly now?: Date;
};

/** B2's shape. */
export type VerifiedJoinTicket = {
  readonly locationCheckId: string;
  readonly result: 'pass' | 'demo_skip';
  readonly issuedAt: Date;
  readonly expiresAt: Date;
};

type TicketClaims = { v: 1; sub: string; room: string; lc: string; iat: number; exp: number };

const MAX_TICKET_LENGTH = 2048;
const STUB_LOCATION_CHECK_ID = '00000000-0000-4000-8000-00000000c0de';

function ticketSignature(payload: string): Buffer {
  return createHmac('sha256', getEnv().JOIN_TICKET_SECRET).update(`join.${payload}`).digest();
}

/**
 * STUB for B2's `verifyJoinTicket`, same signature: never throws, and returns null for an
 * expired, someone else's, another room's, edited, malformed or oversized ticket. Stub tickets
 * are `base64url(claims).base64url(HMAC-SHA256(JOIN_TICKET_SECRET))`. B2's real ones are
 * encrypted. Only tests and local scripts can make a stub ticket, so on a deployed server every
 * ticket fails closed until B2's module replaces this.
 */
export async function verifyJoinTicket(
  ticket: string,
  expected: JoinTicketExpectation,
): Promise<VerifiedJoinTicket | null> {
  const now = (expected.now ?? new Date()).getTime();
  if (ticket.length > MAX_TICKET_LENGTH) return null;
  const [payload, sig, extra] = ticket.split('.');
  if (!payload || !sig || extra !== undefined) return null;
  const expectedSig = ticketSignature(payload);
  const givenSig = Buffer.from(sig, 'base64url');
  if (givenSig.length !== expectedSig.length || !timingSafeEqual(givenSig, expectedSig)) {
    return null;
  }
  let claims: Partial<TicketClaims>;
  try {
    claims = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8')) as Partial<TicketClaims>;
  } catch {
    return null;
  }
  if (
    claims.v !== 1 ||
    claims.sub !== expected.userId.toLowerCase() ||
    claims.room !== expected.roomId.toLowerCase() ||
    typeof claims.lc !== 'string' ||
    typeof claims.iat !== 'number' ||
    typeof claims.exp !== 'number' ||
    claims.exp * 1000 <= now ||
    claims.exp * 1000 > now + JOIN_TICKET_TTL_SECONDS * 1000
  ) {
    return null;
  }
  return {
    locationCheckId: claims.lc,
    result: 'pass',
    issuedAt: new Date(claims.iat * 1000),
    expiresAt: new Date(claims.exp * 1000),
  };
}

/** For tests and local scripts only: a ticket the stub accepts. */
export function signJoinTicketForTests(
  { userId, roomId, now = new Date() }: JoinTicketExpectation,
  locationCheckId = STUB_LOCATION_CHECK_ID,
): string {
  const iat = Math.floor(now.getTime() / 1000);
  const claims: TicketClaims = {
    v: 1,
    sub: userId.toLowerCase(),
    room: roomId.toLowerCase(),
    lc: locationCheckId,
    iat,
    exp: iat + JOIN_TICKET_TTL_SECONDS,
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
 * STUB for B8's `moderateImage(kind, bytes)`. In local development (the `local` profile, no
 * Anthropic key) it approves everything, like B8's deterministic dev fake. Anywhere else it
 * refuses to answer, so a card photo can never skip moderation on a deployed server.
 */
export async function moderateImage(
  _kind: 'card' | 'profile',
  _bytes: Uint8Array,
): Promise<ModerationVerdict> {
  if (getEnv().profile !== 'local') throw new ModerationUnavailableError();
  return { ok: true };
}
