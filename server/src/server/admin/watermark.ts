/**
 * A faint, repeated watermark of the viewer's code, so a leaked screenshot can be traced
 * (spec: Private images, step 9). STAND-IN for B3's watermark in server/src/server/images/,
 * which isn't merged yet. When it is, `watermarkJpeg` calls B3's, so admins and people in
 * rooms get the same mark.
 *
 * The output is a fresh JPEG: sharp drops all metadata unless told to keep it.
 */
import sharp from 'sharp';
import { PHOTO_JPEG_QUALITY_PERCENT } from '@/contracts';

const CODE = /^[A-HJ-NP-Z2-9]{8}$/;

function tile(code: string, width: number, height: number): Buffer {
  const step = Math.max(140, Math.round(Math.min(width, height) / 4));
  const size = Math.max(14, Math.round(step / 7));
  const rows: string[] = [];
  for (let y = -step; y < height + step; y += step) {
    for (let x = -step; x < width + step; x += step) {
      const shift = (Math.round(y / step) % 2) * (step / 2);
      rows.push(
        `<text x="${x + shift}" y="${y}" transform="rotate(-30 ${x + shift} ${y})">${code}</text>`,
      );
    }
  }
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}">
<style>text{font:600 ${size}px sans-serif;fill:#fff;fill-opacity:.18;stroke:#000;stroke-opacity:.12;stroke-width:1}</style>
${rows.join('\n')}
</svg>`;
  return Buffer.from(svg);
}

export async function watermarkJpeg(jpeg: Uint8Array, viewerCode: string): Promise<Buffer> {
  // The code goes into SVG markup, so it must be exactly the 8-character alphabet.
  if (!CODE.test(viewerCode)) throw new Error('viewer code is not valid');
  // Apply any orientation first, so the mark is laid over the image as it's seen.
  const { data, info } = await sharp(jpeg, { failOn: 'error' })
    .rotate()
    .raw()
    .toBuffer({ resolveWithObject: true });
  const { width, height, channels } = info;
  return sharp(data, { raw: { width, height, channels } })
    .composite([{ input: tile(viewerCode, width, height), top: 0, left: 0 }])
    .jpeg({ quality: PHOTO_JPEG_QUALITY_PERCENT, mozjpeg: true })
    .toBuffer();
}
