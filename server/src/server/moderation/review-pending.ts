/**
 * Owner: B8. The after-the-fact review of chat messages that went through as `pending`
 * because moderation didn't answer within MODERATION_TIMEOUT (D71). The purge cron calls it
 * every PURGE_INTERVAL. A message that turns out bad is marked `flagged`; C4 hides flagged
 * messages from the recipient. Message text is never logged.
 */
import { logger } from '@/server/log';
import { dbError, serviceDb } from '@/server/safety/db';
import { reviewText } from './index';

/** Messages younger than this may still be in their first, live check. */
const SETTLE_SECONDS = 15;
const BATCH = 25;
const CONCURRENCY = 5;

export type ReviewResult = { readonly reviewed: number; readonly flagged: number };

export async function reviewPendingMessages(limit = BATCH): Promise<ReviewResult> {
  const db = serviceDb();
  const before = new Date(Date.now() - SETTLE_SECONDS * 1000).toISOString();
  const { data, error } = await db
    .from('messages')
    .select('id, body')
    .eq('moderation', 'pending')
    .lt('created_at', before)
    .order('created_at', { ascending: true })
    .limit(limit);
  if (error) throw dbError('review_pending', error);

  let reviewed = 0;
  let flagged = 0;
  const queue = [...(data ?? [])];
  const worker = async () => {
    for (let next = queue.shift(); next; next = queue.shift()) {
      const verdict = await reviewText(next.body);
      if (verdict.decision === 'pending') continue; // still down; next run tries again
      const moderation = verdict.decision === 'flagged' ? 'flagged' : 'passed';
      const update = await db
        .from('messages')
        .update({ moderation })
        .eq('id', next.id)
        .eq('moderation', 'pending');
      if (update.error) {
        logger.error('moderation.review_update_failed', { code: update.error.code ?? null });
        continue;
      }
      reviewed += 1;
      if (moderation === 'flagged') flagged += 1;
    }
  };
  await Promise.all(Array.from({ length: CONCURRENCY }, worker));
  if (reviewed > 0 || (data?.length ?? 0) > 0) {
    logger.info('moderation.review_pending', { found: data?.length ?? 0, reviewed, flagged });
  }
  return { reviewed, flagged };
}
