/**
 * B8's tests against a real local Supabase: blocks, pause, account deletion and purge.
 *
 * Which database:
 * - An agent's own stack, from `eval "$(scripts/agent-env.sh B8 --own-db)"`
 *   (GLOW_SUPABASE_URL plus the keys it exports).
 * - In CI (no agent ID), the stack CI starts, read from server/.env.local, which
 *   `scripts/env-setup.sh --force` writes from `supabase status`.
 * - An agent on the shared `glow` stack: skipped, so parallel agents never touch each
 *   other's data. These tests only add their own throwaway people and rooms, and delete
 *   them afterwards, but purge runs for real.
 *
 * Values are read once, at import, before tests/setup.ts swaps in its fake env.
 */
import { randomUUID } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '@/contracts';
import { resetEnvCacheForTests } from '@/env';

export type Live = { readonly url: string; readonly anonKey: string; readonly serviceKey: string };

function fromEnvFile(): Partial<Record<string, string>> {
  const file = new URL('../../../.env.local', import.meta.url);
  if (!existsSync(file)) return {};
  const out: Record<string, string> = {};
  for (const line of readFileSync(file, 'utf8').split('\n')) {
    const m = /^([A-Z_]+)=(.*)$/.exec(line.trim());
    if (m?.[1] && m[2] !== undefined) out[m[1]] = m[2].replace(/^['"]|['"]$/g, '');
  }
  return out;
}

function resolve(): Live | null {
  const env = process.env;
  if (env.GLOW_SUPABASE_URL && env.SUPABASE_SERVICE_ROLE_KEY && env.SUPABASE_ANON_KEY) {
    return {
      url: env.GLOW_SUPABASE_URL,
      anonKey: env.SUPABASE_ANON_KEY,
      serviceKey: env.SUPABASE_SERVICE_ROLE_KEY,
    };
  }
  if (env.GLOW_AGENT_ID) return null;
  const file = fromEnvFile();
  if (!file.SUPABASE_URL || !file.SUPABASE_ANON_KEY || !file.SUPABASE_SERVICE_ROLE_KEY) return null;
  if (!/^http:\/\/(127\.0\.0\.1|localhost):\d+$/.test(file.SUPABASE_URL)) return null;
  return {
    url: file.SUPABASE_URL,
    anonKey: file.SUPABASE_ANON_KEY,
    serviceKey: file.SUPABASE_SERVICE_ROLE_KEY,
  };
}

async function reachable(live: Live): Promise<boolean> {
  try {
    const res = await fetch(`${live.url}/auth/v1/health`, {
      headers: { apikey: live.anonKey },
      signal: AbortSignal.timeout(1500),
    });
    return res.ok;
  } catch {
    return false;
  }
}

const candidate = resolve();
export const LIVE: Live | null = candidate && (await reachable(candidate)) ? candidate : null;

/** Points the server's env at the live stack. Call in beforeEach. */
export function useLiveEnv(live: Live): void {
  process.env.SUPABASE_URL = live.url;
  process.env.SUPABASE_ANON_KEY = live.anonKey;
  process.env.SUPABASE_SERVICE_ROLE_KEY = live.serviceKey;
  resetEnvCacheForTests();
}

export function adminClient(live: Live): SupabaseClient<Database> {
  return createClient<Database>(live.url, live.serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

export const tag = () => randomUUID().slice(0, 8);
