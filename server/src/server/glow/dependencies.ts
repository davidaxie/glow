/**
 * Owner: C3. What the glow module uses from other owners, in one place to swap.
 *
 * - B5 (PR #15): `notify(userIds, event)` from `@/server/notify`. A stand-in with the same
 *   signature until it merges.
 */
export { notify, type UserEvent } from './stubs/notify';
