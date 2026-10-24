/**
 * Owner: B4. Unit tests for the deck route, with the database mocked. The deck rules
 * themselves are tested against a real database in deck-rules.integration.test.ts.
 */
import { createHmac } from 'node:crypto';
import { NextRequest } from 'next/server';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { CARD_URL_TTL_SECONDS, CARD_VIEWS_PER_ROOM_PER_DAY, zDeck } from '@/contracts';
import { HttpError } from '@/server/http';
import { LOCAL_ENV } from '../helpers/env';
import { fakeAccessToken, mockVerify, USER_ID } from '../helpers/auth';

vi.mock('@/server/auth/verify', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@/server/auth/verify')>();
  return { ...actual, verifyAccessToken: vi.fn() };
});
vi.mock('@/server/deck/db', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@/server/deck/db')>();
  return { ...actual, rpc: vi.fn() };
});

const { rpc } = await import('@/server/deck/db');
const { loadDeck, toDeck, validateFilters } = await import('@/server/deck/get-deck');
const { POST } = await import('../../app/api/rooms/[id]/deck/route');

const ROOM = 'de000000-0000-4000-8000-000000000001';
const CARD_1 = 'bbbbbbbb-0000-4000-8000-000000000001';
const CARD_2 = 'bbbbbbbb-0000-4000-8000-000000000002';
const OTHER_USER = '7e570000-0000-4000-8000-000000000002';

const dbDeck = (overrides: Record<string, unknown> = {}) => ({
  cards: [
    {
      id: CARD_1,
      cardPath: `${ROOM}/${CARD_1}.jpg`,
      tags: { topColor: 'green', hairLength: 'short', hairColor: 'brown', extras: ['glasses'] },
      tappedByMe: false,
      // Never in a real get_deck result; here to prove nothing unexpected passes through.
      userId: OTHER_USER,
    },
    {
      id: CARD_2,
      cardPath: `${ROOM}/${CARD_2}.jpg`,
      tags: { topColor: 'blue', extras: [] },
      tappedByMe: true,
    },
  ],
  viewsLeftToday: 48,
  hasMore: true,
  nextOffset: 10,
  ...overrides,
});

function call(body: unknown, { token = fakeAccessToken(), room = ROOM } = {}) {
  const req = new NextRequest(`http://localhost/api/rooms/${room}/deck`, {
    method: 'POST',
    headers: {
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      'content-type': 'application/json',
    },
    body: JSON.stringify(body),
  });
  return POST(req, { params: Promise.resolve({ id: room }) });
}

beforeEach(async () => {
  await mockVerify();
});

describe('validateFilters', () => {
  it('keeps listed values and drops empty lists, which mean any', () => {
    expect(validateFilters({ topColor: ['green', 'blue'], extras: [], gender: ['woman'] })).toEqual(
      {
        topColor: ['green', 'blue'],
        gender: ['woman'],
      },
    );
    expect(validateFilters(undefined)).toEqual({});
  });

  it('refuses a repeated value (uniqueItems), naming the field but not the value', () => {
    try {
      validateFilters({ topColor: ['green', 'green'], hairColor: ['red'] });
      expect.unreachable();
    } catch (error) {
      expect(error).toBeInstanceOf(HttpError);
      const e = error as HttpError;
      expect(e.status).toBe(400);
      expect(e.issues).toEqual([
        {
          path: 'body.filters.topColor',
          code: 'not_unique',
          message: 'Each value may appear once.',
        },
      ]);
      expect(JSON.stringify(e.issues)).not.toContain('green');
    }
  });
});

