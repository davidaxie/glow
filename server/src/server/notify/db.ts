/**
 * The service-role Supabase client this module uses for the `devices` table. Server only:
 * the service key never leaves the server. If A1 adds a shared client, this file switches
 * to it.
 */
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { getEnv } from '@/env';
import type { Database } from '@/contracts';

const DB_TIMEOUT_MS = 5000;

let client: SupabaseClient<Database> | undefined;
let clientKey: string | undefined;

export function serviceDb(): SupabaseClient<Database> {
  const env = getEnv();
  const key = `${env.SUPABASE_URL}|${env.SUPABASE_SERVICE_ROLE_KEY}`;
  if (client && clientKey === key) return client;
  client = createClient<Database>(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    global: {
      fetch: (input, init) =>
        fetch(input, { ...init, signal: init?.signal ?? AbortSignal.timeout(DB_TIMEOUT_MS) }),
    },
  });
  clientKey = key;
  return client;
}
