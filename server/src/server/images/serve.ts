/**
 * Shared by the two image routes: read a private object, watermark it with the viewer's code,
 * and send it so nothing on the way (browser, proxy, CDN, the app) keeps a copy.
 */
import { notFound, unavailable } from '@/server/http';
import { logger } from '@/server/log';
import { watermark } from './watermark';
import { serviceClient, type ServiceClient } from './supabase';

/** The headers on every served image. `Cache-Control` is exactly the contract's `no-store`. */
export const IMAGE_HEADERS: Readonly<Record<string, string>> = {
  'content-type': 'image/jpeg',
  'cache-control': 'no-store',
  pragma: 'no-cache',
  expires: '0',
  'content-disposition': 'inline',
  'x-content-type-options': 'nosniff',
  'referrer-policy': 'no-referrer',
  'cross-origin-resource-policy': 'same-origin',
};

/** The signed-in person's watermark code, or 404 if they have no profile. */
export async function viewerCodeOf(userId: string, db: ServiceClient = serviceClient()) {
  const { data, error } = await db
    .from('profiles')
    .select('viewer_code')
    .eq('id', userId)
    .maybeSingle();
  if (error) throw unavailable();
  if (!data) throw notFound();
  return data.viewer_code;
}

/** The object's bytes, 404 if it's gone (purged, replaced), 503 if storage is down. */
export async function readPrivateObject(
  bucket: string,
  path: string,
  db: ServiceClient = serviceClient(),
): Promise<Uint8Array> {
  const { data, error } = await db.storage.from(bucket).download(path);
  if (error || !data) {
    const status = (error as { status?: number; statusCode?: string } | null)?.status;
    const statusCode = (error as { statusCode?: string } | null)?.statusCode;
    if (status === 400 || status === 404 || statusCode === '404' || statusCode === '400') {
      throw notFound();
    }
    logger.warn('images.read_failed', { bucket });
    throw unavailable();
  }
  return new Uint8Array(await data.arrayBuffer());
}

/** A watermarked, never-cached JPEG response. */
export async function watermarkedResponse(jpeg: Uint8Array, viewerCode: string): Promise<Response> {
  const out = await watermark(jpeg, viewerCode);
  return new Response(new Uint8Array(out), {
    status: 200,
    headers: { ...IMAGE_HEADERS, 'content-length': String(out.byteLength) },
  });
}
