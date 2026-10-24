import { NextRequest } from 'next/server';
import sharp from 'sharp';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { zMyCheckin } from '@/contracts';
import { signJoinTicketForTests } from '@/server/images/deps';
import { isValidCardImageLink } from '@/server/images/signed-link';
import { moderationFixtureJpeg, withJpegComment } from '@/server/moderation';
import { setRateLimitStoreForTests } from '@/server/ratelimit';
import { POST } from '../../app/api/rooms/[id]/checkin/route';
import { fakeAccessToken, mockVerify, USER_ID } from '../helpers/auth';
import { dbError, fakeSupabase, type FakeSupabase } from './fake-supabase';
import { hasJpegMetadata, syntheticPhoto } from './helpers';

vi.mock('@/server/auth/verify', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@/server/auth/verify')>();
  return { ...actual, verifyAccessToken: vi.fn() };
});

let db: FakeSupabase;
vi.mock('@/server/images/supabase', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@/server/images/supabase')>();
  return { ...actual, serviceClient: () => db.client };
});

const ROOM = 'de000000-0000-4000-8000-000000000001';
const OTHER_ROOM = 'de000000-0000-4000-8000-000000000002';
const TAGS = { topColor: 'green', hairLength: 'short', extras: ['glasses', 'glasses'] } as const;

async function checkIn(
  photo: Uint8Array,
  {
    room = ROOM,
    ticket = signJoinTicketForTests({ userId: USER_ID, roomId: room }),
    tags = TAGS as unknown,
  } = {},
) {
  const req = new NextRequest(`http://localhost/api/rooms/${room}/checkin`, {
    method: 'POST',
    headers: { authorization: `Bearer ${fakeAccessToken()}`, 'content-type': 'application/json' },
    body: JSON.stringify({ ticket, photo: Buffer.from(photo).toString('base64'), tags }),
  });
  const res = await POST(req, { params: Promise.resolve({ id: room }) });
  return { res, json: (await res.json()) as Record<string, unknown> };
}

function acceptCheckins() {
  db.onRpc('create_checkin', (args) => ({
    data: {
      checkin: {
        id: args.p_checkin_id,
        roomId: args.p_room_id,
        cardPath: args.p_card_path,
        tags: args.p_tags,
        visible: true,
        joinedAt: '2026-10-24T20:00:00.000Z',
        expiresAt: '2026-10-24T23:00:00.000Z',
      },
      replacedCardPaths: [`${ROOM}/11111111-0000-4000-8000-000000000001.jpg`],
    },
    error: null,
  }));
}

const cards = () => db.buckets.get('room-cards')!;

beforeEach(async () => {
  db = fakeSupabase();
  setRateLimitStoreForTests(undefined);
  await mockVerify();
});

