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

import { parseArgs } from 'node:util';
import { pathToFileURL } from 'node:url';
import {
  DEMO_ROOM,
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
  --api URL                       the API (default $GLOW_API, else http://localhost:3000)`;

const ADMIN_EMAIL = 'admin@glow.test';

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
      const showMe = values['show-me'].split(',').flatMap((g) => genders.filter((x) => x === g.trim()));
      if (!rest[0] || !gender || showMe.length === 0) break;
      const email = freshEmail(rest[0]);
      const person = await onboardedPerson(env, email, { firstName: values.name, gender, showMe });
      out({ email, userId: person.userId, accessToken: person.session.accessToken, firstName: values.name });
      return 0;
    }
    case 'expire': {
      if (!rest[0] || !rest[1]) break;
      out(await expire(env, rest[0], rest[1]));
      return 0;
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
