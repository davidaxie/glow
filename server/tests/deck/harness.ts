/**
 * Owner: B4. A real local Supabase for the deck, taps and matches integration tests.
 *
 * These tests call the real route handlers with real access tokens, so every request goes
 * through A1's sign-in check (Supabase Auth), the contract validation, PostgREST and the
 * database functions. Only B5's notify is replaced, by a spy, so tests can see who would
 * have been told what.
 *
 * They run when GLOW_INTEGRATION=1 or CI is set, against:
 *   - GLOW_IT_SUPABASE_URL, GLOW_IT_SUPABASE_ANON_KEY, GLOW_IT_SUPABASE_SERVICE_ROLE_KEY, or
 *   - server/.env.local (what `pnpm env:setup` writes; CI writes it after `supabase start`).
 * They refuse anything but a local Supabase, because they create and delete people.
 *
 *   GLOW_INTEGRATION=1 pnpm --filter server exec vitest run tests/deck tests/taps tests/matches
 *
 * Everything a test makes is named `b4it-…` and removed in `cleanup()`, so the shared CI
 * database is left as it was for pgTAP.
 */
import { randomBytes, randomUUID } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { NextRequest } from 'next/server';
import type { CardTags, Database, DeckRequest } from '@/contracts';
import { resetEnvCacheForTests } from '@/env';
import { setRateLimitStoreForTests } from '@/server/ratelimit';
import { LOCAL_ENV } from '../helpers/env';

type Gender = Database['public']['Enums']['gender'];

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
    throw new Error(
      'Integration tests need a local Supabase: run `pnpm env:setup` (see harness.ts).',
    );
  }
  if (!isLocal(url)) throw new Error('Integration tests only run against a local Supabase.');
  return { url, anonKey, serviceKey };
}

/** Null when integration tests are off. Use with `describe.runIf(IT)`. */
export const IT: ItConfig | null = resolveConfig();

/** Points getEnv() at the real local Supabase. Call in beforeEach, after tests/setup.ts. */
export function useRealSupabase(config: ItConfig): void {
  // The signing secrets stay the test values from tests/helpers/env.ts (also in beforeAll,
  // which runs before tests/setup.ts sets them).
  Object.assign(process.env, LOCAL_ENV);
  process.env.SUPABASE_URL = config.url;
  process.env.SUPABASE_ANON_KEY = config.anonKey;
  process.env.SUPABASE_SERVICE_ROLE_KEY = config.serviceKey;
  resetEnvCacheForTests();
  // B8's burst limits are B8's tests; these tests make far more requests per person than any
  // phone would. route() still counts every request; this store just never says no.
  setRateLimitStoreForTests({
    name: 'test',
    hit: async () => ({ allowed: true, remaining: Number.MAX_SAFE_INTEGER, resetAt: 0 }),
  });
}

export type Person = {
  readonly id: string;
  readonly token: string;
  readonly firstName: string;
  readonly gender: Gender;
};

export type PersonSpec = {
  readonly gender: Gender;
  readonly showMe: readonly Gender[];
  readonly firstName?: string;
};

type Handler = (
  req: NextRequest,
  ctx: { params: Promise<Record<string, string>> },
) => Promise<Response>;

type Routes = { readonly deck: Handler; readonly taps: Handler; readonly matches: Handler };

/** One test file's people and rooms. Everything is deleted by `cleanup()`. */
export class World {
  readonly admin: SupabaseClient<Database>;
  private readonly anon: SupabaseClient<Database>;
  private readonly people: string[] = [];
  private readonly rooms: string[] = [];
  private readonly tag = randomBytes(4).toString('hex');
  private made = 0;
  private routes: Routes | undefined;

  constructor(private readonly config: ItConfig) {
    const options = { auth: { persistSession: false, autoRefreshToken: false } };
    this.admin = createClient<Database>(config.url, config.serviceKey, options);
    this.anon = createClient<Database>(config.url, config.anonKey, options);
  }

  /** A person who finished onboarding, with a real access token from Supabase Auth. */
  async person(spec: PersonSpec): Promise<Person> {
    const n = ++this.made;
    const email = `b4it-${this.tag}-${n}@glow.test`;
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
    const firstName = spec.firstName ?? `Test${n}`;
    const profile = await this.admin
      .from('profiles')
      .update({
        first_name: firstName,
        birthdate: '1996-05-05',
        gender: spec.gender,
        show_me: [...spec.showMe],
        onboarding_step: 'complete',
      })
      .eq('id', id);
    if (profile.error) throw new Error(`profile: ${profile.error.message}`);
    const session = await this.anon.auth.signInWithPassword({ email, password });
    if (session.error || !session.data.session)
      throw new Error(`sign-in: ${session.error?.message}`);
    return { id, token: session.data.session.access_token, firstName, gender: spec.gender };
  }

  async crowd(count: number, spec: PersonSpec): Promise<Person[]> {
    const out: Person[] = [];
    // A few at a time: fast, without flooding Supabase Auth.
    for (let i = 0; i < count; i += 10) {
      const batch = await Promise.all(
        Array.from({ length: Math.min(10, count - i) }, () => this.person(spec)),
      );
      out.push(...batch);
    }
    return out;
  }

