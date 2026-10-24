import sharp from 'sharp';

/** Marker bytes of every segment before the image data (SOS). */
export function jpegMarkers(jpeg: Uint8Array): number[] {
  if (jpeg[0] !== 0xff || jpeg[1] !== 0xd8) throw new Error('not a JPEG');
  const markers: number[] = [];
  let i = 2;
  while (i + 3 < jpeg.length) {
    if (jpeg[i] !== 0xff) throw new Error('bad marker');
    const marker = jpeg[i + 1]!;
    if (marker === 0xda) break;
    markers.push(marker);
    i += 2 + ((jpeg[i + 2]! << 8) | jpeg[i + 3]!);
  }
  return markers;
}

/** True if the JPEG has EXIF/XMP (APP1), ICC (APP2), IPTC (APP13), other APPn or comments. */
export function hasJpegMetadata(jpeg: Uint8Array): boolean {
  return jpegMarkers(jpeg).some((m) => (m >= 0xe1 && m <= 0xef) || m === 0xfe);
}

/** A synthetic "outfit" photo: dark background, a light top and dark trousers. */
export async function syntheticPhoto(width = 600, height = 800): Promise<Buffer> {
  const rect = (w: number, h: number, rgb: [number, number, number]) =>
    sharp({
      create: { width: w, height: h, channels: 3, background: { r: rgb[0], g: rgb[1], b: rgb[2] } },
    })
      .png()
      .toBuffer();
  const top = await rect(Math.round(width * 0.6), Math.round(height * 0.35), [236, 236, 230]);
  const legs = await rect(Math.round(width * 0.4), Math.round(height * 0.4), [32, 34, 44]);
  return sharp({ create: { width, height, channels: 3, background: { r: 128, g: 128, b: 128 } } })
    .composite([
      { input: top, top: Math.round(height * 0.2), left: Math.round(width * 0.2) },
      { input: legs, top: Math.round(height * 0.55), left: Math.round(width * 0.3) },
    ])
    .jpeg({ quality: 90 })
    .toBuffer();
}

/** A flat gray JPEG. */
export function flatJpeg(width: number, height: number, gray = 128): Promise<Buffer> {
  return sharp({
    create: { width, height, channels: 3, background: { r: gray, g: gray, b: gray } },
  })
    .jpeg({ quality: 95 })
    .toBuffer();
}

export async function rawPixels(jpeg: Uint8Array) {
  const { data, info } = await sharp(jpeg)
    .removeAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });
  return { data, width: info.width, height: info.height, channels: info.channels };
}
