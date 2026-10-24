/**
 * B8's moderation, for photos (B1 profile photos, B3 card photos) and chat (C4).
 *
 *   import { moderateImage, photoRejected, moderationUnavailable } from '@/server/moderation';
 *
 *   // B3, POST /api/rooms/{id}/checkin. Card photos fail closed.
 *   const verdict = await moderateImage('card', jpegBytes); // throws ModerationUnavailableError
 *   if (verdict.decision !== 'approved') throw photoRejected(verdict.reason);
 *
 *   // B1, POST /api/me/photos. Possibly under 18 is held for review, not rejected.
 *   const verdict = await moderateImage('profile', jpegBytes);
 *   if (verdict.decision === 'rejected') throw photoRejected(verdict.reason);
 *   // store with moderation_status = verdict.decision ('approved' or 'held')
 *
 *   // C4, POST /api/matches/{id}/messages. Never throws.
 *   const verdict = await moderateText(body);
 *   if (verdict.decision === 'flagged') throw messageRejected();
 *   // store with moderation = verdict.decision ('passed' or 'pending')
 *
 * `ModerationUnavailableError` (timeout after MODERATION_TIMEOUT, outage, bad answer) is
 * already an HttpError: a 503 `unavailable` with Retry-After, so letting it propagate from
 * a route handler gives the contract's answer. Nothing here logs photos or message text.
 */
import { MODERATION_TIMEOUT_MS, PHOTO_MAX_DIMENSION_PX } from '@/contracts';
import { HttpError, unprocessable } from '@/server/http';
import { logger } from '@/server/log';
import { activeModel, ModelRefusal } from './model';
import { prepareImage } from './prepare';
import type {
  ImageFindings,
  ImageKind,
  ImageModeration,
  ImageRejectReason,
  TextModeration,
} from './types';

export type * from './types';
export { setModerationModelForTests, type ModerationModel } from './model';
export {
  moderationFixtureJpeg,
  TEXT_FIXTURE,
  withJpegComment,
  type ImageFixtureFlag,
} from './fake';

/** How long the after-the-fact review of a `pending` message may take. */
export const TEXT_REVIEW_TIMEOUT_MS = 15_000;

/** Moderation didn't answer in time or failed. A 503 `unavailable`, reason `moderation`. */
export class ModerationUnavailableError extends HttpError {
  constructor() {
    super(503, 'unavailable', 'Try again in a moment.', {
      reason: 'moderation',
      headers: { 'Retry-After': '2' },
    });
    this.name = 'ModerationUnavailableError';
  }
}

class DeadlineExceeded extends Error {
  override readonly name = 'DeadlineExceeded';
}

/** 422 `photo_rejected`. The contract's `reason` tells the app which retake copy to show. */
export function photoRejected(reason: ImageRejectReason): HttpError {
  return unprocessable('photo_rejected', REJECT_MESSAGES[reason], { reason });
}

/** 422 `message_rejected`, for a flagged chat message. */
export function messageRejected(): HttpError {
  return unprocessable('message_rejected', 'This message cannot be sent.');
}

/** A 503 for when the caller decides moderation is unavailable itself. */
export function moderationUnavailable(): ModerationUnavailableError {
  return new ModerationUnavailableError();
}

const REJECT_MESSAGES: Record<ImageRejectReason, string> = {
  face_visible: 'A face is visible.',
  nudity: 'The photo is not allowed.',
  no_outfit: 'The outfit is not visible.',
  no_person: 'Nobody is in the photo.',
  possibly_minor: 'The photo is not allowed.',
  unreadable: 'The photo could not be read.',
};

/**
 * The rules, from what the model saw. Pure, so the tests cover every combination.
 *
 * Card photos (outfit cards, faces blurred on the phone): reject nudity, a visible face,
 * someone who may be under 18, no person, or no visible outfit, in that order of reason.
 *
 * Profile photos (shown only after a mutual match, faces expected): reject nudity and
 * photos with nobody in them; hold someone who may be under 18 for human review.
 */
