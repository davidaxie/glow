/**
 * P2: user coordinates are never stored or logged; only pass or fail is kept.
 *
 * Sends location fixes with digits that appear nowhere else (inside the room, outside it,
 * and too inaccurate) through the real join route (and C2's Find choice once it's merged),
 * then looks for those digits everywhere the server could have put them: every log line,
 * every error report, every reply, and every row of every table the service role can read.
 */
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { resetEnvCacheForTests } from '@/env';
import { call, isStub } from './helpers/api';
import { LIVE, supa, type Live } from './helpers/live';
import { World, type Card, type Person } from './helpers/world';

const reports = vi.hoisted(() => ({ calls: [] as unknown[] }));
vi.mock('@/server/observability', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@/server/observability')>();
  return {
    ...actual,
    captureError: vi.fn((...args: unknown[]) => {
      reports.calls.push(args);
    }),
  };
});

const live = LIVE as Live;
let world: World;
let roomId: string;
let roomCode: string;
let person: Person;
let other: Person;
let card: Card;
let otherCard: Card;
const logged: string[] = [];
const replies: string[] = [];

// Room center is 37.8029, -122.4484. These fixes add digits no other value has.
const FIXES = {
  inside: { latitude: 37.80291357913, longitude: -122.44842468024, accuracy: 13.579246 },
  outside: { latitude: 37.82093579135, longitude: -122.44846802468, accuracy: 24.680135 },
  inaccurate: { latitude: 37.80297913579, longitude: -122.44840246802, accuracy: 913.57924 },
};
const DIGITS = Object.values(FIXES).flatMap((f) => [
  String(f.latitude).slice(4),
  String(f.longitude).slice(5),
  String(f.accuracy),
]);
const found = (text: string) => DIGITS.filter((d) => text.includes(d));

beforeAll(async () => {
  if (!LIVE) return;
  world = new World(live);
  [person, other] = await Promise.all([world.person('woman', ['man']), world.person('man', ['woman'])]);
  roomId = await world.room();
  const room = await world.db.from('rooms').select('code').eq('id', roomId).single();
  roomCode = room.data!.code;
  card = await world.checkIn(person, roomId);
  otherCard = await world.checkIn(other, roomId);
}, 60_000);

beforeEach(() => {
  if (!LIVE) return;
  process.env.SUPABASE_URL = live.url;
  process.env.SUPABASE_ANON_KEY = live.anonKey;
  process.env.SUPABASE_SERVICE_ROLE_KEY = live.serviceKey;
  resetEnvCacheForTests();
  for (const method of ['log', 'info', 'warn', 'error', 'debug'] as const) {
    vi.spyOn(console, method).mockImplementation((...args: unknown[]) => {
      logged.push(args.map((a) => (typeof a === 'string' ? a : JSON.stringify(a))).join(' '));
    });
  }
});

afterAll(async () => {
  if (LIVE) await world.cleanup();
});

describe.skipIf(!LIVE)('P2: coordinates go nowhere (live)', () => {
  it('the join route answers pass, fail and try again, and keeps only that', async () => {
    const join = (location: (typeof FIXES)[keyof typeof FIXES]) =>
      call('joinRoom', {
        token: person.token,
        params: { id: roomId },
        body: { access: { kind: 'code', code: roomCode }, location },
      });
    const inside = await join(FIXES.inside);
    const outside = await join(FIXES.outside);
    const inaccurate = await join(FIXES.inaccurate);
    expect(inside.status).toBe(200);
    expect(outside.status).toBe(422);
    expect(inaccurate.status).toBe(422);
    replies.push(inside.text, outside.text, inaccurate.text);

    const checks = await world.db
      .from('location_checks')
      .select('*')
      .eq('user_id', person.id)
      .eq('purpose', 'join');
    const results = (checks.data ?? []).map((c) => c.result).sort();
    expect(results).toEqual(expect.arrayContaining(['fail', 'pass']));
    for (const row of checks.data ?? []) {
      expect(Object.keys(row).sort()).toEqual(
        ['accuracy_bucket', 'created_at', 'id', 'purpose', 'result', 'room_id', 'user_id'].sort(),
      );
    }
  });

  it("C2's Find choice keeps only pass or fail too", async (ctx) => {
    if (await isStub('setChoice')) ctx.skip();
    const matchId = await world.match(person, card, other, otherCard);
    for (const location of [FIXES.inside, FIXES.outside, FIXES.inaccurate]) {
      const reply = await call('setChoice', {
        token: person.token,
        params: { id: matchId },
        body: { choice: 'find', location },
      });
      replies.push(reply.text);
    }
  });

  it('no log line, error report, reply or table row holds a single coordinate digit', async () => {
    // Controls: the scan finds every digit string in the fixes themselves, and the spy saw
    // the route's own log lines.
    expect(found(JSON.stringify(FIXES))).toHaveLength(DIGITS.length);
    expect(logged.some((line) => line.includes('"operation":"joinRoom"'))).toBe(true);
    for (const line of logged) expect(found(line), line).toEqual([]);
    expect(found(JSON.stringify(reports.calls))).toEqual([]);
    for (const reply of replies) expect(found(reply), reply).toEqual([]);

    // Every table and view the Data API knows about, read as the server would.
    const root = await supa(live, 'GET', '/rest/v1/', { key: 'service' });
    const tables = Object.keys((root.json.paths ?? {}) as Record<string, unknown>)
      .map((p) => p.slice(1))
      .filter((p) => p && !p.startsWith('rpc/'));
    expect(tables).toEqual(expect.arrayContaining(['location_checks', 'checkins', 'profiles']));
    for (const table of tables) {
      const rows = await supa(live, 'GET', `/rest/v1/${table}?select=*&limit=10000`, { key: 'service' });
      expect(found(JSON.stringify(rows.json)), table).toEqual([]);
    }
  });
});
