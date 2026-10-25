/**
 * The typed route helper. Every API route file is one line per method:
 *
 *   export const GET = route('getMatch', async ({ user, params }) => {
 *     const match = await findMatchFor(user.id, params.id);
 *     if (!match) throw notFound();          // also for "exists but not yours" (P11)
 *     return { status: 200, body: match };
 *   });
 *
 * For each request it, in order:
 * 1. checks sign-in from the operation's `auth` (401, or 503 if Supabase Auth is down), then
 *    B8's rate limit for the operation, per person or per IP (429 with Retry-After)
 * 2. validates path params (invalid means it can't exist, so 404), query and body (400)
 * 3. runs the handler
 * 4. validates the reply against the contract and sends only the fields the contract
 *    declares, so an extra field (a user ID, say) never leaves the server (P1)
 *
 * Errors: throw `notFound()`, `badRequest()`, `conflict()`, `rateLimited()` and so on
 * from `./errors`. A 403 is always turned into 404 (P11). Anything else becomes a 500
 * with a generic body, and is logged without the request body (P2).
 */
import type { NextRequest } from 'next/server';
import type { z } from 'zod';
import { requireCron, requireUser, type AuthUser } from '@/server/auth';
import { logger } from '@/server/log';
import { limitRequest } from '@/server/ratelimit';
import { captureError } from '@/server/observability';
import {
  HttpError,
  badRequest,
  errorBody,
  notFound,
  notImplemented,
  type ErrorIssue,
} from './errors';
import type { OperationDef } from './operation';
import { operations, type OperationId, type Operations } from './operations';

const DEFAULT_JSON_LIMIT = 64 * 1024;
const DEFAULT_UPLOAD_LIMIT = 8 * 1024 * 1024;
const NO_STORE = 'no-store, max-age=0';

type Op<Id extends OperationId> = Operations[Id];
type Parsed<S> = S extends z.ZodType ? z.output<S> : never;

type ParamsOf<D> = D extends { params: infer P } ? Parsed<P> : Record<string, never>;
type QueryOf<D> = D extends { query: infer Q } ? Parsed<Q> : Record<string, never>;
type BodyOf<D> = D extends { body: infer B }
  ? B extends 'multipart'
    ? FormData
    : Parsed<B>
  : undefined;
type UserOf<D> = D extends { auth: 'user' } ? AuthUser : null;

export type RouteInput<Id extends OperationId> = {
  readonly req: NextRequest;
  readonly user: UserOf<Op<Id>>;
  readonly params: ParamsOf<Op<Id>>;
  readonly query: QueryOf<Op<Id>>;
  readonly body: BodyOf<Op<Id>>;
};

type Headers = Readonly<Record<string, string>>;

type ReplyFor<S extends number, Spec> = Spec extends z.ZodType
  ? { readonly status: S; readonly body: z.input<Spec>; readonly headers?: Headers }
  : Spec extends null
    ? { readonly status: S; readonly headers?: Headers }
    : Response;

type RepliesOf<R> = { [S in keyof R & number]: ReplyFor<S, R[S]> }[keyof R & number];

/** What a handler may return: one of the contract's responses for this operation. */
export type RouteReply<Id extends OperationId> = RepliesOf<Op<Id>['responses']>;

export type RouteHandler<Id extends OperationId> = (
  input: RouteInput<Id>,
) => RouteReply<Id> | Promise<RouteReply<Id>>;

/** What Next.js calls. The context's params are a Promise in Next 16. */
export type NextRouteHandler = (
  req: NextRequest,
  ctx: { params: Promise<Record<string, string | string[] | undefined>> },
) => Promise<Response>;

export type RouteOptions = {
  /**
   * Runs right after sign-in and before the path, query or body is read. Throw `notFound()`
   * to turn someone away with the same 404 whatever they sent (P11): for example, the admin
   * routes for anyone who isn't an admin, who would otherwise learn from a 400 that the
   * route exists and what it expects.
   */
  readonly authorize?: (user: AuthUser) => void | Promise<void>;
};

