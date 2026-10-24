#!/usr/bin/env -S node --disable-warning=MODULE_TYPELESS_PACKAGE_JSON
/**
 * scripts/seed-demo.ts · D5 · A realistic demo room, made only of test data.
 *
 *   scripts/seed-demo.ts                  # seed or refresh the local `demo` room
 *   scripts/seed-demo.ts --refresh        # also replace every seeded card (fresh 3 hours)
 *   scripts/seed-demo.ts --demo-mode      # also turn demo mode on for an existing room
 *   scripts/seed-demo.ts --remove         # delete the seeded people and their card photos
 *   scripts/seed-demo.ts --print-venue    # the venue values, for the admin web and sim.sh
 *   scripts/seed-demo.ts --remote         # allow a Supabase that isn't on this machine
 *
 * (`node scripts/seed-demo.ts …` works too; it only adds a warning about module type.)
 *
 * It talks to Supabase with SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY from the environment,
 * or from server/.env.local (what `pnpm env:setup` writes) when they aren't set. It refuses
 * any URL that isn't localhost, 127.0.0.1 or [::1] unless `--remote` is passed.
 *
 * What it makes (docs/DEMO.md, "The seeded room"):
 *   - the room (slug `demo` unless `--slug`), at VENUE below, live for the day, with VENUE's
 *     meeting spots. A room it creates has demo mode on; an existing room keeps its setting
 *     unless `--demo-mode` is passed, so the shared local `demo` room behaves as A2 seeded it. A room is only ever touched if its name ends in
 *     "(test data)", so this can never put test people into a real event room (D5-D1).
 *   - PEOPLE below: adults with `@glow.test` emails, first names starting with "Test", and
 *     `test_data` in their auth metadata. They have no profile photos, and never tap anyone.
 *   - one card each, from the public-domain NASA outfit crops in ios/fixtures/photos
 *     (`outfit-real-*`, neck down, name tags pixelated), flipped and cropped a little so the
 *     deck doesn't show the same picture twice. No other photos of real people, ever.
 *
 * It's idempotent: people have fixed IDs (derived from the room slug), the room and its spots
 * are updated in place, and a card that still has an hour left is kept. Running it twice
 * makes nothing new. It never prints keys.
 *
 * The venue is a PLACEHOLDER until David confirms the Cal Hacks venue: change VENUE, and
 * only VENUE, to move it (D5-D4).
 */
import { createHash, randomUUID } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

// ---------------------------------------------------------------------------------------------
// The venue: the one place to change it
// ---------------------------------------------------------------------------------------------

export const VENUE = {
  /** False until David confirms the Cal Hacks venue, meeting spots and table (Needs David). */
  confirmed: false,
  place: 'Palace of Fine Arts, San Francisco (placeholder)',
  lat: 37.8029,
  lng: -122.4484,
  radiusM: 200,
  timezone: 'America/Los_Angeles',
  /** 3 to 5 places everyone in the hall will recognize. Glow sends matches to one of them. */
  meetingSpots: ['Main entrance', 'Food line', 'Water station', 'Stage left'],
  /** Where the Glow table and the display laptop are. Printed on the checklist only. */
  table: 'Not chosen yet',
} as const;

/** The seeded room. Its name must keep ending in TEST_ROOM_MARK. */
export const DEMO_ROOM = { slug: 'demo', name: 'Glow demo room (test data)' } as const;
export const TEST_ROOM_MARK = '(test data)';

// ---------------------------------------------------------------------------------------------
// The people: all test data
// ---------------------------------------------------------------------------------------------

type Gender = 'woman' | 'man' | 'nonbinary';
type TopColor =
  'black' | 'white' | 'gray' | 'red' | 'pink' | 'orange' | 'yellow' | 'green' | 'blue' | 'purple';
type HairLength = 'short' | 'medium' | 'long';
type HairColor = 'black' | 'brown' | 'blonde' | 'red' | 'gray' | 'dyed';
type CardExtra = 'glasses' | 'hat' | 'beard' | 'headphones' | 'backpack';

export type Photo =
  | 'outfit-real-blue-flightsuit.jpg'
  | 'outfit-real-white-suit.jpg'
  | 'outfit-real-lightblue-suit.jpg';

/** How a fixture is changed for one card: mirrored, cropped in, nudged and lit a little. */
export type Variant = {
  readonly flop: boolean;
  /** Share of the width and height kept, 0.75 to 1. */
  readonly zoom: number;
  /** Where the crop sits, -1 (left or top) to 1 (right or bottom). */
  readonly shiftX: number;
  readonly shiftY: number;
  /** 0.9 to 1.1. */
  readonly brightness: number;
};

