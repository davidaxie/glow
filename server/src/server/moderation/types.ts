/**
 * Shapes for B8's moderation. See `./index.ts` for how to call it.
 */

/** Which photo is being checked. The rules differ (see `decideImage`). */
export type ImageKind = 'card' | 'profile';

/** What the model saw in a photo. Booleans only: no descriptions, no text from the image. */
export type ImageFindings = {
  readonly personPresent: boolean;
  readonly faceVisible: boolean;
  readonly nudity: boolean;
  readonly outfitVisible: boolean;
  readonly possiblyUnder18: boolean;
};

/**
 * Why a photo was refused. These are exactly the `reason` values the contract lists for
 * 422 `photo_rejected`, so a route can pass `reason` straight through.
 */
export type ImageRejectReason =
  'face_visible' | 'nudity' | 'no_outfit' | 'no_person' | 'possibly_minor' | 'unreadable';

/**
 * The verdict on one photo. `decision` matches `profile_photos.moderation_status`
 * (approved, held, rejected), so B1 can store it as is.
 *
 * - `approved`: store and use it.
 * - `rejected`: don't store it. Answer 422 `photo_rejected` with `reason`.
 * - `held`: profile photos only. Store it as `held`; it's never shown until an admin
 *   approves it (B7). Today the only hold reason is `possibly_minor`.
 *
 * A moderation outage is not a verdict: `moderateImage` throws `ModerationUnavailableError`.
 */
export type ImageModeration =
  | { readonly decision: 'approved'; readonly findings: ImageFindings }
  | {
      readonly decision: 'rejected';
      readonly reason: ImageRejectReason;
      readonly findings?: ImageFindings;
    }
  | {
      readonly decision: 'held';
      readonly reason: 'possibly_minor';
      readonly findings: ImageFindings;
    };

/** Kinds of chat message that are refused. `none` means it's fine. */
export type TextCategory =
  'none' | 'harassment' | 'hate' | 'threat' | 'sexual_explicit' | 'minor_safety' | 'scam';

export type TextFindings = {
  readonly flagged: boolean;
  readonly category: TextCategory;
};

/**
 * The verdict on one chat message. `decision` matches `messages.moderation`
 * (passed, flagged, pending), so C4 can store it as is.
 *
 * - `passed`: send it.
 * - `flagged`: refuse it with 422 `message_rejected`, and don't store it.
 * - `pending`: moderation didn't answer within MODERATION_TIMEOUT. Send it anyway and
 *   store `moderation: 'pending'`. B8's purge cron reviews pending messages afterwards
 *   and marks the bad ones `flagged` (see `reviewPendingMessages`).
 */
export type TextModeration =
  | { readonly decision: 'passed' }
  | { readonly decision: 'flagged'; readonly category: Exclude<TextCategory, 'none'> | 'other' }
  | { readonly decision: 'pending' };
