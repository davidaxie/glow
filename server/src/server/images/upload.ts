/**
 * Turns a check-in's base64 photo into the JPEG we store. The phone already blurred faces and
 * removed metadata (P3); the server re-encodes anyway, so whatever a modified app sends, the
 * stored file is a plain upright JPEG with no EXIF, GPS, XMP, ICC profile or comments, and no
 * bigger than PHOTO_MAX_DIMENSION.
 */
import sharp from 'sharp';
import { PHOTO_MAX_BYTES, PHOTO_MAX_DIMENSION_PX, PHOTO_JPEG_QUALITY_PERCENT } from '@/contracts';
import { HttpError, badRequest } from '@/server/http';
import { MAX_INPUT_PIXELS } from './watermark';

sharp.cache(false);

const BASE64 = /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/;

const tooLarge = () => new HttpError(413, 'payload_too_large', 'That photo is too large.');

/** Strict base64 (no whitespace, no URL alphabet, correct padding), at most PHOTO_MAX_BYTES. */
export function decodePhoto(base64: string): Buffer {
  if (base64.length === 0 || !BASE64.test(base64)) {
    throw badRequest('The photo is not valid base64.', [
      { path: 'body.photo', code: 'invalid_format', message: 'Expected base64' },
    ]);
  }
  const bytes = Buffer.from(base64, 'base64');
  if (bytes.byteLength > PHOTO_MAX_BYTES) throw tooLarge();
  return bytes;
}

/** A clean JPEG for storage, or 400 if it isn't a readable JPEG. */
export async function normalizeCardPhoto(bytes: Uint8Array): Promise<Buffer> {
  let format: string | undefined;
  try {
    ({ format } = await sharp(bytes, { limitInputPixels: MAX_INPUT_PIXELS }).metadata());
  } catch {
    format = undefined;
  }
  if (format !== 'jpeg') {
    throw badRequest('The photo must be a JPEG.', [
      { path: 'body.photo', code: 'invalid_format', message: 'Expected a JPEG' },
    ]);
  }
  try {
    const out = await sharp(bytes, { failOn: 'error', limitInputPixels: MAX_INPUT_PIXELS })
      .rotate()
      .resize({
        width: PHOTO_MAX_DIMENSION_PX,
        height: PHOTO_MAX_DIMENSION_PX,
        fit: 'inside',
        withoutEnlargement: true,
      })
      .toColourspace('srgb')
      .jpeg({ quality: PHOTO_JPEG_QUALITY_PERCENT })
      .toBuffer();
    if (out.byteLength > PHOTO_MAX_BYTES) throw tooLarge();
    return out;
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw badRequest('The photo could not be read.', [
      { path: 'body.photo', code: 'invalid_format', message: 'Unreadable JPEG' },
    ]);
  }
}
