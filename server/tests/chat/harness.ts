/**
 * Owner: C4. A real local Supabase for the chat integration tests.
 *
 * These call the real route handlers with real access tokens, so every request goes through
 * A1's sign-in check (Supabase Auth), the contract validation, PostgREST and the database
 * functions (`get_match`, `send_message`, `unmatch`, `block_user`). Moderation is B8's real
 * module, which runs its deterministic fake without ANTHROPIC_API_KEY. Only `notify` is
 * replaced, by a spy, so tests can see who would have been told what.
 *
 * They run when GLOW_INTEGRATION=1 or CI is set, against:
 *   - GLOW_IT_SUPABASE_URL, GLOW_IT_SUPABASE_ANON_KEY, GLOW_IT_SUPABASE_SERVICE_ROLE_KEY, or
 *   - server/.env.local (what `pnpm env:setup` writes; CI writes it after `supabase start`).
 * They refuse anything but a local Supabase, because they create and delete people.
 *
 *   GLOW_INTEGRATION=1 pnpm --filter server exec vitest run tests/chat
 *
 * Everything a test makes is named `c4it-…` and removed in `cleanup()`.
 */
import { randomBytes, randomUUID } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { NextRequest } from 'next/server';
import type { Database } from '@/contracts';
import { resetEnvCacheForTests } from '@/env';
import { LOCAL_ENV } from '../helpers/env';

type MatchStatus = Database['public']['Enums']['match_status'];

export type ItConfig = {
  readonly url: string;
  readonly anonKey: string;
  readonly serviceKey: string;
};

