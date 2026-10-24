/**
 * Owner: B8. What safety uses from other owners, in one place.
 *
 * - B5: `notify(userIds, event)` and `notifyRoom(roomId, event)` from `@/server/notify`:
 *   a Realtime broadcast on the private channel, plus an Apple push when the event has one.
 *   Both never throw. Tests mock this module to see what safety sends.
 */
export { notify, notifyRoom } from '@/server/notify';
