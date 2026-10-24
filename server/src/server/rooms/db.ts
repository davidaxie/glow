/**
 * The service-role Supabase client for B2's routes. Owner: B2.
 *
 * Only the server holds the service role key. Every table has RLS on with no client
 * policies, so this is the only way in. No session is kept or refreshed.
 */
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '@/contracts';
import { getEnv } from '@/env';

export type Db = SupabaseClient<Database>;

let client: Db | undefined;

export function serviceDb(): Db {
  if (!client) {
    const env = getEnv();
    client = createClient<Database>(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
      global: { headers: { 'x-glow-module': 'rooms' } },
    });
  }
  return client;
}

/** For tests: forget the cached client, or use a fake one. */
export function setServiceDbForTests(fake: Db | undefined): void {
  client = fake;
}
