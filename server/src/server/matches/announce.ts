/**
 * Owner: B4. Telling both people about a new match, and about matches whose time ran out.
 *
 * Events carry only `{ type, matchId }` (contracts/events.json). The user IDs here come from
 * the database, go only to `notify()`, and never reach a reply (P1).
 *
 * A notification that fails never fails the request: the match is already committed, and
 * the app finds it with `GET /api/matches` anyway. Failures are logged by event type only.
 */
import type { GlowEvent } from '@/contracts';
import { serviceDb } from '@/server/deck/db';
import { notify } from '@/server/deck/dependencies';
import { logger } from '@/server/log';

async function notifyAll(userIds: readonly string[], event: GlowEvent): Promise<void> {
  const results = await Promise.allSettled(userIds.map((id) => notify(id, event)));
  const failed = results.filter((r) => r.status === 'rejected').length;
  if (failed > 0) logger.warn('notify.failed', { type: event.type, failed });
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
  try {
    const people = await matchPeople(matchId);
    if (!people) {
      logger.warn('notify.failed', { type: 'match.created', failed: 2 });
      return;
    }
    await notifyAll(people, { type: 'match.created', matchId });
  } catch {
    logger.warn('notify.failed', { type: 'match.created', failed: 2 });
  }
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

const EVENT_FOR_KIND: Readonly<Record<string, GlowEvent['type']>> = {
  choice_timeout: 'match.choice',
  glow_expired: 'glow.ended',
};

/** Tells both people about each settled transition: match.choice or glow.ended. */
export async function announceSettled(
  settled: readonly SettledTransition[] | null | undefined,
): Promise<void> {
  if (!settled || settled.length === 0) return;
  await Promise.all(
    settled.map(async (t) => {
      const type = EVENT_FOR_KIND[t.kind];
      if (!type) return;
      try {
        await notifyAll(t.userIds, { type, matchId: t.matchId } as GlowEvent);
      } catch {
        logger.warn('notify.failed', { type, failed: t.userIds.length });
      }
    }),
  );
}
