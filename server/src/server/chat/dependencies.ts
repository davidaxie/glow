/**
 * Owner: C4. What chat uses from other owners. Each is a stand-in with the owner's exact
 * signature until their PR merges; this file is the one place to swap them for the real
 * modules.
 *
 * - B5 (PR #15): `notify(userIds, event)` from `@/server/notify`
 * - B8 (PR #12): `moderateText(body)`, `messageRejected()` and `TEXT_FIXTURE` from
 *   `@/server/moderation`, and `rateLimit(key, policy)` from `@/server/ratelimit`
 */
export { notify } from './stubs/notify';
export { messageRejected, moderateText, TEXT_FIXTURE } from './stubs/moderation';
export { rateLimit } from './stubs/ratelimit';
