/**
 * Every operation in the contract has a route file that exports its method, checks
 * sign-in the way the contract says, and (while it's a stub) answers 501.
 * When an owner builds their endpoint, it drops out of the 501 check automatically.
 */
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { NextRequest } from 'next/server';
import { describe, expect, it, vi } from 'vitest';
import { operations } from '@/server/http/operations';
import type { OperationDef } from '@/server/http/operation';
import { LOCAL_ENV } from './helpers/env';
import { fakeAccessToken, mockVerify } from './helpers/auth';

vi.mock('@/server/auth/verify', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@/server/auth/verify')>();
  return { ...actual, verifyAccessToken: vi.fn() };
});

const APP = fileURLToPath(new URL('../app', import.meta.url));
const SAMPLE: Record<string, string> = {
  id: '11111111-1111-4111-8111-111111111111',
  cardId: '22222222-2222-4222-8222-222222222222',
  n: '0',
  slug: 'demo',
};

/** `/api/matches/{id}/glow` becomes `app/api/matches/[id]/glow/route.ts`. */
const routeFile = (path: string) =>
  join(
    APP,
    ...path
      .split('/')
      .filter(Boolean)
      .map((s) => s.replace(/^\{(.+)\}$/, '[$1]')),
    'route.ts',
  );

const samplePath = (path: string) =>
  path.replace(/\{(\w+)\}/g, (_, name: string) => SAMPLE[name] ?? 'x');
const sampleParams = (path: string) =>
  Object.fromEntries(
    [...path.matchAll(/\{(\w+)\}/g)].map(([, name]) => [name!, SAMPLE[name!] ?? 'x']),
  );

type Handler = (
  req: NextRequest,
  ctx: { params: Promise<Record<string, string>> },
) => Promise<Response>;

async function load(op: OperationDef): Promise<Handler> {
  const mod = (await import(/* @vite-ignore */ routeFile(op.path))) as Record<string, unknown>;
  const handler = mod[op.method];
  if (typeof handler !== 'function') throw new Error(`${op.path} has no ${op.method} export`);
  return handler as Handler;
}

function request(op: OperationDef, authorization?: string) {
  const headers: Record<string, string> = authorization ? { authorization } : {};
  let body: BodyInit | undefined;
  if (op.body === 'multipart') {
    const form = new FormData();
    form.set('placeholder', '1');
    body = form;
  } else if (op.body) {
    headers['content-type'] = 'application/json';
    body = '{}';
  }
  return new NextRequest(`http://localhost${samplePath(op.path)}`, {
    method: op.method,
    headers,
    ...(body !== undefined ? { body } : {}),
  });
}

const isStub = (op: OperationDef) =>
  new RegExp(`export const ${op.method} = route\\('[^']+', notImplemented\\)`).test(
    readFileSync(routeFile(op.path), 'utf8'),
  );

const entries = Object.entries(operations) as [string, OperationDef][];

describe('contract coverage', () => {
  it.each(entries)('%s has a route file exporting its method', async (id, op) => {
    expect(
      existsSync(routeFile(op.path)),
      `missing ${relative(process.cwd(), routeFile(op.path))}`,
    ).toBe(true);
    const source = readFileSync(routeFile(op.path), 'utf8');
    expect(source).toContain(`export const ${op.method} = route('${id}'`);
    await load(op);
  });

  it('has no API route file that is not in the contract', () => {
    const contractFiles = new Set(entries.map(([, op]) => routeFile(op.path)));
    const allowed = new Set([join(APP, 'api', '[...path]', 'route.ts')]);
    const found: string[] = [];
    const walk = (dir: string) => {
      for (const name of readdirSync(dir)) {
        const full = join(dir, name);
        if (statSync(full).isDirectory()) walk(full);
        else if (name === 'route.ts') found.push(full);
      }
    };
    walk(APP);
    const extra = found.filter((f) => !contractFiles.has(f) && !allowed.has(f));
    expect(extra.map((f) => relative(APP, f).split(sep).join('/'))).toEqual([]);
  });
});

describe('sign-in on every route', () => {
  const userOps = entries.filter(([, op]) => op.auth === 'user');
  it.each(userOps)('%s answers 401 without a token', async (_id, op) => {
    const verify = await mockVerify();
    const res = await (
      await load(op)
    )(request(op), { params: Promise.resolve(sampleParams(op.path)) });
    expect(res.status).toBe(401);
    expect(verify).not.toHaveBeenCalled();
  });

  const cronOps = entries.filter(([, op]) => op.auth === 'cron');
  it.each(cronOps)('%s answers 401 without the cron secret', async (_id, op) => {
    const res = await (
      await load(op)
    )(request(op, 'Bearer not-the-secret'), {
      params: Promise.resolve(sampleParams(op.path)),
    });
    expect(res.status).toBe(401);
  });
});

describe('stubs answer 501 to a valid request', () => {
  const stubs = entries.filter(([, op]) => isStub(op));
  it.each(stubs)('%s', async (_id, op) => {
    await mockVerify();
    const auth =
      op.auth === 'user'
        ? `Bearer ${fakeAccessToken()}`
        : op.auth === 'cron'
          ? `Bearer ${LOCAL_ENV.CRON_SECRET}`
          : undefined;
    const res = await (
      await load(op)
    )(request(op, auth), { params: Promise.resolve(sampleParams(op.path)) });
    expect(res.status).toBe(501);
  });
});

describe('unknown API paths', () => {
  it('get a JSON 404', async () => {
    const mod = (await import('../app/api/[...path]/route')) as { GET: () => Response };
    const res = mod.GET();
    expect(res.status).toBe(404);
    expect(await res.json()).toEqual({ error: { code: 'not_found', message: 'Not found.' } });
  });
});
