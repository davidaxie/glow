import { NextRequest } from 'next/server';
import sharp from 'sharp';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { CARD_URL_TTL_SECONDS } from '@/contracts';
import { cardImageLink } from '@/server/images/signed-link';
import { GET as getCardImage } from '../../app/api/cards/[cardId]/image/route';
import { GET as getMatchPhoto } from '../../app/api/matches/[id]/photos/[n]/route';
import { fakeAccessToken, mockVerify, USER_ID } from '../helpers/auth';
import { dbError, fakeSupabase, type FakeSupabase } from './fake-supabase';
import { hasJpegMetadata, rawPixels, syntheticPhoto } from './helpers';

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
const CARD = 'aaaaaaaa-0000-4000-8000-000000000001';
const OTHER_VIEWER = 'cccccccc-0000-4000-8000-000000000003';
const MATCH = 'dddddddd-0000-4000-8000-000000000004';
const CARD_PATH = `${ROOM}/${CARD}.jpg`;
const PHOTO_PATH = `eeeeeeee-0000-4000-8000-000000000005/ffffffff-0000-4000-8000-000000000006.jpg`;
const VIEWER_CODE = 'K7MPQ2RX';

let photo: Buffer;
let visibleTo: Set<string>;

async function fetchCard(url: string, cardId = CARD) {
  const req = new NextRequest(`http://localhost${url}`, {
    headers: { authorization: `Bearer ${fakeAccessToken()}` },
  });
  return getCardImage(req, { params: Promise.resolve({ cardId }) });
}

async function fetchMatchPhoto(match: string, n: string) {
  const req = new NextRequest(`http://localhost/api/matches/${match}/photos/${n}`, {
    headers: { authorization: `Bearer ${fakeAccessToken()}` },
  });
  return getMatchPhoto(req, { params: Promise.resolve({ id: match, n }) });
}

async function expectNotFound(res: Response) {
  expect(res.status).toBe(404);
  expect(res.headers.get('content-type')).toContain('application/json');
  expect(await res.json()).toEqual({ error: { code: 'not_found', message: 'Not found.' } });
}

beforeEach(async () => {
  db = fakeSupabase();
  await mockVerify();
  photo = await syntheticPhoto(300, 400);
  visibleTo = new Set([USER_ID]);
  db.buckets.get('room-cards')!.set(CARD_PATH, photo);
  db.buckets.get('profile-photos')!.set(PHOTO_PATH, photo);
  db.tables.checkins![CARD] = { card_path: CARD_PATH };
  db.tables.profiles![USER_ID] = { viewer_code: VIEWER_CODE };
  db.onRpc('card_visible_to', (args) => ({
    data: visibleTo.has(args.p_viewer_id as string) && args.p_checkin_id === CARD,
    error: null,
  }));
  db.onRpc('match_photo_path', (args) =>
    args.p_match_id === MATCH && args.p_n === 0
      ? { data: PHOTO_PATH, error: null }
      : dbError('not_found'),
  );
});

