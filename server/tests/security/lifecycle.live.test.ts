/**
 * P3 (server side), P8, P9 and P10, through the real routes on a live stack:
 *
 *   P3  A check-in photo with a visible face is refused and never stored; whatever metadata a
 *       modified app sends (GPS EXIF, comments, ICC), the stored card has none; a join ticket
 *       works for its own person and room only.
 *   P8  Pausing or leaving takes a person out of every deck at once (limit: 5 seconds).
 *   P9  Expired check-ins and their photos are gone after one purge run; the purge route
 *       answers only to the cron secret.
 *   P10 Nobody under 18 can be stored, and onboarding can't finish without an approved photo.
 */
import { randomUUID } from 'node:crypto';
import sharp from 'sharp';
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { resetEnvCacheForTests } from '@/env';
import { moderationFixtureJpeg } from '@/server/moderation';
import { call } from './helpers/api';
import { LIVE, tag, type Live } from './helpers/live';
import { World, type Person } from './helpers/world';
import { LOCAL_ENV } from '../helpers/env';

vi.mock('@/server/notify', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@/server/notify')>();
  return {
    ...actual,
    notify: vi.fn(async () => ({ realtime: 'sent', push: null })),
    notifyRoom: vi.fn(async () => ({ realtime: 'sent', push: null })),
  };
});

const live = LIVE as Live;
let world: World;
let roomId: string;
let roomCode: string;

beforeAll(async () => {
  if (!LIVE) return;
  world = new World(live);
  roomId = await world.room();
  roomCode = (await world.db.from('rooms').select('code').eq('id', roomId).single()).data!.code;
}, 30_000);
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

const INSIDE = { latitude: 37.8029, longitude: -122.4484, accuracy: 10 };

async function ticketFor(who: Person, room = roomId, code = roomCode): Promise<string> {
  const joined = await call('joinRoom', {
    token: who.token,
    params: { id: room },
    body: { access: { kind: 'code', code }, location: INSIDE },
  });
  expect(joined.status).toBe(200);
  return (joined.json as { ticket: string }).ticket;
}

const checkin = (who: Person, ticket: string, jpeg: Uint8Array, room = roomId) =>
  call('createCheckin', {
    token: who.token,
    params: { id: room },
    body: {
      ticket,
      photo: Buffer.from(jpeg).toString('base64'),
      tags: { topColor: 'blue', extras: ['glasses'] },
    },
  });

async function cardObjects(room = roomId): Promise<string[]> {
  const { data } = await world.db.storage.from('room-cards').list(room);
  return (data ?? []).map((o) => o.name);
}

