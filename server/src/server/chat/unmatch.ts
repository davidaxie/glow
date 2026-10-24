/**
 * Owner: C4. `POST /api/matches/{id}/unmatch`.
 *
 * `unmatch` ends the match for both people and deletes the whole thread in one transaction,
 * so neither can read or send from then on (every chat route answers 404, the same as for a
 * match that never existed, P11). Then exactly what a block sends goes out: match.ended to both
 * people and deck.changed to the rooms either is checked into, so neither phone can tell an
 * unmatch from a block (D18, B8-D6).
 *
 * Anyone not in the match, or a match that already ended, gets 404: unmatching twice is not
 * a way to learn whether the other person got there first.
 */
import { z } from 'zod';
import type { RouteHandler } from '@/server/http';
import { logger } from '@/server/log';
import { announceEnded } from './announce';
import { DatabaseError, rpc } from './db';

const Unmatched = z.looseObject({ matchId: z.string(), userIds: z.array(z.string()) });

export async function unmatchFor(userId: string, matchId: string): Promise<void> {
  const parsed = Unmatched.safeParse(
    await rpc('unmatch', { p_user_id: userId, p_match_id: matchId }),
  );
  if (!parsed.success) throw new DatabaseError('unmatch returned an unexpected shape');
  logger.info('chat.unmatched', {});
  await announceEnded(parsed.data.userIds, matchId);
}

export const unmatchRoute: RouteHandler<'unmatch'> = async ({ user, params }) => {
  await unmatchFor(user.id, params.id.toLowerCase());
  return { status: 204 };
};
