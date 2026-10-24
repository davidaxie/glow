/**
 * Owner: C3. A real local Supabase for the glow integration tests.
 *
 * These call the real route handlers with real access tokens, so every request goes through A1's
 * sign-in check (Supabase Auth), the contract validation, PostgREST and the database functions
 * (`start_glow`, `glow_met`, `cancel_glow`, `get_match`). Only B5's notify is replaced, by a spy,
 * so tests can see who would have been told what.
 *
 * They run when GLOW_INTEGRATION=1 or CI is set, against:
 *   - GLOW_IT_SUPABASE_URL, GLOW_IT_SUPABASE_ANON_KEY, GLOW_IT_SUPABASE_SERVICE_ROLE_KEY, or
 *   - server/.env.local (what `pnpm env:setup` writes; CI writes it after `supabase start`).
 * They refuse anything but a local Supabase, because they create and delete people.
 *
 *   eval "$(scripts/agent-env.sh C3 --own-db)"
 *   GLOW_INTEGRATION=1 GLOW_IT_SUPABASE_URL=$SUPABASE_URL \
 *     GLOW_IT_SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY \
 *     GLOW_IT_SUPABASE_SERVICE_ROLE_KEY=$SUPABASE_SERVICE_ROLE_KEY \
 *     pnpm --filter server exec vitest run tests/glow
 *
 * Everything a test makes is named `c3it-…` and removed in `cleanup()`, so a shared database is
 * left as it was.
 */
import { randomBytes, randomUUID } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { NextRequest } from 'next/server';
import type { Database } from '@/contracts';
import { resetEnvCacheForTests } from '@/env';
import { LOCAL_ENV } from '../helpers/env';

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
    throw new Error('Integration tests need a local Supabase: run `pnpm env:setup` (harness.ts).');
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
  resetEnvCacheForTests();
}

export type Person = { readonly id: string; readonly token: string };

type Handler = (
  req: NextRequest,
  ctx: { params: Promise<Record<string, string>> },
) => Promise<Response>;

/** One test file's people and rooms. Everything is deleted by `cleanup()`. */
export class World {
  readonly admin: SupabaseClient<Database>;
  private readonly anon: SupabaseClient<Database>;
  private readonly people: string[] = [];
  private readonly rooms: string[] = [];
  private readonly tag = randomBytes(4).toString('hex');
  private made = 0;

  constructor(config: ItConfig) {
    const options = { auth: { persistSession: false, autoRefreshToken: false } };
    this.admin = createClient<Database>(config.url, config.serviceKey, options);
    this.anon = createClient<Database>(config.url, config.anonKey, options);
  }

