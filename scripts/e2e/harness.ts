#!/usr/bin/env node
// Owner: D1. Setup and teardown for the end-to-end journeys, on the local stack only.
//
//   node scripts/e2e/harness.ts room                      # a fresh room of the run's own (JSON)
//   node scripts/e2e/harness.ts end-room <roomId>         # end it (deletes its cards)
//   node scripts/e2e/harness.ts person a --name Avery --gender woman --show-me man
//   node scripts/e2e/harness.ts expire <accessToken> <roomId>   # expire that check-in, run purge
//
// `room` makes the room through B7's admin API as admin@glow.test, centred on the demo room's
// spot, so `scripts/sim.sh at venue` stands inside it. A room per run means a journey's deck holds
// only the people in that run, however many runs came before (D1-D1).

import { execFile } from 'node:child_process';
import { existsSync } from 'node:fs';
import { createServer, type IncomingMessage, type ServerResponse } from 'node:http';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { parseArgs } from 'node:util';
import {
  DEMO_ROOM,
  ROOT,
  Person,
  freshEmail,
  loadEnv,
  note,
  onboardedPerson,
  serviceRest,
  signIn,
  type Env,
} from './glow.ts';

const USAGE = `Usage: node scripts/e2e/harness.ts <command> [options]

  room [--lat N --lng N]          make a fresh live room; prints { id, slug, token, code, link, ... }
  end-room ROOM_ID                end the room
  person PREFIX [--name N --gender G --show-me LIST]
                                  a fresh onboarded test person; prints { email, userId, accessToken }
  expire ACCESS_TOKEN ROOM_ID     end that person's check-in as if its time ran out, then run purge
  serve --port P [--udid U] [--token T --room R]
                                  the helper UI tests call: POST /push/<fixture>, POST /expire
  --api URL                       the API (default $GLOW_API, else http://localhost:3000)`;

const ADMIN_EMAIL = 'admin@glow.test';
const BUNDLE_ID = 'com.davidxie.glow';

async function admin(env: Env): Promise<Person> {
  return new Person(env, await signIn(env, ADMIN_EMAIL));
}

export async function makeRoom(env: Env, latitude: number, longitude: number) {
  const id = crypto.randomUUID().slice(0, 8);
  const now = Date.now();
  const room = await (
    await admin(env)
  ).createRoom({
    slug: `e2e-${id}`,
    name: `End-to-end ${id} (test data)`,
    latitude,
    longitude,
    radiusM: 200,
    timezone: 'America/Los_Angeles',
    allowStaticQr: true,
    demoMode: false,
    startsAt: new Date(now - 60_000).toISOString(),
    endsAt: new Date(now + 6 * 3600_000).toISOString(),
    spots: ['Main entrance', 'Water station', 'Stage left'],
  });
  return {
    id: room.id,
    slug: room.slug,
    token: room.staticQrToken,
    code: room.code,
    latitude: room.latitude,
    longitude: room.longitude,
    link: `glow://r/${room.slug}?t=${room.staticQrToken}`,
  };
}

async function expire(env: Env, accessToken: string, roomId: string) {
  // Who the token belongs to, through Supabase Auth, so the caller never handles a user ID.
  const who = await fetch(`${env.supabaseUrl}/auth/v1/user`, {
    headers: { apikey: env.anonKey ?? '', authorization: `Bearer ${accessToken}` },
  });
  const user = (await who.json()) as { id?: string };
  if (!who.ok || !user.id) throw new Error(`that token isn't signed in (${who.status})`);
  const past = new Date(Date.now() - 60_000).toISOString();
  const rows = (await serviceRest(
    env,
    'PATCH',
    `checkins?user_id=eq.${user.id}&room_id=eq.${roomId}&left_at=is.null`,
    { joined_at: new Date(Date.now() - 2 * 60_000).toISOString(), expires_at: past },
  )) as unknown[];
  if (!env.cronSecret) throw new Error('need CRON_SECRET (pnpm env:setup)');
  const purge = await fetch(`${env.api}/api/cron/purge`, {
    headers: { authorization: `Bearer ${env.cronSecret}` },
  });
  if (!purge.ok) throw new Error(`purge answered ${purge.status}`);
  return { expired: rows.length, purge: await purge.json() };
}

/**
 * The Mac-side helper a UI test calls for what it can't do from inside the Simulator, on
 * 127.0.0.1 only: `POST /push/<fixture>` runs `xcrun simctl push` with ios/fixtures/push/<fixture>.apns,
 * `POST /expire` ends person A's check-in (the token and room given at start), `GET /health`,
 * `POST /quit`.
 */
