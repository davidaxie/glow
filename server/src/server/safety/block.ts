/**
 * Owner: B8. Block and report, from a card, match or chat ID. The app never sends a user
 * ID; the database works out the person (`block_user`, `create_report`), checks the caller
 * may act on that ID (a card the deck showed them, a match they're in), and answers
 * `not_found` otherwise (P11).
 *
 * A block applies both ways in every deck rule at once (P7), and ends any match and glow
 * between the two. A report also blocks, and keeps the reported person's last messages as
 * evidence first (D23).
 */
import { z } from 'zod';
import type { BlockRequest, ReportRequest } from '@/contracts';
import { logger } from '@/server/log';
import { announceEnded } from './announce';
import { DatabaseError, rpc } from './db';

const BlockResult = z.looseObject({
  endedMatchIds: z.array(z.string()),
  roomIds: z.array(z.string()),
});

function parseResult(fn: string, raw: unknown) {
  const parsed = BlockResult.safeParse(raw);
  if (!parsed.success) throw new DatabaseError(`${fn} returned an unexpected shape`);
  return parsed.data;
}

export async function blockFor(userId: string, request: BlockRequest): Promise<void> {
  const result = parseResult(
    'block_user',
    await rpc('block_user', {
      p_user_id: userId,
      p_context: request.context,
      p_context_id: request.contextId,
    }),
  );
  logger.info('safety.block', {
    context: request.context,
    endedMatches: result.endedMatchIds.length,
    rooms: result.roomIds.length,
  });
  await announceEnded(result);
}

export async function reportFor(userId: string, request: ReportRequest): Promise<void> {
  const details = request.details?.trim();
  const result = parseResult(
    'create_report',
    await rpc('create_report', {
      p_reporter_id: userId,
      p_context: request.context,
      p_context_id: request.contextId,
      p_reason: request.reason,
      ...(details ? { p_details: details } : {}),
    }),
  );
  logger.info('safety.report', {
    context: request.context,
    reason: request.reason,
    endedMatches: result.endedMatchIds.length,
    rooms: result.roomIds.length,
  });
  await announceEnded(result);
}
