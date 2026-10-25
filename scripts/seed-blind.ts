#!/usr/bin/env -S node --disable-warning=MODULE_TYPELESS_PACKAGE_JSON
/**
 * scripts/seed-blind.ts · X1 · Blind mode demo members, made only of test data.
 *
 *   scripts/seed-blind.ts                       # seed or refresh 20 Blind demo members
 *   scripts/seed-blind.ts likeback <email>      # every fitting demo member right-swipes <email>
 *   scripts/seed-blind.ts pair <email> <email>  # the two stage accounts join, like each other,
 *                                               # and each likes demo members up to 5 right swipes
 *   scripts/seed-blind.ts --remove              # delete the demo members and their photos
 *
 * Reads SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY, or server/.env.local. Refuses any URL that
 * isn't on this machine. Demo members have `@blind.glow.test` emails, first names starting with
 * "Test", `test_data` in their auth metadata, and one generated placeholder photo each (a color
 * field with a number: no real people, no faces). Fixed IDs, so it's idempotent.
 */
import { createHash } from 'node:crypto';
import { existsSync } from 'node:fs';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Db = any;

const COUNT = 20;
const BUCKET = 'profile-photos';
const NAMES = [
  'Ava',
  'Ben',
  'Cleo',
  'Dev',
  'Eli',
  'Fay',
  'Gus',
  'Hana',
  'Ivo',
  'Jade',
  'Kai',
  'Lena',
  'Milo',
  'Nia',
  'Omar',
  'Pia',
  'Quin',
  'Rosa',
  'Sam',
  'Tess',
];
const COLORS = [
  '#3b5bdb',
  '#c2255c',
  '#2b8a3e',
  '#e8590c',
  '#5f3dc4',
  '#0b7285',
  '#a61e4d',
  '#5c940d',
  '#d9480f',
  '#364fc7',
];

function uuidFrom(text: string): string {
  const h = createHash('sha256').update(text).digest('hex');
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-4${h.slice(13, 16)}-8${h.slice(17, 20)}-${h.slice(20, 32)}`;
}

type Member = {
  id: string;
  photoId: string;
  email: string;
  firstName: string;
  gender: string;
  showMe: string[];
};

export function members(): Member[] {
  return NAMES.slice(0, COUNT).map((name, i) => {
    // Even: women who want men; odd: men who want women; every fifth also open to everyone.
    const gender = i % 2 === 0 ? 'woman' : 'man';
    const showMe = i % 5 === 4 ? ['woman', 'man', 'nonbinary'] : [i % 2 === 0 ? 'man' : 'woman'];
    return {
      id: uuidFrom(`blind-demo:${i}`),
      photoId: uuidFrom(`blind-demo-photo:${i}`),
      email: `blind-demo-${String(i + 1).padStart(2, '0')}@blind.glow.test`,
      firstName: `Test ${name}`,
      gender,
      showMe,
    };
  });
}

function isLocalUrl(url: string): boolean {
  try {
    return ['localhost', '127.0.0.1', '[::1]'].includes(new URL(url).hostname);
  } catch {
    return false;
  }
}

async function must<T>(what: string, p: PromiseLike<{ data: T; error: unknown }>): Promise<T> {
  const { data, error } = await p;
  if (error) throw new Error(`${what} failed: ${(error as { message?: string }).message ?? error}`);
  return data;
}

async function placeholderJpeg(sharp: Db, i: number): Promise<Buffer> {
  const color = COLORS[i % COLORS.length];
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="900" height="1200">
    <defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="${color}"/><stop offset="1" stop-color="#0b0b10"/></linearGradient></defs>
    <rect width="900" height="1200" fill="url(#g)"/>
    <circle cx="${200 + ((i * 97) % 500)}" cy="${300 + ((i * 53) % 600)}" r="${120 + (i % 4) * 30}" fill="#ffffff" fill-opacity="0.12"/>
    <text x="450" y="660" font-size="260" text-anchor="middle" fill="#ffffff" fill-opacity="0.85"
      font-family="Helvetica, Arial, sans-serif" font-weight="700">${i + 1}</text>
    <text x="450" y="1120" font-size="44" text-anchor="middle" fill="#ffffff" fill-opacity="0.6"
      font-family="Helvetica, Arial, sans-serif">Blind demo (test data)</text></svg>`;
  return sharp(Buffer.from(svg)).jpeg({ quality: 80 }).toBuffer();
}

async function ensureMember(db: Db, sharp: Db, m: Member, i: number): Promise<void> {
  const found = await db.auth.admin.getUserById(m.id);
  if (!found.data?.user) {
    await must(
      'create member',
      db.auth.admin.createUser({
        id: m.id,
        email: m.email,
        email_confirm: true,
        app_metadata: { test_data: true },
        user_metadata: { test_data: true },
      }),
    );
  } else if (found.data.user.email !== m.email) {
    throw new Error(`User ${m.id} exists with a different email; not touching it.`);
  }
  await must(
    'set profile',
    db
      .from('profiles')
      .update({
        first_name: m.firstName,
        birthdate: `${1994 + (i % 8)}-0${1 + (i % 9)}-1${i % 9}`,
        gender: m.gender,
        show_me: m.showMe,
        onboarding_step: 'complete',
        paused: false,
      })
      .eq('id', m.id),
  );
  const path = `${m.id}/${m.photoId}.jpg`;
  const photo = await must(
    'read photo',
    db.from('profile_photos').select('id').eq('id', m.photoId).maybeSingle(),
  );
  if (!photo) {
    await must(
      'upload photo',
      db.storage.from(BUCKET).upload(path, await placeholderJpeg(sharp, i), {
        contentType: 'image/jpeg',
        upsert: true,
      }),
    );
    await must(
      'add photo',
      db.from('profile_photos').insert({
        id: m.photoId,
        user_id: m.id,
        path,
        position: 0,
        moderation_status: 'approved',
      }),
    );
  }
  await must('join Blind', db.rpc('blind_join', { p_user_id: m.id }));
}

