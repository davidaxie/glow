/**
 * Owner: C4. Who may read or write a thread, decided by the database.
 *
 * `get_match` answers not_found unless the person is in the match and it hasn't ended
 * (unmatched, blocked, or an account deleted), so a stranger, a blocked person and an
 * unmatched person all get the same 404 (P11). It also applies the lazy timeouts first, so a
 * choice window that ran out opens the chat here rather than waiting for the purge cron.
 *
 * Every chat route calls this before anything else. In particular a message is only sent to
 * moderation once we know the sender may write in this thread, so a blocked person's text is
 * never even read.
 */
import { z } from 'zod';
import { logger } from '@/server/log';
import { announceSettled } from './announce';
import { chatNotOpen, DatabaseError, rpc } from './db';

const MatchState = z.looseObject({
  id: z.string(),
  status: z.enum(['choosing', 'glowing', 'chatting', 'met']),
  settled: z
    .array(z.looseObject({ matchId: z.string(), kind: z.string(), userIds: z.array(z.string()) }))
    .optional(),
});

export type ThreadState = 'glowing' | 'chatting' | 'met';

/**
 * Resolves when `userId` may use the thread of `matchId` now. Throws 404 (not theirs, or
 * ended) or 409 `chat_not_open` (still choosing), and tells both people about any timeout it
 * applied on the way.
 */
export async function openThread(userId: string, matchId: string): Promise<ThreadState> {
  const raw = await rpc('get_match', { p_user_id: userId, p_match_id: matchId });
  const parsed = MatchState.safeParse(raw);
  if (!parsed.success || parsed.data.id.toLowerCase() !== matchId.toLowerCase()) {
    logger.error('chat.unexpected_match_shape', {});
    throw new DatabaseError('get_match returned an unexpected shape');
  }
  await announceSettled(parsed.data.settled);
  const { status } = parsed.data;
  if (status === 'choosing') throw chatNotOpen();
  return status;
}
