/**
 * Owner: B4. The two things the deck, taps and matches modules use from other owners.
 * Both are stand-ins until their owners merge; this file is the one place to swap them.
 *
 * - B3 (PR #7): `cardImageLink(cardId, viewerId)` from `@/server/images/signed-link`
 * - B5: `notify(userId, event)` from `@/server/notify`
 */
export { cardImageLink } from './stubs/card-link';
export { notify } from './stubs/notify';
