/**
 * Live counts for a room, from `room_activity` (anonymous counters, D30) and a count of open
 * check-ins. Nothing here can name a person.
 *
 * There is no tap count (P5, D52): an admin standing in the room, watching a tap count tick
 * up as someone looks at their phone, could learn that that person just tapped someone.
 * A2's contract change (#14) removes `taps` from RoomMetrics and stops tap activity rows;
 * until it merges, the field the old contract still requires is always 0.
 */
import type { RoomMetrics } from '@/contracts';
import { badRequest } from '@/server/http';
import { deps } from './context';
import { getRoomRecord } from './rooms';

/** How far `timeZone` is ahead of UTC at `ms`, in milliseconds. */
function offsetMs(timeZone: string, ms: number): number {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone,
    hourCycle: 'h23',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  }).formatToParts(ms);
  const get = (type: string) => Number(parts.find((p) => p.type === type)?.value ?? 0);
  const asUtc = Date.UTC(
    get('year'),
    get('month') - 1,
    get('day'),
    get('hour'),
    get('minute'),
    get('second'),
  );
  return asUtc - Math.floor(ms / 1000) * 1000;
}

/** Midnight at the start of the room's current day, in the room's timezone (D12). */
export function startOfRoomDay(timeZone: string, nowMs: number): Date {
  const local = new Date(nowMs + offsetMs(timeZone, nowMs));
  const midnightAsUtc = Date.UTC(local.getUTCFullYear(), local.getUTCMonth(), local.getUTCDate());
  // Use the offset in force at midnight itself, which differs from now's across a DST change.
  let guess = midnightAsUtc - offsetMs(timeZone, midnightAsUtc);
  guess = midnightAsUtc - offsetMs(timeZone, guess);
  return new Date(guess);
}

export async function roomMetrics(roomId: string, since?: string): Promise<RoomMetrics> {
  const { repo, now } = deps();
  const room = await getRoomRecord(roomId);
  const from = since ?? startOfRoomDay(room.timezone, now()).toISOString();
  if (Date.parse(from) > now()) throw badRequest('`since` is in the future.');
  const [totals, activeCheckins] = await Promise.all([
    repo.activityTotals(roomId, from),
    repo.activeCheckinCount(roomId),
  ]);
  return {
    since: new Date(from).toISOString(),
    activeCheckins,
    checkins: totals.checkin,
    cardViews: totals.card_view,
    // Never a real count. Goes away with A2's #14.
    taps: 0,
    matches: totals.match,
    glowsStarted: totals.glow_started,
    glowsMet: totals.glow_met,
    reports: totals.report,
  };
}

/** Demo mode skips of the location check since the start of the room's day (B2 logs them). */
export async function demoSkipsToday(roomId: string): Promise<number> {
  const { repo, now } = deps();
  const room = await getRoomRecord(roomId);
  return repo.demoSkipCount(roomId, startOfRoomDay(room.timezone, now()).toISOString());
}
