import { NextRequest } from 'next/server';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { GLOW_ENDED_RETENTION_SECONDS } from '@/contracts';
import { notFound } from '@/server/http';
import { activeGlowId, rpc } from '@/server/glow/db';
import { notify } from '@/server/glow/dependencies';
import { fakeAccessToken, mockVerify, USER_ID } from '../helpers/auth';
import { GLOW_ID, GLOW_KEYS, glowRow, MATCH_ID, OTHER_ID } from './fixtures';

// Owner: C3. The three glow routes through A1's route helper: sign-in, 404 (P11), contract-only
// replies (P1), and exactly which events each one sends.

vi.mock('@/server/auth/verify', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/server/auth/verify')>()),
  verifyAccessToken: vi.fn(),
}));
vi.mock('@/server/glow/db', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/server/glow/db')>()),
  rpc: vi.fn(),
  activeGlowId: vi.fn(),
}));
vi.mock('@/server/glow/dependencies', () => ({
  notify: vi.fn(async () => ({ realtime: 'sent', push: null })),
}));

const getRoute = (await import('../../app/api/matches/[id]/glow/route')).GET;
const metRoute = (await import('../../app/api/matches/[id]/glow/met/route')).POST;
const cancelRoute = (await import('../../app/api/matches/[id]/glow/cancel/route')).POST;

const BOTH = [USER_ID, OTHER_ID];

function call(
  handler: typeof getRoute,
  { method = 'GET', body, token = fakeAccessToken(), id = MATCH_ID } = {} as {
    method?: string;
    body?: unknown;
    token?: string | null;
    id?: string;
  },
) {
  const req = new NextRequest(`http://localhost/api/matches/${id}/glow`, {
    method,
    headers: {
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      ...(body !== undefined ? { 'content-type': 'application/json' } : {}),
    },
    ...(body !== undefined ? { body: JSON.stringify(body) } : {}),
  });
  return handler(req, { params: Promise.resolve({ id }) });
}

const sent = () => vi.mocked(notify).mock.calls.map(([ids, event]) => [ids, event]);
const recently = (secondsAgo: number) => new Date(Date.now() - secondsAgo * 1000).toISOString();

beforeEach(async () => {
  await mockVerify();
  vi.mocked(activeGlowId).mockResolvedValue(GLOW_ID);
});

describe('GET /api/matches/{id}/glow', () => {
  it('needs sign-in, and asks the database nothing without it', async () => {
    const res = await call(getRoute, { token: null });
    expect(res.status).toBe(401);
    expect(rpc).not.toHaveBeenCalled();
  });

  it('answers the glow from my side, with only the contract fields (P1)', async () => {
    vi.mocked(rpc).mockResolvedValue({
      id: MATCH_ID,
      firstName: 'Blake',
      userIds: BOTH,
      glow: glowRow(USER_ID, { theyMet: true }),
      settled: [],
    } as never);
    const res = await call(getRoute);
    expect(res.status).toBe(200);
    expect(res.headers.get('cache-control')).toContain('no-store');
    const body = (await res.json()) as Record<string, unknown>;
    expect(Object.keys(body).every((key) => GLOW_KEYS.includes(key))).toBe(true);
    expect(body).toMatchObject({ color: 'aqua', codeWord: 'lantern', theyMet: true });
    expect(body.meetingSpot).toEqual({ id: expect.any(String), name: 'Water station' });
    const text = JSON.stringify(body);
    expect(text).not.toContain(USER_ID);
    expect(text).not.toContain(OTHER_ID);
    expect(text).not.toContain('Blake');
    expect(rpc).toHaveBeenCalledWith(expect.anything(), 'get_match', {
      p_user_id: USER_ID,
      p_match_id: MATCH_ID,
    });
  });

  it('is 404 when the match has no glow', async () => {
    vi.mocked(rpc).mockResolvedValue({ id: MATCH_ID, settled: [] } as never);
    expect((await call(getRoute)).status).toBe(404);
  });

  it('is the same 404 for a match that is not mine as for a malformed ID (P11)', async () => {
    vi.mocked(rpc).mockRejectedValue(notFound());
    const notMine = await call(getRoute);
    const malformed = await call(getRoute, { id: 'not-a-uuid' });
    expect(notMine.status).toBe(404);
    expect(await notMine.text()).toBe(await malformed.text());
  });

  it('shows an ended glow for GLOW_ENDED_RETENTION, then answers 404', async () => {
    const ended = (secondsAgo: number) =>
      ({
        glow: glowRow(USER_ID, { status: 'met', endedAt: recently(secondsAgo) }),
        settled: [],
      }) as never;
    vi.mocked(rpc).mockResolvedValueOnce(ended(GLOW_ENDED_RETENTION_SECONDS - 30));
    expect((await call(getRoute)).status).toBe(200);
    vi.mocked(rpc).mockResolvedValueOnce(ended(GLOW_ENDED_RETENTION_SECONDS + 30));
    expect((await call(getRoute)).status).toBe(404);
  });

  it('sends glow.ended to both when reading it settled the timeout', async () => {
    vi.mocked(rpc).mockResolvedValue({
      glow: glowRow(USER_ID, { status: 'expired', endedAt: recently(1) }),
      settled: [{ matchId: MATCH_ID, kind: 'glow_expired', userIds: BOTH }],
    } as never);
    const res = await call(getRoute);
    expect(res.status).toBe(200);
    expect(((await res.json()) as { status: string }).status).toBe('expired');
    expect(sent()).toEqual([[BOTH, { type: 'glow.ended', matchId: MATCH_ID }]]);
  });

  it('sends nothing for an ordinary read', async () => {
    vi.mocked(rpc).mockResolvedValue({ glow: glowRow(USER_ID), settled: [] } as never);
    await call(getRoute);
    expect(notify).not.toHaveBeenCalled();
  });
});

