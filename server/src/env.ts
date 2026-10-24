/**
 * Every server environment variable, validated with zod.
 *
 * This file is also loaded by `next.config.ts` through Node's built-in TypeScript
 * support, so it must stay free of path aliases and of TypeScript syntax that needs
 * transforming (enums, namespaces, parameter properties). It only imports `zod`.
 *
 * Which variables are required depends on where the server runs. See the
 * env profiles decision in docs/DECISIONS.md.
 *
 * - local: `pnpm dev` on a laptop, `next start` in CI, and Vitest. Only the local
 *   Supabase keys and the three generated secrets are required.
 * - preview: a Vercel preview deploy. Adds moderation and rate limits, because a
 *   preview is reachable from the internet.
 * - production: the Vercel production deploy. Adds Apple push.
 *
 * Values are never printed, only variable names and what is wrong with them.
 */
import { z } from 'zod';

export type EnvProfile = 'local' | 'preview' | 'production';

type Source = Readonly<Record<string, string | undefined>>;

/** Marks the placeholder secrets in `.env.example`. Rejected on Vercel. */
export const PLACEHOLDER_MARKER = 'local-dev-only';

const SECRET_HINT = 'Generate one with `openssl rand -base64 32`.';

const blankToUndefined = (value: unknown): unknown =>
  typeof value === 'string' && value.trim() === '' ? undefined : value;

const supabaseKey = z
  .string()
  .trim()
  .min(20, 'is too short to be a Supabase API key')
  .refine((v) => !/\s/.test(v), 'must not contain spaces or line breaks');

const randomSecret = z
  .string()
  .trim()
  .min(43, `must be at least 32 random bytes (43 or more characters). ${SECRET_HINT}`)
  .refine((v) => !/\s/.test(v), 'must not contain spaces or line breaks');

const appleId = z
  .string()
  .trim()
  .regex(/^[A-Z0-9]{10}$/, 'must be the 10-character ID from the Apple Developer portal');

