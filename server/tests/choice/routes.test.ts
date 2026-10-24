/**
 * C2's routes with the database faked: GET /api/matches/{id} and POST /api/matches/{id}/choice.
 * What each database answer turns into (reply, events, location rows). The real database
 * functions are exercised in live.test.ts, and in A2's pgTAP tests.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GET as getMatchRoute } from '../../app/api/matches/[id]/route';
import { POST as setChoiceRoute } from '../../app/api/matches/[id]/choice/route';
import { STAND_IN_CODE_WORDS } from '@/server/choice/glow-start';
import { mockVerify, USER_ID } from '../helpers/auth';
import { FakeDb, raise, type Result } from './fake-db';
import { call, captureLogs, sentEvents, uuidsIn } from './helpers';

vi.mock('@/server/auth/verify', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@/server/auth/verify')>();
  return { ...actual, verifyAccessToken: vi.fn() };
});

let db: FakeDb;
vi.mock('@/server/choice/db', () => ({ serviceDb: () => db.asDb() }));

vi.mock('@/server/choice/deps', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@/server/choice/deps')>();
  return {
    ...actual,
    notify: vi.fn(async () => ({ realtime: 'sent' })),
    rateLimit: vi.fn(async () => {}),
  };
});
const deps = await import('@/server/choice/deps');
const notify = vi.mocked(deps.notify);
const rateLimit = vi.mocked(deps.rateLimit);

const ME = USER_ID;
const THEM = '9b2f3c4d-5e6f-4a1b-8c2d-3e4f5a6b7c8d';
const MATCH = '64bfd966-bf7f-426a-b7aa-f0dc371bae1a';
const ROOM = 'de000000-0000-4000-8000-000000000001';
const GLOW = '453803c0-4199-465b-a12d-1981639daadd';
const SPOT = 'de000000-0000-4000-8000-0000000005f3';
const CENTER = { lat: 37.8029, lng: -122.4484 };
const AT_VENUE = { latitude: CENTER.lat, longitude: CENTER.lng, accuracy: 12 };
const FAR_AWAY = { latitude: CENTER.lat + 0.02, longitude: CENTER.lng, accuracy: 12 };

const inAnHour = new Date(Date.now() + 3_600_000).toISOString();
const anHourAgo = new Date(Date.now() - 3_600_000).toISOString();

/** What the database functions return: the contract's MatchDetail plus server-only fields. */
function dbMatch(overrides: Record<string, unknown> = {}) {
  return {
    id: MATCH,
    status: 'choosing',
    firstName: 'Blake',
    photoCount: 2,
    roomId: ROOM,
    roomName: 'Glow demo room (test data)',
    createdAt: '2026-10-24T20:10:00.000Z',
    choiceDeadline: inAnHour,
    otherHasChosen: false,
    lastMessageAt: '2026-10-24T20:11:00.000Z',
    userIds: [ME, THEM],
    ...overrides,
  };
}

const dbGlow = {
  id: GLOW,
  matchId: MATCH,
  roomId: ROOM,
  status: 'active',
  color: 'aqua',
  codeWord: 'maple',
  meetingSpot: { id: SPOT, name: 'Water station' },
  startedAt: '2026-10-24T20:12:00.000Z',
  endsAt: '2026-10-24T20:27:00.000Z',
  youMet: false,
  theyMet: false,
  userIds: [ME, THEM],
};

const ok = (data: unknown): Result => ({ data, error: null });

function seedMatch(overrides: Record<string, unknown> = {}) {
  return {
    id: MATCH,
    room_id: ROOM,
    user_a: ME,
    user_b: THEM,
    status: 'choosing',
    choice_deadline: inAnHour,
    ...overrides,
  };
}

function freshDb({
  match = seedMatch(),
  demoMode = false,
  admin = false,
}: { match?: Record<string, unknown> | null; demoMode?: boolean; admin?: boolean } = {}) {
  return new FakeDb({
    matches: match ? [match] : [],
    rooms: [{ id: ROOM, lat: CENTER.lat, lng: CENTER.lng, radius_m: 200, demo_mode: demoMode }],
    admins: admin ? [{ user_id: ME }] : [],
  });
}

const getMatch = (id = MATCH) =>
  call(getMatchRoute, { path: `/api/matches/${id}`, params: { id } });

const choose = (json: unknown, id = MATCH) =>
  call(setChoiceRoute, {
    method: 'POST',
    path: `/api/matches/${id}/choice`,
    params: { id },
    json,
  });

beforeEach(async () => {
  await mockVerify();
  db = freshDb();
});

