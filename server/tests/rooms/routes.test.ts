/**
 * B2's routes end to end through the route helper: sign-in, P11 404s, onboarding,
 * room status, the location check, demo skips, tickets, leaving and room state.
 * Supabase Auth is mocked and the database is an in-memory fake (./fake-db.ts).
 */
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { qrWindow, rotatingToken } from '@/server/qr';
import { memoryStore, setRateLimitStoreForTests } from '@/server/ratelimit';
import { setServiceDbForTests } from '@/server/rooms/db';
import { verifyJoinTicket } from '@/server/rooms';
import { destinationPoint } from '@/server/geo';
import * as resolveRoute from '../../app/api/rooms/resolve/route';
import * as joinRoute from '../../app/api/rooms/[id]/join/route';
import * as leaveRoute from '../../app/api/rooms/[id]/leave/route';
import * as stateRoute from '../../app/api/rooms/[id]/route';
import * as aasaRoute from '../../app/.well-known/apple-app-site-association/route';
import * as webRoute from '../../app/r/[slug]/route';
import { mockVerify, USER_ID } from '../helpers/auth';
import { call } from './helpers';
import { DEMO_CENTER, DEMO_ROOM_ID, FakeDb, demoRoom, onboarded } from './fake-db';

vi.mock('@/server/auth/verify', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@/server/auth/verify')>();
  return { ...actual, verifyAccessToken: vi.fn() };
});
// The real generated registry, whatever `operations.ts` points at today.
vi.mock('@/server/http/operations', async () => ({
  operations: (await import('@/contracts/operations')).operations,
}));

const OTHER_ROOM_ID = 'de000000-0000-4000-8000-000000000002';
const SECRET = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';
const LINK = { kind: 'link', slug: 'demo', token: 'DEMOSTATICTOKEN2' } as const;
const CODE = { kind: 'code', code: 'hack26' } as const;
const inside = { ...DEMO_CENTER, accuracy: 8 };
const away = { ...destinationPoint(DEMO_CENTER, 0, 2000), accuracy: 8 };

let db: FakeDb;
let fetchSpy: ReturnType<typeof vi.spyOn>;

function seed(
  room = demoRoom(),
  profile = onboarded(USER_ID),
  extra: Record<string, unknown[]> = {},
) {
  db = new FakeDb({
    rooms: [
      room,
      demoRoom({
        id: OTHER_ROOM_ID,
        slug: 'other',
        code: 'ABCD23',
        static_qr_token: 'OTHERSTATICTOKEN',
      }),
    ],
    profiles: [profile],
    admins: [],
    checkins: [],
    location_checks: [],
    ...(extra as Record<string, Record<string, unknown>[]>),
  });
  setServiceDbForTests(db.asDb());
}

beforeEach(async () => {
  await mockVerify();
  setRateLimitStoreForTests(memoryStore());
  seed();
  fetchSpy = vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(null, { status: 202 }));
  vi.spyOn(console, 'log').mockImplementation(() => {});
});

afterEach(() => {
  setServiceDbForTests(undefined);
  setRateLimitStoreForTests(undefined);
  // tests/setup.ts doesn't reset these two.
  delete process.env.APPLE_APP_ID;
  delete process.env.TESTFLIGHT_URL;
});

const resolve = (json: unknown, token?: string | null) =>
  call(resolveRoute.POST, {
    path: '/api/rooms/resolve',
    json,
    ...(token !== undefined ? { token } : {}),
  });
const join = (json: unknown, roomId = DEMO_ROOM_ID, token?: string | null) =>
  call(joinRoute.POST, {
    path: `/api/rooms/${roomId}/join`,
    json,
    params: { id: roomId },
    ...(token !== undefined ? { token } : {}),
  });
const leave = (roomId = DEMO_ROOM_ID) =>
  call(leaveRoute.POST, { path: `/api/rooms/${roomId}/leave`, params: { id: roomId } });
const state = (roomId = DEMO_ROOM_ID) =>
  call(stateRoute.GET, { path: `/api/rooms/${roomId}`, method: 'GET', params: { id: roomId } });

const errorCode = (body: unknown) => (body as { error: { code: string } }).error.code;

