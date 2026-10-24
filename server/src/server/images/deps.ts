/**
 * What check-in needs from other agents' modules, in one place.
 *
 * - `verifyJoinTicket` (B2, `@/server/rooms`): the join ticket from a passed location check.
 *   Null means expired, someone else's, another room's, edited or malformed; check-in answers
 *   422 `join_ticket_invalid`.
 * - `moderateImage`, `photoRejected` (B8, `@/server/moderation`): card photos fail closed.
 *
 * Rate limits come from the route helper (`limitRequest`), so check-in doesn't call them itself.
 */
export { verifyJoinTicket, type VerifiedJoinTicket } from '@/server/rooms';
export { moderateImage, photoRejected } from '@/server/moderation';
