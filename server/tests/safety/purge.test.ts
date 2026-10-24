/**
 * The purge job's notifications and schedule, with the database and storage stubbed.
 * (tests/safety/safety.live.test.ts runs it against a real Supabase.)
 */
import { readFileSync } from 'node:fs';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { PURGE_INTERVAL_SECONDS } from '@/contracts';

const calls = vi.hoisted(() => ({
  user: [] as { userIds: unknown; event: unknown }[],
  room: [] as { roomId: string; event: unknown }[],
  removed: [] as string[][],
  rpc: [] as string[],
}));

vi.mock('@/server/safety/dependencies', () => ({
  notify: vi.fn(async (userIds: unknown, event: unknown) => {
    calls.user.push({ userIds, event });
    return { realtime: 'sent', push: null };
  }),
  notifyRoom: vi.fn(async (roomId: string, event: unknown) => {
    calls.room.push({ roomId, event });
    return { realtime: 'sent', push: null };
  }),
}));

const ROOM = 'de000000-0000-4000-8000-000000000001';
const MATCH = '0a000000-0000-4000-8000-00000000000a';
const A = '7e570000-0000-4000-8000-000000000001';
const B = '7e570000-0000-4000-8000-000000000002';

vi.mock('@/server/safety/db', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@/server/safety/db')>();
  return {
    ...actual,
    rpc: vi.fn(async (fn: string) => {
      calls.rpc.push(fn);
      if (fn === 'purge_auth_audit') return 3;
      return {
        cardPaths: [`${ROOM}/c1000000-0000-4000-8000-000000000001.jpg`],
        expiringCheckins: [{ userId: A, roomId: ROOM, checkinId: 'x' }],
        endedGlows: [{ matchId: MATCH, kind: 'glow_expired', userIds: [A, B] }],
        choiceTimeouts: [{ matchId: MATCH, userIds: [A, B] }],
        deleted: { checkins: 1, taps: 4, glowSessions: 0, cardViews: 0, locationChecks: 0 },
      };
    }),
  };
});

vi.mock('@/server/safety/storage', () => ({
  removeObjects: vi.fn(async (_bucket: string, paths: string[]) => {
    calls.removed.push(paths);
    return paths.length;
  }),
  sweepOrphans: vi.fn(async () => ({ cardPhotos: 2, profilePhotos: 1 })),
}));

vi.mock('@/server/moderation/review-pending', () => ({
  reviewPendingMessages: vi.fn(async () => ({ reviewed: 0, flagged: 0 })),
}));

beforeEach(() => {
  calls.user.length = 0;
  calls.room.length = 0;
  calls.removed.length = 0;
  calls.rpc.length = 0;
});

describe('runPurgeJob', () => {
  it('deletes photos, notifies everyone who needs to know, and counts it all', async () => {
    const { runPurgeJob } = await import('@/server/safety/purge');
    const result = await runPurgeJob();

    expect(result).toEqual({
      checkinsDeleted: 1,
      cardPhotosDeleted: 3,
      tapsDeleted: 4,
      glowsEnded: 1,
      choicesTimedOut: 1,
      expiringNotified: 1,
    });
    expect(calls.removed).toEqual([[`${ROOM}/c1000000-0000-4000-8000-000000000001.jpg`]]);
    expect(calls.user).toEqual(
      expect.arrayContaining([
        { userIds: A, event: { type: 'checkin.expiring', roomId: ROOM } },
        { userIds: [A, B], event: { type: 'glow.ended', matchId: MATCH } },
        { userIds: [A, B], event: { type: 'match.choice', matchId: MATCH } },
      ]),
    );
    expect(calls.room).toEqual([{ roomId: ROOM, event: { type: 'deck.changed', roomId: ROOM } }]);
    expect(calls.rpc).toEqual(['purge_expired', 'purge_auth_audit']);
  });

  it('sends events built only from the contract: no user IDs in any payload (P1)', async () => {
    const { runPurgeJob } = await import('@/server/safety/purge');
    await runPurgeJob();
    for (const { event } of [...calls.user, ...calls.room]) {
      expect(JSON.stringify(event)).not.toContain(A);
      expect(JSON.stringify(event)).not.toContain(B);
    }
  });
});

describe('the purge schedule (P9)', () => {
  it('runs every PURGE_INTERVAL, so a card is gone well within 10 minutes of expiring', () => {
    const vercel = JSON.parse(readFileSync(new URL('../../vercel.json', import.meta.url), 'utf8'));
    expect(vercel.crons).toEqual([{ path: '/api/cron/purge', schedule: '*/5 * * * *' }]);
    expect(PURGE_INTERVAL_SECONDS).toBe(300);
    // Worst case: the photo's first delete fails and the next run's sweep gets it.
    expect(2 * PURGE_INTERVAL_SECONDS).toBeLessThanOrEqual(600);
  });
});
