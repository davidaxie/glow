/**
 * Owner: B4. STAND-IN for B5's `notify(userId, event)`, until `server/src/server/notify`
 * merges (AGENTS.md, "Mocks"). Swap the export in `../dependencies.ts`, then delete this file.
 *
 * B5's version sends a Realtime broadcast to `user:{userId}` plus an Apple push, both built
 * only from contracts/events.json. This one sends nothing: it logs the event type, so local
 * runs show where a notification would have gone, without the person or match.
 */
import type { GlowEvent } from '@/contracts';
import { logger } from '@/server/log';

export async function notify(_userId: string, event: GlowEvent): Promise<void> {
  logger.debug('notify.stub', { type: event.type });
}