  /** A live room with three meeting spots. */
  async room(
    overrides: Partial<Database['public']['Tables']['rooms']['Insert']> = {},
  ): Promise<string> {
    const n = ++this.made;
    const slug = `b4it-${this.tag}-r${n}`;
    const { data, error } = await this.admin
      .from('rooms')
      .insert({
        slug,
        name: `B4 test room ${n}`,
        lat: 37.8,
        lng: -122.45,
        starts_at: new Date(Date.now() - 3_600_000).toISOString(),
        ends_at: new Date(Date.now() + 2 * 86_400_000).toISOString(),
        ...overrides,
      })
      .select('id')
      .single();
    if (error || !data) throw new Error(`room: ${error?.message}`);
    this.rooms.push(data.id);
    const spots = await this.admin
      .from('meeting_spots')
      .insert(
        ['Spot A', 'Spot B', 'Spot C'].map((name, sort) => ({ room_id: data.id, name, sort })),
      );
    if (spots.error) throw new Error(`spots: ${spots.error.message}`);
    return data.id;
  }

  /**
   * Checks someone in the way B2 and B3 will: a passed join location check (pass or fail
   * only, never coordinates), then `create_checkin`. No photo is uploaded; the deck never
   * reads storage. Returns the card ID.
   */
  async checkIn(person: Person, roomId: string, tags: Partial<CardTags> = {}): Promise<string> {
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
      p_tags: { topColor: 'blue', extras: [], ...tags },
    });
    if (error) throw new Error(`create_checkin: ${error.message}`);
    return cardId;
  }

  async update<T extends keyof Database['public']['Tables']>(
    table: T,
    values: Database['public']['Tables'][T]['Update'],
    match: Record<string, string>,
  ): Promise<void> {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    let query: any = this.admin.from(table).update(values as never);
    for (const [column, value] of Object.entries(match)) query = query.eq(column, value);
    const { error } = await query;
    if (error) throw new Error(`update ${table}: ${error.message}`);
  }

  private async loadRoutes(): Promise<Routes> {
    if (this.routes) return this.routes;
    const deck = await import('../../app/api/rooms/[id]/deck/route');
    const taps = await import('../../app/api/rooms/[id]/taps/route');
    const matches = await import('../../app/api/matches/route');
    this.routes = { deck: deck.POST, taps: taps.POST, matches: matches.GET };
    return this.routes;
  }

  private static request(path: string, token: string, method: string, body?: unknown) {
    return new NextRequest(`http://localhost${path}`, {
      method,
      headers: {
        authorization: `Bearer ${token}`,
        ...(body !== undefined ? { 'content-type': 'application/json' } : {}),
      },
      ...(body !== undefined ? { body: JSON.stringify(body) } : {}),
    });
  }

  /** POST /api/rooms/{id}/deck through the real route. */
  async deck(person: Person, roomId: string, body: DeckRequest = {}): Promise<Response> {
    const { deck } = await this.loadRoutes();
    return World.retryUnavailable(() =>
      deck(World.request(`/api/rooms/${roomId}/deck`, person.token, 'POST', body), {
        params: Promise.resolve({ id: roomId }),
      }),
    );
  }

  /**
   * Like the app, tries a read again after a 503 (Supabase Auth or the database took too
   * long, which happens on a busy shared machine). Taps are never retried here, so the
   * simultaneous-taps test sees exactly what each first request got.
   */
  private static async retryUnavailable(call: () => Promise<Response>): Promise<Response> {
    for (let attempt = 1; ; attempt++) {
      const res = await call();
      if (res.status !== 503 || attempt === 3) return res;
      await new Promise((resolve) => setTimeout(resolve, 250 * attempt));
    }
  }

  /** POST /api/rooms/{id}/taps through the real route. */
  async tap(person: Person, roomId: string, cardId: string): Promise<Response> {
    const { taps } = await this.loadRoutes();
    return taps(World.request(`/api/rooms/${roomId}/taps`, person.token, 'POST', { cardId }), {
      params: Promise.resolve({ id: roomId }),
    });
  }

  /** GET /api/matches through the real route. */
  async matches(person: Person): Promise<Response> {
    const { matches } = await this.loadRoutes();
    return World.retryUnavailable(() =>
      matches(World.request('/api/matches', person.token, 'GET'), {
        params: Promise.resolve({}),
      }),
    );
  }

  /** Every card ID in the person's deck, page by page, as the app would scroll it. */
  async wholeDeck(person: Person, roomId: string, filters: DeckRequest['filters'] = {}) {
    const ids: string[] = [];
    let offset = 0;
    for (let page = 0; page < 20; page++) {
      const res = await this.deck(person, roomId, { filters, offset });
      if (res.status !== 200) throw new Error(`deck answered ${res.status}`);
      const body = (await res.json()) as {
        cards: { id: string }[];
        hasMore: boolean;
        nextOffset?: number;
      };
      ids.push(...body.cards.map((c) => c.id));
      if (!body.hasMore) return ids;
      offset = body.nextOffset!;
    }
    throw new Error('deck never ended');
  }

  /** Deletes every room and person this world made (rooms first: their rows cascade). */
  async cleanup(): Promise<void> {
    if (this.rooms.length > 0) await this.admin.from('rooms').delete().in('id', this.rooms);
    for (let i = 0; i < this.people.length; i += 20) {
      await Promise.all(
        this.people.slice(i, i + 20).map((id) => this.admin.auth.admin.deleteUser(id)),
      );
    }
  }
}
