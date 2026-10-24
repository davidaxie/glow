/**
 * Owner: B4. The two things the deck, taps and matches modules use from other owners.
 * Both are stand-ins until their owners merge; this file is the one place to swap them.
 *
 * - B3, signed card image links: `signCardImage(cardId, viewerId)` from `server/src/server/images`
 * - B5, events: `notify(userId, event)` from `server/src/server/notify`
 */
export { signCardImage } from './stubs/card-link';
export { notify } from './stubs/notify';
