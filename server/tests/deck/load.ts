/**
 * Owner: B4. Deck load test and the simultaneous-taps check, over real HTTP against a running
 * server (`next start`) and a local Supabase. Not part of `pnpm test`; run it by hand:
 *
 *   pnpm --filter server build
 *   PORT=3104 pnpm --filter server start &
 *   node server/tests/deck/load.ts                     # defaults below
 *   GLOW_API=http://localhost:3104 LOAD_PEOPLE=300 node server/tests/deck/load.ts
 *
 * Reads the Supabase URL and keys from GLOW_IT_SUPABASE_* or server/.env.local (local only).
 *
 * Scenario: one live room with LOAD_PEOPLE people checked in, who all want to see everyone,
 * so every deck has LOAD_PEOPLE - 1 eligible cards (the worst case for get_deck), plus some
 * blocks, one-sided taps and matches. Each person opens the deck and scrolls five pages (the
 * whole daily view cap). That sweep runs at several concurrency levels, and as an open-loop
 * arrival rate. It reports p50, p95 and p99 per level, and the time Supabase Auth and the
 * get_deck call take on their own at the same concurrency, so the cost can be attributed.
 *
 * Then 50 pairs in a second room tap each other at the same moment, over HTTP, and the
 * database must hold exactly 50 matches.
 *
 * Everything is named b4load-… and deleted at the end.
 */
import { randomBytes, randomUUID } from 'node:crypto';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { createClient } from '@supabase/supabase-js';

const env = (name: string, fallback: string) => process.env[name] ?? fallback;
const API = env('GLOW_API', 'http://localhost:3104');
const PEOPLE = Number(env('LOAD_PEOPLE', '300'));
const PAGES = Number(env('LOAD_PAGES', '5'));
const LEVELS = env('LOAD_CONCURRENCY', '1,10,25,50').split(',').map(Number);
const RATES = env('LOAD_RATES', '30,60,100').split(',').map(Number);
const PAIRS = Number(env('LOAD_PAIRS', '50'));
const OUT = process.env.LOAD_OUT;

function config() {
  const file = fileURLToPath(new URL('../../.env.local', import.meta.url));
  const vars: Record<string, string> = {};
  if (existsSync(file)) {
    for (const line of readFileSync(file, 'utf8').split('\n')) {
      const m = /^([A-Z0-9_]+)=(.*)$/.exec(line.trim());
      if (m) vars[m[1]!] = m[2]!;
    }
  }
  const url = process.env.GLOW_IT_SUPABASE_URL ?? vars.SUPABASE_URL;
  const anon = process.env.GLOW_IT_SUPABASE_ANON_KEY ?? vars.SUPABASE_ANON_KEY;
  const service = process.env.GLOW_IT_SUPABASE_SERVICE_ROLE_KEY ?? vars.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !anon || !service)
    throw new Error('No Supabase config (GLOW_IT_SUPABASE_* or server/.env.local).');
  const host = new URL(url).hostname;
  if (host !== '127.0.0.1' && host !== 'localhost') throw new Error('Local Supabase only.');
  return { url, anon, service };
}

const cfg = config();
const opts = { auth: { persistSession: false, autoRefreshToken: false } };
const admin = createClient(cfg.url, cfg.service, opts);
const anonClient = createClient(cfg.url, cfg.anon, opts);
const tag = randomBytes(3).toString('hex');
const madeUsers: string[] = [];
const madeRooms: string[] = [];
let made = 0;

type Person = { id: string; token: string; card?: string };
const GENDERS = ['woman', 'man', 'nonbinary'] as const;
const COLORS = [
  'black',
  'white',
  'gray',
  'red',
  'pink',
  'orange',
  'yellow',
  'green',
  'blue',
  'purple',
] as const;

async function pool<T, R>(
  items: readonly T[],
  size: number,
  fn: (item: T, i: number) => Promise<R>,
): Promise<R[]> {
  const out: R[] = new Array(items.length);
  let next = 0;
  await Promise.all(
    Array.from({ length: Math.min(size, items.length) }, async () => {
      while (next < items.length) {
        const i = next++;
        out[i] = await fn(items[i]!, i);
      }
    }),
  );
  return out;
}

async function person(
  gender: (typeof GENDERS)[number],
  showMe: readonly string[],
): Promise<Person> {
  const email = `b4load-${tag}-${++made}@glow.test`;
  const password = randomBytes(18).toString('base64url');
  const c = await admin.auth.admin.createUser({ email, password, email_confirm: true });
  if (c.error || !c.data.user) throw new Error(`createUser: ${c.error?.message}`);
  const id = c.data.user.id;
  madeUsers.push(id);
  const p = await admin
    .from('profiles')
    .update({
      first_name: `Load${made}`,
      birthdate: '1995-01-01',
      gender,
      show_me: showMe,
      onboarding_step: 'complete',
    })
    .eq('id', id);
  if (p.error) throw new Error(`profile: ${p.error.message}`);
  const s = await anonClient.auth.signInWithPassword({ email, password });
  if (s.error || !s.data.session) throw new Error(`sign-in: ${s.error?.message}`);
  return { id, token: s.data.session.access_token };
}

