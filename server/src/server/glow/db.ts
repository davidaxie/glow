/**
 * Owner: C3. The service-role database client for glow, and `rpc()`, which calls a database
 * function and turns its expected failures into the contract's HTTP errors (docs/CONTRACTS.md,
 * "Database errors").
 *
 *   const result = await rpc(db, 'glow_met', { p_user_id, p_match_id });
 *
 * The rules (which color, which word, who may end a glow) live in the database functions
 * `start_glow`, `glow_met`, `cancel_glow` and `get_match`. This file only moves data and maps
 * errors. It never logs arguments or results, only the function name and an error code (P2).
 */
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '@/contracts';
import { getEnv } from '@/env';
import { badRequest, notFound, unavailable, type HttpError } from '@/server/http';
import { logger } from '@/server/log';

/** Past this, a database call answers 503 so the app retries, instead of hanging. */
export const DB_TIMEOUT_MS = 5000;

export type GlowDb = SupabaseClient<Database>;
type Functions = Database['public']['Functions'];
export type DbFunction = keyof Functions & string;

let cached: { readonly key: string; readonly client: GlowDb } | undefined;

/** The service-role client. Server only: it bypasses row level security. */
export function serviceDb(): GlowDb {
  const env = getEnv();
  const key = `${env.SUPABASE_URL}\n${env.SUPABASE_SERVICE_ROLE_KEY}`;
  if (cached?.key === key) return cached.client;
  const client = createClient<Database>(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    global: {
      fetch: (input, init) =>
        fetch(input, { ...init, signal: init?.signal ?? AbortSignal.timeout(DB_TIMEOUT_MS) }),
    },
  });
  cached = { key, client };
  return client;
}

/** Codes the glow functions raise as SQLSTATE P0001, mapped to HTTP. */
const EXPECTED: Readonly<Record<string, () => HttpError>> = {
  // Also "exists, but it isn't yours", and "it ended" (P11).
  not_found: notFound,
  invalid_input: () => badRequest(),
};

type PostgrestErrorLike = { readonly code?: string; readonly message?: string };

/** A database error the route can't recover from. Becomes a generic 500. */
export class DatabaseError extends Error {
  override readonly name = 'DatabaseError';
}

/** Maps a PostgREST error to the HTTP error the contract promises, or a DatabaseError. */
export function mapDbError(fn: string, error: PostgrestErrorLike): Error {
  if (error.code === 'P0001' && error.message && EXPECTED[error.message]) {
    return EXPECTED[error.message]!();
  }
  // PostgREST answers PGRST000 to PGRST003 when it can't reach the database or the pool is
  // exhausted, and 57014 is a statement timeout. All of these are worth a retry.
  if (error.code && (/^PGRST00[0-3]$/.test(error.code) || error.code === '57014')) {
    logger.warn('db.unavailable', { fn, code: error.code });
    return unavailable();
  }
  logger.error('db.error', { fn, code: error.code ?? 'unknown' });
  return new DatabaseError(`${fn} failed`);
}

/**
 * Calls a database function as the service role. Throws the mapped HttpError for expected
 * failures, 503 when the database can't be reached in time, and a DatabaseError otherwise.
 */
export async function rpc<F extends DbFunction>(
  db: GlowDb,
  fn: F,
  args: Functions[F]['Args'],
): Promise<Functions[F]['Returns']> {
  let result: { data: unknown; error: PostgrestErrorLike | null; status: number };
  try {
    // supabase-js types rpc() per function; the generic F is narrowed by the caller.
    result = (await db.rpc(fn, args as never)) as typeof result;
  } catch {
    result = { data: null, error: { code: 'fetch_failed' }, status: 0 };
  }
  if (result.error && result.status === 0) {
    // fetch itself failed: the database API is down, or DB_TIMEOUT_MS passed.
    logger.warn('db.unavailable', { fn, code: 'fetch_failed' });
    throw unavailable();
  }
  if (result.error) throw mapDbError(fn, result.error);
  return result.data as Functions[F]['Returns'];
}

/** The ID of this match's active glow, if it has one. Lets a route tell "I just ended it" apart
 *  from "it had already ended", so glow.ended goes out once. */
export async function activeGlowId(db: GlowDb, matchId: string): Promise<string | null> {
  let result: { data: { id: string } | null; error: PostgrestErrorLike | null; status: number };
  try {
    result = await db
      .from('glow_sessions')
      .select('id')
      .eq('match_id', matchId)
      .eq('status', 'active')
      .maybeSingle();
  } catch {
    result = { data: null, error: { code: 'fetch_failed' }, status: 0 };
  }
  if (result.error && result.status === 0) {
    logger.warn('db.unavailable', { fn: 'glow_sessions', code: 'fetch_failed' });
    throw unavailable();
  }
  if (result.error) throw mapDbError('glow_sessions', result.error);
  return result.data?.id ?? null;
}
