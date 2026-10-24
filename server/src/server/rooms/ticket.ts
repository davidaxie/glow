/**
 * Join tickets: what a passed location check hands the app, and what check-in needs.
 * Owner: B2. B3's check-in route calls `verifyJoinTicket`.
 *
 * A ticket is an encrypted JWT (JWE, `dir` + `A256GCM`) with:
 *
 *   sub   the person's user ID          room  the room ID
 *   chk   the location_checks row ID    res   'pass' or 'demo_skip'
 *   iat   issued at                     exp   iat + JOIN_TICKET_TTL
 *   iss   'glow'                        aud   'glow:checkin'
 *
 * It's encrypted, not just signed, so the ticket is opaque to the app and to anything
 * that sees it: no user or room ID can be read out of it (D20). AES-GCM also
 * authenticates it, so it can't be forged or edited. The key is derived from
 * JOIN_TICKET_SECRET with HKDF, so the secret itself is never used as a raw key.
 */
import { hkdfSync } from 'node:crypto';
import { EncryptJWT, jwtDecrypt } from 'jose';
import { JOIN_TICKET_TTL_SECONDS } from '@/contracts';
import { getEnv } from '@/env';

const ISSUER = 'glow';
const AUDIENCE = 'glow:checkin';
const KEY_INFO = 'glow join ticket v1';
/** Compact JWEs of these claims are about 400 characters. Anything far longer isn't one. */
const MAX_TICKET_LENGTH = 2048;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

export type JoinTicketResult = 'pass' | 'demo_skip';

export type IssuedJoinTicket = {
  readonly ticket: string;
  readonly expiresAt: Date;
};

export type VerifiedJoinTicket = {
  /** The `location_checks` row the ticket came from. */
  readonly locationCheckId: string;
  readonly result: JoinTicketResult;
  readonly issuedAt: Date;
  readonly expiresAt: Date;
};

let cachedKey: { secret: string; key: Uint8Array } | undefined;

function ticketKey(): Uint8Array {
  const secret = getEnv().JOIN_TICKET_SECRET;
  if (cachedKey?.secret !== secret) {
    const key = new Uint8Array(hkdfSync('sha256', secret, 'glow', KEY_INFO, 32));
    cachedKey = { secret, key };
  }
  return cachedKey.key;
}

export async function issueJoinTicket(input: {
  readonly userId: string;
  readonly roomId: string;
  readonly locationCheckId: string;
  readonly result: JoinTicketResult;
  readonly now?: Date;
}): Promise<IssuedJoinTicket> {
  const issuedAt = Math.floor((input.now ?? new Date()).getTime() / 1000);
  const expiresAt = issuedAt + JOIN_TICKET_TTL_SECONDS;
  const ticket = await new EncryptJWT({
    room: input.roomId,
    chk: input.locationCheckId,
    res: input.result,
  })
    .setProtectedHeader({ alg: 'dir', enc: 'A256GCM', typ: 'glow-join+jwt' })
    .setSubject(input.userId)
    .setIssuer(ISSUER)
    .setAudience(AUDIENCE)
    .setIssuedAt(issuedAt)
    .setExpirationTime(expiresAt)
    .encrypt(ticketKey());
  return { ticket, expiresAt: new Date(expiresAt * 1000) };
}

/**
 * The ticket's contents, if it was issued to this person for this room and hasn't
 * expired. Null for anything else: expired, edited, someone else's, another room's.
 * B3 answers null with 422 `join_ticket_invalid`.
 */
export async function verifyJoinTicket(
  ticket: string,
  expected: { readonly userId: string; readonly roomId: string; readonly now?: Date },
): Promise<VerifiedJoinTicket | null> {
  if (typeof ticket !== 'string' || ticket.length === 0 || ticket.length > MAX_TICKET_LENGTH) {
    return null;
  }
  try {
    const { payload } = await jwtDecrypt(ticket, ticketKey(), {
      issuer: ISSUER,
      audience: AUDIENCE,
      subject: expected.userId,
      keyManagementAlgorithms: ['dir'],
      contentEncryptionAlgorithms: ['A256GCM'],
      typ: 'glow-join+jwt',
      requiredClaims: ['iat', 'exp', 'sub'],
      maxTokenAge: JOIN_TICKET_TTL_SECONDS,
      ...(expected.now ? { currentDate: expected.now } : {}),
    });
    const { room, chk, res, iat, exp } = payload;
    if (room !== expected.roomId) return null;
    if (typeof chk !== 'string' || !UUID.test(chk)) return null;
    if (res !== 'pass' && res !== 'demo_skip') return null;
    if (typeof iat !== 'number' || typeof exp !== 'number') return null;
    if (exp - iat > JOIN_TICKET_TTL_SECONDS) return null;
    return {
      locationCheckId: chk,
      result: res,
      issuedAt: new Date(iat * 1000),
      expiresAt: new Date(exp * 1000),
    };
  } catch {
    return null;
  }
}
