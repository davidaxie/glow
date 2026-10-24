/**
 * A faint, repeated watermark of the viewer's code, so a leaked screenshot can be traced
 * (spec: Private images, step 9). Admins get B3's mark from `@/server/images`, the same one
 * people in rooms see, drawn with the admin's own viewer code (B7-D6).
 *
 * The output is a fresh JPEG with no metadata.
 */
import { watermark } from '@/server/images/watermark';

export async function watermarkJpeg(jpeg: Uint8Array, viewerCode: string): Promise<Buffer> {
  return watermark(jpeg, viewerCode);
}
