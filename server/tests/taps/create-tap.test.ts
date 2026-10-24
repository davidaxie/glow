/**
 * Owner: B4. Unit tests for the tap route, with the database and notify mocked. Real taps,
 * caps and simultaneous mutual taps are in taps.integration.test.ts.
 */
import { NextRequest } from 'next/server';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { zTapResult } from '@/contracts';
import { HttpError, rateLimited } from '@/server/http';
import { fakeAccessToken, mockVerify, USER_ID } from '../helpers/auth';

vi.mock('@/server/auth/verify', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@/server/auth/verify')>();
  return { ...actual, verifyAccessToken: vi.fn() };
});
vi.mock('@/server/deck/db', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@/server/deck/db')>();
  return { ...actual, rpc: vi.fn(), serviceDb: vi.fn() };
});
vi.mock('@/server/deck/dependencies', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@/server/deck/dependencies')>();
  return { ...actual, notify: vi.fn(async () => {}), rateLimit: vi.fn(async () => {}) };
});

const { rpc, serviceDb } = await import('@/server/deck/db');
const { notify, rateLimit } = await import('@/server/deck/dependencies');
const { POST } = await import('../../app/api/rooms/[id]/taps/route');

const ROOM = 'de000000-0000-4000-8000-000000000001';
const CARD = 'bbbbbbbb-0000-4000-8000-000000000001';
const MATCH = '64bfd966-bf7f-426a-b7aa-f0dc371bae1a';
const OTHER_USER = '7e570000-0000-4000-8000-000000000002';

function call(body: unknown, { token = fakeAccessToken() } = {}) {
  const req = new NextRequest(`http://localhost/api/rooms/${ROOM}/taps`, {
    method: 'POST',
    headers: {
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      'content-type': 'application/json',
    },
    body: JSON.stringify(body),
  });
  return POST(req, { params: Promise.resolve({ id: ROOM }) });
}

/** A fake `from('matches').select().eq().maybeSingle()` chain answering with the pair. */
function mockMatchRow(row: { user_a: string; user_b: string } | null) {
  const chain = {
    select: () => chain,
    eq: () => chain,
    maybeSingle: async () => ({ data: row, error: null }),
  };
  vi.mocked(serviceDb).mockReturnValue({ from: () => chain } as never);
}

beforeEach(async () => {
  await mockVerify();
});

describe('POST /api/rooms/{id}/taps', () => {
  it('a one-sided tap answers sent and taps left, and tells nobody (P5)', async () => {
    vi.mocked(rpc).mockResolvedValue({ result: 'sent', tapsLeftToday: 2 } as never);
    const res = await call({ cardId: CARD });
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body).toEqual({ result: 'sent', tapsLeftToday: 2 });
    expect(rpc).toHaveBeenCalledExactlyOnceWith('record_tap', {
      p_viewer_id: USER_ID,
      p_room_id: ROOM,
      p_checkin_id: CARD,
    });
    expect(notify).not.toHaveBeenCalled();
    expect(serviceDb).not.toHaveBeenCalled();
  });

  it('a sent reply has exactly two fields, even if the database said more', async () => {
    vi.mocked(rpc).mockResolvedValue({
      result: 'sent',
      tapsLeftToday: 1,
      matchId: MATCH,
      theyTappedMe: false,
    } as never);
    const res = await call({ cardId: CARD });
    expect(Object.keys(await res.json()).sort()).toEqual(['result', 'tapsLeftToday']);
  });

  it('a mutual tap answers mutual with the match ID, and sends match.created to both people', async () => {
    vi.mocked(rpc).mockResolvedValue({
      result: 'mutual',
      tapsLeftToday: 1,
      matchId: MATCH,
    } as never);
    mockMatchRow({ user_a: USER_ID, user_b: OTHER_USER });
    const res = await call({ cardId: CARD });
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body).toEqual({ result: 'mutual', tapsLeftToday: 1, matchId: MATCH });
    expect(zTapResult.parse(body)).toEqual(body);
    expect(JSON.stringify(body)).not.toContain(OTHER_USER);
    expect(notify).toHaveBeenCalledExactlyOnceWith([USER_ID, OTHER_USER], {
      type: 'match.created',
      matchId: MATCH,
    });
  });

  it('a failed notification never fails the tap: the match exists either way', async () => {
    vi.mocked(rpc).mockResolvedValue({
      result: 'mutual',
      tapsLeftToday: 0,
      matchId: MATCH,
    } as never);
    mockMatchRow({ user_a: USER_ID, user_b: OTHER_USER });
    vi.mocked(notify).mockRejectedValue(new Error('push down'));
    const res = await call({ cardId: CARD });
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ result: 'mutual', tapsLeftToday: 0, matchId: MATCH });
  });

  it('a card not in my deck right now is 404 (P11)', async () => {
    vi.mocked(rpc).mockRejectedValue(new HttpError(404, 'not_found', 'Not found.'));
    const res = await call({ cardId: CARD });
    expect(res.status).toBe(404);
    expect(await res.json()).toEqual({ error: { code: 'not_found', message: 'Not found.' } });
  });

  it('no taps left today is 409 tap_limit_reached', async () => {
    vi.mocked(rpc).mockRejectedValue(
      new HttpError(409, 'tap_limit_reached', 'No taps left today in this room.'),
    );
    const res = await call({ cardId: CARD });
    expect(res.status).toBe(409);
    expect(((await res.json()) as { error: { code: string } }).error.code).toBe(
      'tap_limit_reached',
    );
  });

  it('a card ID that is not a UUID is 400, before touching the database', async () => {
    const res = await call({ cardId: 'not-a-card' });
    expect(res.status).toBe(400);
    expect(rpc).not.toHaveBeenCalled();
  });

  it('counts against the taps rate limit first, and a 429 records nothing', async () => {
    vi.mocked(rateLimit).mockRejectedValue(rateLimited(30));
    const res = await call({ cardId: CARD });
    expect(res.status).toBe(429);
    expect(res.headers.get('retry-after')).toBe('30');
    expect(rateLimit).toHaveBeenCalledWith(USER_ID, 'taps');
    expect(rpc).not.toHaveBeenCalled();
  });

  it('401 without a token, and nothing is recorded', async () => {
    const res = await call({ cardId: CARD }, { token: '' });
    expect(res.status).toBe(401);
    expect(rpc).not.toHaveBeenCalled();
  });
});