export function route<Id extends OperationId>(
  operationId: Id,
  handler: RouteHandler<Id>,
  options: RouteOptions = {},
): NextRouteHandler {
  const op: OperationDef = operations[operationId];
  const isStub = (handler as unknown) === notImplemented;

  return async function handle(req, ctx) {
    const started = performance.now();
    let response: Response;
    try {
      const user = await authenticate(op, req);
      await limitRequest(operationId, req, user);
      if (user && options.authorize) await options.authorize(user);
      const params = await parseParams(op, ctx);
      if (isStub) notImplemented();
      const query = parseQuery(op, req);
      const body = await parseBody(op, req);
      const input = { req, user, params, query, body } as unknown as RouteInput<Id>;
      const reply = await handler(input);
      response = toResponse(operationId, op, reply);
    } catch (error) {
      response = errorResponse(operationId, error);
    }
    logger.info('api.request', {
      operation: operationId,
      method: op.method,
      status: response.status,
      ms: Math.round(performance.now() - started),
    });
    return response;
  };
}

async function authenticate(op: OperationDef, req: Request): Promise<AuthUser | null> {
  if (op.auth === 'user') return requireUser(req);
  if (op.auth === 'cron') requireCron(req);
  return null;
}

async function parseParams(
  op: OperationDef,
  ctx: { params?: Promise<Record<string, string | string[] | undefined>> } | undefined,
): Promise<unknown> {
  const raw = (await ctx?.params) ?? {};
  if (!op.params) return {};
  const parsed = op.params.safeParse(raw);
  // A malformed ID can't name anything that exists, so it's simply not found.
  if (!parsed.success) throw notFound();
  return parsed.data;
}

function parseQuery(op: OperationDef, req: NextRequest): unknown {
  if (!op.query) return {};
  const raw: Record<string, string | string[]> = {};
  for (const [key, value] of req.nextUrl.searchParams) {
    const existing = raw[key];
    raw[key] =
      existing === undefined
        ? value
        : Array.isArray(existing)
          ? [...existing, value]
          : [existing, value];
  }
  if (Object.values(raw).some((v) => hasNul(v))) throw badRequest('The query is not valid.');
  const parsed = op.query.safeParse(raw);
  if (!parsed.success) throw badRequest('The query is not valid.', issuesOf(parsed.error, 'query'));
  return parsed.data;
}

async function parseBody(op: OperationDef, req: Request): Promise<unknown> {
  if (op.body === undefined) return undefined;
  const contentType = (req.headers.get('content-type') ?? '').toLowerCase();

  if (op.body === 'multipart') {
    if (!contentType.startsWith('multipart/form-data')) {
      throw new HttpError(415, 'unsupported_media_type', 'Send this as multipart/form-data.');
    }
    const bytes = await readLimited(req, op.maxBodyBytes ?? DEFAULT_UPLOAD_LIMIT);
    try {
      return await new Response(bytes, { headers: { 'content-type': contentType } }).formData();
    } catch {
      throw badRequest('The upload could not be read.');
    }
  }

  const bytes = await readLimited(req, op.maxBodyBytes ?? DEFAULT_JSON_LIMIT);
  let json: unknown = undefined;
  if (bytes.byteLength > 0) {
    if (!contentType.startsWith('application/json')) {
      throw new HttpError(415, 'unsupported_media_type', 'Send this as application/json.');
    }
    try {
      json = JSON.parse(new TextDecoder().decode(bytes));
    } catch {
      throw badRequest('The body is not valid JSON.');
    }
    // Postgres text can't hold a NUL, so one anywhere in a string used to reach the database
    // and come back as a 500 (D2-F4). Nothing Glow stores needs one: refuse it up front.
    if (hasNul(json)) throw badRequest('The body is not valid.');
  }
  const parsed = op.body.safeParse(json);
  if (!parsed.success) throw badRequest('The body is not valid.', issuesOf(parsed.error, 'body'));
  return parsed.data;
}

