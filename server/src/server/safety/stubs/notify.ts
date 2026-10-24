/**
 * Owner: B8. STAND-IN for B5's `notify` and `notifyRoom` (PR #15), until
 * `server/src/server/notify` merges (AGENTS.md, "Mocks"). Swap the export in
 * `../dependencies.ts`, then delete this file.
 *
 * B5's version broadcasts on the private Realtime channel and sends an Apple push, both
 * built only from contracts/events.json. This one sends nothing: it logs the event type,
 * so local runs show where a notification would have gone, without the person or match.
 */
import type { GlowEvent } from '@/contracts';
import { logger } from '@/server/log';

type UserEvent = Exclude<GlowEvent, { type: 'deck.changed' }>;
type RoomEvent = Extract<GlowEvent, { type: 'deck.changed' }>;

export async function notify(_userIds: string | readonly string[], event: UserEvent) {
  logger.debug('notify.stub', { type: event.type });
  return { realtime: 'skipped' as const, push: null };
}

export async function notifyRoom(_roomId: string, event: RoomEvent) {
  logger.debug('notify.stub', { type: event.type });
  return { realtime: 'skipped' as const, push: null };
}