async function room(): Promise<string> {
  const { data, error } = await admin
    .from('rooms')
    .insert({
      slug: `b4load-${tag}-${madeRooms.length + 1}`,
      name: 'B4 load room',
      lat: 37.8,
      lng: -122.45,
      starts_at: new Date(Date.now() - 3_600_000).toISOString(),
      ends_at: new Date(Date.now() + 86_400_000).toISOString(),
    })
    .select('id')
    .single();
  if (error || !data) throw new Error(`room: ${error?.message}`);
  madeRooms.push(data.id);
  return data.id;
}

async function checkIn(p: Person, roomId: string, i: number) {
  const lc = await admin
    .from('location_checks')
    .insert({
      user_id: p.id,
      room_id: roomId,
      purpose: 'join',
      result: 'pass',
      accuracy_bucket: 'under_20m',
    });
  if (lc.error) throw new Error(`location check: ${lc.error.message}`);
  const card = randomUUID();
  const extras = (['glasses', 'hat', 'beard', 'headphones', 'backpack'] as const).filter(
    (_, k) => (i >> k) & 1,
  );
  const { error } = await admin.rpc('create_checkin', {
    p_user_id: p.id,
    p_room_id: roomId,
    p_checkin_id: card,
    p_card_path: `${roomId}/${card}.jpg`,
    p_tags: {
      topColor: COLORS[i % COLORS.length],
      hairLength: (['short', 'medium', 'long'] as const)[i % 3],
      extras,
    },
  });
  if (error) throw new Error(`create_checkin: ${error.message}`);
  p.card = card;
}

async function timed(call: () => Promise<Response>): Promise<{ ms: number; status: number }> {
  const t0 = performance.now();
  const res = await call();
  await res.arrayBuffer();
  return { ms: performance.now() - t0, status: res.status };
}

const deckCall = (p: Person, roomId: string, offset: number) => () =>
  fetch(`${API}/api/rooms/${roomId}/deck`, {
    method: 'POST',
    headers: { authorization: `Bearer ${p.token}`, 'content-type': 'application/json' },
    body: JSON.stringify({ offset }),
  });

const tapCall = (p: Person, roomId: string, cardId: string) => () =>
  fetch(`${API}/api/rooms/${roomId}/taps`, {
    method: 'POST',
    headers: { authorization: `Bearer ${p.token}`, 'content-type': 'application/json' },
    body: JSON.stringify({ cardId }),
  });

function stats(samples: { ms: number; status: number }[]) {
  const ms = samples.map((s) => s.ms).sort((a, b) => a - b);
  const q = (p: number) => ms[Math.min(ms.length - 1, Math.ceil(p * ms.length) - 1)]!;
  const statuses: Record<string, number> = {};
  for (const s of samples) statuses[s.status] = (statuses[s.status] ?? 0) + 1;
  return {
    n: ms.length,
    p50: +q(0.5).toFixed(1),
    p95: +q(0.95).toFixed(1),
    p99: +q(0.99).toFixed(1),
    max: +ms[ms.length - 1]!.toFixed(1),
    statuses,
  };
}

/** Every person scrolls PAGES pages, `concurrency` people at a time. */
async function sweep(people: Person[], roomId: string, concurrency: number) {
  const samples: { ms: number; status: number }[] = [];
  const t0 = performance.now();
  await pool(people, concurrency, async (p) => {
    for (let page = 0; page < PAGES; page++)
      samples.push(await timed(deckCall(p, roomId, page * 10)));
  });
  const seconds = (performance.now() - t0) / 1000;
  return { ...stats(samples), rps: +(samples.length / seconds).toFixed(1) };
}

/** Open loop: deck requests arrive at `rate` per second for `seconds`, whatever the latency. */
async function arrivals(people: Person[], roomId: string, rate: number, seconds: number) {
  const total = rate * seconds;
  const inflight: Promise<{ ms: number; status: number }>[] = [];
  const t0 = performance.now();
  for (let i = 0; i < total; i++) {
    const due = t0 + (i * 1000) / rate;
    const wait = due - performance.now();
    if (wait > 0) await new Promise((r) => setTimeout(r, wait));
    const p = people[i % people.length]!;
    inflight.push(timed(deckCall(p, roomId, (Math.floor(i / people.length) % PAGES) * 10)));
  }
  return { rate, ...stats(await Promise.all(inflight)) };
}

