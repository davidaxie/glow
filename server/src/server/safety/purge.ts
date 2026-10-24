/**
 * Owner: B8. `GET /api/cron/purge`, every PURGE_INTERVAL (5 minutes), with the cron secret.
 *
 * 1. `purge_expired()` ends timed-out glows and choice windows, flags check-ins that end
 *    within CHECKIN_EXPIRY_WARNING (once each), and deletes expired and left check-ins, old
 *    taps, ended glows, old card views, location checks and room days.
 * 2. Deletes the card photos of the check-ins it deleted, then sweeps both buckets for any
 *    photo whose row is gone. So a card photo is gone at most one interval after its card
 *    expires, plus one more if storage failed the first time: well inside P9's 10 minutes.
 * 3. Notifies: `checkin.expiring` to each person whose card ends soon, `glow.ended` and
 *    `match.choice` to both people in each timed-out glow or choice, and `deck.changed` to
 *    each room that lost a card.
 * 4. Reviews chat messages that went through as `pending` (D71).
 * 5. Deletes Supabase Auth audit entries older than AUTH_AUDIT_RETENTION.
 *
 * Safe to call from any scheduler, as often as it likes, and twice at once: the database
 * work is one transaction, each warning is sent once (`expiry_warned_at`), and deleting a
 * photo that's already gone is a no-op.
 */
import { z } from 'zod';
import type { PurgeResult } from '@/contracts';
import { logger } from '@/server/log';
import { reviewPendingMessages } from '@/server/moderation/review-pending';
import { announceRooms } from './announce';
import { DatabaseError, rpc } from './db';
import { notify } from './dependencies';
import { removeObjects, sweepOrphans } from './storage';

const Pair = z.looseObject({ matchId: z.string(), userIds: z.array(z.string()) });

const PurgeOutput = z.looseObject({
  cardPaths: z.array(z.string()),
  expiringCheckins: z.array(z.looseObject({ userId: z.string(), roomId: z.string() })),
  endedGlows: z.array(Pair),
  choiceTimeouts: z.array(Pair),
  deleted: z.looseObject({ checkins: z.number(), taps: z.number() }),
});

/**
 * Supabase Auth's own audit log (sign-ins, with email and IP) is kept this long, then
 * deleted. Long enough to look into an abuse report, short enough not to pile up (D74).
 */
export const AUTH_AUDIT_RETENTION = '7 days';

/** `{roomId}/{cardId}.jpg` → roomId. */
const roomOf = (path: string) => path.split('/')[0] ?? '';

export async function runPurgeJob(): Promise<PurgeResult> {
  const started = performance.now();
  const parsed = PurgeOutput.safeParse(await rpc('purge_expired', {}));
  if (!parsed.success) throw new DatabaseError('purge_expired returned an unexpected shape');
  const out = parsed.data;

  const cardPhotosDeleted = await removeObjects('room-cards', out.cardPaths);
  const orphans = await sweepOrphans();

  await Promise.all([
    ...out.expiringCheckins.map((c) =>
      notify(c.userId, { type: 'checkin.expiring', roomId: c.roomId }),
    ),
    ...out.endedGlows.map((g) => notify(g.userIds, { type: 'glow.ended', matchId: g.matchId })),
    ...out.choiceTimeouts.map((t) =>
      notify(t.userIds, { type: 'match.choice', matchId: t.matchId }),
    ),
    ...announceRooms(out.cardPaths.map(roomOf).filter(Boolean)),
  ]);

  let review = { reviewed: 0, flagged: 0 };
  try {
    review = await reviewPendingMessages();
  } catch {
    logger.error('safety.purge_review_failed', {});
  }

  let auditEntries = 0;
  try {
    auditEntries = await rpc('purge_auth_audit', { p_older_than: AUTH_AUDIT_RETENTION });
  } catch {
    logger.error('safety.purge_audit_failed', {});
  }

  const result: PurgeResult = {
    checkinsDeleted: out.deleted.checkins,
    cardPhotosDeleted: cardPhotosDeleted + orphans.cardPhotos,
    tapsDeleted: out.deleted.taps,
    glowsEnded: out.endedGlows.length,
    choicesTimedOut: out.choiceTimeouts.length,
    expiringNotified: out.expiringCheckins.length,
  };
  logger.info('safety.purge', {
    ...result,
    profilePhotosSwept: orphans.profilePhotos,
    authAuditPurged: auditEntries,
    messagesReviewed: review.reviewed,
    messagesFlagged: review.flagged,
    ms: Math.round(performance.now() - started),
  });
  return result;
}
