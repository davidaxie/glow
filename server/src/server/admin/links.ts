/**
 * Room links for posters, the display screen and the admin web.
 *
 * WEB_DOMAIN is the one server-side place the web domain ({DOMAIN} in the spec) is set. It
 * matches GLOW_WEB_DOMAIN in ios/Glow/Config/Shared.xcconfig, so a link built here opens the
 * Debug app today. The `.invalid` top-level domain can never resolve, so nothing points at a
 * domain we don't control. When {DOMAIN} is chosen, change this line and GLOW_WEB_DOMAIN together
 * (or move it into server/src/env.ts, which B7 asked A1 for in docs/HANDOFFS.md).
 */
import { z } from 'zod';
import { zQrToken, zRoomSlug } from '@/contracts';

export const WEB_DOMAIN = 'glow-domain-not-chosen.invalid';

/** `https://{DOMAIN}/r/{slug}?t={token}`, the link in every room QR code. */
export function roomLink(slug: string, token: string): string {
  const s = zRoomSlug.parse(slug);
  const t = zQrToken.parse(token);
  return `https://${WEB_DOMAIN}/r/${s}?t=${t}`;
}

/** What a scanned link names, for tests and the end-to-end check. Never trusts the input. */
export function parseRoomLink(link: string): { slug: string; token: string } | null {
  let url: URL;
  try {
    url = new URL(link);
  } catch {
    return null;
  }
  if (url.protocol !== 'https:' || url.hostname !== WEB_DOMAIN || url.port !== '') return null;
  const match = /^\/r\/([^/]+)$/.exec(url.pathname);
  const parsed = z
    .object({ slug: zRoomSlug, token: zQrToken })
    .safeParse({ slug: match?.[1], token: url.searchParams.get('t') });
  return parsed.success ? parsed.data : null;
}
