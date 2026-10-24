/**
 * Events the admin module sends. STAND-IN for B5's `notify` and `notifyRoom` in
 * `@/server/notify` (PR #15), which isn't merged yet: today these only log. When it merges,
 * `deckChanged` becomes `notifyRoom(roomId, event)` and `matchEnded` becomes
 * `notify(recipients, event)`, and nothing else in the admin module changes.
 *
 * Payloads are the contract's events: a type plus a room or match ID, never a user ID, name
 * or anything else (P1, P6). User IDs are only ever passed to say who receives an event.
 */
import type { DeckChangedEvent, MatchEndedEvent } from '@/contracts';
import { logger } from '@/server/log';

export type AdminEvents = {
  /** deck.changed to everyone checked into the room. */
  deckChanged(roomId: string): Promise<void>;
  /** match.ended to both people in the match. */
  matchEnded(matchId: string, recipients: readonly string[]): Promise<void>;
};

export const pendingEvents: AdminEvents = {
  async deckChanged(roomId) {
    const event: DeckChangedEvent = { type: 'deck.changed', roomId };
    logger.info('admin.event', { event: event.type, roomId, sent: false });
  },
  async matchEnded(matchId, recipients) {
    const event: MatchEndedEvent = { type: 'match.ended', matchId };
    logger.info('admin.event', {
      event: event.type,
      matchId,
      recipients: recipients.length,
      sent: false,
    });
  },
};