export type SeedPerson = {
  readonly handle: string;
  readonly firstName: string;
  readonly birthdate: string;
  readonly gender: Gender;
  readonly showMe: readonly Gender[];
  readonly photo: Photo;
  readonly variant: Variant;
  readonly tags: {
    readonly topColor: TopColor;
    readonly hairLength?: HairLength;
    readonly hairColor?: HairColor;
    readonly extras: readonly CardExtra[];
  };
};

const FULL: Variant = { flop: false, zoom: 1, shiftX: 0, shiftY: 0, brightness: 1 };
const MIRROR: Variant = { flop: true, zoom: 0.94, shiftX: 0, shiftY: -0.4, brightness: 1.05 };
const CLOSE: Variant = { flop: false, zoom: 0.82, shiftX: 0.3, shiftY: -0.6, brightness: 0.95 };
const CLOSE_MIRROR: Variant = {
  flop: true,
  zoom: 0.86,
  shiftX: -0.4,
  shiftY: 0.5,
  brightness: 1.08,
};

const FLIGHTSUIT: Photo = 'outfit-real-blue-flightsuit.jpg';
const WHITE_SUIT: Photo = 'outfit-real-white-suit.jpg';
const LIGHTBLUE_SUIT: Photo = 'outfit-real-lightblue-suit.jpg';

/**
 * Twelve people, so that whoever is on stage sees a few cards whatever their gender and show
 * me. Hair isn't visible in the crops; hair tags are what each test person "said" about
 * themselves, so the What did you notice filters have something to narrow.
 */
export const PEOPLE: readonly SeedPerson[] = [
  {
    handle: 'river',
    firstName: 'Test River',
    birthdate: '1998-03-14',
    gender: 'woman',
    showMe: ['man'],
    photo: FLIGHTSUIT,
    variant: FULL,
    tags: { topColor: 'blue', hairLength: 'long', hairColor: 'brown', extras: [] },
  },
  {
    handle: 'sage',
    firstName: 'Test Sage',
    birthdate: '1999-07-02',
    gender: 'woman',
    showMe: ['man', 'nonbinary'],
    photo: WHITE_SUIT,
    variant: FULL,
    tags: { topColor: 'white', hairLength: 'medium', hairColor: 'black', extras: [] },
  },
  {
    handle: 'quinn',
    firstName: 'Test Quinn',
    birthdate: '2000-11-21',
    gender: 'nonbinary',
    showMe: ['woman', 'man', 'nonbinary'],
    photo: LIGHTBLUE_SUIT,
    variant: FULL,
    tags: { topColor: 'blue', hairLength: 'short', hairColor: 'dyed', extras: [] },
  },
  {
    handle: 'rowan',
    firstName: 'Test Rowan',
    birthdate: '1997-01-30',
    gender: 'man',
    showMe: ['woman'],
    photo: FLIGHTSUIT,
    variant: MIRROR,
    tags: { topColor: 'blue', hairLength: 'short', hairColor: 'black', extras: [] },
  },
  {
    handle: 'emery',
    firstName: 'Test Emery',
    birthdate: '1996-05-09',
    gender: 'man',
    showMe: ['woman', 'nonbinary'],
    photo: WHITE_SUIT,
    variant: MIRROR,
    tags: { topColor: 'white', hairLength: 'short', hairColor: 'brown', extras: [] },
  },
  {
    handle: 'harper',
    firstName: 'Test Harper',
    birthdate: '2001-09-17',
    gender: 'woman',
    showMe: ['woman', 'nonbinary'],
    photo: LIGHTBLUE_SUIT,
    variant: MIRROR,
    tags: { topColor: 'blue', hairLength: 'long', hairColor: 'blonde', extras: [] },
  },
  {
    handle: 'jules',
    firstName: 'Test Jules',
    birthdate: '1999-12-03',
    gender: 'man',
    showMe: ['woman', 'man'],
    photo: FLIGHTSUIT,
    variant: CLOSE,
    tags: { topColor: 'blue', hairLength: 'medium', hairColor: 'brown', extras: [] },
  },
  {
    handle: 'avery',
    firstName: 'Test Avery',
    birthdate: '1998-08-25',
    gender: 'woman',
    showMe: ['man', 'woman'],
    photo: WHITE_SUIT,
    variant: CLOSE,
    tags: { topColor: 'white', hairLength: 'short', hairColor: 'red', extras: [] },
  },
  {
    handle: 'kai',
    firstName: 'Test Kai',
    birthdate: '2002-02-11',
    gender: 'nonbinary',
    showMe: ['woman', 'man', 'nonbinary'],
    photo: LIGHTBLUE_SUIT,
    variant: CLOSE,
    tags: { topColor: 'blue', hairLength: 'medium', hairColor: 'black', extras: [] },
  },
  {
    handle: 'noor',
    firstName: 'Test Noor',
    birthdate: '1997-06-19',
    gender: 'woman',
    showMe: ['man'],
    photo: FLIGHTSUIT,
    variant: CLOSE_MIRROR,
    tags: { topColor: 'blue', hairLength: 'long', hairColor: 'black', extras: [] },
  },
  {
    handle: 'milan',
    firstName: 'Test Milan',
    birthdate: '1995-10-08',
    gender: 'man',
    showMe: ['woman'],
    photo: WHITE_SUIT,
    variant: CLOSE_MIRROR,
    tags: { topColor: 'white', hairLength: 'short', hairColor: 'gray', extras: [] },
  },
  {
    handle: 'remy',
    firstName: 'Test Remy',
    birthdate: '2000-04-27',
    gender: 'woman',
    showMe: ['man', 'nonbinary'],
    photo: LIGHTBLUE_SUIT,
    variant: CLOSE_MIRROR,
    tags: { topColor: 'blue', hairLength: 'medium', hairColor: 'brown', extras: [] },
  },
];

