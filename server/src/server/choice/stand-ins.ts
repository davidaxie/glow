/**
 * Stand-ins for modules other agents are still building. Owner: C2.
 *
 * Each one has the real export's signature, so swapping it in changes no behavior. When the
 * owner's PR merges, C2 points `./deps` at theirs and deletes the stand-in here
 * (docs/HANDOFFS.md, C2 · Still mocked):
 *
 * - `notify`              → B5's `notify()` in `@/server/notify` (#15). This one broadcasts over
 *                           Realtime only; the Apple push is B5's.
 * - `rateLimit`           → B8's `rateLimit()` in `@/server/ratelimit` (#12). A no-op here.
 * - `checkFix`,
 *   `recordLocationCheck` → B2's `@/server/geo` (#10). The same rule and the same row.
 */
import type { SupabaseClient } from '@supabase/supabase-js';
import {
  GEO_ACCURACY_CREDIT_METERS,
  GEO_MAX_ACCURACY_METERS,
  userTopic,
  type Database,
  type GlowEvent,
} from '@/contracts';
import { getEnv } from '@/env';
import { logger } from '@/server/log';

// ---------------------------------------------------------------------------------- notify

/** An event for one person's `user:{id}` channel: only the type and a match ID (P1, P6). */
export type UserEvent = Extract<GlowEvent, { matchId: string }>;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Sends `event` to each person's private channel. Never throws: a missed event is logged,
 * and the app refetches when it next opens the match.
 */
export async function notify(
  userIds: string | readonly string[],
  event: UserEvent,
): Promise<unknown> {
  const people = [
    ...new Set((typeof userIds === 'string' ? [userIds] : userIds).map((id) => id.toLowerCase())),
  ].filter((id) => UUID.test(id));
  if (people.length === 0) return { realtime: 'skipped' };
  // Rebuilt from the contract's two fields, so nothing else can ride along.
  const payload = { type: event.type, matchId: event.matchId.toLowerCase() };
  const env = getEnv();
  const key = env.SUPABASE_SERVICE_ROLE_KEY;
  try {
    const res = await fetch(new URL('/realtime/v1/api/broadcast', env.SUPABASE_URL), {
      method: 'POST',
      headers: {
        apikey: key,
        ...(/^[\w-]+\.[\w-]+\.[\w-]+$/.test(key) ? { authorization: `Bearer ${key}` } : {}),
        'content-type': 'application/json',
      },
      body: JSON.stringify({
        messages: people.map((id) => ({
          topic: userTopic(id),
          event: payload.type,
          payload,
          private: true,
        })),
      }),
      signal: AbortSignal.timeout(3000),
    });
    await res.arrayBuffer().catch(() => undefined);
    const realtime = res.ok ? 'sent' : 'failed';
    logger.info('choice.notify', { type: payload.type, people: people.length, realtime });
    return { realtime };
  } catch (error) {
    logger.warn('choice.notify_failed', {
      type: payload.type,
      errorClass: error instanceof Error ? error.name : typeof error,
    });
    return { realtime: 'failed' };
  }
}

// ------------------------------------------------------------------------------- rateLimit

export type RateLimitPolicyName = 'join' | 'api';

/** Counts one request against `policy`, and throws 429 when it's over. A no-op for now. */
export async function rateLimit(_key: string, _policy: RateLimitPolicyName): Promise<void> {}

// ------------------------------------------------------------------------------------- geo

export type RoomArea = { readonly lat: number; readonly lng: number; readonly radiusM: number };
export type Fix = {
  readonly latitude: number;
  readonly longitude: number;
  readonly accuracy: number;
};
export type AccuracyBucket = 'under_20m' | 'under_50m' | 'under_100m' | 'under_500m' | 'over_500m';
export type CheckOutcome = 'pass' | 'outside' | 'inaccurate';
export type CheckResult = {
  readonly outcome: CheckOutcome;
  readonly accuracyBucket: AccuracyBucket;
};

export function accuracyBucket(accuracy: number): AccuracyBucket {
  if (!Number.isFinite(accuracy) || accuracy > GEO_MAX_ACCURACY_METERS) return 'over_500m';
  if (accuracy < 20) return 'under_20m';
  if (accuracy < 50) return 'under_50m';
  if (accuracy < 100) return 'under_100m';
  return 'under_500m';
}

const EARTH_RADIUS_M = 6_371_008.8;
const rad = (degrees: number) => (degrees * Math.PI) / 180;

function distanceMeters(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const h =
    Math.sin(rad(lat2 - lat1) / 2) ** 2 +
    Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(rad(lng2 - lng1) / 2) ** 2;
  return 2 * EARTH_RADIUS_M * Math.asin(Math.min(1, Math.sqrt(h)));
}

/**
 * The spec's location check: the distance from the room's center, minus the smaller of the
 * fix's accuracy and GEO_ACCURACY_CREDIT, is within the radius. Fixes rougher than
 * GEO_MAX_ACCURACY are refused. Pure: it keeps nothing (P2).
 */
export function checkFix(room: RoomArea, fix: Fix): CheckResult {
  const bucket = accuracyBucket(fix.accuracy);
  const usable =
    Number.isFinite(fix.latitude) &&
    Number.isFinite(fix.longitude) &&
    Number.isFinite(fix.accuracy) &&
    fix.accuracy > 0 &&
    fix.accuracy <= GEO_MAX_ACCURACY_METERS;
  if (!usable) return { outcome: 'inaccurate', accuracyBucket: bucket };
  const distance = distanceMeters(room.lat, room.lng, fix.latitude, fix.longitude);
  const credit = Math.min(fix.accuracy, GEO_ACCURACY_CREDIT_METERS);
  return {
    outcome: distance - credit <= room.radiusM ? 'pass' : 'outside',
    accuracyBucket: bucket,
  };
}

export type LocationCheckRecord = {
  readonly userId: string;
  readonly roomId: string;
  readonly purpose: Database['public']['Enums']['location_check_purpose'];
  readonly result: Database['public']['Enums']['location_check_result'];
  readonly accuracyBucket: AccuracyBucket | null;
};

/** One `location_checks` row: pass or fail and a rough bucket, never coordinates (P2). */
export async function recordLocationCheck(
  db: SupabaseClient<Database>,
  record: LocationCheckRecord,
): Promise<string> {
  const { data, error } = await db
    .from('location_checks')
    .insert({
      user_id: record.userId,
      room_id: record.roomId,
      purpose: record.purpose,
      result: record.result,
      accuracy_bucket: record.accuracyBucket,
    })
    .select('id')
    .single();
  if (error || !data) throw new Error('location_checks insert failed');
  return data.id;
}
