import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import type { Glow } from '@/contracts';
import { notify } from '@/server/glow/dependencies';
import { startGlow } from '@/server/glow';
import { serviceDb } from '@/server/glow/db';
import { CODE_WORDS } from '@/server/glow/words';
import { IT, useRealSupabase, World, type Person } from './harness';

// Owner: C3. Glow against a real local Supabase (harness.ts says how to run it). The database
// functions make the rules; these tests prove the routes and startGlow use them correctly, and
// that both people see exactly the same glow.

vi.mock('@/server/glow/dependencies', () => ({
  notify: vi.fn(async () => ({ realtime: 'sent', push: null })),
}));

const sent = () => vi.mocked(notify).mock.calls.map(([ids, event]) => [[...ids].sort(), event]);
const both = (a: Person, b: Person) => [a.id, b.id].sort();

describe.runIf(IT)('glow, end to end against the database', () => {
  let world: World;
  let room: string;

  beforeAll(async () => {
    useRealSupabase(IT!);
    world = new World(IT!);
    room = await world.room();
  }, 60_000);

  beforeEach(() => {
    useRealSupabase(IT!);
    vi.mocked(notify).mockClear();
  });

  afterAll(async () => {
    await world?.cleanup();
  }, 60_000);

  it('shows both people the same color, code word and meeting spot', async () => {
    const { matchId, a, b } = await world.readyToGlow(room);
    await expect(startGlow(serviceDb(), matchId)).resolves.toEqual({ result: 'started' });
    expect(sent()).toEqual([[both(a, b), { type: 'glow.started', matchId }]]);

    const [mine, theirs] = await Promise.all([world.glow(a, matchId), world.glow(b, matchId)]);
    expect(mine.status).toBe(200);
    expect(theirs.status).toBe(200);
    const glowA = (await mine.json()) as Glow;
    const glowB = (await theirs.json()) as Glow;
    expect(glowA.status).toBe('active');
    expect(CODE_WORDS).toContain(glowA.codeWord);
    expect(glowA.meetingSpot?.name).toBeTruthy();
    for (const key of ['id', 'color', 'codeWord', 'meetingSpot', 'startedAt', 'endsAt'] as const) {
      expect(glowB[key]).toEqual(glowA[key]);
    }
    // 15 minutes, from contracts/constants.json.
    expect(Date.parse(glowA.endsAt) - Date.parse(glowA.startedAt)).toBe(900_000);
    // No user ID anywhere in either reply (P1).
    const text = JSON.stringify([glowA, glowB]);
    expect(text).not.toContain(a.id);
    expect(text).not.toContain(b.id);
    expect(await world.matchStatus(matchId)).toBe('glowing');

    // Starting again is harmless: the same glow.
    await expect(startGlow(serviceDb(), matchId)).resolves.toEqual({ result: 'started' });
    expect(((await (await world.glow(b, matchId)).json()) as Glow).id).toBe(glowA.id);
  }, 60_000);

  it('answers 404 to anyone outside the match, exactly like a match that never existed (P11)', async () => {
    const { matchId } = await world.readyToGlow(room);
    await startGlow(serviceDb(), matchId);
    const stranger = await world.person();
    const notMine = await world.glow(stranger, matchId);
    const missing = await world.glow(stranger, crypto.randomUUID());
    expect(notMine.status).toBe(404);
    expect(await notMine.text()).toBe(await missing.text());
    expect((await world.met(stranger, matchId)).status).toBe(404);
    expect((await world.cancel(stranger, matchId)).status).toBe(404);
  }, 60_000);

  it('counts We met only when both tap it, then ends the glow as met for both', async () => {
    const { matchId, a, b } = await world.readyToGlow(room);
    await startGlow(serviceDb(), matchId);
    vi.mocked(notify).mockClear();

    const first = (await (await world.met(a, matchId)).json()) as Glow;
    expect(first).toMatchObject({ status: 'active', youMet: true, theyMet: false });
    expect(notify).not.toHaveBeenCalled();
    const seenByB = (await (await world.glow(b, matchId)).json()) as Glow;
    expect(seenByB).toMatchObject({ status: 'active', youMet: false, theyMet: true });

    const second = (await (await world.met(b, matchId)).json()) as Glow;
    expect(second).toMatchObject({ status: 'met', youMet: true, theyMet: true });
    expect(second.endedAt).toBeDefined();
    expect(sent()).toEqual([[both(a, b), { type: 'glow.ended', matchId }]]);
    expect(await world.matchStatus(matchId)).toBe('met');

    // Tapping again changes nothing and tells nobody.
    vi.mocked(notify).mockClear();
    expect(((await (await world.met(a, matchId)).json()) as Glow).status).toBe('met');
    expect(notify).not.toHaveBeenCalled();
  }, 60_000);

  it.each(['cancel', 'switch_to_chat'] as const)(
    '%s ends the glow for both and opens the chat',
    async (reason) => {
      const { matchId, a, b } = await world.readyToGlow(room);
      await startGlow(serviceDb(), matchId);
      vi.mocked(notify).mockClear();

      const res = await world.cancel(a, matchId, reason);
      expect(res.status).toBe(200);
      expect(((await res.json()) as Glow).status).toBe('canceled');
      expect(sent()).toEqual([[both(a, b), { type: 'glow.ended', matchId }]]);
      expect(((await (await world.glow(b, matchId)).json()) as Glow).status).toBe('canceled');
      expect(await world.matchStatus(matchId)).toBe('chatting');

      // The other person canceling a moment later is harmless and announces nothing new.
      vi.mocked(notify).mockClear();
      expect((await world.cancel(b, matchId)).status).toBe(200);
      expect(notify).not.toHaveBeenCalled();
    },
    60_000,
  );

  it('ends on time: once GLOW_TTL has passed it reads as expired and both are told', async () => {
    const { matchId, a, b } = await world.readyToGlow(room);
    await startGlow(serviceDb(), matchId);
    vi.mocked(notify).mockClear();
    // Move the glow's start and end 16 minutes into the past.
    const { error } = await world.admin
      .from('glow_sessions')
      .update({
        started_at: new Date(Date.now() - 16 * 60_000).toISOString(),
        ends_at: new Date(Date.now() - 60_000).toISOString(),
      })
      .eq('match_id', matchId);
    expect(error).toBeNull();

    const res = await world.glow(a, matchId);
    expect(res.status).toBe(200);
    expect(((await res.json()) as Glow).status).toBe('expired');
    expect(sent()).toEqual([[both(a, b), { type: 'glow.ended', matchId }]]);
    expect(await world.matchStatus(matchId)).toBe('chatting');
    // A late We met can't revive it.
    expect(((await (await world.met(b, matchId)).json()) as Glow).status).toBe('expired');
  }, 60_000);

  it('opens the chat for both when someone left the room before the glow could start', async () => {
    const { matchId, a, b } = await world.readyToGlow(room);
    await world.admin
      .from('checkins')
      .update({ left_at: new Date().toISOString() })
      .eq('user_id', a.id);
    await expect(startGlow(serviceDb(), matchId)).resolves.toEqual({
      result: 'chat',
      reason: 'not_checked_in',
    });
    expect(sent()).toEqual([[both(a, b), { type: 'match.choice', matchId }]]);
    expect((await world.glow(b, matchId)).status).toBe(404);
  }, 60_000);

  it('asks only the person whose location check went stale to send Find again', async () => {
    const { matchId, b } = await world.readyToGlow(room);
    // Any passed check counts as fresh (join or find), so age all of B's.
    await world.admin
      .from('location_checks')
      .update({ created_at: new Date(Date.now() - 5 * 60_000).toISOString() })
      .eq('user_id', b.id);
    await expect(startGlow(serviceDb(), matchId)).resolves.toEqual({
      result: 'waiting',
      reason: 'location_stale',
    });
    expect(sent()).toEqual([[[b.id], { type: 'match.recheck', matchId }]]);
    expect(await world.matchStatus(matchId)).toBe('choosing');
  }, 60_000);
});

