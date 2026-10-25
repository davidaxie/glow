/**
 * B7 asked D2 to try the admin area as a non-admin (docs/HANDOFFS.md, B7's notes): every
 * `/api/admin/*` operation must answer a signed-in non-admin with the same 404 whatever they
 * send (P11), before reading the path, query or body, and a signed-out caller with 401. The
 * ordinary admin works. The admin web's pages and server actions are B7's own tests.
 */
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { resetEnvCacheForTests } from '@/env';
import type { OperationDef } from '@/server/http/operation';
import { operations, type OperationId } from '@/server/http/operations';
import { setRateLimitStoreForTests } from '@/server/ratelimit';
import { call } from './helpers/api';
import { LIVE, type Live } from './helpers/live';
import { World, type Person } from './helpers/world';

const live = LIVE as Live;
let world: World;
let user: Person;
let admin: Person;

const adminOps = (Object.entries(operations) as unknown as [OperationId, OperationDef][]).filter(
  ([id]) => id.startsWith('admin'),
);
const NOBODY = '00000000-0000-4000-8000-0000000000ad';

beforeAll(async () => {
  if (!LIVE) return;
  world = new World(live);
  [user, admin] = await Promise.all([world.person(), world.person()]);
  await world.db.from('admins').insert({ user_id: admin.id });
}, 30_000);
beforeEach(() => {
  if (!LIVE) return;
  process.env.SUPABASE_URL = live.url;
  process.env.SUPABASE_ANON_KEY = live.anonKey;
  process.env.SUPABASE_SERVICE_ROLE_KEY = live.serviceKey;
  resetEnvCacheForTests();
  setRateLimitStoreForTests({
    name: 'test',
    hit: async () => ({ allowed: true, remaining: 999, resetAt: Date.now() + 1000 }),
  });
});
afterAll(async () => {
  if (LIVE) await world.cleanup();
});

const paramsFor = (path: string) =>
  Object.fromEntries([...path.matchAll(/\{(\w+)\}/g)].map(([, n]) => [n!, NOBODY]));

describe.skipIf(!LIVE)('admin routes as a non-admin (live)', () => {
  it('covers every admin operation', () => {
    expect(adminOps.length).toBeGreaterThanOrEqual(17);
  });

  it('control: a real admin gets through', async () => {
    const reply = await call('adminListRooms', { token: admin.token });
    expect(reply.status).toBe(200);
  });

  for (const [id, op] of adminOps) {
    it(`${id}: the same 404 for a non-admin whatever they send, 401 signed out`, async () => {
      const params = paramsFor(op.path);
      const bodies: unknown[] =
        op.body === undefined ? [undefined] : [{}, { name: 'x'.repeat(5000) }, [], 'junk'];
      const answers = new Set<string>();
      for (const body of bodies) {
        const reply = await call(id, {
          token: user.token,
          params,
          ...(body === undefined ? {} : { body }),
          ...(op.query ? { query: { status: 'bogus', limit: '-1' } } : {}),
        });
        expect(reply.status, id).toBe(404);
        answers.add(reply.text);
      }
      expect(answers.size, `${id} answers differently`).toBe(1);
      const unknownRoute = await call('adminListRooms', { token: user.token });
      expect([...answers][0]).toBe(unknownRoute.text);
      const signedOut = await call(id, { params, ...(op.body === undefined ? {} : { body: {} }) });
      expect(signedOut.status).toBe(401);
    });
  }
});
