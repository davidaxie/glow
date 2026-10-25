// Owner: D1. A small client for the Glow API, for the end-to-end scripts in scripts/e2e/.
//
// Plain Node (24+, which runs TypeScript by stripping types): no dependencies beyond the repo's
// generated contract types. Talks to the local server and the local Supabase only, and refuses
// anything else, because it creates test people and reads keys from server/.env.local.
//
// Every step goes through the API, test sign-in and onboarding included (B1's routes). The
// service role key is only used to end a check-in early for the expiry journey (harness.ts).

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import type {
  AdminRoom,
  ChoiceResult,
  Deck,
  Glow,
  JoinTicket,
  LocationFix,
  MatchDetail,
  MatchList,
  Message,
  MessagePage,
  MyCheckin,
  RoomState,
  RoomSummary,
  TapResult,
  TestSession,
} from '../../server/src/contracts/openapi/types.gen.ts';

export type {
  AdminRoom,
  ChoiceResult,
  Deck,
  Glow,
  MatchDetail,
  Message,
  MyCheckin,
  RoomState,
  TapResult,
};

export const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');

/** The seeded demo room (A2's supabase/seed.sql, copied in ios/fixtures/demo-room.env). */
export const DEMO_ROOM = {
  id: 'de000000-0000-4000-8000-000000000001',
  slug: 'demo',
  token: 'DEMOSTATICTOKEN2',
  code: 'HACK26',
  latitude: 37.8029,
  longitude: -122.4484,
} as const;

export const DEFAULT_PHOTO = join(ROOT, 'ios/fixtures/photos/outfit-real-blue-flightsuit.jpg');

/** A profile photo: B1's route wants a 4:5 crop (cut from the outfit-real fixtures). */
export const DEFAULT_PROFILE_PHOTO = join(ROOT, 'scripts/e2e/fixtures/profile-b.jpg');

// ---------------------------------------------------------------------------------- environment

export type Env = {
  api: string;
  supabaseUrl?: string;
  anonKey?: string;
  serviceKey?: string;
  cronSecret?: string;
};

function readEnvFile(): Record<string, string> {
  const values: Record<string, string> = {};
  let text = '';
  try {
    text = readFileSync(join(ROOT, 'server/.env.local'), 'utf8');
  } catch {
    return values;
  }
  for (const line of text.split('\n')) {
    const match = /^([A-Z0-9_]+)=(.*)$/.exec(line.trim());
    if (match?.[1] && match[2] !== undefined) values[match[1]] = match[2].replace(/^"|"$/g, '');
  }
  return values;
}

const LOCAL = /^http:\/\/(localhost|127\.0\.0\.1|\[::1\])(:\d+)?(\/|$)/;

export function isLocalUrl(url: string): boolean {
  return LOCAL.test(url);
}

/** The API and local Supabase this run talks to: the environment first, then server/.env.local. */
export function loadEnv(api?: string): Env {
  const file = readEnvFile();
  const pick = (name: string) => process.env[name] || file[name] || undefined;
  const env: Env = {
    api: (api ?? process.env.GLOW_API ?? 'http://localhost:3000').replace(/\/$/, ''),
    supabaseUrl: pick('SUPABASE_URL'),
    anonKey: pick('SUPABASE_ANON_KEY'),
    serviceKey: pick('SUPABASE_SERVICE_ROLE_KEY'),
    cronSecret: pick('CRON_SECRET'),
  };
  if (!isLocalUrl(env.api))
    throw new Error(`refusing to play against ${env.api}: local servers only`);
  if (env.supabaseUrl && !isLocalUrl(env.supabaseUrl)) {
    throw new Error(`refusing to use Supabase at ${env.supabaseUrl}: local Supabase only`);
  }
  return env;
}

// ---------------------------------------------------------------------------------- errors

export class ApiError extends Error {
  readonly status: number;
  readonly code: string | undefined;
  readonly reason: string | undefined;
  readonly operation: string;