describe('GET /api/matches/{id}', () => {
  it('answers 401 without a token, before touching the database', async () => {
    const res = await call(getMatchRoute, {
      path: `/api/matches/${MATCH}`,
      params: { id: MATCH },
      token: null,
    });
    expect(res.status).toBe(401);
    expect(db.rpcCalls).toEqual([]);
  });

  it('returns the match with only the contract fields: no user IDs anywhere (P1, D20)', async () => {
    db.rpcHandler = () => ok({ ...dbMatch({ status: 'glowing', glow: dbGlow }), settled: [] });
    const res = await getMatch();
    expect(res.status).toBe(200);
    expect(res.headers.get('cache-control')).toContain('no-store');
    expect(db.rpcCalls).toEqual([
      { name: 'get_match', args: { p_user_id: ME, p_match_id: MATCH } },
    ]);
    expect(res.body).toEqual({
      id: MATCH,
      status: 'glowing',
      firstName: 'Blake',
      photoCount: 2,
      roomId: ROOM,
      roomName: 'Glow demo room (test data)',
      createdAt: '2026-10-24T20:10:00.000Z',
      choiceDeadline: inAnHour,
      otherHasChosen: false,
      glow: {
        id: GLOW,
        status: 'active',
        color: 'aqua',
        codeWord: 'maple',
        meetingSpot: { id: SPOT, name: 'Water station' },
        startedAt: '2026-10-24T20:12:00.000Z',
        endsAt: '2026-10-24T20:27:00.000Z',
        youMet: false,
        theyMet: false,
      },
    });
    expect(uuidsIn(res.body)).not.toContain(ME);
    expect(uuidsIn(res.body)).not.toContain(THEM);
    expect(res.text).not.toMatch(/userIds|lastMessageAt|settled/);
    expect(notify).not.toHaveBeenCalled();
  });

  it('sends the events for timeouts it applied: match.choice and glow.ended to both', async () => {
    const OTHER_MATCH = '11111111-2222-4333-8444-555555555555';
    db.rpcHandler = () =>
      ok({
        ...dbMatch({ status: 'chatting' }),
        settled: [
          { matchId: MATCH, kind: 'choice_timeout', userIds: [ME, THEM] },
          { matchId: OTHER_MATCH, kind: 'glow_expired', userIds: [ME, THEM] },
        ],
      });
    const res = await getMatch();
    expect(res.status).toBe(200);
    expect(sentEvents(notify)).toEqual([
      { type: 'glow.ended', matchId: OTHER_MATCH, to: [ME, THEM].sort() },
      { type: 'match.choice', matchId: MATCH, to: [ME, THEM].sort() },
    ]);
    for (const [, event] of notify.mock.calls)
      expect(Object.keys(event as object).sort()).toEqual(['matchId', 'type']);
  });

  it("answers 404 for a match that doesn't exist, isn't mine or has ended (P11)", async () => {
    db.rpcHandler = () => raise('not_found');
    const res = await getMatch();
    expect(res.status).toBe(404);
    expect(res.body).toEqual({ error: { code: 'not_found', message: 'Not found.' } });
  });

  it('answers 404 for a malformed ID without asking the database', async () => {
    const res = await getMatch('not-a-uuid');
    expect(res.status).toBe(404);
    expect(db.rpcCalls).toEqual([]);
  });

  it('turns an unexpected database failure into a 500 that says nothing about it', async () => {
    db.rpcHandler = () => ({
      data: null,
      error: { message: 'relation "x" for Blake', code: '42P01' },
    });
    const { result: res, lines } = await captureLogs(() => getMatch());
    expect(res.status).toBe(500);
    expect(res.text).not.toContain('Blake');
    expect(lines.join('\n')).not.toContain('Blake');
  });

  it('turns a result that breaks the shape into a 500, logging paths but not values', async () => {
    db.rpcHandler = () => ok({ ...dbMatch({ firstName: 42 }), settled: [] });
    const { result: res, lines } = await captureLogs(() => getMatch());
    expect(res.status).toBe(500);
    expect(lines.join('\n')).not.toContain('Blake');
  });
});

