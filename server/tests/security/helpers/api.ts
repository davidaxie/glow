/**
 * Calls the real route handlers in-process, by contract operation, exactly as Next.js would:
 * the same route helper, sign-in against the live Supabase Auth, rate limits, validation and
 * reply stripping. A test sees what the app (or an attacker's script) would see.
 */
import { NextRequest } from 'next/server';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { operations, type OperationId } from '@/server/http/operations';

const APP = fileURLToPath(new URL('../../../app', import.meta.url));

/** `/api/matches/{id}/glow` is `app/api/matches/[id]/glow/route.ts`. */
export const routeFile = (path: string) =>
  join(
    APP,
    ...path
      .split('/')
      .filter(Boolean)
      .map((s) => s.replace(/^\{(.+)\}$/, '[$1]')),
    'route.ts',
  );

type Handler = (
  req: NextRequest,
  ctx: { params: Promise<Record<string, string>> },
) => Promise<Response>;

export type ApiReply = {
  readonly status: number;
  readonly headers: Headers;
  /** The body as text ('' for none, a short marker for binary bodies). */
  readonly text: string;
  readonly json: unknown;
  readonly bytes: Uint8Array;
};

export type CallOptions = {
  readonly token?: string | null;
  readonly params?: Record<string, string>;
  readonly query?: Record<string, string>;
  readonly body?: unknown;
  /** A path with its own query string (for signed links), instead of building one. */
  readonly url?: string;
  readonly headers?: Record<string, string>;
};

/** Every reply a test got, for scans across a whole journey. */
export const journal: { operationId: string; status: number; text: string }[] = [];

export async function call(operationId: OperationId, options: CallOptions = {}): Promise<ApiReply> {
  const op = operations[operationId];
  const mod = (await import(/* @vite-ignore */ routeFile(op.path))) as Record<string, unknown>;
  const handler = mod[op.method] as Handler | undefined;
  if (typeof handler !== 'function') throw new Error(`${op.path} has no ${op.method} export`);

  const params = options.params ?? {};
  let path = op.path.replace(/\{(\w+)\}/g, (_, name: string) => {
    const value = params[name];
    if (value === undefined) throw new Error(`${operationId} needs ${name}`);
    return encodeURIComponent(value);
  });
  if (options.query) path += `?${new URLSearchParams(options.query).toString()}`;
  if (options.url) path = options.url;

  const headers: Record<string, string> = { ...(options.headers ?? {}) };
  if (options.token) headers.authorization = `Bearer ${options.token}`;
  if (options.body !== undefined) headers['content-type'] = 'application/json';
  const req = new NextRequest(`http://localhost${path}`, {
    method: op.method,
    headers,
    ...(options.body === undefined ? {} : { body: JSON.stringify(options.body) }),
  });
  const res = await handler(req, { params: Promise.resolve(params) });
  const bytes = new Uint8Array(await res.arrayBuffer());
  const type = res.headers.get('content-type') ?? '';
  const text = type.startsWith('image/')
    ? `[${type}, ${bytes.byteLength} bytes]`
    : new TextDecoder().decode(bytes);
  let json: unknown = null;
  if (type.includes('json') && text) json = JSON.parse(text);
  journal.push({ operationId, status: res.status, text });
  return { status: res.status, headers: res.headers, text, json, bytes };
}

/** True while an operation is still A1's 501 stub (its owner's PR hasn't merged). */
export async function isStub(operationId: OperationId): Promise<boolean> {
  const op = operations[operationId];
  const { readFileSync } = await import('node:fs');
  return /notImplemented/.test(readFileSync(routeFile(op.path), 'utf8'));
}
