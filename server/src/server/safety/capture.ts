/**
 * Owner: B8. Screenshots and screen recordings of the deck (C1 reports them, P12).
 * Each one is an `abuse_signals` row: the person, the room and the kind, nothing else.
 * Reaching CAPTURE_REVIEW_THRESHOLD in CAPTURE_REVIEW_WINDOW flags the account for review
 * (B7 lists flagged accounts from `abuse_signals`).
 */
import type { CaptureRequest } from '@/contracts';
import { logger } from '@/server/log';
import { dbError, serviceDb } from './db';

export const CAPTURE_REVIEW_THRESHOLD = 3;
export const CAPTURE_REVIEW_WINDOW_SECONDS = 24 * 60 * 60;

export async function logCaptureFor(userId: string, request: CaptureRequest): Promise<void> {
  const db = serviceDb();
  // Keep the room only if this person has a check-in there. The contract has no 404 here,
  // and a made-up room ID must not land in the table or say whether that room exists.
  const checkin = await db
    .from('checkins')
    .select('room_id')
    .eq('user_id', userId)
    .eq('room_id', request.roomId)
    .limit(1);
  if (checkin.error) throw dbError('capture', checkin.error);
  const roomId = checkin.data.length > 0 ? request.roomId : null;

  const inserted = await db
    .from('abuse_signals')
    .insert({ user_id: userId, room_id: roomId, kind: request.kind });
  if (inserted.error) throw dbError('capture', inserted.error);

  const since = new Date(Date.now() - CAPTURE_REVIEW_WINDOW_SECONDS * 1000).toISOString();
  const recent = await db
    .from('abuse_signals')
    .select('id', { count: 'exact', head: true })
    .eq('user_id', userId)
    .gte('created_at', since);
  const count = recent.count ?? 0;
  logger.info('safety.capture', { kind: request.kind, inRoom: roomId !== null, recent: count });
  if (count === CAPTURE_REVIEW_THRESHOLD) {
    logger.warn('safety.capture_review', { userId, recent: count });
  }
}
