/**
 * Owner: C4. Telling the right people what chat changed, without saying who or what.
 *
 * Events carry only `{ type, matchId }` (contracts/events.json): never a user ID, a name or
 * message text (P1, P6). The user IDs here come from the database, go only to `notify()`,
 * and never reach a reply. The lock screen text for `message.created` is the catalog's fixed
 * "New message".
 *
 * Sending runs after the response (Next's `after()`), so a slow push never slows a send. A
 * notification that fails never fails the request: the change is already committed, and the
 * app refetches when it next opens the thread. Failures are logged by event type only.
 */
import { after } from 'next/server';
import { logger } from '@/server/log';
import { notify } from './dependencies';

/**
 * Runs `task` after the response is sent. Outside a request (tests, scripts) there is no
 * response to wait for, so it runs now and is awaited, which keeps tests deterministic.
 */
export async function afterResponse(task: () => Promise<unknown>): Promise<void> {
  const safe = () =>
    task().then(
      () => undefined,
      (error: unknown) =>
        logger.warn('notify.failed', { error: error instanceof Error ? error.name : 'unknown' }),
    );
  try {
    after(safe);
  } catch {
    await safe();
  }
}

/** message.created, to the recipient only. */
export function announceMessage(recipientId: string, matchId: string): Promise<void> {
  return afterResponse(() => notify([recipientId], { type: 'message.created', matchId }));
}

/** match.ended, to both people. It never says why, so it looks like a block (D18). */
export function announceEnded(userIds: readonly string[], matchId: string): Promise<void> {
  return afterResponse(() => notify(userIds, { type: 'match.ended', matchId }));
}

/**
 * A timeout a database function applied while answering (A2's `settled`, migration 0002):
 * `choice_timeout` opened the chat, `glow_expired` ended the glow. Purge skips anything
 * already settled, so the route that called the function must send these.
 */
export type SettledTransition = {
  readonly matchId: string;
  readonly kind: string;
  readonly userIds: readonly string[];
};

/** Tells both people about each settled transition: match.choice or glow.ended. */
export async function announceSettled(
  settled: readonly SettledTransition[] | undefined,
): Promise<void> {
  if (!settled || settled.length === 0) return;
  await afterResponse(() =>
    Promise.all(
      settled.map((t) => {
        if (t.kind === 'choice_timeout') {
          return notify(t.userIds, { type: 'match.choice', matchId: t.matchId });
        }
        if (t.kind === 'glow_expired') {
          return notify(t.userIds, { type: 'glow.ended', matchId: t.matchId });
        }
        return undefined;
      }),
    ),
  );
}
