/**
 * Owner: D5. Tests for scripts/seed-demo.ts.
 *
 * The unit tests always run. The integration tests run when GLOW_INTEGRATION=1 or CI is set,
 * against the local Supabase in server/.env.local (or GLOW_IT_SUPABASE_URL and
 * GLOW_IT_SUPABASE_SERVICE_ROLE_KEY), and refuse anything else. They seed rooms named
 * `d5it-…` and remove everything they made, so the shared CI database is left as it was.
 *
 *   pnpm --filter server exec vitest run tests/seed-demo
 *   GLOW_INTEGRATION=1 pnpm --filter server exec vitest run tests/seed-demo
 */
import { randomBytes } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import sharp from 'sharp';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { MIN_AGE_YEARS, zCardTags, type Database } from '@/contracts';
import {
  DEMO_ROOM,
  PEOPLE,
  SeedRefused,
  TEST_ROOM_MARK,
  VENUE,
  assertSafeTarget,
  checkVenue,
  cropFor,
  fixturePath,
  isLocalUrl,
  isTestRoomName,
  parseArgs,
  personEmail,
  personId,
  readConstants,
  removeSeed,
  seedDemo,
  sharpCardMaker,
  simVenue,
  venueText,
} from '../../../scripts/seed-demo.ts';

const constants = readConstants();
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

describe('seed-demo: where it may run', () => {
  it('treats only this machine as local', () => {
    expect(isLocalUrl('http://127.0.0.1:54421')).toBe(true);
    expect(isLocalUrl('http://localhost:55351')).toBe(true);
    expect(isLocalUrl('http://[::1]:54421')).toBe(true);
    expect(isLocalUrl('http://glow.localhost:54421')).toBe(true);
    expect(isLocalUrl('https://abcd.supabase.co')).toBe(false);
    expect(isLocalUrl('http://127.0.0.1.evil.example')).toBe(false);
    expect(isLocalUrl('http://localhost.evil.example')).toBe(false);
    expect(isLocalUrl('not a url')).toBe(false);
  });

  it('refuses a remote Supabase unless --remote is passed', () => {
    expect(() => assertSafeTarget('http://127.0.0.1:54421', false)).not.toThrow();
    expect(() => assertSafeTarget('https://abcd.supabase.co', false)).toThrow(SeedRefused);
    expect(() => assertSafeTarget('https://abcd.supabase.co', true)).not.toThrow();
    expect(() => assertSafeTarget('nope', true)).toThrow(SeedRefused);
    expect(() => assertSafeTarget('ftp://127.0.0.1', true)).toThrow(SeedRefused);
  });

  it('reads its options and refuses unknown ones', () => {
    expect(parseArgs([])).toEqual({
      remote: false,
      refresh: false,
      remove: false,
      printVenue: false,
      help: false,
      demoMode: false,
      slug: 'demo',
    });
    expect(parseArgs(['--remote', '--refresh', '--demo-mode', '--slug', 'stage-2'])).toMatchObject({
      remote: true,
      refresh: true,
      demoMode: true,
      slug: 'stage-2',
    });
    expect(() => parseArgs(['--slug'])).toThrow(SeedRefused);
    expect(() => parseArgs(['--slug', 'Not A Slug'])).toThrow(SeedRefused);
    expect(() => parseArgs(['--refresh', '--remove'])).toThrow(SeedRefused);
    expect(() => parseArgs(['--force'])).toThrow(SeedRefused);
  });

  it('only ever touches rooms marked as test data', () => {
    expect(isTestRoomName(DEMO_ROOM.name)).toBe(true);
    expect(isTestRoomName('Cal Hacks 12')).toBe(false);
    expect(isTestRoomName(`Cal Hacks ${TEST_ROOM_MARK} main hall`)).toBe(false);
  });
});

