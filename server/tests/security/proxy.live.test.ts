/**
 * The brief's proxy run: a scripted two-person journey sent through mitmproxy, then every
 * request, response and Realtime frame it saw is scanned. Opt-in, because it needs mitmproxy
 * (`brew install mitmproxy`) and a running server:
 *
 *   eval "$(scripts/agent-env.sh D2 --own-db)"          # your own Supabase
 *   pnpm --filter server build && pnpm --filter server start &   # the API on $PORT
 *   D2_PROXY=1 pnpm --filter server exec vitest run tests/security/proxy.live.test.ts
 *
 * Two reverse proxies listen on 127.0.0.1 and forward to the local API and the local Supabase
 * over plain HTTP: no certificate is installed anywhere, and nothing but localhost is touched.
 * The "app" in this run is a script that does what the app does (sign in, join, check in, look
 * at the deck, tap, chat). The same scan runs on a Simulator once B1's session is merged.
 *
 * Rules checked on all traffic (P1, P2, P3, P4, P5, P11):
 * - No user ID but your own, ever. Not before a match, and not after one (D20).
 * - No other person's first name, email or profile photo path before the match; after it, the
 *   name appears only in the match replies.
 * - No coordinates anywhere but the one request that sends them.
 * - Only the server's own host gets the token; no cookies; no `Cache-Control` that allows
 *   storing; no wildcard CORS; no 403; no 5xx; no stack traces.
 * - Card photos arrive only through the signed API link, as no-store JPEGs.
 */
