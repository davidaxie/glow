/**
 * Owner: B4. What the deck, taps and matches modules use from other owners, in one place.
 * Stand-ins have the owner's exact signature and are swapped here when the owner merges.
 *
 * - B3 (PR #7): `cardImageLink(cardId, viewerId)` from `@/server/images/signed-link` (stand-in)
 * - B5 (PR #15): `notify(userIds, event)` from `@/server/notify` (stand-in)
 * - B8 (#12, merged): `rateLimit(key, policy)` from `@/server/ratelimit`
 */
export { cardImageLink } from './stubs/card-link';
export { notify } from './stubs/notify';
export { rateLimit } from '@/server/ratelimit';
