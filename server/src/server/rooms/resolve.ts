/**
 * POST /api/rooms/resolve (resolveRoom). Owner: B2.
 *
 * A room code, or a slug plus QR token, returns the room's name and times. This only
 * gets someone to the location check; it never gets them into a room by itself.
 * The route helper rate limits it with B8's `join` policy, so codes can't be guessed in bulk.
 */
import { notFound, type RouteHandler } from '@/server/http';
import { logger } from '@/server/log';
import { serviceDb } from './db';
import { requireOnboarded, roomForAccess, roomSummary } from './rooms';

export const resolveRoom: RouteHandler<'resolveRoom'> = async ({ user, body }) => {
  const db = serviceDb();
  await requireOnboarded(db, user.id);

  const now = Date.now();
  const room = await roomForAccess(db, body, now);
  logger.info('rooms.resolve', { via: body.kind, found: room !== null });
  if (!room) throw notFound();
  return { status: 200, body: roomSummary(room, now) };
};
