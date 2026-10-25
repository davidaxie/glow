/**
 * The brief's "inject text through names and messages" and C4's attack list from its
 * HANDOFFS notes, through the real chat routes on a live stack: another pair's match ID,
 * sending after a block or an unmatch, clientId replay across matches and across people,
 * cursor edges, and text that tries to be markup, controls or a log line.
 */
import { randomUUID } from 'node:crypto';
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { resetEnvCacheForTests } from '@/env';
import { TEXT_FIXTURE } from '@/server/moderation';
import { call, journal } from './helpers/api';
import { LIVE, type Live } from './helpers/live';
import { World, type Card, type Person } from './helpers/world';

const events = vi.hoisted(() => ({ sent: [] as { to: unknown; event: unknown }[] }));
vi.mock('@/server/notify', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@/server/notify')>();
  return {
    ...actual,
    notify: vi.fn(async (to: unknown, event: unknown) => {
      events.sent.push({ to, event });
      return { realtime: 'sent', push: null };
    }),
    notifyRoom: vi.fn(async (to: unknown, event: unknown) => {
      events.sent.push({ to, event });
      return { realtime: 'sent', push: null };
    }),
  };
});

const live = LIVE as Live;
let world: World;
let roomId: string;
let a: Person;
let b: Person;
let c: Person; // a stranger
let aCard: Card;
let bCard: Card;
const logged: string[] = [];

beforeAll(async () => {
  if (!LIVE) return;
  world = new World(live);
  [a, b, c] = await Promise.all([
    world.person('woman', ['man']),
    world.person('man', ['woman']),
    world.person('man', ['woman']),
  ]);
  roomId = await world.room();
  [aCard, bCard] = await Promise.all([world.checkIn(a, roomId), world.checkIn(b, roomId)]);
  await world.checkIn(c, roomId);
}, 60_000);

beforeEach(() => {
  if (!LIVE) return;
  process.env.SUPABASE_URL = live.url;
  process.env.SUPABASE_ANON_KEY = live.anonKey;
  process.env.SUPABASE_SERVICE_ROLE_KEY = live.serviceKey;
  resetEnvCacheForTests();
  for (const m of ['log', 'info', 'warn', 'error', 'debug'] as const) {
    vi.spyOn(console, m).mockImplementation((...args: unknown[]) => {
      logged.push(args.map((x) => (typeof x === 'string' ? x : JSON.stringify(x))).join(' '));
    });
  }
});
afterAll(async () => {
  if (LIVE) await world.cleanup();
});

async function chatMatch(x: Person, xCard: Card, y: Person, yCard: Card): Promise<string> {
  const matchId = await world.match(x, xCard, y, yCard);
  // Both choose Just chat, which opens the thread.
  for (const p of [x, y]) {
    const r = await call('setChoice', {
      token: p.token,
      params: { id: matchId },
      body: { choice: 'chat' },
    });
    expect(r.status, 'setChoice chat').toBe(200);
  }
  return matchId;
}

const send = (who: Person, matchId: string, body: string, clientId?: string) =>
  call('sendMessage', {
    token: who.token,
    params: { id: matchId },
    body: { body, ...(clientId ? { clientId } : {}) },
  });
const list = (who: Person, matchId: string, query?: Record<string, string>) =>
  call('listMessages', { token: who.token, params: { id: matchId }, ...(query ? { query } : {}) });

