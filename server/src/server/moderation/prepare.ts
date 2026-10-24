/**
 * Gets a photo ready for the model: decode it (anything that isn't a readable JPEG is
 * refused before any network call), apply its orientation, drop all metadata, and
 * downscale to at most MODEL_IMAGE_MAX_SIDE. Smaller images answer faster and cost less,
 * and 768 px is plenty to see a face, nudity or an outfit.
 */
import sharp from 'sharp';

export const MODEL_IMAGE_MAX_SIDE = 768;

/** The prepared JPEG, or null if `bytes` isn't a JPEG we can read. */
export async function prepareImage(
  bytes: Uint8Array,
  maxInputSide: number,
): Promise<Uint8Array | null> {
  try {
    // limitInputPixels stops decompression bombs before they use memory.
    const image = sharp(bytes, {
      limitInputPixels: maxInputSide * maxInputSide * 2,
      failOn: 'error',
    });
    const meta = await image.metadata();
    if (meta.format !== 'jpeg' || !meta.width || !meta.height) return null;
    const out = await image
      .rotate()
      .resize({
        width: MODEL_IMAGE_MAX_SIDE,
        height: MODEL_IMAGE_MAX_SIDE,
        fit: 'inside',
        withoutEnlargement: true,
      })
      .jpeg({ quality: 80 })
      .toBuffer();
    return new Uint8Array(out);
  } catch {
    return null;
  }
}