  constructor(operation: string, status: number, code?: string, reason?: string) {
    super(
      `${operation} answered ${status}${code ? ` ${code}` : ''}${reason ? ` (${reason})` : ''}`,
    );
    this.status = status;
    this.code = code;
    this.reason = reason;
    this.operation = operation;
  }

  /** The owner's route isn't built yet. */
  get isStub(): boolean {
    return this.status === 501;
  }
}

export function note(message: string): void {
  process.stderr.write(`e2e: ${message}\n`);
}

// ---------------------------------------------------------------------------------- privacy watch

/** Operations that only ever answer about a mutual match, where the other first name belongs. */
const MATCH_OPERATIONS = new Set([
  'listMatches',
  'getMatch',
  'setChoice',
  'getGlow',
  'markGlowMet',
  'cancelGlow',
  'listMessages',
  'sendMessage',
]);

/**
 * Strings that must never reach this person (P1): the other person's user ID anywhere, ever, and
 * their first name anywhere but the match routes. Every reply is checked before it's used.
 */
export class PrivacyWatch {
  private readonly ids: string[] = [];
  private readonly names: string[] = [];
  readonly violations: string[] = [];

  watchUserId(id: string): void {
    this.ids.push(id.toLowerCase());
  }

  watchName(name: string): void {
    if (name.trim().length >= 3) this.names.push(name.toLowerCase());
  }

  check(operation: string, text: string): void {
    const lower = text.toLowerCase();
    for (const id of this.ids) {
      if (lower.includes(id)) this.violations.push(`${operation}: the other person's user ID`);
    }
    if (MATCH_OPERATIONS.has(operation)) return;
    for (const name of this.names) {
      if (new RegExp(`\\b${escapeRegExp(name)}\\b`).test(lower)) {
        this.violations.push(`${operation}: the other person's first name outside a match`);
      }
    }
  }
}

