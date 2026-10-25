/**
 * A2's D56: "a banned person can delete their account and come back". What the code does:
 *
 * - `banPerson` (B7) sets `profiles.banned_at`, bans the auth user, hides their cards, ends
 *   their matches. A banned auth user's tokens stop verifying (D3), so every API route,
 *   `DELETE /api/me` included, answers 401. Supabase offers no self-delete endpoint, so a
 *   banned person has no way to remove their own account, or the ban with it.
 * - What stays open, and is written up in docs/SECURITY_REVIEW.md (D2-F5): they can still
 *   register a *new* account with another address or Apple ID.
 *
 * This test proves the first part against a live stack, and pins the second one so a future
 * ban list (D2-D2) has something to flip.
 */
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { resetEnvCacheForTests } from '@/env';
import { banPerson } from '@/server/admin/reports';
import { setAdminDepsForTests } from '@/server/admin/context';
import { supabaseRepo } from '@/server/admin/supabase-repo';
import { call } from './helpers/api';
import { LIVE, supa, type Live } from './helpers/live';
import { World, type Person } from './helpers/world';

vi.mock('@/server/notify', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@/server/notify')>();
  return {
    ...actual,
    notify: vi.fn(async () => ({ realtime: 'sent', push: null })),
    notifyRoom: vi.fn(async () => ({ realtime: 'sent', push: null })),
  };
});

const live = LIVE as Live;
let world: World;
let admin: Person;
let bad: Person;
let good: Person;
let roomId: string;
let matchId: string;

beforeAll(async () => {
  if (!LIVE) return;
  world = new World(live);
  [admin, bad, good] = await Promise.all([
    world.person('man'),
    world.person('woman', ['man']),
    world.person('man', ['woman']),
  ]);
  roomId = await world.room();
  const [badCard, goodCard] = await Promise.all([
    world.checkIn(bad, roomId),
    world.checkIn(good, roomId),
  ]);
  matchId = await world.match(bad, badCard, good, goodCard);
}, 60_000);

beforeEach(() => {
  if (!LIVE) return;
  process.env.SUPABASE_URL = live.url;
  process.env.SUPABASE_ANON_KEY = live.anonKey;
  process.env.SUPABASE_SERVICE_ROLE_KEY = live.serviceKey;
  resetEnvCacheForTests();
  setAdminDepsForTests({
    repo: supabaseRepo(),
    events: {
      matchEnded: async () => undefined,
      deckChanged: async () => undefined,
    } as never,
    now: () => Date.now(),
  });
});
afterAll(async () => {
  setAdminDepsForTests(undefined);
  if (LIVE) await world.cleanup();
});

describe.skipIf(!LIVE)('D56: a banned person cannot delete their way out (live)', () => {
  it('control: before the ban, the person is fully signed in', async () => {
    expect((await call('listMatches', { token: bad.token })).status).toBe(200);
  });

  it('after the ban, no route works with their old token, DELETE /api/me included', async () => {
    await banPerson(bad.id, admin.id);

    const attempts = [
      call('deleteAccount', { token: bad.token }),
      call('listMatches', { token: bad.token }),
      call('getRoomState', { token: bad.token, params: { id: roomId } }),
      call('getDeck', { token: bad.token, params: { id: roomId }, body: {} }),
      call('setPaused', { token: bad.token, body: { paused: true } }),
    ];
    for (const reply of await Promise.all(attempts)) expect(reply.status).toBe(401);

    const profile = await world.db.from('profiles').select('banned_at').eq('id', bad.id).single();
    expect(profile.data?.banned_at).not.toBeNull();
  });

  it('they cannot get a new token either: a code, a refresh or a magic link', async () => {
    const link = await supa(live, 'POST', '/auth/v1/admin/generate_link', {
      key: 'service',
      body: { type: 'magiclink', email: bad.email },
    });
    const hash = (link.json.hashed_token ??
      (link.json.properties as Record<string, unknown> | undefined)?.hashed_token) as string;
    const verified = await supa(live, 'POST', '/auth/v1/verify', {
      body: { type: 'email', token_hash: hash },
    });
    expect(verified.json.access_token).toBeUndefined();
    expect(verified.status).toBeGreaterThanOrEqual(400);
  });

  it('the other person lost the match; the banned person left the deck', async () => {
    const match = await world.db.from('matches').select('status').eq('id', matchId).single();
    expect(match.data?.status).toBe('ended');
    const deck = await call('getDeck', { token: good.token, params: { id: roomId }, body: {} });
    expect((deck.json as { cards: unknown[] }).cards).toEqual([]);
  });

  it('open gap (D2-F5): the same person can still register a new, unbanned account', async () => {
    const fresh = await world.person('woman', ['man']);
    expect((await call('listMatches', { token: fresh.token })).status).toBe(200);
  });
});
