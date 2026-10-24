/**
 * D2's red-team journey through the real route handlers, on a live local stack.
 *
 *   P1  Before a mutual match, nothing a person receives (any API reply, any event)
 *       contains another person's user ID, name, email or profile photo path.
 *   P5  A one-sided tap changes nothing the tapped person can see: replies, counts, events.
 *   P7  A block applies both ways at once: deck, taps, card images, match and chat.
 *   P11 Somebody else's thing answers exactly like a thing that doesn't exist: 404,
 *       the same body, never 403.
 *
 * Every reply is kept in `journal` and scanned at the end as well.
 */
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { resetEnvCacheForTests } from '@/env';
import { call, isStub, journal } from './helpers/api';
import { LIVE, type Live } from './helpers/live';
import { World, type Card, type Person } from './helpers/world';

const sent = vi.hoisted(() => ({ events: [] as { to: unknown; event: unknown }[] }));
vi.mock('@/server/notify', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@/server/notify')>();
  return {
    ...actual,
    notify: vi.fn(async (to: unknown, event: unknown) => {
      sent.events.push({ to, event });
      return { realtime: 'sent', push: null };
    }),
    notifyRoom: vi.fn(async (to: unknown, event: unknown) => {
      sent.events.push({ to, event });
      return { realtime: 'sent', push: null };
    }),
  };
});

const live = LIVE as Live;
let world: World;
let roomId: string;
let alex: Person; // woman, shows men
let blake: Person; // man, shows women
let casey: Person; // man, shows women: taps Alex, one-sided
let alexCard: Card;
let blakeCard: Card;
let caseyCard: Card;

const uuidsIn = (text: string) =>
  [...text.matchAll(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi)].map((m) =>
    m[0].toLowerCase(),
  );

/** Anything in `text` that identifies `other`. */
function leaks(text: string, other: Person): string[] {
  const found: string[] = [];
  const lower = text.toLowerCase();
  if (lower.includes(other.id)) found.push('user id');
  if (lower.includes(other.email.toLowerCase())) found.push('email');
  if (text.includes(other.firstName)) found.push('first name');
  if (lower.includes(`${other.id}/`)) found.push('profile photo path');
  return found;
}

beforeAll(async () => {
  if (!LIVE) return;
  world = new World(live);
  [alex, blake, casey] = await Promise.all([
    world.person('woman', ['man']),
    world.person('man', ['woman']),
    world.person('man', ['woman']),
  ]);
  roomId = await world.room();
  alexCard = await world.checkIn(alex, roomId);
  blakeCard = await world.checkIn(blake, roomId);
  caseyCard = await world.checkIn(casey, roomId);
}, 60_000);

beforeEach(() => {
  if (!LIVE) return;
  process.env.SUPABASE_URL = live.url;
  process.env.SUPABASE_ANON_KEY = live.anonKey;
  process.env.SUPABASE_SERVICE_ROLE_KEY = live.serviceKey;
  resetEnvCacheForTests();
});

afterAll(async () => {
  if (LIVE) await world.cleanup();
});

const deck = (who: Person) =>
  call('getDeck', { token: who.token, params: { id: roomId }, body: {} });
const roomState = (who: Person) =>
  call('getRoomState', { token: who.token, params: { id: roomId } });
const matches = (who: Person) => call('listMatches', { token: who.token });

