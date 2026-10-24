/**
 * P2: user coordinates are never stored or logged. Only pass or fail is kept.
 *
 * Sends join requests with distinctive coordinates through every path the route can
 * take (pass, outside, too rough, malformed, demo skip, and a database failure that
 * ends in a 500), then checks that those numbers appear nowhere: not in anything the
 * logger was handed (before its redaction, so we don't rely on it), not on the console,
 * not in error reports, not in anything written to the database, and not in the reply.
 * Also audits the database schema: no table but `rooms` (a public venue) has a
 * coordinate or accuracy column.
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { destinationPoint } from '@/server/geo';
import { logger } from '@/server/log';
import * as observability from '@/server/observability';
import { memoryStore, setRateLimitStoreForTests } from '@/server/ratelimit';
import { setServiceDbForTests } from '@/server/rooms/db';
import * as joinRoute from '../../app/api/rooms/[id]/join/route';
import { mockVerify, USER_ID } from '../helpers/auth';
import { DEMO_CENTER, DEMO_ROOM_ID, FakeDb, demoRoom, onboarded } from './fake-db';
import { call, captureLogs } from './helpers';

vi.mock('@/server/auth/verify', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@/server/auth/verify')>();
  return { ...actual, verifyAccessToken: vi.fn() };
});
vi.mock('@/server/http/operations', async () => ({
  operations: (await import('@/contracts/operations')).operations,
}));
vi.mock('@/server/observability', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@/server/observability')>();
  return { ...actual, captureError: vi.fn() };
});

const LINK = { kind: 'link', slug: 'demo', token: 'DEMOSTATICTOKEN2' } as const;

/** Distinctive values that can't appear by chance. Near the demo venue, test data only. */
const INSIDE = { latitude: 37.80291357, longitude: -122.44842468, accuracy: 7.31864 };
const OUTSIDE = {
  ...destinationPoint(DEMO_CENTER, 37, 1234.5678),
  accuracy: 6.92751,
};
const ROUGH = { latitude: 37.80297531, longitude: -122.44849753, accuracy: 731.42857 };
const MALFORMED = { latitude: 91.13579, longitude: -122.44841357, accuracy: 5.86421 };

/** Every way a coordinate could be written down: full, rounded, and trimmed forms. */
function needles(fix: { latitude: number; longitude: number; accuracy: number }): string[] {
  const out = new Set<string>();
  for (const value of [fix.latitude, fix.longitude, fix.accuracy]) {
    const abs = Math.abs(value);
    out.add(String(value));
    out.add(String(abs));
    for (const digits of [4, 5, 6, 7]) out.add(abs.toFixed(digits));
  }
  // A 4-decimal latitude near the venue center would match the room's own public
  // location, which is fine to store. Only fixes' own digits are needles.
  out.delete(Math.abs(DEMO_CENTER.latitude).toFixed(4));
  out.delete(Math.abs(DEMO_CENTER.longitude).toFixed(4));
  return [...out].filter((s) => s.replace(/\D/g, '').length >= 5);
}

let db: FakeDb;
let loggerFields: unknown[];

beforeEach(async () => {
  await mockVerify();
  setRateLimitStoreForTests(memoryStore());
  db = new FakeDb({
    rooms: [demoRoom()],
    profiles: [onboarded(USER_ID)],
    admins: [],
    location_checks: [],
  });
  setServiceDbForTests(db.asDb());
  loggerFields = [];
  for (const level of ['debug', 'info', 'warn', 'error'] as const) {
    const original = logger[level];
    vi.spyOn(logger, level).mockImplementation((event, fields) => {
      loggerFields.push({ event, fields });
      original(event, fields);
    });
  }
  vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(null, { status: 202 }));
});

afterEach(() => {
  setServiceDbForTests(undefined);
  setRateLimitStoreForTests(undefined);
});