function readEnvFile(): Record<string, string> {
  const file = fileURLToPath(new URL('../../.env.local', import.meta.url));
  if (!existsSync(file)) return {};
  const out: Record<string, string> = {};
  for (const line of readFileSync(file, 'utf8').split('\n')) {
    const match = /^([A-Z0-9_]+)=(.*)$/.exec(line.trim());
    if (match) out[match[1]!] = match[2]!.replace(/^['"]|['"]$/g, '');
  }
  return out;
}

function isLocal(url: string): boolean {
  try {
    const host = new URL(url).hostname;
    return host === '127.0.0.1' || host === 'localhost' || host === '[::1]';
  } catch {
    return false;
  }
}

function resolveConfig(): ItConfig | null {
  const wanted = process.env.GLOW_INTEGRATION === '1' || Boolean(process.env.CI);
  if (!wanted) return null;
  const file = readEnvFile();
  const url = process.env.GLOW_IT_SUPABASE_URL ?? file.SUPABASE_URL;
  const anonKey = process.env.GLOW_IT_SUPABASE_ANON_KEY ?? file.SUPABASE_ANON_KEY;
  const serviceKey =
    process.env.GLOW_IT_SUPABASE_SERVICE_ROLE_KEY ?? file.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !anonKey || !serviceKey) {
    throw new Error('Integration tests need a local Supabase: run `pnpm env:setup`.');
  }
  if (!isLocal(url)) throw new Error('Integration tests only run against a local Supabase.');
  return { url, anonKey, serviceKey };
}

/** Null when integration tests are off. Use with `describe.runIf(IT)`. */
export const IT: ItConfig | null = resolveConfig();

/** Points getEnv() at the real local Supabase. Call in beforeEach, after tests/setup.ts. */
export function useRealSupabase(config: ItConfig): void {
  Object.assign(process.env, LOCAL_ENV);
  process.env.SUPABASE_URL = config.url;
  process.env.SUPABASE_ANON_KEY = config.anonKey;
  process.env.SUPABASE_SERVICE_ROLE_KEY = config.serviceKey;
  delete process.env.ANTHROPIC_API_KEY;
  resetEnvCacheForTests();
}

export type Person = { readonly id: string; readonly token: string };

type Handler = (
  req: NextRequest,
  ctx: { params: Promise<Record<string, string>> },
) => Promise<Response>;

type Routes = { readonly list: Handler; readonly send: Handler; readonly unmatch: Handler };

/** One test file's people, rooms and matches. Everything is deleted by `cleanup()`. */
export class World {
  readonly admin: SupabaseClient<Database>;
  private readonly anon: SupabaseClient<Database>;
  private readonly people: string[] = [];
  private readonly rooms: string[] = [];
  private readonly tag = randomBytes(4).toString('hex');
  private made = 0;
  private routes: Routes | undefined;

  constructor(config: ItConfig) {
    const options = { auth: { persistSession: false, autoRefreshToken: false } };
    this.admin = createClient<Database>(config.url, config.serviceKey, options);
    this.anon = createClient<Database>(config.url, config.anonKey, options);
  }

  /** A person who finished onboarding, with a real access token from Supabase Auth. */
  async person(firstName = 'Test'): Promise<Person> {
    const n = ++this.made;
    const email = `c4it-${this.tag}-${n}@glow.test`;
    const password = randomBytes(18).toString('base64url');
    const created = await this.admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
    });
    if (created.error || !created.data.user)
      throw new Error(`createUser: ${created.error?.message}`);
    const id = created.data.user.id;
    this.people.push(id);
    const profile = await this.admin
      .from('profiles')
      .update({
        first_name: `${firstName}${n}`,
        birthdate: '1996-05-05',
        gender: 'nonbinary',
        show_me: ['woman', 'man', 'nonbinary'],
        onboarding_step: 'complete',
      })
      .eq('id', id);
    if (profile.error) throw new Error(`profile: ${profile.error.message}`);
    const session = await this.anon.auth.signInWithPassword({ email, password });
    if (session.error || !session.data.session)
      throw new Error(`sign-in: ${session.error?.message}`);
    return { id, token: session.data.session.access_token };
  }

  async room(): Promise<string> {
    const n = ++this.made;
    const { data, error } = await this.admin
      .from('rooms')
      .insert({
        slug: `c4it-${this.tag}-r${n}`,
        name: `C4 test room ${n}`,
        lat: 37.8,
        lng: -122.45,
        starts_at: new Date(Date.now() - 3_600_000).toISOString(),
        ends_at: new Date(Date.now() + 2 * 86_400_000).toISOString(),
      })
      .select('id')
      .single();
    if (error || !data) throw new Error(`room: ${error?.message}`);
    this.rooms.push(data.id);
    return data.id;
  }

  /**
   * A match between two people, written straight to the table (B4's taps make real ones;
   * chat only cares about the match row). `chatting` by default, so the thread is open.
   */
  async match(
    roomId: string,
    one: Person,
    two: Person,
    status: MatchStatus = 'chatting',
    choiceDeadline = new Date(Date.now() - 60_000),
  ): Promise<string> {
    const [a, b] = one.id < two.id ? [one, two] : [two, one];
    const { data, error } = await this.admin
      .from('matches')
      .insert({
        room_id: roomId,
        user_a: a.id,
        user_b: b.id,
        status,
        choice_deadline: choiceDeadline.toISOString(),
      })
      .select('id')
      .single();
    if (error || !data) throw new Error(`match: ${error?.message}`);
    return data.id;
  }

  /**
   * Checks someone in the way B2 and B3 do: a passed join location check (pass or fail only,
   * never coordinates), then `create_checkin`. No photo is uploaded; chat never reads it.
   */
  async checkIn(person: Person, roomId: string): Promise<void> {
    const check = await this.admin.from('location_checks').insert({
      user_id: person.id,
      room_id: roomId,
      purpose: 'join',
      result: 'pass',
      accuracy_bucket: 'under_20m',
    });
    if (check.error) throw new Error(`location check: ${check.error.message}`);
    const cardId = randomUUID();
    const { error } = await this.admin.rpc('create_checkin', {
      p_user_id: person.id,
      p_room_id: roomId,
      p_checkin_id: cardId,
      p_card_path: `${roomId}/${cardId}.jpg`,
      p_tags: { topColor: 'blue', extras: [] },
    });
    if (error) throw new Error(`create_checkin: ${error.message}`);
  }

  private async loadRoutes(): Promise<Routes> {
    if (this.routes) return this.routes;
    const messages = await import('../../app/api/matches/[id]/messages/route');
    const unmatch = await import('../../app/api/matches/[id]/unmatch/route');
    this.routes = { list: messages.GET, send: messages.POST, unmatch: unmatch.POST };
    return this.routes;
  }

  private static request(path: string, token: string | null, method: string, body?: unknown) {
    return new NextRequest(`http://localhost${path}`, {
      method,
      headers: {
        ...(token ? { authorization: `Bearer ${token}` } : {}),
        ...(body !== undefined ? { 'content-type': 'application/json' } : {}),
      },
      ...(body !== undefined ? { body: JSON.stringify(body) } : {}),
    });
  }

  /** GET /api/matches/{id}/messages through the real route. */
  async list(
    person: Person | null,
    matchId: string,
    query: Record<string, string> = {},
  ): Promise<Response> {
    const { list } = await this.loadRoutes();
    const search = new URLSearchParams(query).toString();
    const path = `/api/matches/${matchId}/messages${search ? `?${search}` : ''}`;
    return list(World.request(path, person?.token ?? null, 'GET'), {
      params: Promise.resolve({ id: matchId }),
    });
  }

  /** POST /api/matches/{id}/messages through the real route. */
  async send(person: Person | null, matchId: string, body: unknown): Promise<Response> {
    const { send } = await this.loadRoutes();
    return send(
      World.request(`/api/matches/${matchId}/messages`, person?.token ?? null, 'POST', body),
      { params: Promise.resolve({ id: matchId }) },
    );
  }

  /** POST /api/matches/{id}/unmatch through the real route. */
  async unmatch(person: Person | null, matchId: string): Promise<Response> {
    const { unmatch } = await this.loadRoutes();
    return unmatch(
      World.request(`/api/matches/${matchId}/unmatch`, person?.token ?? null, 'POST'),
      { params: Promise.resolve({ id: matchId }) },
    );
  }

  /** The thread's rows, read as the service role. */
  async rows(matchId: string) {
    const { data, error } = await this.admin
      .from('messages')
      .select('id, sender_id, body, moderation, client_id, created_at')
      .eq('match_id', matchId)
      .order('created_at', { ascending: true });
    if (error) throw new Error(`rows: ${error.message}`);
    return data ?? [];
  }

  /** Deletes every room and person this world made (rooms first: their rows cascade). */
  async cleanup(): Promise<void> {
    if (this.rooms.length > 0) await this.admin.from('rooms').delete().in('id', this.rooms);
    await Promise.all(this.people.map((id) => this.admin.auth.admin.deleteUser(id)));
  }
}