  /** Someone who finished onboarding, with a real access token from Supabase Auth. */
  async person(): Promise<Person> {
    const n = ++this.made;
    const email = `c3it-${this.tag}-${n}@glow.test`;
    const password = randomBytes(18).toString('base64url');
    const created = await this.admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
    });
    if (created.error || !created.data.user) {
      throw new Error(`createUser: ${created.error?.message}`);
    }
    const id = created.data.user.id;
    this.people.push(id);
    const profile = await this.admin
      .from('profiles')
      .update({
        first_name: `Glow${n}`,
        birthdate: '1995-06-06',
        gender: n % 2 ? 'woman' : 'man',
        show_me: ['woman', 'man', 'nonbinary'],
        onboarding_step: 'complete',
      })
      .eq('id', id);
    if (profile.error) throw new Error(`profile: ${profile.error.message}`);
    const session = await this.anon.auth.signInWithPassword({ email, password });
    if (session.error || !session.data.session) {
      throw new Error(`sign-in: ${session.error?.message}`);
    }
    return { id, token: session.data.session.access_token };
  }

  /** A live room with three meeting spots. */
  async room(): Promise<string> {
    const n = ++this.made;
    const { data, error } = await this.admin
      .from('rooms')
      .insert({
        slug: `c3it-${this.tag}-r${n}`,
        name: `C3 test room ${n}`,
        lat: 37.8,
        lng: -122.45,
        starts_at: new Date(Date.now() - 3_600_000).toISOString(),
        ends_at: new Date(Date.now() + 2 * 86_400_000).toISOString(),
      })
      .select('id')
      .single();
    if (error || !data) throw new Error(`room: ${error?.message}`);
    this.rooms.push(data.id);
    const spots = await this.admin.from('meeting_spots').insert(
      ['Main entrance', 'Food line', 'Water station'].map((name, sort) => ({
        room_id: data.id,
        name,
        sort,
      })),
    );
    if (spots.error) throw new Error(`spots: ${spots.error.message}`);
    return data.id;
  }

  /** A passed location check, the only kind of record P2 allows: pass or fail, no coordinates. */
  async passCheck(person: Person, roomId: string, purpose: 'join' | 'find'): Promise<void> {
    const { error } = await this.admin.from('location_checks').insert({
      user_id: person.id,
      room_id: roomId,
      purpose,
      result: 'pass',
      accuracy_bucket: 'under_20m',
    });
    if (error) throw new Error(`location check: ${error.message}`);
  }

  /** Checked in, as B2 and B3 do it (no photo is uploaded; glow never reads storage). */
  async checkIn(person: Person, roomId: string): Promise<void> {
    await this.passCheck(person, roomId, 'join');
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

  /**
   * Two checked-in people with a match where both chose Find a moment ago, each with a fresh
   * location check: exactly the state set_choice leaves when it answers next: glow.
   */
  async readyToGlow(roomId: string): Promise<{ matchId: string; a: Person; b: Person }> {
    const [one, two] = await Promise.all([this.person(), this.person()]);
    const [a, b] = one.id < two.id ? [one, two] : [two, one];
    await Promise.all([this.checkIn(a, roomId), this.checkIn(b, roomId)]);
    await Promise.all([this.passCheck(a, roomId, 'find'), this.passCheck(b, roomId, 'find')]);
    const { data, error } = await this.admin
      .from('matches')
      .insert({
        room_id: roomId,
        user_a: a.id,
        user_b: b.id,
        a_choice: 'find',
        b_choice: 'find',
        choice_deadline: new Date(Date.now() + 600_000).toISOString(),
      })
      .select('id')
      .single();
    if (error || !data) throw new Error(`match: ${error?.message}`);
    return { matchId: data.id, a, b };
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

  private async call(
    load: Promise<Record<string, unknown>>,
    method: 'GET' | 'POST',
    path: string,
    person: Person,
    matchId: string,
    body?: unknown,
  ): Promise<Response> {
    const handler = (await load)[method] as Handler;
    return handler(World.request(path, person.token, method, body), {
      params: Promise.resolve({ id: matchId }),
    });
  }

  /** GET /api/matches/{id}/glow through the real route. */
  glow(person: Person, matchId: string) {
    const path = `/api/matches/${matchId}/glow`;
    return this.call(import('../../app/api/matches/[id]/glow/route'), 'GET', path, person, matchId);
  }

  /** POST /api/matches/{id}/glow/met through the real route. */
  met(person: Person, matchId: string) {
    const path = `/api/matches/${matchId}/glow/met`;
    const load = import('../../app/api/matches/[id]/glow/met/route');
    return this.call(load, 'POST', path, person, matchId);
  }

  /** POST /api/matches/{id}/glow/cancel through the real route. */
  cancel(person: Person, matchId: string, reason?: 'cancel' | 'switch_to_chat') {
    const path = `/api/matches/${matchId}/glow/cancel`;
    const load = import('../../app/api/matches/[id]/glow/cancel/route');
    return this.call(load, 'POST', path, person, matchId, reason ? { reason } : undefined);
  }

  async matchStatus(matchId: string): Promise<string | undefined> {
    const { data } = await this.admin.from('matches').select('status').eq('id', matchId).single();
    return data?.status;
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
