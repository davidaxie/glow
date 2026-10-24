import { NextRequest } from 'next/server';
import { describe, expect, it, vi } from 'vitest';
import { HttpError, notFound, notImplemented, route } from '@/server/http';
import { fakeAccessToken, mockVerify, USER_ID } from './helpers/auth';

vi.mock('@/server/auth/verify', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@/server/auth/verify')>();
  return { ...actual, verifyAccessToken: vi.fn() };
});

vi.mock('@/server/http/operations', async () => ({
  operations: (await import('./helpers/test-operations')).testOperations,
}));

// The helper is typed against the real registry; these tests swap in their own.
type AnyRoute = (id: string, handler: (input: never) => unknown) => ReturnType<typeof route>;
const testRoute = route as unknown as AnyRoute;

const ID = '0b6f8f7e-1c2d-4e3f-8a9b-0c1d2e3f4a5b';
const COORDS = { lat: 37.774929, lng: -122.419416 };

function call(
  handler: ReturnType<typeof route>,
  {
    path = `/api/test/${ID}`,
    method = 'POST',
    body,
    headers = {},
    token = fakeAccessToken(),
    params = { id: ID },
  }: {
    path?: string;
    method?: string;
    body?: BodyInit;
    headers?: Record<string, string>;
    token?: string | null;
    params?: Record<string, string>;
  } = {},
) {
  const req = new NextRequest(`http://localhost${path}`, {
    method,
    headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), ...headers },
    ...(body !== undefined ? { body } : {}),
  });
  return handler(req, { params: Promise.resolve(params) });
}

const jsonBody = (value: unknown) => ({
  body: JSON.stringify(value),
  headers: { 'content-type': 'application/json' },
});

function captureConsole() {
  const lines: string[] = [];
  const grab = (...args: unknown[]) => lines.push(args.map(String).join(' '));
  vi.spyOn(console, 'log').mockImplementation(grab);
  vi.spyOn(console, 'warn').mockImplementation(grab);
  vi.spyOn(console, 'error').mockImplementation(grab);
  return lines;
}