/** One zod schema per variable. Every variable is optional here; profiles decide below. */
const formats = {
  SUPABASE_URL: z.url({
    protocol: /^https?$/,
    error: 'must be a URL like http://127.0.0.1:54321 or https://<project>.supabase.co',
  }),
  SUPABASE_ANON_KEY: supabaseKey,
  SUPABASE_SERVICE_ROLE_KEY: supabaseKey,
  ANTHROPIC_API_KEY: z.string().trim().min(20, 'is too short to be an Anthropic API key'),
  APNS_KEY_ID: appleId,
  APNS_TEAM_ID: appleId,
  APNS_PRIVATE_KEY: z
    .string()
    .transform((v) => v.replace(/\\n/g, '\n').trim())
    .refine(
      (v) => /^-----BEGIN PRIVATE KEY-----\n[\s\S]+\n-----END PRIVATE KEY-----$/.test(v),
      'must be the full contents of the .p8 file, including the BEGIN and END lines',
    ),
  APNS_BUNDLE_ID: z
    .string()
    .trim()
    .regex(/^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$/, 'must be a bundle ID like com.example.app'),
  JOIN_TICKET_SECRET: randomSecret,
  CARD_URL_SECRET: randomSecret,
  CRON_SECRET: z
    .string()
    .trim()
    .min(32, `must be at least 32 characters. ${SECRET_HINT}`)
    .refine((v) => !/\s/.test(v), 'must not contain spaces or line breaks'),
  UPSTASH_REDIS_REST_URL: z.url({ protocol: /^https$/, error: 'must be an https URL' }),
  UPSTASH_REDIS_REST_TOKEN: z.string().trim().min(20, 'is too short to be an Upstash token'),
  POSTHOG_KEY: z.string().trim().min(10, 'is too short to be a PostHog project key'),
  // The public TestFlight link on the /r/{slug} page for people without Glow (B2).
  TESTFLIGHT_URL: z.url({
    protocol: /^https$/,
    hostname: /^testflight\.apple\.com$/,
    error: 'must be the public TestFlight link, https://testflight.apple.com/join/...',
  }),
  // TEAMID.bundle.id for the apple-app-site-association file (B2). Separate from the APNS_*
  // group, so a preview without push can still serve the link file.
  APPLE_APP_ID: z
    .string()
    .trim()
    .regex(
      /^[A-Z0-9]{10}\.[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$/,
      'must be TEAMID.bundle.id, like ABCDE12345.com.davidxie.glow',
    ),
  SENTRY_DSN: z.url({ protocol: /^https?$/, error: 'must be the DSN URL from Sentry' }),
  ALLOW_TEST_LOGIN: z
    .enum(['1', 'true', '0', 'false'], { error: 'must be 1, true, 0 or false' })
    .transform((v) => v === '1' || v === 'true'),
} as const;

export type EnvName = keyof typeof formats;
export const ENV_NAMES = Object.keys(formats) as EnvName[];

const CORE = [
  'SUPABASE_URL',
  'SUPABASE_ANON_KEY',
  'SUPABASE_SERVICE_ROLE_KEY',
  'JOIN_TICKET_SECRET',
  'CARD_URL_SECRET',
  'CRON_SECRET',
] as const satisfies readonly EnvName[];

const HOSTED = [
  'ANTHROPIC_API_KEY',
  'UPSTASH_REDIS_REST_URL',
  'UPSTASH_REDIS_REST_TOKEN',
] as const satisfies readonly EnvName[];

const APNS = [
  'APNS_KEY_ID',
  'APNS_TEAM_ID',
  'APNS_PRIVATE_KEY',
  'APNS_BUNDLE_ID',
] as const satisfies readonly EnvName[];

/** Which profiles require each variable. Optional everywhere if it isn't listed. */
export const REQUIRED_IN: Readonly<Partial<Record<EnvName, readonly EnvProfile[]>>> = {
  ...Object.fromEntries(CORE.map((n) => [n, ['local', 'preview', 'production']])),
  ...Object.fromEntries(HOSTED.map((n) => [n, ['preview', 'production']])),
  ...Object.fromEntries(APNS.map((n) => [n, ['production']])),
};

type Out<N extends EnvName> = z.output<(typeof formats)[N]>;

export type Env = { readonly profile: EnvProfile } & {
  readonly [N in (typeof CORE)[number]]: Out<N>;
} & {
  readonly [N in Exclude<EnvName, (typeof CORE)[number] | 'ALLOW_TEST_LOGIN'>]?: Out<N>;
} & { readonly ALLOW_TEST_LOGIN: boolean };

export type EnvProblem = { readonly name: string; readonly message: string };

export type EnvResult =
  | { readonly ok: true; readonly env: Env }
  | { readonly ok: false; readonly profile: EnvProfile; readonly problems: readonly EnvProblem[] };

/** Works out the profile from what Vercel sets. Anything that isn't Vercel is local. */
export function detectProfile(source: Source): EnvProfile {
  const vercelEnv = source.VERCEL_ENV;
  if (vercelEnv === 'production') return 'production';
  if (vercelEnv === 'preview') return 'preview';
  if (source.VERCEL === '1' && vercelEnv !== 'development') return 'preview';
  return 'local';
}

function isLocalHost(url: string): boolean {
  try {
    const host = new URL(url).hostname;
    return (
      host === 'localhost' ||
      host === '127.0.0.1' ||
      host === '[::1]' ||
      host === '::1' ||
      host === 'host.docker.internal' ||
      host.endsWith('.localhost')
    );
  } catch {
    return false;
  }
}

/** Reads the `role` and `iss` claims of a legacy JWT-style Supabase key, without trusting it. */
function jwtClaims(key: string): { role?: unknown; iss?: unknown } | undefined {
  const parts = key.split('.');
  if (parts.length !== 3 || !parts[1]) return undefined;
  try {
    const json: unknown = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8'));
    return typeof json === 'object' && json !== null ? json : undefined;
  } catch {
    return undefined;
  }
}

function isServiceKey(key: string): boolean {
  return key.startsWith('sb_secret_') || jwtClaims(key)?.role === 'service_role';
}

function isPublishableKey(key: string): boolean {
  return key.startsWith('sb_publishable_') || jwtClaims(key)?.role === 'anon';
}

/**
 * Validates `source` (normally `process.env`) and returns either the typed env or
 * every problem found. Pure, so tests can call it with any input.
 */
export function parseEnv(source: Source, profile: EnvProfile = detectProfile(source)): EnvResult {
  const problems: EnvProblem[] = [];
  const values: Record<string, unknown> = {};
  const add = (name: string, message: string) => problems.push({ name, message });

  for (const name of ENV_NAMES) {
    const raw = blankToUndefined(source[name]);
    const required = REQUIRED_IN[name]?.includes(profile) ?? false;
    if (raw === undefined) {
      if (required) add(name, `is missing. ${requiredWhy(name)}`);
      continue;
    }
    const parsed = formats[name].safeParse(raw);
    if (parsed.success) values[name] = parsed.data;
    else add(name, parsed.error.issues[0]?.message ?? 'is not valid');
  }

  const has = (name: EnvName) => values[name] !== undefined;
  const str = (name: EnvName) => values[name] as string | undefined;
  const hosted = profile !== 'local';

  // Groups that only work when every member is set.
  for (const group of [APNS, ['UPSTASH_REDIS_REST_URL', 'UPSTASH_REDIS_REST_TOKEN'] as const]) {
    const set = group.filter(has);
    if (set.length > 0 && set.length < group.length) {
      for (const name of group) {
        if (!has(name) && !problems.some((p) => p.name === name)) {
          add(name, `is missing. It only works together with ${set.join(', ')}.`);
        }
      }
    }
  }

  // The app must only ever hold the anon key. Catch keys pasted into the wrong slot.
  const anon = str('SUPABASE_ANON_KEY');
  const service = str('SUPABASE_SERVICE_ROLE_KEY');
  if (anon && isServiceKey(anon)) {
    add('SUPABASE_ANON_KEY', 'is a service role (secret) key. Use the anon or publishable key.');
  }
  if (service && isPublishableKey(service)) {
    add('SUPABASE_SERVICE_ROLE_KEY', 'is the anon or publishable key. Use the service role key.');
  }
  if (anon && service && anon === service) {
    add('SUPABASE_SERVICE_ROLE_KEY', 'must not be the same as SUPABASE_ANON_KEY.');
  }

  // Each secret signs a different thing, so a leak of one can't forge the others.
  const secrets = (['JOIN_TICKET_SECRET', 'CARD_URL_SECRET', 'CRON_SECRET'] as const).filter(has);
  for (let i = 0; i < secrets.length; i++) {
    for (let j = i + 1; j < secrets.length; j++) {
      const a = secrets[i];
      const b = secrets[j];
      if (a && b && str(a) === str(b)) add(b, `must be different from ${a}.`);
    }
  }

  const supabaseUrl = str('SUPABASE_URL');
  if (hosted) {
    if (supabaseUrl && (isLocalHost(supabaseUrl) || !supabaseUrl.startsWith('https://'))) {
      add('SUPABASE_URL', 'must be your Supabase project URL over https on Vercel, not localhost.');
    }
    for (const name of ['SUPABASE_ANON_KEY', 'SUPABASE_SERVICE_ROLE_KEY'] as const) {
      const key = str(name);
      if (key && jwtClaims(key)?.iss === 'supabase-demo') {
        add(name, 'is the local Supabase demo key. Use the key from your Supabase project.');
      }
    }
    for (const name of ['JOIN_TICKET_SECRET', 'CARD_URL_SECRET', 'CRON_SECRET'] as const) {
      if (str(name)?.includes(PLACEHOLDER_MARKER)) {
        add(name, `is still the placeholder from .env.example. ${SECRET_HINT}`);
      }
    }
    if (values.ALLOW_TEST_LOGIN === true) {
      add('ALLOW_TEST_LOGIN', 'must never be set on Vercel. Test sign-in is for local runs only.');
    }
  }

  // Test sign-in only ever makes sense against the local Supabase.
  if (values.ALLOW_TEST_LOGIN === true && supabaseUrl && !isLocalHost(supabaseUrl)) {
    add('ALLOW_TEST_LOGIN', 'only works with a local SUPABASE_URL (127.0.0.1 or localhost).');
  }

  if (problems.length > 0) return { ok: false, profile, problems: dedupe(problems) };
  return {
    ok: true,
    env: { ...values, ALLOW_TEST_LOGIN: values.ALLOW_TEST_LOGIN === true, profile } as Env,
  };
}

function requiredWhy(name: EnvName): string {
  const where = REQUIRED_IN[name] ?? [];
  if (where.includes('local')) return 'Required in every environment.';
  if (where.includes('preview')) return 'Required on Vercel (preview and production).';
  return 'Required on Vercel production.';
}

function dedupe(problems: EnvProblem[]): EnvProblem[] {
  const seen = new Set<string>();
  return problems.filter((p) => {
    const key = `${p.name}\u0000${p.message}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

/** The message printed when the server refuses to start. Names only, never values. */
export function formatEnvProblems(profile: EnvProfile, problems: readonly EnvProblem[]): string {
  const width = Math.max(...problems.map((p) => p.name.length));
  const count =
    problems.length === 1
      ? '1 environment variable needs'
      : `${problems.length} environment variables need`;
  const lines = problems.map((p) => `  ${p.name.padEnd(width)}  ${p.message}`);
  const fix =
    profile === 'local'
      ? 'Fix: run `pnpm env:setup` from the repo root, or copy server/.env.example to server/.env.local and fill it in.'
      : 'Fix: set them in the Vercel project, under Settings, Environment Variables, then redeploy.';
  return [
    `Glow server can't start: ${count} fixing (profile: ${profile}).`,
    '',
    ...lines,
    '',
    fix,
    'Every variable is described in server/.env.example.',
  ].join('\n');
}

export class EnvError extends Error {
  readonly profile: EnvProfile;
  readonly problems: readonly EnvProblem[];

  constructor(profile: EnvProfile, problems: readonly EnvProblem[]) {
    super(formatEnvProblems(profile, problems));
    this.name = 'EnvError';
    this.profile = profile;
    this.problems = problems;
  }
}

let cached: Env | undefined;

/** The validated env for this process. Throws EnvError with a readable message if invalid. */
export function getEnv(): Env {
  if (cached) return cached;
  const result = parseEnv(process.env);
  if (!result.ok) throw new EnvError(result.profile, result.problems);
  cached = result.env;
  return cached;
}

/** For tests only: forget the cached env so the next getEnv() reads process.env again. */
export function resetEnvCacheForTests(): void {
  cached = undefined;
}
