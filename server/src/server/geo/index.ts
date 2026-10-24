// Owner: B2. The room location check and its pass-or-fail record (P2).
export { distanceMeters, destinationPoint, EARTH_RADIUS_M, type LatLng } from './distance';
export {
  accuracyBucket,
  checkFix,
  type AccuracyBucket,
  type CheckOutcome,
  type CheckResult,
  type Fix,
  type RoomArea,
} from './check';
export {
  recordLocationCheck,
  type LocationCheckPurpose,
  type LocationCheckRecord,
  type LocationCheckResult,
} from './record';