/** Auth metadata every seeded person carries, so test data can always be found and removed. */
export const TEST_APP_METADATA = { test_data: true, seeded_by: 'seed-demo' } as const;
export const TEST_USER_METADATA = { glow_test_data: true, test_data: true } as const;

/** A card made in the last run is kept if it has at least this long left. */
export const KEEP_CARD_FOR_MS = 60 * 60 * 1000;

// ---------------------------------------------------------------------------------------------
// Pure helpers (tested in server/tests/seed-demo/)
// ---------------------------------------------------------------------------------------------

export type SeedOptions = {
  readonly remote: boolean;
  readonly refresh: boolean;
  readonly remove: boolean;
  readonly printVenue: boolean;
  readonly help: boolean;
  readonly demoMode: boolean;
  readonly slug: string;
};

export class SeedRefused extends Error {
  override readonly name = 'SeedRefused';
}

const SLUG_PATTERN = /^[a-z0-9](?:[a-z0-9-]{0,38}[a-z0-9])?$/;

export function parseArgs(argv: readonly string[]): SeedOptions {
  const options = {
    remote: false,
    refresh: false,
    remove: false,
    printVenue: false,
    help: false,
    demoMode: false,
    slug: DEMO_ROOM.slug as string,
  };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--remote') options.remote = true;
    else if (arg === '--refresh') options.refresh = true;
    else if (arg === '--remove') options.remove = true;
    else if (arg === '--print-venue') options.printVenue = true;
    else if (arg === '--demo-mode') options.demoMode = true;
    else if (arg === '--help' || arg === '-h') options.help = true;
    else if (arg === '--slug') {
      const slug = argv[++i];
      if (!slug || !SLUG_PATTERN.test(slug)) throw new SeedRefused('--slug needs a room slug.');
      options.slug = slug;
    } else throw new SeedRefused(`Unknown option ${arg}. Try --help.`);
  }
  if (options.refresh && options.remove) {
    throw new SeedRefused('Pick one of --refresh and --remove.');
  }
  return options;
}

/** True only for a Supabase on this machine. */
export function isLocalUrl(url: string): boolean {
  let host: string;
  try {
    host = new URL(url).hostname;
  } catch {
    return false;
  }
  return (
    host === 'localhost' ||
    host === '127.0.0.1' ||
    host === '[::1]' ||
    host === '::1' ||
    host.endsWith('.localhost')
  );
}

/** Refuses a non-local Supabase unless `--remote` was passed. */
export function assertSafeTarget(url: string, remote: boolean): void {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    throw new SeedRefused('SUPABASE_URL is not a URL.');
  }
  if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
    throw new SeedRefused('SUPABASE_URL must be http or https.');
  }
  if (!isLocalUrl(url) && !remote) {
    throw new SeedRefused(
      `Refusing to seed ${parsed.host}: it isn't a local Supabase. ` +
        'Pass --remote if you really mean to put test data there.',
    );
  }
}