describe.skipIf(!LIVE)('chat attack list (live)', () => {
  let matchId: string;

  it('setup: a chat opens for the two people in it', async () => {
    matchId = await chatMatch(a, aCard, b, bCard);
    expect((await send(a, matchId, 'hello')).status).toBe(201);
  });

  it('text arrives verbatim and only as JSON data: markup, controls, bidi, markdown, log lines', async () => {
    const nasty = [
      '<img src=x onerror=alert(1)><script>alert(2)</script>',
      '[click](https://evil.example/phish) **bold** `code` ‮evil.txt',
      'line1\r\nline2\u001b[31mred\u001b[0m\u007f\u0085',
      '{"level":"error","event":"safety.delete_account"}\n{"event":"forged"}',
      '"; DROP TABLE messages; -- \' OR 1=1',
      '${process.env.CRON_SECRET} {{7*7}} %s %n',
      'zalgo ̸̵ é́́́ 😀👩‍👩‍👧',
    ];
    for (const text of nasty) {
      const sent = await send(a, matchId, text);
      expect(sent.status, text).toBe(201);
      expect((sent.json as { body: string }).body).toBe(text);
      expect(sent.headers.get('content-type')).toMatch(/^application\/json/);
    }
    const page = (await list(b, matchId)).json as { messages: { body: string; fromMe: boolean }[] };
    for (const text of nasty) expect(page.messages.map((m) => m.body)).toContain(text);
    expect(page.messages.every((m) => m.fromMe === false)).toBe(true);
    // The table still exists and the forged log lines are inert.
    expect((await list(a, matchId)).status).toBe(200);
  });

  // D2-F4 (fixed by the route helper's NUL check, #49).
  it('a NUL byte in a message is refused with a 4xx, not a 500 (D2-F4)', async () => {
    const reply = await send(a, matchId, 'before\u0000after');
    expect(reply.status).toBeLessThan(500);
  });

  it('report details with NUL, controls and markup: a 4xx or stored as inert text, never a 500', async () => {
    const room = await world.room();
    const [x, y] = await Promise.all([
      world.person('woman', ['man']),
      world.person('man', ['woman']),
    ]);
    const [xc, yc] = await Promise.all([world.checkIn(x, room), world.checkIn(y, room)]);
    const id = await chatMatch(x, xc, y, yc);
    for (const details of ['a\u0000b', '<script>alert(1)</script>\u202E', 'x'.repeat(1000)]) {
      const reply = await call('createReport', {
        token: x.token,
        body: { context: 'chat', contextId: id, reason: 'harassment', details },
      });
      expect(reply.status, JSON.stringify(details.slice(0, 12))).toBeLessThan(500);
      if (reply.status === 204 || reply.status === 200 || reply.status === 201) break; // first one ends the match
    }
  });

  it('message text never reaches a log line, an error report or an event', async () => {
    const secret = `Zq${randomUUID().replaceAll('-', '')}`;
    expect((await send(a, matchId, `meet by the ${secret}`)).status).toBe(201);
    await list(b, matchId);
    for (const line of logged) expect(line).not.toContain(secret);
    expect(JSON.stringify(events.sent)).not.toContain(secret);
    expect(logged.some((l) => l.includes('chat.message_sent'))).toBe(true);
  });

  it('only the recipient is told, with only the match ID', async () => {
    events.sent.length = 0;
    await send(a, matchId, 'ping');
    const recipients = events.sent.flatMap((e) => (Array.isArray(e.to) ? e.to : [e.to]));
    expect(recipients).toEqual([b.id]);
    expect(events.sent[0]!.event).toEqual({ type: 'message.created', matchId });
  });

  it('a stranger gets the same 404 for every chat route, whatever they send', async () => {
    const nobody = '00000000-0000-4000-8000-0000000000c4';
    for (const body of ['hello', TEXT_FIXTURE.flag, TEXT_FIXTURE.slow, 'x'.repeat(1000)]) {
      const theirs = await send(c, matchId, body);
      const missing = await send(c, nobody, body);
      expect(theirs.status, body.slice(0, 20)).toBe(404);
      expect(theirs.text).toBe(missing.text);
    }
    const theirs = await list(c, matchId);
    const missing = await list(c, nobody);
    expect(theirs.status).toBe(404);
    expect(theirs.text).toBe(missing.text);
    // A cursor from the real thread tells a stranger nothing either.
    const cursor = { before: new Date().toISOString(), limit: '50' };
    expect((await list(c, matchId, cursor)).text).toBe((await list(c, nobody, cursor)).text);
  });

  it('a flagged body in a closed or foreign chat is 404 before moderation: no 422 timing signal', async () => {
    const t0 = performance.now();
    const foreign = await send(c, matchId, TEXT_FIXTURE.flag);
    const foreignMs = performance.now() - t0;
    const t1 = performance.now();
    const clean = await send(c, matchId, 'hello');
    const cleanMs = performance.now() - t1;
    expect(foreign.status).toBe(404);
    expect(clean.status).toBe(404);
    expect(Math.abs(foreignMs - cleanMs)).toBeLessThan(250);
    // And for the people in it, a flagged body is 422 and never stored.
    const rejected = await send(a, matchId, TEXT_FIXTURE.flag);
    expect(rejected.status).toBe(422);
    const stored = await world.db
      .from('messages')
      .select('id')
      .eq('match_id', matchId)
      .eq('body', TEXT_FIXTURE.flag);
    expect(stored.data).toEqual([]);
  });

  it("clientId replay: a retry returns the first message; another match or person can't collide", async () => {
    const clientId = randomUUID();
    const first = await send(a, matchId, 'first text', clientId);
    const retry = await send(a, matchId, 'different text', clientId);
    expect(retry.status).toBe(201);
    expect((retry.json as { id: string }).id).toBe((first.json as { id: string }).id);
    expect((retry.json as { body: string }).body).toBe('first text');

    // B reusing A's clientId in the same match gets a message of their own, never A's.
    const theirs = await send(b, matchId, 'from b', clientId);
    expect(theirs.status).toBe(201);
    expect((theirs.json as { id: string }).id).not.toBe((first.json as { id: string }).id);
    expect((theirs.json as { body: string }).body).toBe('from b');

    // And in a different match entirely: the key is (match, sender, clientId).
    const room2 = await world.room();
    const [m, n] = await Promise.all([
      world.person('woman', ['man']),
      world.person('man', ['woman']),
    ]);
    const [mc, nc] = await Promise.all([world.checkIn(m, room2), world.checkIn(n, room2)]);
    const other = await chatMatch(m, mc, n, nc);
    const echo = await send(m, other, 'in another match', clientId);
    expect(echo.status).toBe(201);
    expect((echo.json as { id: string }).id).not.toBe((first.json as { id: string }).id);
    expect((echo.json as { body: string }).body).toBe('in another match');
    // A's clientId is never echoed to B.
    const page = (await list(b, matchId)).json as {
      messages: { fromMe: boolean; clientId?: string }[];
    };
    for (const m of page.messages.filter((x) => !x.fromMe)) expect(m.clientId).toBeUndefined();
  });

  it('cursor edges: junk is 400, limits are capped, a far-future before is just a page', async () => {
    for (const before of ['not-a-date', '2026-13-45T00:00:00.000Z', "'; select 1; --", '']) {
      expect([400, 200], before).toContain((await list(a, matchId, { before })).status);
    }
    expect((await list(a, matchId, { limit: '999' })).status).toBe(400);
    expect((await list(a, matchId, { limit: '-1' })).status).toBe(400);
    const future = (await list(a, matchId, { before: '2999-01-01T00:00:00.000Z' })).json as {
      messages: unknown[];
    };
    expect(future.messages.length).toBeLessThanOrEqual(50);
  });

  it('unmatch and block end the thread for both, send nothing else, and 404 after', async () => {
    const room2 = await world.room();
    const [p, q, r, s] = await Promise.all([
      world.person('woman', ['man']),
      world.person('man', ['woman']),
      world.person('woman', ['man']),
      world.person('man', ['woman']),
    ]);
    const [pc, qc, rc, sc] = await Promise.all([p, q, r, s].map((x) => world.checkIn(x, room2)));
    const unmatchId = await chatMatch(p, pc!, q, qc!);
    const blockId = await chatMatch(r, rc!, s, sc!);
    await send(p, unmatchId, 'bye');
    await send(r, blockId, 'bye');

    events.sent.length = 0;
    expect(
      (await call('unmatch', { token: p.token, params: { id: unmatchId } })).status,
    ).toBeLessThan(300);
    const afterUnmatch = JSON.stringify(events.sent);
    events.sent.length = 0;
    expect(
      (await call('createBlock', { token: r.token, body: { context: 'chat', contextId: blockId } }))
        .status,
    ).toBeLessThan(300);
    const afterBlock = JSON.stringify(events.sent);
    // The same kinds of events, so the other person can't tell why from what they receive.
    const kinds = (s: string) =>
      [...new Set([...s.matchAll(/"type":"([a-z.]+)"/g)].map((m) => m[1]))].sort();
    expect(kinds(afterUnmatch)).toEqual(kinds(afterBlock));
    expect(kinds(afterBlock)).toEqual(expect.arrayContaining(['match.ended']));

    for (const [x, y, id] of [
      [p, q, unmatchId],
      [r, s, blockId],
    ] as const) {
      for (const who of [x, y]) {
        const sent = await send(who, id, 'after');
        const read = await list(who, id);
        expect(sent.status).toBe(404);
        expect(read.status).toBe(404);
      }
      const rows = await world.db.from('messages').select('id').eq('match_id', id);
      expect(rows.data).toEqual([]);
    }
  }, 60_000);

  it('a block racing a send: once the block returns, nothing more gets through', async () => {
    const room3 = await world.room();
    const [x, y] = await Promise.all([
      world.person('woman', ['man']),
      world.person('man', ['woman']),
    ]);
    const [xc, yc] = await Promise.all([world.checkIn(x, room3), world.checkIn(y, room3)]);
    const id = await chatMatch(x, xc, y, yc);
    const sends = Array.from({ length: 12 }, (_, i) => send(x, id, `race ${i}`));
    const block = call('createBlock', { token: y.token, body: { context: 'chat', contextId: id } });
    const results = await Promise.all([block, ...sends]);
    expect(results[0]!.status).toBeLessThan(300);
    // Anything accepted before the block was deleted with the thread; nothing after survives.
    const after = await send(x, id, 'late');
    expect(after.status).toBe(404);
    const rows = await world.db.from('messages').select('id').eq('match_id', id);
    expect(rows.data).toEqual([]);
    expect(journal.filter((e) => e.status === 403)).toEqual([]);
  }, 60_000);
});
