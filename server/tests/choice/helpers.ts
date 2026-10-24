/**
 * Calling C2's real route files the way Next.js does. Each test file mocks Supabase Auth
 * (`@/server/auth/verify`, see tests/helpers/auth.ts) and C2's `deps` (to watch `notify`).
 */
import { NextRequest } from 'next/server';
import { vi } from 'vitest';
import { fakeAccessToken } from '../helpers/auth';

type Handler = (
  req: NextRequest,
  ctx: { params: Promise<Record<string, string>> },
) => Promise<Response>;

export type Reply = { status: number; body: unknown; text: string; headers: Headers };

export async function call(
  handler: Handler,
  {
    path,
    method = 'GET',
    json,
    params = {},
    token = fakeAccessToken(),
  }: {
    path: string;
    method?: string;
    json?: unknown;
    params?: Record<string, string>;
    token?: string | null;
  },
): Promise<Reply> {
  const headers: Record<string, string> = token ? { authorization: `Bearer ${token}` } : {};
  if (json !== undefined) headers['content-type'] = 'application/json';
  const req = new NextRequest(`http://localhost${path}`, {
    method,
    headers,
    ...(json !== undefined ? { body: JSON.stringify(json) } : {}),
  });
  const res = await handler(req, { params: Promise.resolve(params) });
  const text = await res.text();
  let body: unknown = undefined;
  try {
    body = text ? JSON.parse(text) : undefined;
  } catch {
    body = undefined;
  }
  return { status: res.status, body, text, headers: res.headers };
}

/** Everything the logger writes while `run` runs. */
export async function captureLogs<T>(
  run: () => Promise<T>,
): Promise<{ result: T; lines: string[] }> {
  const lines: string[] = [];
  const grab = (...args: unknown[]) => {
    lines.push(args.map((a) => (typeof a === 'string' ? a : JSON.stringify(a))).join(' '));
  };
  for (const method of ['log', 'warn', 'error', 'info', 'debug'] as const) {
    vi.spyOn(console, method).mockImplementation(grab);
  }
  const result = await run();
  return { result, lines };
}

/** Every UUID in a value, lowercased, to check that no user ID is in a reply (P1). */
export function uuidsIn(value: unknown): string[] {
  return [
    ...JSON.stringify(value ?? null).matchAll(
      /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi,
    ),
  ].map((m) => m[0].toLowerCase());
}

/** The calls a mocked `notify` got, as `{ type, matchId, to }`, sorted for comparison. */
export function sentEvents(notify: { mock: { calls: unknown[][] } }) {
  return notify.mock.calls
    .map(([to, event]) => {
      const e = event as { type: string; matchId: string };
      const people = (typeof to === 'string' ? [to] : (to as string[])).map((id) =>
        id.toLowerCase(),
      );
      return { type: e.type, matchId: e.matchId, to: [...people].sort() };
    })
    .sort((a, b) => (a.type + a.to.join()).localeCompare(b.type + b.to.join()));
}
