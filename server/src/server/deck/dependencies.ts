/**
 * Owner: B4. What the deck, taps and matches modules use from other owners, in one place.
 *
 * - B5 (#15, merged): `notify(userIds, event)` from `@/server/notify`. Never throws.
 * - B3 (PR #7): `cardImageLink(cardId, viewerId)` from `@/server/images/signed-link`. Still a
 *   stand-in with B3's exact signature until #7 merges; swap it here.
 *
 * (Rate limits need nothing here: route() applies B8's policy for every operation.)
 */
export { cardImageLink } from './stubs/card-link';
export { notify } from '@/server/notify';
