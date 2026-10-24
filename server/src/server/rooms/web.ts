/**
 * The two public web answers behind room links. Owner: B2.
 *
 * - `GET /.well-known/apple-app-site-association` lets `https://{DOMAIN}/r/*` open Glow.
 * - `GET /r/{slug}` is what someone without Glow sees after scanning a room's QR code.
 *
 * The page is the same for every slug and token: it never looks the room up, so it
 * can't say whether a room exists, and it never shows the token or the room's location.
 */
import type { AppleAppSiteAssociation } from '@/contracts';
import { getEnv } from '@/env';
import type { RouteHandler } from '@/server/http';

/** The universal link paths Glow opens. Matches AppCore's DeepLink. */
export const ROOM_LINK_PATHS = ['/r/*'] as const;

/**
 * `APPLE_APP_ID` (`{TEAM_ID}.{BUNDLE_ID}`), or none while it isn't set. With no app ID the
 * file is still valid; links just open the web page instead of the app (B2-D3).
 */
export function appleAppIds(): string[] {
  const appId = getEnv().APPLE_APP_ID;
  return appId ? [appId] : [];
}

export function appSiteAssociation(appIds: readonly string[]): AppleAppSiteAssociation {
  return {
    applinks: {
      details:
        appIds.length === 0
          ? []
          : [
              {
                appIDs: [...appIds],
                components: ROOM_LINK_PATHS.map((path) => ({ '/': path })),
              },
            ],
    },
  };
}

export const getAppSiteAssociation: RouteHandler<'getAppSiteAssociation'> = () =>
  new Response(JSON.stringify(appSiteAssociation(appleAppIds())), {
    status: 200,
    headers: {
      'content-type': 'application/json',
      // Public and the same for everyone; Apple's CDN fetches it.
      'cache-control': 'public, max-age=3600',
    },
  });

/** The public TestFlight invite link (`TESTFLIGHT_URL`, set by B9), or null until it exists. */
export function testFlightUrl(): string | null {
  return getEnv().TESTFLIGHT_URL ?? null;
}

const escapeHtml = (value: string) =>
  value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

/** The whole page. Inline styles only, no scripts, no images, nothing third party. */
export function roomWebPage(options: { readonly testFlightUrl: string | null }): string {
  const link = options.testFlightUrl;
  const action = link
    ? `<a class="button" href="${escapeHtml(link)}" rel="noreferrer noopener">Get Glow on TestFlight</a>
      <p class="small">Then scan the room's code again with your iPhone camera.</p>`
    : `<p class="small">Glow is in a private beta. Ask the host for a TestFlight invite, then scan the room's code again with your iPhone camera.</p>`;
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="referrer" content="no-referrer">
<meta name="robots" content="noindex, nofollow">
<meta name="color-scheme" content="dark">
<title>Join this room on Glow</title>
<style>
  :root { color-scheme: dark; }
  body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: #0B0B10;
    color: #F4F4F6; font: 17px/1.5 -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif; }
  main { max-width: 26rem; padding: 32px 24px; text-align: center; }
  h1 { font-size: 34px; margin: 0 0 8px; color: #FF4FA3; }
  h2 { font-size: 22px; margin: 0 0 16px; font-weight: 600; }
  p { color: #A1A1AA; margin: 0 0 24px; }
  .button { display: inline-block; background: #FF4FA3; color: #0B0B10; text-decoration: none;
    font-weight: 600; padding: 14px 22px; border-radius: 12px; margin-bottom: 16px; }
  .small { font-size: 15px; }
  ol { text-align: left; color: #A1A1AA; padding-left: 1.2em; margin: 0 0 28px; }
</style>
</head>
<body>
<main>
  <h1>Glow</h1>
  <h2>Someone here might have noticed you.</h2>
  <p>Glow lets two people in the same room find out, privately, that they noticed each other.</p>
  <ol>
    <li>Get Glow on your iPhone.</li>
    <li>Scan the room's code again, or type its 6-character code in the app.</li>
    <li>Glow checks once that you're in the room, then forgets your location.</li>
  </ol>
  ${action}
</main>
</body>
</html>
`;
}

export const getRoomWebPage: RouteHandler<'getRoomWebPage'> = () =>
  new Response(roomWebPage({ testFlightUrl: testFlightUrl() }), {
    status: 200,
    headers: {
      'content-type': 'text/html; charset=utf-8',
      // The URL can carry a QR token, so nothing keeps a copy of this response.
      'cache-control': 'no-store, max-age=0',
      'content-security-policy':
        "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
      'referrer-policy': 'no-referrer',
    },
  });
