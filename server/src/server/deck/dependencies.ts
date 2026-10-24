/**
 * Owner: B4. What the deck, taps and matches modules use from other owners, in one place.
 *
 * - B5 (#15, #37, merged): `notify(userIds, event)` and `notifySettled(settled)` from
 *   `@/server/notify`. Neither throws.
 * - B3 (#7, merged): `cardImageLink(cardId, viewerId)` from `@/server/images/signed-link`.
 *
 * (Rate limits need nothing here: route() applies B8's policy for every operation.)
 */
export { cardImageLink } from '@/server/images/signed-link';
export { notify, notifySettled } from '@/server/notify';
