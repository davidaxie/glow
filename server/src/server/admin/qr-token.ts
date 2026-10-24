/**
 * STAND-IN for B2's `displayToken` in `@/server/qr` (PR #10, decision D47), with the same
 * signature and the same algorithm, until that PR merges. Then this file becomes
 * `export { displayToken } from '@/server/qr';` and B7 never computes the HMAC itself.
 *
 * Every admin file gets the screen token from here, so the swap is one line.
 */
import { createHmac } from 'node:crypto';
import { QR_ROTATION_SECONDS, QR_TOKEN_LENGTH } from '@/contracts';

const BASE32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

function base32(bytes: Uint8Array): string {
  let out = '';
  let buffer = 0;
  let bits = 0;
  for (const byte of bytes) {
    buffer = ((buffer << 8) | byte) & 0xffff;
    bits += 8;
    while (bits >= 5) {
      out += BASE32[(buffer >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  if (bits > 0) out += BASE32[(buffer << (5 - bits)) & 31];
  return out;
}

/** What the display shows now, and when it changes (B2's signature). */
export function displayToken(
  qrSecretHex: string,
  nowMs: number,
): { readonly token: string; readonly windowEndsAt: Date } {
  const hex = qrSecretHex.toLowerCase();
  if (!/^[0-9a-f]{64}$/.test(hex)) throw new Error('qr_secret must be 32 bytes of hex');
  const window = Math.floor(nowMs / 1000 / QR_ROTATION_SECONDS);
  const counter = Buffer.alloc(8);
  counter.writeBigUInt64BE(BigInt(window));
  const mac = createHmac('sha256', Buffer.from(hex, 'hex')).update(counter).digest();
  return {
    token: base32(mac).slice(0, QR_TOKEN_LENGTH),
    windowEndsAt: new Date((window + 1) * QR_ROTATION_SECONDS * 1000),
  };
}
