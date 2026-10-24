/**
 * Owner: C3. What the glow module uses from other owners, in one place.
 *
 * - B5: `notify(userIds, event)` from `@/server/notify`. A Realtime broadcast to each person's
 *   `user:{id}` channel plus an Apple push when the event has one, built only from
 *   contracts/events.json. It never throws.
 */
export { notify, type UserEvent } from '@/server/notify';
