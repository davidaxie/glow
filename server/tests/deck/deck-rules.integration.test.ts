/**
 * Owner: B4. Every deck rule in docs/SPEC.md ("Who appears in your deck"), through the real
 * POST /api/rooms/{id}/deck route, real sign-in and the real get_deck. See harness.ts for
 * when these run.
 *
 * - Both people have an active check-in in this room: not expired, not left, not paused.
 * - Their gender is in your show me, and yours is in theirs.
 * - Neither has blocked the other.
 * - You don't already have an active match.
 * - Their card fits the filters you picked.
 * - You haven't used up today's card views in this room.
 * - The order is shuffled from your ID, the room and the date, so refreshing gives the same
 *   order and nobody can work out who arrived when.
 * Plus P1 (no user ID, name or face in any deck response) and P11 (404, never 403).
 */
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { CARD_VIEWS_PER_ROOM_PER_DAY, DECK_PAGE_SIZE, zDeck, type Deck } from '@/contracts';
import { IT, useRealSupabase, World, type Person } from './harness';

vi.mock('@/server/deck/dependencies', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@/server/deck/dependencies')>();
  return { ...actual, notify: vi.fn(async () => {}) };
});

const sorted = (ids: readonly string[]) => [...ids].sort();

async function deckBody(res: Response): Promise<Deck> {
  expect(res.status).toBe(200);
  const body = (await res.json()) as Deck;
  expect(zDeck.parse(body)).toEqual(body);
  return body;
}