/** A fixed UUID per room and person, so running the seed again finds the same people. */
export function personId(slug: string, handle: string): string {
  const hex = createHash('sha256').update(`glow-seed-demo:${slug}:${handle}`).digest('hex');
  const variant = ((parseInt(hex[16]!, 16) & 0x3) | 0x8).toString(16);
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-4${hex.slice(13, 16)}-${variant}${hex.slice(17, 20)}-${hex.slice(20, 32)}`;
}

export function personEmail(slug: string, handle: string): string {
  return `${slug}-${handle}@glow.test`;
}

export function isTestRoomName(name: string): boolean {
  return name.trim().endsWith(TEST_ROOM_MARK);
}

/** The shared numbers, read from contracts/constants.json so nothing here is hardcoded. */
export function readConstants(): Record<string, number> {
  const file = fileURLToPath(new URL('../contracts/constants.json', import.meta.url));
  const parsed = JSON.parse(readFileSync(file, 'utf8')) as {
    constants: Record<string, { value: number }>;
  };
  return Object.fromEntries(Object.entries(parsed.constants).map(([k, v]) => [k, v.value]));
}

export function fixturePath(photo: Photo): string {
  return fileURLToPath(new URL(`../ios/fixtures/photos/${photo}`, import.meta.url));
}

/** Checks VENUE against the contract's limits. Throws SeedRefused with every problem. */
export function checkVenue(constants: Record<string, number>): void {
  const problems: string[] = [];
  const spots = VENUE.meetingSpots.length;
  if (spots < constants.MEETING_SPOTS_MIN! || spots > constants.MEETING_SPOTS_MAX!) {
    problems.push(
      `VENUE needs ${constants.MEETING_SPOTS_MIN} to ${constants.MEETING_SPOTS_MAX} meeting spots.`,
    );
  }
  if (new Set(VENUE.meetingSpots.map((s) => s.trim().toLowerCase())).size !== spots) {
    problems.push('VENUE meeting spots must all be different.');
  }
  if (VENUE.meetingSpots.some((s) => s.trim().length < 1 || s.length > 60)) {
    problems.push('Each meeting spot name is 1 to 60 characters.');
  }
  if (Math.abs(VENUE.lat) > 90 || Math.abs(VENUE.lng) > 180) problems.push('VENUE is off the map.');
  if (VENUE.radiusM < 10 || VENUE.radiusM > 5000) problems.push('VENUE radius is 10 to 5000 m.');
  if (problems.length) throw new SeedRefused(problems.join(' '));
}

/** The crop rectangle for one card, inside a w by h fixture. */
export function cropFor(
  width: number,
  height: number,
  v: Variant,
): { left: number; top: number; width: number; height: number } {
  const w = Math.max(1, Math.round(width * v.zoom));
  const h = Math.max(1, Math.round(height * v.zoom));
  const spareX = width - w;
  const spareY = height - h;
  const left = Math.round((spareX / 2) * (1 + Math.max(-1, Math.min(1, v.shiftX))));
  const top = Math.round((spareY / 2) * (1 + Math.max(-1, Math.min(1, v.shiftY))));
  return { left: Math.min(left, spareX), top: Math.min(top, spareY), width: w, height: h };
}

/** What `--print-venue` prints: shell lines for sim.sh, then the admin web checklist. */
export function venueText(): string {
  return [
    `# ${VENUE.place}${VENUE.confirmed ? '' : ' -- NOT CONFIRMED'}`,
    `GLOW_DEMO_LAT="${VENUE.lat}"`,
    `GLOW_DEMO_LNG="${VENUE.lng}"`,
    `# Room radius: ${VENUE.radiusM} m, timezone ${VENUE.timezone}`,
    `# Meeting spots: ${VENUE.meetingSpots.join(', ')}`,
    `# Glow table: ${VENUE.table}`,
  ].join('\n');
}

/** The lat and lng in ios/fixtures/demo-room.env, which `sim.sh at venue` uses. */
export function simVenue(): { lat: number; lng: number } | null {
  const file = fileURLToPath(new URL('../ios/fixtures/demo-room.env', import.meta.url));
  if (!existsSync(file)) return null;
  const text = readFileSync(file, 'utf8');
  const lat = /^GLOW_DEMO_LAT="?([-0-9.]+)"?/m.exec(text)?.[1];
  const lng = /^GLOW_DEMO_LNG="?([-0-9.]+)"?/m.exec(text)?.[1];
  return lat && lng ? { lat: Number(lat), lng: Number(lng) } : null;
}

