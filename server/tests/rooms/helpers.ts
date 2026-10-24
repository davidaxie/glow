/**
 * Calling B2's real route files the way Next.js does, with Supabase Auth mocked and the
 * database faked. Each test file needs these two mocks at its top:
 *
 *   vi.mock('@/server/auth/verify', ...)       (see tests/helpers/auth.ts)
 *   vi.mock('@/server/http/operations', ...)   the generated registry
 */
import { NextRequest } from 'next/server';
import { vi } from 'vitest';
import { fakeAccessToken } from '../helpers/auth';

type Handler = (
  req: NextRequest,
  ctx: { params: Promise<Record<string, string>> },
) => Promise<Response>;

export async function call(
  handler: Handler,
  {
    path,
    method = 'POST',
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
): Promise<{ status: number; body: unknown; text: string; headers: Headers }> {
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

/** Everything written to the console while `run` runs: what the logger writes. */
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
