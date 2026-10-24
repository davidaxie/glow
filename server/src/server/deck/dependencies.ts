/**
 * Owner: B4. What the deck, taps and matches modules use from other owners, in one place.
 * Both are stand-ins with the owner's exact signature until the owner merges; swap them here.
 *
 * - B3 (PR #7): `cardImageLink(cardId, viewerId)` from `@/server/images/signed-link`
 * - B5 (PR #15): `notify(userIds, event)` from `@/server/notify`
 *
 * (Rate limits need nothing here: route() applies B8's policy for every operation.)
 */
export { cardImageLink } from './stubs/card-link';
export { notify } from './stubs/notify';
