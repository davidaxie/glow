/**
 * Rooms: create, change, meeting spots, poster token and the screen token. Every function
 * here assumes the caller is an admin (`access.ts` checks first) and throws the route
 * helper's HttpErrors, so the API and the admin web answer the same way.
 */
import { randomBytes } from 'node:crypto';
import {
  MEETING_SPOTS_MAX,
  MEETING_SPOTS_MIN,
  ROOM_RADIUS_DEFAULT_METERS,
  type AdminRoom,
  type AdminRoomCreate,
  type AdminRoomUpdate,
  type DisplayToken,
  type RoomStatus,
} from '@/contracts';
import { HttpError, badRequest, notFound } from '@/server/http';
import { logger } from '@/server/log';
import { deps } from './context';
import { roomLink } from './links';
import { displayToken } from './qr-token';
import { RepoConflict, type CardRecord, type RoomPatch, type RoomRecord } from './repo';
import { toAdminRoom } from './views';

export const DEFAULT_TIMEZONE = 'America/Los_Angeles';
const BASE32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

export const slugTaken = () =>
  new HttpError(409, 'slug_taken', 'Another room already uses that link name.');

/** IANA names this server knows. The database checks against its own list as well. */
export function isValidTimezone(tz: string): boolean {
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: tz });
    return tz.includes('/') || tz === 'UTC';
  } catch {
    return false;
  }
}

/** Trimmed, MEETING_SPOTS_MIN to MEETING_SPOTS_MAX, no two alike. */
export function cleanSpots(spots: readonly string[]): string[] {
  const names = spots.map((s) => s.trim().replace(/\s+/g, ' '));
  if (names.some((n) => n.length === 0 || n.length > 60)) {
    throw badRequest('Each meeting spot needs a name of 1 to 60 characters.');
  }
  if (names.length < MEETING_SPOTS_MIN || names.length > MEETING_SPOTS_MAX) {
    throw badRequest(`A room needs ${MEETING_SPOTS_MIN} to ${MEETING_SPOTS_MAX} meeting spots.`);
  }
  if (new Set(names.map((n) => n.toLowerCase())).size !== names.length) {
    throw badRequest('Two meeting spots have the same name.');
  }
  return names;
}

function checkTimes(startsAt: string, endsAt: string): void {
  if (Date.parse(endsAt) <= Date.parse(startsAt)) {
    throw badRequest('The room must end after it starts.');
  }
}

/** A fresh 16-character poster token. 32 divides 256, so every character is uniform. */
export function newStaticToken(): string {
  return [...randomBytes(16)].map((b) => BASE32[b % 32]).join('');
}

async function load(id: string): Promise<RoomRecord> {
  const room = await deps().repo.findRoom({ id });
  if (!room) throw notFound();
  return room;
}

export async function listRooms(): Promise<AdminRoom[]> {
  return (await deps().repo.listRooms()).map(toAdminRoom);
}

export async function getRoom(id: string): Promise<AdminRoom> {
  return toAdminRoom(await load(id));
}

export async function getRoomRecord(id: string): Promise<RoomRecord> {
  return load(id);
}

export async function getRoomBySlug(slug: string): Promise<RoomRecord> {
  const room = await deps().repo.findRoom({ slug });
  if (!room) throw notFound();
  return room;
}

export async function createRoom(input: AdminRoomCreate, adminId: string): Promise<AdminRoom> {
  const timezone = input.timezone ?? DEFAULT_TIMEZONE;
  if (!isValidTimezone(timezone)) throw badRequest('That timezone is not valid.');
  checkTimes(input.startsAt, input.endsAt);
  const name = input.name.trim();
  if (name.length === 0) throw badRequest('The room needs a name.');
  const spots = cleanSpots(input.spots);
  try {
    const room = await deps().repo.createRoom(
      {
        slug: input.slug,
        name,
        latitude: input.latitude,
        longitude: input.longitude,
        radiusM: input.radiusM ?? ROOM_RADIUS_DEFAULT_METERS,
        timezone,
        allowStaticQr: input.allowStaticQr ?? false,
        demoMode: input.demoMode ?? false,
        startsAt: input.startsAt,
        endsAt: input.endsAt,
      },
      spots,
    );
    // IDs and flags only. The room's center is a public venue, but it still isn't logged.
    logger.info('admin.room_created', {
      roomId: room.id,
      adminId,
      demoMode: room.demoMode,
      posters: room.allowStaticQr,
    });
    return toAdminRoom(room);
  } catch (error) {
    if (error instanceof RepoConflict && error.what === 'slug') throw slugTaken();
    if (error instanceof RepoConflict && error.what === 'check') {
      throw badRequest('The database refused one of those values.');
    }
    throw error;
  }
}