function escapeRegExp(text: string): string {
  return text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

// ---------------------------------------------------------------------------------- the client

type Method = 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE';

export type Session = { accessToken: string; userId: string; email: string };

/** One signed-in person. */
export class Person {
  readonly env: Env;
  readonly session: Session;
  readonly watch: PrivacyWatch;

  constructor(env: Env, session: Session, watch = new PrivacyWatch()) {
    this.env = env;
    this.session = session;
    this.watch = watch;
  }

  get userId(): string {
    return this.session.userId;
  }

  async call<T>(operation: string, method: Method, path: string, body?: unknown): Promise<T> {
    const res = await fetch(`${this.env.api}${path}`, {
      method,
      headers: {
        authorization: `Bearer ${this.session.accessToken}`,
        ...(body === undefined ? {} : { 'content-type': 'application/json' }),
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const text = await res.text();
    this.watch.check(operation, text);
    if (!res.ok) {
      let code: string | undefined;
      let reason: string | undefined;
      try {
        const parsed = JSON.parse(text) as { error?: { code?: string; reason?: string } };
        code = parsed.error?.code;
        reason = parsed.error?.reason;
      } catch {
        // not JSON
      }
      throw new ApiError(operation, res.status, code, reason);
    }
    return (text ? JSON.parse(text) : undefined) as T;
  }

  /** Fetches a signed image link with this person's token. Returns its size in bytes. */
  async fetchImage(url: string): Promise<number> {
    const res = await fetch(`${this.env.api}${url}`, {
      headers: { authorization: `Bearer ${this.session.accessToken}` },
    });
    if (!res.ok) throw new ApiError('getCardImage', res.status);
    return (await res.arrayBuffer()).byteLength;
  }

  // ---- rooms (B2), check-in (B3)

  resolveLink(slug: string, token: string): Promise<RoomSummary> {
    return this.call('resolveRoom', 'POST', '/api/rooms/resolve', { kind: 'link', slug, token });
  }

  join(roomId: string, slug: string, token: string, location: LocationFix): Promise<JoinTicket> {
    return this.call('joinRoom', 'POST', `/api/rooms/${roomId}/join`, {
      access: { kind: 'link', slug, token },
      location,
    });
  }

  checkIn(
    roomId: string,
    ticket: string,
    jpeg: Buffer,
    tags: MyCheckin['tags'],
  ): Promise<MyCheckin> {
    return this.call('createCheckin', 'POST', `/api/rooms/${roomId}/checkin`, {
      ticket,
      photo: jpeg.toString('base64'),
      tags,
    });
  }

  roomState(roomId: string): Promise<RoomState> {
    return this.call('getRoomState', 'GET', `/api/rooms/${roomId}`);
  }

  leave(roomId: string): Promise<void> {
    return this.call('leaveRoom', 'POST', `/api/rooms/${roomId}/leave`);
  }

  // ---- deck and taps (B4)

  deck(roomId: string, offset = 0): Promise<Deck> {
    return this.call('getDeck', 'POST', `/api/rooms/${roomId}/deck`, { filters: {}, offset });
  }

  tap(roomId: string, cardId: string): Promise<TapResult> {
    return this.call('createTap', 'POST', `/api/rooms/${roomId}/taps`, { cardId });
  }

  matches(): Promise<MatchList> {
    return this.call('listMatches', 'GET', '/api/matches');
  }

  // ---- match, choice (C2), glow (C3), chat (C4), safety (B8)

  match(matchId: string): Promise<MatchDetail> {
    return this.call('getMatch', 'GET', `/api/matches/${matchId}`);
  }

  choose(matchId: string, choice: 'find' | 'chat', location?: LocationFix): Promise<ChoiceResult> {
    return this.call('setChoice', 'POST', `/api/matches/${matchId}/choice`, {
      choice,
      ...(choice === 'find' ? { location } : {}),
    });
  }

  glow(matchId: string): Promise<Glow> {
    return this.call('getGlow', 'GET', `/api/matches/${matchId}/glow`);
  }

  met(matchId: string): Promise<Glow> {
    return this.call('markGlowMet', 'POST', `/api/matches/${matchId}/glow/met`);
  }

  cancelGlow(matchId: string, reason: 'cancel' | 'switch_to_chat'): Promise<Glow> {
    return this.call('cancelGlow', 'POST', `/api/matches/${matchId}/glow/cancel`, { reason });
  }

  messages(matchId: string): Promise<MessagePage> {
    return this.call('listMessages', 'GET', `/api/matches/${matchId}/messages`);
  }

  send(matchId: string, body: string): Promise<Message> {
    return this.call('sendMessage', 'POST', `/api/matches/${matchId}/messages`, {
      body,
      clientId: crypto.randomUUID(),
    });
  }

  unmatch(matchId: string): Promise<void> {
    return this.call('unmatch', 'POST', `/api/matches/${matchId}/unmatch`);
  }

  block(context: 'card' | 'match' | 'chat', contextId: string): Promise<void> {
    return this.call('createBlock', 'POST', '/api/blocks', { context, contextId });
  }

  // ---- admin (B7), for setting up a room of the run's own

  createRoom(input: Record<string, unknown>): Promise<AdminRoom> {
    return this.call('adminCreateRoom', 'POST', '/api/admin/rooms', input);
  }

  updateRoom(roomId: string, input: Record<string, unknown>): Promise<AdminRoom> {
    return this.call('adminUpdateRoom', 'PATCH', `/api/admin/rooms/${roomId}`, input);
  }
}

// ---------------------------------------------------------------------------------- sign-in

/** A fresh test address, unique to this run: `{prefix}-{random}@glow.test`. */
export function freshEmail(prefix: string): string {
  const suffix = crypto.randomUUID().slice(0, 8);
  return `${prefix.toLowerCase().replace(/[^a-z0-9.+-]/g, '')}-${suffix}@glow.test`;
}

/** A made-up private IPv4 address, new each call. */
function fakeClientAddress(): string {
  const [a = 0, b = 0, c = 0] = crypto.getRandomValues(new Uint8Array(3));
  return `10.${a}.${b}.${Math.max(1, c)}`;
}

/** Signs in with B1's test sign-in: `POST /api/dev/test-login` (local servers with ALLOW_TEST_LOGIN). */
export async function signIn(env: Env, email: string): Promise<Session> {
  if (!email.endsWith('@glow.test'))
    throw new Error('test sign-in takes @glow.test addresses only');
  const res = await fetch(`${env.api}/api/dev/test-login`, {
    method: 'POST',
    // Test sign-in is limited to 10 per 10 minutes per client IP (B8's `signIn` policy), and a
    // ten-run check signs in far more often than that. Each sign-in names its own made-up client
    // address, the way a proxy would (D1-D7). On Vercel the header is overwritten, and this route
    // doesn't exist there.
    headers: { 'content-type': 'application/json', 'x-forwarded-for': fakeClientAddress() },
    body: JSON.stringify({ email }),
  });
  if (!res.ok) {
    throw new ApiError(
      'testLogin',
      res.status,
      undefined,
      'is ALLOW_TEST_LOGIN on? pnpm env:setup --force --test-login, then restart the server',
    );
  }
  const session = (await res.json()) as TestSession;
  return { accessToken: session.accessToken, userId: session.userId, email };
}

function requireSupabase(env: Env): Required<Pick<Env, 'supabaseUrl' | 'anonKey' | 'serviceKey'>> {
  const { supabaseUrl, anonKey, serviceKey } = env;
  if (!supabaseUrl || !anonKey || !serviceKey) {
    throw new Error(
      'need SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY (pnpm env:setup)',
    );
  }
  return { supabaseUrl, anonKey, serviceKey };
}

/** Service-role PostgREST call on the local Supabase, for test setup and expiry only. */
export async function serviceRest(
  env: Env,
  method: 'GET' | 'PATCH' | 'POST',
  path: string,
  body?: unknown,
): Promise<unknown> {
  const { supabaseUrl, serviceKey } = requireSupabase(env);
  const res = await fetch(`${supabaseUrl}/rest/v1/${path}`, {
    method,
    headers: {
      apikey: serviceKey,
      authorization: `Bearer ${serviceKey}`,
      'content-type': 'application/json',
      prefer: 'return=representation',
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`service ${method} ${path.split('?')[0]} answered ${res.status}`);
  return text ? JSON.parse(text) : undefined;
}

// ---------------------------------------------------------------------------------- onboarding

export type ProfileInput = {
  firstName: string;
  gender: 'woman' | 'man' | 'nonbinary';
  showMe: Array<'woman' | 'man' | 'nonbinary'>;
  birthdate?: string;
  /** A 4:5 JPEG for the profile (default scripts/e2e/fixtures/profile-b.jpg). */
  profilePhoto?: string;
};

/**
 * Signs in a test person and finishes their onboarding through B1's routes: profile, one
 * profile photo, complete.
 */
export async function onboardedPerson(
  env: Env,
  email: string,
  input: ProfileInput,
): Promise<Person> {
  const person = new Person(env, await signIn(env, email));
  const profile = {
    firstName: input.firstName,
    birthdate: input.birthdate ?? '1996-05-14',
    gender: input.gender,
    showMe: input.showMe,
  };
  await person.call('updateProfile', 'PUT', '/api/me/profile', profile);
  const photo = readFileSync(input.profilePhoto ?? DEFAULT_PROFILE_PHOTO).toString('base64');
  await person.call('addProfilePhoto', 'POST', '/api/me/photos', { position: 0, photo });
  await person.call('completeOnboarding', 'POST', '/api/me/onboarding/complete');
  return person;
}

// ---------------------------------------------------------------------------------- helpers

export function venueFix(latitude: number, longitude: number): LocationFix {
  return { latitude, longitude, accuracy: 10 };
}

export const sleep = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms));

/** Calls `probe` every `everyMs` until it returns a value, or throws after `timeoutMs`. */
export async function waitFor<T>(
  what: string,
  probe: () => Promise<T | undefined>,
  timeoutMs: number,
  everyMs = 500,
): Promise<T> {
  const deadline = Date.now() + timeoutMs;
  for (;;) {
    const value = await probe();
    if (value !== undefined) return value;
    if (Date.now() > deadline)
      throw new Error(`timed out after ${Math.round(timeoutMs / 1000)} s waiting for ${what}`);
    await sleep(everyMs);
  }
}