/**
 * True if any string in `value` (a key or a value) holds a NUL character. Nesting deeper than
 * 64 levels counts as true too: no Glow body is anywhere near that deep.
 */
export function hasNul(value: unknown, depth = 0): boolean {
  if (typeof value === 'string') return value.includes('\u0000');
  if (value === null || typeof value !== 'object') return false;
  if (depth > 64) return true;
  if (Array.isArray(value)) return value.some((v) => hasNul(v, depth + 1));
  return Object.entries(value).some(([k, v]) => k.includes('\u0000') || hasNul(v, depth + 1));
}

const tooLarge = () => new HttpError(413, 'payload_too_large', 'That request is too large.');

/** Reads the body, stopping as soon as it's bigger than `limit`. */
async function readLimited(req: Request, limit: number): Promise<Uint8Array<ArrayBuffer>> {
  const declared = Number(req.headers.get('content-length') ?? NaN);
  if (Number.isFinite(declared) && declared > limit) throw tooLarge();
  if (!req.body) return new Uint8Array(new ArrayBuffer(0));
  const reader = req.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > limit) {
      // Stop reading and let go, rather than cancel(): on Node 24, cancelling a body
      // that undici is still producing raises an unhandled rejection, and an unhandled
      // rejection can stop the process. The unread rest is dropped with the request.
      reader.releaseLock();
      throw tooLarge();
    }
    chunks.push(value);
  }
  const out = new Uint8Array(new ArrayBuffer(size));
  let offset = 0;
  for (const chunk of chunks) {
    out.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return out;
}

/** Field paths and rule names only. Values the person sent are never echoed back. */
function issuesOf(error: z.ZodError, root: string): ErrorIssue[] {
  return error.issues.slice(0, 20).map((issue) => ({
    path: [root, ...issue.path.map(String)].join('.'),
    code: issue.code,
    message: issue.message,
  }));
}

function json(status: number, body: unknown, headers: Headers = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...headers,
      'content-type': 'application/json; charset=utf-8',
      'cache-control': NO_STORE,
    },
  });
}

class ContractViolation extends Error {
  override readonly name = 'ContractViolation';
}

function toResponse(operationId: string, op: OperationDef, reply: unknown): Response {
  if (reply instanceof Response) {
    if (op.responses[reply.status] !== 'raw') {
      throw new ContractViolation(`${operationId} returned a raw ${reply.status} response`);
    }
    if (!reply.headers.has('cache-control')) reply.headers.set('cache-control', NO_STORE);
    return reply;
  }
  const { status, body, headers } = reply as { status: number; body?: unknown; headers?: Headers };
  const spec = op.responses[status];
  if (spec === undefined || spec === 'raw') {
    throw new ContractViolation(`${operationId} has no JSON ${status} response in the contract`);
  }
  if (spec === null) {
    return new Response(null, { status, headers: { ...headers, 'cache-control': NO_STORE } });
  }
  const parsed = spec.safeParse(body);
  if (!parsed.success) {
    // Log where the reply broke the contract, never the values in it.
    logger.error('api.contract_violation', {
      operation: operationId,
      status,
      paths: parsed.error.issues.map((i) => i.path.join('.') || '(root)').join(','),
    });
    throw new ContractViolation(`${operationId} replied with a body that breaks the contract`);
  }
  return json(status, parsed.data, headers);
}

function errorResponse(operationId: string, error: unknown): Response {
  if (error instanceof HttpError) {
    // P11: "not allowed" and "doesn't exist" must look exactly the same.
    const shown = error.status === 403 ? notFound() : error;
    return json(shown.status, errorBody(shown), shown.headers ?? {});
  }
  const errorClass = error instanceof Error ? error.name : typeof error;
  logger.error('api.unhandled', { operation: operationId, errorClass });
  captureError(error, { operation: operationId });
  return json(500, errorBody(new HttpError(500, 'internal', 'Something went wrong on our side.')));
}