const join = (location: unknown) =>
  call(joinRoute.POST, {
    path: `/api/rooms/${DEMO_ROOM_ID}/join`,
    json: { access: LINK, location },
    params: { id: DEMO_ROOM_ID },
  });

function expectNoCoordinates(haystack: string, fix: Parameters<typeof needles>[0]) {
  for (const needle of needles(fix)) {
    expect(haystack, `found ${needle}`).not.toContain(needle);
  }
}

describe('P2: no coordinates in logs, error reports, the database or replies', () => {
  it.each([
    ['a pass', INSIDE, 200],
    ['a fix outside the room', OUTSIDE, 422],
    ['a fix that is too rough', ROUGH, 422],
    ['a malformed fix', MALFORMED, 400],
  ] as const)('for %s', async (_label, fix, status) => {
    const { result, lines } = await captureLogs(() => join(fix));
    expect(result.status).toBe(status);

    expect(lines.length).toBeGreaterThan(0); // the request was logged at all
    expectNoCoordinates(lines.join('\n'), fix);
    expectNoCoordinates(JSON.stringify(loggerFields), fix);
    expectNoCoordinates(JSON.stringify(db.writes), fix);
    expectNoCoordinates(result.text, fix);
    expect(vi.mocked(observability.captureError)).not.toHaveBeenCalled();
  });

  it('for a demo mode skip', async () => {
    db.tables.rooms = [demoRoom({ demo_mode: true })];
    db.tables.admins = [{ user_id: USER_ID }];
    const { result, lines } = await captureLogs(() => join(OUTSIDE));
    expect(result.status).toBe(200);
    expect(lines.some((l) => l.includes('rooms.join.demo_skip'))).toBe(true);
    expectNoCoordinates(lines.join('\n') + JSON.stringify(loggerFields), OUTSIDE);
    expectNoCoordinates(JSON.stringify(db.writes), OUTSIDE);
  });

  it('for a database failure that ends in a 500, including the error report', async () => {
    db.failInsertsInto.add('location_checks');
    const { result, lines } = await captureLogs(() => join(INSIDE));
    expect(result.status).toBe(500);
    expectNoCoordinates(lines.join('\n'), INSIDE);
    expectNoCoordinates(JSON.stringify(loggerFields), INSIDE);
    expectNoCoordinates(result.text, INSIDE);
    const reports = vi.mocked(observability.captureError).mock.calls;
    expect(reports).toHaveLength(1);
    const [error, tags] = reports[0]!;
    expectNoCoordinates(
      JSON.stringify({ message: (error as Error).message, stack: (error as Error).stack, tags }),
      INSIDE,
    );
  });

  it('stores only the outcome and a bucket for each check', async () => {
    await join(INSIDE);
    await join(OUTSIDE);
    await join(ROUGH);
    const keys = new Set(db.writes.flatMap((w) => Object.keys(w.values)));
    expect([...keys].sort()).toEqual([
      'accuracy_bucket',
      'purpose',
      'result',
      'room_id',
      'user_id',
    ]);
    expect(db.writes.map((w) => w.values.result)).toEqual(['pass', 'fail', 'fail']);
  });
});

describe('P2: database column audit', () => {
  it('has no coordinate or accuracy column outside `rooms`', () => {
    const file = fileURLToPath(new URL('../../src/contracts/database.ts', import.meta.url));
    const source = readFileSync(file, 'utf8');
    const tables = source.slice(source.indexOf('Tables: {'), source.indexOf('Views: {'));
    const rowBlocks = [...tables.matchAll(/"(\w+)": \{\s*Row: \{([^}]*)\}/g)];
    expect(rowBlocks.length).toBeGreaterThan(10);
    const suspicious =
      /"(lat|lng|lon|latitude|longitude|coords?|coordinates?|accuracy|location|geo\w*|altitude)"\s*:/;
    for (const [, table, columns] of rowBlocks) {
      if (table === 'rooms') continue; // the venue's own public location
      expect(columns, `${table} has a coordinate column`).not.toMatch(suspicious);
    }
  });
});
