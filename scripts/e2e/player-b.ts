#!/usr/bin/env node
// Owner: D1. Plays person B through the Glow API, so a UI test (or a person) on Glow A has
// someone to notice: test sign-in, join, check in, tap, choose, glow, We met, chat, block.
//
//   node scripts/e2e/player-b.ts                          # the full loop in the demo room
//   node scripts/e2e/player-b.ts --steps join,checkin,tap,match,chat,say,read
//   node scripts/e2e/player-b.ts --control 4121           # wait for a UI test's instructions
//   node scripts/e2e/player-b.ts --help
//
// Every reply B gets is checked for person A's user ID, and for A's first name outside the match
// routes (P1), when --watch-user and --watch-name say who A is. Any sighting fails the run.
//
// Prints one JSON line per step on stdout. Exits 0 when every step passed, 1 when one failed,
// 2 for bad arguments, 3 when a step needs a route that isn't built yet (it answers 501).

import { readFileSync } from 'node:fs';
import { createServer, type IncomingMessage, type ServerResponse } from 'node:http';
import { pathToFileURL } from 'node:url';
import { parseArgs } from 'node:util';
import {
  ApiError,
  DEFAULT_PHOTO,
  DEMO_ROOM,
  freshEmail,
  loadEnv,
  note,
  onboardedPerson,
  venueFix,
  waitFor,
  type Glow,
  type MatchDetail,
  type MyCheckin,
  type Person,
  type TapResult,
} from './glow.ts';

const USAGE = `Usage: node scripts/e2e/player-b.ts [options]

Plays person B through the API. Options:
  --api URL            the API (default $GLOW_API, else http://localhost:3000)
  --slug SLUG          the room's slug (default demo)
  --token TOKEN        the room's QR token (default the demo room's poster token)
  --lat N --lng N      where B stands (default the demo room's center)
  --email EMAIL        B's test address (default a fresh b-xxxxxxxx@glow.test)
  --name NAME          B's first name (default Brook)
  --gender G           woman, man or nonbinary (default man)
  --show-me LIST       comma-separated genders B wants to see (default woman)
  --photo PATH         B's outfit photo (default ios/fixtures/photos/outfit-real-blue-flightsuit.jpg)
  --card ID            the card B taps (default the first card in B's deck)
  --steps LIST         what B does, in order (default ${'join,checkin,tap,match,find,glow,met,metboth'})
                         join      resolve the room link and pass the location check
                         checkin   check in with the photo
                         tap       wait for a card in the deck, look at it, tap it
                         match     wait for the mutual match
                         find      choose Find each other (with a fresh location fix)
                         chat      choose Just chat
                         glow      wait for the glow to start
                         met       tap We met
                         metboth   wait until both tapped We met
                         say       send a chat message (--say TEXT)
                         read      wait for a message from A (--expect TEXT, else any)
                         block     block A from the chat
                         unmatch   unmatch A
                         ended     wait until the match has ended (A blocked or unmatched)
                         leave     leave the room
  --say TEXT           what B says (default "Hi, it's me by the window.")
  --expect TEXT        the message B waits for
  --timeout SECONDS    how long each waiting step waits (default 90)
  --control PORT       instead of --steps: join and check in, then take instructions over HTTP
                       on 127.0.0.1:PORT (GET /state, POST /do/<step>), for UI tests
  --watch-user ID      person A's user ID: must never reach B (P1)
  --watch-name NAME    person A's first name: must never reach B outside a match (P1)
  --help`;

type Room = { id: string; slug: string; token: string; latitude: number; longitude: number };

export type PlayerState = {
  step: string;
  roomId?: string;
  cardId?: string;
  tappedCardId?: string;
  tapsLeftToday?: number;
  matchId?: string;
  matchStatus?: MatchDetail['status'];
  glow?: Pick<Glow, 'status' | 'color' | 'codeWord'> & { meetingSpot?: string };
  messages?: string[];
  violations: string[];
};

const STEPS = [
  'join',
  'checkin',
  'tap',
  'match',
  'find',
  'chat',
  'glow',
  'met',
  'metboth',
  'say',
  'read',
  'block',
  'unmatch',
  'ended',
  'leave',
] as const;
type Step = (typeof STEPS)[number];

