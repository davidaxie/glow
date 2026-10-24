import { createHmac } from 'node:crypto';
import { beforeEach, describe, expect, it } from 'vitest';
import { CARD_URL_TTL_SECONDS } from '@/contracts';
import { cardImageLink, isValidCardImageLink } from '@/server/images/signed-link';
import { LOCAL_ENV } from '../helpers/env';

const CARD = 'aaaaaaaa-0000-4000-8000-000000000001';
const VIEWER = 'bbbbbbbb-0000-4000-8000-000000000002';
const SOMEONE_ELSE = 'cccccccc-0000-4000-8000-000000000003';
const NOW = Date.parse('2026-10-24T20:15:00.000Z');

function parse(url: string) {
  const parsed = new URL(url, 'http://localhost');
  return {
    path: parsed.pathname,
    exp: Number(parsed.searchParams.get('exp')),
    sig: parsed.searchParams.get('sig') ?? '',
    keys: [...parsed.searchParams.keys()],
  };
}

describe('cardImageLink', () => {
  it('makes a relative link with only exp and sig, and no user ID (P1)', () => {
    const link = cardImageLink(CARD, VIEWER, NOW);
    const { path, exp, sig, keys } = parse(link.url);
    expect(path).toBe(`/api/cards/${CARD}/image`);
    expect(keys).toEqual(['exp', 'sig']);
    expect(sig).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(link.url).not.toContain(VIEWER);
    expect(exp).toBe(NOW / 1000 + CARD_URL_TTL_SECONDS);
    expect(link.expiresAt).toBe('2026-10-24T20:16:00.000Z');
  });

  it('signs {cardId}.{viewerId}.{exp} with CARD_URL_SECRET, as the contract says', () => {
    const { exp, sig } = parse(cardImageLink(CARD, VIEWER, NOW).url);
    const expected = createHmac('sha256', LOCAL_ENV.CARD_URL_SECRET)
      .update(`${CARD}.${VIEWER}.${exp}`)
      .digest('base64url');
    expect(sig).toBe(expected);
  });

  it('refuses IDs that are not UUIDs', () => {
    expect(() => cardImageLink('not-a-uuid', VIEWER, NOW)).toThrow();
    expect(() => cardImageLink(CARD, '', NOW)).toThrow();
  });
});

describe('isValidCardImageLink', () => {
  let link: ReturnType<typeof parse>;
  beforeEach(() => {
    link = parse(cardImageLink(CARD, VIEWER, NOW).url);
  });
  const check = (overrides: Partial<Parameters<typeof isValidCardImageLink>[0]> = {}, now = NOW) =>
    isValidCardImageLink(
      { cardId: CARD, viewerId: VIEWER, exp: link.exp, sig: link.sig, ...overrides },
      now,
    );

  it('accepts the link for its own viewer and card until it expires', () => {
    expect(check()).toBe(true);
    expect(check({}, NOW + (CARD_URL_TTL_SECONDS - 1) * 1000)).toBe(true);
  });

  it('refuses an expired link', () => {
    expect(check({}, NOW + CARD_URL_TTL_SECONDS * 1000)).toBe(false);
    expect(check({}, NOW + 3600 * 1000)).toBe(false);
  });

  it('refuses the same link for anyone else (reused by someone else)', () => {
    expect(check({ viewerId: SOMEONE_ELSE })).toBe(false);
  });

  it('refuses the signature on another card', () => {
    expect(check({ cardId: SOMEONE_ELSE })).toBe(false);
  });

  it('refuses a stretched expiry, even with the old signature', () => {
    expect(check({ exp: link.exp + 1 })).toBe(false);
    expect(check({ exp: link.exp + 86400 })).toBe(false);
  });

  it('refuses a link that claims to live longer than CARD_URL_TTL, even if signed', () => {
    const farExp = NOW / 1000 + CARD_URL_TTL_SECONDS + 60;
    const sig = createHmac('sha256', LOCAL_ENV.CARD_URL_SECRET)
      .update(`${CARD}.${VIEWER}.${farExp}`)
      .digest('base64url');
    expect(check({ exp: farExp, sig })).toBe(false);
  });

  it('refuses edited and malformed signatures', () => {
    const flipped = (link.sig[0] === 'A' ? 'B' : 'A') + link.sig.slice(1);
    expect(check({ sig: flipped })).toBe(false);
    expect(check({ sig: '' })).toBe(false);
    expect(check({ sig: `${link.sig}A` })).toBe(false);
    expect(check({ sig: 'x'.repeat(43) })).toBe(false);
  });

  it('refuses a link signed with another secret', () => {
    const sig = createHmac('sha256', 'some-other-secret-that-is-long-enough-000000')
      .update(`${CARD}.${VIEWER}.${link.exp}`)
      .digest('base64url');
    expect(check({ sig })).toBe(false);
  });

  it('treats uppercase IDs like lowercase ones', () => {
    expect(check({ cardId: CARD.toUpperCase(), viewerId: VIEWER.toUpperCase() })).toBe(true);
  });
});