export function decideImage(kind: ImageKind, f: ImageFindings): ImageModeration {
  if (f.nudity) return { decision: 'rejected', reason: 'nudity', findings: f };
  if (kind === 'card') {
    if (f.faceVisible) return { decision: 'rejected', reason: 'face_visible', findings: f };
    if (f.possiblyUnder18) return { decision: 'rejected', reason: 'possibly_minor', findings: f };
    if (!f.personPresent) return { decision: 'rejected', reason: 'no_person', findings: f };
    if (!f.outfitVisible) return { decision: 'rejected', reason: 'no_outfit', findings: f };
    return { decision: 'approved', findings: f };
  }
  if (!f.personPresent) return { decision: 'rejected', reason: 'no_person', findings: f };
  if (f.possiblyUnder18) return { decision: 'held', reason: 'possibly_minor', findings: f };
  return { decision: 'approved', findings: f };
}

/** Runs `work` with an AbortSignal that fires at the deadline, and stops waiting then. */
async function withDeadline<T>(ms: number, work: (signal: AbortSignal) => Promise<T>): Promise<T> {
  const controller = new AbortController();
  let timer: ReturnType<typeof setTimeout> | undefined;
  const deadline = new Promise<never>((_, reject) => {
    timer = setTimeout(
      () => {
        const error = new DeadlineExceeded();
        controller.abort(error);
        reject(error);
      },
      Math.max(0, ms),
    );
  });
  try {
    return await Promise.race([work(controller.signal), deadline]);
  } finally {
    clearTimeout(timer);
  }
}

const errorClass = (error: unknown) => (error instanceof Error ? error.name : typeof error);

/**
 * Checks one photo. Resolves with a verdict, or throws `ModerationUnavailableError` when
 * moderation can't answer within MODERATION_TIMEOUT (the caller fails closed).
 * `bytes` is the JPEG as uploaded; it's downscaled to at most 768 px before it's sent.
 */
export async function moderateImage(kind: ImageKind, bytes: Uint8Array): Promise<ImageModeration> {
  const started = performance.now();
  const model = activeModel();
  const done = (verdict: ImageModeration): ImageModeration => {
    logger.info('moderation.image', {
      kind,
      decision: verdict.decision,
      reason: verdict.decision === 'approved' ? undefined : verdict.reason,
      model: model.name,
      ms: Math.round(performance.now() - started),
    });
    return verdict;
  };

  try {
    return await withDeadline(MODERATION_TIMEOUT_MS, async (signal) => {
      const jpeg = await prepareImage(bytes, PHOTO_MAX_DIMENSION_PX);
      if (!jpeg) return done({ decision: 'rejected', reason: 'unreadable' });
      const findings = await model.classifyImage({ kind, original: bytes, jpeg, signal });
      return done(decideImage(kind, findings));
    });
  } catch (error) {
    if (error instanceof ModelRefusal) return done({ decision: 'rejected', reason: 'unreadable' });
    logger.warn('moderation.unavailable', {
      kind,
      model: model.name,
      cause: errorClass(error),
      ms: Math.round(performance.now() - started),
    });
    throw new ModerationUnavailableError();
  }
}

/**
 * Checks one chat message within MODERATION_TIMEOUT. Never throws: if moderation is slow
 * or down, the message goes through as `pending` and is reviewed afterwards.
 */
export async function moderateText(body: string): Promise<TextModeration> {
  return checkText(body, MODERATION_TIMEOUT_MS);
}

/**
 * The after-the-fact review of a `pending` message, with a longer timeout. Resolves
 * `passed` or `flagged`, or `pending` if moderation is still unavailable (try again later).
 */
export async function reviewText(body: string): Promise<TextModeration> {
  return checkText(body, TEXT_REVIEW_TIMEOUT_MS);
}

async function checkText(body: string, timeoutMs: number): Promise<TextModeration> {
  const started = performance.now();
  const model = activeModel();
  let verdict: TextModeration;
  let cause: string | undefined;
  try {
    const findings = await withDeadline(timeoutMs, (signal) =>
      model.classifyText({ body, signal }),
    );
    verdict =
      findings.flagged && findings.category !== 'none'
        ? { decision: 'flagged', category: findings.category }
        : { decision: 'passed' };
  } catch (error) {
    if (error instanceof ModelRefusal) {
      verdict = { decision: 'flagged', category: 'other' };
    } else {
      verdict = { decision: 'pending' };
      cause = errorClass(error);
    }
  }
  logger.info('moderation.text', {
    decision: verdict.decision,
    category: verdict.decision === 'flagged' ? verdict.category : undefined,
    model: model.name,
    cause,
    ms: Math.round(performance.now() - started),
  });
  return verdict;
}
