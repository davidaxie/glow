/**
 * Owner: B4. The service-role database client the deck, taps and matches modules share,
 * plus `rpc()`, which calls a database function and turns its expected failures into the
 * contract's HTTP errors (docs/CONTRACTS.md, "Database errors").
 *
 *   const deck = await rpc('get_deck', { p_viewer_id, p_room_id, p_filters, p_offset });
 *
 * Every rule that decides who sees whom lives in those functions (get_deck, record_tap,
 * list_matches). This file only moves data and maps errors. It never logs arguments or
 * results, only the function name and an error code (P2).
 */
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '@/contracts';
import { getEnv } from '@/env';
import { badRequest, conflict, notFound, unavailable, type HttpError } from '@/server/http';
import { logger } from '@/server/log';

/** Past this, a database call answers 503 so the app retries, instead of hanging. */
export const DB_TIMEOUT_MS = 5000;

type Functions = Database['public']['Functions'];
export type DbFunction = keyof Functions & string;

let cached: { readonly key: string; readonly client: SupabaseClient<Database> } | undefined;

/** The service-role client. Server only: it bypasses row level security. */
export function serviceDb(): SupabaseClient<Database> {
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

/** Error codes the database functions raise as SQLSTATE P0001, mapped to HTTP. */
const EXPECTED: Readonly<Record<string, () => HttpError>> = {
  not_found: notFound,
  invalid_input: () => badRequest(),
  tap_limit_reached: () => conflict('tap_limit_reached', 'No taps left today in this room.'),
  room_not_live: () => conflict('room_not_live', 'This room is not live right now.'),
  onboarding_incomplete: () =>
    conflict('onboarding_incomplete', 'Finish setting up your profile first.'),
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
  // PostgREST answers PGRST000-PGRST003 when it can't reach the database or the pool is
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
  fn: F,
  args: Functions[F]['Args'],
): Promise<Functions[F]['Returns']> {
  let result: { data: unknown; error: PostgrestErrorLike | null; status: number };
  try {
    // supabase-js types rpc() per function; the generic F is narrowed by the caller.
    result = (await serviceDb().rpc(fn, args as never)) as typeof result;
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
