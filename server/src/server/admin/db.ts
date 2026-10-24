/**
 * The service-role Supabase client for the admin module. Server only: the service key never
 * reaches a browser or the app (spec: Environment and secrets). Only server components,
 * server actions and route handlers import this; client components under app/admin get
 * plain data from server actions. Server variables have no NEXT_PUBLIC_ prefix, so a
 * browser bundle could never see the key anyway.
 */
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '@/contracts';
import { getEnv } from '@/env';

export type Db = SupabaseClient<Database>;

let service: Db | undefined;
let anon: SupabaseClient | undefined;

const noSession = { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false };

/** Reads and writes every table, bypassing row level security. */
export function serviceDb(): Db {
  if (service) return service;
  const env = getEnv();
  service = createClient<Database>(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
    auth: noSession,
  });
  return service;
}

/** Supabase Auth with the anon key, for sign-in codes and refreshing sessions. */
export function anonAuth(): SupabaseClient['auth'] {
  if (anon) return anon.auth;
  const env = getEnv();
  anon = createClient(env.SUPABASE_URL, env.SUPABASE_ANON_KEY, { auth: noSession });
  return anon.auth;
}
