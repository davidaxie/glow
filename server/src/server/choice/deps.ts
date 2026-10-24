/**
 * Everything C2 takes from other owners' modules, in one place. Owner: C2.
 *
 * Tests replace this module with `vi.mock` (to watch `notify`). C3's `startGlow` isn't here yet:
 * until it merges, `./glow-start` stands in for it.
 */
export { checkFix, recordLocationCheck } from '@/server/geo';
export { notify, type UserEvent } from '@/server/notify';
export { rateLimit } from '@/server/ratelimit';
