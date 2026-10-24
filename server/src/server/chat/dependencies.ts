/**
 * Owner: C4. What chat uses from other owners, in one place, so tests can replace them and a
 * stand-in can be swapped for the real module in one line.
 *
 * - B8: `moderateText(body)`, `messageRejected()` and `TEXT_FIXTURE` from
 *   `@/server/moderation`, and `rateLimit(key, policy)` from `@/server/ratelimit`
 * - B5 (PR #15, still a stand-in): `notify(userIds, event)` from `@/server/notify`
 */
export { messageRejected, moderateText, TEXT_FIXTURE } from '@/server/moderation';
export { rateLimit } from '@/server/ratelimit';
export { notify } from './stubs/notify';
