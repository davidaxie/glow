/**
 * Owner: C4. The chat routes end to end against a real local Supabase: who may read and
 * send (P11), moderation, idempotent retries, paging, unmatch and block. See ./harness.ts
 * for when these run.
 */
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import {
  MESSAGES_PAGE_SIZE,
  zMessage,
  zMessagePage,
  type Message,
  type MessagePage,
} from '@/contracts';
import { setRateLimitStoreForTests } from '@/server/ratelimit';
import { IT, useRealSupabase, World, type Person } from './harness';

const notifySpy = vi.hoisted(() =>
  vi.fn(async (_userIds: string | readonly string[], _event: unknown) => ({
    realtime: 'sent' as const,
    push: null,
  })),
);

vi.mock('@/server/chat/dependencies', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@/server/chat/dependencies')>();
  return { ...actual, notify: notifySpy };
});

const FLAG = '[glow-test:flag]';
const SLOW = '[glow-test:slow]';

describe.runIf(IT)('chat routes (integration)', { timeout: 120_000 }, () => {
  let world: World;
  let room: string;
  let ana: Person;
  let ben: Person;
  let cal: Person;
  let thread: string;
  let paged: string;
  let everyone: string[];

  /** The reply's text never names anyone: no user ID appears anywhere in it (P1, D20). */
  const noIds = async (res: Response) => {
    const text = await res.clone().text();
    for (const id of everyone) expect(text).not.toContain(id);
  };

  const page = async (p: Person, matchId: string, query: Record<string, string> = {}) => {
    const res = await world.list(p, matchId, query);
    expect(res.status).toBe(200);
    await noIds(res);
    const body = (await res.json()) as MessagePage;
    expect(zMessagePage.parse(body)).toEqual(body);
    return body;
  };

  const send = async (p: Person, matchId: string, body: string, clientId?: string) => {
    const res = await world.send(p, matchId, { body, ...(clientId ? { clientId } : {}) });
    return res;
  };

  const sent = async (p: Person, matchId: string, body: string, clientId?: string) => {
    const res = await send(p, matchId, body, clientId);
    expect(res.status).toBe(201);
    await noIds(res);
    const message = (await res.json()) as Message;
    expect(zMessage.parse(message)).toEqual(message);
    return message;
  };

  const errorCode = async (res: Response) =>
    ((await res.json()) as { error: { code: string } }).error.code;

  const events = () =>
    notifySpy.mock.calls.map(([ids, event]) => ({
      to: [...(typeof ids === 'string' ? [ids] : ids)].sort(),
      event,
    }));

  beforeAll(async () => {
    world = new World(IT!);
    useRealSupabase(IT!);
    room = await world.room();
    ana = await world.person('Ana');
    ben = await world.person('Ben');
    cal = await world.person('Cal');
    everyone = [ana.id, ben.id, cal.id];
    thread = await world.match(room, ana, ben);
  });
  beforeEach(() => {
    useRealSupabase(IT!);
    setRateLimitStoreForTests(undefined);
    notifySpy.mockClear();
  });
  afterAll(() => world?.cleanup());

  it('needs sign-in', async () => {
    expect((await world.list(null, thread)).status).toBe(401);
    expect((await world.send(null, thread, { body: 'hi' })).status).toBe(401);
    expect((await world.unmatch(null, thread)).status).toBe(401);
  });

  it('sends, and both see the message with fromMe and no sender', async () => {
    const mine = await sent(ana, thread, 'Hi! I liked your green jacket.');
    expect(mine).toMatchObject({ fromMe: true, body: 'Hi! I liked your green jacket.' });
    expect(Object.keys(mine).sort()).toEqual(['body', 'createdAt', 'fromMe', 'id']);
    expect(mine.createdAt).toMatch(/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/);

    expect(events()).toEqual([
      { to: [ben.id], event: { type: 'message.created', matchId: thread } },
    ]);

    const forBen = await page(ben, thread);
    expect(forBen.messages).toEqual([{ ...mine, fromMe: false }]);
    expect(forBen.hasMore).toBe(false);
    const forAna = await page(ana, thread);
    expect(forAna.messages).toEqual([mine]);

    const [row] = await world.rows(thread);
    expect(row).toMatchObject({ sender_id: ana.id, moderation: 'passed' });
  });

  it('keeps the order oldest to newest, and replies in both directions', async () => {
    await sent(ben, thread, 'Thanks! Want to grab a drink at the bar?');
    await sent(ana, thread, 'Sure, see you there');
    const forBen = await page(ben, thread);
    expect(forBen.messages.map((m) => [m.fromMe, m.body])).toEqual([
      [false, 'Hi! I liked your green jacket.'],
      [true, 'Thanks! Want to grab a drink at the bar?'],
      [false, 'Sure, see you there'],
    ]);
  });

  it('a retry with the same clientId returns the first message and stores one row', async () => {
    const clientId = '0f5c3b8e-6d55-4d9b-9f0e-9f6f2a7c1d01';
    const first = await sent(ana, thread, 'Is the bar the one by the stage?', clientId);
    const again = await sent(ana, thread, 'Is the bar the one by the stage?', clientId);
    expect(again).toEqual(first);
    expect(first.clientId).toBe(clientId);
    const rows = (await world.rows(thread)).filter((r) => r.client_id === clientId);
    expect(rows).toHaveLength(1);
    // The other person never sees someone else's idempotency key.
    const forBen = await page(ben, thread);
    expect(forBen.messages.find((m) => m.id === first.id)).not.toHaveProperty('clientId');
  });

  it('refuses a flagged message with 422 and never stores it', async () => {
    const before = (await world.rows(thread)).length;
    const res = await send(ana, thread, `you are ${FLAG}`);
    expect(res.status).toBe(422);
    expect(await errorCode(res)).toBe('message_rejected');
    expect(await world.rows(thread)).toHaveLength(before);
    expect(notifySpy).not.toHaveBeenCalled();
  });

  it('lets a message through as pending when moderation is too slow', async () => {
    const started = Date.now();
    const message = await sent(ben, thread, `hello ${SLOW}`);
    expect(Date.now() - started).toBeLessThan(5000);
    const row = (await world.rows(thread)).find((r) => r.id === message.id);
    expect(row?.moderation).toBe('pending');
    expect((await page(ana, thread)).messages.map((m) => m.id)).toContain(message.id);
    expect(events()).toEqual([
      { to: [ana.id], event: { type: 'message.created', matchId: thread } },
    ]);
  });

  it('hides a message the review flagged from the recipient, not from its sender', async () => {
    const message = await sent(ben, thread, 'something the review will flag');
    await world.admin.from('messages').update({ moderation: 'flagged' }).eq('id', message.id);
    expect((await page(ana, thread)).messages.map((m) => m.id)).not.toContain(message.id);
    expect((await page(ben, thread)).messages.map((m) => m.id)).toContain(message.id);
  });

  it('rejects blank and too long bodies with 400', async () => {
    expect((await send(ana, thread, '   \n ')).status).toBe(400);
    expect((await send(ana, thread, '')).status).toBe(400);
    expect((await send(ana, thread, 'x'.repeat(1001))).status).toBe(400);
    expect((await send(ana, thread, 'x'.repeat(1000))).status).toBe(201);
  });

  it('answers 404 for someone not in the match, and for an ID that does not exist', async () => {
    for (const res of [
      await world.list(cal, thread),
      await send(cal, thread, 'hi'),
      await world.unmatch(cal, thread),
      await world.list(ana, '6e0b2a4c-1d6f-4a5e-9c3b-7f1a2b3c4d5e'),
      await world.list(ana, 'not-a-uuid'),
    ]) {
      expect(res.status).toBe(404);
      expect(await errorCode(res)).toBe('not_found');
    }
  });

  it('is 409 chat_not_open while choosing, and opens when the choice window runs out', async () => {
    const choosing = await world.match(room, ana, cal, 'choosing', new Date(Date.now() + 60_000));
    const read = await world.list(ana, choosing);
    expect(read.status).toBe(409);
    expect(await errorCode(read)).toBe('chat_not_open');
    const write = await send(cal, choosing, 'hi');
    expect(write.status).toBe(409);
    expect(await errorCode(write)).toBe('chat_not_open');
    // A flagged message to a closed chat says 409, not 422: moderation never saw it.
    expect((await send(cal, choosing, FLAG)).status).toBe(409);

    await world.admin
      .from('matches')
      .update({ choice_deadline: new Date(Date.now() - 1000).toISOString() })
      .eq('id', choosing);
    await sent(cal, choosing, 'the window ran out, so here I am');
    await world.unmatch(ana, choosing);
  });

  it('pages back with before and nextBefore, without skipping or repeating', async () => {
    paged = await world.match(room, ben, cal);
    // 2 pages and a bit, with several messages sharing each millisecond at the page edges.
    const base = Date.now() - 3_600_000;
    const rows = Array.from({ length: MESSAGES_PAGE_SIZE * 2 + 7 }, (_, i) => ({
      match_id: paged,
      sender_id: i % 2 ? ben.id : cal.id,
      body: `message ${i}`,
      moderation: 'passed' as const,
      created_at: new Date(base + Math.floor(i / 3)).toISOString().replace('Z', `${i % 3}00Z`),
    }));
    const { error } = await world.admin.from('messages').insert(rows);
    expect(error).toBeNull();

    const seen: string[] = [];
    let before: string | undefined;
    for (let n = 0; n < 10; n++) {
      const p = await page(ben, paged, before ? { before } : {});
      expect(p.messages.length).toBeLessThanOrEqual(MESSAGES_PAGE_SIZE);
      const times = p.messages.map((m) => Date.parse(m.createdAt));
      expect([...times].sort((x, y) => x - y)).toEqual(times);
      seen.unshift(...p.messages.map((m) => m.body));
      if (!p.hasMore) {
        expect(p.nextBefore).toBeUndefined();
        break;
      }
      before = p.nextBefore;
    }
    expect(seen).toEqual(rows.map((r) => r.body));

    // A page never ends in the middle of a millisecond, so it can be a little short. The
    // newest millisecond here holds 2 messages and the next 3, so a page of 5 would end
    // inside the second one: it stops after the first 2, and those 3 come on the next page.
    const small = await page(ben, paged, { limit: '5' });
    expect(small.messages.map((m) => m.body)).toEqual(seen.slice(-2));
    expect(small.hasMore).toBe(true);
    const rest = await page(ben, paged, { limit: '5', before: small.nextBefore! });
    expect(rest.messages.map((m) => m.body)).toEqual(seen.slice(-5, -2));
    expect((await world.list(ben, paged, { limit: '51' })).status).toBe(400);
    expect((await world.list(ben, paged, { before: 'yesterday' })).status).toBe(400);
  });

  it('rate limits sending', async () => {
    const busy = await world.match(room, ana, cal);
    for (let i = 0; i < 30; i++) expect((await send(ana, busy, `n${i}`)).status).toBe(201);
    const res = await send(ana, busy, 'one too many');
    expect(res.status).toBe(429);
    expect(Number(res.headers.get('retry-after'))).toBeGreaterThan(0);
    await world.unmatch(ana, busy);
  });

  it('after a block, neither person can read or send', async () => {
    const blocked = paged;
    await sent(cal, blocked, 'hey');
    const { error } = await world.admin.rpc('block_user', {
      p_user_id: ben.id,
      p_context: 'chat',
      p_context_id: blocked,
    });
    expect(error).toBeNull();
    for (const p of [ben, cal]) {
      expect((await send(p, blocked, 'are you there?')).status).toBe(404);
      expect((await world.list(p, blocked)).status).toBe(404);
    }
    expect(await world.rows(blocked)).toEqual([]);
  });

  it('unmatch removes the thread for both, tells both, and then answers 404', async () => {
    const before = await page(ben, thread);
    expect(before.messages.length).toBeGreaterThan(0);

    const res = await world.unmatch(ben, thread);
    expect(res.status).toBe(204);
    expect(await res.text()).toBe('');
    expect(events()).toEqual([
      { to: [ana.id, ben.id].sort(), event: { type: 'match.ended', matchId: thread } },
    ]);
    expect(await world.rows(thread)).toEqual([]);

    for (const p of [ana, ben]) {
      expect((await world.list(p, thread)).status).toBe(404);
      expect((await send(p, thread, 'still there?')).status).toBe(404);
      expect((await world.unmatch(p, thread)).status).toBe(404);
    }
  });
});