describe('seed-demo: the people are all test data', () => {
  it('has unique handles, @glow.test emails and "Test" first names', () => {
    const handles = PEOPLE.map((p) => p.handle);
    expect(new Set(handles).size).toBe(handles.length);
    for (const p of PEOPLE) {
      expect(personEmail('demo', p.handle)).toMatch(/^[a-z0-9-]+@glow\.test$/);
      expect(p.firstName).toMatch(/^Test [A-Z][a-z]+$/);
      expect(p.firstName.length).toBeLessThanOrEqual(40);
    }
  });

  it('is only adults', () => {
    const now = new Date();
    for (const p of PEOPLE) {
      const born = new Date(`${p.birthdate}T00:00:00Z`);
      const age = (now.getTime() - born.getTime()) / (365.25 * 24 * 3600_000);
      expect(age, p.handle).toBeGreaterThanOrEqual(MIN_AGE_YEARS + 3);
    }
  });

  it('uses only the public-domain, faceless outfit crops', () => {
    for (const p of PEOPLE) {
      expect(p.photo).toMatch(/^outfit-real-[a-z-]+\.jpg$/);
      expect(existsSync(fixturePath(p.photo)), p.photo).toBe(true);
    }
    const readme = readFileSync(
      fileURLToPath(new URL('../../../ios/fixtures/photos/README.md', import.meta.url)),
      'utf8',
    );
    for (const photo of new Set(PEOPLE.map((p) => p.photo))) {
      const row = readme.split('\n').find((line) => line.includes(photo));
      expect(row, photo).toMatch(/Public domain/);
    }
  });

  it('gives every card valid contract tags', () => {
    for (const p of PEOPLE) {
      expect(zCardTags.safeParse({ ...p.tags, extras: [...p.tags.extras] }).success, p.handle).toBe(
        true,
      );
    }
  });

  it('gives whoever is on stage a few cards, whatever their gender and show me', () => {
    const genders = ['woman', 'man', 'nonbinary'] as const;
    for (const gender of genders) {
      for (const shows of genders) {
        const visible = PEOPLE.filter((p) => p.gender === shows && p.showMe.includes(gender));
        expect(visible.length, `${gender} who shows ${shows}`).toBeGreaterThanOrEqual(1);
      }
      const all = PEOPLE.filter((p) => p.showMe.includes(gender));
      expect(all.length, `${gender} who shows everyone`).toBeGreaterThanOrEqual(6);
    }
  });

  it('gives each person a fixed UUID per room', () => {
    const ids = PEOPLE.map((p) => personId('demo', p.handle));
    for (const id of ids) expect(id).toMatch(UUID);
    expect(new Set(ids).size).toBe(ids.length);
    expect(personId('demo', 'river')).toBe(personId('demo', 'river'));
    expect(personId('demo', 'river')).not.toBe(personId('stage', 'river'));
  });
});

describe('seed-demo: the venue is one edit', () => {
  it('fits the contract limits', () => {
    expect(() => checkVenue(constants)).not.toThrow();
    expect(VENUE.meetingSpots.length).toBeGreaterThanOrEqual(constants.MEETING_SPOTS_MIN!);
    expect(VENUE.meetingSpots.length).toBeLessThanOrEqual(constants.MEETING_SPOTS_MAX!);
  });

  it("matches the center sim.sh uses (if this fails, copy --print-venue's lines into ios/fixtures/demo-room.env)", () => {
    expect(simVenue()).toEqual({ lat: VENUE.lat, lng: VENUE.lng });
    expect(venueText()).toContain(`GLOW_DEMO_LAT="${VENUE.lat}"`);
  });
});

describe('seed-demo: card images', () => {
  it('crops inside the photo', () => {
    for (const p of PEOPLE) {
      const box = cropFor(450, 831, p.variant);
      expect(box.left).toBeGreaterThanOrEqual(0);
      expect(box.top).toBeGreaterThanOrEqual(0);
      expect(box.left + box.width).toBeLessThanOrEqual(450);
      expect(box.top + box.height).toBeLessThanOrEqual(831);
    }
  });

  it('makes small JPEGs with no metadata, every one different', async () => {
    const make = sharpCardMaker(sharp, constants);
    const hashes = new Set<string>();
    for (const p of PEOPLE) {
      const bytes = await make(fixturePath(p.photo), p.variant);
      expect(bytes.byteLength).toBeLessThan(constants.PHOTO_MAX_BYTES!);
      const meta = await sharp(bytes).metadata();
      expect(meta.format).toBe('jpeg');
      expect(Math.max(meta.width, meta.height)).toBeLessThanOrEqual(constants.PHOTO_MAX_DIMENSION!);
      expect(meta.exif).toBeUndefined();
      expect(meta.icc).toBeUndefined();
      expect(meta.xmp).toBeUndefined();
      hashes.add(Buffer.from(bytes).toString('base64'));
    }
    expect(hashes.size).toBe(PEOPLE.length);
  });
});