describe('toDeck', () => {
  it('sends only contract fields: no card path, no user ID', () => {
    const deck = toDeck(dbDeck() as never, USER_ID);
    const text = JSON.stringify(deck);
    expect(text).not.toContain('cardPath');
    expect(text).not.toContain(`${ROOM}/`);
    expect(text).not.toContain(OTHER_USER);
    expect(text).not.toContain(USER_ID);
    expect(Object.keys(deck.cards[0]!).sort()).toEqual(['id', 'image', 'tags', 'tappedByMe']);
    expect(zDeck.parse(deck)).toEqual(deck);
  });

  it('signs a 60-second image link bound to this viewer, in the format B3 checks', () => {
    const now = Date.parse('2026-10-24T20:15:00.250Z');
    const card = toDeck(dbDeck() as never, USER_ID, now).cards[0]!;
    const exp = Math.floor(now / 1000) + CARD_URL_TTL_SECONDS;
    const sig = createHmac('sha256', LOCAL_ENV.CARD_URL_SECRET)
      .update(`${CARD_1}.${USER_ID}.${exp}`)
      .digest('base64url');
    expect(card.image).toEqual({
      url: `/api/cards/${CARD_1}/image?exp=${exp}&sig=${sig}`,
      expiresAt: new Date(exp * 1000).toISOString(),
    });
    expect(sig).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(Date.parse(card.image.expiresAt) - now).toBeLessThanOrEqual(CARD_URL_TTL_SECONDS * 1000);
    // Another viewer's link for the same card is different, so links can't be shared.
    expect(toDeck(dbDeck() as never, OTHER_USER, now).cards[0]!.image.url).not.toBe(card.image.url);
  });

  it('drops missing hair tags instead of sending nulls', () => {
    const deck = toDeck(
      dbDeck({
        cards: [
          {
            id: CARD_1,
            tags: { topColor: 'red', hairLength: null, hairColor: null, extras: null },
            tappedByMe: false,
          },
        ],
      }) as never,
      USER_ID,
    );
    expect(deck.cards[0]!.tags).toEqual({ topColor: 'red', extras: [] });
  });

  it('has nextOffset only with hasMore, and emptyReason only on an empty page', () => {
    expect(
      toDeck(dbDeck({ hasMore: false, nextOffset: null }) as never, USER_ID),
    ).not.toHaveProperty('nextOffset');
    expect(toDeck(dbDeck({ emptyReason: 'no_match' }) as never, USER_ID)).not.toHaveProperty(
      'emptyReason',
    );
    const empty = toDeck(
      { cards: [], viewsLeftToday: 0, hasMore: false, emptyReason: 'view_limit_reached' },
      USER_ID,
    );
    expect(empty).toEqual({
      cards: [],
      viewsLeftToday: 0,
      hasMore: false,
      emptyReason: 'view_limit_reached',
    });
  });
});

describe('loadDeck', () => {
  it('calls get_deck once with the viewer, room, filters and offset', async () => {
    vi.mocked(rpc).mockResolvedValue(dbDeck() as never);
    await loadDeck(USER_ID, ROOM, { filters: { topColor: ['green'], extras: [] }, offset: 10 });
    expect(rpc).toHaveBeenCalledExactlyOnceWith('get_deck', {
      p_viewer_id: USER_ID,
      p_room_id: ROOM,
      p_filters: { topColor: ['green'] },
      p_offset: 10,
    });
  });

  it('clamps an offset past the most cards a day can show (it would overflow Postgres)', async () => {
    vi.mocked(rpc).mockResolvedValue({ cards: [], viewsLeftToday: 3, hasMore: false } as never);
    await loadDeck(USER_ID, ROOM, { offset: 2 ** 40 });
    expect(vi.mocked(rpc).mock.calls[0]![1]).toMatchObject({
      p_offset: CARD_VIEWS_PER_ROOM_PER_DAY,
    });
  });
});

describe('POST /api/rooms/{id}/deck', () => {
  it('answers 200 with the deck', async () => {
    vi.mocked(rpc).mockResolvedValue(dbDeck() as never);
    const res = await call({ filters: { gender: ['man'] } });
    expect(res.status).toBe(200);
    expect(res.headers.get('cache-control')).toContain('no-store');
    const body = (await res.json()) as {
      cards: unknown[];
      viewsLeftToday: number;
      nextOffset: number;
    };
    expect(body.cards).toHaveLength(2);
    expect(body).toMatchObject({ viewsLeftToday: 48, hasMore: true, nextOffset: 10 });
  });

  it('accepts an empty body as page one with no filters', async () => {
    vi.mocked(rpc).mockResolvedValue(dbDeck({ hasMore: false, nextOffset: null }) as never);
    const res = await call({});
    expect(res.status).toBe(200);
    expect(vi.mocked(rpc).mock.calls[0]![1]).toMatchObject({ p_filters: {}, p_offset: 0 });
  });

  it('answers 404 when get_deck says not_found (never checked in here), like a missing room', async () => {
    vi.mocked(rpc).mockRejectedValue(new HttpError(404, 'not_found', 'Not found.'));
    const res = await call({});
    expect(res.status).toBe(404);
    expect(await res.json()).toEqual({ error: { code: 'not_found', message: 'Not found.' } });
  });

  it('answers 400 for a filter value outside the contract, before touching the database', async () => {
    const res = await call({ filters: { topColor: ['plaid'] } });
    expect(res.status).toBe(400);
    expect(rpc).not.toHaveBeenCalled();
  });

  it('answers 400 for repeated filter values, before touching the database', async () => {
    const res = await call({ filters: { extras: ['hat', 'hat'] } });
    expect(res.status).toBe(400);
    expect(rpc).not.toHaveBeenCalled();
  });

  it('answers 401 without a token and never reads the deck', async () => {
    const res = await call({}, { token: '' });
    expect(res.status).toBe(401);
    expect(rpc).not.toHaveBeenCalled();
  });

  it('answers 404 for a room ID that is not a UUID', async () => {
    const res = await call({}, { room: 'not-a-room' });
    expect(res.status).toBe(404);
    expect(rpc).not.toHaveBeenCalled();
  });
});