describe('POST /api/rooms/resolve', () => {
  it('needs sign-in', async () => {
    expect((await resolve(LINK, null)).status).toBe(401);
  });

  it('turns a poster link into the room summary, with no location or secrets', async () => {
    const res = await resolve(LINK);
    expect(res.status).toBe(200);
    expect(res.body).toEqual({
      id: DEMO_ROOM_ID,
      slug: 'demo',
      name: 'Glow demo room (test data)',
      status: 'live',
      startsAt: expect.stringMatching(/Z$/),
      endsAt: expect.stringMatching(/Z$/),
    });
    expect(res.text).not.toMatch(/lat|lng|radius|secret|HACK26|DEMOSTATICTOKEN2/i);
    expect(res.headers.get('cache-control')).toContain('no-store');
  });

  it('accepts a room code in any case', async () => {
    expect((await resolve(CODE)).status).toBe(200);
    expect((await resolve({ kind: 'code', code: 'HACK26' })).status).toBe(200);
  });

  it('accepts the current rotating screen token', async () => {
    const token = rotatingToken(SECRET, qrWindow(Date.now()));
    expect((await resolve({ kind: 'link', slug: 'demo', token })).status).toBe(200);
  });

  it('answers 404 for a wrong code, a wrong token, an old token or an unknown slug (P11)', async () => {
    const old = rotatingToken(SECRET, qrWindow(Date.now()) - 2);
    for (const access of [
      { kind: 'code', code: 'ZZZZZZ' },
      { kind: 'link', slug: 'demo', token: 'WRONGSTATICTOKEN' },
      { kind: 'link', slug: 'demo', token: old },
      { kind: 'link', slug: 'nope', token: 'DEMOSTATICTOKEN2' },
      { kind: 'link', slug: 'other', token: 'DEMOSTATICTOKEN2' },
    ]) {
      const res = await resolve(access);
      expect(res.status).toBe(404);
      expect(res.body).toEqual({ error: { code: 'not_found', message: 'Not found.' } });
    }
  });

  it('refuses poster tokens when the room turned them off', async () => {
    seed(demoRoom({ allow_static_qr: false }));
    expect((await resolve(LINK)).status).toBe(404);
  });

  it('says 409 onboarding_incomplete before looking at the code', async () => {
    seed(demoRoom(), onboarded(USER_ID, { onboarding_step: 'photos' }));
    const res = await resolve({ kind: 'code', code: 'ZZZZZZ' });
    expect(res.status).toBe(409);
    expect(errorCode(res.body)).toBe('onboarding_incomplete');
  });

  it('answers 404 to a banned person', async () => {
    seed(demoRoom(), onboarded(USER_ID, { banned_at: new Date().toISOString() }));
    expect((await resolve(LINK)).status).toBe(404);
  });

  it('reports an ended room as ended, even before an admin says so', async () => {
    seed(demoRoom({ ends_at: new Date(Date.now() - 1000).toISOString() }));
    const res = await resolve(LINK);
    expect(res.status).toBe(200);
    expect((res.body as { status: string }).status).toBe('ended');
  });

  it('rejects a malformed body with 400 and no echo of the values', async () => {
    const res = await resolve({ kind: 'code', code: 'not a code!' });
    expect(res.status).toBe(400);
    expect(res.text).not.toContain('not a code!');
  });
});

