/**
 * Integration helpers for the local Supabase stack (`pnpm db:start`, or CI's `supabase start`).
 * Tests that use these skip themselves when no local stack answers.
 *
 * The defaults are the Supabase CLI's public demo keys (the same on every machine, and in
 * server/.env.example). Point at another stack with GLOW_IT_SUPABASE_URL,
 * GLOW_IT_SUPABASE_ANON_KEY and GLOW_IT_SUPABASE_SERVICE_ROLE_KEY. Local addresses only.
 */
import { randomBytes } from 'node:crypto';
import { createClient, type RealtimeChannel, type SupabaseClient } from '@supabase/supabase-js';
import { resetEnvCacheForTests } from '@/env';

// Read once at import, before tests/setup.ts swaps in fake keys for every test.
export const LOCAL = {
  url: process.env.GLOW_IT_SUPABASE_URL ?? 'http://127.0.0.1:54421',
  anonKey:
    process.env.GLOW_IT_SUPABASE_ANON_KEY ?? 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH',
  serviceKey:
    process.env.GLOW_IT_SUPABASE_SERVICE_ROLE_KEY ?? 'sb_secret_N7UND0UgjKTVK-Uodkm0Hg_xSvEMPvz',
} as const;

if (!/^http:\/\/(127\.0\.0\.1|localhost)(:\d+)?$/.test(LOCAL.url)) {
  throw new Error('Integration tests only run against a local Supabase.');
}

/** True if the local stack answers within a second. */
export async function localSupabaseIsUp(): Promise<boolean> {
  try {
    const res = await fetch(`${LOCAL.url}/auth/v1/health`, {
      headers: { apikey: LOCAL.anonKey },
      signal: AbortSignal.timeout(1000),
    });
    return res.ok;
  } catch {
    return false;
  }
}

/** Points getEnv() at the local stack for this test. */
export function useLocalSupabase(): void {
  Object.assign(process.env, {
    SUPABASE_URL: LOCAL.url,
    SUPABASE_ANON_KEY: LOCAL.anonKey,
    SUPABASE_SERVICE_ROLE_KEY: LOCAL.serviceKey,
  });
  resetEnvCacheForTests();
}

export type TestPerson = {
  readonly id: string;
  readonly accessToken: string;
  /** A client signed in as this person, the way the app would be. */
  readonly client: SupabaseClient;
};

const admin = () =>
  createClient(LOCAL.url, LOCAL.serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

/** A brand-new throwaway `@glow.test` person, signed in. Delete with `deletePeople`. */
export async function createPerson(): Promise<TestPerson> {
  const email = `b5-it+${randomBytes(6).toString('hex')}@glow.test`;
  const password = randomBytes(24).toString('base64url');
  const created = await admin().auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { test_data: true },
  });
  if (created.error || !created.data.user) throw new Error('could not create a test person');

  const client = createClient(LOCAL.url, LOCAL.anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const signedIn = await client.auth.signInWithPassword({ email, password });
  if (signedIn.error || !signedIn.data.session)
    throw new Error('could not sign in the test person');
  await client.realtime.setAuth(signedIn.data.session.access_token);
  return { id: created.data.user.id, accessToken: signedIn.data.session.access_token, client };
}

export async function deletePeople(people: readonly TestPerson[]): Promise<void> {
  for (const person of people) {
    await person.client.removeAllChannels();
    await admin().auth.admin.deleteUser(person.id);
  }
}

export type Joined = {
  readonly channel: RealtimeChannel;
  readonly status: string;
  /** Every broadcast received so far: `{ event, payload }`. */
  readonly received: { event: string; payload: unknown }[];
};

/** Joins a private channel as this person and waits until Realtime accepts or refuses. */
export async function join(person: TestPerson, topic: string, timeoutMs = 8000): Promise<Joined> {
  const received: { event: string; payload: unknown }[] = [];
  const channel = person.client.channel(topic, { config: { private: true } });
  channel.on('broadcast', { event: '*' }, (message) => {
    received.push({ event: String(message.event), payload: message.payload });
  });
  const status = await new Promise<string>((resolve) => {
    const timer = setTimeout(() => resolve('TIMED_OUT'), timeoutMs);
    channel.subscribe((state) => {
      if (state === 'SUBSCRIBED' || state === 'CHANNEL_ERROR' || state === 'CLOSED') {
        clearTimeout(timer);
        resolve(state);
      }
    });
  });
  return { channel, status, received };
}

/** Waits until `check` is true, or the time runs out. */
export async function eventually(check: () => boolean, timeoutMs = 5000): Promise<boolean> {
  const end = Date.now() + timeoutMs;
  while (Date.now() < end) {
    if (check()) return true;
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  return check();
}
