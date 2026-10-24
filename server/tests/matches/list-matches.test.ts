/**
 * Owner: B4. Unit tests for GET /api/matches, with the database and notify mocked.
 */
import { NextRequest } from 'next/server';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { zMatchList } from '@/contracts';
import { fakeAccessToken, mockVerify, USER_ID } from '../helpers/auth';

vi.mock('@/server/auth/verify', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@/server/auth/verify')>();
  return { ...actual, verifyAccessToken: vi.fn() };
});
vi.mock('@/server/deck/db', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@/server/deck/db')>();
  return { ...actual, rpc: vi.fn() };
});
vi.mock('@/server/deck/dependencies', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@/server/deck/dependencies')>();
  return { ...actual, notify: vi.fn(async () => {}) };
});

const { rpc } = await import('@/server/deck/db');
const { notify } = await import('@/server/deck/dependencies');
const { GET } = await import('../../app/api/matches/route');

const OTHER_USER = '7e570000-0000-4000-8000-000000000002';
const M1 = '64bfd966-bf7f-426a-b7aa-f0dc371bae1a';
const M2 = '453803c0-4199-465b-a12d-1981639daadd';

/** What list_matches returns per match: MatchDetail plus server-only fields. */
const detail = (id: string, status: string, extra: Record<string, unknown> = {}) => ({
  id,
  status,
  firstName: 'Blake',
  photoCount: 2,
  roomId: 'de000000-0000-4000-8000-000000000001',
  roomName: 'Glow demo room (test data)',
  createdAt: '2026-10-24T20:10:00.000Z',
  choiceDeadline: '2026-10-24T20:20:00.000Z',
  otherHasChosen: false,
  userIds: [USER_ID, OTHER_USER],
  ...extra,
});

function call(token: string | null = fakeAccessToken()) {
  const req = new NextRequest('http://localhost/api/matches', {
    headers: token ? { authorization: `Bearer ${token}` } : {},
  });
  return GET(req, { params: Promise.resolve({}) });
}

beforeEach(async () => {
  await mockVerify();
});

describe('GET /api/matches', () => {
  it('lists matches with only MatchSummary fields: never a user ID', async () => {
    vi.mocked(rpc).mockResolvedValue({
      matches: [
        detail(M1, 'choosing'),
        detail(M2, 'met', { lastMessageAt: '2026-10-24T21:00:00.000Z', yourChoice: 'find' }),
      ],
    } as never);
    const res = await call();
    expect(res.status).toBe(200);
    const body = (await res.json()) as { matches: Record<string, unknown>[] };
    expect(zMatchList.parse(body)).toEqual(body);
    expect(body.matches.map((m) => m.id)).toEqual([M1, M2]);
    expect(Object.keys(body.matches[1]!).sort()).toEqual([
      'choiceDeadline',
      'createdAt',
      'firstName',
      'id',
      'lastMessageAt',
      'roomName',
      'status',
    ]);
    const text = JSON.stringify(body);
    expect(text).not.toContain(OTHER_USER);
    expect(text).not.toContain(USER_ID);
    expect(rpc).toHaveBeenCalledExactlyOnceWith('list_matches', { p_user_id: USER_ID });
  });

  it('is an empty list when there are none', async () => {
    vi.mocked(rpc).mockResolvedValue({ matches: [] } as never);
    const res = await call();
    expect(await res.json()).toEqual({ matches: [] });
    expect(notify).not.toHaveBeenCalled();
  });

  it('tells both people about timeouts it applied: match.choice and glow.ended', async () => {
    vi.mocked(rpc).mockResolvedValue({
      matches: [detail(M1, 'chatting'), detail(M2, 'chatting')],
      settled: [
        { matchId: M1, kind: 'choice_timeout', userIds: [USER_ID, OTHER_USER] },
        { matchId: M2, kind: 'glow_expired', userIds: [USER_ID, OTHER_USER] },
      ],
    } as never);
    const res = await call();
    expect(res.status).toBe(200);
    expect(notify).toHaveBeenCalledTimes(4);
    expect(notify).toHaveBeenCalledWith(OTHER_USER, { type: 'match.choice', matchId: M1 });
    expect(notify).toHaveBeenCalledWith(USER_ID, { type: 'match.choice', matchId: M1 });
    expect(notify).toHaveBeenCalledWith(OTHER_USER, { type: 'glow.ended', matchId: M2 });
    expect(notify).toHaveBeenCalledWith(USER_ID, { type: 'glow.ended', matchId: M2 });
    expect(JSON.stringify(await res.clone().json())).not.toContain('settled');
  });

  it('401 without a token', async () => {
    const res = await call(null);
    expect(res.status).toBe(401);
    expect(rpc).not.toHaveBeenCalled();
  });
});