// ---------------------------------------------------------------------------------------------
// Talking to Supabase
// ---------------------------------------------------------------------------------------------

/**
 * The Supabase service-role client, typed loosely: this script lives outside the server
 * package and loads @supabase/supabase-js from it at run time.
 */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export type Db = any;

/** Turns a JPEG fixture into one card's bytes. Injected so tests can use the real sharp. */
export type MakeCard = (file: string, variant: Variant) => Promise<Uint8Array>;

export type SeedLog = (line: string) => void;

export type SeedSummary = {
  readonly room: {
    readonly id: string;
    readonly slug: string;
    readonly name: string;
    readonly code: string;
    readonly created: boolean;
    readonly demoMode: boolean;
    readonly staticLink: string | null;
  };
  readonly peopleCreated: number;
  readonly peopleUpdated: number;
  readonly cardsMade: number;
  readonly cardsKept: number;
  readonly skipped: readonly string[];
};

const CARDS_BUCKET = 'room-cards';

async function must<T>(
  what: string,
  promise: PromiseLike<{ data: T; error: unknown }>,
): Promise<T> {
  const { data, error } = await promise;
  if (error) {
    const message = (error as { message?: string }).message ?? String(error);
    throw new Error(`${what}: ${message}`);
  }
  return data;
}

type RoomRow = {
  id: string;
  slug: string;
  name: string;
  code: string;
  static_qr_token: string;
  allow_static_qr: boolean;
  demo_mode: boolean;
  starts_at: string;
  ends_at: string;
};

const ROOM_COLUMNS =
  'id, slug, name, code, static_qr_token, allow_static_qr, demo_mode, starts_at, ends_at';

async function findRoom(db: Db, slug: string): Promise<RoomRow | null> {
  const rows = await must<RoomRow[]>(
    'read room',
    db.from('rooms').select(ROOM_COLUMNS).eq('slug', slug).limit(1),
  );
  return rows[0] ?? null;
}

/** Creates the room, or moves an existing test room to VENUE and keeps it live for the day. */
async function upsertRoom(
  db: Db,
  slug: string,
  demoMode: boolean,
  now: Date,
): Promise<{ row: RoomRow; created: boolean }> {
  const name = slug === DEMO_ROOM.slug ? DEMO_ROOM.name : `Glow ${slug} room ${TEST_ROOM_MARK}`;
  const venue = {
    lat: VENUE.lat,
    lng: VENUE.lng,
    radius_m: VENUE.radiusM,
    timezone: VENUE.timezone,
    status: 'live',
  };
  const existing = await findRoom(db, slug);
  if (existing && !isTestRoomName(existing.name)) {
    throw new SeedRefused(
      `The room "${slug}" exists and isn't a test room (its name doesn't end in ` +
        `"${TEST_ROOM_MARK}"). The seed never puts test people into a real room.`,
    );
  }
  const dayLater = new Date(now.getTime() + 24 * 3600_000);
  if (existing) {
    const startsAt = new Date(existing.starts_at) > now ? new Date(now.getTime() - 3600_000) : null;
    const endsAt =
      new Date(existing.ends_at).getTime() < now.getTime() + 12 * 3600_000 ? dayLater : null;
    const rows = await must<RoomRow[]>(
      'update room',
      db
        .from('rooms')
        .update({
          ...venue,
          name,
          ...(demoMode ? { demo_mode: true } : {}),
          ...(startsAt ? { starts_at: startsAt.toISOString() } : {}),
          ...(endsAt ? { ends_at: endsAt.toISOString() } : {}),
          updated_at: now.toISOString(),
        })
        .eq('id', existing.id)
        .select(ROOM_COLUMNS),
    );
    return { row: rows[0]!, created: false };
  }
  const rows = await must<RoomRow[]>(
    'create room',
    db
      .from('rooms')
      .insert({
        ...venue,
        slug,
        name,
        demo_mode: true,
        allow_static_qr: false,
        starts_at: new Date(now.getTime() - 3600_000).toISOString(),
        ends_at: dayLater.toISOString(),
      })
      .select(ROOM_COLUMNS),
  );
  return { row: rows[0]!, created: true };
}

