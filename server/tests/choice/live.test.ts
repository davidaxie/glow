/**
 * C2's routes against a real local Supabase (CI starts one before Vitest), with A2's real
 * `get_match`, `set_choice` and `start_glow`. Every combination of choices, the timeout, a
 * stale location check, someone leaving the room, and the location rules.
 *
 * Only Supabase Auth's token check and `notify` are mocked: the test signs each person in by
 * ID, and reads what would have been sent. Each test makes its own room, people, check-ins
 * and match, and deletes them afterwards. Point it at your own stack with GLOW_SUPABASE_URL
 * (from `scripts/agent-env.sh C2 --own-db`). Without a reachable Supabase, it's skipped.
 */
import { randomUUID } from 'node:crypto';
import { createClient } from '@supabase/supabase-js';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import type { Database } from '@/contracts';
import { resetEnvCacheForTests } from '@/env';
import { GET as getMatchRoute } from '../../app/api/matches/[id]/route';
import { POST as setChoiceRoute } from '../../app/api/matches/[id]/choice/route';
import { fakeAccessToken, mockVerify } from '../helpers/auth';
import { call, sentEvents, uuidsIn } from './helpers';

vi.mock('@/server/auth/verify', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@/server/auth/verify')>();
  return { ...actual, verifyAccessToken: vi.fn() };
});

// One `notify` mock for everything that sends. B5's notifySettled is played by a stand-in that
// sends each settled entry the way the real helper does (B5 tests the real one).
const sends = vi.hoisted(() => ({ notify: vi.fn() }));
const settledType = { choice_timeout: 'match.choice', glow_expired: 'glow.ended' } as const;

vi.mock('@/server/choice/deps', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@/server/choice/deps')>();
  return {
    ...actual,
    notify: sends.notify,
    notifySettled: async (
      settled: { matchId: string; kind: keyof typeof settledType; userIds: string[] }[],
    ) => {
      for (const { matchId, kind, userIds } of settled ?? []) {
        await sends.notify(userIds, { type: settledType[kind], matchId });
      }
    },
  };
});
vi.mock('@/server/glow/dependencies', () => ({ notify: sends.notify }));
const notify = vi.mocked(sends.notify);

/** The standard keys of every local `supabase start`. Public, and only valid on 127.0.0.1. */
const LOCAL_ANON = 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH';
const LOCAL_SERVICE = 'sb_secret_N7UND0UgjKTVK-Uodkm0Hg_xSvEMPvz';
const LIVE_URL = process.env.GLOW_SUPABASE_URL ?? 'http://127.0.0.1:54421';

async function reachable(): Promise<boolean> {
  try {
    const res = await fetch(`${LIVE_URL}/auth/v1/health`, {
      headers: { apikey: LOCAL_ANON },
      signal: AbortSignal.timeout(1500),
    });
    if (!res.ok) return false;
    // Needs migration 0002 (settled, recheckUserIds, start_glow results). Its room_days table
    // is the simplest sign that it's there.
    const probe = await admin().from('room_days').select('user_id').limit(1);
    return probe.error === null;
  } catch {
    return false;
  }
}

