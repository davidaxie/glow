/**
 * Keeps the outcome of a location check, and nothing else (P2). Owner: B2.
 *
 * One `location_checks` row per check: person, room, purpose (join or find), result
 * (pass, fail or demo_skip) and a rough accuracy bucket. Never coordinates, never the
 * raw accuracy. `create_checkin` and `set_choice` read these rows (D17), and purge
 * deletes them after LOCATION_CHECK_RETENTION.
 *
 * C2's Find check uses this too: `checkFix` then `recordLocationCheck` with purpose `find`.
 */
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '@/contracts';
import type { AccuracyBucket } from './check';

export type LocationCheckPurpose = Database['public']['Enums']['location_check_purpose'];
export type LocationCheckResult = Database['public']['Enums']['location_check_result'];

export type LocationCheckRecord = {
  readonly userId: string;
  readonly roomId: string;
  readonly purpose: LocationCheckPurpose;
  readonly result: LocationCheckResult;
  readonly accuracyBucket: AccuracyBucket | null;
};

/** Inserts the row and returns its ID. Throws if the database refuses. */
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