function serve(
  env: Env,
  port: number,
  udid: string | undefined,
  token: string | undefined,
  roomId: string | undefined,
) {
  return new Promise<number>((resolve) => {
    const reply = (res: ServerResponse, status: number, body: unknown) => {
      res.writeHead(status, { 'content-type': 'application/json', 'cache-control': 'no-store' });
      res.end(JSON.stringify(body));
    };
    const server = createServer((req: IncomingMessage, res: ServerResponse) => {
      const url = new URL(req.url ?? '/', 'http://127.0.0.1');
      const fail = (error: unknown) =>
        reply(res, 409, { error: error instanceof Error ? error.message : String(error) });
      if (req.method === 'GET' && url.pathname === '/health') return reply(res, 200, { ok: true });
      if (req.method === 'POST' && url.pathname === '/quit') {
        reply(res, 200, { ok: true });
        server.close();
        return resolve(0);
      }
      const push = /^\/push\/([a-z_]+)$/.exec(url.pathname);
      if (req.method === 'POST' && push?.[1]) {
        if (!udid) return fail(new Error('started without --udid'));
        const file = join(ROOT, 'ios/fixtures/push', `${push[1]}.apns`);
        if (!existsSync(file)) return reply(res, 404, { error: `no fixture ${push[1]}` });
        execFile('xcrun', ['simctl', 'push', udid, BUNDLE_ID, file], (error) =>
          error ? fail(error) : reply(res, 200, { pushed: push[1] }),
        );
        return;
      }
      if (req.method === 'POST' && url.pathname === '/expire') {
        if (!token || !roomId) return fail(new Error('started without --token and --room'));
        expire(env, token, roomId).then((out) => reply(res, 200, out), fail);
        return;
      }
      reply(res, 404, { error: 'unknown request' });
    });
    server.listen(port, '127.0.0.1', () =>
      note(`harness is listening on http://127.0.0.1:${port}`),
    );
  });
}

async function main(): Promise<number> {
  const { values, positionals } = parseArgs({
    allowPositionals: true,
    options: {
      api: { type: 'string' },
      lat: { type: 'string', default: String(DEMO_ROOM.latitude) },
      lng: { type: 'string', default: String(DEMO_ROOM.longitude) },
      name: { type: 'string', default: 'Avery' },
      gender: { type: 'string', default: 'woman' },
      'show-me': { type: 'string', default: 'man' },
      port: { type: 'string' },
      udid: { type: 'string' },
      token: { type: 'string' },
      room: { type: 'string' },
      help: { type: 'boolean', default: false },
    },
  });
  const [command, ...rest] = positionals;
  if (values.help || !command) {
    process.stdout.write(`${USAGE}\n`);
    return values.help ? 0 : 2;
  }
  const env = loadEnv(values.api);
  const out = (value: unknown) => process.stdout.write(`${JSON.stringify(value)}\n`);
  switch (command) {
    case 'room':
      out(await makeRoom(env, Number(values.lat), Number(values.lng)));
      return 0;
    case 'end-room': {
      if (!rest[0]) break;
      await (await admin(env)).updateRoom(rest[0], { status: 'ended' });
      out({ ended: rest[0] });
      return 0;
    }
    case 'person': {
      const genders = ['woman', 'man', 'nonbinary'] as const;
      const gender = genders.find((g) => g === values.gender);
      const showMe = values['show-me']
        .split(',')
        .flatMap((g) => genders.filter((x) => x === g.trim()));
      if (!rest[0] || !gender || showMe.length === 0) break;
      const email = freshEmail(rest[0]);
      const person = await onboardedPerson(env, email, {
        firstName: values.name,
        gender,
        showMe,
        profilePhoto: join(ROOT, 'scripts/e2e/fixtures/profile-a.jpg'),
      });
      out({
        email,
        userId: person.userId,
        accessToken: person.session.accessToken,
        firstName: values.name,
      });
      return 0;
    }
    case 'expire': {
      if (!rest[0] || !rest[1]) break;
      out(await expire(env, rest[0], rest[1]));
      return 0;
    }
    case 'serve': {
      if (!values.port) break;
      return serve(env, Number(values.port), values.udid, values.token, values.room);
    }
  }
  process.stderr.write(`${USAGE}\n`);
  return 2;
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
