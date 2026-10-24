/**
 * Owner: C4. What chat uses from other owners, in one place, so tests can replace them.
 *
 * - B8: `moderateText(body)`, `messageRejected()` and `TEXT_FIXTURE` from `@/server/moderation`.
 *   Rate limits need nothing here: A1's `route()` counts every `sendMessage` against B8's
 *   `messages` policy before the handler runs.
 * - B5: `notify(userIds, event)` and `notifyRoom(roomId, event)` from `@/server/notify`, a
 *   Realtime broadcast on the private channel plus an Apple push when the event has one.
 */
export { messageRejected, moderateText, TEXT_FIXTURE } from '@/server/moderation';
export { notify, notifyRoom } from '@/server/notify';
