/**
 * Owner: B4. Telling both people about a new match, and about matches whose time ran out.
 *
 * Events carry only `{ type, matchId }` (contracts/events.json). The user IDs here come from
 * the database, go only to `notify()`, and never reach a reply (P1).
 *
 * Sending runs after the response (Next's `after()`), so a slow push never slows a tap. A
 * notification that fails never fails the request: the match is already committed, and the
 * app finds it with `GET /api/matches` anyway. Failures are logged by event type only.
 */
import { after } from 'next/server';
import { serviceDb } from '@/server/deck/db';
import { notify } from '@/server/deck/dependencies';
import { logger } from '@/server/log';

/**
 * Runs `task` after the response is sent. Outside a request (tests, scripts) there is no
 * response to wait for, so it runs now and is awaited, which keeps tests deterministic.
 */
export async function afterResponse(task: () => Promise<void>): Promise<void> {
  const safe = () =>
    task().catch((error: unknown) =>
      logger.warn('notify.failed', { error: error instanceof Error ? error.name : 'unknown' }),
    );
  try {
    after(safe);
  } catch {
    await safe();
  }
}

/** The two people in a match, from the matches table (server only). */
async function matchPeople(matchId: string): Promise<readonly string[] | null> {
  const { data, error } = await serviceDb()
    .from('matches')
    .select('user_a, user_b')
    .eq('id', matchId)
    .maybeSingle();
  if (error || !data) return null;
  return [data.user_a, data.user_b];
}

/** match.created to both people. Called once, by the tap that made the match. */
export async function announceMatch(matchId: string): Promise<void> {
  await afterResponse(async () => {
    const people = await matchPeople(matchId);
    if (!people) {
      logger.warn('notify.failed', { type: 'match.created', cause: 'match_not_found' });
      return;
    }
    await notify(people, { type: 'match.created', matchId });
  });
}

/**
 * A timeout a database function applied while answering (A2's `settled`, migration 0002):
 * `choice_timeout` opened the chat, `glow_expired` ended the glow.
 */
export type SettledTransition = {
  readonly matchId: string;
  readonly kind: 'choice_timeout' | 'glow_expired' | (string & {});
  readonly userIds: readonly string[];
};

/** Tells both people about each settled transition: match.choice or glow.ended. */
export async function announceSettled(
  settled: readonly SettledTransition[] | null | undefined,
): Promise<void> {
  if (!settled || settled.length === 0) return;
  await afterResponse(async () => {
    await Promise.all(
      settled.map((t) => {
        if (t.kind === 'choice_timeout') {
          return notify(t.userIds, { type: 'match.choice', matchId: t.matchId });
        }
        if (t.kind === 'glow_expired') {
          return notify(t.userIds, { type: 'glow.ended', matchId: t.matchId });
        }
        return undefined;
      }),
    );
  });
}
