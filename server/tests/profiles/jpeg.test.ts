import sharp from 'sharp';
import { describe, expect, it } from 'vitest';
import { withJpegComment } from '@/server/moderation';
import { InvalidJpegError, stripJpegMetadata } from '@/server/profiles/jpeg';

const latin1 = (bytes: Uint8Array) => Buffer.from(bytes).toString('latin1');

/** A 4:5 JPEG carrying EXIF (with a GPS position and a camera), XMP and a comment. */
async function photoWithMetadata(): Promise<Uint8Array> {
  const xmp =
    '<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">' +
    '<rdf:Description xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:creator>Robin Example</dc:creator>' +
    '</rdf:Description></rdf:RDF></x:xmpmeta>';
  const jpeg = await sharp({
    create: { width: 80, height: 100, channels: 3, background: '#aa5533' },
  })
    .withExif({
      IFD0: { Make: 'ExampleCam', Model: 'Example 1', Artist: 'Robin Example' },
      IFD3: {
        GPSLatitudeRef: 'N',
        GPSLatitude: '37/1 48/1 1044/100',
        GPSLongitudeRef: 'W',
        GPSLongitude: '122/1 26/1 5424/100',
      },
    })
    .withXmp(xmp)
    .jpeg({ quality: 80 })
    .toBuffer();
  return withJpegComment(new Uint8Array(jpeg), 'taken at Robin home');
}

describe('stripJpegMetadata', () => {
  it('removes EXIF (GPS, camera, names), XMP and comments, and keeps the picture', async () => {
    const original = await photoWithMetadata();
    const before = await sharp(original).metadata();
    expect(before.exif).toBeDefined();
    expect(before.xmp).toBeDefined();
    expect(latin1(original)).toContain('Robin');

    const { bytes, info } = stripJpegMetadata(original);
    expect(info).toEqual({ width: 80, height: 100 });

    const text = latin1(bytes);
    for (const leak of [
      'Exif',
      'Robin',
      'ExampleCam',
      'http://ns.adobe.com',
      'adobe:ns:meta',
      'home',
    ]) {
      expect(text).not.toContain(leak);
    }
    const after = await sharp(bytes).metadata();
    expect(after.exif).toBeUndefined();
    expect(after.xmp).toBeUndefined();
    expect(after.icc).toBeUndefined();
    expect(after.comments ?? []).toEqual([]);
    expect([after.width, after.height, after.format]).toEqual([80, 100, 'jpeg']);

    // Same pixels: nothing was re-encoded.
    const [a, b] = await Promise.all([
      sharp(original).raw().toBuffer(),
      sharp(bytes).raw().toBuffer(),
    ]);
    expect(Buffer.compare(a, b)).toBe(0);
  });

  it('keeps a progressive JPEG whole', async () => {
    const jpeg = await sharp({
      create: { width: 160, height: 200, channels: 3, background: '#123456' },
    })
      .jpeg({ quality: 80, progressive: true })
      .toBuffer();
    const { bytes } = stripJpegMetadata(new Uint8Array(jpeg));
    const meta = await sharp(bytes).metadata();
    expect([meta.width, meta.height, meta.isProgressive]).toEqual([160, 200, true]);
  });

  it('drops anything hidden after the end of the image', async () => {
    const jpeg = new Uint8Array(
      await sharp({ create: { width: 8, height: 10, channels: 3, background: '#000' } })
        .jpeg()
        .toBuffer(),
    );
    const padded = new Uint8Array([...jpeg, ...Buffer.from('secret trailer', 'latin1')]);
    const { bytes } = stripJpegMetadata(padded);
    expect(latin1(bytes)).not.toContain('secret');
    expect(bytes.at(-2)).toBe(0xff);
    expect(bytes.at(-1)).toBe(0xd9);
  });

  it.each([
    ['empty', new Uint8Array()],
    ['a PNG', new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])],
    ['a truncated JPEG', new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a])],
    ['only start and end markers', new Uint8Array([0xff, 0xd8, 0xff, 0xd9])],
  ])('refuses %s', (_name, bytes) => {
    expect(() => stripJpegMetadata(bytes)).toThrow(InvalidJpegError);
  });

  it('refuses a JPEG cut off in the middle of its picture data', async () => {
    const jpeg = new Uint8Array(
      await sharp({ create: { width: 64, height: 80, channels: 3, background: '#ff0000' } })
        .jpeg()
        .toBuffer(),
    );
    expect(() => stripJpegMetadata(jpeg.subarray(0, jpeg.length - 40))).toThrow(InvalidJpegError);
  });
});
