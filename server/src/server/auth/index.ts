/**
 * Sign-in checks for API routes. The route helper calls these for you, based on the
 * operation's `auth` in the contract, so a route never forgets to check.
 *
 *   const user = await requireUser(req); // throws 401, or 503 if Auth is down
 *
 * 401 is the same for every route and is decided before anything is looked up, so
 * it never reveals whether a resource exists (P11).
 */
import { createHash, timingSafeEqual } from 'node:crypto';
import { getEnv } from '@/env';
import { unauthorized, unavailable } from '@/server/http/errors';
import { verifyAccessToken, type AuthUser } from './verify';

export type { AuthUser } from './verify';

/** Supabase access tokens are about 1 KB. Anything far bigger isn't one. */
const MAX_TOKEN_LENGTH = 8192;
const JWT_SHAPE = /^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/;

/** The raw Bearer token, or null if the header is missing or malformed. */
export function bearerToken(req: Request): string | null {
  const header = req.headers.get('authorization');
  if (!header) return null;
  const match = /^Bearer\s+(\S+)\s*$/i.exec(header);
  return match?.[1] ?? null;
}

type Claims = { sub?: unknown; exp?: unknown; role?: unknown; aud?: unknown };

/** Reads claims without trusting them, only to reject obvious junk before a network call. */
export function unverifiedClaims(token: string): Claims | null {
  if (token.length > MAX_TOKEN_LENGTH || !JWT_SHAPE.test(token)) return null;
  const payload = token.split('.')[1];
  if (!payload) return null;
  try {
    const json: unknown = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8'));
    return typeof json === 'object' && json !== null ? (json as Claims) : null;
  } catch {
    return null;
  }
}

function looksLikeLiveUserToken(claims: Claims, now: number): boolean {
  const audOk =
    claims.aud === 'authenticated' ||
    (Array.isArray(claims.aud) && claims.aud.includes('authenticated'));
  return (
    typeof claims.sub === 'string' &&
    typeof claims.exp === 'number' &&
    claims.exp * 1000 > now &&
    claims.role === 'authenticated' &&
    audOk
  );
}

/** The signed-in person making this request. Throws 401 or 503. */
export async function requireUser(req: Request): Promise<AuthUser> {
  const token = bearerToken(req);
  if (!token) throw unauthorized();
  const claims = unverifiedClaims(token);
  if (!claims || !looksLikeLiveUserToken(claims, Date.now())) throw unauthorized();

  const outcome = await verifyAccessToken(token);
  if (outcome.kind === 'unavailable') throw unavailable();
  if (outcome.kind === 'invalid' || outcome.user.id !== claims.sub) throw unauthorized();
  return outcome.user;
}

function sameSecret(given: string, expected: string): boolean {
  const a = createHash('sha256').update(given).digest();
  const b = createHash('sha256').update(expected).digest();
  return timingSafeEqual(a, b);
}

/** For `GET /api/cron/purge`. Vercel Cron sends `Authorization: Bearer $CRON_SECRET`. */
export function requireCron(req: Request): void {
  const token = bearerToken(req);
  if (!token || !sameSecret(token, getEnv().CRON_SECRET)) throw unauthorized();
}
