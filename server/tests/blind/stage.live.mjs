#!/usr/bin/env node
/**
 * Owner: X1. The Blind stage path against a running server and its local Supabase, with a
 * traffic recorder (a port of Double Blind's web/e2e/lib/recorder.ts idea): every Blind
 * response body is kept, and before the reveal none may contain the partner's user ID, first
 * name or photo path (B1). Run with the server up (BLIND_DEMO_MODE=true):
 *
 *   GLOW_API=http://localhost:3151 node server/tests/blind/stage.live.mjs
 *
 * Reads SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY from server/.env.local. Local only.
 */
import { createRequire } from 'node:module';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

const envFile = fileURLToPath(new URL('../../.env.local', import.meta.url));
if (existsSync(envFile)) process.loadEnvFile(envFile);
const API = process.env.GLOW_API ?? 'http://localhost:3151';
const require = createRequire(new URL('../../package.json', import.meta.url));
const { createClient } = require('@supabase/supabase-js');
const sharp = require('sharp');
const db = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

let failures = 0;
let checks = 0;
const ok = (cond, what) => {
  checks++;
  if (!cond) failures++;
  console.log(`${cond ? 'ok' : 'NOT OK'} ${checks} - ${what}`);
};

const recorded = []; // { phase, op, body }
let phase = 'blind';

async function call(token, method, path, body) {
  const res = await fetch(`${API}${path}`, {
    method,
    headers: {
      authorization: `Bearer ${token}`,
      ...(body ? { 'content-type': 'application/json' } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  if (path.startsWith('/api/blind'))
    recorded.push({ phase, op: `${method} ${path}`, status: res.status, body: text });
  let json = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    json = text;
  }
  return { status: res.status, json };
}

async function person(email, name, gender, showMe) {
  const r = await fetch(`${API}/api/dev/test-login`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email }),
  });
  const session = await r.json();
  if (!session.accessToken)
    throw new Error(`test-login failed for ${email}: ${JSON.stringify(session)}`);
  const id = session.userId;
  await db
    .from('profiles')
    .update({
      first_name: name,
      birthdate: '1997-04-04',
      gender,
      show_me: showMe,
      onboarding_step: 'complete',
    })
    .eq('id', id);
  const { data: has } = await db.from('profile_photos').select('id').eq('user_id', id).limit(1);
  if (!has?.length) {
    const photoId = crypto.randomUUID();
    const path = `${id}/${photoId}.jpg`;
    const jpeg = await sharp({
      create: { width: 600, height: 800, channels: 3, background: '#445566' },
    })
      .jpeg()
      .toBuffer();
    await db.storage
      .from('profile-photos')
      .upload(path, jpeg, { contentType: 'image/jpeg', upsert: true });
    await db
      .from('profile_photos')
      .insert({ id: photoId, user_id: id, path, position: 0, moderation_status: 'approved' });
  }
  const { data: photos } = await db.from('profile_photos').select('path').eq('user_id', id);
  return { id, token: session.accessToken, name, email, paths: (photos ?? []).map((p) => p.path) };
}

const stamp = Date.now().toString(36);
const a = await person(`stage-a-${stamp}@glow.test`, 'Avery', 'woman', ['man']);
const b = await person(`stage-b-${stamp}@glow.test`, 'Blake', 'man', ['woman']);

// Opt in
ok(
  (await call(a.token, 'GET', '/api/blind/deck')).status === 404,
  'not a member: deck is 404 (P11)',
);
const meBefore = await call(a.token, 'GET', '/api/blind/me');
ok(
  meBefore.status === 200 && meBefore.json.member === false,
  'me says member false before joining',
);
const joinA = await call(a.token, 'POST', '/api/blind/join');
ok(joinA.status === 200 && joinA.json.member === true && joinA.json.hasPhoto === true, 'A joins');
ok((await call(b.token, 'POST', '/api/blind/join')).status === 200, 'B joins');

// Deck and a swipe on a demo member
const deck = await call(a.token, 'GET', '/api/blind/deck?limit=5');
ok(
  deck.status === 200 && deck.json.cards.length > 0,
  `A's deck has cards (${deck.json.cards?.length})`,
);
const card = deck.json.cards[0];
const img = await fetch(`${API}${card.photoUrl}`, {
  headers: { authorization: `Bearer ${a.token}` },
});
ok(
  img.status === 200 && img.headers.get('content-type') === 'image/jpeg',
  'the card photo link serves a JPEG',
);
const imgB = await fetch(`${API}${card.photoUrl}`, {
  headers: { authorization: `Bearer ${b.token}` },
});
ok(imgB.status === 404, 'the same link is 404 for someone else');
const sw = await call(a.token, 'POST', '/api/blind/swipe', { targetId: card.id, kind: 'pass' });
ok(
  sw.status === 200 && Object.keys(sw.json).sort().join() === 'rightCount,rightRemaining',
  'a swipe answers only the counters (B2)',
);

// Pair the two stage accounts (mutual like, 5 right swipes each) through the seed helper
execFileSync(
  'node',
  [
    '--disable-warning=MODULE_TYPELESS_PACKAGE_JSON',
    fileURLToPath(new URL('../../../scripts/seed-blind.ts', import.meta.url)),
    'pair',
    a.email,
    b.email,
  ],
  { stdio: 'inherit' },
);