describe.runIf(IT)('no two active glows in a room share a color and code word', () => {
  const PAIRS = 40;
  let world: World;
  let room: string;
  let matches: string[];

  beforeAll(async () => {
    useRealSupabase(IT!);
    world = new World(IT!);
    room = await world.room();
    matches = [];
    // A few pairs at a time, so Supabase Auth isn't flooded.
    for (let i = 0; i < PAIRS; i += 8) {
      const batch = await Promise.all(
        Array.from({ length: Math.min(8, PAIRS - i) }, () => world.readyToGlow(room)),
      );
      matches.push(...batch.map((m) => m.matchId));
    }
  }, 180_000);

  beforeEach(() => useRealSupabase(IT!));

  afterAll(async () => {
    await world?.cleanup();
  }, 120_000);

  it(`starts ${PAIRS} glows at the same moment, every one with its own color and word`, async () => {
    const outcomes = await Promise.all(matches.map((id) => startGlow(serviceDb(), id)));
    expect(outcomes.every((o) => o.result === 'started')).toBe(true);

    const { data, error } = await world.admin
      .from('glow_sessions')
      .select('color, code_word, spot_id, status')
      .eq('room_id', room)
      .eq('status', 'active');
    expect(error).toBeNull();
    const active = data!;
    expect(active).toHaveLength(PAIRS);
    // The rule itself: color plus code word is unique among active glows in the room.
    expect(new Set(active.map((g) => `${g.color}+${g.code_word}`)).size).toBe(PAIRS);
    // Colors are spread out first: 40 glows over 8 colors is 5 of each.
    const perColor = new Map<string, number>();
    for (const g of active) perColor.set(g.color, (perColor.get(g.color) ?? 0) + 1);
    expect([...perColor.values()]).toEqual(Array(8).fill(PAIRS / 8));
    // Words are spread out too: none repeats while unused ones remain.
    expect(new Set(active.map((g) => g.code_word)).size).toBe(PAIRS);
    expect(active.every((g) => (CODE_WORDS as readonly string[]).includes(g.code_word))).toBe(true);
    // Meeting spots are shared out evenly (3 spots: 14, 13, 13).
    const perSpot = new Map<string, number>();
    for (const g of active) perSpot.set(g.spot_id!, (perSpot.get(g.spot_id!) ?? 0) + 1);
    expect(Math.max(...perSpot.values()) - Math.min(...perSpot.values())).toBeLessThanOrEqual(1);
  }, 120_000);

  it('a unique index backs the rule up: a duplicate active color and word cannot be stored', async () => {
    const { data } = await world.admin
      .from('glow_sessions')
      .select('match_id, room_id, color, code_word, ends_at')
      .eq('room_id', room)
      .eq('status', 'active')
      .limit(1)
      .single();
    const spare = await world.readyToGlow(room);
    const { error } = await world.admin.from('glow_sessions').insert({
      match_id: spare.matchId,
      room_id: data!.room_id,
      color: data!.color,
      code_word: data!.code_word,
      ends_at: data!.ends_at,
    });
    expect(error?.code).toBe('23505');
  }, 60_000);
});
