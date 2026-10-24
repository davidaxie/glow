/**
 * Owner: C4. STAND-IN for B5's `notify(userIds, event)` from `@/server/notify` (PR #15),
 * until it merges (AGENTS.md, "Mocks"). Same signature. When #15 merges, point
 * `../dependencies.ts` at `@/server/notify` and delete this file.
 *
 * B5's version sends a Realtime broadcast to each `user:{id}` plus an Apple push, both built
 * only from contracts/events.json, and never throws. This one sends nothing: it logs the
 * event type and how many people, never who or which match.
 */
import type { GlowEvent } from '@/contracts';
import { logger } from '@/server/log';

/** An event for one person's `user:{id}` channel (everything but deck.changed). */
export type UserEvent = Exclude<GlowEvent, { type: 'deck.changed' }>;

export type NotifyOutcome = {
  readonly realtime: 'sent' | 'failed' | 'skipped';
  readonly push: null;
};

export async function notify(
  userIds: string | readonly string[],
  event: UserEvent,
): Promise<NotifyOutcome> {
  const people = new Set(typeof userIds === 'string' ? [userIds] : userIds).size;
  logger.debug('notify.stub', { type: event.type, people });
  return { realtime: 'skipped', push: null };
}
