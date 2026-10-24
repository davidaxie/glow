/**
 * Join tickets (B2, B2-D1): issued after a passed check, opaque, and only good for that
 * person, that room and JOIN_TICKET_TTL.
 */
import { describe, expect, it } from 'vitest';
import { JOIN_TICKET_TTL_SECONDS } from '@/contracts';
import { resetEnvCacheForTests } from '@/env';
import { issueJoinTicket, verifyJoinTicket } from '@/server/rooms';

const USER = '6a1e5c1e-7f0b-4c55-9a38-2d1f7c3b9e01';
const OTHER_USER = '6a1e5c1e-7f0b-4c55-9a38-2d1f7c3b9e02';
const ROOM = 'de000000-0000-4000-8000-000000000001';
const OTHER_ROOM = 'de000000-0000-4000-8000-000000000002';
const CHECK = '0c0c0c0c-0000-4000-8000-000000000001';
const NOW = new Date('2026-10-24T20:00:00.000Z');
const later = (seconds: number) => new Date(NOW.getTime() + seconds * 1000);

const issue = (overrides: Partial<Parameters<typeof issueJoinTicket>[0]> = {}) =>
  issueJoinTicket({
    userId: USER,
    roomId: ROOM,
    locationCheckId: CHECK,
    result: 'pass',
    now: NOW,
    ...overrides,
  });

describe('join tickets', () => {
  it('round-trips for the same person and room', async () => {
    const { ticket, expiresAt } = await issue();
    expect(expiresAt.toISOString()).toBe(later(JOIN_TICKET_TTL_SECONDS).toISOString());
    const verified = await verifyJoinTicket(ticket, { userId: USER, roomId: ROOM, now: later(1) });
    expect(verified).toEqual({
      locationCheckId: CHECK,
      result: 'pass',
      issuedAt: NOW,
      expiresAt,
    });
  });

  it('carries a demo skip', async () => {
    const { ticket } = await issue({ result: 'demo_skip' });
    const verified = await verifyJoinTicket(ticket, { userId: USER, roomId: ROOM, now: NOW });
    expect(verified?.result).toBe('demo_skip');
  });

  it('works until the last second of JOIN_TICKET_TTL, and not after', async () => {
    const { ticket } = await issue();
    const at = (s: number) =>
      verifyJoinTicket(ticket, { userId: USER, roomId: ROOM, now: later(s) });
    expect(await at(JOIN_TICKET_TTL_SECONDS - 1)).not.toBeNull();
    expect(await at(JOIN_TICKET_TTL_SECONDS)).toBeNull();
    expect(await at(JOIN_TICKET_TTL_SECONDS + 60)).toBeNull();
  });

  it('is useless to someone else, or for another room', async () => {
    const { ticket } = await issue();
    expect(
      await verifyJoinTicket(ticket, { userId: OTHER_USER, roomId: ROOM, now: NOW }),
    ).toBeNull();
    expect(
      await verifyJoinTicket(ticket, { userId: USER, roomId: OTHER_ROOM, now: NOW }),
    ).toBeNull();
  });

  it('refuses an edited ticket', async () => {
    const { ticket } = await issue();
    const parts = ticket.split('.');
    const body = parts[3]!;
    parts[3] = (body[0] === 'A' ? 'B' : 'A') + body.slice(1);
    expect(
      await verifyJoinTicket(parts.join('.'), { userId: USER, roomId: ROOM, now: NOW }),
    ).toBeNull();
  });

  it('refuses junk without throwing', async () => {
    for (const junk of ['', 'abc', 'a.b.c.d.e', 'x'.repeat(5000)]) {
      expect(await verifyJoinTicket(junk, { userId: USER, roomId: ROOM, now: NOW })).toBeNull();
    }
  });

  it('refuses a ticket made with another JOIN_TICKET_SECRET', async () => {
    const { ticket } = await issue();
    process.env.JOIN_TICKET_SECRET = 'a-completely-different-join-ticket-secret-000000000000';
    resetEnvCacheForTests();
    expect(await verifyJoinTicket(ticket, { userId: USER, roomId: ROOM, now: NOW })).toBeNull();
  });

  it('is opaque: no user ID, room ID or check ID can be read out of it', async () => {
    const { ticket } = await issue();
    const decoded = ticket
      .split('.')
      .map((part) => Buffer.from(part, 'base64url').toString('latin1'))
      .join('|');
    for (const secret of [USER, ROOM, CHECK]) {
      expect(ticket).not.toContain(secret);
      expect(decoded).not.toContain(secret);
    }
    // Five parts: a compact JWE, not a signed (readable) JWT.
    expect(ticket.split('.')).toHaveLength(5);
  });
});
