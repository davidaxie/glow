import { createHmac } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { afterEach, describe, expect, it } from 'vitest';
import { zAdminRoom, zDisplayToken } from '@/contracts';
import { setAdminDepsForTests } from '@/server/admin/context';
import { WEB_DOMAIN, parseRoomLink, roomLink } from '@/server/admin/links';
import { displayToken, verifyRoomToken } from '@/server/qr';
import {
  cleanSpots,
  createRoom,
  displayTokenFor,
  isValidTimezone,
  newStaticToken,
  replaceSpots,
  rotateStaticToken,
  updateRoom,
} from '@/server/admin/rooms';
import { HttpError } from '@/server/http';
import { ADMIN_ID, FakeRepo, ROOM_ID, SECRET, card, fakeDeps } from './fake-repo';

afterEach(() => setAdminDepsForTests(undefined));

function setup(init?: (repo: FakeRepo) => void) {
  const repo = new FakeRepo(init);
  const { deps, events } = fakeDeps(repo);
  setAdminDepsForTests(deps);
  return { repo, events };
}

async function httpError(promise: Promise<unknown>): Promise<HttpError> {
  try {
    await promise;
  } catch (error) {
    if (error instanceof HttpError) return error;
    throw error;
  }
  throw new Error('expected an HttpError');
}

const NEW_ROOM = {
  slug: 'main-hall',
  name: '  Main hall  ',
  latitude: 37.78,
  longitude: -122.39,
  startsAt: '2026-10-24T18:00:00.000Z',
  endsAt: '2026-10-25T06:00:00.000Z',
  spots: ['Main entrance', 'Info desk', 'Water station'],
};

describe('links', () => {
  it('uses the same web domain as the iPhone app', () => {
    const xcconfig = readFileSync(
      new URL('../../../ios/Glow/Config/Shared.xcconfig', import.meta.url),
      'utf8',
    );
    const appDomain = /^GLOW_WEB_DOMAIN\s*=\s*(\S+)/m.exec(xcconfig)?.[1];
    expect(appDomain).toBe(WEB_DOMAIN);
  });

  it('builds the poster link and reads it back', () => {
    const link = roomLink('demo', 'DEMOSTATICTOKEN2');
    expect(link).toBe(`https://${WEB_DOMAIN}/r/demo?t=DEMOSTATICTOKEN2`);
    expect(parseRoomLink(link)).toEqual({ slug: 'demo', token: 'DEMOSTATICTOKEN2' });
    expect(parseRoomLink('https://evil.example/r/demo?t=DEMOSTATICTOKEN2')).toBeNull();
  });

  it('refuses a slug or token that could break the link', () => {
    expect(() => roomLink('Demo/../x', 'DEMOSTATICTOKEN2')).toThrow();
    expect(() => roomLink('demo', 'abc')).toThrow();
  });
});

describe('screen tokens', () => {
  // Written out independently of the code under test: HMAC-SHA256 keyed with the hex-decoded
  // secret over the window as an 8-byte big-endian integer, base32, first 8 (B2's D47).
  function reference(secretHex: string, nowMs: number): string {
    const counter = Buffer.alloc(8);
    counter.writeBigUInt64BE(BigInt(Math.floor(nowMs / 30_000)));
    const mac = createHmac('sha256', Buffer.from(secretHex, 'hex')).update(counter).digest();
    let bits = '';
    for (const byte of mac) bits += byte.toString(2).padStart(8, '0');
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    let out = '';
    for (let i = 0; i + 5 <= bits.length && out.length < 8; i += 5) {
      out += alphabet[parseInt(bits.slice(i, i + 5), 2)];
    }
    return out;
  }

  it('matches the joining side for the seeded demo room', () => {
    for (const now of [0, 1_793_000_000_000, 1_793_000_029_999, 1_793_000_030_000]) {
      expect(displayToken(SECRET, now).token).toBe(reference(SECRET, now));
    }
  });

  it('changes every QR_ROTATION window and says when', () => {
    const at = 1_793_000_010_000;
    const a = displayToken(SECRET, at);
    const b = displayToken(SECRET, at + 30_000);
    expect(a.token).not.toBe(b.token);
    expect(a.windowEndsAt.getTime() % 30_000).toBe(0);
    expect(a.windowEndsAt.getTime() - at).toBeLessThanOrEqual(30_000);
  });

  it('serves the token with its screen link', async () => {
    setup();
    const body = zDisplayToken.parse(await displayTokenFor(ROOM_ID));
    expect(parseRoomLink(body.url)).toEqual({ slug: 'demo', token: body.token });
    expect(body.token).toMatch(/^[A-Z2-7]{8}$/);
  });

  it('is a token the join route accepts now and for one more window, then refuses', async () => {
    const { repo } = setup();
    const room = repo.rooms.get(ROOM_ID)!;
    const now = repo.now();
    const { token, windowEndsAt } = await displayTokenFor(ROOM_ID);
    const secrets = {
      qrSecret: room.qrSecret,
      staticQrToken: room.staticQrToken,
      allowStaticQr: true,
    };
    const ends = Date.parse(windowEndsAt);
    expect(verifyRoomToken(secrets, token, now)).toBe(true);
    expect(verifyRoomToken(secrets, token, ends + 1_000)).toBe(true);
    expect(verifyRoomToken(secrets, token, ends + 30_000 + 1_000)).toBe(false);
  });
});

