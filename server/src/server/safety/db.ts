/**
 * Owner: B8. The service-role database client for safety, moderation and cleanup, plus
 * `rpc()`, which calls a database function and turns its expected failures into the
 * contract's HTTP errors (docs/CONTRACTS.md, "Database errors").
 *
 * The rules that must never break (who is blocked, what a report keeps, what purge deletes)
 * live in those functions. This file only moves data and maps errors. It never logs
 * arguments or results, only the function name and an error code.
 */
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '@/contracts';
import { getEnv } from '@/env';
import { badRequest, notFound, unavailable, type HttpError } from '@/server/http';
import { logger } from '@/server/log';

/** Past this, a database call gives up, so a request answers instead of hanging. */
export const DB_TIMEOUT_MS = 8000;

export type Db = SupabaseClient<Database>;
type Functions = Database['public']['Functions'];
export type DbFunction = keyof Functions & string;

let cached: { readonly key: string; readonly client: Db } | undefined;

/** The service-role client. Server only: it bypasses row level security. */
export function serviceDb(): Db {
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

/** A database error the route can't recover from. Becomes a generic 500. */
export class DatabaseError extends Error {
  override readonly name = 'DatabaseError';
}

type PostgrestErrorLike = { readonly code?: string; readonly message?: string };

const EXPECTED: Readonly<Record<string, () => HttpError>> = {
  not_found: notFound,
  invalid_input: () => badRequest(),
};

/** Maps a PostgREST or Storage error to the contract's HTTP error, or a DatabaseError. */
export function dbError(where: string, error: PostgrestErrorLike): Error {
  if (error.code === 'P0001' && error.message && EXPECTED[error.message]) {
    return EXPECTED[error.message]!();
  }
  // supabase-js reports a timeout or a refused connection as a fetch failure with no code.
  if (!error.code || error.code === '' || /fetch|abort|timeout/i.test(error.message ?? '')) {
    logger.error('safety.db_unavailable', { where });
    return unavailable();
  }
  logger.error('safety.db_error', { where, code: error.code });
  return new DatabaseError(`${where} failed (${error.code})`);
}

/** Calls a database function with named `p_` arguments. Throws the mapped error. */
export async function rpc<F extends DbFunction>(
  fn: F,
  args: Functions[F]['Args'],
): Promise<Functions[F]['Returns']> {
  const { data, error } = await serviceDb().rpc(fn, args as never);
  if (error) throw dbError(fn, error);
  return data as Functions[F]['Returns'];
}
