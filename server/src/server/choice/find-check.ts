/**
 * The fresh location check before Find. Owner: C2.
 *
 * Choosing Find repeats the room check (docs/SPEC.md, Location check, step 6), and `set_choice`
 * then needs a passed `location_checks` row from the last GEO_FRESHNESS_FOR_GLOW (D17).
 *
 * Order, so nothing leaks (P11): the match must be the caller's and not ended (404) before the
 * fix is looked at. If the choice can no longer matter (choosing is over, or its window ran
 * out), the fix is never looked at or recorded, and `set_choice` answers `already_decided` or
 * `timeout` (C2-D1).
 *
 * P2: the fix is used for one distance calculation and dropped. Only pass or fail and a rough
 * accuracy bucket are stored, and nothing about the fix is logged. In a demo mode room, admins
 * skip the check, and the skip is stored as `demo_skip` and logged.
 */
import type { LocationFix } from '@/contracts';
import { notFound, unprocessable } from '@/server/http';
import { logger } from '@/server/log';
import type { Db } from './db';
import { checkFix, recordLocationCheck } from './deps';
import { DatabaseError, locationRequired } from './rpc';

export const notInRoom = () =>
  unprocessable('not_in_room', "Looks like you're not in this room yet. Try again inside.");
export const locationInaccurate = () =>
  unprocessable('location_inaccurate', 'The location fix is too rough. Try again.');

type MatchForFind = {
  readonly room_id: string;
  readonly user_a: string;
  readonly user_b: string;
  readonly status: string;
  readonly choice_deadline: string;
};

async function matchForFind(db: Db, matchId: string): Promise<MatchForFind | null> {
  const { data, error } = await db
    .from('matches')
    .select('room_id, user_a, user_b, status, choice_deadline')
    .eq('id', matchId)
    .maybeSingle();
  if (error) throw new DatabaseError('matches lookup failed');
  return data;
}

async function roomArea(db: Db, roomId: string) {
  const { data, error } = await db
    .from('rooms')
    .select('lat, lng, radius_m, demo_mode')
    .eq('id', roomId)
    .maybeSingle();
  if (error || !data) throw new DatabaseError('rooms lookup failed');
  return data;
}

async function isAdmin(db: Db, userId: string): Promise<boolean> {
  const { data, error } = await db
    .from('admins')
    .select('user_id')
    .eq('user_id', userId)
    .maybeSingle();
  if (error) throw new DatabaseError('admins lookup failed');
  return data !== null;
}

/**
 * Checks the fix for Find and records the outcome. Returns normally when `set_choice` may go
 * ahead; throws 404, or 422 `location_required`, `location_inaccurate` or `not_in_room`.
 */
export async function checkFindLocation(
  db: Db,
  userId: string,
  matchId: string,
  fix: LocationFix | undefined,
  nowMs = Date.now(),
): Promise<void> {
  const match = await matchForFind(db, matchId);
  if (!match || (match.user_a !== userId && match.user_b !== userId) || match.status === 'ended') {
    throw notFound();
  }
  // Too late for Find to matter: set_choice says so without the fix ever being looked at.
  if (match.status !== 'choosing' || Date.parse(match.choice_deadline) <= nowMs) return;
  if (!fix) throw locationRequired();

  const room = await roomArea(db, match.room_id);
  if (room.demo_mode && (await isAdmin(db, userId))) {
    await recordLocationCheck(db, {
      userId,
      roomId: match.room_id,
      purpose: 'find',
      result: 'demo_skip',
      accuracyBucket: null,
    });
    logger.info('choice.find_check.demo_skip', { matchId, roomId: match.room_id });
    return;
  }

  const check = checkFix({ lat: room.lat, lng: room.lng, radiusM: room.radius_m }, fix);
  await recordLocationCheck(db, {
    userId,
    roomId: match.room_id,
    purpose: 'find',
    result: check.outcome === 'pass' ? 'pass' : 'fail',
    accuracyBucket: check.accuracyBucket,
  });
  logger.info('choice.find_check', { matchId, result: check.outcome });
  if (check.outcome === 'inaccurate') throw locationInaccurate();
  if (check.outcome === 'outside') throw notInRoom();
}
