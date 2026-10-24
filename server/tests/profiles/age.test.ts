import { describe, expect, it } from 'vitest';
import {
  isAdult,
  latestAdultBirthdate,
  parseIsoDate,
  todayInLastTimezone,
} from '@/server/profiles/age';

// P10: nobody under 18 can finish onboarding. "Today" is the date in UTC-12, like the
// database trigger (D24), so nobody is 18 before it's their birthday everywhere on Earth.
describe('18+ rule', () => {
  it('uses the date in UTC-12', () => {
    // 2026-10-24 10:00 UTC is still 2026-10-23 in UTC-12.
    expect(todayInLastTimezone(new Date('2026-10-24T10:00:00.000Z'))).toBe('2026-10-23');
    expect(todayInLastTimezone(new Date('2026-10-24T12:00:00.000Z'))).toBe('2026-10-24');
  });

  it('lets someone in on the day they turn 18 in UTC-12, and not a moment before', () => {
    const now = new Date('2026-10-24T12:00:00.000Z'); // 2026-10-24 in UTC-12
    expect(isAdult('2008-10-24', now)).toBe(true);
    expect(isAdult('2008-10-25', now)).toBe(false);
    // Earlier the same UTC day it is still the 23rd in UTC-12: not 18 yet.
    expect(isAdult('2008-10-24', new Date('2026-10-24T11:59:59.000Z'))).toBe(false);
  });

  it('turns a Feb 29 cutoff into Feb 28, like Postgres', () => {
    expect(latestAdultBirthdate(new Date('2044-03-01T00:00:00.000Z'))).toBe('2026-02-28');
    expect(latestAdultBirthdate(new Date('2044-02-29T13:00:00.000Z'))).toBe('2026-02-28');
  });

  it('treats someone born on Feb 29 as 18 on Feb 28 of a common year', () => {
    // Born 2008-02-29. 2026 has no Feb 29, so the cutoff on 2026-02-28 is 2008-02-28.
    expect(isAdult('2008-02-29', new Date('2026-02-28T12:00:00.000Z'))).toBe(false);
    expect(isAdult('2008-02-29', new Date('2026-03-01T12:00:00.000Z'))).toBe(true);
  });

  it('is never adult for a date that does not exist', () => {
    expect(isAdult('2001-02-30')).toBe(false);
    expect(isAdult('not a date')).toBe(false);
    expect(parseIsoDate('2001-13-01')).toBeNull();
    expect(parseIsoDate('2000-02-29')).toEqual({ y: 2000, m: 2, d: 29 });
    expect(parseIsoDate('1900-02-29')).toBeNull();
  });

  it('accepts someone clearly over 18', () => {
    expect(isAdult('1990-01-01', new Date('2026-10-24T12:00:00.000Z'))).toBe(true);
  });
});