describe.runIf(IT)('deck rules (integration)', { timeout: 120_000 }, () => {
  // Made in beforeAll: describe bodies also run when the suite is skipped.
  let world: World;
  const allPeople: Person[] = [];
  const person = async (...args: Parameters<World['person']>) => {
    const p = await world.person(...args);
    allPeople.push(p);
    return p;
  };

  /** No deck response ever contains a user ID or first name (P1). */
  function expectNoIdentity(text: string) {
    for (const p of allPeople) {
      expect(text).not.toContain(p.id);
      expect(text).not.toMatch(new RegExp(`"${p.firstName}"`));
    }
    expect(text).not.toMatch(/userId|user_id|firstName|cardPath|card_path/);
  }

  beforeAll(() => {
    world = new World(IT!);
  });
  beforeEach(() => useRealSupabase(IT!));
  afterAll(() => world?.cleanup());

  describe('who appears', () => {
    let room: string;
    let otherRoom: string;
    let v: Person;
    const visible: Record<string, string> = {};
    const hidden: Record<string, string> = {};
    let matched: Person;

    beforeAll(async () => {
      useRealSupabase(IT!);
      room = await world.room();
      otherRoom = await world.room();
      v = await person({ gender: 'woman', showMe: ['man'] });
      await world.checkIn(v, room);

      const man = () => person({ gender: 'man', showMe: ['woman'] });

      const m1 = await man();
      visible.m1 = await world.checkIn(m1, room, { topColor: 'green', extras: ['glasses'] });
      const m9 = await person({ gender: 'man', showMe: ['woman', 'man'] });
      visible.m9 = await world.checkIn(m9, room);

      // Show me, both ways.
      const onlyMen = await person({ gender: 'man', showMe: ['man'] });
      hidden.theyDontShowMe = await world.checkIn(onlyMen, room);
      const woman = await person({ gender: 'woman', showMe: ['man', 'woman'] });
      hidden.iDontShowThem = await world.checkIn(woman, room);
      const nb = await person({ gender: 'nonbinary', showMe: ['woman'] });
      hidden.nonbinaryNotInMyShowMe = await world.checkIn(nb, room);

      // Their check-in isn't active.
      const paused = await man();
      hidden.paused = await world.checkIn(paused, room);
      await world.update('profiles', { paused: true }, { id: paused.id });
      const expired = await man();
      hidden.expired = await world.checkIn(expired, room);
      await world.update(
        'checkins',
        {
          joined_at: new Date(Date.now() - 4 * 3_600_000).toISOString(),
          expires_at: new Date(Date.now() - 60_000).toISOString(),
        },
        { id: hidden.expired },
      );
      const left = await man();
      hidden.left = await world.checkIn(left, room);
      await world.update('checkins', { left_at: new Date().toISOString() }, { id: hidden.left });
      const removed = await man();
      hidden.removedByAdmin = await world.checkIn(removed, room);
      await world.update('checkins', { visible: false }, { id: hidden.removedByAdmin });
      const banned = await man();
      hidden.banned = await world.checkIn(banned, room);
      await world.update('profiles', { banned_at: new Date().toISOString() }, { id: banned.id });
      const elsewhere = await man();
      hidden.otherRoom = await world.checkIn(elsewhere, otherRoom);

      // Blocks, both ways.
      const iBlocked = await man();
      hidden.iBlocked = await world.checkIn(iBlocked, room);
      const theyBlocked = await man();
      hidden.theyBlocked = await world.checkIn(theyBlocked, room);
      const blocks = await world.admin.from('blocks').insert([
        { blocker_id: v.id, blocked_id: iBlocked.id },
        { blocker_id: theyBlocked.id, blocked_id: v.id },
      ]);
      expect(blocks.error).toBeNull();

      // An active match.
      matched = await man();
      hidden.matched = await world.checkIn(matched, room);
      const [a, b] = [v.id, matched.id].sort() as [string, string];
      const match = await world.admin.from('matches').insert({
        room_id: room,
        user_a: a,
        user_b: b,
        choice_deadline: new Date(Date.now() + 600_000).toISOString(),
      });
      expect(match.error).toBeNull();
    });

    it('shows exactly the people every rule allows', async () => {
      const ids = await world.wholeDeck(v, room);
      expect(sorted(ids)).toEqual(sorted(Object.values(visible)));
      for (const [why, card] of Object.entries(hidden)) {
        expect(ids, `${why} should be hidden`).not.toContain(card);
      }
    });

    it('a card never carries a user ID, name, card path or anything outside the contract (P1)', async () => {
      const res = await world.deck(v, room);
      const text = await res.clone().text();
      const body = await deckBody(res);
      expectNoIdentity(text);
      for (const card of body.cards) {
        expect(Object.keys(card).sort()).toEqual(['id', 'image', 'tags', 'tappedByMe']);
        expect(card.image.url).toMatch(
          new RegExp(`^/api/cards/${card.id}/image\\?exp=\\d+&sig=[A-Za-z0-9_-]{43}$`),
        );
      }
    });

    it('the matched person comes back once the match ends (unmatch or block)', async () => {
      const [a, b] = [v.id, matched.id].sort() as [string, string];
      await world.update(
        'matches',
        { status: 'ended', ended_at: new Date().toISOString() },
        { user_a: a, user_b: b },
      );
      const ids = await world.wholeDeck(v, room);
      expect(ids).toContain(hidden.matched);
    });

    it('nobody sees me while I am paused, and I get emptyReason paused', async () => {
      const m1View = await person({ gender: 'man', showMe: ['woman'] });
      await world.checkIn(m1View, room);
      const vCard = (
        await world.admin
          .from('checkins')
          .select('id')
          .eq('user_id', v.id)
          .is('left_at', null)
          .single()
      ).data!.id;
      expect(await world.wholeDeck(m1View, room)).toContain(vCard);

      await world.update('profiles', { paused: true }, { id: v.id });
      try {
        expect(await world.wholeDeck(m1View, room)).not.toContain(vCard);
        const body = await deckBody(await world.deck(v, room));
        expect(body).toMatchObject({ cards: [], hasMore: false, emptyReason: 'paused' });
      } finally {
        await world.update('profiles', { paused: false }, { id: v.id });
      }
    });
  });

  describe('my own check-in', () => {
    it('never checked in to this room, or no such room: 404, the same body (P11)', async () => {
      const room = await world.room();
      const someone = await person({ gender: 'man', showMe: ['woman'] });
      const notHere = await world.deck(someone, room);
      const noRoom = await world.deck(someone, '00000000-0000-4000-8000-00000000dead');
      expect(notHere.status).toBe(404);
      expect(noRoom.status).toBe(404);
      expect(await notHere.json()).toEqual(await noRoom.json());
    });

    it('expired, left or room no longer live: an empty page with checkin_ended', async () => {
      const room = await world.room();
      const me = await person({ gender: 'woman', showMe: ['man'] });
      const other = await person({ gender: 'man', showMe: ['woman'] });
      const mine = await world.checkIn(me, room);
      await world.checkIn(other, room);
      expect((await deckBody(await world.deck(me, room))).cards).toHaveLength(1);

      await world.update('checkins', { left_at: new Date().toISOString() }, { id: mine });
      expect(await deckBody(await world.deck(me, room))).toEqual({
        cards: [],
        viewsLeftToday: CARD_VIEWS_PER_ROOM_PER_DAY - 1,
        hasMore: false,
        emptyReason: 'checkin_ended',
      });

      await world.checkIn(me, room);
      await world.update('rooms', { status: 'ended' }, { id: room });
      expect(await deckBody(await world.deck(me, room))).toMatchObject({
        cards: [],
        emptyReason: 'checkin_ended',
      });
    });

    it('nobody else here yet: an empty page with quiet', async () => {
      const room = await world.room();
      const me = await person({ gender: 'woman', showMe: ['man'] });
      await world.checkIn(me, room);
      expect(await deckBody(await world.deck(me, room))).toEqual({
        cards: [],
        viewsLeftToday: CARD_VIEWS_PER_ROOM_PER_DAY,
        hasMore: false,
        emptyReason: 'quiet',
      });
    });
  });

  describe('filters (What did you notice)', () => {
    let room: string;
    let me: Person;
    const c: Record<string, string> = {};

    beforeAll(async () => {
      useRealSupabase(IT!);
      room = await world.room();
      me = await person({ gender: 'man', showMe: ['woman', 'nonbinary'] });
      await world.checkIn(me, room);
      const w = () => person({ gender: 'woman', showMe: ['man'] });
      c.greenShortBrownGlasses = await world.checkIn(await w(), room, {
        topColor: 'green',
        hairLength: 'short',
        hairColor: 'brown',
        extras: ['glasses', 'hat'],
      });
      c.blueLongBlonde = await world.checkIn(await w(), room, {
        topColor: 'blue',
        hairLength: 'long',
        hairColor: 'blonde',
        extras: ['glasses'],
      });
      c.redNoHair = await world.checkIn(await w(), room, { topColor: 'red', extras: ['hat'] });
      c.nonbinaryGreen = await world.checkIn(
        await person({ gender: 'nonbinary', showMe: ['man'] }),
        room,
        { topColor: 'green', hairLength: 'medium', hairColor: 'dyed', extras: [] },
      );
    });

    const cases: [string, Record<string, string[]>, string[]][] = [
      [
        'no filters means everyone',
        {},
        ['greenShortBrownGlasses', 'blueLongBlonde', 'redNoHair', 'nonbinaryGreen'],
      ],
      [
        'empty lists mean any',
        { topColor: [], extras: [] },
        ['greenShortBrownGlasses', 'blueLongBlonde', 'redNoHair', 'nonbinaryGreen'],
      ],
      ['gender', { gender: ['nonbinary'] }, ['nonbinaryGreen']],
      [
        'top color, any of the listed',
        { topColor: ['green', 'red'] },
        ['greenShortBrownGlasses', 'redNoHair', 'nonbinaryGreen'],
      ],
      [
        'hair length (no hair tag never matches)',
        { hairLength: ['short', 'long'] },
        ['greenShortBrownGlasses', 'blueLongBlonde'],
      ],
      ['hair color', { hairColor: ['dyed'] }, ['nonbinaryGreen']],
      ['extras: every listed extra', { extras: ['glasses', 'hat'] }, ['greenShortBrownGlasses']],
      ['extras: one', { extras: ['glasses'] }, ['greenShortBrownGlasses', 'blueLongBlonde']],
      [
        'several attributes together',
        { gender: ['woman'], topColor: ['green', 'blue'], extras: ['glasses'] },
        ['greenShortBrownGlasses', 'blueLongBlonde'],
      ],
    ];

    it.each(cases)('%s', async (_name, filters, expected) => {
      const ids = await world.wholeDeck(me, room, filters);
      expect(sorted(ids)).toEqual(sorted(expected.map((k) => c[k]!)));
    });

    it('nobody fits: an empty page with no_match', async () => {
      const body = await deckBody(
        await world.deck(me, room, { filters: { topColor: ['purple'] } }),
      );
      expect(body).toMatchObject({ cards: [], hasMore: false, emptyReason: 'no_match' });
    });

    it('cards carry their tags as checked in', async () => {
      const body = await deckBody(
        await world.deck(me, room, { filters: { extras: ['glasses', 'hat'] } }),
      );
      expect(body.cards[0]!.tags).toEqual({
        topColor: 'green',
        hairLength: 'short',
        hairColor: 'brown',
        extras: ['glasses', 'hat'],
      });
      const noHair = await deckBody(await world.deck(me, room, { filters: { topColor: ['red'] } }));
      expect(noHair.cards[0]!.tags).toEqual({ topColor: 'red', extras: ['hat'] });
    });

    it('a filter value outside the contract, or repeated, is 400', async () => {
      expect(
        (await world.deck(me, room, { filters: { topColor: ['plaid' as never] } })).status,
      ).toBe(400);
      expect((await world.deck(me, room, { filters: { hairColor: ['red', 'red'] } })).status).toBe(
        400,
      );
    });
  });

  describe('paging, the daily view cap and the shuffle', () => {
    const CROWD = CARD_VIEWS_PER_ROOM_PER_DAY + 5;
    let room: string;
    let me: Person;
    let other: Person;
    let arrival: string[];

    beforeAll(async () => {
      useRealSupabase(IT!);
      room = await world.room();
      me = await person({ gender: 'woman', showMe: ['man'] });
      other = await person({ gender: 'woman', showMe: ['man'] });
      await world.checkIn(me, room);
      await world.checkIn(other, room);
      const men = await world.crowd(CROWD, { gender: 'man', showMe: ['woman'] });
      allPeople.push(...men);
      arrival = [];
      // Check in one at a time, so arrival order is known.
      for (const m of men) arrival.push(await world.checkIn(m, room));
    });

    it('pages of DECK_PAGE_SIZE, no repeats, then the view cap: view_limit_reached', async () => {
      const seen: string[] = [];
      let offset = 0;
      let last: Deck | undefined;
      for (let page = 0; page < 10; page++) {
        last = await deckBody(await world.deck(me, room, { offset }));
        expect(last.cards.length).toBeLessThanOrEqual(DECK_PAGE_SIZE);
        seen.push(...last.cards.map((card) => card.id));
        expect(last.viewsLeftToday).toBe(CARD_VIEWS_PER_ROOM_PER_DAY - seen.length);
        if (!last.hasMore) break;
        expect(last.nextOffset).toBe(offset + DECK_PAGE_SIZE);
        offset = last.nextOffset!;
      }
      expect(seen).toHaveLength(CARD_VIEWS_PER_ROOM_PER_DAY);
      expect(new Set(seen).size).toBe(seen.length);
      expect(last!.viewsLeftToday).toBe(0);

      // The page after the last one is empty and says why.
      const after = await deckBody(
        await world.deck(me, room, { offset: CARD_VIEWS_PER_ROOM_PER_DAY }),
      );
      expect(after).toEqual({
        cards: [],
        viewsLeftToday: 0,
        hasMore: false,
        emptyReason: 'view_limit_reached',
      });
    });

    it('seeing the same cards again is free, and the order holds on refresh', async () => {
      const first = await world.wholeDeck(me, room);
      const again = await world.wholeDeck(me, room);
      expect(again).toEqual(first);
      expect(first).toHaveLength(CARD_VIEWS_PER_ROOM_PER_DAY);
      const page = await deckBody(await world.deck(me, room));
      expect(page.viewsLeftToday).toBe(0);
    });

    it('a filter only shows cards already seen once the cap is used', async () => {
      const seen = new Set(await world.wholeDeck(me, room));
      const blue = await world.wholeDeck(me, room, { topColor: ['blue'] });
      for (const id of blue) expect(seen.has(id)).toBe(true);
    });

    it('the order is not arrival order, and differs from person to person', async () => {
      const mine = await world.wholeDeck(me, room);
      const theirs = await world.wholeDeck(other, room);
      const arrivedOrder = arrival.filter((id) => mine.includes(id));
      expect(mine).not.toEqual(arrivedOrder);
      expect(mine).not.toEqual([...arrivedOrder].reverse());
      expect(theirs.slice(0, 20)).not.toEqual(mine.slice(0, 20));
      // A rank correlation with arrival near zero: arrival can't be read off the order.
      const pos = new Map(arrival.map((id, i) => [id, i]));
      const ranks = mine.map((id) => pos.get(id)!);
      const n = ranks.length;
      const mean = (n - 1) / 2;
      let num = 0;
      let den = 0;
      ranks.forEach((r, i) => {
        num += (i - mean) * (r - mean);
        den += (i - mean) ** 2;
      });
      expect(Math.abs(num / den)).toBeLessThan(0.6);
    });
  });
});