describe('GET /api/cards/{cardId}/image', () => {
  it('serves the watermarked photo, never cached, with no metadata', async () => {
    const res = await fetchCard(cardImageLink(CARD, USER_ID).url);
    expect(res.status).toBe(200);
    expect(res.headers.get('content-type')).toBe('image/jpeg');
    expect(res.headers.get('cache-control')).toBe('no-store');
    expect(res.headers.get('pragma')).toBe('no-cache');
    const body = new Uint8Array(await res.arrayBuffer());
    expect(hasJpegMetadata(body)).toBe(false);
    const meta = await sharp(body).metadata();
    expect([meta.width, meta.height]).toEqual([300, 400]);

    // The served pixels differ from what's stored: that's the watermark.
    const before = await rawPixels(photo);
    const after = await rawPixels(body);
    let changed = 0;
    for (let i = 0; i < after.data.length; i += 3) {
      if (Math.abs(after.data[i]! - before.data[i]!) >= 6) changed += 1;
    }
    expect(changed / (after.width * after.height)).toBeGreaterThan(0.02);
    expect(db.rpc).toHaveBeenCalledWith('card_visible_to', {
      p_viewer_id: USER_ID,
      p_checkin_id: CARD,
    });
  });

  it('404s an expired link without asking the database', async () => {
    const old = cardImageLink(CARD, USER_ID, Date.now() - (CARD_URL_TTL_SECONDS + 1) * 1000);
    await expectNotFound(await fetchCard(old.url));
    expect(db.rpc).not.toHaveBeenCalled();
  });

  it('404s a link made for someone else (reused by another viewer)', async () => {
    visibleTo.add(OTHER_VIEWER);
    const theirs = cardImageLink(CARD, OTHER_VIEWER);
    await expectNotFound(await fetchCard(theirs.url));
    expect(db.rpc).not.toHaveBeenCalled();
  });

  it('404s a valid link when the card is no longer visible to the viewer', async () => {
    visibleTo.clear();
    await expectNotFound(await fetchCard(cardImageLink(CARD, USER_ID).url));
  });

  it('404s a link for one card used on another card', async () => {
    const other = 'aaaaaaaa-0000-4000-8000-000000000009';
    const link = cardImageLink(CARD, USER_ID).url.replace(CARD, other);
    await expectNotFound(await fetchCard(link, other));
  });

  it('404s when the photo is already gone from storage', async () => {
    db.buckets.get('room-cards')!.clear();
    await expectNotFound(await fetchCard(cardImageLink(CARD, USER_ID).url));
  });

  it('404s a malformed card ID, and 400s a malformed signature', async () => {
    const link = new URL(cardImageLink(CARD, USER_ID).url, 'http://localhost');
    await expectNotFound(
      await fetchCard(link.pathname.replace(CARD, 'nope') + link.search, 'nope'),
    );
    const res = await fetchCard(`/api/cards/${CARD}/image?exp=1&sig=short`);
    expect(res.status).toBe(400);
  });

  it('answers 503, not an image, when the database is down', async () => {
    db.onRpc('card_visible_to', () => ({ data: null, error: { code: 'XX000', message: 'down' } }));
    const res = await fetchCard(cardImageLink(CARD, USER_ID).url);
    expect(res.status).toBe(503);
  });

  it('needs sign-in', async () => {
    const req = new NextRequest(`http://localhost${cardImageLink(CARD, USER_ID).url}`);
    const res = await getCardImage(req, { params: Promise.resolve({ cardId: CARD }) });
    expect(res.status).toBe(401);
  });
});

describe('GET /api/matches/{id}/photos/{n}', () => {
  it('serves the other person’s photo for an active match, watermarked and never cached', async () => {
    const res = await fetchMatchPhoto(MATCH, '0');
    expect(res.status).toBe(200);
    expect(res.headers.get('content-type')).toBe('image/jpeg');
    expect(res.headers.get('cache-control')).toBe('no-store');
    const body = new Uint8Array(await res.arrayBuffer());
    expect(hasJpegMetadata(body)).toBe(false);
    expect(Buffer.from(body).equals(photo)).toBe(false);
    expect(db.rpc).toHaveBeenCalledWith('match_photo_path', {
      p_viewer_id: USER_ID,
      p_match_id: MATCH,
      p_n: 0,
    });
  });

  it('404s ended or unknown matches and photos out of range (P11)', async () => {
    await expectNotFound(await fetchMatchPhoto(MATCH, '1'));
    await expectNotFound(await fetchMatchPhoto('dddddddd-0000-4000-8000-000000000099', '0'));
    await expectNotFound(await fetchMatchPhoto(MATCH, '3'));
    await expectNotFound(await fetchMatchPhoto(MATCH, '-1'));
    await expectNotFound(await fetchMatchPhoto('not-a-uuid', '0'));
  });

  it('404s when the photo object is gone', async () => {
    db.buckets.get('profile-photos')!.clear();
    await expectNotFound(await fetchMatchPhoto(MATCH, '0'));
  });
});