export function isStep(value: string): value is Step {
  return (STEPS as readonly string[]).includes(value);
}

export class PlayerB {
  readonly person: Person;
  readonly room: Room;
  readonly photo: Buffer;
  readonly timeoutMs: number;
  cardToTap: string | undefined;
  sayText = "Hi, it's me by the window.";
  expectText: string | undefined;
  state: PlayerState = { step: 'signed-in', violations: [] };
  private checkin: MyCheckin | undefined;

  constructor(person: Person, room: Room, photo: Buffer, timeoutMs: number) {
    this.person = person;
    this.room = room;
    this.photo = photo;
    this.timeoutMs = timeoutMs;
  }

  private where() {
    return venueFix(this.room.latitude, this.room.longitude);
  }

  private matchId(): string {
    if (!this.state.matchId) throw new Error('no match yet (run the match step first)');
    return this.state.matchId;
  }

  private set(step: string, extra: Partial<PlayerState> = {}): PlayerState {
    this.state = { ...this.state, ...extra, step, violations: [...this.person.watch.violations] };
    return this.state;
  }

  async run(step: Step): Promise<PlayerState> {
    switch (step) {
      case 'join': {
        const summary = await this.person.resolveLink(this.room.slug, this.room.token);
        this.room.id = summary.id;
        await this.person.join(summary.id, this.room.slug, this.room.token, this.where());
        return this.set('joined', { roomId: summary.id });
      }
      case 'checkin': {
        if (!this.state.roomId) await this.run('join');
        // A fresh join each time: the ticket lasts JOIN_TICKET_TTL and check-in needs a recent pass.
        const ticket = await this.person.join(this.room.id, this.room.slug, this.room.token, this.where());
        this.checkin = await this.person.checkIn(this.room.id, ticket.ticket, this.photo, {
          topColor: 'blue',
          hairLength: 'short',
          hairColor: 'brown',
          extras: [],
        });
        return this.set('checked-in', { cardId: this.checkin.cardId });
      }
      case 'tap': {
        const card = await waitFor(
          this.cardToTap ? `card ${this.cardToTap} in B's deck` : "someone's card in B's deck",
          async () => {
            const deck = await this.person.deck(this.room.id);
            return deck.cards.find((c) => (this.cardToTap ? c.id === this.cardToTap : true));
          },
          this.timeoutMs,
        );
        // Look at it the way the app does: a 60-second link, with B's own token (P4).
        await this.person.fetchImage(card.image.url);
        const result: TapResult = await this.person.tap(this.room.id, card.id);
        return this.set(result.result === 'mutual' ? 'matched' : 'tapped', {
          tappedCardId: card.id,
          tapsLeftToday: result.tapsLeftToday,
          ...(result.matchId ? { matchId: result.matchId } : {}),
        });
      }
      case 'match': {
        const matchId =
          this.state.matchId ??
          (await waitFor(
            'the mutual match',
            async () => (await this.person.matches()).matches.find((m) => m.status === 'choosing')?.id,
            this.timeoutMs,
          ));
        const match = await this.person.match(matchId);
        return this.set('matched', { matchId, matchStatus: match.status });
      }
      case 'find': {
        const result = await this.person.choose(this.matchId(), 'find', this.where());
        return this.set(`chose-find:${result.next}`, { matchStatus: result.match.status });
      }
      case 'chat': {
        const result = await this.person.choose(this.matchId(), 'chat');
        return this.set(`chose-chat:${result.next}`, { matchStatus: result.match.status });
      }
      case 'glow': {
        const glow = await waitFor(
          'the glow to start',
          async () => {
            const match = await this.person.match(this.matchId());
            return match.status === 'glowing' ? (match.glow ?? (await this.person.glow(this.matchId()))) : undefined;
          },
          this.timeoutMs,
        );
        return this.set('glowing', { matchStatus: 'glowing', glow: summarizeGlow(glow) });
      }
      case 'met': {
        const glow = await this.person.met(this.matchId());
        return this.set('said-met', { glow: summarizeGlow(glow) });
      }
      case 'metboth': {
        const glow = await waitFor(
          'both to tap We met',
          async () => {
            const current = await this.person.glow(this.matchId());
            return current.status === 'met' ? current : undefined;
          },
          this.timeoutMs,
        );
        const match = await this.person.match(this.matchId());
        return this.set('met', { glow: summarizeGlow(glow), matchStatus: match.status });
      }
      case 'say': {
        await waitFor(
          'the chat to open',
          async () => {
            const match = await this.person.match(this.matchId());
            return match.status === 'chatting' || match.status === 'met' ? true : undefined;
          },
          this.timeoutMs,
        );
        await this.person.send(this.matchId(), this.sayText);
        return this.set('said', { messages: await this.readAll() });
      }
      case 'read': {
        const expected = this.expectText;
        await waitFor(
          expected ? `"${expected}" from A` : 'a message from A',
          async () => {
            const page = await this.person.messages(this.matchId());
            return page.messages.find((m) => !m.fromMe && (expected ? m.body === expected : true));
          },
          this.timeoutMs,
        );
        return this.set('read', { messages: await this.readAll() });
      }
      case 'block': {
        await this.person.block('chat', this.matchId());
        return this.set('blocked');
      }
      case 'unmatch': {
        await this.person.unmatch(this.matchId());
        return this.set('unmatched');
      }
      case 'ended': {
        const matchId = this.matchId();
        await waitFor(
          'the match to end',
          async () => {
            const list = await this.person.matches();
            return list.matches.some((m) => m.id === matchId) ? undefined : true;
          },
          this.timeoutMs,
        );
        // P7: after a block or unmatch, nothing about the match is reachable any more.
        try {
          await this.person.match(matchId);
          throw new Error('the ended match still answers getMatch');
        } catch (error) {
          if (!(error instanceof ApiError && error.status === 404)) throw error;
        }
        return this.set('ended', { matchStatus: undefined });
      }
      case 'leave': {
        await this.person.leave(this.room.id);
        return this.set('left');
      }
    }
  }

