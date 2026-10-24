/**
 * The watermark on every served image: the viewer's code, repeated across the whole photo at
 * about 12% opacity, so a leaked screenshot can be traced to whoever was shown it (spec: Private
 * images on device, step 9). A light pass and a dark pass, offset slightly, keep it visible on
 * both white and black clothes while staying faint.
 *
 * The output is a fresh JPEG with no metadata (sharp drops it unless asked to keep it).
 */
import sharp from 'sharp';
import { PHOTO_MAX_DIMENSION_PX } from '@/contracts';
import { GLYPH_HEIGHT, hasGlyph, textPath, textWidth } from './glyphs';

// Decoded photos must not linger in libvips' operation cache between requests.
sharp.cache(false);

export const WATERMARK_OPACITY = 0.12;
export const WATERMARK_ANGLE_DEGREES = -30;
const OUTPUT_QUALITY = 85;
/** Refuses anything far larger than we ever store, so a hostile file can't exhaust memory. */
export const MAX_INPUT_PIXELS = PHOTO_MAX_DIMENSION_PX * PHOTO_MAX_DIMENSION_PX * 2;

const VIEWER_CODE = /^[A-HJ-NP-Z2-9]{8}$/;

/** The SVG overlay for an image of `width` by `height`. Exported for tests. */
export function watermarkSvg(width: number, height: number, viewerCode: string): string {
  if (!VIEWER_CODE.test(viewerCode)) throw new Error('A viewer code is 8 characters');
  const label = `·${viewerCode}·`;
  if (![...label].every(hasGlyph)) throw new Error('No glyph for a watermark character');

  // One font pixel is about 1/150 of the short side: roughly 9 px on a 1440 px wide photo.
  const unit = Math.max(2, Math.round(Math.min(width, height) / 150));
  const textW = textWidth(label) * unit;
  const textH = GLYPH_HEIGHT * unit;
  const tileW = textW + 10 * unit;
  const tileH = textH + 12 * unit;
  const shadow = Math.max(1, Math.round(unit / 3));
  const path = textPath(label, unit, 0, 0);

  // Two rows per tile, the second shifted half a tile, so the pattern reads as a brick wall.
  return [
    `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">`,
    '<defs>',
    `<path id="t" d="${path}"/>`,
    `<pattern id="w" patternUnits="userSpaceOnUse" width="${tileW}" height="${tileH * 2}" patternTransform="rotate(${WATERMARK_ANGLE_DEGREES})">`,
    `<g fill="#000" fill-opacity="${WATERMARK_OPACITY}">`,
    `<use href="#t" x="${shadow}" y="${shadow}"/>`,
    `<use href="#t" x="${tileW / 2 + shadow}" y="${tileH + shadow}"/>`,
    `<use href="#t" x="${-tileW / 2 + shadow}" y="${tileH + shadow}"/>`,
    '</g>',
    `<g fill="#fff" fill-opacity="${WATERMARK_OPACITY}">`,
    '<use href="#t" x="0" y="0"/>',
    `<use href="#t" x="${tileW / 2}" y="${tileH}"/>`,
    `<use href="#t" x="${-tileW / 2}" y="${tileH}"/>`,
    '</g>',
    '</pattern>',
    '</defs>',
    `<rect width="${width}" height="${height}" fill="url(#w)"/>`,
    '</svg>',
  ].join('');
}

/** The served JPEG: `jpeg`, upright, with the viewer's code tiled over it, and no metadata. */
export async function watermark(jpeg: Uint8Array, viewerCode: string): Promise<Buffer> {
  // Apply any orientation first, so the overlay is drawn on the picture as people see it.
  const { data, info } = await sharp(jpeg, { failOn: 'error', limitInputPixels: MAX_INPUT_PIXELS })
    .rotate()
    .removeAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });
  const overlay = Buffer.from(watermarkSvg(info.width, info.height, viewerCode));
  return sharp(data, { raw: { width: info.width, height: info.height, channels: info.channels } })
    .composite([{ input: overlay, top: 0, left: 0 }])
    .jpeg({ quality: OUTPUT_QUALITY })
    .toBuffer();
}
