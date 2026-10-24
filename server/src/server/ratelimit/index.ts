/**
 * B8's rate limits.
 *
 *   import { rateLimit } from '@/server/ratelimit';
 *
 *   await rateLimit(user.id, 'messages'); // throws 429 rate_limited with Retry-After
 *
 * Or check without throwing:
 *
 *   const { allowed, retryAfterSeconds } = await checkRateLimit(user.id, 'deck');
 *
 * `limitRequest(operationId, req, user)` picks the policy for a contract operation and the
 * key (the person's ID, or the client IP when there's no sign-in). It's meant for A1's
 * route helper, so every route is limited without each handler remembering to.
 *
 * Keys never reach the store as given: each is an HMAC of the policy and key, so Upstash
 * never sees a user ID or an IP address. Upstash outages fail open after 1 second (logged).
 */
import { createHmac, hkdfSync } from 'node:crypto';
import { getEnv } from '@/env';
import { rateLimited } from '@/server/http';
import { logger } from '@/server/log';
import {
  RATE_LIMIT_POLICIES,
  policyForOperation,
  type RateLimitPolicy,
  type RateLimitPolicyName,
} from './policies';
import { memoryStore, upstashStore, type RateLimitStore } from './stores';

export { RATE_LIMIT_POLICIES, policyForOperation, type RateLimitPolicyName, type RateLimitPolicy };
export { memoryStore, type RateLimitStore } from './stores';

export type RateLimitResult = {
  readonly allowed: boolean;
  readonly remaining: number;
  /** Whole seconds until another request is allowed. 0 when allowed. */
  readonly retryAfterSeconds: number;
};

let override: RateLimitStore | undefined;
let memory: ReturnType<typeof memoryStore> | undefined;
let upstash: { id: string; store: RateLimitStore } | undefined;
let hashKey: { source: string; key: Buffer } | undefined;

function activeStore(): RateLimitStore {
  if (override) return override;
  const env = getEnv();
  if (env.UPSTASH_REDIS_REST_URL && env.UPSTASH_REDIS_REST_TOKEN) {
    const id = `${env.UPSTASH_REDIS_REST_URL}\u0000${env.UPSTASH_REDIS_REST_TOKEN}`;
    if (upstash?.id !== id) {
      upstash = {
        id,
        store: upstashStore(env.UPSTASH_REDIS_REST_URL, env.UPSTASH_REDIS_REST_TOKEN),
      };
    }
    return upstash.store;
  }
  if (env.profile === 'local') return (memory ??= memoryStore());
  throw new Error('UPSTASH_REDIS_REST_URL and UPSTASH_REDIS_REST_TOKEN are required on Vercel.');
}

/**
 * The key the store sees: HMAC-SHA256 over the policy and key, with a key derived (HKDF)
 * from the service role key, which never leaves the server. Not reversible, and a
 * dictionary of IP addresses or user IDs doesn't help without that secret.
 */
function storeKey(policy: RateLimitPolicyName, key: string): string {
  const source = getEnv().SUPABASE_SERVICE_ROLE_KEY;
  if (hashKey?.source !== source) {
    const derived = Buffer.from(hkdfSync('sha256', source, '', 'glow/ratelimit-key/v1', 32));
    hashKey = { source, key: derived };
  }
  return createHmac('sha256', hashKey.key).update(`${policy}\u0000${key}`).digest('base64url');
}

/** Counts one request against `policy` for `key`, and says whether it's allowed. */
export async function checkRateLimit(
  key: string,
  policy: RateLimitPolicyName,
): Promise<RateLimitResult> {
  const spec = RATE_LIMIT_POLICIES[policy];
  const store = activeStore();
  try {
    const now = Date.now();
    const result = await store.hit(storeKey(policy, key), policy, spec, now);
    if (!result.allowed) logger.info('ratelimit.limited', { policy, store: store.name });
    return {
      allowed: result.allowed,
      remaining: result.remaining,
      retryAfterSeconds: result.allowed ? 0 : Math.max(1, Math.ceil((result.resetAt - now) / 1000)),
    };
  } catch (error) {
    // Fail open: an outage of the limiter must not take the API down with it.
    logger.warn('ratelimit.unavailable', {
      policy,
      store: store.name,
      cause: error instanceof Error ? error.name : typeof error,
    });
    return { allowed: true, remaining: spec.limit, retryAfterSeconds: 0 };
  }
}

/** Counts one request, and throws 429 `rate_limited` (with Retry-After) if it's over. */
export async function rateLimit(key: string, policy: RateLimitPolicyName): Promise<void> {
  const result = await checkRateLimit(key, policy);
  if (!result.allowed) throw rateLimited(result.retryAfterSeconds);
}

/**
 * The client IP as Vercel reports it. Vercel sets x-forwarded-for itself (the first entry
 * is the client), so it can't be spoofed there. Locally it's usually absent.
 */
export function clientIp(req: Request): string {
  const forwarded = req.headers.get('x-forwarded-for')?.split(',')[0]?.trim();
  return forwarded || req.headers.get('x-real-ip')?.trim() || 'unknown';
}

/** Requests already counted, so calling `limitRequest` twice for one request counts once. */
const counted = new WeakSet<Request>();

/**
 * Limits one API request by its contract operation: per person when signed in, per IP
 * otherwise. Throws 429. Operations without a policy (the purge cron) pass. Counts each
 * request once, so a handler may call it even if the route helper already did.
 */
export async function limitRequest(
  operationId: string,
  req: Request,
  user: { readonly id: string } | null,
): Promise<void> {
  const policy = policyForOperation(operationId);
  if (!policy || counted.has(req)) return;
  counted.add(req);
  // A user ID is a UUID, so it can never collide with an `ip:` key.
  await rateLimit(user ? user.id : `ip:${clientIp(req)}`, policy);
}

/** For tests only: use `store` (or the defaults again with `undefined`), and forget counts. */
export function setRateLimitStoreForTests(store: RateLimitStore | undefined): void {
  override = store;
  memory?.clear();
}