  private async readAll(): Promise<string[]> {
    const page = await this.person.messages(this.matchId());
    return page.messages.map((m) => `${m.fromMe ? 'B' : 'A'}: ${m.body}`);
  }
}

function summarizeGlow(glow: Glow): NonNullable<PlayerState['glow']> {
  return {
    status: glow.status,
    color: glow.color,
    codeWord: glow.codeWord,
    ...(glow.meetingSpot ? { meetingSpot: glow.meetingSpot.name } : {}),
  };
}

function print(state: PlayerState): void {
  process.stdout.write(`${JSON.stringify(state)}\n`);
}

function exitCodeFor(error: unknown): number {
  return error instanceof ApiError && error.isStub ? 3 : 1;
}

// ---------------------------------------------------------------------------------- control mode

/**
 * Takes instructions from a UI test: `POST /do/tap`, `POST /do/find`, and so on, each answering
 * B's state after the step, or `{ error }` with status 409 (step failed) or 501 (not built yet).
 * `GET /state` answers the current state. `POST /quit` stops. Listens on 127.0.0.1 only.
 */
function serve(player: PlayerB, port: number): Promise<number> {
  return new Promise((resolve) => {
    let queue: Promise<unknown> = Promise.resolve();
    let failed = false;
    const reply = (res: ServerResponse, status: number, body: unknown) => {
      res.writeHead(status, { 'content-type': 'application/json', 'cache-control': 'no-store' });
      res.end(JSON.stringify(body));
    };
    const server = createServer((req: IncomingMessage, res: ServerResponse) => {
      const url = new URL(req.url ?? '/', 'http://127.0.0.1');
      if (req.method === 'GET' && url.pathname === '/state') return reply(res, 200, player.state);
      if (req.method === 'POST' && url.pathname === '/quit') {
        reply(res, 200, player.state);
        server.close();
        return resolve(failed || player.state.violations.length > 0 ? 1 : 0);
      }
      const match = /^\/do\/([a-z]+)$/.exec(url.pathname);
      if (req.method !== 'POST' || !match?.[1] || !isStep(match[1])) {
        return reply(res, 404, { error: 'unknown instruction' });
      }
      const step = match[1];
      const say = url.searchParams.get('text');
      if (say && step === 'say') player.sayText = say;
      if (step === 'read') player.expectText = say ?? undefined;
      // One step at a time, in the order they arrive.
      queue = queue.then(async () => {
        try {
          const state = await player.run(step);
          print(state);
          reply(res, 200, state);
        } catch (error) {
          failed = true;
          const message = error instanceof Error ? error.message : String(error);
          note(`B's ${step} failed: ${message}`);
          reply(res, error instanceof ApiError && error.isStub ? 501 : 409, { error: message, state: player.state });
        }
      });
    });
    server.listen(port, '127.0.0.1', () => note(`player B is listening on http://127.0.0.1:${port}`));
  });
}