// ---------------------------------------------------------------------------------------------
// Against a real local Supabase
// ---------------------------------------------------------------------------------------------

type Config = { url: string; serviceKey: string };

function itConfig(): Config | null {
  if (process.env.GLOW_INTEGRATION !== '1' && !process.env.CI) return null;
  const file = fileURLToPath(new URL('../../.env.local', import.meta.url));
  const env: Record<string, string> = {};
  if (existsSync(file)) {
    for (const line of readFileSync(file, 'utf8').split('\n')) {
      const match = /^([A-Z0-9_]+)=(.*)$/.exec(line.trim());
      if (match) env[match[1]!] = match[2]!.replace(/^['"]|['"]$/g, '');
    }
  }
  const url = process.env.GLOW_IT_SUPABASE_URL ?? env.SUPABASE_URL;
  const serviceKey = process.env.GLOW_IT_SUPABASE_SERVICE_ROLE_KEY ?? env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !serviceKey) throw new Error('seed-demo integration tests need a local Supabase.');
  if (!isLocalUrl(url)) throw new Error('seed-demo integration tests only run locally.');
  return { url, serviceKey };
}

const IT = itConfig();

describe.runIf(IT)('seed-demo: on a local Supabase', () => {
  let db: SupabaseClient<Database>;
  const tag = randomBytes(3).toString('hex');
  const slug = `d5it-${tag}`;
  const realSlug = `d5it-${tag}-real`;
  const make = sharpCardMaker(sharp, constants);
  const ids = PEOPLE.map((p) => personId(slug, p.handle));

  async function roomId(s: string): Promise<string> {
    const { data, error } = await db.from('rooms').select('id').eq('slug', s).single();
    if (error) throw error;
    return data.id;
  }

  async function openCards(room: string): Promise<{ id: string; card_path: string }[]> {
    const { data, error } = await db
      .from('checkins')
      .select('id, card_path')
      .eq('room_id', room)
      .is('left_at', null)
      .order('id');
    if (error) throw error;
    return data;
  }

  async function storedCards(room: string): Promise<string[]> {
    const { data, error } = await db.storage.from('room-cards').list(room, { limit: 1000 });
    if (error) throw error;
    return data.map((o) => `${room}/${o.name}`).sort();
  }

  beforeAll(() => {
    db = createClient<Database>(IT!.url, IT!.serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
  });

  afterAll(async () => {
    await removeSeed(db, slug);
    await removeSeed(db, realSlug);
    await db.from('rooms').delete().in('slug', [slug, realSlug]);
  });

  it('seeds a live demo-mode room at the venue, with test people and their cards', async () => {
    const summary = await seedDemo(db, make, { slug, refresh: false });
    expect(summary.room.created).toBe(true);
    expect(summary.peopleCreated).toBe(PEOPLE.length);
    expect(summary.cardsMade).toBe(PEOPLE.length);
    expect(summary.room.staticLink).toBeNull();
    expect(summary.room.demoMode).toBe(true);

    const { data: room } = await db.from('rooms').select('*').eq('slug', slug).single();
    expect(room).toMatchObject({
      lat: VENUE.lat,
      lng: VENUE.lng,
      radius_m: VENUE.radiusM,
      timezone: VENUE.timezone,
      demo_mode: true,
      status: 'live',
      allow_static_qr: false,
    });
    expect(isTestRoomName(room!.name)).toBe(true);

    const { data: spots } = await db
      .from('meeting_spots')
      .select('name, sort')
      .eq('room_id', room!.id)
      .order('sort');
    expect(spots!.map((s) => s.name)).toEqual([...VENUE.meetingSpots]);

    for (const [i, p] of PEOPLE.entries()) {
      const { data } = await db.auth.admin.getUserById(ids[i]!);
      expect(data.user?.email).toBe(personEmail(slug, p.handle));
      expect(data.user?.app_metadata).toMatchObject({ test_data: true });
      expect(data.user?.user_metadata).toMatchObject({ glow_test_data: true });
    }
    const { data: profiles } = await db
      .from('profiles')
      .select('first_name, onboarding_step, paused')
      .in('id', ids);
    expect(profiles).toHaveLength(PEOPLE.length);
    for (const profile of profiles!) {
      expect(profile.first_name).toMatch(/^Test /);
      expect(profile.onboarding_step).toBe('complete');
    }
    const { count: photos } = await db
      .from('profile_photos')
      .select('id', { count: 'exact', head: true })
      .in('user_id', ids);
    expect(photos).toBe(0);

    const cards = await openCards(room!.id);
    expect(cards).toHaveLength(PEOPLE.length);
    expect(await storedCards(room!.id)).toEqual(cards.map((c) => c.card_path).sort());

    // Join checks are recorded as demo-mode skips, never as a pass, and never with coordinates.
    const { data: checks } = await db.from('location_checks').select('*').eq('room_id', room!.id);
    expect(checks!.length).toBe(PEOPLE.length);
    for (const check of checks!) {
      expect(check).toMatchObject({ purpose: 'join', result: 'demo_skip' });
      expect(Object.keys(check).some((k) => /lat|lng|lon|coord/i.test(k))).toBe(false);
    }

    // Seeded people never tap anyone.
    const { count: taps } = await db
      .from('taps')
      .select('id', { count: 'exact', head: true })
      .in('from_user', ids);
    expect(taps).toBe(0);
  });

  it('puts real, eligible cards in the deck', async () => {
    const room = await roomId(slug);
    const river = PEOPLE.find((p) => p.handle === 'river')!;
    const { data, error } = await db.rpc('get_deck', {
      p_viewer_id: personId(slug, river.handle),
      p_room_id: room,
      p_filters: {},
      p_offset: 0,
    });
    expect(error).toBeNull();
    const deck = data as { cards: { id: string }[] };
    const expected = PEOPLE.filter(
      (p) => p.handle !== 'river' && river.showMe.includes(p.gender) && p.showMe.includes('woman'),
    );
    expect(deck.cards).toHaveLength(expected.length);
  });

  it('makes nothing new when run again', async () => {
    const room = await roomId(slug);
    const before = await openCards(room);
    const summary = await seedDemo(db, make, { slug, refresh: false });
    expect(summary.room.created).toBe(false);
    expect(summary.peopleCreated).toBe(0);
    expect(summary.peopleUpdated).toBe(PEOPLE.length);
    expect(summary.cardsMade).toBe(0);
    expect(summary.cardsKept).toBe(PEOPLE.length);
    expect(await openCards(room)).toEqual(before);
    const { count } = await db
      .from('meeting_spots')
      .select('id', { count: 'exact', head: true })
      .eq('room_id', room);
    expect(count).toBe(VENUE.meetingSpots.length);
  });

  it('replaces every card with --refresh, and deletes the old photos', async () => {
    const room = await roomId(slug);
    const before = await openCards(room);
    const summary = await seedDemo(db, make, { slug, refresh: true });
    expect(summary.cardsMade).toBe(PEOPLE.length);
    const after = await openCards(room);
    expect(after).toHaveLength(PEOPLE.length);
    expect(after.some((c) => before.some((b) => b.id === c.id))).toBe(false);
    expect(await storedCards(room)).toEqual(after.map((c) => c.card_path).sort());
  });

  it('refuses a room that is not marked as test data, and touches nobody', async () => {
    const { error } = await db.from('rooms').insert({
      slug: realSlug,
      name: 'A real event room',
      lat: 37.8,
      lng: -122.45,
      starts_at: new Date(Date.now() - 3600_000).toISOString(),
      ends_at: new Date(Date.now() + 86_400_000).toISOString(),
    });
    expect(error).toBeNull();
    await expect(seedDemo(db, make, { slug: realSlug, refresh: false })).rejects.toThrow(
      SeedRefused,
    );
    const { data } = await db.auth.admin.getUserById(personId(realSlug, 'river'));
    expect(data.user).toBeNull();
    const { data: room } = await db.from('rooms').select('demo_mode').eq('slug', realSlug).single();
    expect(room!.demo_mode).toBe(false);
  });

  it('removes the seeded people and every card photo with --remove', async () => {
    const room = await roomId(slug);
    const removed = await removeSeed(db, slug);
    expect(removed.peopleRemoved).toBe(PEOPLE.length);
    expect(await storedCards(room)).toEqual([]);
    expect(await openCards(room)).toEqual([]);
    for (const id of ids) {
      const { data } = await db.auth.admin.getUserById(id);
      expect(data.user).toBeNull();
    }
    expect((await removeSeed(db, slug)).peopleRemoved).toBe(0);
  });
});