const pool = await call(a.token, 'GET', '/api/blind/pool');
ok(pool.status === 200 && pool.json.canDrop === true, 'A can drop');
const status = await call(a.token, 'GET', '/api/blind/drop');
ok(
  status.status === 200 && status.json.ready === true && status.json.demo === true,
  'demo mode: the drop is ready',
);
const dropA = await call(a.token, 'POST', '/api/blind/drop');
ok(dropA.status === 200 && dropA.json.opened >= 1, `A's drop opens chats (${dropA.json.opened})`);
const dropB = await call(b.token, 'POST', '/api/blind/drop');
ok(
  dropB.status === 200 && dropB.json.opened >= 1,
  `B's drop shows the chat A's drop opened (${dropB.json.opened})`,
);

// Find the shared chat (server side, for the test only)
const { data: chatRow } = await db
  .from('blind_chats')
  .select('id')
  .eq('user_a', a.id < b.id ? a.id : b.id)
  .eq('user_b', a.id < b.id ? b.id : a.id)
  .single();
const chatId = chatRow.id;
ok(
  dropA.json.chats.some((c) => c.id === chatId) && dropB.json.chats.some((c) => c.id === chatId),
  'both drops include the chat',
);

const listA = await call(a.token, 'GET', '/api/blind/chats');
ok(
  listA.status === 200 && listA.json.chats.some((c) => c.id === chatId),
  "the chat is in A's list",
);
const chatA = await call(a.token, 'GET', `/api/blind/chats/${chatId}`);
ok(
  chatA.status === 200 && chatA.json.status === 'open' && !('partner' in chatA.json),
  'before reveal: no partner (B1)',
);
const warn = await call(a.token, 'POST', `/api/blind/chats/${chatId}/messages`, {
  text: 'my insta is avery.codes',
});
ok(
  warn.status === 200 && warn.json.warning && !warn.json.message,
  'a give-away message is held back with a warning',
);
const sent = await call(a.token, 'POST', `/api/blind/chats/${chatId}/messages`, {
  text: 'hey, what are you building?',
});
ok(sent.status === 200 && sent.json.message?.mine === true, 'A sends a message');
const msgsB = await call(b.token, 'GET', `/api/blind/chats/${chatId}/messages?after=0`);
ok(
  msgsB.status === 200 && msgsB.json.messages.length === 1 && msgsB.json.messages[0].mine === false,
  'B reads it as not mine',
);
ok(
  (
    await call(b.token, 'POST', `/api/blind/chats/${chatId}/messages`, {
      text: 'a hardware thing',
      confirm: true,
    })
  ).status === 200,
  'B replies',
);
const tapA = await call(a.token, 'POST', `/api/blind/chats/${chatId}/reveal`);
ok(tapA.status === 200 && tapA.json.status === 'open', 'A taps Reveal: still open');
const chatB = await call(b.token, 'GET', `/api/blind/chats/${chatId}`);
ok(
  chatB.json.iTappedReveal === false && chatB.json.status === 'open',
  "B can't tell A tapped (B5)",
);
ok((await call(b.token, 'GET', `/api/blind/pool/cards`)).status === 200, 'Guess Who cards load');

// Leak scan of everything before the reveal (B1)
const needles = (p) =>
  [p.id, p.name, ...p.paths, ...p.paths.map((x) => x.split('/')[1])].filter(Boolean);
const leaks = [];
for (const r of recorded) {
  for (const n of [...needles(a), ...needles(b)]) {
    // Chat and drop replies must name nobody (neither side's ID, name or photo) before reveal.
    if (r.op.includes('/chats') || r.op.includes('/drop')) {
      if (r.body.includes(n))
        leaks.push(`${r.op}: ${n === a.name || n === b.name ? 'name' : 'id or photo'}`);
    }
  }
}
ok(
  leaks.length === 0,
  `leak scan: ${recorded.length} Blind responses before reveal, ${leaks.length} leaks ${leaks.slice(0, 3).join('; ')}`,
);

phase = 'revealed';
const tapB = await call(b.token, 'POST', `/api/blind/chats/${chatId}/reveal`);
ok(tapB.status === 200 && tapB.json.status === 'revealed', 'B taps Reveal: revealed');
const after = await call(a.token, 'GET', `/api/blind/chats/${chatId}`);
ok(
  after.json.partner?.name === 'Blake' && after.json.partner.photos.length === 1,
  'after reveal A sees Blake and a photo link',
);
const ph = await fetch(`${API}${after.json.partner.photos[0]}`, {
  headers: { authorization: `Bearer ${a.token}` },
});
ok(ph.status === 200, 'the partner photo link serves');

// Leaving
const leave = await call(b.token, 'POST', `/api/blind/join`, undefined);
void leave;
ok(
  (await call(a.token, 'POST', `/api/blind/chats/${chatId}/leave`)).status === 200,
  'A can call leave (a revealed chat stays listed)',
);

console.log(`\n${checks - failures}/${checks} passed, ${recorded.length} Blind responses recorded`);
process.exit(failures ? 1 : 0);
