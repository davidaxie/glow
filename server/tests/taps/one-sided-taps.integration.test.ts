/**
 * Owner: B4. P5: one-sided taps are never revealed by any response, count, event or timing.
 *
 * Bea is tapped by three people who she hasn't tapped. Bo is in the same room, seeing the
 * same people, and nobody tapped him. Everything either of them can ask the API (their
 * deck, their room state, their matches, their own taps) must look the same, apart from
 * the per-viewer image signatures, and must not change when the taps land. Nobody but the
 * tapper is notified, and the tapper's `sent` never depends on what the other person did.
 */
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import type { Deck, TapResult } from '@/contracts';
import { IT, useRealSupabase, World, type Person } from '../deck/harness';

vi.mock('@/server/deck/dependencies', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@/server/deck/dependencies')>();
  return { ...actual, notify: vi.fn(async () => ({ realtime: 'skipped', push: null })) };
});
const { notify } = await import('@/server/deck/dependencies');

/** A deck with the per-viewer image links taken out, so two viewers' decks compare. */
function shape(deck: Deck) {
  return {
    ...deck,
    cards: deck.cards.map(({ image, ...rest }) => {
      expect(image.url).toMatch(/^\/api\/cards\/[0-9a-f-]{36}\/image\?exp=\d+&sig=[\w-]{43}$/);
      return rest;
    }),
  };
}

const median = (xs: number[]) => {
  const s = [...xs].sort((a, b) => a - b);
  return s[Math.floor(s.length / 2)]!;
};