describe.skipIf(!LIVE)('red-team journey (live)', () => {
  it('P1: before any match, nobody sees anyone else', async () => {
    const replies = [
      await deck(alex),
      await deck(blake),
      await deck(casey),
      await roomState(alex),
      await roomState(blake),
      await matches(alex),
      await matches(blake),
    ];
    for (const reply of replies) expect(reply.status).toBeLessThan(500);
    const alexDeck = replies[0]!.json as { cards: { id: string }[] };
    expect(alexDeck.cards.map((c) => c.id).sort()).toEqual([blakeCard.id, caseyCard.id].sort());
    for (const [viewer, others] of [
      [alex, [blake, casey]],
      [blake, [alex, casey]],
      [casey, [alex, blake]],
    ] as const) {
      for (const other of others) {
        for (const entry of journal)
          expect(leaks(entry.text, other), entry.operationId).toEqual([]);
      }
      expect(viewer).toBeDefined();
    }
  });

  it('P1: card image links carry no user ID, and the image route checks the viewer', async (ctx) => {
    const page = (await deck(alex)).json as { cards: { id: string; image: { url: string } }[] };
    const card = page.cards.find((c) => c.id === blakeCard.id)!;
    expect(uuidsIn(card.image.url)).toEqual([blakeCard.id]);
    if (await isStub('getCardImage')) ctx.skip();
    const mine = await call('getCardImage', {
      token: alex.token,
      params: { cardId: blakeCard.id },
      url: card.image.url,
    });
    expect(mine.status).toBe(200);
    expect(mine.headers.get('cache-control')).toMatch(/no-store/);
    // P4: the same link is useless to anyone else, and an edited one is useless to everyone.
    const reused = await call('getCardImage', {
      token: casey.token,
      params: { cardId: blakeCard.id },
      url: card.image.url,
    });
    expect(reused.status).toBe(404);
    // An edited or missing signature never serves the image. (400 is the query check, which
    // runs before anything is looked up, so it says nothing about the card either.)
    const edited = [
      card.image.url.replace(/exp=(\d+)/, (_, n: string) => `exp=${Number(n) + 3600}`),
      card.image.url.replace(/exp=(\d+)/, (_, n: string) => `exp=${Number(n) + 1}`),
      card.image.url.replace(/sig=([^&]+)/, (_, s: string) => `sig=${s.slice(0, -2)}AA`),
      `/api/cards/${blakeCard.id}/image`,
      `/api/cards/${caseyCard.id}/image?${card.image.url.split('?')[1]}`,
    ];
    for (const url of edited) {
      const reply = await call('getCardImage', {
        token: alex.token,
        params: { cardId: url.split('/')[3]! },
        url,
      });
      expect([400, 404], url).toContain(reply.status);
    }
    const noToken = await call('getCardImage', {
      params: { cardId: blakeCard.id },
      url: card.image.url,
    });
    expect(noToken.status).toBe(401);
  });

  it('P5: a one-sided tap changes nothing the tapped person can see', async () => {
    const before = [
      (await deck(alex)).text,
      (await roomState(alex)).text,
      (await matches(alex)).text,
    ];
    sent.events.length = 0;
    const tap = await call('createTap', {
      token: casey.token,
      params: { id: roomId },
      body: { cardId: alexCard.id },
    });
    expect(tap.status).toBe(200);
    expect(tap.json).toEqual({ result: 'sent', tapsLeftToday: expect.any(Number) });
    await new Promise((r) => setTimeout(r, 200));
    expect(sent.events).toEqual([]);
    const after = [
      (await deck(alex)).text,
      (await roomState(alex)).text,
      (await matches(alex)).text,
    ];
    // The signed image links in the deck change every minute; compare without them.
    const stable = (s: string) => s.replace(/"image":\{[^}]*\}/g, '"image":{}');
    expect(after.map(stable)).toEqual(before.map(stable));

    // Tapping again is free and says the same; nothing tells Casey whether Alex tapped back.
    const again = await call('createTap', {
      token: casey.token,
      params: { id: roomId },
      body: { cardId: alexCard.id },
    });
    expect(again.json).toEqual(tap.json);
  });

  it("P11: someone else's match, missing or not, answers the same 404", async () => {
    const matchId = await world.match(alex, alexCard, blake, blakeCard);
    const nobody = '00000000-0000-4000-8000-0000000000d2';
    const ops = ['getMatch', 'listMessages', 'getMatchPhoto', 'getGlow'] as const;
    for (const op of ops) {
      if (await isStub(op)) continue;
      const params = op === 'getMatchPhoto' ? { id: matchId, n: '0' } : { id: matchId };
      const missingParams = op === 'getMatchPhoto' ? { id: nobody, n: '0' } : { id: nobody };
      const theirs = await call(op, { token: casey.token, params });
      const missing = await call(op, { token: casey.token, params: missingParams });
      expect(theirs.status, op).toBe(404);
      expect(theirs.text, op).toBe(missing.text);
      // The people in it get something else (409 chat_not_open while choosing is fine;
      // a match that hasn't glowed has no glow to get).
      if (op !== 'getGlow') {
        expect((await call(op, { token: alex.token, params })).status, op).not.toBe(404);
      }
    }
    for (const op of ['unmatch', 'markGlowMet', 'cancelGlow'] as const) {
      if (await isStub(op)) continue;
      const theirs = await call(op, { token: casey.token, params: { id: matchId } });
      const missing = await call(op, { token: casey.token, params: { id: nobody } });
      expect(theirs.status, op).toBe(404);
      expect(theirs.text, op).toBe(missing.text);
    }
    if (!(await isStub('sendMessage'))) {
      const body = { body: 'hello from D2' };
      const theirs = await call('sendMessage', {
        token: casey.token,
        params: { id: matchId },
        body,
      });
      const missing = await call('sendMessage', {
        token: casey.token,
        params: { id: nobody },
        body,
      });
      expect(theirs.status).toBe(404);
      expect(theirs.text).toBe(missing.text);
    }
    // Blocking or reporting by a match ID you're not in: the same 404 as a made-up ID.
    for (const op of ['createBlock', 'createReport'] as const) {
      const body = (contextId: string) =>
        op === 'createBlock'
          ? { context: 'match', contextId }
          : { context: 'match', contextId, reason: 'spam' };
      const theirs = await call(op, { token: casey.token, body: body(matchId) });
      const missing = await call(op, { token: casey.token, body: body(nobody) });
      expect(theirs.status, op).toBe(404);
      expect(theirs.text, op).toBe(missing.text);
    }
    // A room you never checked into reads like a room that doesn't exist.
    const otherRoom = await world.room();
    const notMine = await call('getDeck', {
      token: casey.token,
      params: { id: otherRoom },
      body: {},
    });
    const noRoom = await call('getDeck', { token: casey.token, params: { id: nobody }, body: {} });
    expect(notMine.status).toBe(404);
    expect(notMine.text).toBe(noRoom.text);
    expect(journal.filter((e) => e.status === 403)).toEqual([]);
  });

  it('P1 after the match: only the match ID, the first name, never a user ID', async () => {
    const list = await matches(alex);
    expect(list.text).toContain(blake.firstName);
    expect(list.text.toLowerCase()).not.toContain(blake.id);
    expect(list.text.toLowerCase()).not.toContain(alex.id);
    for (const entry of journal) {
      expect(entry.text.toLowerCase(), entry.operationId).not.toContain(casey.id);
      for (const id of [alex.id, blake.id]) expect(entry.text.toLowerCase()).not.toContain(id);
    }
  });

  it('P7: a block applies both ways at once, everywhere', async () => {
    // Casey blocks Alex from the deck; Alex's tap and card image stop working too.
    const alexDeck = (await deck(alex)).json as { cards: { id: string; image: { url: string } }[] };
    const caseyLink = alexDeck.cards.find((c) => c.id === caseyCard.id)?.image.url;
    const block = await call('createBlock', {
      token: casey.token,
      body: { context: 'card', contextId: alexCard.id },
    });
    expect(block.status).toBeLessThan(300);
    const started = Date.now();
    const caseyDeck = (await deck(casey)).json as { cards: { id: string }[] };
    const alexAfter = (await deck(alex)).json as { cards: { id: string }[] };
    expect(caseyDeck.cards.map((c) => c.id)).not.toContain(alexCard.id);
    expect(alexAfter.cards.map((c) => c.id)).not.toContain(caseyCard.id);
    const tap = await call('createTap', {
      token: alex.token,
      params: { id: roomId },
      body: { cardId: caseyCard.id },
    });
    expect(tap.status).toBe(404);
    if (caseyLink && !(await isStub('getCardImage'))) {
      const image = await call('getCardImage', {
        token: alex.token,
        params: { cardId: caseyCard.id },
        url: caseyLink,
      });
      expect(image.status).toBe(404);
    }
    expect(Date.now() - started).toBeLessThan(5000);
  });
});