describe('POST /api/rooms/{id}/join', () => {
  it('needs sign-in, before anything is looked up', async () => {
    expect((await join({ access: LINK, location: inside }, DEMO_ROOM_ID, null)).status).toBe(401);
    expect(db.writes).toHaveLength(0);
  });

  it('passes inside the room: a ticket, and a pass row with no coordinates', async () => {
    const before = Date.now();
    const res = await join({ access: LINK, location: inside });
    expect(res.status).toBe(200);
    const body = res.body as { ticket: string; expiresAt: string };
    expect(Object.keys(body).sort()).toEqual(['expiresAt', 'ticket']);
    expect(Date.parse(body.expiresAt) - before).toBeGreaterThan(590_000);
    expect(Date.parse(body.expiresAt) - before).toBeLessThanOrEqual(601_000);

    expect(db.writes).toEqual([
      {
        table: 'location_checks',
        kind: 'insert',
        values: {
          user_id: USER_ID,
          room_id: DEMO_ROOM_ID,
          purpose: 'join',
          result: 'pass',
          accuracy_bucket: 'under_20m',
        },
      },
    ]);
    const verified = await verifyJoinTicket(body.ticket, { userId: USER_ID, roomId: DEMO_ROOM_ID });
    expect(verified?.result).toBe('pass');
    expect(verified?.locationCheckId).toBe(db.rows('location_checks')[0]!.id);
  });

  it('passes with a room code too', async () => {
    expect((await join({ access: CODE, location: inside })).status).toBe(200);
  });

  it('answers 422 not_in_room 2 km away, and keeps only a fail', async () => {
    const res = await join({ access: LINK, location: away });
    expect(res.status).toBe(422);
    expect(errorCode(res.body)).toBe('not_in_room');
    expect(db.writes.map((w) => w.values.result)).toEqual(['fail']);
  });

  it('answers 422 location_inaccurate for a fix rougher than GEO_MAX_ACCURACY', async () => {
    const res = await join({ access: LINK, location: { ...DEMO_CENTER, accuracy: 900 } });
    expect(res.status).toBe(422);
    expect(errorCode(res.body)).toBe('location_inaccurate');
    expect(db.writes[0]?.values).toMatchObject({ result: 'fail', accuracy_bucket: 'over_500m' });
  });

  it('answers 404 when the code or token is for another room, or wrong (P11)', async () => {
    for (const access of [
      { kind: 'link', slug: 'other', token: 'OTHERSTATICTOKEN' },
      { kind: 'code', code: 'ABCD23' },
      { kind: 'link', slug: 'demo', token: 'WRONGSTATICTOKEN' },
      { kind: 'code', code: 'ZZZZZZ' },
    ]) {
      const res = await join({ access, location: inside });
      expect(res.status).toBe(404);
    }
    expect(db.writes).toHaveLength(0);
  });

  it('answers 404 for a room that does not exist, and for a malformed room ID', async () => {
    expect(
      (await join({ access: LINK, location: inside }, 'de000000-0000-4000-8000-0000000000ff'))
        .status,
    ).toBe(404);
    expect((await join({ access: LINK, location: inside }, 'not-a-uuid')).status).toBe(404);
  });

  it('answers 409 room_not_live for a paused, ended or not yet started room, after the access check', async () => {
    for (const room of [
      demoRoom({ status: 'paused' }),
      demoRoom({ status: 'ended' }),
      demoRoom({ ends_at: new Date(Date.now() - 1000).toISOString() }),
      demoRoom({ starts_at: new Date(Date.now() + 60_000).toISOString() }),
    ]) {
      seed(room);
      const res = await join({ access: LINK, location: inside });
      expect(res.status).toBe(409);
      expect(errorCode(res.body)).toBe('room_not_live');
      // A wrong token for a closed room is still just 404.
      const wrong = await join({
        access: { ...LINK, token: 'WRONGSTATICTOKEN' },
        location: inside,
      });
      expect(wrong.status).toBe(404);
    }
    expect(db.writes).toHaveLength(0);
  });

  it('answers 409 onboarding_incomplete', async () => {
    seed(demoRoom(), onboarded(USER_ID, { onboarding_step: 'profile' }));
    const res = await join({ access: LINK, location: inside });
    expect(res.status).toBe(409);
    expect(errorCode(res.body)).toBe('onboarding_incomplete');
  });

  it('lets an admin skip the check in a demo mode room, and stores the skip', async () => {
    seed(demoRoom({ demo_mode: true }), onboarded(USER_ID), { admins: [{ user_id: USER_ID }] });
    const res = await join({ access: LINK, location: away });
    expect(res.status).toBe(200);
    expect(db.writes[0]?.values).toMatchObject({ result: 'demo_skip', accuracy_bucket: null });
    const ticket = (res.body as { ticket: string }).ticket;
    expect(
      (await verifyJoinTicket(ticket, { userId: USER_ID, roomId: DEMO_ROOM_ID }))?.result,
    ).toBe('demo_skip');
  });

  it('still checks everyone else in a demo mode room', async () => {
    seed(demoRoom({ demo_mode: true }));
    expect((await join({ access: LINK, location: away })).status).toBe(422);
  });

  it('does not let an admin skip outside demo mode', async () => {
    seed(demoRoom(), onboarded(USER_ID), { admins: [{ user_id: USER_ID }] });
    expect((await join({ access: LINK, location: away })).status).toBe(422);
  });

  it('answers 429 with Retry-After once the join rate limit is used up', async () => {
    const statuses: number[] = [];
    for (let i = 0; i < 21; i += 1) {
      statuses.push((await join({ access: LINK, location: away })).status);
    }
    expect(statuses.slice(0, 20).every((s) => s === 422)).toBe(true);
    const res = await join({ access: LINK, location: inside });
    expect(res.status).toBe(429);
    expect(Number(res.headers.get('retry-after'))).toBeGreaterThan(0);
    // The limited request never reached the location check.
    expect(db.writes).toHaveLength(20);
  });

  it('rejects out-of-range coordinates with 400, never echoing them', async () => {
    const res = await join({
      access: LINK,
      location: { latitude: 91.123456, longitude: 0, accuracy: 5 },
    });
    expect(res.status).toBe(400);
    expect(res.text).not.toContain('91.123456');
  });
});

