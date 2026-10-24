/**
 * Owner: C4. STAND-IN for B8's `rateLimit(key, policy)` from `@/server/ratelimit` (PR #12),
 * until it merges (AGENTS.md, "Mocks"). Same signature. When #12 merges, point
 * `../dependencies.ts` at `@/server/ratelimit` and delete this file. (Once A1 calls
 * `limitRequest` in `route()`, the send handler can drop its own call.)
 *
 * B8's version counts a sliding window per person (`messages`: 30 a minute) and throws 429
 * `rate_limited` with Retry-After. This one allows everything.
 */
export type RateLimitPolicyName = 'messages' | 'api';

export async function rateLimit(_key: string, _policy: RateLimitPolicyName): Promise<void> {}
