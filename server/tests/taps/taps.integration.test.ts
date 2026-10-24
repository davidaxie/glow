/**
 * Owner: B4. Taps and matches through the real POST /api/rooms/{id}/taps route, real sign-in
 * and the real record_tap: what a tap may target (P11), the daily cap, re-tapping, mutual
 * taps, and 50 pairs tapping each other at the same moment. See tests/deck/harness.ts for
 * when these run.
 */
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { TAPS_PER_ROOM_PER_DAY, zTapResult, type TapResult } from '@/contracts';
import { IT, useRealSupabase, World, type Person } from '../deck/harness';

// Setting up dozens of people takes a while on a busy machine.
vi.setConfig({ hookTimeout: 180_000, testTimeout: 180_000 });

vi.mock('@/server/deck/dependencies', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@/server/deck/dependencies')>();
  return { ...actual, notify: vi.fn(async () => ({ realtime: 'skipped', push: null })) };
});
const { notify } = await import('@/server/deck/dependencies');

async function tapBody(res: Response): Promise<TapResult> {
  expect(res.status).toBe(200);
  const body = (await res.json()) as TapResult;
  expect(zTapResult.parse(body)).toEqual(body);
  return body;
}

describe.runIf(IT)('taps (integration)', { timeout: 180_000 }, () => {
  let world: World;
  beforeAll(() => {
    world = new World(IT!);
  });
  beforeEach(() => useRealSupabase(IT!));
  afterAll(() => world?.cleanup());

  /** A room with one woman and `men` men who all see each other, every deck already shown. */
  async function scene(men: number) {
    const room = await world.room();
    const me = await world.person({ gender: 'woman', showMe: ['man'], firstName: 'Avery' });
    const myCard = await world.checkIn(me, room);
    const them: Person[] = [];
    const cards: string[] = [];
    for (let i = 0; i < men; i++) {
      const m = await world.person({ gender: 'man', showMe: ['woman'], firstName: `Blake${i}` });
      them.push(m);
      cards.push(await world.checkIn(m, room));
    }
    await world.wholeDeck(me, room);
    for (const m of them) await world.wholeDeck(m, room);
    return { room, me, myCard, them, cards };
  }

  it('a tap is sent, and tapping the same card again is free', async () => {
    const { room, me, cards } = await scene(1);
    expect(await tapBody(await world.tap(me, room, cards[0]!))).toEqual({
      result: 'sent',
      tapsLeftToday: TAPS_PER_ROOM_PER_DAY - 1,
    });
    expect(await tapBody(await world.tap(me, room, cards[0]!))).toEqual({
      result: 'sent',
      tapsLeftToday: TAPS_PER_ROOM_PER_DAY - 1,
    });
    expect(notify).not.toHaveBeenCalled();
    // The deck says I tapped it, and nothing else changed.
    const deck = (await (await world.deck(me, room)).json()) as {
      cards: { id: string; tappedByMe: boolean }[];
    };
    expect(deck.cards.find((c) => c.id === cards[0])?.tappedByMe).toBe(true);
  });

  it(`after ${TAPS_PER_ROOM_PER_DAY} taps, a new one is 409 tap_limit_reached; re-tapping is still free`, async () => {
    const { room, me, cards } = await scene(TAPS_PER_ROOM_PER_DAY + 1);
    for (let i = 0; i < TAPS_PER_ROOM_PER_DAY; i++) {
      const body = await tapBody(await world.tap(me, room, cards[i]!));
      expect(body).toEqual({ result: 'sent', tapsLeftToday: TAPS_PER_ROOM_PER_DAY - 1 - i });
    }
    const over = await world.tap(me, room, cards[TAPS_PER_ROOM_PER_DAY]!);
    expect(over.status).toBe(409);
    expect(((await over.json()) as { error: { code: string } }).error.code).toBe(
      'tap_limit_reached',
    );
    expect(await tapBody(await world.tap(me, room, cards[0]!))).toEqual({
      result: 'sent',
      tapsLeftToday: 0,
    });
  });

  it('a tap only reaches a card the deck has shown me, in this room, that is not mine: else 404', async () => {
    const { room, me, myCard } = await scene(0);
    const late = await world.person({ gender: 'man', showMe: ['woman'] });
    const lateCard = await world.checkIn(late, room);
    const otherRoom = await world.room();
    const elsewhere = await world.person({ gender: 'man', showMe: ['woman'] });
    const elsewhereCard = await world.checkIn(elsewhere, otherRoom);
    const notInDeck = await world.person({ gender: 'woman', showMe: ['woman'] });
    const notInDeckCard = await world.checkIn(notInDeck, room);

    const bodies: unknown[] = [];
    for (const card of [
      lateCard,
      myCard,
      elsewhereCard,
      notInDeckCard,
      '00000000-0000-4000-8000-00000000dead',
    ]) {
      const res = await world.tap(me, room, card);
      expect(res.status, card).toBe(404);
      bodies.push(await res.json());
    }
    // Every 404 is the same body (P11).
    for (const body of bodies)
      expect(body).toEqual({ error: { code: 'not_found', message: 'Not found.' } });

    // Once the deck has shown it, the same card can be tapped.
    expect(await world.wholeDeck(me, room)).toContain(lateCard);
    expect((await tapBody(await world.tap(me, room, lateCard))).result).toBe('sent');
    // A card from another room, through this room's route, stays 404.
    expect((await world.tap(me, room, elsewhereCard)).status).toBe(404);
  });

  it('a card whose owner blocked me after I saw it is 404', async () => {
    const { room, me, them, cards } = await scene(1);
    await world.admin.from('blocks').insert({ blocker_id: them[0]!.id, blocked_id: me.id });
    expect((await world.tap(me, room, cards[0]!)).status).toBe(404);
  });

  it('the second tap makes a match: mutual, match.created to both, and both decks drop each other', async () => {
    const { room, me, myCard, them, cards } = await scene(2);
    const [blake] = them as [Person];
    expect(await tapBody(await world.tap(me, room, cards[0]!))).toEqual({
      result: 'sent',
      tapsLeftToday: 2,
    });
    expect(notify).not.toHaveBeenCalled();

    const mutual = await tapBody(await world.tap(blake, room, myCard));
    expect(mutual).toMatchObject({ result: 'mutual', tapsLeftToday: 2 });
    expect(mutual.matchId).toMatch(/^[0-9a-f-]{36}$/);
    expect(JSON.stringify(mutual)).not.toContain(me.id);

    expect(notify).toHaveBeenCalledTimes(1);
    const [people, event] = vi.mocked(notify).mock.calls[0]!;
    expect([...(people as string[])].sort()).toEqual([me.id, blake.id].sort());
    expect(event).toEqual({ type: 'match.created', matchId: mutual.matchId });

    expect(await world.wholeDeck(me, room)).not.toContain(cards[0]);
    expect(await world.wholeDeck(me, room)).toContain(cards[1]);
    expect(await world.wholeDeck(blake, room)).not.toContain(myCard);

    // Exactly one match for the pair, and the card is gone, so a third tap is 404.
    const { count } = await world.admin
      .from('matches')
      .select('id', { count: 'exact', head: true })
      .eq('room_id', room);
    expect(count).toBe(1);
    expect((await world.tap(me, room, cards[0]!)).status).toBe(404);
  });

  it.each([1, 2])(
    '50 pairs tapping each other at the same moment make exactly 50 matches (round %i)',
    async (round) => {
      const PAIRS = 50;
      const room = await world.room();
      const women = await world.crowd(PAIRS, { gender: 'woman', showMe: ['man'] });
      const men = await world.crowd(PAIRS, { gender: 'man', showMe: ['woman'] });
      const card = new Map<string, string>();
      for (const p of [...women, ...men]) card.set(p.id, await world.checkIn(p, room));
      // Everyone scrolls their whole deck first, as the app would, so every card was shown.
      for (let i = 0; i < women.length + men.length; i += 20) {
        await Promise.all([...women, ...men].slice(i, i + 20).map((p) => world.wholeDeck(p, room)));
      }
      // Round 1 pairs woman i with man i; round 2 with man i+1, so the pairs differ.
      const pairs = women.map((w, i) => [w, men[(i + round - 1) % PAIRS]!] as const);
      vi.mocked(notify).mockClear();

      const taps = pairs.flatMap(([w, m]) => [
        { pair: w.id, call: () => world.tap(w, room, card.get(m.id)!) },
        { pair: w.id, call: () => world.tap(m, room, card.get(w.id)!) },
      ]);
      // All 100 requests start together.
      const results = await Promise.all(
        taps.map(async (t) => ({ pair: t.pair, res: await t.call() })),
      );

      const byPair = new Map<string, TapResult[]>();
      for (const { pair, res } of results) {
        const body = await tapBody(res);
        byPair.set(pair, [...(byPair.get(pair) ?? []), body]);
      }
      // Per pair: one tap landed first (sent), the other found it and made the match.
      for (const [, bodies] of byPair) {
        expect(bodies.map((b) => b.result).sort()).toEqual(['mutual', 'sent']);
      }
      const matchIds = [...byPair.values()].flat().flatMap((b) => (b.matchId ? [b.matchId] : []));
      expect(new Set(matchIds).size).toBe(PAIRS);

      const { data: rows } = await world.admin
        .from('matches')
        .select('user_a, user_b, status')
        .eq('room_id', room);
      expect(rows).toHaveLength(PAIRS);
      const expected = pairs.map(([w, m]) => [w.id, m.id].sort().join(':')).sort();
      expect(rows!.map((r) => `${r.user_a}:${r.user_b}`).sort()).toEqual(expected);
      expect(rows!.every((r) => r.status === 'choosing')).toBe(true);

      // match.created exactly once per match, to both people.
      expect(notify).toHaveBeenCalledTimes(PAIRS);
      for (const [people, event] of vi.mocked(notify).mock.calls) {
        expect((people as string[]).length).toBe(2);
        expect(event.type).toBe('match.created');
      }
    },
  );
});