describe('POST /api/matches/{id}/glow/met', () => {
  it('records my tap and tells nobody while they have not tapped yet', async () => {
    vi.mocked(rpc).mockResolvedValue({ ...glowRow(USER_ID, { youMet: true }), settled: [] });
    const res = await call(metRoute, { method: 'POST' });
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ status: 'active', youMet: true, theyMet: false });
    expect(notify).not.toHaveBeenCalled();
  });

  it('ends the glow as met for both when the second person taps', async () => {
    vi.mocked(rpc).mockResolvedValue({
      ...glowRow(USER_ID, { status: 'met', youMet: true, theyMet: true, endedAt: recently(0) }),
      settled: [],
    });
    const res = await call(metRoute, { method: 'POST' });
    expect(await res.json()).toMatchObject({ status: 'met', youMet: true, theyMet: true });
    expect(sent()).toEqual([[BOTH, { type: 'glow.ended', matchId: MATCH_ID }]]);
  });

  it('does not announce again when the glow had already ended', async () => {
    vi.mocked(activeGlowId).mockResolvedValue(null);
    vi.mocked(rpc).mockResolvedValue({
      ...glowRow(USER_ID, { status: 'met', youMet: true, theyMet: true, endedAt: recently(5) }),
      settled: [],
    });
    expect((await call(metRoute, { method: 'POST' })).status).toBe(200);
    expect(notify).not.toHaveBeenCalled();
  });

  it('answers expired, and tells both once, when the time had run out', async () => {
    vi.mocked(rpc).mockResolvedValue({
      ...glowRow(USER_ID, { status: 'expired', endedAt: recently(2) }),
      settled: [{ matchId: MATCH_ID, kind: 'glow_expired', userIds: BOTH }],
    });
    const res = await call(metRoute, { method: 'POST' });
    expect(((await res.json()) as { status: string }).status).toBe('expired');
    expect(sent()).toEqual([[BOTH, { type: 'glow.ended', matchId: MATCH_ID }]]);
  });

  it('is 404 for a match that is not mine (P11)', async () => {
    vi.mocked(rpc).mockRejectedValue(notFound());
    expect((await call(metRoute, { method: 'POST' })).status).toBe(404);
    expect(notify).not.toHaveBeenCalled();
  });

  it('is 404 for a glow that ended long ago', async () => {
    vi.mocked(activeGlowId).mockResolvedValue(null);
    vi.mocked(rpc).mockResolvedValue({
      ...glowRow(USER_ID, { status: 'met', endedAt: recently(GLOW_ENDED_RETENTION_SECONDS + 1) }),
      settled: [],
    });
    expect((await call(metRoute, { method: 'POST' })).status).toBe(404);
  });
});

describe('POST /api/matches/{id}/glow/cancel', () => {
  const canceled = () => glowRow(USER_ID, { status: 'canceled', endedAt: recently(0) });

  it.each([undefined, {}, { reason: 'cancel' }, { reason: 'switch_to_chat' }])(
    'ends the glow for both (%j)',
    async (body) => {
      vi.mocked(rpc).mockResolvedValue(canceled());
      const res = await call(cancelRoute, { method: 'POST', body });
      expect(res.status).toBe(200);
      expect(((await res.json()) as { status: string }).status).toBe('canceled');
      expect(rpc).toHaveBeenCalledWith(expect.anything(), 'cancel_glow', {
        p_user_id: USER_ID,
        p_match_id: MATCH_ID,
      });
      expect(sent()).toEqual([[BOTH, { type: 'glow.ended', matchId: MATCH_ID }]]);
    },
  );

  it('refuses an unknown reason with field paths only', async () => {
    const res = await call(cancelRoute, { method: 'POST', body: { reason: 'ghost' } });
    expect(res.status).toBe(400);
    expect(await res.text()).not.toContain('ghost');
    expect(rpc).not.toHaveBeenCalled();
  });

  it('does not announce again when the other person had already canceled', async () => {
    vi.mocked(activeGlowId).mockResolvedValue(null);
    vi.mocked(rpc).mockResolvedValue(canceled());
    expect((await call(cancelRoute, { method: 'POST' })).status).toBe(200);
    expect(notify).not.toHaveBeenCalled();
  });

  it('is 404 for a match that is not mine (P11)', async () => {
    vi.mocked(rpc).mockRejectedValue(notFound());
    expect((await call(cancelRoute, { method: 'POST' })).status).toBe(404);
  });
});
