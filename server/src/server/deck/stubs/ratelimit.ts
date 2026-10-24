/**
 * Owner: B4. STAND-IN for B8's `rateLimit(key, policy)` from `@/server/ratelimit` (PR #12),
 * until it merges (AGENTS.md, "Mocks"). Same signature. When #12 merges, point
 * `../dependencies.ts` at `@/server/ratelimit` and delete this file. (Once A1 calls
 * `limitRequest` in `route()`, the handlers can drop their own calls.)
 *
 * B8's version counts a sliding window per person and throws 429 `rate_limited` with
 * Retry-After. This one allows everything: the product caps (3 taps, 50 card views a day)
 * are enforced by the database either way.
 */
export type RateLimitPolicyName = 'deck' | 'taps' | 'api';

export async function rateLimit(_key: string, _policy: RateLimitPolicyName): Promise<void> {}