describe('POST /api/matches/{id}/choice · Just chat', () => {
  it('saves Chat without any location lookup, and tells both people the chat opened', async () => {
    db.rpcHandler = () =>
      ok({
        next: 'chat',
        reason: 'chose_chat',
        match: dbMatch({ status: 'chatting', yourChoice: 'chat' }),
        settled: [],
      });
    const res = await choose({ choice: 'chat' });
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({
      next: 'chat',
      reason: 'chose_chat',
      match: { status: 'chatting', yourChoice: 'chat' },
    });
    expect(db.rpcCalls).toEqual([
      { name: 'set_choice', args: { p_user_id: ME, p_match_id: MATCH, p_choice: 'chat' } },
    ]);
    expect(db.reads).toEqual([]);
    expect(db.inserts).toEqual([]);
    expect(sentEvents(notify)).toEqual([
      { type: 'match.choice', matchId: MATCH, to: [ME, THEM].sort() },
    ]);
    expect(rateLimit).not.toHaveBeenCalled(); // the route helper's own api limit is enough
    expect(uuidsIn(res.body)).not.toContain(THEM);
  });

  it('sends nothing when choosing was already over', async () => {
    db.rpcHandler = () =>
      ok({
        next: 'chat',
        reason: 'already_decided',
        match: dbMatch({ status: 'chatting' }),
        settled: [],
      });
    const res = await choose({ choice: 'chat' });
    expect(res.body).toMatchObject({ next: 'chat', reason: 'already_decided' });
    expect(notify).not.toHaveBeenCalled();
  });

  it('opens the chat on a timeout, sending match.choice to both once', async () => {
    db.rpcHandler = () =>
      ok({
        next: 'chat',
        reason: 'timeout',
        match: dbMatch({ status: 'chatting' }),
        settled: [{ matchId: MATCH, kind: 'choice_timeout', userIds: [ME, THEM] }],
      });
    const res = await choose({ choice: 'chat' });
    expect(res.body).toMatchObject({ next: 'chat', reason: 'timeout' });
    expect(sentEvents(notify)).toEqual([
      { type: 'match.choice', matchId: MATCH, to: [ME, THEM].sort() },
    ]);
  });

  it('rejects an unknown choice with 400, naming the field but not the value', async () => {
    const res = await choose({ choice: 'kiss' });
    expect(res.status).toBe(400);
    expect(res.text).not.toContain('kiss');
    expect(db.rpcCalls).toEqual([]);
  });
});

