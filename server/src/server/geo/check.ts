/**
 * The room location check (docs/SPEC.md, Location check). Owner: B2.
 *
 * A fix passes when its distance from the room's center, minus the smaller of its
 * reported accuracy and GEO_ACCURACY_CREDIT, is within the room's radius. Fixes less
 * accurate than GEO_MAX_ACCURACY are refused outright, so the person tries again.
 *
 * Pure and synchronous: it takes the fix, answers, and keeps nothing. Callers store
 * only the outcome and the accuracy bucket, never the fix (P2).
 */
import { GEO_ACCURACY_CREDIT_METERS, GEO_MAX_ACCURACY_METERS } from '@/contracts';
import { distanceMeters } from './distance';

export type RoomArea = {
  readonly lat: number;
  readonly lng: number;
  readonly radiusM: number;
};

export type Fix = {
  readonly latitude: number;
  readonly longitude: number;
  /** Horizontal accuracy in meters, as CoreLocation reports it. */
  readonly accuracy: number;
};

/** The `accuracy_bucket` enum in the database: the only trace of a fix that's kept. */
export type AccuracyBucket = 'under_20m' | 'under_50m' | 'under_100m' | 'under_500m' | 'over_500m';

export type CheckOutcome = 'pass' | 'outside' | 'inaccurate';

export type CheckResult = {
  readonly outcome: CheckOutcome;
  readonly accuracyBucket: AccuracyBucket;
};

/** A rough bucket, so metrics can tell bad GPS from people outside the room. */
export function accuracyBucket(accuracy: number): AccuracyBucket {
  if (!Number.isFinite(accuracy) || accuracy > GEO_MAX_ACCURACY_METERS) return 'over_500m';
  if (accuracy < 20) return 'under_20m';
  if (accuracy < 50) return 'under_50m';
  if (accuracy < 100) return 'under_100m';
  return 'under_500m';
}

/** Whether the fix is inside the room. Exactly at the edge counts as inside. */
export function checkFix(room: RoomArea, fix: Fix): CheckResult {
  const bucket = accuracyBucket(fix.accuracy);
  const usable =
    Number.isFinite(fix.latitude) &&
    Number.isFinite(fix.longitude) &&
    Number.isFinite(fix.accuracy) &&
    fix.accuracy > 0 &&
    fix.accuracy <= GEO_MAX_ACCURACY_METERS;
  if (!usable) return { outcome: 'inaccurate', accuracyBucket: bucket };

  const distance = distanceMeters(
    { latitude: room.lat, longitude: room.lng },
    { latitude: fix.latitude, longitude: fix.longitude },
  );
  const credit = Math.min(fix.accuracy, GEO_ACCURACY_CREDIT_METERS);
  return {
    outcome: distance - credit <= room.radiusM ? 'pass' : 'outside',
    accuracyBucket: bucket,
  };
}
