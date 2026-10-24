/**
 * D2's security tests against a real local Supabase: the Auth, REST, Storage and Realtime
 * APIs exactly as an attacker with the app's anon key would reach them.
 *
 * Which stack (same rules as B8's live tests):
 * - An agent's own stack, from `eval "$(scripts/agent-env.sh D2 --own-db)"`
 *   (GLOW_SUPABASE_URL plus the keys it exports).
 * - In CI (no agent ID), the stack CI starts, read from server/.env.local.
 * - An agent on the shared `glow` stack: skipped, so nobody else's data is touched.
 *
 * Only local addresses are ever used (http://127.0.0.1 or localhost), so these tests can't
 * be pointed at a cloud project by accident.
 */
import { randomUUID } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';

export type Live = { readonly url: string; readonly anonKey: string; readonly serviceKey: string };

const LOCAL = /^http:\/\/(127\.0\.0\.1|localhost):\d+$/;

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
  let live: Live | null = null;
  if (env.GLOW_SUPABASE_URL && env.SUPABASE_SERVICE_ROLE_KEY && env.SUPABASE_ANON_KEY) {
    live = {
      url: env.GLOW_SUPABASE_URL,
      anonKey: env.SUPABASE_ANON_KEY,
      serviceKey: env.SUPABASE_SERVICE_ROLE_KEY,
    };
  } else if (!env.GLOW_AGENT_ID) {
    const file = fromEnvFile();
    if (file.SUPABASE_URL && file.SUPABASE_ANON_KEY && file.SUPABASE_SERVICE_ROLE_KEY) {
      live = {
        url: file.SUPABASE_URL,
        anonKey: file.SUPABASE_ANON_KEY,
        serviceKey: file.SUPABASE_SERVICE_ROLE_KEY,
      };
    }
  }
  return live && LOCAL.test(live.url) ? live : null;
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
/** The live stack, or null when there isn't one to use (the tests then skip). */
export const LIVE: Live | null = candidate && (await reachable(candidate)) ? candidate : null;

export const tag = () => randomUUID().slice(0, 8);

export type Reply = { readonly status: number; readonly json: Record<string, unknown> };

/** One call to Supabase with the given key (anon by default) and optional bearer token. */
export async function supa(
  live: Live,
  method: string,
  path: string,
  options: { body?: unknown; token?: string; key?: 'anon' | 'service' } = {},
): Promise<Reply> {
  const key = options.key === 'service' ? live.serviceKey : live.anonKey;
  const res = await fetch(`${live.url}${path}`, {
    method,
    headers: {
      apikey: key,
      authorization: `Bearer ${options.token ?? key}`,
      ...(options.body === undefined ? {} : { 'content-type': 'application/json' }),
    },
    ...(options.body === undefined ? {} : { body: JSON.stringify(options.body) }),
  });
  const text = await res.text();
  let json: Record<string, unknown> = {};
  try {
    const parsed: unknown = JSON.parse(text);
    if (parsed && typeof parsed === 'object') json = parsed as Record<string, unknown>;
  } catch {
    // Not JSON (an image, say); the status is what matters.
  }
  return { status: res.status, json };
}