describe('POST /api/rooms/{id}/checkin', () => {
  it('stores a clean photo and returns my card with a link only I can use', async () => {
    acceptCheckins();
    const old = `${ROOM}/11111111-0000-4000-8000-000000000001.jpg`;
    cards().set(old, new Uint8Array([1]));
    const photo = await sharp(await syntheticPhoto())
      .withExif({ IFD3: { GPSLatitudeRef: 'N', GPSLatitude: '37/1 48/1 10/1' } })
      .jpeg()
      .toBuffer();

    const { res, json } = await checkIn(photo);

    expect(res.status).toBe(201);
    expect(res.headers.get('cache-control')).toContain('no-store');
    const card = zMyCheckin.parse(json);
    expect(card.roomId).toBe(ROOM);
    expect(card.tags).toEqual({ topColor: 'green', hairLength: 'short', extras: ['glasses'] });
    // P1: my own card carries no user ID, not even mine.
    expect(JSON.stringify(json)).not.toContain(USER_ID);

    // The link is signed for me and this card.
    const url = new URL(card.image.url, 'http://localhost');
    expect(url.pathname).toBe(`/api/cards/${card.cardId}/image`);
    expect(
      isValidCardImageLink({
        cardId: card.cardId,
        viewerId: USER_ID,
        exp: Number(url.searchParams.get('exp')),
        sig: url.searchParams.get('sig')!,
      }),
    ).toBe(true);

    // Stored privately under {roomId}/{cardId}.jpg, re-encoded with no metadata.
    const path = `${ROOM}/${card.cardId}.jpg`;
    const stored = cards().get(path)!;
    expect(stored).toBeDefined();
    expect(hasJpegMetadata(stored)).toBe(false);
    expect(db.rpc).toHaveBeenCalledWith('create_checkin', {
      p_user_id: USER_ID,
      p_room_id: ROOM,
      p_checkin_id: card.cardId,
      p_card_path: path,
      p_tags: { topColor: 'green', hairLength: 'short', extras: ['glasses'] },
    });
    // The replaced check-in's photo is gone.
    expect(cards().has(old)).toBe(false);
  });

  it('a face-visible photo is rejected with face_visible, and nothing is stored', async () => {
    acceptCheckins();
    const { res, json } = await checkIn(await moderationFixtureJpeg(['face_visible']));
    expect(res.status).toBe(422);
    expect(json).toEqual({
      error: { code: 'photo_rejected', message: expect.any(String), reason: 'face_visible' },
    });
    expect(cards().size).toBe(0);
    expect(db.rpc).not.toHaveBeenCalled();
  });

  it('a nude photo is rejected with nudity, and nothing is stored', async () => {
    acceptCheckins();
    const { res, json } = await checkIn(await moderationFixtureJpeg(['nudity']));
    expect(res.status).toBe(422);
    expect((json.error as { reason: string }).reason).toBe('nudity');
    expect(cards().size).toBe(0);
  });

  it.each(['no_outfit', 'no_person', 'possibly_minor'] as const)(
    'passes %s through as the reason',
    async (flag) => {
      acceptCheckins();
      const { res, json } = await checkIn(await moderationFixtureJpeg([flag]));
      expect(res.status).toBe(422);
      expect((json.error as { reason: string }).reason).toBe(flag);
    },
  );

  it('fails closed when moderation is down: 503, nothing stored', async () => {
    acceptCheckins();
    const { res, json } = await checkIn(await moderationFixtureJpeg(['error']));
    expect(res.status).toBe(503);
    expect((json.error as { code: string }).code).toBe('unavailable');
    expect(res.headers.get('retry-after')).toBe('2');
    expect(cards().size).toBe(0);
  });

  it('strips the moderation fixture marker (a JPEG comment) before storing', async () => {
    acceptCheckins();
    const photo = withJpegComment(await syntheticPhoto(), 'glow-moderation-fixture:');
    const { res, json } = await checkIn(photo);
    expect(res.status).toBe(201);
    const stored = cards().get(`${ROOM}/${json.cardId as string}.jpg`)!;
    expect(Buffer.from(stored).includes(Buffer.from('glow-moderation-fixture'))).toBe(false);
  });

  it.each([
    [
      'someone else',
      () =>
        signJoinTicketForTests({ userId: '00000000-0000-4000-8000-0000000000aa', roomId: ROOM }),
    ],
    ['another room', () => signJoinTicketForTests({ userId: USER_ID, roomId: OTHER_ROOM })],
    [
      'expired',
      () =>
        signJoinTicketForTests({
          userId: USER_ID,
          roomId: ROOM,
          now: new Date(Date.now() - 11 * 60_000),
        }),
    ],
    ['edited', () => `${signJoinTicketForTests({ userId: USER_ID, roomId: ROOM })}x`],
    ['garbage', () => 'not-a-ticket'],
  ])('refuses a join ticket for %s with 422 join_ticket_invalid', async (_name, ticket) => {
    acceptCheckins();
    const { res, json } = await checkIn(await syntheticPhoto(), { ticket: ticket() });
    expect(res.status).toBe(422);
    expect((json.error as { code: string }).code).toBe('join_ticket_invalid');
    expect(cards().size).toBe(0);
  });

  it.each([
    ['not_found', 404, 'not_found'],
    ['room_not_live', 409, 'room_not_live'],
    ['onboarding_incomplete', 409, 'onboarding_incomplete'],
    ['location_required', 422, 'location_required'],
    ['invalid_input', 400, 'bad_request'],
  ])(
    'maps %s from create_checkin and deletes the photo it just stored',
    async (code, status, apiCode) => {
      db.onRpc('create_checkin', () => dbError(code));
      const { res, json } = await checkIn(await syntheticPhoto());
      expect(res.status).toBe(status);
      expect((json.error as { code: string }).code).toBe(apiCode);
      expect(cards().size).toBe(0);
    },
  );

  it('refuses a body that breaks the contract with 400 and never echoes it back', async () => {
    acceptCheckins();
    const { res, json } = await checkIn(await syntheticPhoto(), {
      tags: { topColor: 'teal', extras: [] },
    });
    expect(res.status).toBe(400);
    expect(JSON.stringify(json)).not.toContain('teal');
  });

  it('refuses a PNG as unreadable (moderation reads JPEGs only), and stores nothing', async () => {
    acceptCheckins();
    const png = await sharp({ create: { width: 20, height: 20, channels: 3, background: '#000' } })
      .png()
      .toBuffer();
    const { res, json } = await checkIn(png);
    expect(res.status).toBe(422);
    expect(json.error).toMatchObject({ code: 'photo_rejected', reason: 'unreadable' });
    expect(cards().size).toBe(0);
  });

  it('rate limits uploads per person', async () => {
    acceptCheckins();
    const photo = await syntheticPhoto(120, 160);
    const statuses: number[] = [];
    for (let i = 0; i < 11; i += 1) statuses.push((await checkIn(photo)).res.status);
    expect(statuses.slice(0, 10).every((s) => s === 201)).toBe(true);
    expect(statuses[10]).toBe(429);
  });

  it('needs sign-in', async () => {
    const req = new NextRequest(`http://localhost/api/rooms/${ROOM}/checkin`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: '{}',
    });
    const res = await POST(req, { params: Promise.resolve({ id: ROOM }) });
    expect(res.status).toBe(401);
  });
});