import { spawn, type ChildProcess } from 'node:child_process';
import { existsSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { LIVE, supa, tag, type Live } from './helpers/live';
import { RealtimeProbe } from './helpers/realtime';
import { World, type Person } from './helpers/world';

const ENABLED = process.env.D2_PROXY === '1' && LIVE !== null;
const live = LIVE as Live;
const API = process.env.GLOW_API ?? 'http://localhost:3122';
const API_PROXY = 3123;
const SUPABASE_PROXY = 3124;
const ADDON = fileURLToPath(new URL('./proxy/addon.py', import.meta.url));
const PHOTO = fileURLToPath(
  new URL('../../../ios/fixtures/photos/outfit-real-blue-flightsuit.jpg', import.meta.url),
);
const LOG = join(tmpdir(), `d2-flows-${tag()}.jsonl`);

type Exchange = {
  kind: 'http' | 'ws';
  label: string;
  ts: number;
  method?: string;
  path: string;
  req?: { headers: Record<string, string>; text?: string };
  res?: {
    status: number;
    headers: Record<string, string>;
    set_cookie: string[];
    text?: string;
    binary?: boolean;
    type?: string;
    magic?: string;
  };
  from_client?: boolean;
  text?: string;
};

function lowerHeaders(e: Exchange): Exchange {
  const lower = (h: Record<string, string> | undefined) =>
    Object.fromEntries(Object.entries(h ?? {}).map(([k, v]) => [k.toLowerCase(), v]));
  if (e.req) e.req.headers = lower(e.req.headers);
  if (e.res) e.res.headers = lower(e.res.headers);
  return e;
}

const procs: ChildProcess[] = [];
function startProxy(label: string, target: string, port: number) {
  const child = spawn(
    'mitmdump',
    [
      '--mode',
      `reverse:${target}`,
      '--listen-host',
      '127.0.0.1',
      '--listen-port',
      String(port),
      '-s',
      ADDON,
      '--set',
      'termlog_verbosity=error',
      '--set',
      'connection_strategy=lazy',
    ],
    { env: { ...process.env, D2_FLOWLOG: LOG, D2_LABEL: label }, stdio: 'ignore' },
  );
  procs.push(child);
}
async function waitFor(url: string) {
  for (let i = 0; i < 50; i++) {
    try {
      await fetch(url, { signal: AbortSignal.timeout(500) });
      return;
    } catch {
      await new Promise((r) => setTimeout(r, 200));
    }
  }
  throw new Error(`${url} never came up`);
}

let world: World;
let alex: Person;
let blake: Person;
const marks: Record<string, number> = {};
const via = (port: number) => `http://127.0.0.1:${port}`;

async function api(who: Person & { jwt: string }, method: string, path: string, body?: unknown) {
  const res = await fetch(`${via(API_PROXY)}${path}`, {
    method,
    headers: {
      authorization: `Bearer ${who.jwt}`,
      ...(body === undefined ? {} : { 'content-type': 'application/json' }),
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  const bytes = new Uint8Array(await res.arrayBuffer());
  return {
    status: res.status,
    json: res.headers.get('content-type')?.includes('json')
      ? (JSON.parse(new TextDecoder().decode(bytes)) as Record<string, any>)
      : null,
    bytes,
  };
}

/** Signs in the way the app does, over the Supabase proxy: a one-time token, then verify. */
async function appSignIn(person: Person): Promise<Person & { jwt: string }> {
  const link = await supa(live, 'POST', '/auth/v1/admin/generate_link', {
    key: 'service',
    body: { type: 'magiclink', email: person.email },
  });
  const hash = (link.json.hashed_token ??
    (link.json.properties as Record<string, unknown>)?.hashed_token) as string;
  const res = await fetch(`${via(SUPABASE_PROXY)}/auth/v1/verify`, {
    method: 'POST',
    headers: { apikey: live.anonKey, 'content-type': 'application/json' },
    body: JSON.stringify({ type: 'email', token_hash: hash }),
  });
  const session = (await res.json()) as { access_token: string };
  return { ...person, jwt: session.access_token };
}

describe.skipIf(!ENABLED)('proxy run: every byte of a two-person journey (live)', () => {
  const traffic: Exchange[] = [];
  let a: Person & { jwt: string };
  let b: Person & { jwt: string };
  const probes: RealtimeProbe[] = [];
  let matchId = '';
  let roomId = '';

  beforeAll(async () => {
    rmSync(LOG, { force: true });
    startProxy('api', API, API_PROXY);
    startProxy('supabase', live.url, SUPABASE_PROXY);
    await waitFor(`${via(API_PROXY)}/api/nothing`);
    await waitFor(`${via(SUPABASE_PROXY)}/auth/v1/health`);

    world = new World(live);
    [alex, blake] = await Promise.all([
      world.person('woman', ['man']),
      world.person('man', ['woman']),
    ]);
    roomId = await world.room();
    const code = (await world.db.from('rooms').select('code').eq('id', roomId).single()).data!.code;

    a = await appSignIn(alex);
    b = await appSignIn(blake);
    const proxied: Live = { ...live, url: via(SUPABASE_PROXY) };
    const [pa, pb] = await Promise.all([
      RealtimeProbe.connect(proxied),
      RealtimeProbe.connect(proxied),
    ]);
    probes.push(pa, pb);
    expect(await pa.join(`user:${alex.id}`, { token: a.jwt, private: true })).toBe('ok');
    expect(await pb.join(`user:${blake.id}`, { token: b.jwt, private: true })).toBe('ok');

    const photo = readFileSync(PHOTO).toString('base64');
    for (const who of [a, b]) {
      const resolved = await api(who, 'POST', '/api/rooms/resolve', { kind: 'code', code });
      expect(resolved.status).toBe(200);
      const joined = await api(who, 'POST', `/api/rooms/${roomId}/join`, {
        access: { kind: 'code', code },
        location: { latitude: 37.80291357, longitude: -122.4484246, accuracy: 12.5 },
      });
      expect(joined.status).toBe(200);
      const checkin = await api(who, 'POST', `/api/rooms/${roomId}/checkin`, {
        ticket: joined.json!.ticket,
        photo,
        tags: { topColor: 'blue', extras: ['glasses'] },
      });
      expect(checkin.status, JSON.stringify(checkin.json)).toBe(201);
      expect((await api(who, 'GET', `/api/rooms/${roomId}`)).status).toBe(200);
    }

    // Each looks at the deck and at the other's card image (through the signed link).
    for (const [me, other] of [
      [a, b],
      [b, a],
    ] as const) {
      const deck = await api(me, 'POST', `/api/rooms/${roomId}/deck`, { filters: {}, offset: 0 });
      expect(deck.status).toBe(200);
      const card = (deck.json!.cards as { id: string; image: { url: string } }[])[0]!;
      const image = await api(me, 'GET', card.image.url);
      expect(image.status).toBe(200);
      expect(other.id).toBeDefined();
    }
    const aDeck = await api(a, 'POST', `/api/rooms/${roomId}/deck`, { filters: {}, offset: 0 });
    const bDeck = await api(b, 'POST', `/api/rooms/${roomId}/deck`, { filters: {}, offset: 0 });
    const aTarget = aDeck.json!.cards[0].id as string;
    const bTarget = bDeck.json!.cards[0].id as string;

    expect(
      (await api(a, 'POST', `/api/rooms/${roomId}/taps`, { cardId: aTarget })).json!.result,
    ).toBe('sent');
    await api(a, 'GET', '/api/matches');
    await api(b, 'POST', `/api/rooms/${roomId}/deck`, { filters: {}, offset: 0 });
    marks.beforeMutual = Date.now() / 1000;
    const mutual = await api(b, 'POST', `/api/rooms/${roomId}/taps`, { cardId: bTarget });
    expect(mutual.json!.result).toBe('mutual');
    matchId = mutual.json!.matchId as string;
    marks.afterMutual = Date.now() / 1000;

    await pa.settle(1200);
    for (const [me] of [[a], [b]] as const) {
      await api(me, 'GET', '/api/matches');
      await api(me, 'GET', `/api/matches/${matchId}`);
      await api(me, 'GET', `/api/matches/${matchId}/photos/0`);
      await api(me, 'POST', `/api/matches/${matchId}/choice`, { choice: 'chat' });
    }
    await api(a, 'POST', `/api/matches/${matchId}/messages`, { body: 'hi from the proxy run' });
    await api(b, 'GET', `/api/matches/${matchId}/messages`);
    await pa.settle(800);
    await api(a, 'POST', `/api/matches/${matchId}/unmatch`);
    await pb.settle(1200);

    for (const p of probes) p.close();
    await new Promise((r) => setTimeout(r, 800)); // let the proxies flush
    traffic.push(
      ...readFileSync(LOG, 'utf8')
        .split('\n')
        .filter(Boolean)
        .map((l) => lowerHeaders(JSON.parse(l) as Exchange)),
    );
  }, 180_000);

  afterAll(async () => {
    for (const p of procs) p.kill();
    if (existsSync(LOG)) rmSync(LOG, { force: true });
    if (world) await world.cleanup();
  });

  const text = (e: Exchange) =>
    [
      e.path,
      e.req?.text ?? '',
      e.res?.text ?? '',
      e.text ?? '',
      JSON.stringify(e.req?.headers ?? {}),
    ].join('\n');
  const UUID = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi;

  it('the proxy saw the whole journey (control)', () => {
    const api = traffic.filter((t) => t.label === 'api' && t.kind === 'http');
    expect(api.length).toBeGreaterThan(20);
    expect(traffic.some((t) => t.kind === 'ws')).toBe(true);
    expect(traffic.some((t) => t.kind === 'ws' && t.text!.includes('match.created'))).toBe(true);
    expect(api.some((t) => t.res?.binary && t.res.magic?.startsWith('ffd8'))).toBe(true);
    // The scan can see names: after the match, each person's name does show up in a match reply.
    for (const person of [alex, blake]) {
      expect(
        api.some((t) => t.path.startsWith('/api/matches') && text(t).includes(person.firstName)),
      ).toBe(true);
    }
  });

  it("P1: nobody else's user ID appears anywhere, before or after the match", () => {
    // The whole population of user IDs on the stack, minus the one person each run is about.
    for (const [me, other] of [
      [alex, blake],
      [blake, alex],
    ] as const) {
      void me;
      const mine = (e: Exchange) =>
        (e.req?.headers.authorization ?? '').includes(me === alex ? a.jwt : b.jwt);
      for (const e of traffic.filter((t) => t.kind === 'http' && mine(t))) {
        expect(text(e).toLowerCase(), `${e.method} ${e.path}`).not.toContain(other.id);
      }
    }
    // Realtime frames to a person never carry anyone's user ID but their own channel name.
    for (const e of traffic.filter((t) => t.kind === 'ws' && !t.from_client)) {
      const foreign = (e.text!.match(UUID) ?? []).map((u) => u.toLowerCase());
      for (const id of foreign) expect([alex.id, blake.id, matchId, roomId]).toContain(id);
      expect(e.text).not.toContain(alex.firstName);
      expect(e.text).not.toContain(blake.firstName);
    }
  });

  it('P1: no other first name, email or photo path until the match, and then only in the match replies', () => {
    const matchRoutes = /^\/api\/matches(\/|\?|$)/;
    for (const e of traffic.filter((t) => t.kind === 'http' && t.label === 'api')) {
      const body = text(e);
      for (const person of [alex, blake]) {
        expect(body.toLowerCase(), e.path).not.toContain(person.email.toLowerCase());
        expect(body, e.path).not.toContain(`${person.id}/`);
      }
      const forMatchOnly = [alex.firstName, blake.firstName].some((n) => body.includes(n));
      if (forMatchOnly) {
        expect(e.ts, `${e.path} named someone before the match`).toBeGreaterThan(
          marks.beforeMutual!,
        );
        expect(matchRoutes.test(e.path), `${e.path} named someone outside the match replies`).toBe(
          true,
        );
      }
    }
  });

  it("P5: the tapped person's traffic before the mutual tap says nothing about the tap", () => {
    const forBlake = traffic.filter(
      (t) =>
        t.label === 'api' &&
        t.kind === 'http' &&
        t.ts < marks.beforeMutual! &&
        (t.req?.headers.authorization ?? '').includes(b.jwt),
    );
    expect(forBlake.length).toBeGreaterThan(3);
    const blakeWs = traffic.filter(
      (t) => t.kind === 'ws' && !t.from_client && t.ts < marks.beforeMutual!,
    );
    // Nothing is pushed to Blake over Realtime at all until the match exists.
    expect(
      blakeWs.filter(
        (t) => /"event":"(broadcast|match\.)/.test(t.text!) && t.text!.includes(blake.id),
      ),
    ).toEqual([]);
    for (const e of forBlake) {
      expect(text(e)).not.toMatch(
        /tappedYou|tappedBy(?!Me\b)|tapsReceived|admirer|tappedAt|tapsAboutMe/i,
      );
    }
  });

  it('P2: coordinates appear only in the one request that sends them', () => {
    const digits = ['80291357', '4484246', '12.5'];
    for (const e of traffic.filter((t) => t.kind === 'http')) {
      const isJoin = /^\/api\/rooms\/[0-9a-f-]{36}\/join$/.test(e.path) && e.method === 'POST';
      const reqSide = [e.req?.text ?? '', e.path].join('\n');
      const resSide = [e.res?.text ?? ''].join('\n');
      for (const d of digits) {
        expect(resSide, `${e.path} response`).not.toContain(d);
        if (!isJoin) expect(reqSide, `${e.path} request`).not.toContain(d);
      }
    }
    for (const e of traffic.filter((t) => t.kind === 'ws' && !t.from_client)) {
      for (const d of digits) expect(e.text).not.toContain(d);
    }
  });

  it('P3 and P4: photos only come as no-store JPEGs through the signed API link', () => {
    const images = traffic.filter((t) => t.kind === 'http' && t.res?.binary);
    expect(images.length).toBeGreaterThanOrEqual(3);
    for (const e of images) {
      expect(e.label).toBe('api');
      expect(e.path).toMatch(
        /^\/api\/(cards\/[0-9a-f-]{36}\/image\?exp=\d+&sig=[\w-]{43}|matches\/[0-9a-f-]{36}\/photos\/\d)$/,
      );
      expect(e.res!.headers['cache-control']).toMatch(/no-store/);
      expect(e.res!.magic).toMatch(/^ffd8/);
      expect(e.req!.headers.authorization).toMatch(/^Bearer /);
    }
    // Nothing fetched a storage URL: the app never sees one.
    expect(traffic.filter((t) => t.label === 'supabase' && t.path.startsWith('/storage'))).toEqual(
      [],
    );
    // The upload carried a JPEG that the client had already stripped (nothing here adds EXIF).
    const upload = traffic.find((t) => t.path.endsWith('/checkin') && t.method === 'POST')!;
    expect(upload.req!.text).toMatch(/"photo":"\/9j\//);
  });

  it('headers: no cookies, no wildcard CORS, no cacheable API replies, no stack traces, no 403/5xx', () => {
    for (const e of traffic.filter((t) => t.kind === 'http')) {
      const res = e.res!;
      expect(res.set_cookie ?? [], e.path).toEqual([]);
      // Supabase Auth answers CORS for supabase-js; the API must not.
      if (e.label === 'api')
        expect(res.headers['access-control-allow-origin'], e.path).toBeUndefined();
      expect(res.status, e.path).not.toBe(403);
      expect(res.status, e.path).toBeLessThan(500);
      expect(res.headers['x-powered-by'], e.path).toBeUndefined();
      if (e.label === 'api') expect(res.headers['cache-control'], e.path).toMatch(/no-store/);
      expect(res.text ?? '', e.path).not.toMatch(
        /node_modules|\.ts:\d+|at async|sb_secret_|service_role/,
      );
    }
  });

  it("only the API's own hosts ever saw the token; the app talks to nobody else", () => {
    const hosts = new Set(traffic.filter((t) => t.kind === 'http').map((t) => t.label));
    expect([...hosts].sort()).toEqual(['api', 'supabase']);
    for (const e of traffic.filter((t) => t.kind === 'http' && t.label === 'supabase')) {
      // Supabase gets sign-in and Realtime only, never an API payload.
      expect(e.path).toMatch(/^\/(auth\/v1\/|realtime\/v1\/)/);
    }
  });
});