// ---------------------------------------------------------------------------------- main

async function main(): Promise<number> {
  let values;
  try {
    ({ values } = parseArgs({
      options: {
        api: { type: 'string' },
        slug: { type: 'string', default: DEMO_ROOM.slug },
        token: { type: 'string', default: DEMO_ROOM.token },
        lat: { type: 'string', default: String(DEMO_ROOM.latitude) },
        lng: { type: 'string', default: String(DEMO_ROOM.longitude) },
        email: { type: 'string' },
        name: { type: 'string', default: 'Brook' },
        gender: { type: 'string', default: 'man' },
        'show-me': { type: 'string', default: 'woman' },
        photo: { type: 'string', default: DEFAULT_PHOTO },
        card: { type: 'string' },
        steps: { type: 'string', default: 'join,checkin,tap,match,find,glow,met,metboth' },
        say: { type: 'string' },
        expect: { type: 'string' },
        timeout: { type: 'string', default: '90' },
        control: { type: 'string' },
        'watch-user': { type: 'string', multiple: true, default: [] },
        'watch-name': { type: 'string', multiple: true, default: [] },
        help: { type: 'boolean', default: false },
      },
      strict: true,
    }));
  } catch (error) {
    process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n\n${USAGE}\n`);
    return 2;
  }
  if (values.help) {
    process.stdout.write(`${USAGE}\n`);
    return 0;
  }
  const steps = values.steps.split(',').map((s) => s.trim());
  const unknown = steps.filter((s) => !isStep(s));
  const genders = ['woman', 'man', 'nonbinary'] as const;
  const gender = genders.find((g) => g === values.gender);
  const showMe = values['show-me'].split(',').map((g) => genders.find((x) => x === g.trim()));
  if (unknown.length > 0 || !gender || showMe.some((g) => !g)) {
    process.stderr.write(`bad --steps, --gender or --show-me\n\n${USAGE}\n`);
    return 2;
  }

  const env = loadEnv(values.api);
  const email = values.email ?? freshEmail('b');
  const person = await onboardedPerson(env, email, {
    firstName: values.name,
    gender,
    showMe: showMe.filter((g) => g !== undefined),
  });
  for (const id of values['watch-user']) person.watch.watchUserId(id);
  for (const name of values['watch-name']) person.watch.watchName(name);

  const room: Room = {
    id: '',
    slug: values.slug,
    token: values.token,
    latitude: Number(values.lat),
    longitude: Number(values.lng),
  };
  const player = new PlayerB(person, room, readFileSync(values.photo), Number(values.timeout) * 1000);
  player.cardToTap = values.card;
  if (values.say) player.sayText = values.say;
  player.expectText = values.expect;
  print(player.state);

  if (values.control) {
    try {
      print(await player.run('join'));
      print(await player.run('checkin'));
    } catch (error) {
      note(`B couldn't get into the room: ${error instanceof Error ? error.message : String(error)}`);
      return exitCodeFor(error);
    }
    return serve(player, Number(values.control));
  }

  for (const step of steps) {
    if (!isStep(step)) continue;
    try {
      print(await player.run(step));
    } catch (error) {
      note(`B's ${step} failed: ${error instanceof Error ? error.message : String(error)}`);
      return exitCodeFor(error);
    }
  }
  if (person.watch.violations.length > 0) {
    note(`P1: B saw what it never should: ${person.watch.violations.join('; ')}`);
    return 1;
  }
  return 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().then(
    (code) => process.exit(code),
    (error: unknown) => {
      note(error instanceof Error ? error.message : String(error));
      process.exit(1);
    },
  );
}
