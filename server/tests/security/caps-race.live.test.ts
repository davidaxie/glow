/**
 * The brief's "send parallel requests to get past the tap and view caps": everything at once,
 * through the real routes, against a live stack. The database holds the caps (record_tap and
 * get_deck lock per viewer), so parallel requests must never get more than one at a time would.
 */
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { CARD_VIEWS_PER_ROOM_PER_DAY, DECK_PAGE_SIZE, TAPS_PER_ROOM_PER_DAY } from '@/contracts/constants';
import { resetEnvCacheForTests } from '@/env';
import { call } from './helpers/api';
import { LIVE, type Live } from './helpers/live';
import { World, type Card, type Person } from './helpers/world';

const live = LIVE as Live;
let world: World;

beforeAll(() => {
  if (LIVE) world = new World(live);
});
beforeEach(() => {
  if (!LIVE) return;
  process.env.SUPABASE_URL = live.url;
  process.env.SUPABASE_ANON_KEY = live.anonKey;
  process.env.SUPABASE_SERVICE_ROLE_KEY = live.serviceKey;
  resetEnvCacheForTests();
});
afterAll(async () => {
  if (LIVE) await world.cleanup();
});

async function crowd(roomId: string, n: number): Promise<{ people: Person[]; cards: Card[] }> {
  const people: Person[] = [];
  const cards: Card[] = [];
  for (let i = 0; i < n; i += 10) {
    const batch = await Promise.all(
      Array.from({ length: Math.min(10, n - i) }, () => world.person('woman', ['man'])),
    );
    people.push(...batch);
    cards.push(...(await Promise.all(batch.map((p) => world.checkIn(p, roomId)))));
  }
  return { people, cards };
}

describe.skipIf(!LIVE)('caps hold under parallel requests (live)', () => {
  it(`${TAPS_PER_ROOM_PER_DAY} taps a day, however many are sent at once`, async () => {
    const roomId = await world.room();
    const viewer = await world.person('man', ['woman']);
    await world.checkIn(viewer, roomId);
    const { cards } = await crowd(roomId, TAPS_PER_ROOM_PER_DAY * 3);
    await call('getDeck', { token: viewer.token, params: { id: roomId }, body: {} });

    const replies = await Promise.all(
      cards.map((card) =>
        call('createTap', { token: viewer.token, params: { id: roomId }, body: { cardId: card.id } }),
      ),
    );
    const statuses = replies.map((r) => r.status);
    expect(statuses.filter((s) => s === 200)).toHaveLength(TAPS_PER_ROOM_PER_DAY);
    expect(statuses.filter((s) => s === 409)).toHaveLength(cards.length - TAPS_PER_ROOM_PER_DAY);
    const used = await world.db
      .from('taps')
      .select('id', { count: 'exact', head: true })
      .eq('from_user', viewer.id);
    expect(used.count).toBe(TAPS_PER_ROOM_PER_DAY);
  }, 120_000);

  it(`${CARD_VIEWS_PER_ROOM_PER_DAY} different cards a day, however many pages are asked for at once`, async () => {
    const roomId = await world.room();
    const viewer = await world.person('man', ['woman']);
    await world.checkIn(viewer, roomId);
    const extra = 6;
    const { cards } = await crowd(roomId, CARD_VIEWS_PER_ROOM_PER_DAY + extra);
    const pages = Math.ceil(cards.length / DECK_PAGE_SIZE) + 1;

    const replies = await Promise.all(
      Array.from({ length: pages * 2 }, (_, i) =>
        call('getDeck', {
          token: viewer.token,
          params: { id: roomId },
          body: { offset: (i % pages) * DECK_PAGE_SIZE },
        }),
      ),
    );
    const seen = new Set<string>();
    for (const reply of replies) {
      expect(reply.status).toBe(200);
      for (const c of (reply.json as { cards: { id: string }[] }).cards) seen.add(c.id);
    }
    expect(seen.size).toBeLessThanOrEqual(CARD_VIEWS_PER_ROOM_PER_DAY);
    const views = await world.db
      .from('card_views')
      .select('checkin_id', { count: 'exact', head: true })
      .eq('viewer_id', viewer.id)
      .eq('room_id', roomId);
    expect(views.count).toBeLessThanOrEqual(CARD_VIEWS_PER_ROOM_PER_DAY);
  }, 180_000);
});
