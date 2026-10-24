/**
 * Room QR tokens (B2, B2-D2): poster tokens, and rotating screen tokens with exactly the
 * current and previous 30-second windows accepted, compared in constant time.
 */
import * as crypto from 'node:crypto';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { QR_ROTATION_SECONDS, QR_TOKEN_LENGTH } from '@/contracts';
import { base32, displayToken, qrWindow, rotatingToken, verifyRoomToken } from '@/server/qr';

vi.mock('node:crypto', async (importOriginal) => {
  const actual = await importOriginal<typeof import('node:crypto')>();
  return { ...actual, timingSafeEqual: vi.fn(actual.timingSafeEqual) };
});

/** The seeded demo room's secret (supabase/seed.sql), so tokens are reproducible. Test data. */
const SECRET = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';
const ROOM = { qrSecret: SECRET, staticQrToken: 'DEMOSTATICTOKEN2', allowStaticQr: true };
const ROTATION_MS = QR_ROTATION_SECONDS * 1000;
/** The start of some window: 2026-10-24T20:00:00Z is a multiple of 30 s. */
const T0 = Date.parse('2026-10-24T20:00:00.000Z');

afterEach(() => vi.mocked(crypto.timingSafeEqual).mockClear());

describe('base32', () => {
  // RFC 4648 section 10 test vectors, without padding.
  it.each([
    ['', ''],
    ['f', 'MY'],
    ['fo', 'MZXQ'],
    ['foo', 'MZXW6'],
    ['foob', 'MZXW6YQ'],
    ['fooba', 'MZXW6YTB'],
    ['foobar', 'MZXW6YTBOI'],
  ])('encodes %j as %s', (input, output) => {
    expect(base32(Buffer.from(input))).toBe(output);
  });
});

describe('rotatingToken', () => {
  it('is HMAC-SHA256(secret bytes, 8-byte big-endian window), base32, first 8 characters', () => {
    const window = qrWindow(T0);
    const counter = Buffer.alloc(8);
    counter.writeBigUInt64BE(BigInt(window));
    const mac = crypto.createHmac('sha256', Buffer.from(SECRET, 'hex')).update(counter).digest();
    expect(rotatingToken(SECRET, window)).toBe(base32(mac).slice(0, 8));
  });

  it('is 8 base32 characters that change every window', () => {
    const window = qrWindow(T0);
    const a = rotatingToken(SECRET, window);
    const b = rotatingToken(SECRET, window + 1);
    expect(a).toMatch(/^[A-Z2-7]{8}$/);
    expect(a).toHaveLength(QR_TOKEN_LENGTH);
    expect(a).not.toBe(b);
  });

  it('differs per room secret', () => {
    const other = 'ff'.repeat(32);
    expect(rotatingToken(SECRET, 1)).not.toBe(rotatingToken(other, 1));
  });

  it('refuses a malformed secret or window', () => {
    expect(() => rotatingToken('abc', 1)).toThrow();
    expect(() => rotatingToken(SECRET, -1)).toThrow();
    expect(() => rotatingToken(SECRET, 1.5)).toThrow();
  });

  it('pins a known value for the demo room, so B7 and B2 agree (window 0)', () => {
    expect(rotatingToken(SECRET, 0)).toBe(
      base32(
        crypto.createHmac('sha256', Buffer.from(SECRET, 'hex')).update(Buffer.alloc(8)).digest(),
      ).slice(0, 8),
    );
  });
});

describe('qrWindow and displayToken', () => {
  it('starts a new window every QR_ROTATION seconds', () => {
    expect(qrWindow(T0 + ROTATION_MS - 1)).toBe(qrWindow(T0));
    expect(qrWindow(T0 + ROTATION_MS)).toBe(qrWindow(T0) + 1);
  });

  it('gives the current token and when its window ends', () => {
    const shown = displayToken(SECRET, T0 + 12_345);
    expect(shown.token).toBe(rotatingToken(SECRET, qrWindow(T0)));
    expect(shown.windowEndsAt.getTime()).toBe(T0 + ROTATION_MS);
  });
});

describe('verifyRoomToken: rotating screen tokens', () => {
  const tokenFor = (ms: number) => rotatingToken(SECRET, qrWindow(ms));

  it('accepts the current window, from its first to its last millisecond', () => {
    const token = tokenFor(T0);
    expect(verifyRoomToken(ROOM, token, T0)).toBe(true);
    expect(verifyRoomToken(ROOM, token, T0 + ROTATION_MS - 1)).toBe(true);
  });

  it('accepts the previous window, until the very end of the next one', () => {
    const token = tokenFor(T0);
    expect(verifyRoomToken(ROOM, token, T0 + ROTATION_MS)).toBe(true);
    expect(verifyRoomToken(ROOM, token, T0 + 2 * ROTATION_MS - 1)).toBe(true);
  });

  it('refuses a token two windows old', () => {
    expect(verifyRoomToken(ROOM, tokenFor(T0), T0 + 2 * ROTATION_MS)).toBe(false);
  });

  it('refuses a token from the next window (no clock-skew grace into the future)', () => {
    expect(verifyRoomToken(ROOM, tokenFor(T0 + ROTATION_MS), T0)).toBe(false);
  });

  it("refuses another room's token", () => {
    const other = { ...ROOM, qrSecret: 'ab'.repeat(32) };
    expect(verifyRoomToken(other, tokenFor(T0), T0)).toBe(false);
  });

  it('works whether or not posters are allowed', () => {
    expect(verifyRoomToken({ ...ROOM, allowStaticQr: false }, tokenFor(T0), T0)).toBe(true);
  });

  it('compares both windows in constant time, even when the first one matches', () => {
    verifyRoomToken(ROOM, tokenFor(T0), T0);
    expect(crypto.timingSafeEqual).toHaveBeenCalledTimes(2);
    vi.mocked(crypto.timingSafeEqual).mockClear();
    verifyRoomToken(ROOM, 'AAAAAAAA', T0);
    expect(crypto.timingSafeEqual).toHaveBeenCalledTimes(2);
  });
});

describe('verifyRoomToken: poster tokens', () => {
  it('accepts the static token when allow_static_qr is on', () => {
    expect(verifyRoomToken(ROOM, 'DEMOSTATICTOKEN2', T0)).toBe(true);
  });

  it('refuses it when allow_static_qr is off, after the same constant-time compare', () => {
    expect(verifyRoomToken({ ...ROOM, allowStaticQr: false }, 'DEMOSTATICTOKEN2', T0)).toBe(false);
    expect(crypto.timingSafeEqual).toHaveBeenCalledTimes(1);
  });

  it('refuses a wrong static token', () => {
    expect(verifyRoomToken(ROOM, 'DEMOSTATICTOKEN3', T0)).toBe(false);
  });

  it('refuses tokens of any other length', () => {
    for (const token of ['', 'ABC', 'DEMOSTATICTOKEN', 'DEMOSTATICTOKEN22', 'A'.repeat(64)]) {
      expect(verifyRoomToken(ROOM, token, T0)).toBe(false);
    }
  });
});