async function userIdByEmail(db: Db, email: string): Promise<string> {
  for (let page = 1; page < 50; page++) {
    const { data, error } = await db.auth.admin.listUsers({ page, perPage: 200 });
    if (error) throw new Error(`list users failed: ${error.message}`);
    const hit = data.users.find(
      (u: { email?: string }) => u.email?.toLowerCase() === email.toLowerCase(),
    );
    if (hit) return hit.id;
    if (data.users.length < 200) break;
  }
  throw new Error(`No account with email ${email}. Sign in with it once first.`);
}

/** viewer right-swipes target through viewer's own card for them (the same path as the app). */
async function like(db: Db, viewer: string, target: string): Promise<'ok' | 'cap'> {
  const { data: card } = await db
    .from('blind_cards')
    .select('card_id')
    .eq('viewer_id', viewer)
    .eq('target_id', target)
    .maybeSingle();
  let cardId = card?.card_id;
  if (!cardId) {
    const made = (await must(
      'make card',
      db
        .from('blind_cards')
        .insert({ viewer_id: viewer, target_id: target })
        .select('card_id')
        .single(),
    )) as { card_id: string };
    cardId = made.card_id;
  }
  const { error } = await db.rpc('blind_record_swipe', {
    p_swiper_id: viewer,
    p_card_id: cardId,
    p_kind: 'like',
  });
  if (error?.message === 'right_cap_reached') return 'cap';
  if (error) throw new Error(`swipe failed: ${error.message}`);
  return 'ok';
}

async function fits(db: Db, a: string, b: string): Promise<boolean> {
  const { data } = await db.from('profiles').select('id, gender, show_me').in('id', [a, b]);
  const pa = data?.find((p: { id: string }) => p.id === a);
  const pb = data?.find((p: { id: string }) => p.id === b);
  return !!pa && !!pb && pa.show_me.includes(pb.gender) && pb.show_me.includes(pa.gender);
}

async function rightCount(db: Db, user: string): Promise<number> {
  const me = (await must('blind_me', db.rpc('blind_me', { p_user_id: user }))) as {
    rightCount: number;
  };
  return me.rightCount;
}

async function main(): Promise<void> {
  const file = fileURLToPath(new URL('../server/.env.local', import.meta.url));
  if (existsSync(file) && !process.env.SUPABASE_SERVICE_ROLE_KEY) process.loadEnvFile(file);
  const url = process.env.SUPABASE_URL ?? '';
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY ?? '';
  if (!url || !key)
    throw new Error('Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY, or run pnpm env:setup.');
  if (!isLocalUrl(url)) throw new Error(`Refusing ${url}: seed-blind only seeds a local Supabase.`);
  const require = createRequire(new URL('../server/package.json', import.meta.url));
  const { createClient } = require('@supabase/supabase-js');
  const sharp = require('sharp');
  const db: Db = createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const [cmd, ...args] = process.argv.slice(2);
  const all = members();

  if (cmd === '--remove') {
    for (const m of all) {
      await db.storage.from(BUCKET).remove([`${m.id}/${m.photoId}.jpg`]);
      await db.auth.admin.deleteUser(m.id);
    }
    console.log(`seed-blind: removed ${all.length} demo members`);
    return;
  }
  if (cmd === 'likeback' || cmd === 'pair') {
    if (cmd === 'likeback' && args.length !== 1)
      throw new Error('usage: seed-blind.ts likeback <email>');
    if (cmd === 'pair' && args.length !== 2)
      throw new Error('usage: seed-blind.ts pair <email> <email>');
    const ids = [];
    for (const email of args) ids.push(await userIdByEmail(db, email));
    for (const id of ids) {
      const { error } = await db.rpc('blind_join', { p_user_id: id });
      if (error)
        throw new Error(
          `${id} can't join Blind (${error.message}): finish the Glow profile first.`,
        );
    }
    if (cmd === 'likeback') {
      let n = 0;
      for (const m of all)
        if ((await fits(db, m.id, ids[0])) && (await like(db, m.id, ids[0])) === 'ok') n++;
      console.log(
        `seed-blind: ${n} demo members now like ${args[0]} (their swipes; mutual once they like back)`,
      );
      return;
    }
    const [a, b] = ids as [string, string];
    if (!(await fits(db, a, b)))
      console.log("seed-blind: warning, the two accounts don't fit each other's show me");
    await like(db, a, b);
    await like(db, b, a);
    for (const id of [a, b]) {
      for (const m of all) {
        if ((await rightCount(db, id)) >= 5) break;
        if (await fits(db, id, m.id)) await like(db, id, m.id);
      }
    }
    console.log(
      `seed-blind: paired ${args[0]} and ${args[1]} (mutual like, each has ${await rightCount(db, a)} and ${await rightCount(db, b)} right swipes). Open the drop to see the chat.`,
    );
    return;
  }
  if (cmd) throw new Error(`unknown command ${cmd}`);
  for (const [i, m] of all.entries()) await ensureMember(db, sharp, m, i);
  console.log(`seed-blind: ${all.length} Blind demo members ready (@blind.glow.test, test data)`);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((e: unknown) => {
    console.error(`seed-blind: ${e instanceof Error ? e.message : String(e)}`);
    process.exit(1);
  });
}