/** Makes the room's meeting spots exactly VENUE's, renaming in place so a live glow keeps its spot. */
async function syncSpots(db: Db, roomId: string): Promise<void> {
  type Spot = { id: string; name: string; sort: number };
  const spots = await must<Spot[]>(
    'read spots',
    db.from('meeting_spots').select('id, name, sort').eq('room_id', roomId).order('sort'),
  );
  const bySort = new Map(spots.map((s) => [s.sort, s]));
  for (const [sort, name] of VENUE.meetingSpots.entries()) {
    const spot = bySort.get(sort);
    if (spot && spot.name !== name) {
      await must('rename spot', db.from('meeting_spots').update({ name }).eq('id', spot.id));
    } else if (!spot) {
      await must('add spot', db.from('meeting_spots').insert({ room_id: roomId, name, sort }));
    }
  }
  const extra = spots.filter((s) => s.sort >= VENUE.meetingSpots.length).map((s) => s.id);
  if (extra.length) await must('remove spots', db.from('meeting_spots').delete().in('id', extra));
}

/** Creates the person if needed (with a fixed ID), and sets their test profile. */
async function ensurePerson(
  db: Db,
  slug: string,
  person: SeedPerson,
): Promise<'created' | 'updated'> {
  const id = personId(slug, person.handle);
  const email = personEmail(slug, person.handle);
  const found = await db.auth.admin.getUserById(id);
  let outcome: 'created' | 'updated';
  if (found.data?.user) {
    if (found.data.user.email !== email) {
      throw new SeedRefused(`User ${id} exists with a different email; not touching it.`);
    }
    await must(
      'update person',
      db.auth.admin.updateUserById(id, {
        app_metadata: TEST_APP_METADATA,
        user_metadata: TEST_USER_METADATA,
      }),
    );
    outcome = 'updated';
  } else {
    await must(
      'create person',
      db.auth.admin.createUser({
        id,
        email,
        email_confirm: true,
        app_metadata: TEST_APP_METADATA,
        user_metadata: TEST_USER_METADATA,
      }),
    );
    outcome = 'created';
  }
  await must(
    'set profile',
    db
      .from('profiles')
      .update({
        first_name: person.firstName,
        birthdate: person.birthdate,
        gender: person.gender,
        show_me: [...person.showMe],
        onboarding_step: 'complete',
        paused: false,
      })
      .eq('id', id),
  );
  return outcome;
}

type OpenCheckin = { id: string; user_id: string; expires_at: string };

/**
 * Seeds (or refreshes) the room, its people and their cards. Never touches a room whose name
 * doesn't end in "(test data)", and never anyone outside PEOPLE.
 */
export async function seedDemo(
  db: Db,
  makeCard: MakeCard,
  options: Pick<SeedOptions, 'slug' | 'refresh'> & { readonly demoMode?: boolean },
  log: SeedLog = () => {},
  now: Date = new Date(),
): Promise<SeedSummary> {
  const constants = readConstants();
  checkVenue(constants);

  const { row: room, created } = await upsertRoom(db, options.slug, options.demoMode ?? false, now);
  log(`${created ? 'Created' : 'Updated'} room ${room.slug} (${room.name}).`);
  await syncSpots(db, room.id);

  let peopleCreated = 0;
  let peopleUpdated = 0;
  for (const person of PEOPLE) {
    const outcome = await ensurePerson(db, options.slug, person);
    if (outcome === 'created') peopleCreated++;
    else peopleUpdated++;
  }
  log(`People: ${peopleCreated} new, ${peopleUpdated} already there.`);

  const ids = PEOPLE.map((p) => personId(options.slug, p.handle));
  const open = await must<OpenCheckin[]>(
    'read cards',
    db
      .from('checkins')
      .select('id, user_id, expires_at')
      .eq('room_id', room.id)
      .in('user_id', ids)
      .is('left_at', null),
  );
  const openByUser = new Map(open.map((c) => [c.user_id, c]));

  let cardsMade = 0;
  let cardsKept = 0;
  const skipped: string[] = [];
  for (const person of PEOPLE) {
    const userId = personId(options.slug, person.handle);
    const current = openByUser.get(userId);
    const leftMs = current ? new Date(current.expires_at).getTime() - now.getTime() : 0;
    if (current && leftMs >= KEEP_CARD_FOR_MS && !options.refresh) {
      cardsKept++;
      continue;
    }
    const made = await makeCheckin(db, makeCard, room.id, userId, person, constants);
    if (made) cardsMade++;
    else skipped.push(person.firstName);
  }
  log(`Cards: ${cardsMade} made, ${cardsKept} kept.`);
  if (skipped.length) log(`Skipped (banned by an admin, left as they are): ${skipped.join(', ')}.`);

  return {
    room: {
      id: room.id,
      slug: room.slug,
      name: room.name,
      code: room.code,
      created,
      demoMode: room.demo_mode,
      staticLink: room.allow_static_qr ? `glow://r/${room.slug}?t=${room.static_qr_token}` : null,
    },
    peopleCreated,
    peopleUpdated,
    cardsMade,
    cardsKept,
    skipped,
  };
}

