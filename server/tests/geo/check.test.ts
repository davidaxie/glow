/**
 * The room location check (B2): distance math, the accuracy credit, and the edge of the
 * radius, measured to the millimeter. Test coordinates are the seeded demo room's
 * public venue (a placeholder, D11), never a person's.
 */
import { describe, expect, it } from 'vitest';
import { GEO_ACCURACY_CREDIT_METERS, GEO_MAX_ACCURACY_METERS } from '@/contracts';
import { accuracyBucket, checkFix, destinationPoint, distanceMeters } from '@/server/geo';

const CENTER = { latitude: 37.8029, longitude: -122.4484 };
const ROOM = { lat: CENTER.latitude, lng: CENTER.longitude, radiusM: 200 };
/** 1 mm: well under any GPS accuracy, well over floating point error at these distances. */
const MM = 0.001;

const at = (meters: number, bearing = 0) => destinationPoint(CENTER, bearing, meters);
const fixAt = (meters: number, accuracy: number, bearing = 0) => ({
  ...at(meters, bearing),
  accuracy,
});

describe('distanceMeters', () => {
  it('is zero for the same point', () => {
    expect(distanceMeters(CENTER, CENTER)).toBe(0);
  });

  it('matches a known distance: one degree of latitude is about 111.2 km', () => {
    const d = distanceMeters({ latitude: 0, longitude: 0 }, { latitude: 1, longitude: 0 });
    expect(d).toBeCloseTo(111_195, 0);
  });

  it('matches a known distance between two San Francisco landmarks', () => {
    // Palace of Fine Arts to the Ferry Building is about 4.6 km.
    const ferryBuilding = { latitude: 37.7955, longitude: -122.3937 };
    expect(distanceMeters(CENTER, ferryBuilding)).toBeGreaterThan(4_700);
    expect(distanceMeters(CENTER, ferryBuilding)).toBeLessThan(4_900);
  });

  it('is symmetric', () => {
    const p = at(321, 77);
    expect(distanceMeters(CENTER, p)).toBeCloseTo(distanceMeters(p, CENTER), 9);
  });

  it.each([0, 45, 90, 135, 180, 225, 270, 315])(
    'round-trips destinationPoint at bearing %i',
    (bearing) => {
      expect(distanceMeters(CENTER, at(200, bearing))).toBeCloseTo(200, 6);
    },
  );

  it('handles the antimeridian', () => {
    const d = distanceMeters(
      { latitude: 0, longitude: 179.9999 },
      { latitude: 0, longitude: -179.9999 },
    );
    expect(d).toBeCloseTo(22.24, 1);
  });
});

describe('checkFix at the edge of the radius', () => {
  it.each([0, 90, 180, 270])('passes 1 mm inside radius + credit (bearing %i)', (bearing) => {
    // accuracy 100 gives the full credit, so the edge is 200 + 100 = 300 m.
    expect(checkFix(ROOM, fixAt(300 - MM, 100, bearing)).outcome).toBe('pass');
  });

  it.each([0, 90, 180, 270])('counts exactly on the edge as inside (bearing %i)', (bearing) => {
    // Build the room around the fix's measured distance, so "exactly" is exact in floats.
    const fix = fixAt(300, 100, bearing);
    const measured = distanceMeters(CENTER, fix);
    const credit = GEO_ACCURACY_CREDIT_METERS;
    expect(checkFix({ ...ROOM, radiusM: measured - credit }, fix).outcome).toBe('pass');
    expect(checkFix({ ...ROOM, radiusM: measured - credit - MM }, fix).outcome).toBe('outside');
  });

  it.each([0, 90, 180, 270])('fails just past radius + credit (bearing %i)', (bearing) => {
    expect(checkFix(ROOM, fixAt(300 + MM, 100, bearing)).outcome).toBe('outside');
    expect(checkFix(ROOM, fixAt(300 + 1, 100, bearing)).outcome).toBe('outside');
  });

  it('credits the accuracy itself when it is under GEO_ACCURACY_CREDIT', () => {
    expect(checkFix(ROOM, fixAt(200 + 5, 5)).outcome).toBe('pass');
    expect(checkFix(ROOM, fixAt(200 + 5 + MM, 5)).outcome).toBe('outside');
  });

  it('never credits more than GEO_ACCURACY_CREDIT, however rough the fix', () => {
    const edge = 200 + GEO_ACCURACY_CREDIT_METERS;
    expect(checkFix(ROOM, fixAt(edge, 400)).outcome).toBe('pass');
    expect(checkFix(ROOM, fixAt(edge + MM, 400)).outcome).toBe('outside');
    expect(checkFix(ROOM, fixAt(edge + MM, GEO_MAX_ACCURACY_METERS)).outcome).toBe('outside');
  });

  it('passes at the center and anywhere well inside', () => {
    expect(checkFix(ROOM, { ...CENTER, accuracy: 5 }).outcome).toBe('pass');
    expect(checkFix(ROOM, fixAt(150, 5, 33)).outcome).toBe('pass');
  });

  it('fails the away spot `sim.sh at away` uses, 2 km north', () => {
    const away = { latitude: CENTER.latitude + 2000 / 111_320, longitude: CENTER.longitude };
    expect(checkFix(ROOM, { ...away, accuracy: 5 }).outcome).toBe('outside');
  });

  it('uses the room radius', () => {
    const small = { ...ROOM, radiusM: 10 };
    expect(checkFix(small, fixAt(15, 5)).outcome).toBe('pass');
    expect(checkFix(small, fixAt(15 + MM, 5)).outcome).toBe('outside');
  });
});

describe('checkFix refuses unusable fixes', () => {
  it('accepts accuracy right at GEO_MAX_ACCURACY and refuses anything rougher', () => {
    expect(checkFix(ROOM, { ...CENTER, accuracy: GEO_MAX_ACCURACY_METERS }).outcome).toBe('pass');
    expect(checkFix(ROOM, { ...CENTER, accuracy: GEO_MAX_ACCURACY_METERS + MM }).outcome).toBe(
      'inaccurate',
    );
  });

  it.each([0, -1, Number.NaN, Number.POSITIVE_INFINITY])('refuses accuracy %s', (accuracy) => {
    expect(checkFix(ROOM, { ...CENTER, accuracy }).outcome).toBe('inaccurate');
  });

  it('refuses non-finite coordinates', () => {
    expect(checkFix(ROOM, { latitude: Number.NaN, longitude: 0, accuracy: 5 }).outcome).toBe(
      'inaccurate',
    );
  });
});

describe('accuracyBucket', () => {
  it.each([
    [0.5, 'under_20m'],
    [19.99, 'under_20m'],
    [20, 'under_50m'],
    [49.99, 'under_50m'],
    [50, 'under_100m'],
    [99.99, 'under_100m'],
    [100, 'under_500m'],
    [500, 'under_500m'],
    [500.01, 'over_500m'],
    [Number.NaN, 'over_500m'],
  ] as const)('puts %s m in %s', (accuracy, bucket) => {
    expect(accuracyBucket(accuracy)).toBe(bucket);
  });
});
