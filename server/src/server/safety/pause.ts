/**
 * Owner: B8. Pause and resume. Every deck rule reads `profiles.paused` (through
 * `active_checkin`), so a paused person leaves every deck on the next fetch (P8), and
 * `deck.changed` makes every phone in their rooms fetch right away.
 */
import type { PauseState } from '@/contracts';
import { logger } from '@/server/log';
import { announceRooms, openRoomsOf } from './announce';
import { DatabaseError, dbError, serviceDb } from './db';

export async function setPausedFor(userId: string, paused: boolean): Promise<PauseState> {
  const db = serviceDb();
  const { data, error } = await db
    .from('profiles')
    .update({ paused })
    .eq('id', userId)
    .neq('paused', paused)
    .select('id');
  if (error) throw dbError('pause', error);

  const changed = (data?.length ?? 0) > 0;
  if (!changed) {
    // Already in that state (a retry, or a second phone). Answer with what's stored.
    const current = await db.from('profiles').select('paused').eq('id', userId).maybeSingle();
    if (current.error) throw dbError('pause', current.error);
    if (!current.data) throw new DatabaseError('pause: no profile for a signed-in person');
    logger.info('safety.pause', { paused: current.data.paused, changed: false });
    return { paused: current.data.paused };
  }

  const rooms = await openRoomsOf(userId);
  await Promise.all(announceRooms(rooms));
  logger.info('safety.pause', { paused, changed: true, rooms: rooms.length });
  return { paused };
}
