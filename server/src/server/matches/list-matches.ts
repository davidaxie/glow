/**
 * Owner: B4. `GET /api/matches` (listMatches).
 *
 * My matches that haven't ended, newest first. `list_matches` applies any timeouts first
 * (a choice window or a glow that ran out), and from migration 0002 says which ones it
 * applied, so both people hear about them.
 *
 * Each entry has the other person's first name, which only ever leaves the server once a
 * match exists (P1), and never a user ID (D20). "Now" in the app is `choosing` and
 * `glowing`; "Earlier" is `chatting` and `met`. Ended matches never appear.
 */
import type { MatchList, MatchStatus, MatchSummary } from '@/contracts';
import { rpc } from '@/server/deck/db';
import type { RouteHandler } from '@/server/http';
import { logger } from '@/server/log';
import { notifySettled } from '@/server/deck/dependencies';
import { afterResponse } from './announce';

/** What `list_matches` returns per match: MatchDetail plus server-only fields. */
type DbMatch = {
  readonly id: string;
  readonly status: MatchStatus | 'ended';
  readonly firstName?: string | null;
  readonly roomName: string;
  readonly createdAt: string;
  readonly choiceDeadline: string;
  readonly lastMessageAt?: string | null;
};

type DbMatchList = {
  readonly matches: readonly DbMatch[];
  /** Timeouts it applied, `[{ matchId, kind, userIds }]` (CONTRACTS.md, "Settled timeouts"). */
  readonly settled?: readonly unknown[] | null;
};

const LISTED: ReadonlySet<string> = new Set<MatchStatus>([
  'choosing',
  'glowing',
  'chatting',
  'met',
]);

/** Exactly the MatchSummary fields. userIds, photoCount, glow and the rest stay behind. */
export function toSummary(match: DbMatch): MatchSummary | null {
  if (!LISTED.has(match.status) || !match.firstName) return null;
  return {
    id: match.id,
    status: match.status as MatchStatus,
    firstName: match.firstName,
    roomName: match.roomName,
    createdAt: match.createdAt,
    choiceDeadline: match.choiceDeadline,
    ...(match.lastMessageAt ? { lastMessageAt: match.lastMessageAt } : {}),
  };
}

export async function listMatches(userId: string): Promise<MatchList> {
  const raw = (await rpc('list_matches', { p_user_id: userId })) as unknown as DbMatchList;
  // match.choice or glow.ended to both people, after the response (B5's notifySettled).
  const settled = raw.settled;
  if (settled && settled.length > 0) {
    await afterResponse(async () => {
      await notifySettled(settled);
    });
  }
  const matches: MatchSummary[] = [];
  for (const match of raw.matches) {
    const summary = toSummary(match);
    if (summary) matches.push(summary);
    // Can't happen while profiles_complete_has_fields holds; skipped rather than failing the list.
    else logger.warn('matches.skipped', { status: match.status });
  }
  return { matches };
}

export const listMatchesRoute: RouteHandler<'listMatches'> = async ({ user }) => ({
  status: 200,
  body: await listMatches(user.id),
});
