/**
 * Looking up rooms, and checking a code or QR token against one. Owner: B2.
 *
 * A code or token only ever gets someone to the location check, never into a room.
 * A wrong code, a wrong token, and a room that doesn't exist all look the same (404).
 */
import { timingSafeEqual } from 'node:crypto';
import type { RoomAccess, RoomSummary } from '@/contracts';
import { verifyRoomToken } from '@/server/qr';
import { conflict, notFound } from '@/server/http';
import type { Db } from './db';

/** The room columns B2's routes read. `qr_secret` and the tokens never leave the server. */
const ROOM_COLUMNS =
  'id, slug, name, code, lat, lng, radius_m, qr_secret, static_qr_token, allow_static_qr, demo_mode, status, starts_at, ends_at' as const;

export type RoomRow = {
  readonly id: string;
  readonly slug: string;
  readonly name: string;
  readonly code: string;
  readonly lat: number;
  readonly lng: number;
  readonly radius_m: number;
  readonly qr_secret: string;
  readonly static_qr_token: string;
  readonly allow_static_qr: boolean;
  readonly demo_mode: boolean;
  readonly status: 'live' | 'paused' | 'ended';
  readonly starts_at: string;
  readonly ends_at: string;
};

/** Compared against when no room matched, so a miss takes about as long as a hit. */
const DECOY: Pick<RoomRow, 'qr_secret' | 'static_qr_token' | 'allow_static_qr'> = {
  qr_secret: '0'.repeat(64),
  static_qr_token: 'A'.repeat(16),
  allow_static_qr: false,
};

export async function roomById(db: Db, roomId: string): Promise<RoomRow | null> {
  const { data, error } = await db
    .from('rooms')
    .select(ROOM_COLUMNS)
    .eq('id', roomId)
    .maybeSingle();
  if (error) throw new Error('rooms lookup failed');
  return data;
}

/** The room a code or a slug plus token opens, or null. */
export async function roomForAccess(
  db: Db,
  access: RoomAccess,
  nowMs: number,
): Promise<RoomRow | null> {
  if (access.kind === 'code') {
    const { data, error } = await db
      .from('rooms')
      .select(ROOM_COLUMNS)
      .eq('code', access.code.toUpperCase())
      .maybeSingle();
    if (error) throw new Error('rooms lookup failed');
    return data;
  }
  const { data, error } = await db
    .from('rooms')
    .select(ROOM_COLUMNS)
    .eq('slug', access.slug)
    .maybeSingle();
  if (error) throw new Error('rooms lookup failed');
  const opens = verifyRoomToken(toSecrets(data ?? DECOY), access.token, nowMs);
  return data && opens ? data : null;
}

/** Whether this code or token opens this particular room. */
export function accessOpensRoom(room: RoomRow, access: RoomAccess, nowMs: number): boolean {
  if (access.kind === 'code') {
    const given = Buffer.from(access.code.toUpperCase(), 'utf8');
    const expected = Buffer.from(room.code, 'utf8');
    return given.length === expected.length && timingSafeEqual(given, expected);
  }
  const slugMatches = access.slug === room.slug;
  const tokenMatches = verifyRoomToken(toSecrets(room), access.token, nowMs);
  return slugMatches && tokenMatches;
}

function toSecrets(room: Pick<RoomRow, 'qr_secret' | 'static_qr_token' | 'allow_static_qr'>) {
  return {
    qrSecret: room.qr_secret,
    staticQrToken: room.static_qr_token,
    allowStaticQr: room.allow_static_qr,
  };
}

/**
 * The status the app sees. A live room past its end time is ended, even before an admin
 * or the purge job says so.
 */
export function effectiveStatus(
  room: Pick<RoomRow, 'status' | 'ends_at'>,
  nowMs: number,
): RoomRow['status'] {
  if (room.status === 'live' && nowMs >= Date.parse(room.ends_at)) return 'ended';
  return room.status;
}

/** Open for joining right now: live, started and not ended. */
export function isOpen(room: Pick<RoomRow, 'status' | 'starts_at' | 'ends_at'>, nowMs: number) {
  return (
    effectiveStatus(room, nowMs) === 'live' &&
    nowMs >= Date.parse(room.starts_at) &&
    nowMs < Date.parse(room.ends_at)
  );
}

/** What the app may know about a room: never its location or secrets. */
export function roomSummary(room: RoomRow, nowMs: number): RoomSummary {
  return {
    id: room.id,
    slug: room.slug,
    name: room.name,
    status: effectiveStatus(room, nowMs),
    startsAt: new Date(room.starts_at).toISOString(),
    endsAt: new Date(room.ends_at).toISOString(),
  };
}

/**
 * Rooms open only to people who finished onboarding (409 `onboarding_incomplete`).
 * Someone an admin banned gets the same 404 as a room that doesn't exist.
 */
export async function requireOnboarded(db: Db, userId: string): Promise<void> {
  const { data, error } = await db
    .from('profiles')
    .select('onboarding_step, banned_at')
    .eq('id', userId)
    .maybeSingle();
  if (error) throw new Error('profiles lookup failed');
  if (data?.banned_at) throw notFound();
  if (data?.onboarding_step !== 'complete') {
    throw conflict('onboarding_incomplete', 'Finish setting up your profile first.');
  }
}

export async function isAdmin(db: Db, userId: string): Promise<boolean> {
  const { data, error } = await db
    .from('admins')
    .select('user_id')
    .eq('user_id', userId)
    .maybeSingle();
  if (error) throw new Error('admins lookup failed');
  return data !== null;
}

export const roomNotLive = () => conflict('room_not_live', 'This room is not open right now.');
