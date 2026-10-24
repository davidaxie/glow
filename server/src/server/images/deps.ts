/**
 * What check-in needs from other agents' modules, in one place.
 *
 * - `moderateImage`, `photoRejected` (B8, `@/server/moderation`) and `rateLimit` (B8,
 *   `@/server/ratelimit`): the real modules.
 * - `verifyJoinTicket` (B2, `@/server/rooms`): a TEMPORARY stub with exactly B2's signature,
 *   until B2's module merges; then this file re-exports B2's and the stub goes. It fails
 *   closed: only tests and local scripts can make a ticket it accepts.
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
    claims = JSON.parse(
      Buffer.from(payload, 'base64url').toString('utf8'),
    ) as Partial<TicketClaims>;
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

// ---------------------------------------------------------------------------- B8, real

export { moderateImage, photoRejected } from '@/server/moderation';
export { rateLimit } from '@/server/ratelimit';
