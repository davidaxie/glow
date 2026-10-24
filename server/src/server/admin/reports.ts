/**
 * The reports queue, and the three ways to resolve a report: dismiss it, remove the reported
 * person's card, or ban them.
 */
import type { AdminReport, ReportStatus } from '@/contracts';
import { badRequest, notFound } from '@/server/http';
import { logger } from '@/server/log';
import { CAPTURE_REVIEW_THRESHOLD, CAPTURE_REVIEW_WINDOW_SECONDS } from '@/server/safety/capture';
import { hideAndNotify } from './cards';
import { deps } from './context';
import type { ReportRecord } from './repo';
import { toAdminReport } from './views';

export type ReportAction = 'dismiss' | 'remove_card' | 'ban';

export async function listReports(status: ReportStatus = 'open'): Promise<AdminReport[]> {
  return (await deps().repo.listReports(status)).map(toAdminReport);
}

/**
 * Bans a person, most protective step first, so a failure part way still leaves them
 * hidden. Every step is safe to run again.
 *
 * 1. `profiles.banned_at`: out of every deck at once, and no new check-ins (D31).
 * 2. The auth user is banned: every token they hold stops working (D3).
 * 3. Their open check-ins end, cards are hidden and photos deleted; their rooms refetch.
 * 4. Their matches end for both people (match.ended). Report evidence was already kept (D23).
 * 5. Every other open report about them is closed as actioned.
 */
export async function banPerson(userId: string, adminId: string): Promise<void> {
  const { repo, events } = deps();
  if (userId === adminId) throw badRequest("You can't ban yourself.");
  if (!(await repo.markBanned(userId))) throw notFound();
  await repo.banAuthUser(userId);

  const cards = await repo.openCardsOf(userId);
  await hideAndNotify(
    cards.map((c) => c.id),
    'person',
  );

  let ended = 0;
  for (const matchId of await repo.activeMatchIdsOf(userId)) {
    const result = await repo.unmatch(userId, matchId);
    if (result) {
      ended++;
      await events.matchEnded(matchId, result.userIds);
    }
  }

  await repo.setReportStatus(await repo.openReportIdsAbout(userId), 'actioned', adminId);
  logger.info('admin.person_banned', { userId, adminId, cards: cards.length, matches: ended });
}

async function removeReportedCards(report: ReportRecord): Promise<number> {
  const { repo } = deps();
  if (report.context === 'card') {
    const card = await repo.findCard(report.contextId);
    if (!card || card.userId !== report.reportedId || card.leftAt !== null) return 0;
    return (await hideAndNotify([card.id], 'card')).length;
  }
  // A match or chat report: the reported person's card in the room where it happened.
  if (!report.roomId) return 0;
  const cards = await repo.openCardsOf(report.reportedId, report.roomId);
  return (
    await hideAndNotify(
      cards.map((c) => c.id),
      'card',
    )
  ).length;
}

export async function resolveReport(
  id: string,
  action: ReportAction,
  adminId: string,
): Promise<AdminReport> {
  const { repo } = deps();
  const report = await repo.findReport(id);
  if (!report) throw notFound();

  if (action === 'dismiss') {
    await repo.setReportStatus([id], 'dismissed', adminId);
  } else if (action === 'remove_card') {
    const removed = await removeReportedCards(report);
    await repo.setReportStatus([id], 'actioned', adminId);
    logger.info('admin.report_card_removed', { reportId: id, adminId, removed });
  } else {
    await banPerson(report.reportedId, adminId);
    await repo.setReportStatus([id], 'actioned', adminId);
  }
  logger.info('admin.report_resolved', { reportId: id, adminId, action });

  const after = await repo.findReport(id);
  if (!after) throw notFound();
  return toAdminReport(after);
}

export type CaptureFlag = { readonly viewerCode: string; readonly count: number };

/**
 * People B8 flagged for review: CAPTURE_REVIEW_THRESHOLD or more screenshots or recordings
 * of the deck in CAPTURE_REVIEW_WINDOW (B8-D7). Named by watermark code only.
 */
export async function captureFlags(): Promise<CaptureFlag[]> {
  const { repo, now } = deps();
  const since = new Date(now() - CAPTURE_REVIEW_WINDOW_SECONDS * 1000).toISOString();
  const flags = await repo.captureFlags(since, CAPTURE_REVIEW_THRESHOLD);
  return flags.map((f) => ({ viewerCode: f.viewerCode, count: f.count }));
}

/** Bans a person named by their watermark code, so no user ID ever reaches the browser. */
export async function banByViewerCode(viewerCode: string, adminId: string): Promise<void> {
  if (!/^[A-HJ-NP-Z2-9]{8}$/.test(viewerCode)) throw notFound();
  const userId = await deps().repo.personByViewerCode(viewerCode);
  if (!userId) throw notFound();
  await banPerson(userId, adminId);
}