/** The pieces on their own: Supabase Auth's token check, and get_deck through PostgREST. */
async function parts(people: Person[], roomId: string, concurrency: number) {
  const auth: { ms: number; status: number }[] = [];
  const rpc: { ms: number; status: number }[] = [];
  await pool(people, concurrency, async (p) => {
    auth.push(
      await timed(() =>
        fetch(`${cfg.url}/auth/v1/user`, {
          headers: { apikey: cfg.anon, authorization: `Bearer ${p.token}` },
        }),
      ),
    );
    rpc.push(
      await timed(() =>
        fetch(`${cfg.url}/rest/v1/rpc/get_deck`, {
          method: 'POST',
          headers: {
            apikey: cfg.service,
            authorization: `Bearer ${cfg.service}`,
            'content-type': 'application/json',
          },
          body: JSON.stringify({
            p_viewer_id: p.id,
            p_room_id: roomId,
            p_filters: {},
            p_offset: 0,
          }),
        }),
      ),
    );
  });
  return { concurrency, auth: stats(auth), getDeckRpc: stats(rpc) };
}

async function main() {
  const report: Record<string, unknown> = {
    api: API,
    people: PEOPLE,
    pages: PAGES,
    startedAt: new Date().toISOString(),
  };
  const health = await fetch(`${API}/`).catch(() => null);
  if (!health) throw new Error(`No server at ${API}. Start it first (see the top of this file).`);

  console.log(`setup: ${PEOPLE} people in one room …`);
  const r1 = await room();
  const all = ['woman', 'man', 'nonbinary'];
  const people = await pool(
    Array.from({ length: PEOPLE }, (_, i) => i),
    15,
    (i) => person(GENDERS[i % 3]!, all),
  );
  await pool(people, 15, (p, i) => checkIn(p, r1, i));
  // A little of everything a real room has: blocks and matches change who's eligible.
  const blocks = people
    .slice(0, 20)
    .map((p, i) => ({ blocker_id: p.id, blocked_id: people[(i * 7 + 13) % PEOPLE]!.id }));
  await admin.from('blocks').insert(blocks);
  const matches = people.slice(40, 60).map((p, i) => {
    const [a, b] = [p.id, people[60 + i]!.id].sort();
    return {
      room_id: r1,
      user_a: a!,
      user_b: b!,
      choice_deadline: new Date(Date.now() + 600_000).toISOString(),
    };
  });
  await admin.from('matches').insert(matches);

  console.log('warm-up sweep …');
  report.warmup = await sweep(people, r1, 10);
  // One-sided taps on cards the deck has shown (so tappedByMe is set on some cards).
  await pool(people.slice(100, 200), 10, async (p, i) => {
    const target = people[(100 + i * 3 + 1) % PEOPLE]!;
    await timed(tapCall(p, r1, target.card!));
  });

  const sweeps: unknown[] = [];
  for (const c of LEVELS) {
    console.log(`sweep at concurrency ${c} …`);
    sweeps.push({ concurrency: c, ...(await sweep(people, r1, c)) });
  }
  report.sweeps = sweeps;

  const open: unknown[] = [];
  for (const rate of RATES) {
    console.log(`open loop at ${rate} requests/s …`);
    open.push(await arrivals(people, r1, rate, 10));
  }
  report.openLoop = open;

  report.parts = [await parts(people, r1, 1), await parts(people, r1, 25)];

  console.log(`${PAIRS} pairs tapping each other at the same moment …`);
  const r2 = await room();
  const women = await pool(Array.from({ length: PAIRS }), 15, () => person('woman', ['man']));
  const men = await pool(Array.from({ length: PAIRS }), 15, () => person('man', ['woman']));
  await pool([...women, ...men], 15, (p, i) => checkIn(p, r2, i));
  await pool([...women, ...men], 20, async (p) => {
    for (let page = 0; page < 5; page++) await timed(deckCall(p, r2, page * 10));
  });
  const taps = women.flatMap((w, i) => [
    tapCall(w, r2, men[i]!.card!),
    tapCall(men[i]!, r2, w.card!),
  ]);
  const results = await Promise.all(
    taps.map(async (call) => {
      const t0 = performance.now();
      const res = await call();
      const body = (await res.json()) as { result?: string };
      return { ms: performance.now() - t0, status: res.status, result: body.result };
    }),
  );
  const { count } = await admin
    .from('matches')
    .select('id', { count: 'exact', head: true })
    .eq('room_id', r2);
  report.simultaneousTaps = {
    pairs: PAIRS,
    requests: results.length,
    statuses: stats(results).statuses,
    mutual: results.filter((r) => r.result === 'mutual').length,
    sent: results.filter((r) => r.result === 'sent').length,
    matchesInDatabase: count,
    latency: stats(results),
  };
  report.finishedAt = new Date().toISOString();

  console.log(JSON.stringify(report, null, 2));
  if (OUT) writeFileSync(OUT, JSON.stringify(report, null, 2));
  if (count !== PAIRS) process.exitCode = 1;
}

try {
  await main();
} finally {
  console.log('cleanup …');
  if (madeRooms.length) await admin.from('rooms').delete().in('id', madeRooms);
  await pool(madeUsers, 20, (id) => admin.auth.admin.deleteUser(id));
}