/** Deletes card photos now rather than waiting for the purge cron (P9 holds either way). */
async function removePhotos(cards: readonly CardRecord[]): Promise<void> {
  const paths = [...new Set(cards.map((c) => c.cardPath))];
  if (paths.length > 0) await deps().repo.deleteCardPhotos(paths);
}

export async function updateRoom(
  id: string,
  update: AdminRoomUpdate,
  adminId: string,
): Promise<AdminRoom> {
  const { repo, events, now } = deps();
  const before = await load(id);
  const startsAt = update.startsAt ?? before.startsAt;
  const endsAt = update.endsAt ?? before.endsAt;
  checkTimes(startsAt, endsAt);
  if (update.timezone !== undefined && !isValidTimezone(update.timezone)) {
    throw badRequest('That timezone is not valid.');
  }
  const patch: RoomPatch = { ...update };
  if (update.name !== undefined) {
    const name = update.name.trim();
    if (name.length === 0) throw badRequest('The room needs a name.');
    patch.name = name;
  }

  let after: RoomRecord | null;
  try {
    after = await repo.updateRoom(id, patch);
  } catch (error) {
    if (error instanceof RepoConflict && error.what === 'check') {
      throw badRequest('The database refused one of those values.');
    }
    throw error;
  }
  if (!after) throw notFound();

  const ended = after.status === 'ended' || Date.parse(after.endsAt) <= now();
  if (ended && (before.status !== 'ended' || update.endsAt !== undefined)) {
    // An ended room keeps no one: every check-in ends and its photo goes now.
    const closed = await repo.closeRoomCheckins(id);
    await removePhotos(closed);
  } else if (update.endsAt !== undefined && Date.parse(endsAt) < Date.parse(before.endsAt)) {
    // A check-in never outlasts its room (D15).
    await repo.clampRoomCheckins(id, new Date(Date.parse(endsAt)).toISOString());
  }

  if (deckChanges(before, after)) await events.deckChanged(id);

  logger.info('admin.room_updated', {
    roomId: id,
    adminId,
    fields: Object.keys(update).sort().join(','),
    status: after.status,
  });
  return toAdminRoom(after);
}

/** Whether people in the room should refetch their deck. */
function deckChanges(before: RoomRecord, after: RoomRecord): boolean {
  const changed = (a: RoomStatus, b: RoomStatus) => a !== b;
  return (
    changed(before.status, after.status) ||
    before.startsAt !== after.startsAt ||
    before.endsAt !== after.endsAt
  );
}

export async function replaceSpots(
  id: string,
  spots: readonly string[],
  adminId: string,
): Promise<AdminRoom> {
  const names = cleanSpots(spots);
  const room = await deps().repo.replaceSpots(id, names);
  if (!room) throw notFound();
  logger.info('admin.spots_replaced', { roomId: id, adminId, count: names.length });
  return toAdminRoom(room);
}

export async function rotateStaticToken(id: string, adminId: string): Promise<AdminRoom> {
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      const room = await deps().repo.setStaticToken(id, newStaticToken());
      if (!room) throw notFound();
      logger.info('admin.static_token_rotated', { roomId: id, adminId });
      return toAdminRoom(room);
    } catch (error) {
      if (!(error instanceof RepoConflict && error.what === 'static_token')) throw error;
    }
  }
  throw new Error('could not find a free poster token');
}

/** The current screen token and its link (`adminDisplayToken`). */
export function screenTokenFor(room: RoomRecord, nowMs: number): DisplayToken {
  const { token, windowEndsAt } = displayToken(room.qrSecret, nowMs);
  return { token, url: roomLink(room.slug, token), windowEndsAt: windowEndsAt.toISOString() };
}

export async function displayTokenFor(id: string): Promise<DisplayToken> {
  return screenTokenFor(await load(id), deps().now());
}
