/**
 * Events the admin module sends, through B5's `notify` and `notifyRoom` (`@/server/notify`).
 * Payloads are the contract's events: a type plus a room or match ID, never a user ID, name
 * or anything else (P1, P6). User IDs only ever say who receives an event. B5's sender never
 * throws, so a missed event never fails the admin's action; apps refetch on their next open.
 */
import { notify, notifyRoom } from '@/server/notify';

export type AdminEvents = {
  /** deck.changed to everyone checked into the room. */
  deckChanged(roomId: string): Promise<void>;
  /** match.ended to both people in the match. */
  matchEnded(matchId: string, recipients: readonly string[]): Promise<void>;
};

export const liveEvents: AdminEvents = {
  async deckChanged(roomId) {
    await notifyRoom(roomId, { type: 'deck.changed', roomId });
  },
  async matchEnded(matchId, recipients) {
    await notify(recipients, { type: 'match.ended', matchId });
  },
};
