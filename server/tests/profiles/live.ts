/**
 * Helpers for B1's tests against a real local Supabase (CI starts one before Vitest).
 * Each test person is a throwaway `b1-test-…@glow.test` account, deleted afterwards.
 *
 * Point them at another stack with GLOW_SUPABASE_URL (from `scripts/agent-env.sh B1 --own-db`).
 * Without a reachable Supabase they're skipped.
 */
import { createClient } from '@supabase/supabase-js';
import { NextRequest } from 'next/server';
import { resetEnvCacheForTests } from '@/env';
import type { Database } from '@/contracts/database';
import { resetServiceDbForTests } from '@/server/profiles/db';

/** The standard keys of every local `supabase start`. Public, and only valid on 127.0.0.1. */
const LOCAL_ANON = 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH';
const LOCAL_SERVICE = 'sb_secret_N7UND0UgjKTVK-Uodkm0Hg_xSvEMPvz';

export const LIVE_URL = process.env.GLOW_SUPABASE_URL ?? 'http://127.0.0.1:54421';

async function reachable(): Promise<boolean> {
  try {
    const res = await fetch(`${LIVE_URL}/auth/v1/health`, {
      headers: { apikey: LOCAL_ANON },
      signal: AbortSignal.timeout(1500),
    });
    return res.ok;
  } catch {
    return false;
  }
}

export const supabaseUp = await reachable();

/** Call in `beforeEach`, after the global setup reset the env to fake values. */
export function useLiveSupabase({ testLogin = false }: { testLogin?: boolean } = {}): void {
  process.env.SUPABASE_URL = LIVE_URL;
  process.env.SUPABASE_ANON_KEY = LOCAL_ANON;
  process.env.SUPABASE_SERVICE_ROLE_KEY = LOCAL_SERVICE;
  if (testLogin) process.env.ALLOW_TEST_LOGIN = '1';
  resetEnvCacheForTests();
  resetServiceDbForTests();
}

export const admin = () =>
  createClient<Database>(LIVE_URL, LOCAL_SERVICE, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

export type TestPerson = { readonly id: string; readonly email: string; readonly token: string };

/** A new person with a real Supabase session, the way the email code would sign them in. */
export async function newPerson(): Promise<TestPerson> {
  const email = `b1-test-${crypto.randomUUID().slice(0, 12)}@glow.test`;
  const db = admin();
  const link = await db.auth.admin.generateLink({ type: 'magiclink', email });
  if (link.error) throw link.error;
  const anon = createClient(LIVE_URL, LOCAL_ANON, { auth: { persistSession: false } });
  const { data, error } = await anon.auth.verifyOtp({
    type: 'email',
    token_hash: link.data.properties.hashed_token,
  });
  if (error || !data.session || !data.user) throw error ?? new Error('no session');
  return { id: data.user.id, email, token: data.session.access_token };
}

/** Deletes the person, their rows (by cascade) and their photo objects. */
export async function removePerson(person: TestPerson | undefined): Promise<void> {
  if (!person) return;
  const db = admin();
  const { data } = await db.storage.from('profile-photos').list(person.id);
  if (data && data.length > 0) {
    await db.storage.from('profile-photos').remove(data.map((f) => `${person.id}/${f.name}`));
  }
  await db.auth.admin.deleteUser(person.id);
}

type Handler = (
  req: NextRequest,
  ctx: { params: Promise<Record<string, string>> },
) => Promise<Response>;

/** Calls a route file's export the way Next.js does. */
export function call(
  handler: Handler,
  {
    method = 'GET',
    path,
    token,
    json,
    params = {},
  }: {
    method?: string;
    path: string;
    token?: string;
    json?: unknown;
    params?: Record<string, string>;
  },
): Promise<Response> {
  const headers: Record<string, string> = token ? { authorization: `Bearer ${token}` } : {};
  if (json !== undefined) headers['content-type'] = 'application/json';
  const req = new NextRequest(`http://localhost${path}`, {
    method,
    headers,
    ...(json !== undefined ? { body: JSON.stringify(json) } : {}),
  });
  return handler(req, { params: Promise.resolve(params) });
}

/** Every UUID in a JSON reply, to check that no one else's ID is in it (P1). */
export function uuidsIn(value: unknown): string[] {
  return [
    ...JSON.stringify(value).matchAll(
      /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi,
    ),
  ].map((m) => m[0].toLowerCase());
}

export const base64 = (bytes: Uint8Array) => Buffer.from(bytes).toString('base64');