describe('createRoom', () => {
  it('makes a room with its spots, trimmed, and the contract shape', async () => {
    const { repo } = setup();
    const created = zAdminRoom.parse(await createRoom(NEW_ROOM, ADMIN_ID));
    expect(created.name).toBe('Main hall');
    expect(created.radiusM).toBe(200);
    expect(created.timezone).toBe('America/Los_Angeles');
    expect(created.allowStaticQr).toBe(false);
    expect(created.demoMode).toBe(false);
    expect(created.spots.map((s) => s.name)).toEqual(NEW_ROOM.spots);
    expect(created.link).toBe(roomLink('main-hall', created.staticQrToken));
    expect(repo.rooms.size).toBe(2);
  });

  it('answers 409 slug_taken for a link name in use', async () => {
    setup();
    const error = await httpError(createRoom({ ...NEW_ROOM, slug: 'demo' }, ADMIN_ID));
    expect([error.status, error.code]).toEqual([409, 'slug_taken']);
  });

  it.each([
    ['ends before it starts', { endsAt: '2026-10-24T17:00:00.000Z' }],
    ['two spots', { spots: ['A', 'B'] }],
    ['six spots', { spots: ['A', 'B', 'C', 'D', 'E', 'F'] }],
    ['the same spot twice', { spots: ['Bar', 'bar ', 'Stage'] }],
    ['a blank spot', { spots: ['Bar', '   ', 'Stage'] }],
    ['a made-up timezone', { timezone: 'Mars/Olympus_Mons' }],
    ['a blank name', { name: '   ' }],
  ])('refuses %s with 400', async (_label, change) => {
    const { repo } = setup();
    const error = await httpError(createRoom({ ...NEW_ROOM, ...change }, ADMIN_ID));
    expect(error.status).toBe(400);
    expect(repo.calls).not.toContain('createRoom');
  });
});

describe('updateRoom', () => {
  it('pausing tells the room to refetch its deck', async () => {
    const { events } = setup();
    const after = await updateRoom(ROOM_ID, { status: 'paused' }, ADMIN_ID);
    expect(after.status).toBe('paused');
    expect(events.deckChanged).toEqual([ROOM_ID]);
  });

  it('turning on demo mode changes no deck', async () => {
    const { events } = setup();
    expect((await updateRoom(ROOM_ID, { demoMode: true }, ADMIN_ID)).demoMode).toBe(true);
    expect(events.deckChanged).toEqual([]);
  });

  it('ending the room ends every check-in and deletes every card photo now', async () => {
    const a = card();
    const b = card({ userId: ADMIN_ID });
    const { repo, events } = setup((r) => {
      r.cards.set(a.id, a);
      r.cards.set(b.id, b);
    });
    await updateRoom(ROOM_ID, { status: 'ended' }, ADMIN_ID);
    expect([...repo.cards.values()].every((c) => c.leftAt !== null && !c.visible)).toBe(true);
    expect(repo.deletedPhotos.sort()).toEqual([a.cardPath, b.cardPath].sort());
    expect(events.deckChanged).toEqual([ROOM_ID]);
  });

  it('moving the end into the past ends the room the same way', async () => {
    const a = card();
    const { repo } = setup((r) => r.cards.set(a.id, a));
    await updateRoom(ROOM_ID, { endsAt: '2026-10-24T18:59:00.000Z' }, ADMIN_ID);
    expect(repo.cards.get(a.id)?.leftAt).not.toBeNull();
    expect(repo.deletedPhotos).toEqual([a.cardPath]);
  });

  it('moving the end earlier cuts check-ins short (D15)', async () => {
    const a = card({ expiresAt: '2026-10-24T21:00:00.000Z' });
    const { repo } = setup((r) => r.cards.set(a.id, a));
    await updateRoom(ROOM_ID, { endsAt: '2026-10-24T20:00:00.000Z' }, ADMIN_ID);
    expect(repo.cards.get(a.id)?.expiresAt).toBe('2026-10-24T20:00:00.000Z');
    expect(repo.cards.get(a.id)?.leftAt).toBeNull();
  });

  it('checks the times against the stored ones', async () => {
    setup();
    const error = await httpError(
      updateRoom(ROOM_ID, { startsAt: '2026-12-01T00:00:00.000Z' }, ADMIN_ID),
    );
    expect(error.status).toBe(400);
  });

  it('is 404 for a room that does not exist', async () => {
    setup();
    const error = await httpError(
      updateRoom('00000000-0000-4000-8000-000000000000', { name: 'x' }, ADMIN_ID),
    );
    expect(error.status).toBe(404);
  });
});

describe('meeting spots and poster tokens', () => {
  it('renames spots in place, so IDs stay', async () => {
    const { repo } = setup();
    const before = repo.rooms.get(ROOM_ID)!.spots;
    const after = await replaceSpots(
      ROOM_ID,
      ['Front door', 'Food line', 'Water', 'Stage'],
      ADMIN_ID,
    );
    expect(after.spots.slice(0, 3).map((s) => s.id)).toEqual(before.map((s) => s.id));
    expect(after.spots.map((s) => s.name)).toEqual(['Front door', 'Food line', 'Water', 'Stage']);
  });

  it('cleans spot names', () => {
    expect(cleanSpots(['  Main   entrance ', 'Bar', 'Stage'])).toEqual([
      'Main entrance',
      'Bar',
      'Stage',
    ]);
  });

  it('makes a fresh 16-character poster token', async () => {
    setup();
    const tokens = new Set(Array.from({ length: 50 }, newStaticToken));
    expect(tokens.size).toBe(50);
    for (const t of tokens) expect(t).toMatch(/^[A-Z2-7]{16}$/);
    const after = await rotateStaticToken(ROOM_ID, ADMIN_ID);
    expect(after.staticQrToken).not.toBe('DEMOSTATICTOKEN2');
    expect(after.link).toContain(after.staticQrToken);
  });

  it('knows real timezones', () => {
    expect(isValidTimezone('America/Los_Angeles')).toBe(true);
    expect(isValidTimezone('UTC')).toBe(true);
    expect(isValidTimezone('Nope/Nowhere')).toBe(false);
  });
});