describe('POST /api/rooms/{id}/leave', () => {
  const card = (overrides: Record<string, unknown> = {}) => ({
    id: 'ca000000-0000-4000-8000-000000000001',
    room_id: DEMO_ROOM_ID,
    user_id: USER_ID,
    card_path: `${DEMO_ROOM_ID}/ca000000-0000-4000-8000-000000000001.jpg`,
    left_at: null,
    ...overrides,
  });

  it('ends my check-in, deletes my card photo and tells the room', async () => {
    seed(demoRoom(), onboarded(USER_ID), { checkins: [card()] });
    const res = await leave();
    expect(res.status).toBe(204);
    expect(db.rows('checkins')[0]!.left_at).toEqual(expect.any(String));
    expect(db.removed).toEqual([{ bucket: 'room-cards', paths: [card().card_path] }]);
    expect(fetchSpy).toHaveBeenCalledTimes(1);
    const [url, init] = fetchSpy.mock.calls[0]! as [URL, RequestInit];
    expect(String(url)).toBe('http://127.0.0.1:54421/realtime/v1/api/broadcast');
    expect(JSON.parse(String(init.body))).toEqual({
      messages: [
        {
          topic: `room:${DEMO_ROOM_ID}`,
          event: 'deck.changed',
          payload: { type: 'deck.changed', roomId: DEMO_ROOM_ID },
          private: true,
        },
      ],
    });
  });

  it("is a quiet 204 when I'm not checked in, and touches nobody else's check-in", async () => {
    const someoneElse = card({ user_id: '6a1e5c1e-7f0b-4c55-9a38-2d1f7c3b9eff' });
    seed(demoRoom(), onboarded(USER_ID), { checkins: [someoneElse] });
    expect((await leave()).status).toBe(204);
    expect(db.rows('checkins')[0]!.left_at).toBeNull();
    expect(db.removed).toHaveLength(0);
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it('answers 404 for a room that does not exist', async () => {
    expect((await leave('de000000-0000-4000-8000-0000000000ff')).status).toBe(404);
  });

  it('still answers 204 if the deck.changed broadcast fails', async () => {
    seed(demoRoom(), onboarded(USER_ID), { checkins: [card()] });
    fetchSpy.mockRejectedValue(new TypeError('fetch failed'));
    vi.spyOn(console, 'warn').mockImplementation(() => {});
    expect((await leave()).status).toBe(204);
  });
});

describe('GET /api/rooms/{id}', () => {
  const dbState = {
    room: {
      id: DEMO_ROOM_ID,
      slug: 'demo',
      name: 'Glow demo room (test data)',
      status: 'live',
      startsAt: '2026-10-23T06:00:00.000Z',
      endsAt: '2099-11-22T06:00:00.000Z',
    },
    checkin: {
      id: 'ca000000-0000-4000-8000-000000000001',
      roomId: DEMO_ROOM_ID,
      cardPath: `${DEMO_ROOM_ID}/ca000000-0000-4000-8000-000000000001.jpg`,
      tags: { topColor: 'green', extras: ['glasses'] },
      visible: true,
      joinedAt: '2026-10-24T20:00:00.000Z',
      expiresAt: '2026-10-24T23:00:00.000Z',
    },
    tapsLeftToday: 3,
    viewsLeftToday: 50,
  };

  it('returns the room, my check-in with a signed link to my own card, and what I have left', async () => {
    db.rpcHandler = () => ({ data: dbState, error: null });
    const res = await state();
    expect(res.status).toBe(200);
    expect(db.rpcCalls).toEqual([
      { name: 'get_room_state', args: { p_user_id: USER_ID, p_room_id: DEMO_ROOM_ID } },
    ]);
    const body = res.body as { checkin: { cardId: string; image: { url: string } } };
    expect(body).toMatchObject({ room: dbState.room, tapsLeftToday: 3, viewsLeftToday: 50 });
    expect(body.checkin.cardId).toBe(dbState.checkin.id);
    expect(body.checkin.image.url).toMatch(
      /^\/api\/cards\/ca000000-0000-4000-8000-000000000001\/image\?exp=\d+&sig=[A-Za-z0-9_-]{43}$/,
    );
    // The storage path and my user ID never reach the app.
    expect(res.text).not.toContain('cardPath');
    expect(res.text).not.toContain(USER_ID);
  });

  it('leaves the check-in out when I have none', async () => {
    db.rpcHandler = () => ({ data: { ...dbState, checkin: undefined }, error: null });
    const res = await state();
    expect(res.status).toBe(200);
    expect(res.body).not.toHaveProperty('checkin');
  });

  it('answers 404 when the room does not exist', async () => {
    db.rpcHandler = () => ({ data: null, error: { message: 'not_found' } });
    expect((await state()).status).toBe(404);
  });
});

describe('GET /.well-known/apple-app-site-association', () => {
  it('serves JSON with no app IDs until APPLE_APP_ID is set (B2-D3)', async () => {
    const res = await call(aasaRoute.GET, {
      path: '/.well-known/apple-app-site-association',
      method: 'GET',
      token: null,
    });
    expect(res.status).toBe(200);
    expect(res.headers.get('content-type')).toBe('application/json');
    expect(res.body).toEqual({ applinks: { details: [] } });
  });

  it('names the app and the /r/* paths when APPLE_APP_ID is set', async () => {
    process.env.APPLE_APP_ID = 'TEAM123456.com.davidxie.glow';
    const { resetEnvCacheForTests } = await import('@/env');
    resetEnvCacheForTests();
    const res = await call(aasaRoute.GET, {
      path: '/.well-known/apple-app-site-association',
      method: 'GET',
      token: null,
    });
    expect(res.body).toEqual({
      applinks: {
        details: [{ appIDs: ['TEAM123456.com.davidxie.glow'], components: [{ '/': '/r/*' }] }],
      },
    });
  });
});

describe('GET /r/{slug}', () => {
  it('is the same page for any slug and token, never showing the token or looking the room up', async () => {
    const a = await call(webRoute.GET, {
      path: '/r/demo?t=DEMOSTATICTOKEN2',
      method: 'GET',
      params: { slug: 'demo' },
      token: null,
    });
    const b = await call(webRoute.GET, {
      path: '/r/nope?t=AAAAAAAA',
      method: 'GET',
      params: { slug: 'nope' },
      token: null,
    });
    expect(a.status).toBe(200);
    expect(a.headers.get('content-type')).toContain('text/html');
    expect(a.headers.get('cache-control')).toContain('no-store');
    expect(a.headers.get('referrer-policy')).toBe('no-referrer');
    expect(a.headers.get('content-security-policy')).toContain("default-src 'none'");
    expect(a.text).toBe(b.text);
    expect(a.text).not.toContain('DEMOSTATICTOKEN2');
    expect(a.text).not.toContain('<script');
    expect(db.writes).toHaveLength(0);
  });

  it('links to TestFlight once TESTFLIGHT_URL is set, and only then', async () => {
    const page = () =>
      call(webRoute.GET, { path: '/r/demo', method: 'GET', params: { slug: 'demo' }, token: null });
    expect((await page()).text).not.toContain('testflight.apple.com');
    process.env.TESTFLIGHT_URL = 'https://testflight.apple.com/join/AbCdEfGh';
    const { resetEnvCacheForTests } = await import('@/env');
    resetEnvCacheForTests();
    const text = (await page()).text;
    expect(text).toContain('href="https://testflight.apple.com/join/AbCdEfGh"');
    expect(text).toContain('rel="noreferrer noopener"');
  });

  it('404s a malformed slug', async () => {
    const res = await call(webRoute.GET, {
      path: '/r/BAD_SLUG',
      method: 'GET',
      params: { slug: 'BAD_SLUG' },
      token: null,
    });
    expect(res.status).toBe(404);
  });
});
