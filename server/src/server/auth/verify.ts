import { createClient, isAuthApiError, isAuthRetryableFetchError } from '@supabase/supabase-js';
import type { SupabaseClient, User } from '@supabase/supabase-js';
import { getEnv } from '@/env';

/** A person whose Supabase access token the server has checked. */
export type AuthUser = {
  readonly id: string;
  readonly email: string | null;
};

export type VerifyOutcome =
  | { readonly kind: 'valid'; readonly user: AuthUser }
  | { readonly kind: 'invalid' }
  | { readonly kind: 'unavailable' };

/** How long to wait for Supabase Auth before answering 503. */
export const AUTH_TIMEOUT_MS = 3000;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

let client: SupabaseClient | undefined;

function authClient(): SupabaseClient {
  if (client) return client;
  const env = getEnv();
  client = createClient(env.SUPABASE_URL, env.SUPABASE_ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    global: {
      fetch: (input, init) =>
        fetch(input, { ...init, signal: init?.signal ?? AbortSignal.timeout(AUTH_TIMEOUT_MS) }),
    },
  });
  return client;
}

/**
 * Asks Supabase Auth whether `token` is a live session. This is a network call on
 * purpose: it means a deleted, banned or signed-out account stops working at once,
 * instead of when its token expires (see docs/DECISIONS.md, D3).
 */
export async function verifyAccessToken(token: string): Promise<VerifyOutcome> {
  let result: Awaited<ReturnType<SupabaseClient['auth']['getUser']>>;
  try {
    result = await authClient().auth.getUser(token);
  } catch {
    return { kind: 'unavailable' };
  }
  const { data, error } = result;
  if (error) {
    if (isAuthRetryableFetchError(error)) return { kind: 'unavailable' };
    if (isAuthApiError(error) && error.status >= 500) return { kind: 'unavailable' };
    return { kind: 'invalid' };
  }
  return accept(data.user);
}

/** Only real, signed-in, unbanned people get through. Anonymous Supabase users don't. */
export function accept(user: User | null | undefined, now = Date.now()): VerifyOutcome {
  if (!user || !UUID.test(user.id)) return { kind: 'invalid' };
  if (user.is_anonymous === true) return { kind: 'invalid' };
  if (user.role !== undefined && user.role !== 'authenticated') return { kind: 'invalid' };
  if (user.aud !== 'authenticated') return { kind: 'invalid' };
  const bannedUntil = (user as { banned_until?: string | null }).banned_until;
  if (bannedUntil && Date.parse(bannedUntil) > now) return { kind: 'invalid' };
  return { kind: 'valid', user: { id: user.id, email: user.email ?? null } };
}
