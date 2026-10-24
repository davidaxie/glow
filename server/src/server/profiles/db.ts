/**
 * The service-role Supabase client B1's routes use for `profiles`, `profile_photos`, `admins`
 * and the private `profile-photos` bucket. Server only: the service key never reaches the app.
 */
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '@/contracts/database';
import { getEnv } from '@/env';

export type Db = SupabaseClient<Database>;

/** How long one database or storage call may take before the route gives up with a 503. */
export const DB_TIMEOUT_MS = 5000;

export const PROFILE_PHOTOS_BUCKET = 'profile-photos';

let client: Db | undefined;

export function serviceDb(): Db {
  if (client) return client;
  const env = getEnv();
  client = createClient<Database>(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    global: {
      fetch: (input, init) =>
        fetch(input, { ...init, signal: init?.signal ?? AbortSignal.timeout(DB_TIMEOUT_MS) }),
    },
  });
  return client;
}

/** Tests only: forget the cached client, so the next call reads the environment again. */
export function resetServiceDbForTests(): void {
  client = undefined;
}