const admin = () =>
  createClient<Database>(LIVE_URL, LOCAL_SERVICE, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

const supabaseUp = await reachable();

const CENTER = { lat: 37.8029, lng: -122.4484 };
const AT_VENUE = { latitude: CENTER.lat, longitude: CENTER.lng, accuracy: 15 };
const FAR_AWAY = { latitude: CENTER.lat + 0.02, longitude: CENTER.lng, accuracy: 15 };

type Pair = { a: string; b: string; matchId: string };

let roomId: string;
const people: string[] = [];

async function newPerson(firstName: string, gender: 'woman' | 'man'): Promise<string> {
  const db = admin();
  const email = `c2-test-${randomUUID().slice(0, 12)}@glow.test`;
  const { data, error } = await db.auth.admin.createUser({ email, email_confirm: true });
  if (error || !data.user) throw error ?? new Error('no user');
  const id = data.user.id;
  people.push(id);
  const update = await db
    .from('profiles')
    .update({
      first_name: firstName,
      birthdate: '1995-05-05',
      gender,
      show_me: gender === 'woman' ? ['man'] : ['woman'],
      onboarding_step: 'complete',
    })
    .eq('id', id);
  if (update.error) throw update.error;
  return id;
}

async function checkIn(userId: string): Promise<string> {
  const id = randomUUID();
  const { error } = await admin()
    .from('checkins')
    .insert({
      id,
      room_id: roomId,
      user_id: userId,
      card_path: `${roomId}/${id}.jpg`,
      top_color: 'green',
      expires_at: new Date(Date.now() + 3 * 3_600_000).toISOString(),
    });
  if (error) throw error;
  return id;
}

/** Two checked-in people and a fresh match between them, in the test room. */
async function newPair(): Promise<Pair> {
  const alex = await newPerson('Alex', 'woman');
  const blake = await newPerson('Blake', 'man');
  await checkIn(alex);
  await checkIn(blake);
  const [userA, userB] = [alex, blake].sort();
  const { data, error } = await admin()
    .from('matches')
    .insert({
      room_id: roomId,
      user_a: userA!,
      user_b: userB!,
      choice_deadline: new Date(Date.now() + 600_000).toISOString(),
    })
    .select('id')
    .single();
  if (error || !data) throw error ?? new Error('no match');
  return { a: alex, b: blake, matchId: data.id };
}

async function as(userId: string) {
  await mockVerify({ kind: 'valid', user: { id: userId, email: 'person@glow.test' } });
}

async function choose(userId: string, matchId: string, json: unknown) {
  await as(userId);
  return call(setChoiceRoute, {
    method: 'POST',
    path: `/api/matches/${matchId}/choice`,
    params: { id: matchId },
    json,
    token: fakeAccessToken({ sub: userId }),
  });
}

async function getMatch(userId: string, matchId: string) {
  await as(userId);
  return call(getMatchRoute, {
    path: `/api/matches/${matchId}`,
    params: { id: matchId },
    token: fakeAccessToken({ sub: userId }),
  });
}

const find = { choice: 'find', location: AT_VENUE } as const;
const chat = { choice: 'chat' } as const;

async function locationChecks(userId: string) {
  const { data } = await admin()
    .from('location_checks')
    .select('*')
    .eq('user_id', userId)
    .order('created_at');
  return data ?? [];
}

describe.skipIf(!supabaseUp)('choosing, against the real database', () => {
  beforeAll(async () => {
    const slug = `c2-test-${randomUUID().slice(0, 8)}`;
    const { data, error } = await admin()
      .from('rooms')
      .insert({
        slug,
        name: 'C2 test room',
        lat: CENTER.lat,
        lng: CENTER.lng,
        radius_m: 200,
        starts_at: new Date(Date.now() - 3_600_000).toISOString(),
        ends_at: new Date(Date.now() + 6 * 3_600_000).toISOString(),
      })
      .select('id')
      .single();
    if (error || !data) throw error ?? new Error('no room');
    roomId = data.id;
    const spots = ['Main entrance', 'Food line', 'Water station'].map((name, sort) => ({
      room_id: roomId,
      name,
      sort,
    }));
    const added = await admin().from('meeting_spots').insert(spots);
    if (added.error) throw added.error;
  });

  beforeEach(() => {
    process.env.SUPABASE_URL = LIVE_URL;
    process.env.SUPABASE_ANON_KEY = LOCAL_ANON;
    process.env.SUPABASE_SERVICE_ROLE_KEY = LOCAL_SERVICE;
    resetEnvCacheForTests();
  });

  afterEach(async () => {
    const db = admin();
    for (const id of people.splice(0)) await db.auth.admin.deleteUser(id);
  });

  afterAll(async () => {
    if (roomId) await admin().from('rooms').delete().eq('id', roomId);
  });

  it('Find and Find: the glow starts, both hear glow.started, and both see the same glow', async () => {
    const { a, b, matchId } = await newPair();

    const first = await choose(a, matchId, find);
    expect(first.status).toBe(200);
    expect(first.body).toMatchObject({
      next: 'waiting',
      reason: 'other_undecided',
      match: { status: 'choosing', yourChoice: 'find' },
    });
    expect(sentEvents(notify)).toEqual([{ type: 'match.choice', matchId, to: [b] }]);
    notify.mockClear();

    const second = await choose(b, matchId, find);
    expect(second.status).toBe(200);
    expect(second.body).toMatchObject({
      next: 'glow',
      reason: 'both_find',
      match: { status: 'glowing', yourChoice: 'find', otherHasChosen: true, firstName: 'Alex' },
    });
    expect(sentEvents(notify)).toEqual([{ type: 'glow.started', matchId, to: [a, b].sort() }]);

    const glowB = (second.body as { match: { glow: { color: string; codeWord: string } } }).match
      .glow;
    const seenByA = await getMatch(a, matchId);
    expect(seenByA.body).toMatchObject({
      status: 'glowing',
      firstName: 'Blake',
      glow: { color: glowB.color, codeWord: glowB.codeWord },
    });
    for (const reply of [first, second, seenByA]) {
      expect(uuidsIn(reply.body)).not.toContain(a);
      expect(uuidsIn(reply.body)).not.toContain(b);
    }
    // Each Find left exactly one passed check, and no coordinates (P2).
    for (const person of [a, b]) {
      const checks = await locationChecks(person);
      expect(checks).toHaveLength(1);
      expect(checks[0]).toMatchObject({
        purpose: 'find',
        result: 'pass',
        accuracy_bucket: 'under_20m',
      });
      expect(JSON.stringify(checks)).not.toContain(String(CENTER.lng));
    }
  });

  it('Find and Chat: the chat opens for both', async () => {
    const { a, b, matchId } = await newPair();
    await choose(a, matchId, find);
    notify.mockClear();

    const second = await choose(b, matchId, chat);
    expect(second.body).toMatchObject({
      next: 'chat',
      reason: 'chose_chat',
      match: { status: 'chatting', yourChoice: 'chat' },
    });
    expect(sentEvents(notify)).toEqual([{ type: 'match.choice', matchId, to: [a, b].sort() }]);
    expect((await getMatch(a, matchId)).body).toMatchObject({
      status: 'chatting',
      yourChoice: 'find',
    });
  });

  it('Chat and Find: the chat opened at the first Chat, and the late Find changes nothing', async () => {
    const { a, b, matchId } = await newPair();
    const first = await choose(a, matchId, chat);
    expect(first.body).toMatchObject({
      next: 'chat',
      reason: 'chose_chat',
      match: { status: 'chatting' },
    });
    notify.mockClear();

    const second = await choose(b, matchId, find);
    expect(second.body).toMatchObject({
      next: 'chat',
      reason: 'already_decided',
      match: { status: 'chatting' },
    });
    expect(notify).not.toHaveBeenCalled();
    expect(await locationChecks(b)).toEqual([]); // the fix was never looked at (C2-D1)
  });

  it('Chat and Chat: the chat opens at the first, and the second is already decided', async () => {
    const { a, b, matchId } = await newPair();
    expect((await choose(a, matchId, chat)).body).toMatchObject({
      next: 'chat',
      reason: 'chose_chat',
    });
    expect((await choose(b, matchId, chat)).body).toMatchObject({
      next: 'chat',
      reason: 'already_decided',
      match: { status: 'chatting' },
    });
  });

  it('Timeout: once the window runs out, the chat opens and both hear it once', async () => {
    const { a, b, matchId } = await newPair();
    await choose(a, matchId, find);
    await admin()
      .from('matches')
      .update({ choice_deadline: new Date(Date.now() - 1000).toISOString() })
      .eq('id', matchId);
    notify.mockClear();

    const seen = await getMatch(b, matchId);
    expect(seen.body).toMatchObject({ status: 'chatting' });
    expect(sentEvents(notify)).toEqual([{ type: 'match.choice', matchId, to: [a, b].sort() }]);
    notify.mockClear();

    // Already settled: a late Find is just too late, and nobody hears it twice.
    const late = await choose(b, matchId, find);
    expect(late.body).toMatchObject({ next: 'chat', reason: 'already_decided' });
    expect(notify).not.toHaveBeenCalled();
  });

  it('Timeout, applied by the choice itself: the late chooser opens the chat for both', async () => {
    const { a, b, matchId } = await newPair();
    await admin()
      .from('matches')
      .update({ choice_deadline: new Date(Date.now() - 1000).toISOString() })
      .eq('id', matchId);
    const late = await choose(a, matchId, chat);
    expect(late.body).toMatchObject({
      next: 'chat',
      reason: 'timeout',
      match: { status: 'chatting' },
    });
    expect(sentEvents(notify)).toEqual([{ type: 'match.choice', matchId, to: [a, b].sort() }]);
  });

  it('A stale Find: the first person is asked to recheck, and their fresh Find starts the glow', async () => {
    const { a, b, matchId } = await newPair();
    await choose(a, matchId, find);
    // A's check is now older than GEO_FRESHNESS_FOR_GLOW.
    await admin()
      .from('location_checks')
      .update({ created_at: new Date(Date.now() - 3 * 60_000).toISOString() })
      .eq('user_id', a);
    notify.mockClear();

    const second = await choose(b, matchId, find);
    expect(second.body).toMatchObject({
      next: 'waiting',
      reason: 'other_location_stale',
      match: { status: 'choosing' },
    });
    expect(sentEvents(notify)).toEqual([{ type: 'match.recheck', matchId, to: [a] }]);
    notify.mockClear();

    const again = await choose(a, matchId, find);
    expect(again.body).toMatchObject({
      next: 'glow',
      reason: 'both_find',
      match: { status: 'glowing' },
    });
    expect(sentEvents(notify)).toEqual([{ type: 'glow.started', matchId, to: [a, b].sort() }]);
  });

  it('Someone left the room: both chose Find, and the chat opens instead', async () => {
    const { a, b, matchId } = await newPair();
    await choose(a, matchId, find);
    await admin().from('checkins').update({ left_at: new Date().toISOString() }).eq('user_id', a);
    notify.mockClear();

    const second = await choose(b, matchId, find);
    expect(second.body).toMatchObject({
      next: 'chat',
      reason: 'not_checked_in',
      match: { status: 'chatting' },
    });
    expect(sentEvents(notify)).toEqual([{ type: 'match.choice', matchId, to: [a, b].sort() }]);
  });

  it('Outside the room: 422 not_in_room, a fail on record, and the choice not saved', async () => {
    const { a, matchId } = await newPair();
    const res = await choose(a, matchId, { choice: 'find', location: FAR_AWAY });
    expect(res.status).toBe(422);
    expect(res.body).toMatchObject({ error: { code: 'not_in_room' } });
    expect(await locationChecks(a)).toMatchObject([{ purpose: 'find', result: 'fail' }]);
    expect((await getMatch(a, matchId)).body).not.toHaveProperty('yourChoice');
  });

  it("Someone else's match: 404 for reading and for choosing, and no check recorded (P11)", async () => {
    const { matchId } = await newPair();
    const stranger = await newPerson('Casey', 'woman');
    expect((await getMatch(stranger, matchId)).status).toBe(404);
    expect((await choose(stranger, matchId, find)).status).toBe(404);
    expect((await choose(stranger, matchId, chat)).status).toBe(404);
    expect(await locationChecks(stranger)).toEqual([]);
    expect((await getMatch(stranger, randomUUID())).status).toBe(404);
  });

  it('An ended match is 404 for both people', async () => {
    const { a, b, matchId } = await newPair();
    await admin()
      .from('matches')
      .update({ status: 'ended', ended_at: new Date().toISOString() })
      .eq('id', matchId);
    expect((await getMatch(a, matchId)).status).toBe(404);
    expect((await choose(b, matchId, chat)).status).toBe(404);
  });
});