describe.skipIf(!LIVE)('P3: only clean, face-free card photos are stored (live)', () => {
  it('a photo with a visible face is refused, and nothing is stored or checked in', async () => {
    const who = await world.person();
    const ticket = await ticketFor(who);
    const before = await cardObjects();
    const reply = await checkin(who, ticket, await moderationFixtureJpeg(['face_visible']));
    expect(reply.status).toBe(422);
    expect(reply.json).toMatchObject({ error: { code: 'photo_rejected', reason: 'face_visible' } });
    expect(await cardObjects()).toEqual(before);
    const rows = await world.db.from('checkins').select('id').eq('user_id', who.id);
    expect(rows.data).toEqual([]);
  });

  it('GPS EXIF, comments and colour profiles never reach storage', async () => {
    const who = await world.person();
    const ticket = await ticketFor(who);
    const base = await moderationFixtureJpeg([]);
    const dirty = await sharp(base)
      .withExif({
        IFD0: { Copyright: 'D2-COPYRIGHT-MARK', Software: 'D2-SOFTWARE-MARK' },
        IFD3: {
          GPSLatitudeRef: 'N',
          GPSLatitude: '37/1 48/1 1044/100',
          GPSLongitudeRef: 'W',
          GPSLongitude: '122/1 26/1 5424/100',
        },
      })
      .withIccProfile('p3')
      .toBuffer();
    expect(dirty.includes(Buffer.from('Exif'))).toBe(true); // control: the input is dirty
    expect(dirty.includes(Buffer.from('D2-COPYRIGHT-MARK'))).toBe(true);

    const reply = await checkin(who, ticket, dirty);
    expect(reply.status).toBe(201);
    const row = await world.db.from('checkins').select('card_path').eq('user_id', who.id).single();
    const stored = await world.db.storage.from('room-cards').download(row.data!.card_path);
    const bytes = Buffer.from(await stored.data!.arrayBuffer());
    for (const marker of [
      'Exif',
      'D2-COPYRIGHT-MARK',
      'D2-SOFTWARE-MARK',
      'GPS',
      'ICC_PROFILE',
      'http://ns.adobe.com',
    ]) {
      expect(bytes.includes(Buffer.from(marker)), marker).toBe(false);
    }
    const meta = await sharp(bytes).metadata();
    expect(meta.exif).toBeUndefined();
    expect(meta.icc).toBeUndefined();
    expect(meta.format).toBe('jpeg');
  });

  it('a join ticket opens one door: its own person and its own room', async () => {
    const owner = await world.person();
    const thief = await world.person();
    const otherRoom = await world.room();
    const ticket = await ticketFor(owner);
    const jpeg = await moderationFixtureJpeg([]);
    const stolen = await checkin(thief, ticket, jpeg);
    expect(stolen.status).toBe(422);
    expect(stolen.json).toMatchObject({ error: { code: 'join_ticket_invalid' } });
    const wrongRoom = await checkin(owner, ticket, jpeg, otherRoom);
    expect([404, 422]).toContain(wrongRoom.status);
    expect((await world.db.from('checkins').select('id').eq('room_id', otherRoom)).data).toEqual(
      [],
    );
    const junk = await checkin(owner, `${ticket.slice(0, -4)}AAAA`, jpeg);
    expect(junk.status).toBe(422);
    expect((await checkin(owner, 'x', jpeg)).status).toBe(422);
  });

  it('a far-away or too-vague location gets no ticket, so no check-in', async () => {
    const who = await world.person();
    for (const location of [
      { latitude: 37.8209, longitude: -122.4484, accuracy: 10 },
      { latitude: 37.8029, longitude: -122.4484, accuracy: 900 },
    ]) {
      const joined = await call('joinRoom', {
        token: who.token,
        params: { id: roomId },
        body: { access: { kind: 'code', code: roomCode }, location },
      });
      expect(joined.status).toBe(422);
      expect(joined.text).not.toContain('ticket');
    }
    const forged = await checkin(who, randomUUID(), await moderationFixtureJpeg([]));
    expect(forged.status).toBe(422);
  });
});

describe.skipIf(!LIVE)('P8: paused or departed people leave every deck (live)', () => {
  it('pausing and leaving each take effect on the next fetch, well inside 5 seconds', async () => {
    const watcher = await world.person('man', ['woman']);
    const room = await world.room();
    await world.checkIn(watcher, room);
    const [pauser, leaver] = await Promise.all([
      world.person('woman', ['man']),
      world.person('woman', ['man']),
    ]);
    const [pauserCard, leaverCard] = await Promise.all([
      world.checkIn(pauser, room),
      world.checkIn(leaver, room),
    ]);
    const ids = async () =>
      (
        (await call('getDeck', { token: watcher.token, params: { id: room }, body: {} })).json as {
          cards: { id: string }[];
        }
      ).cards.map((c) => c.id);
    expect((await ids()).sort()).toEqual([pauserCard.id, leaverCard.id].sort());

    const t0 = Date.now();
    expect(
      (await call('setPaused', { token: pauser.token, body: { paused: true } })).status,
    ).toBeLessThan(300);
    expect(await ids()).toEqual([leaverCard.id]);
    expect(
      (await call('leaveRoom', { token: leaver.token, params: { id: room } })).status,
    ).toBeLessThan(300);
    expect(await ids()).toEqual([]);
    expect(Date.now() - t0).toBeLessThan(5000);
    // And the departed person's card photo is gone, not just hidden.
    expect(await cardObjects(room)).not.toContain(`${leaverCard.id}.jpg`);
    // Resuming brings only the paused person back.
    await call('setPaused', { token: pauser.token, body: { paused: false } });
    expect(await ids()).toEqual([pauserCard.id]);
  });
});

