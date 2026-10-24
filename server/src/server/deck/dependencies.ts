/**
 * Owner: B4. What the deck, taps and matches modules use from other owners. All three are
 * stand-ins with the owners' exact signatures until their PRs merge; this file is the one
 * place to swap them for the real modules.
 *
 * - B3 (PR #7): `cardImageLink(cardId, viewerId)` from `@/server/images/signed-link`
 * - B5 (PR #15): `notify(userIds, event)` from `@/server/notify`
 * - B8 (PR #12): `rateLimit(key, policy)` from `@/server/ratelimit`
 */
export { cardImageLink } from './stubs/card-link';
export { notify } from './stubs/notify';
export { rateLimit } from './stubs/ratelimit';