describe.runIf(IT)('one-sided taps stay secret (P5, integration)', { timeout: 180_000 }, () => {
  let world: World;
  let room: string;
  let bea: Person;
  let bo: Person;
  let beaCard: string;
  let boCard: string;
  let caraCard: string;
  let tappers: Person[];
  let bystanders: Person[];
  const cardOf = new Map<string, string>();

  const deckOf = async (p: Person) => {
    const res = await world.deck(p, room);
    expect(res.status).toBe(200);
    return (await res.json()) as Deck;
  };
  const roomState = async (p: Person) => {
    const { data, error } = await world.admin.rpc('get_room_state', {
      p_user_id: p.id,
      p_room_id: room,
    });
    expect(error).toBeNull();
    const { tapsLeftToday, viewsLeftToday } = data as {
      tapsLeftToday: number;
      viewsLeftToday: number;
    };
    return { tapsLeftToday, viewsLeftToday };
  };
  const matchesOf = async (p: Person) => {
    const res = await world.matches(p);
    expect(res.status).toBe(200);
    return res.json();
  };

  beforeAll(async () => {
    world = new World(IT!);
    useRealSupabase(IT!);
    room = await world.room();
    // Bea and Bo: same gender and show me, so the same people see them and they see the same people.
    bea = await world.person({
      gender: 'nonbinary',
      showMe: ['woman', 'man', 'nonbinary'],
      firstName: 'Bea',
    });
    bo = await world.person({
      gender: 'nonbinary',
      showMe: ['woman', 'man', 'nonbinary'],
      firstName: 'Bo',
    });
    beaCard = await world.checkIn(bea, room, { topColor: 'green' });
    boCard = await world.checkIn(bo, room, { topColor: 'green' });
    // Cara is never tapped by anyone.
    const cara = await world.person({
      gender: 'nonbinary',
      showMe: ['woman', 'man', 'nonbinary'],
      firstName: 'Cara',
    });
    caraCard = await world.checkIn(cara, room);
    tappers = await world.crowd(3, { gender: 'man', showMe: ['nonbinary'] });
    bystanders = await world.crowd(6, { gender: 'woman', showMe: ['nonbinary', 'man'] });
    for (const p of [...tappers, ...bystanders]) cardOf.set(p.id, await world.checkIn(p, room));
    // Everyone has seen the deck once, so every card can be tapped.
    for (const p of [bea, bo, cara, ...tappers, ...bystanders]) await world.wholeDeck(p, room);
  });
  beforeEach(() => useRealSupabase(IT!));
  afterAll(() => world?.cleanup());

  it('the tapped person sees nothing change: deck, room state and matches', async () => {
    const beforeDeck = shape(await deckOf(bea));
    const beforeState = await roomState(bea);
    const beforeMatches = await matchesOf(bea);
    vi.mocked(notify).mockClear();

    for (const t of tappers) {
      const res = await world.tap(t, room, beaCard);
      expect(((await res.json()) as TapResult).result).toBe('sent');
    }

    expect(shape(await deckOf(bea))).toEqual(beforeDeck);
    expect(await roomState(bea)).toEqual(beforeState);
    expect(await matchesOf(bea)).toEqual(beforeMatches);
    expect(beforeMatches).toEqual({ matches: [] });
    // No event to anyone: not Bea, not the tappers.
    expect(notify).not.toHaveBeenCalled();
  });

  it('a tapped person and an untapped one look the same in every response', async () => {
    // Same room, same people, same show me: the only difference is three taps on Bea.
    const others = (ids: string[]) => ids.filter((id) => id !== beaCard && id !== boCard).sort();
    expect(others(await world.wholeDeck(bea, room))).toEqual(
      others(await world.wholeDeck(bo, room)),
    );
    const beaDeck = shape(await deckOf(bea));
    const boDeck = shape(await deckOf(bo));
    expect(Object.keys(beaDeck).sort()).toEqual(Object.keys(boDeck).sort());
    expect(beaDeck.viewsLeftToday).toBe(boDeck.viewsLeftToday);
    expect(beaDeck.hasMore).toBe(boDeck.hasMore);
    expect(beaDeck.cards.every((c) => c.tappedByMe === false)).toBe(true);
    expect(await roomState(bea)).toEqual(await roomState(bo));
    expect(await matchesOf(bea)).toEqual(await matchesOf(bo));
  });

  it("the tapper's sent is the same whether or not the other person has tapped anyone", async () => {
    // Bea has been tapped three times; Cara never. Neither has tapped anyone.
    const [x, y] = bystanders as [Person, Person];
    const toBea = (await (await world.tap(x, room, beaCard)).json()) as TapResult;
    const toCara = (await (await world.tap(y, room, caraCard)).json()) as TapResult;
    expect(toBea).toEqual({ result: 'sent', tapsLeftToday: 2 });
    expect(toCara).toEqual(toBea);
  });

  it('no count anywhere reflects a one-sided tap: no activity row for taps', async () => {
    // room_activity feeds the admin metrics page (B7). A per-room tap counter would let an
    // admin in the room time someone's tap, so taps never write one (A2, migration 0002).
    const { data, error } = await world.admin
      .from('room_activity')
      .select('kind')
      .eq('room_id', room)
      .eq('kind', 'tap');
    expect(error).toBeNull();
    expect(data).toEqual([]);
  });

  it("timing: the tapped person's deck is as fast as an untapped person's", async () => {
    // Interleaved, so drift on a shared machine hits both equally.
    const tapped: number[] = [];
    const untapped: number[] = [];
    for (let i = 0; i < 30; i++) {
      for (const [p, into] of i % 2 === 0
        ? ([
            [bea, tapped],
            [bo, untapped],
          ] as const)
        : ([
            [bo, untapped],
            [bea, tapped],
          ] as const)) {
        const t0 = performance.now();
        const res = await world.deck(p, room);
        await res.arrayBuffer();
        into.push(performance.now() - t0);
      }
    }
    const a = median(tapped);
    const b = median(untapped);
    // A real leak (an extra query or lookup) shows up as a consistent gap; noise doesn't.
    expect(Math.abs(a - b)).toBeLessThanOrEqual(Math.max(8, 0.25 * Math.min(a, b)));
  });

  it('timing: a sent tap is as fast whether or not the other person tapped someone', async () => {
    // One person taps Bea (tapped many times), another taps Cara (never tapped). Re-taps
    // are free, so each taps the same card again and again.
    const [p1, p2] = bystanders.slice(3) as [Person, Person];
    const toTapped: number[] = [];
    const toQuiet: number[] = [];
    for (let i = 0; i < 20; i++) {
      for (const [p, card, into] of [
        [p1, beaCard, toTapped],
        [p2, caraCard, toQuiet],
      ] as const) {
        const t0 = performance.now();
        const res = await world.tap(p, room, card);
        expect(((await res.json()) as TapResult).result).toBe('sent');
        into.push(performance.now() - t0);
      }
    }
    const a = median(toTapped);
    const b = median(toQuiet);
    expect(Math.abs(a - b)).toBeLessThanOrEqual(Math.max(8, 0.25 * Math.min(a, b)));
  });
});
