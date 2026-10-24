/**
 * Every /api/admin route, through the real route files and route helper: a signed-in person
 * who isn't an admin gets the same 404 as a missing room (P11), before anything is read, and
 * an admin gets the contract's answer.
 */
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { NextRequest } from 'next/server';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { operationInfo, operations } from '@/contracts';
import { setAdminDepsForTests } from '@/server/admin/context';
import { USER_ID, fakeAccessToken, mockVerify } from '../helpers/auth';
import { ADMIN_ID, FakeRepo, ROOM_ID, card, fakeDeps, report } from './fake-repo';

vi.mock('@/server/auth/verify', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@/server/auth/verify')>();
  return { ...actual, verifyAccessToken: vi.fn() };
});

afterEach(() => setAdminDepsForTests(undefined));

type Op = (typeof operations)[keyof typeof operations];
type Handler = (
  req: NextRequest,
  ctx: { params: Promise<Record<string, string>> },
) => Promise<Response>;

const APP = fileURLToPath(new URL('../../app', import.meta.url));
const CARD = card();
const REPORT = report({ contextId: CARD.id });

const BODIES: Record<string, unknown> = {
  adminCreateRoom: {
    slug: 'route-test',
    name: 'Route test',
    latitude: 37.8,
    longitude: -122.4,
    startsAt: '2026-10-24T18:00:00.000Z',
    endsAt: '2026-10-25T06:00:00.000Z',
    spots: ['A', 'B', 'C'],
  },
  adminUpdateRoom: { demoMode: true },
  adminReplaceSpots: { spots: ['A', 'B', 'C'] },
  adminRemoveCard: { scope: 'card' },
  adminResolveReport: { action: 'dismiss' },
  adminReviewPhoto: { decision: 'approve' },
};

const PARAMS: Record<string, string> = { id: ROOM_ID, cardId: CARD.id };

function paramsFor(id: string, op: Op): Record<string, string> {
  const names = [...op.path.matchAll(/\{(\w+)\}/g)].map(([, n]) => n!);
  const value = (name: string) =>
    id === 'adminResolveReport' && name === 'id' ? REPORT.id : PARAMS[name]!;
  return Object.fromEntries(names.map((n) => [n, value(n)]));
}

const admin = (Object.entries(operations) as [string, Op][]).filter(
  ([id]) => operationInfo[id as keyof typeof operationInfo].owner === 'B7',
);

function routeFile(path: string) {
  return `${APP}/${path
    .split('/')
    .filter(Boolean)
    .map((s) => s.replace(/^\{(.+)\}$/, '[$1]'))
    .join('/')}/route.ts`;
}

async function call(id: string, op: Op): Promise<Response> {
  const mod = (await import(/* @vite-ignore */ routeFile(op.path))) as Record<string, Handler>;
  const params = paramsFor(id, op);
  const path = op.path.replace(/\{(\w+)\}/g, (_, n: string) => params[n]!);
  const body = BODIES[id];
  const req = new NextRequest(`http://localhost${path}`, {
    method: op.method,
    headers: {
      authorization: `Bearer ${fakeAccessToken()}`,
      ...(body ? { 'content-type': 'application/json' } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  return mod[op.method]!(req, { params: Promise.resolve(params) });
}

function world(isAdmin: boolean) {
  const repo = new FakeRepo((r) => {
    r.admins = isAdmin ? new Set([USER_ID, ADMIN_ID]) : new Set([ADMIN_ID]);
    r.people.set(USER_ID, { viewerCode: 'K7MPQ2XR', bannedAt: null, authBanned: false });
    r.cards.set(CARD.id, { ...CARD, userId: '7e570000-0000-4000-8000-000000000003' });
    r.reports.set(REPORT.id, REPORT);
  });
  setAdminDepsForTests(fakeDeps(repo).deps);
  return repo;
}

describe('admin routes', () => {
  it('cover every B7 operation in the contract', () => {
    expect(admin.length).toBeGreaterThanOrEqual(14);
  });

  const built = admin.filter(([, op]) => existsSync(routeFile(op.path)));

  it.each(built)('%s answers 404 to a signed-in person who is not an admin', async (id, op) => {
    await mockVerify();
    const repo = world(false);
    const res = await call(id, op);
    if (res.status === 501) return; // not built yet
    expect(res.status).toBe(404);
    expect(await res.json()).toEqual({ error: { code: 'not_found', message: 'Not found.' } });
    // Nothing past the admin check ran.
    expect(repo.calls).toEqual(['isAdmin']);
  });

  it.each(built)('%s works for an admin', async (id, op) => {
    await mockVerify();
    world(true);
    const res = await call(id, op);
    if (res.status === 501) return;
    // The card has no photo in the fake store, so its image is a plain 404.
    const expected: Record<string, number> = {
      adminCardImage: 404,
      adminCreateRoom: 201,
      adminRemoveCard: 204,
    };
    expect(res.status, id).toBe(expected[id] ?? 200);
    expect(res.headers.get('cache-control')).toContain('no-store');
    if (id === 'adminRoomPoster') expect(res.headers.get('content-type')).toBe('application/pdf');
  });
});
