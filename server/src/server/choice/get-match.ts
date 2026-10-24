/**
 * GET /api/matches/{id} (getMatch). Owner: C2.
 *
 * One match from the caller's side: the other person's first name and photo count, the
 * choice window, and the glow if there is one. `get_match` applies any timeout first and
 * reports it in `settled`; this route sends those events, because purge won't.
 *
 * 404 when the match doesn't exist, isn't the caller's, or has ended (P11). The reply is
 * rebuilt from the contract's fields, so no user ID ever leaves (P1, D20).
 */
import type { MatchDetail } from '@/contracts';
import type { RouteHandler } from '@/server/http';
import { serviceDb, type Db } from './db';
import { send, settledEvents } from './events';
import { getMatchRow } from './rpc';
import { publicMatch } from './shapes';

/** The match as the caller may see it, after sending the events for any timeout it applied. */
export async function loadMatch(db: Db, userId: string, matchId: string): Promise<MatchDetail> {
  const row = await getMatchRow(db, userId, matchId);
  await send(settledEvents(row.settled));
  return publicMatch(row);
}

export const getMatchFor: RouteHandler<'getMatch'> = async ({ user, params }) => {
  const match = await loadMatch(serviceDb(), user.id, params.id);
  return { status: 200, body: match };
};
