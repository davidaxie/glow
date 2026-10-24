/**
 * Owner: C3. Telling both people when a glow starts or ends, and about anything a database
 * function settled on the way.
 *
 * Events carry only `{ type, matchId }` (contracts/events.json). The user IDs here come from the
 * database, go only to `notify()`, and never reach a reply (P1).
 *
 * Sending runs after the response (Next's `after()`), so a slow push never slows a tap of We met.
 * A notification that fails never fails the request: the change is already committed, and the app
 * finds it with `GET /api/matches/{id}/glow` anyway. Failures are logged by event type only.
 */
import { after } from 'next/server';
import { logger } from '@/server/log';
import { notify, type UserEvent } from './dependencies';
import type { Settled } from './results';

export type Announcement = { readonly userIds: readonly string[]; readonly event: UserEvent };

/**
 * Runs `task` after the response is sent. Outside a request (tests, scripts) there's no response to
 * wait for, so it runs now and is awaited, which keeps tests deterministic.
 */
export async function afterResponse(task: () => Promise<unknown>): Promise<void> {
  const safe = async () => {
    try {
      await task();
    } catch (error) {
      logger.warn('notify.failed', { error: error instanceof Error ? error.name : 'unknown' });
    }
  };
  try {
    after(safe);
  } catch {
    await safe();
  }
}

/** The events each settled timeout implies (CONTRACTS.md, "Settled timeouts"). */
export function settledAnnouncements(settled: Settled): Announcement[] {
  return settled.flatMap((entry): Announcement[] => {
    if (entry.kind === 'glow_expired') {
      return [{ userIds: entry.userIds, event: { type: 'glow.ended', matchId: entry.matchId } }];
    }
    if (entry.kind === 'choice_timeout') {
      return [{ userIds: entry.userIds, event: { type: 'match.choice', matchId: entry.matchId } }];
    }
    logger.warn('glow.settled_unknown_kind', { kind: entry.kind });
    return [];
  });
}

/** Sends every announcement after the response. Duplicates (same people, same event) go once. */
export async function announce(announcements: readonly Announcement[]): Promise<void> {
  const unique = new Map<string, Announcement>();
  for (const a of announcements) {
    if (a.userIds.length === 0) continue;
    const key = `${a.event.type}|${'matchId' in a.event ? a.event.matchId : ''}|${[...a.userIds].sort().join(',')}`;
    unique.set(key, a);
  }
  if (unique.size === 0) return;
  await afterResponse(() =>
    Promise.all([...unique.values()].map((a) => notify(a.userIds, a.event))),
  );
}
