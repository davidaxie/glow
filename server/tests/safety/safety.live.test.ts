/**
 * B8 against a real local Supabase (see ./helpers/live.ts for which one). Covers the
 * Done-when boxes: blocks remove both people from each other's decks within 5 seconds (P7),
 * pause does the same for one person (P8), account deletion leaves no rows or files, and
 * expired cards and their photos are purged (P9).
 */
import { randomUUID } from 'node:crypto';
import { NextRequest } from 'next/server';
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { LOCAL_ENV } from '../helpers/env';
import { LIVE, useLiveEnv, type Live } from './helpers/live';
import { World, type Card, type Person } from './helpers/world';

const sent = vi.hoisted(() => ({
  user: [] as { userIds: readonly string[]; event: { type: string } }[],
  room: [] as { roomId: string; event: { type: string } }[],
}));

vi.mock('@/server/safety/dependencies', () => ({
  notify: vi.fn(async (userIds: string | readonly string[], event: { type: string }) => {
    sent.user.push({ userIds: typeof userIds === 'string' ? [userIds] : userIds, event });
    return { realtime: 'sent', push: null };
  }),
  notifyRoom: vi.fn(async (roomId: string, event: { type: string }) => {
    sent.room.push({ roomId, event });
    return { realtime: 'sent', push: null };
  }),
}));

const live = LIVE as Live;
let world: World;

beforeAll(() => {
  if (LIVE) world = new World(LIVE);
});
beforeEach(() => {
  if (LIVE) useLiveEnv(LIVE);
  sent.user.length = 0;
  sent.room.length = 0;
});
afterAll(async () => {
  if (LIVE) await world.cleanup();
});

type Handler = (
  req: NextRequest,
  ctx: { params: Promise<Record<string, string>> },
) => Promise<Response>;

