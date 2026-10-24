/**
 * The 18+ rule (P10). Mirrors the database trigger on `profiles` (D24): "today" is the calendar
 * date in UTC-12, the last timezone on Earth, so nobody counts as 18 anywhere before it's their
 * birthday everywhere. The route checks first so nothing is written; the trigger is the backstop.
 */
import { MIN_AGE_YEARS } from '@/contracts';

/** The earliest birthdate the database accepts (`profiles.birthdate >= 1900-01-01`). */
export const EARLIEST_BIRTHDATE = '1900-01-01';

const ISO_DATE = /^(\d{4})-(\d{2})-(\d{2})$/;

type Ymd = { readonly y: number; readonly m: number; readonly d: number };

function daysIn(y: number, m: number): number {
  return new Date(Date.UTC(y, m, 0)).getUTCDate();
}

/** Parses `YYYY-MM-DD` into a real calendar date, or null (2001-02-30 is not one). */
export function parseIsoDate(value: string): Ymd | null {
  const match = ISO_DATE.exec(value);
  if (!match) return null;
  const y = Number(match[1]);
  const m = Number(match[2]);
  const d = Number(match[3]);
  if (m < 1 || m > 12 || d < 1 || d > daysIn(y, m)) return null;
  return { y, m, d };
}

const format = ({ y, m, d }: Ymd) =>
  `${String(y).padStart(4, '0')}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`;

/** Today's date in UTC-12, as `YYYY-MM-DD`. */
export function todayInLastTimezone(now: Date): string {
  const shifted = new Date(now.getTime() - 12 * 60 * 60 * 1000);
  return shifted.toISOString().slice(0, 10);
}

/**
 * The latest birthdate that is MIN_AGE today: today in UTC-12 minus MIN_AGE years. Like Postgres's
 * `date - interval 'N years'`, Feb 29 becomes Feb 28 in a year that has none.
 */
export function latestAdultBirthdate(now: Date, minAge = MIN_AGE_YEARS): string {
  const today = parseIsoDate(todayInLastTimezone(now));
  if (!today) throw new Error('unreachable: toISOString always gives a valid date');
  const y = today.y - minAge;
  return format({ y, m: today.m, d: Math.min(today.d, daysIn(y, today.m)) });
}

/** True when someone born on `birthdate` (`YYYY-MM-DD`) is at least MIN_AGE now. */
export function isAdult(birthdate: string, now: Date = new Date()): boolean {
  const date = parseIsoDate(birthdate);
  if (!date) return false;
  // Same-format ISO dates compare correctly as strings.
  return format(date) <= latestAdultBirthdate(now);
}
