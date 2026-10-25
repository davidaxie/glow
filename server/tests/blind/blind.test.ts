/** Owner: X1. Blind mode helpers: signed links, the give-away check and the drop clock. */
import { describe, expect, it } from 'vitest';
import { checkLeak } from '@/server/blind/leak-check';
import {
  blindCardLink,
  blindPhotoLink,
  isValidBlindCardLink,
  isValidBlindPhotoLink,
} from '@/server/blind/links';
import { dropGate, nextDropAt, todaysDrop } from '@/server/blind/schedule';

const CARD = 'aaaaaaaa-0000-4000-8000-000000000001';
const VIEWER = 'bbbbbbbb-0000-4000-8000-000000000002';
const OTHER = 'cccccccc-0000-4000-8000-000000000003';

function parts(url: string) {
  const u = new URL(url, 'http://x');
  return { exp: Number(u.searchParams.get('exp')), sig: u.searchParams.get('sig') ?? '' };
}

describe('blind links', () => {
  it('a card link works only for its viewer and carries no user ID', () => {
    const url = blindCardLink(CARD, VIEWER);
    const { exp, sig } = parts(url);
    expect(url).not.toContain(VIEWER);
    expect(isValidBlindCardLink(CARD, VIEWER, exp, sig)).toBe(true);
    expect(isValidBlindCardLink(CARD, OTHER, exp, sig)).toBe(false);
    expect(isValidBlindCardLink(OTHER, VIEWER, exp, sig)).toBe(false);
  });
  it('expires after CARD_URL_TTL', () => {
    const now = Date.now();
    const { exp, sig } = parts(blindCardLink(CARD, VIEWER, now));
    expect(isValidBlindCardLink(CARD, VIEWER, exp, sig, now + 61_000)).toBe(false);
  });
  it('a card signature never works as a partner photo link', () => {
    const { exp, sig } = parts(blindCardLink(CARD, VIEWER));
    expect(isValidBlindPhotoLink(CARD, 0, VIEWER, exp, sig)).toBe(false);
    const p = parts(blindPhotoLink(CARD, 0, VIEWER));
    expect(isValidBlindPhotoLink(CARD, 0, VIEWER, p.exp, p.sig)).toBe(true);
    expect(isValidBlindPhotoLink(CARD, 1, VIEWER, p.exp, p.sig)).toBe(false);
  });
});

describe('checkLeak', () => {
  it.each([
    'my insta is alex.codes',
    'hit me up @alex_c',
    'alex@example.com',
    'call 415 555 0134',
    'see alexc.dev',
    "I'm at table 12",
  ])('warns on %s', (text) => expect(checkLeak(text).leak).toBe(true));
  it('warns on the sender saying their own name', () => {
    expect(checkLeak('it is Avery btw', 'Avery').leak).toBe(true);
  });
  it.each(['what are you building?', 'pineapple on pizza, yes or no', 'I love hackathons'])(
    'lets %s through',
    (text) => expect(checkLeak(text, 'Avery').leak).toBe(false),
  );
});

describe('drop clock', () => {
  it('drops at 8pm Pacific', () => {
    const noon = new Date('2026-10-25T19:00:00.000Z'); // 12:00 PDT
    expect(todaysDrop(noon).toISOString()).toBe('2026-10-26T03:00:00.000Z');
    expect(nextDropAt(noon).toISOString()).toBe('2026-10-26T03:00:00.000Z');
    expect(dropGate(noon, false).ready).toBe(false);
    expect(dropGate(noon, true)).toMatchObject({ ready: true, demo: true });
  });
  it('is open from 8pm until midnight Pacific', () => {
    expect(dropGate(new Date('2026-10-26T04:00:00.000Z'), false).ready).toBe(true); // 21:00 PDT
  });
});
