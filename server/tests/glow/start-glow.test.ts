import { beforeEach, describe, expect, it, vi } from 'vitest';
import { HttpError, notFound } from '@/server/http';
import { notify } from '@/server/glow/dependencies';
import { rpc, type GlowDb } from '@/server/glow/db';
import { startGlow } from '@/server/glow';
import { CODE_WORDS } from '@/server/glow/words';
import { USER_ID } from '../helpers/auth';
import { glowRow, MATCH_ID, OTHER_ID, OTHER_MATCH_ID, STRANGER_A, STRANGER_B } from './fixtures';

// Owner: C3. startGlow, for C2's setChoice: every result, and every event it implies.

vi.mock('@/server/glow/db', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/server/glow/db')>()),
  rpc: vi.fn(),
}));
vi.mock('@/server/glow/dependencies', () => ({
  notify: vi.fn(async () => ({ realtime: 'sent', push: null })),
}));

const db = {} as GlowDb;
const BOTH = [USER_ID, OTHER_ID];

function answer(data: unknown) {
  vi.mocked(rpc).mockResolvedValue(data as never);
}

/** Every notify call as [people, event]. */
const sent = () => vi.mocked(notify).mock.calls.map(([ids, event]) => [ids, event]);

beforeEach(() => {
  vi.mocked(notify).mockResolvedValue({ realtime: 'sent', push: null });
});

describe('startGlow', () => {
  it('starts the glow with all 300 words and tells both people', async () => {
    answer({ result: 'started', glow: glowRow(USER_ID), settled: [] });
    await expect(startGlow(db, MATCH_ID)).resolves.toEqual({ result: 'started' });
    expect(rpc).toHaveBeenCalledWith(db, 'start_glow', {
      p_match_id: MATCH_ID,
      p_code_words: [...CODE_WORDS],
    });
    expect(sent()).toEqual([[BOTH, { type: 'glow.started', matchId: MATCH_ID }]]);
  });

  it("also ends other pairs' glows in the room that timed out on the way", async () => {
    answer({
      result: 'started',
      glow: glowRow(USER_ID),
      settled: [
        { matchId: OTHER_MATCH_ID, kind: 'glow_expired', userIds: [STRANGER_A, STRANGER_B] },
      ],
    });
    await startGlow(db, MATCH_ID);
    expect(sent()).toEqual([
      [[STRANGER_A, STRANGER_B], { type: 'glow.ended', matchId: OTHER_MATCH_ID }],
      [BOTH, { type: 'glow.started', matchId: MATCH_ID }],
    ]);
  });

  it.each(['not_checked_in', 'no_code_word', 'already_decided'] as const)(
    'opens the chat for both when it says chat (%s)',
    async (reason) => {
      answer({
        result: 'chat',
        reason,
        matchId: MATCH_ID,
        status: 'chatting',
        userIds: BOTH,
        settled: [],
      });
      await expect(startGlow(db, MATCH_ID)).resolves.toEqual({ result: 'chat', reason });
      expect(sent()).toEqual([[BOTH, { type: 'match.choice', matchId: MATCH_ID }]]);
    },
  );

  it('asks only the person whose location check is stale to check again', async () => {
    answer({
      result: 'waiting',
      reason: 'location_stale',
      matchId: MATCH_ID,
      status: 'choosing',
      userIds: BOTH,
      staleUserIds: [OTHER_ID],
      settled: [],
    });
    await expect(startGlow(db, MATCH_ID)).resolves.toEqual({
      result: 'waiting',
      reason: 'location_stale',
    });
    expect(sent()).toEqual([[[OTHER_ID], { type: 'match.recheck', matchId: MATCH_ID }]]);
  });

  it('sends nothing while not both chose Find', async () => {
    answer({
      result: 'waiting',
      reason: 'not_both_find',
      matchId: MATCH_ID,
      status: 'choosing',
      userIds: BOTH,
      settled: [],
    });
    await expect(startGlow(db, MATCH_ID)).resolves.toEqual({
      result: 'waiting',
      reason: 'not_both_find',
    });
    expect(notify).not.toHaveBeenCalled();
  });

  it('reports a choice window that ran out as match.choice', async () => {
    answer({
      result: 'chat',
      reason: 'already_decided',
      matchId: MATCH_ID,
      status: 'chatting',
      userIds: BOTH,
      settled: [{ matchId: MATCH_ID, kind: 'choice_timeout', userIds: BOTH }],
    });
    await startGlow(db, MATCH_ID);
    // The same event to the same people goes once.
    expect(sent()).toEqual([[BOTH, { type: 'match.choice', matchId: MATCH_ID }]]);
  });

  it('throws 404 for a match that ended or never existed', async () => {
    vi.mocked(rpc).mockRejectedValue(notFound());
    await expect(startGlow(db, MATCH_ID)).rejects.toMatchObject({ status: 404 });
    expect(notify).not.toHaveBeenCalled();
  });

  it('refuses a result it does not understand, and tells nobody', async () => {
    answer({ result: 'started', glow: { id: 'nope' }, settled: [] });
    await expect(startGlow(db, MATCH_ID)).rejects.toThrow(/unexpected shape/);
    expect(notify).not.toHaveBeenCalled();
  });

  it('never fails because a notification failed', async () => {
    answer({ result: 'started', glow: glowRow(USER_ID), settled: [] });
    vi.mocked(notify).mockRejectedValue(new Error('push down'));
    await expect(startGlow(db, MATCH_ID)).resolves.toEqual({ result: 'started' });
  });

  it('is an HttpError for routes, not a crash', async () => {
    vi.mocked(rpc).mockRejectedValue(notFound());
    const error = await startGlow(db, MATCH_ID).catch((e: unknown) => e);
    expect(error).toBeInstanceOf(HttpError);
  });
});
