/**
 * POST /api/rooms/{id}/leave (leaveRoom). Owner: B2.
 *
 * Ends my open check-in in this room now and deletes my card photo, then tells the
 * room to refetch its decks (deck.changed). Leaving a room I'm not in is a quiet 204;
 * a room that doesn't exist is 404.
 *
 * If deleting the photo fails, the check-in has still ended (so the card is out of
 * every deck and its image route answers 404), and the purge job deletes the photo
 * within PURGE_INTERVAL, because it removes every left check-in and returns its path.
 */
import { notFound, type RouteHandler } from '@/server/http';
import { logger } from '@/server/log';
import { serviceDb } from './db';
import { roomById } from './rooms';
import { sendDeckChanged } from './stand-ins';

const CARD_BUCKET = 'room-cards';

export const leaveRoom: RouteHandler<'leaveRoom'> = async ({ user, params }) => {
  const db = serviceDb();
  const room = await roomById(db, params.id);
  if (!room) throw notFound();

  const { data, error } = await db
    .from('checkins')
    .update({ left_at: new Date().toISOString() })
    .eq('room_id', room.id)
    .eq('user_id', user.id)
    .is('left_at', null)
    .select('card_path');
  if (error) throw new Error('checkins update failed');

  const paths = (data ?? []).map((row) => row.card_path);
  if (paths.length > 0) {
    const removed = await db.storage.from(CARD_BUCKET).remove(paths);
    if (removed.error) logger.warn('rooms.leave.photo_delete_failed', { roomId: room.id });
    await sendDeckChanged(room.id);
  }
  logger.info('rooms.leave', { roomId: room.id, ended: paths.length });
  return { status: 204 };
};
