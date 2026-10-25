/**
 * Every operation in the contract, hit by a signed-in person with hostile input: made-up and
 * malformed IDs, oversized and wrongly typed bodies, NUL bytes and control characters in every
 * string, and prototype-pollution keys. Nothing may answer 5xx or 403, nothing may echo what
 * was sent, and no reply may carry a stack trace or a secret. Runs against a live stack so
 * the database's own limits are part of it.
 */
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { resetEnvCacheForTests } from '@/env';
import { setRateLimitStoreForTests } from '@/server/ratelimit';
import type { OperationDef } from '@/server/http/operation';
import { operations, type OperationId } from '@/server/http/operations';
import { call } from './helpers/api';
import { LIVE, type Live } from './helpers/live';
import { World, type Person } from './helpers/world';

const live = LIVE as Live;
let world: World;
let me: Person;

beforeAll(async () => {
  if (!LIVE) return;
  world = new World(live);
  me = await world.person();
}, 30_000);
beforeEach(() => {
  if (!LIVE) return;
  process.env.SUPABASE_URL = live.url;
  process.env.SUPABASE_ANON_KEY = live.anonKey;
  process.env.SUPABASE_SERVICE_ROLE_KEY = live.serviceKey;
  resetEnvCacheForTests();
  // Rate limits are tested elsewhere (B8); here they'd stop the hostile input short of the
  // database after a few calls.
  setRateLimitStoreForTests({
    name: 'test',
    hit: async () => ({ allowed: true, remaining: 999, resetAt: Date.now() + 1000 }),
  });
});
afterAll(async () => {
  if (LIVE) await world.cleanup();
});

const NOBODY = '00000000-0000-4000-8000-0000000000f2';
const MARK = 'D2MARK';
const HOSTILE_STRINGS = [
  `${MARK}\u0000nul`,
  `${MARK}\u001b[2J\u0007\r\n`,
  `${MARK}'; drop table profiles; --`,
  `${MARK}<script>alert(1)</script>`,
  `${MARK}${'é'.repeat(5000)}`,
  `${MARK}\uD800lone-surrogate`,
  `${MARK}../../etc/passwd`,
];

/** Replaces every string in a JSON value with `s`. */
function fill(value: unknown, s: string): unknown {
  if (typeof value === 'string') return s;
  if (Array.isArray(value)) return value.map((v) => fill(v, s));
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, fill(v, s)]));
  }
  return value;
}

/** Plausible bodies for the operations that take one, so the hostile strings go deep. */
const BODIES: Partial<Record<OperationId, unknown>> = {
  joinRoom: {
    access: { kind: 'link', slug: 'demo', token: 'DEMOSTATICTOKEN2' },
    location: { latitude: 37.8, longitude: -122.4, accuracy: 10 },
  },
  resolveRoom: { kind: 'code', code: 'HACK26' },
  createTap: { cardId: NOBODY },
  getDeck: { filters: { topColor: ['blue'], extras: ['glasses'] }, offset: 0 },
  setChoice: { choice: 'chat' },
  sendMessage: { body: 'hello' },
  createBlock: { context: 'chat', contextId: NOBODY },
  createReport: { context: 'chat', contextId: NOBODY, reason: 'spam', details: 'details' },
  logCapture: { kind: 'screenshot', roomId: NOBODY },
  registerDevice: { apnsToken: 'a'.repeat(64), environment: 'sandbox', appVersion: '1.0' },
  setPaused: { paused: false },
  updateProfile: { firstName: 'Sam', birthdate: '1995-05-05', gender: 'woman', showMe: ['man'] },
  addProfilePhoto: { image: 'AAAA' },
  createCheckin: { ticket: 'x', photo: 'AAAA', tags: { topColor: 'blue' } },
};

const userOps = (Object.entries(operations) as unknown as [OperationId, OperationDef][]).filter(
  ([id, op]) => op.auth === 'user' && !id.startsWith('admin') && id !== 'deleteAccount',
);

const SAMPLE_PARAMS: Record<string, string[]> = {
  id: [NOBODY, 'not-a-uuid', '%00', '..%2F..%2Fetc', 'A'.repeat(300)],
  cardId: [NOBODY, 'not-a-uuid'],
  n: ['0', '-1', '999999999999', 'NaN'],
};

describe.skipIf(!LIVE)('hostile input to every operation (live)', () => {
  it('covers a real number of operations', () => {
    expect(userOps.length).toBeGreaterThan(25);
  });

  for (const [id, op] of userOps) {
    it(`${id}: no 5xx, no 403, nothing echoed`, async () => {
      const paramNames = [...op.path.matchAll(/\{(\w+)\}/g)].map((m) => m[1]!);
      const base = BODIES[id];
      const bodies: unknown[] = [];
      if (op.body !== undefined) {
        bodies.push(
          ...HOSTILE_STRINGS.map((s) => fill(base ?? {}, s)),
          [],
          'a string',
          12345,
          null,
          { __proto__: { admin: true }, constructor: { prototype: { admin: true } } },
          JSON.parse('{"__proto__":{"admin":true},"toString":1}'),
          { ...(base as object), extra: { deep: [[[[[MARK]]]]] } },
          fill(base ?? {}, 'x'.repeat(200_000)),
        );
      } else {
        bodies.push(undefined);
      }
      const replies: { status: number; text: string }[] = [];
      for (const body of bodies) {
        const params: Record<string, string> = {};
        for (const [i, name] of paramNames.entries()) {
          const choices = SAMPLE_PARAMS[name] ?? [NOBODY];
          params[name] = choices[i % choices.length]!;
        }
        for (const first of paramNames.length
          ? (SAMPLE_PARAMS[paramNames[0]!] ?? [NOBODY])
          : [null]) {
          if (first !== null) params[paramNames[0]!] = first;
          const reply = await call(id, {
            token: me.token,
            params,
            ...(body === undefined ? {} : { body }),
            ...(op.method === 'GET' && op.query
              ? { query: { before: HOSTILE_STRINGS[0]!, limit: '999999' } }
              : {}),
          }).catch((e: unknown) => ({
            status: 599,
            text: `threw ${(e as Error).message}`,
            headers: new Headers(),
          }));
          replies.push({ status: reply.status, text: reply.text });
        }
      }
      for (const r of replies) {
        if (r.status === 501) continue; // an owner's route that hasn't merged yet
        expect(r.status, `${id}: ${r.text.slice(0, 200)}`).toBeLessThan(500);
        expect(r.status).not.toBe(403);
        expect(r.text).not.toContain(MARK);
        expect(r.text).not.toMatch(
          /\bat \S+ \(.*:\d+:\d+\)|node_modules|\.ts:\d+|stack|sb_secret_|service_role/i,
        );
      }
    }, 120_000);
  }
});
