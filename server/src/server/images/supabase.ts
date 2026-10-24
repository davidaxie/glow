/**
 * The service-role Supabase client the image routes use for database functions and the two
 * private buckets. Only the server holds this key; buckets have no policies, so nothing else
 * can read an object (P4).
 */
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '@/contracts';
import { getEnv } from '@/env';

export type ServiceClient = SupabaseClient<Database>;

export const CARD_BUCKET = 'room-cards';
export const PROFILE_BUCKET = 'profile-photos';

/** How long to wait for Supabase before answering 503. */
export const SUPABASE_TIMEOUT_MS = 8000;

let client: ServiceClient | undefined;

export function serviceClient(): ServiceClient {
  if (client) return client;
  const env = getEnv();
  client = createClient<Database>(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    global: {
      fetch: (input, init) =>
        fetch(input, { ...init, signal: init?.signal ?? AbortSignal.timeout(SUPABASE_TIMEOUT_MS) }),
    },
  });
  return client;
}

/** For tests: forget the cached client. */
export function resetServiceClientForTests(): void {
  client = undefined;
}