describe('route helper', () => {
  it('checks sign-in before anything else, and never runs the handler without it', async () => {
    await mockVerify();
    const handler = vi.fn();
    const res = await call(testRoute('echo', handler), { token: null, ...jsonBody({}) });
    expect(res.status).toBe(401);
    expect(res.headers.get('www-authenticate')).toBe('Bearer');
    expect(handler).not.toHaveBeenCalled();
  });

  it('hands the handler the person, params, query and validated body', async () => {
    await mockVerify();
    const handler = vi.fn((input: { user: { id: string }; query: { page?: number } }) => ({
      status: 200,
      body: { id: ID, ok: input.user.id === USER_ID, page: input.query.page },
    }));
    const res = await call(testRoute('echo', handler as never), {
      path: `/api/test/${ID}?page=2`,
      ...jsonBody({ ...COORDS, note: 'hi' }),
    });
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ id: ID, ok: true, page: 2 });
    expect(handler.mock.calls[0]?.[0]).toMatchObject({
      params: { id: ID },
      query: { page: 2 },
      body: { ...COORDS, note: 'hi' },
    });
  });

  it('answers 404 for a malformed ID, since it cannot name anything', async () => {
    await mockVerify();
    const res = await call(testRoute('echo', vi.fn()), { params: { id: 'not-a-uuid' } });
    expect(res.status).toBe(404);
    expect(await res.json()).toEqual({ error: { code: 'not_found', message: 'Not found.' } });
  });

  it('turns a 403 into the exact same 404 as "does not exist" (P11)', async () => {
    await mockVerify();
    const forbidden = await call(
      testRoute('echo', () => {
        throw new HttpError(403, 'forbidden', 'This match belongs to someone else.');
      }),
      jsonBody({ ...COORDS, note: 'x' }),
    );
    const missing = await call(
      testRoute('echo', () => {
        throw notFound();
      }),
      jsonBody({ ...COORDS, note: 'x' }),
    );
    expect(forbidden.status).toBe(404);
    expect(await forbidden.text()).toBe(await missing.text());
  });

  it('answers 400 with field paths but never echoes what was sent', async () => {
    await mockVerify();
    const res = await call(
      testRoute('echo', vi.fn()),
      jsonBody({ lat: 123.456789, lng: 'nope', note: 'too long' }),
    );
    expect(res.status).toBe(400);
    const text = await res.text();
    const body = JSON.parse(text) as { error: { issues: { path: string }[] } };
    expect(body.error.issues.map((i) => i.path).sort()).toEqual([
      'body.lat',
      'body.lng',
      'body.note',
    ]);
    expect(text).not.toContain('123.456789');
    expect(text).not.toContain('too long');
  });

  it('answers 400 for a bad query and 415 for the wrong content type', async () => {
    await mockVerify();
    const badQuery = await call(testRoute('echo', vi.fn()), {
      path: `/api/test/${ID}?page=0`,
      ...jsonBody({ ...COORDS, note: 'x' }),
    });
    expect(badQuery.status).toBe(400);
    const wrongType = await call(testRoute('echo', vi.fn()), {
      body: JSON.stringify({ ...COORDS, note: 'x' }),
      headers: { 'content-type': 'text/plain' },
    });
    expect(wrongType.status).toBe(415);
    const notJson = await call(testRoute('echo', vi.fn()), {
      body: '{"lat":',
      headers: { 'content-type': 'application/json' },
    });
    expect(notJson.status).toBe(400);
  });

  it('answers 413 when the body is too large', async () => {
    await mockVerify();
    const res = await call(
      testRoute('echo', vi.fn()),
      jsonBody({ ...COORDS, note: 'x'.repeat(70_000) }),
    );
    expect(res.status).toBe(413);
  });

  it('sends only the fields the contract declares (P1)', async () => {
    await mockVerify();
    const res = await call(
      testRoute('echo', () => ({
        status: 200,
        body: { id: ID, ok: true, otherUserId: USER_ID, firstName: 'Robin' },
      })),
      jsonBody({ ...COORDS, note: 'x' }),
    );
    expect(res.status).toBe(200);
    const text = await res.text();
    expect(JSON.parse(text)).toEqual({ id: ID, ok: true });
    expect(text).not.toContain(USER_ID);
    expect(text).not.toContain('Robin');
  });

  it('answers 500, without the data, when a reply breaks the contract', async () => {
    await mockVerify();
    const lines = captureConsole();
    const res = await call(
      testRoute('echo', () => ({ status: 200, body: { id: 'Robin', ok: 'yes' } })),
      jsonBody({ ...COORDS, note: 'x' }),
    );
    expect(res.status).toBe(500);
    expect(await res.json()).toEqual({
      error: { code: 'internal', message: 'Something went wrong on our side.' },
    });
    expect(lines.join('\n')).toContain('api.contract_violation');
    expect(lines.join('\n')).not.toContain('Robin');
  });

  it('answers 500 for a status that is not in the contract', async () => {
    await mockVerify();
    captureConsole();
    const res = await call(
      testRoute('echo', () => ({ status: 202, body: {} })),
      jsonBody({ ...COORDS, note: 'x' }),
    );
    expect(res.status).toBe(500);
  });

  it('never logs the request body or error text, so coordinates stay out of logs (P2)', async () => {
    await mockVerify();
    const lines = captureConsole();
    const res = await call(
      testRoute('echo', (input: { body: typeof COORDS }) => {
        throw new Error(`failed at ${input.body.lat},${input.body.lng}`);
      }),
      jsonBody({ ...COORDS, note: 'x' }),
    );
    expect(res.status).toBe(500);
    const logs = lines.join('\n');
    expect(logs).toContain('api.unhandled');
    expect(logs).not.toContain(String(COORDS.lat));
    expect(logs).not.toContain(String(COORDS.lng));
    expect(await res.text()).not.toContain(String(COORDS.lat));
  });

  it('marks every JSON response no-store', async () => {
    await mockVerify();
    const ok = await call(
      testRoute('echo', () => ({ status: 200, body: { id: ID, ok: true } })),
      jsonBody({ ...COORDS, note: 'x' }),
    );
    const err = await call(testRoute('echo', vi.fn()), { token: null });
    expect(ok.headers.get('cache-control')).toBe('no-store, max-age=0');
    expect(err.headers.get('cache-control')).toBe('no-store, max-age=0');
  });

  it('supports empty 204 replies', async () => {
    await mockVerify();
    const res = await call(
      testRoute('echo', () => ({ status: 204 })),
      jsonBody({ ...COORDS, note: 'x' }),
    );
    expect(res.status).toBe(204);
    expect(await res.text()).toBe('');
  });

  it('lets raw operations return their own Response, defaulting to no-store', async () => {
    const res = await call(
      testRoute('file', () => new Response('hello', { status: 200 })),
      {
        path: '/api/test/file',
        method: 'GET',
        token: null,
      },
    );
    expect(res.status).toBe(200);
    expect(await res.text()).toBe('hello');
    expect(res.headers.get('cache-control')).toBe('no-store, max-age=0');
  });

  it('refuses a raw Response from a JSON operation, which would skip validation', async () => {
    await mockVerify();
    captureConsole();
    const res = await call(
      testRoute('echo', () => Response.json({ id: ID, ok: true, otherUserId: USER_ID })),
      jsonBody({ ...COORDS, note: 'x' }),
    );
    expect(res.status).toBe(500);
    expect(await res.text()).not.toContain(USER_ID);
  });

  it('parses multipart uploads within the size limit', async () => {
    await mockVerify();
    const handler = (input: { body: FormData }) => ({
      status: 201,
      body: { size: (input.body.get('photo') as File).size },
    });
    const small = new FormData();
    small.set('photo', new File([new Uint8Array(100)], 'card.jpg', { type: 'image/jpeg' }));
    const ok = await call(testRoute('upload', handler as never), {
      path: '/api/test/upload',
      body: small,
    });
    expect(ok.status).toBe(201);
    expect(await ok.json()).toEqual({ size: 100 });

    const big = new FormData();
    big.set('photo', new File([new Uint8Array(4096)], 'card.jpg', { type: 'image/jpeg' }));
    const tooBig = await call(testRoute('upload', handler as never), {
      path: '/api/test/upload',
      body: big,
    });
    expect(tooBig.status).toBe(413);
  });

  it('answers 501 for stubs, after sign-in', async () => {
    await mockVerify();
    const stub = testRoute('echo', notImplemented);
    expect((await call(stub, { token: null })).status).toBe(401);
    const res = await call(stub);
    expect(res.status).toBe(501);
    expect(await res.json()).toEqual({
      error: { code: 'not_implemented', message: 'This endpoint is not built yet.' },
    });
  });
});