/**
 * One card, the way B2 and B3 make them: the photo goes into private storage first, then a
 * join check, then create_checkin. The join check is recorded as `demo_skip` (D5-D3): these
 * people never stood anywhere, and the room's demo-mode skip count shows them honestly.
 */
async function makeCheckin(
  db: Db,
  makeCard: MakeCard,
  roomId: string,
  userId: string,
  person: SeedPerson,
  constants: Record<string, number>,
): Promise<boolean> {
  const bytes = await makeCard(fixturePath(person.photo), person.variant);
  if (bytes.byteLength > constants.PHOTO_MAX_BYTES!) {
    throw new Error(`The card for ${person.firstName} is over PHOTO_MAX_BYTES.`);
  }
  const cardId = randomUUID();
  const path = `${roomId}/${cardId}.jpg`;
  await must(
    'upload card',
    db.storage.from(CARDS_BUCKET).upload(path, bytes, { contentType: 'image/jpeg', upsert: false }),
  );
  let replaced: string[];
  try {
    await must(
      'join check',
      db.from('location_checks').insert({
        user_id: userId,
        room_id: roomId,
        purpose: 'join',
        result: 'demo_skip',
        accuracy_bucket: null,
      }),
    );
    const { data, error } = await db.rpc('create_checkin', {
      p_user_id: userId,
      p_room_id: roomId,
      p_checkin_id: cardId,
      p_card_path: path,
      p_tags: { ...person.tags, extras: [...person.tags.extras] },
    });
    if (error) {
      // not_found: an admin banned this test person. Leave them be.
      if (/not_found/.test(String(error.message))) {
        await db.storage.from(CARDS_BUCKET).remove([path]);
        return false;
      }
      throw new Error(`create_checkin: ${error.message}`);
    }
    replaced = (data as { replacedCardPaths?: string[] } | null)?.replacedCardPaths ?? [];
  } catch (error) {
    // No check-in points at the photo, so it goes (purge would delete it in 2 minutes anyway).
    await db.storage.from(CARDS_BUCKET).remove([path]);
    throw error;
  }
  if (replaced.length) {
    await must('delete old cards', db.storage.from(CARDS_BUCKET).remove(replaced));
  }
  return true;
}

/**
 * Deletes the seeded people of one room and every card photo they ever had there. Deleting
 * the auth user removes the profile, check-ins and everything else by cascade. The room stays.
 */
export async function removeSeed(
  db: Db,
  slug: string,
  log: SeedLog = () => {},
): Promise<{ peopleRemoved: number; photosRemoved: number }> {
  const ids = PEOPLE.map((p) => personId(slug, p.handle));
  const cards = await must<{ card_path: string }[]>(
    'read cards',
    db.from('checkins').select('card_path').in('user_id', ids),
  );
  const paths = cards.map((c) => c.card_path);
  for (let i = 0; i < paths.length; i += 100) {
    await must('delete cards', db.storage.from(CARDS_BUCKET).remove(paths.slice(i, i + 100)));
  }
  let peopleRemoved = 0;
  for (const person of PEOPLE) {
    const id = personId(slug, person.handle);
    const found = await db.auth.admin.getUserById(id);
    const user = found.data?.user;
    if (!user) continue;
    if (user.email !== personEmail(slug, person.handle) || user.app_metadata?.test_data !== true) {
      log(`Left ${id} alone: it isn't a seeded test person.`);
      continue;
    }
    await must('delete person', db.auth.admin.deleteUser(id));
    peopleRemoved++;
  }
  log(`Removed ${peopleRemoved} seeded people and ${paths.length} card photos.`);
  return { peopleRemoved, photosRemoved: paths.length };
}

// ---------------------------------------------------------------------------------------------
// Running it
// ---------------------------------------------------------------------------------------------

