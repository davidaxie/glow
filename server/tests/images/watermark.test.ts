import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';
import { describe, expect, it } from 'vitest';
import { WATERMARK_OPACITY, watermark, watermarkSvg } from '@/server/images/watermark';
import { flatJpeg, hasJpegMetadata, rawPixels, syntheticPhoto } from './helpers';

const CODE = 'K7MPQ2RX';
const SNAPSHOT = join(
  dirname(fileURLToPath(import.meta.url)),
  '__snapshots__',
  'watermarked-card.jpg',
);
// Set GLOW_UPDATE_SNAPSHOTS=1 to rewrite the snapshot after an intended change.
const UPDATE = process.env.GLOW_UPDATE_SNAPSHOTS === '1';

describe('watermarkSvg', () => {
  it('draws the viewer code as shapes, never as text that needs fonts', () => {
    const svg = watermarkSvg(1200, 1600, CODE);
    expect(svg).not.toContain('<text');
    expect(svg).toContain('<pattern');
    expect(svg).toContain(`fill-opacity="${WATERMARK_OPACITY}"`);
    expect(WATERMARK_OPACITY).toBeCloseTo(0.12);
  });

  it('refuses anything that is not a viewer code', () => {
    expect(() => watermarkSvg(100, 100, 'abc')).toThrow();
    expect(() => watermarkSvg(100, 100, 'IIIIOOOO')).toThrow();
    expect(() => watermarkSvg(100, 100, '<script>')).toThrow();
  });
});

describe('watermark', () => {
  it('keeps the size, and the output is a JPEG with no metadata at all', async () => {
    const input = await sharp(await syntheticPhoto(600, 800))
      .withExif({ IFD0: { Copyright: 'someone', Make: 'Phone' } })
      .withIccProfile('p3')
      .jpeg()
      .toBuffer();
    expect(hasJpegMetadata(input)).toBe(true);

    const out = await watermark(input, CODE);
    const meta = await sharp(out).metadata();
    expect(meta.format).toBe('jpeg');
    expect([meta.width, meta.height]).toEqual([600, 800]);
    expect(meta.exif).toBeUndefined();
    expect(meta.icc).toBeUndefined();
    expect(meta.xmp).toBeUndefined();
    expect(hasJpegMetadata(out)).toBe(false);
  });

  it('marks the whole photo faintly: every quadrant, small changes, never a solid block', async () => {
    const input = await flatJpeg(800, 1000);
    const before = await rawPixels(input);
    const after = await rawPixels(await watermark(input, CODE));

    let marked = 0;
    let maxDiff = 0;
    let total = 0;
    const quadrants = [0, 0, 0, 0];
    for (let y = 0; y < after.height; y += 1) {
      for (let x = 0; x < after.width; x += 1) {
        const i = (y * after.width + x) * after.channels;
        const diff = Math.abs(after.data[i]! - before.data[i]!);
        total += diff;
        maxDiff = Math.max(maxDiff, diff);
        if (diff >= 6) {
          marked += 1;
          quadrants[(y < after.height / 2 ? 0 : 2) + (x < after.width / 2 ? 0 : 1)]! += 1;
        }
      }
    }
    const pixels = after.width * after.height;
    // Tiled over the whole image...
    for (const count of quadrants) expect(count / (pixels / 4)).toBeGreaterThan(0.02);
    // ...faint: about 12% of the way to white or black, plus JPEG noise...
    expect(maxDiff).toBeLessThan(50);
    expect(total / pixels).toBeLessThan(6);
    // ...and mostly untouched.
    expect(marked / pixels).toBeLessThan(0.4);
  });

  it('matches the stored snapshot of a served card', async () => {
    const out = await watermark(await syntheticPhoto(600, 800), CODE);
    if (UPDATE || !existsSync(SNAPSHOT)) {
      mkdirSync(dirname(SNAPSHOT), { recursive: true });
      writeFileSync(SNAPSHOT, out);
    }
    const expected = await rawPixels(readFileSync(SNAPSHOT));
    const actual = await rawPixels(out);
    expect([actual.width, actual.height]).toEqual([expected.width, expected.height]);
    let total = 0;
    for (let i = 0; i < actual.data.length; i += 1) {
      total += Math.abs(actual.data[i]! - expected.data[i]!);
    }
    // Tolerant of tiny JPEG codec differences between machines, not of a missing watermark.
    expect(total / actual.data.length).toBeLessThan(1.5);
  });

  it('differs per viewer, so a leak points at one person', async () => {
    const input = await syntheticPhoto(400, 500);
    const a = await rawPixels(await watermark(input, 'K7MPQ2RX'));
    const b = await rawPixels(await watermark(input, 'Z9WX3TUV'));
    let diff = 0;
    for (let i = 0; i < a.data.length; i += 1) diff += Math.abs(a.data[i]! - b.data[i]!);
    expect(diff / a.data.length).toBeGreaterThan(0.3);
  });

  it('refuses something that is not an image', async () => {
    await expect(watermark(new Uint8Array([1, 2, 3, 4]), CODE)).rejects.toThrow();
  });
});
