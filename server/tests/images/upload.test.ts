import sharp from 'sharp';
import { describe, expect, it } from 'vitest';
import { PHOTO_MAX_BYTES, PHOTO_MAX_DIMENSION_PX } from '@/contracts';
import { HttpError } from '@/server/http';
import { decodePhoto, normalizeCardPhoto } from '@/server/images/upload';
import { hasJpegMetadata, jpegMarkers, syntheticPhoto } from './helpers';

async function status(promise: Promise<unknown>): Promise<number> {
  try {
    await promise;
    return 200;
  } catch (error) {
    return error instanceof HttpError ? error.status : 500;
  }
}

describe('decodePhoto', () => {
  it('decodes strict base64', () => {
    expect([...decodePhoto(Buffer.from([1, 2, 3, 4, 5]).toString('base64'))]).toEqual([
      1, 2, 3, 4, 5,
    ]);
  });

  it('refuses whitespace, the URL alphabet, bad padding and empty strings with 400', () => {
    for (const bad of ['', 'AQID BA==', 'AQID\nBA==', '-_-_', 'AQIDBA=', 'AQIDB', '!!!!']) {
      expect(() => decodePhoto(bad)).toThrowError(expect.objectContaining({ status: 400 }));
    }
  });

  it('refuses more than PHOTO_MAX_BYTES with 413', () => {
    const big = Buffer.alloc(PHOTO_MAX_BYTES + 3).toString('base64');
    expect(() => decodePhoto(big)).toThrowError(expect.objectContaining({ status: 413 }));
  });
});

describe('normalizeCardPhoto', () => {
  it('drops EXIF, GPS, ICC, XMP and comments, whatever a modified app sends', async () => {
    const tagged = await sharp(await syntheticPhoto(600, 800))
      .withExif({
        IFD0: { Make: 'Phone', Model: 'Pro', Copyright: 'someone' },
        IFD3: { GPSLatitudeRef: 'N', GPSLatitude: '37/1 48/1 10/1' },
      })
      .withIccProfile('p3')
      .jpeg()
      .toBuffer();
    expect(hasJpegMetadata(tagged)).toBe(true);

    const out = await normalizeCardPhoto(tagged);
    const meta = await sharp(out).metadata();
    expect(meta.format).toBe('jpeg');
    expect(meta.exif).toBeUndefined();
    expect(meta.icc).toBeUndefined();
    expect(meta.xmp).toBeUndefined();
    expect(meta.comments ?? []).toEqual([]);
    expect(hasJpegMetadata(out)).toBe(false);
    expect(jpegMarkers(out)).not.toContain(0xfe);
    expect(out.includes(Buffer.from('someone'))).toBe(false);
  });

  it('applies the orientation, then forgets it', async () => {
    const sideways = await sharp(await syntheticPhoto(600, 800))
      .withMetadata({ orientation: 6 })
      .jpeg()
      .toBuffer();
    const out = await normalizeCardPhoto(sideways);
    const meta = await sharp(out).metadata();
    expect([meta.width, meta.height]).toEqual([800, 600]);
    expect(meta.orientation).toBeUndefined();
  });

  it('scales anything larger to PHOTO_MAX_DIMENSION on the long side', async () => {
    const big = await sharp({
      create: { width: 3000, height: 2000, channels: 3, background: '#668899' },
    })
      .jpeg()
      .toBuffer();
    const meta = await sharp(await normalizeCardPhoto(big)).metadata();
    expect(Math.max(meta.width!, meta.height!)).toBe(PHOTO_MAX_DIMENSION_PX);
  });

  it('refuses PNGs, garbage and truncated JPEGs with 400', async () => {
    const png = await sharp({ create: { width: 10, height: 10, channels: 3, background: '#000' } })
      .png()
      .toBuffer();
    const jpeg = await syntheticPhoto(200, 200);
    expect(await status(normalizeCardPhoto(png))).toBe(400);
    expect(await status(normalizeCardPhoto(new Uint8Array([0xff, 0xd8, 1, 2])))).toBe(400);
    expect(await status(normalizeCardPhoto(jpeg.subarray(0, jpeg.length / 3)))).toBe(400);
  });
});
