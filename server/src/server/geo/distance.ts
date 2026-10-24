/**
 * Great-circle distance on a spherical Earth (haversine). Owner: B2.
 *
 * Rooms are a few hundred meters across, so the sphere's error (under 0.5%) is a
 * fraction of a meter at the edge of a room, far below any phone's GPS accuracy.
 */

/** The IUGG mean Earth radius, in meters. */
export const EARTH_RADIUS_M = 6_371_008.8;

export type LatLng = { readonly latitude: number; readonly longitude: number };

const toRadians = (degrees: number) => (degrees * Math.PI) / 180;
const toDegrees = (radians: number) => (radians * 180) / Math.PI;

/** Meters between two points. */
export function distanceMeters(a: LatLng, b: LatLng): number {
  const phi1 = toRadians(a.latitude);
  const phi2 = toRadians(b.latitude);
  const dPhi = toRadians(b.latitude - a.latitude);
  const dLambda = toRadians(b.longitude - a.longitude);
  const h = Math.sin(dPhi / 2) ** 2 + Math.cos(phi1) * Math.cos(phi2) * Math.sin(dLambda / 2) ** 2;
  return 2 * EARTH_RADIUS_M * Math.asin(Math.min(1, Math.sqrt(h)));
}

/**
 * The point `meters` away from `from` along `bearingDegrees` (0 is north, 90 east).
 * The exact inverse of `distanceMeters` on the same sphere, which is what the edge
 * tests need. Not used on the request path.
 */
export function destinationPoint(from: LatLng, bearingDegrees: number, meters: number): LatLng {
  const delta = meters / EARTH_RADIUS_M;
  const theta = toRadians(bearingDegrees);
  const phi1 = toRadians(from.latitude);
  const lambda1 = toRadians(from.longitude);
  const phi2 = Math.asin(
    Math.sin(phi1) * Math.cos(delta) + Math.cos(phi1) * Math.sin(delta) * Math.cos(theta),
  );
  const lambda2 =
    lambda1 +
    Math.atan2(
      Math.sin(theta) * Math.sin(delta) * Math.cos(phi1),
      Math.cos(delta) - Math.sin(phi1) * Math.sin(phi2),
    );
  return { latitude: toDegrees(phi2), longitude: ((toDegrees(lambda2) + 540) % 360) - 180 };
}