const HELP = `Usage: scripts/seed-demo.ts [--refresh | --remove] [--demo-mode] [--slug <slug>] [--remote]
       scripts/seed-demo.ts --print-venue

Seeds a demo room with ${PEOPLE.length} test people (@glow.test) and their cards.
  --refresh      replace every seeded card, so each has a fresh 3 hours
  --demo-mode    turn demo mode on for an existing room (new rooms always get it)
  --remove       delete the seeded people and their card photos (the room stays)
  --slug <slug>  another test room (default: ${DEMO_ROOM.slug})
  --remote       allow a Supabase that isn't on this machine
  --print-venue  print the venue values (for sim.sh and the admin web) and stop

Reads SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY, or server/.env.local.`;

function loadEnvFile(): void {
  const file = fileURLToPath(new URL('../server/.env.local', import.meta.url));
  if (existsSync(file)) process.loadEnvFile(file);
}

function loadServerModules(): { createClient: (...args: unknown[]) => Db; sharp: Db } {
  const require = createRequire(new URL('../server/package.json', import.meta.url));
  try {
    const { createClient } = require('@supabase/supabase-js');
    const sharp = require('sharp');
    return { createClient, sharp };
  } catch {
    throw new SeedRefused('Run `pnpm install` first: the seed uses the server package.');
  }
}

/** Real cards: cropped, mirrored and lit per Variant, at most 1920 px, JPEG 80, no metadata. */
export function sharpCardMaker(sharp: Db, constants: Record<string, number>): MakeCard {
  return async (file, variant) => {
    const meta = await sharp(file, { autoOrient: true }).metadata();
    const width = meta.autoOrient?.width ?? meta.width;
    const height = meta.autoOrient?.height ?? meta.height;
    let pipeline = sharp(file, { autoOrient: true }).extract(cropFor(width, height, variant));
    if (variant.flop) pipeline = pipeline.flop();
    const max = constants.PHOTO_MAX_DIMENSION!;
    const buffer: Uint8Array = await pipeline
      .modulate({ brightness: variant.brightness })
      .resize({ width: max, height: max, fit: 'inside', withoutEnlargement: true })
      .jpeg({ quality: constants.PHOTO_JPEG_QUALITY! })
      .toBuffer();
    return buffer;
  };
}

async function main(argv: readonly string[]): Promise<number> {
  const options = parseArgs(argv);
  if (options.help) {
    console.log(HELP);
    return 0;
  }
  if (options.printVenue) {
    console.log(venueText());
    return 0;
  }
  if (!process.env.SUPABASE_URL || !process.env.SUPABASE_SERVICE_ROLE_KEY) loadEnvFile();
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) {
    throw new SeedRefused(
      'Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY, or run `pnpm env:setup` for a local one.',
    );
  }
  assertSafeTarget(url, options.remote);

  const { createClient, sharp } = loadServerModules();
  const db = createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
  const log: SeedLog = (line) => console.log(line);
  const target = new URL(url).host;
  console.log(`Seeding test data into ${target}${isLocalUrl(url) ? ' (local)' : ' (REMOTE)'}.`);
  if (!VENUE.confirmed) console.log(`Venue: ${VENUE.place}. Confirm it before the event.`);

  if (options.remove) {
    await removeSeed(db, options.slug, log);
    return 0;
  }

  const summary = await seedDemo(db, sharpCardMaker(sharp, readConstants()), options, log);
  const sim = simVenue();
  if (options.slug === DEMO_ROOM.slug && sim && (sim.lat !== VENUE.lat || sim.lng !== VENUE.lng)) {
    console.log(
      'Note: ios/fixtures/demo-room.env has a different center, so `sim.sh at venue` puts the ' +
        'Simulators somewhere else. Copy these lines into it:\n' +
        `GLOW_DEMO_LAT="${VENUE.lat}"\nGLOW_DEMO_LNG="${VENUE.lng}"`,
    );
  }
  console.log(
    [
      '',
      `Room: ${summary.room.name}`,
      `  slug ${summary.room.slug}, code ${summary.room.code}, demo mode ${summary.room.demoMode ? 'on' : 'off'}`,
      summary.room.staticLink ? `  link ${summary.room.staticLink}` : '  printed posters off',
      `  ${summary.cardsMade + summary.cardsKept} cards in the deck (${PEOPLE.length} test people)`,
    ].join('\n'),
  );
  return 0;
}

const invokedDirectly =
  process.argv[1] !== undefined && fileURLToPath(import.meta.url) === process.argv[1];

if (invokedDirectly) {
  main(process.argv.slice(2)).then(
    (code) => process.exit(code),
    (error: unknown) => {
      if (error instanceof SeedRefused) {
        console.error(error.message);
        process.exit(2);
      }
      console.error(error instanceof Error ? error.message : error);
      process.exit(1);
    },
  );
}
