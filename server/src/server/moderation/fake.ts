/**
 * A deterministic stand-in for Claude, used when there's no `ANTHROPIC_API_KEY` in local
 * development, CI and tests. It approves every photo and passes every message, unless the
 * input carries a fixture marker:
 *
 * - Photos: a JPEG comment `glow-moderation-fixture:<flags>`, where flags is a comma list of
 *   `face_visible`, `nudity`, `no_outfit`, `no_person`, `possibly_minor`, `slow` (never
 *   answers, so the timeout fires) and `error` (an outage). `moderationFixtureJpeg()` makes one.
 * - Messages: `[glow-test:flag]` (flagged as harassment), `[glow-test:slow]` or
 *   `[glow-test:error]` anywhere in the body.
 *
 * The app's own uploads never carry these markers (B3 and B1 strip all metadata, which
 * includes JPEG comments), so in the Simulator every real photo is approved.
 */
import sharp from 'sharp';
import type { ModerationModel } from './model';
import type { ImageFindings, TextFindings } from './types';

export const IMAGE_FIXTURE_PREFIX = 'glow-moderation-fixture:';

export type ImageFixtureFlag =
  'face_visible' | 'nudity' | 'no_outfit' | 'no_person' | 'possibly_minor' | 'slow' | 'error';

export const TEXT_FIXTURE = {
  flag: '[glow-test:flag]',
  slow: '[glow-test:slow]',
  error: '[glow-test:error]',
} as const;

/** Finds the marker in the raw bytes. Latin-1 keeps one character per byte. */
export function imageFixtureFlags(bytes: Uint8Array): Set<ImageFixtureFlag> {
  const text = Buffer.from(bytes.buffer, bytes.byteOffset, bytes.byteLength).toString('latin1');
  const at = text.indexOf(IMAGE_FIXTURE_PREFIX);
  if (at < 0) return new Set();
  const rest = text.slice(at + IMAGE_FIXTURE_PREFIX.length);
  const list = /^[a-z_,]*/.exec(rest)?.[0] ?? '';
  return new Set(list.split(',').filter(Boolean) as ImageFixtureFlag[]);
}

/** Waits until the caller gives up. Used to exercise the timeout path. */
function hang(signal: AbortSignal): Promise<never> {
  return new Promise((_, reject) => {
    const fail = () => reject(signal.reason ?? new Error('aborted'));
    if (signal.aborted) fail();
    else signal.addEventListener('abort', fail, { once: true });
  });
}

export const fakeModerationModel: ModerationModel = {
  name: 'fake',
  async classifyImage({ original, signal }) {
    const flags = imageFixtureFlags(original);
    if (flags.has('slow')) return hang(signal);
    if (flags.has('error')) throw new Error('fake moderation outage');
    const findings: ImageFindings = {
      personPresent: !flags.has('no_person'),
      faceVisible: flags.has('face_visible'),
      nudity: flags.has('nudity'),
      outfitVisible: !flags.has('no_outfit') && !flags.has('no_person'),
      possiblyUnder18: flags.has('possibly_minor'),
    };
    return findings;
  },
  async classifyText({ body, signal }) {
    if (body.includes(TEXT_FIXTURE.slow)) return hang(signal);
    if (body.includes(TEXT_FIXTURE.error)) throw new Error('fake moderation outage');
    const flagged = body.includes(TEXT_FIXTURE.flag);
    const findings: TextFindings = { flagged, category: flagged ? 'harassment' : 'none' };
    return findings;
  },
};

/** Puts a JPEG comment (COM, 0xFFFE) right after the start-of-image marker. */
export function withJpegComment(jpeg: Uint8Array, comment: string): Uint8Array {
  if (jpeg[0] !== 0xff || jpeg[1] !== 0xd8) throw new Error('not a JPEG');
  const text = Buffer.from(comment, 'latin1');
  const length = text.byteLength + 2;
  if (length > 0xffff) throw new Error('comment too long');
  const segment = Buffer.concat([Buffer.from([0xff, 0xfe, length >> 8, length & 0xff]), text]);
  return new Uint8Array(Buffer.concat([jpeg.subarray(0, 2), segment, jpeg.subarray(2)]));
}

/**
 * A small, valid JPEG the fake moderates as `flags` say. For any agent's tests:
 *
 *   const photo = await moderationFixtureJpeg(['face_visible']); // rejected as a card
 *   const ok = await moderationFixtureJpeg([]);                  // approved
 */
export async function moderationFixtureJpeg(
  flags: readonly ImageFixtureFlag[],
  size: { width: number; height: number } = { width: 64, height: 80 },
): Promise<Uint8Array> {
  const jpeg = await sharp({
    create: { width: size.width, height: size.height, channels: 3, background: '#557799' },
  })
    .jpeg({ quality: 80 })
    .toBuffer();
  return withJpegComment(new Uint8Array(jpeg), `${IMAGE_FIXTURE_PREFIX}${flags.join(',')}`);
}
