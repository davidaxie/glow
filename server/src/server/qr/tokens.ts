/**
 * Room QR tokens (docs/SPEC.md, QR codes, universal links and room codes). Owner: B2.
 *
 * - **Poster tokens** are the room's 16-character `static_qr_token`, accepted only
 *   while `allow_static_qr` is on.
 * - **Screen tokens** rotate every QR_ROTATION seconds: the first QR_TOKEN_LENGTH
 *   base32 characters (RFC 4648, A-Z and 2-7) of HMAC-SHA256 keyed with the room's
 *   32-byte `qr_secret` (stored as hex) over the window number as an 8-byte unsigned
 *   big-endian integer, where window = floor(unix seconds / QR_ROTATION). That's the
 *   TOTP counter encoding (RFC 4226), so any HMAC library can reproduce it.
 *   The current window and the previous one are accepted (QR_ACCEPTED_WINDOWS).
 *
 * Every comparison is constant time, and every candidate is compared, so timing never
 * says how close a guess was or which window matched. A token only ever gets someone
 * to the location check, never into a room by itself.
 *
 * B7's display page uses `displayToken` to show the current screen token.
 */
import { createHmac, timingSafeEqual } from 'node:crypto';
import { QR_ACCEPTED_WINDOWS, QR_ROTATION_SECONDS, QR_TOKEN_LENGTH } from '@/contracts';

const BASE32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
const STATIC_TOKEN_LENGTH = 16;
const SECRET_HEX = /^[0-9a-f]{64}$/;

export type RoomTokenSecrets = {
  /** `rooms.qr_secret`: 32 random bytes, hex. */
  readonly qrSecret: string;
  /** `rooms.static_qr_token`: 16 base32 characters. */
  readonly staticQrToken: string;
  /** `rooms.allow_static_qr`. */
  readonly allowStaticQr: boolean;
};

/** RFC 4648 base32 without padding. */
export function base32(bytes: Uint8Array): string {
  let out = '';
  let buffer = 0;
  let bits = 0;
  for (const byte of bytes) {
    buffer = (buffer << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      out += BASE32[(buffer >>> (bits - 5)) & 31];
      bits -= 5;
    }
    buffer &= (1 << bits) - 1;
  }
  if (bits > 0) out += BASE32[(buffer << (5 - bits)) & 31];
  return out;
}

/** The rotation window a moment falls in. */
export function qrWindow(nowMs: number): number {
  return Math.floor(nowMs / 1000 / QR_ROTATION_SECONDS);
}

function secretKey(qrSecretHex: string): Buffer {
  const hex = qrSecretHex.toLowerCase();
  if (!SECRET_HEX.test(hex)) throw new Error('qr_secret must be 32 bytes of hex');
  return Buffer.from(hex, 'hex');
}

/** The screen token for one window. */
export function rotatingToken(qrSecretHex: string, window: number): string {
  if (!Number.isSafeInteger(window) || window < 0) throw new Error('window must be a whole number');
  const counter = Buffer.alloc(8);
  counter.writeBigUInt64BE(BigInt(window));
  const mac = createHmac('sha256', secretKey(qrSecretHex)).update(counter).digest();
  return base32(mac).slice(0, QR_TOKEN_LENGTH);
}

/** What B7's display page shows now, and when it changes. */
export function displayToken(
  qrSecretHex: string,
  nowMs: number,
): { readonly token: string; readonly windowEndsAt: Date } {
  const window = qrWindow(nowMs);
  return {
    token: rotatingToken(qrSecretHex, window),
    windowEndsAt: new Date((window + 1) * QR_ROTATION_SECONDS * 1000),
  };
}

function sameToken(given: string, expected: string): boolean {
  const a = Buffer.from(given, 'utf8');
  const b = Buffer.from(expected, 'utf8');
  // Lengths are public (8 or 16, fixed by the contract), so this early return leaks nothing.
  if (a.length !== b.length) return false;
  return timingSafeEqual(a, b);
}

/** Whether `token` opens this room's location check right now. */
export function verifyRoomToken(room: RoomTokenSecrets, token: string, nowMs: number): boolean {
  if (token.length === STATIC_TOKEN_LENGTH) {
    // Compare even when posters are off, so both cases take the same time.
    const matches = sameToken(token, room.staticQrToken);
    return matches && room.allowStaticQr;
  }
  if (token.length !== QR_TOKEN_LENGTH) return false;

  const current = qrWindow(nowMs);
  let matched = false;
  for (let back = 0; back < QR_ACCEPTED_WINDOWS; back += 1) {
    const window = current - back;
    if (window < 0) continue;
    // No early exit: every accepted window is always compared.
    matched = sameToken(token, rotatingToken(room.qrSecret, window)) || matched;
  }
  return matched;
}