describe('POST /api/matches/{id}/choice · Find each other', () => {
  it("answers 404 for someone else's match before looking at the fix (P11)", async () => {
    db = freshDb({ match: seedMatch({ user_a: '00000000-0000-4000-8000-0000000000aa' }) });
    const res = await choose({ choice: 'find', location: AT_VENUE });
    expect(res.status).toBe(404);
    expect(db.inserts).toEqual([]);
    expect(db.rpcCalls).toEqual([]);
  });

  it("answers 404 for a match that doesn't exist or has ended, the same way", async () => {
    db = freshDb({ match: null });
    expect((await choose({ choice: 'find', location: AT_VENUE })).status).toBe(404);
    db = freshDb({ match: seedMatch({ status: 'ended' }) });
    expect((await choose({ choice: 'find', location: AT_VENUE })).status).toBe(404);
    expect(db.inserts).toEqual([]);
  });

  it('needs a location: 422 location_required', async () => {
    const res = await choose({ choice: 'find' });
    expect(res.status).toBe(422);
    expect(res.body).toMatchObject({ error: { code: 'location_required' } });
    expect(db.rpcCalls).toEqual([]);
  });

  it('refuses a fix outside the room (422 not_in_room) and keeps only the fail (P2)', async () => {
    const { result: res, lines } = await captureLogs(() =>
      choose({ choice: 'find', location: FAR_AWAY }),
    );
    expect(res.status).toBe(422);
    expect(res.body).toMatchObject({ error: { code: 'not_in_room' } });
    expect(db.inserts).toEqual([
      {
        table: 'location_checks',
        values: {
          user_id: ME,
          room_id: ROOM,
          purpose: 'find',
          result: 'fail',
          accuracy_bucket: 'under_20m',
        },
      },
    ]);
    expect(db.rpcCalls).toEqual([]);
    const logs = lines.join('\n');
    expect(logs).not.toContain(String(FAR_AWAY.latitude));
    expect(logs).not.toContain(String(FAR_AWAY.longitude));
    expect(logs).not.toMatch(/latitude|longitude|accuracy"/);
  });

  it('refuses a rough fix (422 location_inaccurate)', async () => {
    const res = await choose({ choice: 'find', location: { ...AT_VENUE, accuracy: 900 } });
    expect(res.status).toBe(422);
    expect(res.body).toMatchObject({ error: { code: 'location_inaccurate' } });
    expect(db.inserts[0]?.values).toMatchObject({ result: 'fail', accuracy_bucket: 'over_500m' });
  });

  it('records a pass, then saves Find; the other person hears match.choice', async () => {
    db.rpcHandler = () =>
      ok({
        next: 'waiting',
        reason: 'other_undecided',
        match: dbMatch({ yourChoice: 'find' }),
        settled: [],
      });
    const { result: res, lines } = await captureLogs(() =>
      choose({ choice: 'find', location: AT_VENUE }),
    );
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({
      next: 'waiting',
      reason: 'other_undecided',
      match: { yourChoice: 'find' },
    });
    expect(db.inserts).toEqual([
      {
        table: 'location_checks',
        values: {
          user_id: ME,
          room_id: ROOM,
          purpose: 'find',
          result: 'pass',
          accuracy_bucket: 'under_20m',
        },
      },
    ]);
    expect(db.rpcCalls).toEqual([
      { name: 'set_choice', args: { p_user_id: ME, p_match_id: MATCH, p_choice: 'find' } },
    ]);
    expect(sentEvents(notify)).toEqual([{ type: 'match.choice', matchId: MATCH, to: [THEM] }]);
    expect(rateLimit).toHaveBeenCalledWith(ME, 'join');
    expect(lines.join('\n')).not.toContain(String(AT_VENUE.longitude));
  });

  it('asks the other person for a fresh check when theirs went stale (match.recheck)', async () => {
    db.rpcHandler = () =>
      ok({
        next: 'waiting',
        reason: 'other_location_stale',
        match: dbMatch({ yourChoice: 'find', otherHasChosen: true }),
        settled: [],
        recheckUserIds: [THEM],
      });
    const res = await choose({ choice: 'find', location: AT_VENUE });
    expect(res.body).toMatchObject({ next: 'waiting', reason: 'other_location_stale' });
    expect(sentEvents(notify)).toEqual([{ type: 'match.recheck', matchId: MATCH, to: [THEM] }]);
    expect(res.text).not.toContain('recheckUserIds');
  });

  it('starts the glow when both chose Find, and answers with the glowing match', async () => {
    db.rpcHandler = (name) => {
      if (name === 'set_choice')
        return ok({
          next: 'glow',
          reason: 'both_find',
          match: dbMatch({ yourChoice: 'find', otherHasChosen: true }),
          settled: [],
        });
      if (name === 'start_glow') return ok({ result: 'started', glow: dbGlow, settled: [] });
      return ok({
        ...dbMatch({ status: 'glowing', yourChoice: 'find', otherHasChosen: true, glow: dbGlow }),
        settled: [],
      });
    };
    const res = await choose({ choice: 'find', location: AT_VENUE });
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({
      next: 'glow',
      reason: 'both_find',
      match: { status: 'glowing', glow: { codeWord: 'maple' } },
    });
    expect(db.rpcCalls.map((c) => c.name)).toEqual(['set_choice', 'start_glow', 'get_match']);
    expect(db.rpcCalls[1]?.args).toEqual({
      p_match_id: MATCH,
      p_code_words: [...STAND_IN_CODE_WORDS],
    });
    expect(sentEvents(notify)).toEqual([
      { type: 'glow.started', matchId: MATCH, to: [ME, THEM].sort() },
    ]);
    expect(uuidsIn(res.body)).not.toContain(THEM);
    expect(res.text).not.toMatch(
      /userIds|"matchId"|"roomId":"de000000-0000-4000-8000-000000000001","status":"active"/,
    );
  });

  it('opens the chat when both chose Find but no code word was free (reason both_find)', async () => {
    db.rpcHandler = (name) => {
      if (name === 'set_choice')
        return ok({
          next: 'glow',
          reason: 'both_find',
          match: dbMatch({ yourChoice: 'find' }),
          settled: [],
        });
      if (name === 'start_glow')
        return ok({
          result: 'chat',
          reason: 'no_code_word',
          matchId: MATCH,
          status: 'chatting',
          userIds: [ME, THEM],
          settled: [],
        });
      return ok({
        ...dbMatch({ status: 'chatting', yourChoice: 'find', otherHasChosen: true }),
        settled: [],
      });
    };
    const res = await choose({ choice: 'find', location: AT_VENUE });
    expect(res.body).toMatchObject({
      next: 'chat',
      reason: 'both_find',
      match: { status: 'chatting' },
    });
    expect(sentEvents(notify)).toEqual([
      { type: 'match.choice', matchId: MATCH, to: [ME, THEM].sort() },
    ]);
  });

  it('opens the chat when someone left the room between the two choices', async () => {
    db.rpcHandler = (name) => {
      if (name === 'set_choice')
        return ok({
          next: 'glow',
          reason: 'both_find',
          match: dbMatch({ yourChoice: 'find' }),
          settled: [],
        });
      if (name === 'start_glow')
        return ok({
          result: 'chat',
          reason: 'not_checked_in',
          matchId: MATCH,
          status: 'chatting',
          userIds: [ME, THEM],
          settled: [],
        });
      return ok({ ...dbMatch({ status: 'chatting' }), settled: [] });
    };
    const res = await choose({ choice: 'find', location: AT_VENUE });
    expect(res.body).toMatchObject({ next: 'chat', reason: 'not_checked_in' });
  });

  it('keeps waiting and asks for a recheck when a check went stale inside start_glow', async () => {
    db.rpcHandler = (name) => {
      if (name === 'set_choice')
        return ok({
          next: 'glow',
          reason: 'both_find',
          match: dbMatch({ yourChoice: 'find' }),
          settled: [],
        });
      if (name === 'start_glow')
        return ok({
          result: 'waiting',
          reason: 'location_stale',
          matchId: MATCH,
          status: 'choosing',
          userIds: [ME, THEM],
          staleUserIds: [THEM],
          settled: [
            {
              matchId: '22222222-3333-4444-8555-666666666666',
              kind: 'glow_expired',
              userIds: [
                '33333333-4444-4555-8666-777777777777',
                '44444444-5555-4666-8777-888888888888',
              ],
            },
          ],
        });
      return ok({ ...dbMatch({ yourChoice: 'find', otherHasChosen: true }), settled: [] });
    };
    const res = await choose({ choice: 'find', location: AT_VENUE });
    expect(res.body).toMatchObject({ next: 'waiting', reason: 'other_location_stale' });
    expect(sentEvents(notify)).toEqual([
      {
        type: 'glow.ended',
        matchId: '22222222-3333-4444-8555-666666666666',
        to: ['33333333-4444-4555-8666-777777777777', '44444444-5555-4666-8777-888888888888'],
      },
      { type: 'match.recheck', matchId: MATCH, to: [THEM] },
    ]);
  });

  it('never looks at the fix once choosing is over or its window ran out (C2-D1)', async () => {
    db = freshDb({ match: seedMatch({ status: 'chatting' }) });
    db.rpcHandler = () =>
      ok({
        next: 'chat',
        reason: 'already_decided',
        match: dbMatch({ status: 'chatting' }),
        settled: [],
      });
    expect((await choose({ choice: 'find', location: FAR_AWAY })).status).toBe(200);
    expect(db.inserts).toEqual([]);
    expect(db.reads).toEqual(['matches']);

    db = freshDb({ match: seedMatch({ choice_deadline: anHourAgo }) });
    db.rpcHandler = () =>
      ok({
        next: 'chat',
        reason: 'timeout',
        match: dbMatch({ status: 'chatting' }),
        settled: [{ matchId: MATCH, kind: 'choice_timeout', userIds: [ME, THEM] }],
      });
    const res = await choose({ choice: 'find' });
    expect(res.body).toMatchObject({ next: 'chat', reason: 'timeout' });
    expect(db.inserts).toEqual([]);
  });

  it('lets an admin skip the check in a demo mode room, and records the skip', async () => {
    db = freshDb({ demoMode: true, admin: true });
    db.rpcHandler = () =>
      ok({
        next: 'waiting',
        reason: 'other_undecided',
        match: dbMatch({ yourChoice: 'find' }),
        settled: [],
      });
    const { result: res, lines } = await captureLogs(() =>
      choose({ choice: 'find', location: FAR_AWAY }),
    );
    expect(res.status).toBe(200);
    expect(db.inserts[0]?.values).toEqual({
      user_id: ME,
      room_id: ROOM,
      purpose: 'find',
      result: 'demo_skip',
      accuracy_bucket: null,
    });
    expect(lines.join('\n')).toContain('choice.find_check.demo_skip');
  });

  it("doesn't let a non-admin skip the check in a demo mode room", async () => {
    db = freshDb({ demoMode: true, admin: false });
    const res = await choose({ choice: 'find', location: FAR_AWAY });
    expect(res.status).toBe(422);
    expect(db.inserts[0]?.values).toMatchObject({ result: 'fail' });
  });

  it('passes the database refusing a stale Find on as 422 location_required', async () => {
    db.rpcHandler = () => raise('location_required');
    const res = await choose({ choice: 'find', location: AT_VENUE });
    expect(res.status).toBe(422);
    expect(res.body).toMatchObject({ error: { code: 'location_required' } });
  });
});