async function call(handler: Handler, path: string, token: string | null, body?: unknown) {
  const headers: Record<string, string> = {};
  if (token) headers.authorization = `Bearer ${token}`;
  if (body !== undefined) headers['content-type'] = 'application/json';
  const req = new NextRequest(`http://localhost${path}`, {
    method: body === undefined ? (path.startsWith('/api/me') ? 'DELETE' : 'GET') : 'POST',
    headers,
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  return handler(req, { params: Promise.resolve({}) });
}

async function routes() {
  const [blocks, reports, pause, capture, me, purge] = await Promise.all([
    import('../../app/api/blocks/route'),
    import('../../app/api/reports/route'),
    import('../../app/api/me/pause/route'),
    import('../../app/api/abuse/capture/route'),
    import('../../app/api/me/route'),
    import('../../app/api/cron/purge/route'),
  ]);
  return {
    block: blocks.POST as Handler,
    report: reports.POST as Handler,
    pause: pause.POST as Handler,
    capture: capture.POST as Handler,
    deleteMe: me.DELETE as Handler,
    purge: purge.GET as Handler,
  };
}

/** Two people who can see each other, checked into one room, each shown the other's card. */
async function pair() {
  const roomId = await world.room();
  const a = await world.person('woman', ['man']);
  const b = await world.person('man', ['woman']);
  const aCard = await world.checkIn(a, roomId);
  const bCard = await world.checkIn(b, roomId);
  expect(await world.deck(a, roomId)).toContain(bCard.id);
  expect(await world.deck(b, roomId)).toContain(aCard.id);
  return { roomId, a, b, aCard, bCard };
}

describe.skipIf(!LIVE)('blocks (P7)', () => {
  it('removes both people from each other’s decks at once, and tells the room', async () => {
    const { roomId, a, b, aCard, bCard } = await pair();
    const { block } = await routes();

    const started = performance.now();
    const res = await call(block, '/api/blocks', a.token, { context: 'card', contextId: bCard.id });
    expect(res.status).toBe(204);
    const [aDeck, bDeck] = await Promise.all([world.deck(a, roomId), world.deck(b, roomId)]);
    const elapsed = performance.now() - started;

    expect(aDeck).not.toContain(bCard.id);
    expect(bDeck).not.toContain(aCard.id);
    expect(elapsed).toBeLessThan(5000);
    expect(sent.room).toContainEqual({ roomId, event: { type: 'deck.changed', roomId } });
  });

  it('ends their match and glow, and sends match.ended to both, from a chat ID', async () => {
    const { a, b, aCard, bCard } = await pair();
    const matchId = await world.match(a, aCard, b, bCard);
    const { block } = await routes();

    const res = await call(block, '/api/blocks', b.token, { context: 'chat', contextId: matchId });
    expect(res.status).toBe(204);
    const { data } = await world.db.from('matches').select('status').eq('id', matchId).single();
    expect(data?.status).toBe('ended');
    const ended = sent.user.find((s) => s.event.type === 'match.ended');
    expect(ended?.event).toEqual({ type: 'match.ended', matchId });
    expect([...(ended?.userIds ?? [])].sort()).toEqual([a.id, b.id].sort());
  });

  it('answers 404 for a card the deck never showed, and 401 without sign-in', async () => {
    const roomId = await world.room();
    const a = await world.person();
    const c = await world.person();
    const cCard = await world.checkIn(c, roomId);
    const { block } = await routes();
    const unseen = await call(block, '/api/blocks', a.token, { context: 'card', contextId: cCard.id });
    expect(unseen.status).toBe(404);
    const made = await call(block, '/api/blocks', a.token, {
      context: 'match',
      contextId: randomUUID(),
    });
    expect(made.status).toBe(404);
    const anon = await call(block, '/api/blocks', null, { context: 'card', contextId: cCard.id });
    expect(anon.status).toBe(401);
    // Nothing about the other person in any answer (P1).
    expect(await unseen.text()).not.toContain(c.id);
  });
});

describe.skipIf(!LIVE)('reports', () => {
  it('reports and blocks, keeping only the reported person’s last messages', async () => {
    const { roomId, a, b, aCard, bCard } = await pair();
    const matchId = await world.match(a, aCard, b, bCard);
    await world.db.from('matches').update({ status: 'chatting' }).eq('id', matchId);
    for (const [sender, body] of [
      [b, 'hello from b'],
      [a, 'hello from a'],
      [b, 'second from b'],
    ] as const) {
      await world.db.rpc('send_message', { p_sender_id: sender.id, p_match_id: matchId, p_body: body });
    }
    const { report } = await routes();
    const res = await call(report, '/api/reports', a.token, {
      context: 'chat',
      contextId: matchId,
      reason: 'harassment',
      details: '  kept being rude  ',
    });
    expect(res.status).toBe(204);

    const { data: rows } = await world.db
      .from('reports')
      .select('reported_id, reason, details, evidence, room_id')
      .eq('reporter_id', a.id);
    expect(rows).toHaveLength(1);
    expect(rows?.[0]).toMatchObject({
      reported_id: b.id,
      reason: 'harassment',
      details: 'kept being rude',
      room_id: roomId,
    });
    const evidence = (rows?.[0]?.evidence ?? []) as { body: string }[];
    expect(evidence.map((m) => m.body)).toEqual(['hello from b', 'second from b']);
    expect(await world.deck(a, roomId)).not.toContain(bCard.id);
    expect(sent.user.some((s) => s.event.type === 'match.ended')).toBe(true);
  });

  it('refuses details over REPORT_DETAILS_MAX_CHARS', async () => {
    const { a, bCard } = await pair();
    const { report } = await routes();
    const res = await call(report, '/api/reports', a.token, {
      context: 'card',
      contextId: bCard.id,
      reason: 'other',
      details: 'x'.repeat(1001),
    });
    expect(res.status).toBe(400);
  });
});

describe.skipIf(!LIVE)('pause (P8)', () => {
  it('hides a paused person from every deck at once, and brings them back', async () => {
    const { roomId, a, b, aCard } = await pair();
    const { pause } = await routes();

    const paused = await call(pause, '/api/me/pause', a.token, { paused: true });
    expect(paused.status).toBe(200);
    expect(await paused.json()).toEqual({ paused: true });
    expect(await world.deck(b, roomId)).not.toContain(aCard.id);
    expect(sent.room).toContainEqual({ roomId, event: { type: 'deck.changed', roomId } });

    // Saying it again changes nothing and tells nobody.
    sent.room.length = 0;
    expect(await (await call(pause, '/api/me/pause', a.token, { paused: true })).json()).toEqual({
      paused: true,
    });
    expect(sent.room).toHaveLength(0);

    const resumed = await call(pause, '/api/me/pause', a.token, { paused: false });
    expect(await resumed.json()).toEqual({ paused: false });
    expect(await world.deck(b, roomId)).toContain(aCard.id);
  });
});

describe.skipIf(!LIVE)('capture logging', () => {
  it('keeps the room only when the person is checked in there', async () => {
    const { roomId, a } = await pair();
    const { capture } = await routes();
    const other = randomUUID();
    expect((await call(capture, '/api/abuse/capture', a.token, { kind: 'screenshot', roomId })).status).toBe(204);
    expect(
      (await call(capture, '/api/abuse/capture', a.token, { kind: 'recording', roomId: other }))
        .status,
    ).toBe(204);
    const { data } = await world.db
      .from('abuse_signals')
      .select('room_id, kind')
      .eq('user_id', a.id)
      .order('created_at');
    expect(data).toEqual([
      { room_id: roomId, kind: 'screenshot' },
      { room_id: null, kind: 'recording' },
    ]);
  });
});

describe.skipIf(!LIVE)('delete account', () => {
  it('leaves no rows, files or auth records for that person', async () => {
    const { roomId, a, b, aCard, bCard } = await pair();
    const matchId = await world.match(a, aCard, b, bCard);
    await world.db.from('matches').update({ status: 'chatting' }).eq('id', matchId);
    await world.db.rpc('send_message', { p_sender_id: a.id, p_match_id: matchId, p_body: 'hi' });
    await world.db.rpc('send_message', { p_sender_id: b.id, p_match_id: matchId, p_body: 'hey' });

    // Everything else a person can leave behind.
    const photoId = randomUUID();
    const photoPath = `${a.id}/${photoId}.jpg`;
    const jpeg = Buffer.from(await (await import('sharp')).default({
      create: { width: 8, height: 10, channels: 3, background: '#888' },
    }).jpeg().toBuffer());
    await world.db.storage.from('profile-photos').upload(photoPath, jpeg, { contentType: 'image/jpeg' });
    await world.db
      .from('profile_photos')
      .insert({ id: photoId, user_id: a.id, path: photoPath, position: 0, moderation_status: 'approved' });
    await world.db.from('devices').insert({
      user_id: a.id,
      apns_token: 'ab'.repeat(32),
      apns_environment: 'sandbox',
    });
    await world.db.from('abuse_signals').insert({ user_id: a.id, room_id: roomId, kind: 'screenshot' });
    const c = await world.person('man', ['woman']);
    const cCard = await world.checkIn(c, roomId);
    await world.deck(a, roomId);
    await world.db.rpc('create_report', {
      p_reporter_id: a.id,
      p_context: 'card',
      p_context_id: cCard.id,
      p_reason: 'spam',
    });

    const { deleteMe } = await routes();
    const res = await call(deleteMe, '/api/me', a.token);
    expect(res.status).toBe(204);

    // Every uuid column of every table (from PostgREST's own schema), for every ID of theirs.
    const ids = [a.id, aCard.id, photoId, matchId];
    const leftovers = await rowsMentioning(live, ids);
    expect(leftovers).toEqual([]);

    expect(await world.objectExists('room-cards', aCard.path)).toBe(false);
    expect(await world.objectExists('profile-photos', photoPath)).toBe(false);
    const user = await world.db.auth.admin.getUserById(a.id);
    expect(user.data.user).toBeNull();
    // Supabase Auth's audit log no longer names them (running it again finds nothing).
    const traces = await world.db.rpc('forget_account_traces', { p_user_id: a.id });
    expect(traces.data).toEqual({ auditEntries: 0, realtimeMessages: 0 });
    // The other person keeps their own card, and was told the match ended.
    expect(await world.objectExists('room-cards', bCard.path)).toBe(true);
    expect(sent.user).toContainEqual({ userIds: [b.id], event: { type: 'match.ended', matchId } });
    // Their old token stops working at once.
    expect((await call(deleteMe, '/api/me', a.token)).status).toBe(401);
  });
});

describe.skipIf(!LIVE)('purge (P9)', () => {
  const cron = () => LOCAL_ENV.CRON_SECRET;

  it('deletes expired cards and their photos, and tells the room', async () => {
    const roomId = await world.room();
    const a = await world.person();
    const card = await world.checkIn(a, roomId);
    expect(await world.objectExists('room-cards', card.path)).toBe(true);
    await expire(card);

    const { purge } = await routes();
    const res = await call(purge, '/api/cron/purge', cron());
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.checkinsDeleted).toBeGreaterThanOrEqual(1);
    expect(body.cardPhotosDeleted).toBeGreaterThanOrEqual(1);

    const { data } = await world.db.from('checkins').select('id').eq('id', card.id);
    expect(data).toEqual([]);
    expect(await world.objectExists('room-cards', card.path)).toBe(false);
    expect(sent.room).toContainEqual({ roomId, event: { type: 'deck.changed', roomId } });
  });

  it('warns about a check-in ending soon exactly once', async () => {
    const roomId = await world.room();
    const a = await world.person();
    const card = await world.checkIn(a, roomId);
    await world.db
      .from('checkins')
      .update({ expires_at: new Date(Date.now() + 10 * 60_000).toISOString() })
      .eq('id', card.id);
    const { purge } = await routes();
    await call(purge, '/api/cron/purge', cron());
    await call(purge, '/api/cron/purge', cron());
    const warnings = sent.user.filter(
      (s) => s.event.type === 'checkin.expiring' && s.userIds.includes(a.id),
    );
    expect(warnings).toEqual([
      { userIds: [a.id], event: { type: 'checkin.expiring', roomId } },
    ]);
  });

  it('sweeps photos whose row is gone, but not ones still being uploaded', async () => {
    const roomId = await world.room();
    const orphan = `${roomId}/${randomUUID()}.jpg`;
    const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xd9]);
    await world.db.storage.from('room-cards').upload(orphan, jpeg, { contentType: 'image/jpeg' });
    const { sweepOrphans } = await import('@/server/safety/storage');
    await sweepOrphans(); // younger than the grace period: kept
    expect(await world.objectExists('room-cards', orphan)).toBe(true);
    await sweepOrphans(Date.now() + 3 * 60_000);
    expect(await world.objectExists('room-cards', orphan)).toBe(false);
  });

  it('refuses anyone without the cron secret', async () => {
    const { purge } = await routes();
    expect((await call(purge, '/api/cron/purge', null)).status).toBe(401);
    expect((await call(purge, '/api/cron/purge', 'not-the-secret')).status).toBe(401);
  });

  async function expire(card: Card) {
    const { error } = await world.db
      .from('checkins')
      .update({
        joined_at: new Date(Date.now() - 4 * 3600_000).toISOString(),
        expires_at: new Date(Date.now() - 60_000).toISOString(),
      })
      .eq('id', card.id);
    if (error) throw new Error(error.message);
  }
});

/** Rows in any public table whose uuid columns hold one of `ids`. */
async function rowsMentioning(live: Live, ids: readonly string[]) {
  const res = await fetch(`${live.url}/rest/v1/`, {
    headers: { apikey: live.serviceKey, authorization: `Bearer ${live.serviceKey}` },
  });
  const spec = (await res.json()) as {
    definitions: Record<string, { properties: Record<string, { format?: string }> }>;
  };
  const found: string[] = [];
  for (const [table, def] of Object.entries(spec.definitions)) {
    const columns = Object.entries(def.properties)
      .filter(([, p]) => p.format === 'uuid')
      .map(([name]) => name);
    if (columns.length === 0) continue;
    const filter = columns.flatMap((col) => ids.map((id) => `${col}.eq.${id}`)).join(',');
    const rows = await world.db
      .from(table as 'profiles')
      .select('*')
      .or(filter)
      .limit(5);
    if (rows.error) throw new Error(`${table}: ${rows.error.message}`);
    if ((rows.data ?? []).length > 0) found.push(table);
  }
  return found;
}

export type { Person };
