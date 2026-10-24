/**
 * B3 · Check-in and private images.
 *
 * - Routes: `createCheckin`, `getCardImage`, `getMatchPhoto`.
 * - For other modules: `cardImageLink(cardId, viewerId)` signs the `SignedImage` a deck card or
 *   check-in carries (B4's deck uses it), and `watermark(jpeg, viewerCode)` draws the viewer's
 *   code over an image (B7's admin card image can reuse it).
 */
export { createCheckin } from './checkin';
export { getCardImage } from './card-image';
export { getMatchPhoto } from './match-photo';
export { cardImageLink, isValidCardImageLink, type SignedImage } from './signed-link';
export { watermark } from './watermark';
