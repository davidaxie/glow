/**
 * Owner: C3. Starting a glow, for C2's `setChoice` (the signature agreed in docs/HANDOFFS.md).
 *
 *   const outcome = await startGlow(db, matchId);   // after set_choice said next: glow
 *
 * `start_glow` (migration 0002) picks a color, one of the 300 code words and the least-used meeting
 * spot, so that no other active glow in the room has the same color and word, and starts the glow.
 * It never raises for a match it can't start: it opens the chat, or says whose location check is
 * too old. This function sends every event its result implies (CONTRACTS.md, "start_glow
 * results" and "Settled timeouts"):
 *
 * | result               | sent                                       |
 * | -------------------- | ------------------------------------------ |
 * | started              | glow.started to both (the time-sensitive push) |
 * | chat                 | match.choice to both, so both apps open the chat |
 * | waiting, location_stale | match.recheck to each person whose check is stale |
 * | waiting, not_both_find  | nothing                                 |
 * | every result         | glow.ended or match.choice for each `settled` entry, including other pairs' glows in the room |
 */
import { logger } from '@/server/log';
import { rpc, type GlowDb } from './db';
import { announce, settledAnnouncements, type Announcement } from './events';
import { parseResult, zStartGlowResult } from './results';
import { CODE_WORDS } from './words';

export type StartGlowOutcome =
  | { readonly result: 'started' }
  | {
      readonly result: 'chat';
      readonly reason: 'not_checked_in' | 'no_code_word' | 'already_decided';
    }
  | { readonly result: 'waiting'; readonly reason: 'location_stale' | 'not_both_find' };

/**
 * Calls start_glow with the word list, sends every event its result implies, and never throws for
 * a match it can't start. Throws HttpError 404 for not_found (the match ended or doesn't exist),
 * and 503 when the database can't be reached.
 */
export async function startGlow(db: GlowDb, matchId: string): Promise<StartGlowOutcome> {
  const data = await rpc(db, 'start_glow', {
    p_match_id: matchId,
    p_code_words: [...CODE_WORDS],
  });
  const result = parseResult('start_glow', zStartGlowResult, data);
  const announcements: Announcement[] = settledAnnouncements(result.settled);
  let outcome: StartGlowOutcome;

  switch (result.result) {
    case 'started':
      announcements.push({
        userIds: result.glow.userIds,
        event: { type: 'glow.started', matchId: result.glow.matchId },
      });
      outcome = { result: 'started' };
      break;
    case 'chat':
      announcements.push({
        userIds: result.userIds,
        event: { type: 'match.choice', matchId: result.matchId },
      });
      outcome = { result: 'chat', reason: result.reason };
      break;
    case 'waiting':
      if (result.reason === 'location_stale' && result.staleUserIds?.length) {
        announcements.push({
          userIds: result.staleUserIds,
          event: { type: 'match.recheck', matchId: result.matchId },
        });
      }
      outcome = { result: 'waiting', reason: result.reason };
      break;
  }

  logger.info('glow.start', {
    result: outcome.result,
    reason: 'reason' in outcome ? outcome.reason : null,
    settled: result.settled.length,
  });
  await announce(announcements);
  return outcome;
}
