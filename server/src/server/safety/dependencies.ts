/**
 * Owner: B8. What safety uses from other owners, in one place to swap.
 *
 * - B5 (PR #15): `notify(userIds, event)` and `notifyRoom(roomId, event)` from
 *   `@/server/notify`. Until it merges, `./stubs/notify` stands in with the same signatures.
 *   Both never throw.
 */
export { notify, notifyRoom } from './stubs/notify';
