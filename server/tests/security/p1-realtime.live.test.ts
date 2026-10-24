/**
 * P1 and the brief's "join another person's Realtime channel": a signed-in attacker with
 * the app's anon key tries every way into someone else's events on the live Realtime server.
 * The server sends with B5's real `broadcast()` (private messages over Realtime's REST API).
 */
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { resetEnvCacheForTests } from '@/env';
import { broadcast } from '@/server/notify/realtime';
import { LIVE, type Live } from './helpers/live';
import { RealtimeProbe } from './helpers/realtime';
import { World, type Card, type Person } from './helpers/world';

const live = LIVE as Live;
let world: World;
let victim: Person;
let attacker: Person;
let roomId: string;
let victimCard: Card;
const probes: RealtimeProbe[] = [];

function useLiveEnv(): void {
  process.env.SUPABASE_URL = live.url;
  process.env.SUPABASE_ANON_KEY = live.anonKey;
  process.env.SUPABASE_SERVICE_ROLE_KEY = live.serviceKey;
  resetEnvCacheForTests();
}

async function probe(): Promise<RealtimeProbe> {
  const p = await RealtimeProbe.connect(live);
  probes.push(p);
  return p;
}

const marker = () => `00000000-0000-4000-8000-${String(Date.now()).padStart(12, '0').slice(-12)}`;

beforeAll(async () => {
  if (!LIVE) return;
  world = new World(live);
  [victim, attacker] = await Promise.all([world.person('woman'), world.person('man')]);
  roomId = await world.room();
  victimCard = await world.checkIn(victim, roomId);
}, 30_000);
beforeEach(() => {
  if (LIVE) useLiveEnv();
});
afterAll(async () => {
  for (const p of probes) p.close();
  if (LIVE) await world.cleanup();
});

describe.skipIf(!LIVE)('Realtime: nobody hears anyone else (live)', () => {
  it('control: the victim receives their own private event', async () => {
    const mine = await probe();
    expect(await mine.join(`user:${victim.id}`, { token: victim.token, private: true })).toBe('ok');
    const matchId = marker();
    expect(
      await broadcast([{ topic: `user:${victim.id}`, event: { type: 'match.created', matchId } }]),
    ).toBe(true);
    await mine.settle();
    expect(JSON.stringify(mine.received)).toContain(matchId);
  });

  // Realtime doesn't answer a join it refuses, so "refused" is anything but an 'ok' reply,
  // and the proof is that the victim's next event never arrives.
  it("a signed-in attacker can't join someone else's private user channel", async () => {
    const spy = await probe();
    expect(await spy.join(`user:${victim.id}`, { token: attacker.token, private: true })).not.toBe(
      'ok',
    );
    const upper = await probe();
    expect(
      await upper.join(`user:${victim.id.toUpperCase()}`, { token: attacker.token, private: true }),
    ).not.toBe('ok');
    const matchId = marker();
    await broadcast([{ topic: `user:${victim.id}`, event: { type: 'match.created', matchId } }]);
    await spy.settle();
    expect(JSON.stringify([...spy.received, ...upper.received])).not.toContain(matchId);
  }, 20_000);

  it('with only the anon key, no private channel opens at all', async () => {
    const anon = await probe();
    expect(await anon.join(`user:${victim.id}`, { private: true })).not.toBe('ok');
    expect(await anon.join(`room:${roomId}`, { private: true })).not.toBe('ok');
    const matchId = marker();
    await broadcast([
      { topic: `user:${victim.id}`, event: { type: 'match.created', matchId } },
      { topic: `room:${roomId}`, event: { type: 'deck.changed', roomId } },
    ]);
    await anon.settle();
    expect(anon.received).toEqual([]);
  }, 20_000);

  it("a public channel with the victim's topic never carries the victim's private events", async () => {
    const spy = await probe();
    // Whether Realtime lets a public join through depends on "Allow public access"
    // (off on the cloud project, D27). Either way, nothing private may arrive on it.
    await spy.join(`user:${victim.id}`, { token: attacker.token, private: false });
    const matchId = marker();
    await broadcast([{ topic: `user:${victim.id}`, event: { type: 'match.created', matchId } }]);
    await spy.settle();
    expect(JSON.stringify(spy.received)).not.toContain(matchId);
  }, 20_000);

  it("nobody can send into a person's private channel, not even themselves", async () => {
    const mine = await probe();
    expect(await mine.join(`user:${victim.id}`, { token: victim.token, private: true })).toBe('ok');
    const fake = await probe();
    await fake.join(`user:${victim.id}`, { token: victim.token, private: true });
    const sent = await fake.broadcast(`user:${victim.id}`, 'match.created', { matchId: marker() });
    await mine.settle();
    expect(sent).not.toBe('ok');
    expect(mine.received).toEqual([]);

    // A forged event on a public channel of the same name never reaches the private one.
    const forger = await probe();
    await forger.join(`user:${victim.id}`, { token: attacker.token, private: false });
    await forger.broadcast(`user:${victim.id}`, 'match.created', {
      type: 'match.created',
      matchId: marker(),
    });
    await mine.settle();
    expect(mine.received).toEqual([]);
  }, 20_000);

  it("a room channel needs an open check-in there, and never shows who's in it", async () => {
    const outsider = await probe();
    expect(
      await outsider.join(`room:${roomId}`, { token: attacker.token, private: true }),
    ).not.toBe('ok');

    const inside = await probe();
    expect(
      await inside.join(`room:${roomId}`, {
        token: victim.token,
        private: true,
        presenceKey: 'me',
      }),
    ).toBe('ok');
    const tracked = await inside.track(`room:${roomId}`);
    await inside.settle();
    expect(tracked).not.toBe('ok');
    const presence = inside.received.filter((r) => r.event !== 'broadcast');
    expect(JSON.stringify(presence)).not.toContain(victim.id);
    expect(victimCard.roomId).toBe(roomId);
  }, 20_000);

  it('every event a person can receive carries only its type and a match or room ID', async () => {
    const mine = await probe();
    await mine.join(`user:${victim.id}`, { token: victim.token, private: true });
    const matchId = marker();
    await broadcast([
      { topic: `user:${victim.id}`, event: { type: 'message.created', matchId } },
      { topic: `user:${victim.id}`, event: { type: 'checkin.expiring', roomId } },
    ]);
    await mine.settle();
    for (const r of mine.received) {
      const inner = (r.payload as { payload?: Record<string, unknown> }).payload ?? {};
      expect(Object.keys(inner).sort()).toEqual(expect.arrayContaining(['type']));
      for (const key of Object.keys(inner)) expect(['type', 'matchId', 'roomId']).toContain(key);
      expect(JSON.stringify(r)).not.toContain(attacker.id);
      expect(JSON.stringify(r)).not.toContain(victim.firstName);
    }
  });
});
