/**
 * POST /api/rooms/{id}/join (joinRoom). Owner: B2.
 *
 * The code or QR token plus one location fix returns a JOIN_TICKET_TTL join ticket.
 *
 * Order matters, so nothing leaks: sign-in (route helper), onboarding (409), then the
 * room and the code or token together (404 for either being wrong, P11), then whether
 * the room is open (409), then the location check (422).
 *
 * P2: the fix is used for one distance calculation and dropped. Only the outcome and
 * a rough accuracy bucket are stored (`location_checks`), and nothing about the fix is
 * logged. In a demo mode room, admins skip the check; the skip is stored as
 * `demo_skip` and logged.
 *
 * The route helper rate limits it with B8's `join` policy, which also keeps the check from
 * working as a location oracle (many fixes against one room).
 */
import { checkFix, recordLocationCheck } from '@/server/geo';
import { notFound, unprocessable, type RouteHandler } from '@/server/http';
import { logger } from '@/server/log';
import { serviceDb } from './db';
import { accessOpensRoom, isAdmin, isOpen, requireOnboarded, roomById, roomNotLive } from './rooms';
import { issueJoinTicket } from './ticket';

export const notInRoom = () =>
  unprocessable('not_in_room', "Outside the room's area. Try again inside.");
export const locationInaccurate = () =>
  unprocessable('location_inaccurate', 'The location fix is too rough. Try again.');

export const joinRoom: RouteHandler<'joinRoom'> = async ({ user, params, body }) => {
  const db = serviceDb();
  await requireOnboarded(db, user.id);

  const now = Date.now();
  const room = await roomById(db, params.id);
  // A wrong code or token for a real room is exactly as "not found" as no room at all.
  const opens = room ? accessOpensRoom(room, body.access, now) : false;
  if (!room || !opens) throw notFound();
  if (!isOpen(room, now)) throw roomNotLive();

  if (room.demo_mode && (await isAdmin(db, user.id))) {
    const checkId = await recordLocationCheck(db, {
      userId: user.id,
      roomId: room.id,
      purpose: 'join',
      result: 'demo_skip',
      accuracyBucket: null,
    });
    logger.info('rooms.join.demo_skip', { roomId: room.id, userId: user.id });
    const ticket = await issueJoinTicket({
      userId: user.id,
      roomId: room.id,
      locationCheckId: checkId,
      result: 'demo_skip',
    });
    return {
      status: 200,
      body: { ticket: ticket.ticket, expiresAt: ticket.expiresAt.toISOString() },
    };
  }

  const check = checkFix({ lat: room.lat, lng: room.lng, radiusM: room.radius_m }, body.location);
  const checkId = await recordLocationCheck(db, {
    userId: user.id,
    roomId: room.id,
    purpose: 'join',
    result: check.outcome === 'pass' ? 'pass' : 'fail',
    accuracyBucket: check.accuracyBucket,
  });
  logger.info('rooms.join', { roomId: room.id, result: check.outcome });

  if (check.outcome === 'inaccurate') throw locationInaccurate();
  if (check.outcome === 'outside') throw notInRoom();

  const ticket = await issueJoinTicket({
    userId: user.id,
    roomId: room.id,
    locationCheckId: checkId,
    result: 'pass',
  });
  return {
    status: 200,
    body: { ticket: ticket.ticket, expiresAt: ticket.expiresAt.toISOString() },
  };
};