describe.skipIf(!LIVE)('P9: expired check-ins and photos are purged (live)', () => {
  const purge = (token: string | null, scheme = 'Bearer') =>
    call('runPurge', { headers: token ? { authorization: `${scheme} ${token}` } : {} });

  it('only the cron secret runs the purge', async () => {
    const who = await world.person();
    for (const reply of [
      await purge(null),
      await purge('wrong-secret'),
      await purge(who.token),
      await purge(LOCAL_ENV.CRON_SECRET, 'Basic'),
      await purge(`${LOCAL_ENV.CRON_SECRET}x`),
      await purge(LOCAL_ENV.CRON_SECRET.slice(0, -1)),
    ]) {
      expect(reply.status).toBe(401);
    }
  });

  it('an expired card and its photo are gone after one run, and a live one stays', async () => {
    const room = await world.room();
    const [gone, kept] = await Promise.all([world.person(), world.person()]);
    const [goneCard, keptCard] = await Promise.all([
      world.checkIn(gone, room),
      world.checkIn(kept, room),
    ]);
    expect(await cardObjects(room)).toEqual(
      expect.arrayContaining([`${goneCard.id}.jpg`, `${keptCard.id}.jpg`]),
    );

    const expired = await world.db
      .from('checkins')
      .update({
        joined_at: new Date(Date.now() - 2 * 3600_000).toISOString(),
        expires_at: new Date(Date.now() - 60_000).toISOString(),
      })
      .eq('id', goneCard.id);
    expect(expired.error).toBeNull();

    const run = await purge(LOCAL_ENV.CRON_SECRET);
    expect(run.status).toBe(200);
    const left = await world.db.from('checkins').select('id').in('id', [goneCard.id, keptCard.id]);
    expect((left.data ?? []).map((r) => r.id)).toEqual([keptCard.id]);
    const objects = await cardObjects(room);
    expect(objects).not.toContain(`${goneCard.id}.jpg`);
    expect(objects).toContain(`${keptCard.id}.jpg`);
  });
});

describe.skipIf(!LIVE)('P10: nobody under 18 (live)', () => {
  const yearsAgo = (years: number, extraDays = 0) => {
    const d = new Date();
    d.setUTCFullYear(d.getUTCFullYear() - years);
    d.setUTCDate(d.getUTCDate() - extraDays);
    return d.toISOString().slice(0, 10);
  };

  it("a birthdate under 18 is refused by the database, tomorrow's 18th birthday included", async () => {
    const who = await world.person();
    for (const birthdate of [
      yearsAgo(17),
      yearsAgo(18, -2),
      yearsAgo(5),
      new Date().toISOString().slice(0, 10),
    ]) {
      const update = await world.db.from('profiles').update({ birthdate }).eq('id', who.id);
      expect(update.error, birthdate).not.toBeNull();
      expect(update.error!.message).toMatch(/under_18/);
    }
    // And exactly 18 (a day to spare for the UTC-12 rule) is fine.
    const ok = await world.db
      .from('profiles')
      .update({ birthdate: yearsAgo(18, 2) })
      .eq('id', who.id);
    expect(ok.error).toBeNull();
  });

  it('a new account cannot skip to complete without the fields and an approved photo', async () => {
    const email = `d2-new-${tag()}@glow.test`;
    const created = await world.db.auth.admin.createUser({ email, email_confirm: true });
    const id = created.data.user!.id;
    try {
      const skip = await world.db
        .from('profiles')
        .update({ onboarding_step: 'complete' })
        .eq('id', id);
      expect(skip.error).not.toBeNull();
      const rpc = await world.db.rpc('complete_onboarding', { p_user_id: id });
      expect(rpc.error).not.toBeNull();
      await world.db
        .from('profiles')
        .update({ first_name: 'Dee', birthdate: yearsAgo(30), gender: 'woman', show_me: ['man'] })
        .eq('id', id);
      // Fields in, but the only photo is held for review (a possible minor): still no.
      const photoId = randomUUID();
      await world.db.from('profile_photos').insert({
        id: photoId,
        user_id: id,
        path: `${id}/${photoId}.jpg`,
        position: 0,
        moderation_status: 'held',
      });
      expect((await world.db.rpc('complete_onboarding', { p_user_id: id })).error).not.toBeNull();
      await world.db
        .from('profile_photos')
        .update({ moderation_status: 'approved' })
        .eq('id', photoId);
      expect((await world.db.rpc('complete_onboarding', { p_user_id: id })).error).toBeNull();
    } finally {
      await world.db.auth.admin.deleteUser(id);
    }
  });
});
