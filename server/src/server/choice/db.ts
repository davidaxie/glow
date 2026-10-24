/**
 * The service-role Supabase client for C2's routes. Owner: C2.
 *
 * Only the server holds the service role key. Every table has RLS on with no client
 * policies, so this is the only way in. No session is kept or refreshed.
 */
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '@/contracts';
import { getEnv } from '@/env';

export type Db = SupabaseClient<Database>;

let cached: { readonly key: string; readonly client: Db } | undefined;

export function serviceDb(): Db {
  const env = getEnv();
  // Keyed on the URL and key, so a test that points the env at another stack gets a new client.
  const key = `${env.SUPABASE_URL}\u0000${env.SUPABASE_SERVICE_ROLE_KEY}`;
  if (cached?.key !== key) {
    cached = {
      key,
      client: createClient<Database>(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
        auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
        global: { headers: { 'x-glow-module': 'choice' } },
      }),
    };
  }
  return cached.client;
}
