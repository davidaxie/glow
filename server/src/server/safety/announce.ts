/**
 * Owner: B8. Tells apps what a block, report or account deletion changed. Best effort:
 * the change is already committed when these run, so nothing here throws.
 *
 * - `match.ended` to both people in each ended match (D18: it never says why, so a block
 *   looks exactly like an unmatch).
 * - `deck.changed` to each room where either person had an open check-in, so every deck
 *   there refetches and the two leave each other's decks at once (P7).
 */
import { logger } from '@/server/log';
import { serviceDb } from './db';
import { notify, notifyRoom } from './dependencies';

type EndedMatch = { readonly id: string; readonly userIds: readonly string[] };

/** Both people in each match, read on the server. Never sent to an app. */
async function peopleIn(matchIds: readonly string[]): Promise<EndedMatch[]> {
  if (matchIds.length === 0) return [];
  const { data, error } = await serviceDb()
    .from('matches')
    .select('id, user_a, user_b')
    .in('id', [...matchIds]);
  if (error || !data) {
    logger.error('safety.announce_lookup_failed', { matches: matchIds.length });
    return [];
  }
  return data.map((m) => ({ id: m.id, userIds: [m.user_a, m.user_b] }));
}

export async function announceEnded(input: {
  readonly endedMatchIds: readonly string[];
  readonly roomIds: readonly string[];
  /** Matches already read before they were deleted (account deletion). */
  readonly endedMatches?: readonly EndedMatch[];
}): Promise<void> {
  const matches = input.endedMatches ?? (await peopleIn(input.endedMatchIds));
  await Promise.all([
    ...matches.map((m) => notify(m.userIds, { type: 'match.ended', matchId: m.id })),
    ...announceRooms(input.roomIds),
  ]);
}

export function announceRooms(roomIds: readonly string[]): Promise<unknown>[] {
  return [...new Set(roomIds)].map((roomId) =>
    notifyRoom(roomId, { type: 'deck.changed', roomId }),
  );
}

/** Rooms where this person has an open (not left, not expired) check-in. */
export async function openRoomsOf(userId: string): Promise<string[]> {
  const { data, error } = await serviceDb()
    .from('checkins')
    .select('room_id')
    .eq('user_id', userId)
    .is('left_at', null)
    .gt('expires_at', new Date().toISOString());
  if (error || !data) {
    logger.error('safety.rooms_lookup_failed', {});
    return [];
  }
  return [...new Set(data.map((c) => c.room_id))];
}
