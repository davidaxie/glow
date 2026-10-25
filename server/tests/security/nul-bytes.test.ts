/**
 * D2-F4: a NUL character in any request string used to reach Postgres, which can't store it,
 * and came back as a 500. The route helper now refuses it up front with a 400, in bodies
 * (values, keys, any depth) and in query strings, before a handler runs.
 */
import { NextRequest } from 'next/server';
import { describe, expect, it, vi } from 'vitest';
import { route } from '@/server/http';
import { hasNul } from '@/server/http/route';
import { fakeAccessToken, mockVerify } from '../helpers/auth';

vi.mock('@/server/auth/verify', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@/server/auth/verify')>();
  return { ...actual, verifyAccessToken: vi.fn() };
});
vi.mock('@/server/http/operations', async () => ({
  operations: (await import('../helpers/test-operations')).testOperations,
}));

type AnyRoute = (id: string, handler: (input: never) => unknown) => ReturnType<typeof route>;
const testRoute = route as unknown as AnyRoute;
const ID = '0b6f8f7e-1c2d-4e3f-8a9b-0c1d2e3f4a5b';

async function post(handler: ReturnType<typeof route>, body: string, query = '') {
  const req = new NextRequest(`http://localhost/api/test/${ID}${query}`, {
    method: 'POST',
    headers: { authorization: `Bearer ${fakeAccessToken()}`, 'content-type': 'application/json' },
    body,
  });
  return handler(req, { params: Promise.resolve({ id: ID }) });
}

describe('NUL characters are refused before a handler runs (D2-F4)', () => {
  it('finds a NUL anywhere in a value', () => {
    expect(hasNul('a\u0000b')).toBe(true);
    expect(hasNul({ a: ['x', { b: 'y\u0000' }] })).toBe(true);
    expect(hasNul({ ['k\u0000']: 'v' })).toBe(true);
    expect(hasNul({ a: ['x', { b: 'y' }], n: 1, t: true, z: null })).toBe(false);
    let deep: unknown = 'fine';
    for (let i = 0; i < 100; i++) deep = { deep };
    expect(hasNul(deep)).toBe(true); // absurdly deep bodies are refused too
  });

  it('a NUL in a body string is a 400, and the handler never runs', async () => {
    await mockVerify();
    const handler = vi.fn();
    for (const note of ['a\\u0000b', '\\u0000']) {
      const res = await post(testRoute('echo', handler), `{"lat":1,"lng":2,"note":"${note}"}`);
      expect(res.status).toBe(400);
      const text = await res.text();
      expect(text).not.toContain('\u0000');
      expect(text).toContain('"bad_request"');
    }
    expect(handler).not.toHaveBeenCalled();
  });

  it('a NUL in an unknown key or a nested value is a 400 too', async () => {
    await mockVerify();
    const handler = vi.fn();
    const res = await post(
      testRoute('echo', handler),
      '{"lat":1,"lng":2,"note":"ok","x\\u0000y":{"deep":["\\u0000"]}}',
    );
    expect(res.status).toBe(400);
    expect(handler).not.toHaveBeenCalled();
  });

  it('a NUL in the query string is a 400', async () => {
    await mockVerify();
    const handler = vi.fn();
    const res = await post(
      testRoute('echo', handler),
      '{"lat":1,"lng":2,"note":"ok"}',
      '?page=1%00',
    );
    expect(res.status).toBe(400);
    expect(handler).not.toHaveBeenCalled();
  });

  it('everything else still goes through', async () => {
    await mockVerify();
    const handler = vi.fn(() => ({ status: 200, body: { id: ID, ok: true } }));
    const res = await post(testRoute('echo', handler), '{"lat":1,"lng":2,"note":"ok"}');
    expect(res.status).toBe(200);
    expect(handler).toHaveBeenCalledOnce();
  });
});
