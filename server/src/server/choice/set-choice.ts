/**
 * POST /api/matches/{id}/choice (setChoice). Owner: C2.
 *
 * Find (with a fresh location fix) or Chat. Find only happens if both pick it before the
 * deadline, both are still checked in, and both passed a location check in the last
 * GEO_FRESHNESS_FOR_GLOW. Anything else opens the chat.
 *
 * Who hears what (docs/CONTRACTS.md and events.json), all `{ type, matchId }` only:
 *
 * | set_choice says                          | Sent                                        |
 * | ---------------------------------------- | ------------------------------------------- |
 * | waiting, other_undecided                 | match.choice to the other person            |
 * | waiting, other_location_stale            | match.recheck to `recheckUserIds`           |
 * | chat, chose_chat or not_checked_in       | match.choice to both (choosing ended)       |
 * | chat, timeout                            | match.choice to both, from `settled`        |
 * | glow or chat, already_decided            | nothing (nothing changed)                   |
 * | glow, both_find                          | startGlow, which sends its own events       |
 *
 * plus the events for every other entry in `settled`.
 */
import type { ChoiceReason, ChoiceResult, MatchDetail } from '@/contracts';
import type { RouteHandler } from '@/server/http';
import { serviceDb } from './db';
import { rateLimit } from './deps';
import { send, settledEvents, type Outgoing } from './events';
import { checkFindLocation } from './find-check';
import { loadMatch } from './get-match';
import { startGlow, type StartGlowOutcome } from './glow-start';
import { setChoiceRow } from './rpc';
import { publicMatch, type DbChoice } from './shapes';

/** The events `set_choice`'s own answer implies (not `start_glow`'s, which C3's sends). */
export function choiceEvents(userId: string, matchId: string, row: DbChoice): Outgoing[] {
  const both = row.match.userIds;
  const others = both.filter((id) => id.toLowerCase() !== userId.toLowerCase());
  const outgoing = settledEvents(row.settled);
  if (row.next === 'waiting' && row.reason === 'other_undecided') {
    outgoing.push({ to: others, event: { type: 'match.choice', matchId } });
  } else if (row.next === 'waiting' && row.reason === 'other_location_stale') {
    outgoing.push({ to: row.recheckUserIds ?? others, event: { type: 'match.recheck', matchId } });
  } else if (
    row.next === 'chat' &&
    (row.reason === 'chose_chat' || row.reason === 'not_checked_in')
  ) {
    outgoing.push({ to: both, event: { type: 'match.choice', matchId } });
  }
  return outgoing;
}

/** What the app hears after `startGlow`, given what it did. */
export function afterGlow(outcome: StartGlowOutcome, match: MatchDetail): ChoiceResult {
  switch (outcome.result) {
    case 'started':
      return { next: 'glow', reason: 'both_find', match };
    case 'chat': {
      // Both chose Find, but the chat opened: someone left, or no code word was free. The
      // contract has no reason for "no free code word", and both_find is what happened (C2-D3).
      const reason: ChoiceReason =
        outcome.reason === 'not_checked_in'
          ? 'not_checked_in'
          : outcome.reason === 'already_decided'
            ? 'already_decided'
            : 'both_find';
      return { next: 'chat', reason, match };
    }
    case 'waiting':
      // A check went stale between set_choice and start_glow; startGlow asked for a recheck.
      return {
        next: 'waiting',
        reason: outcome.reason === 'location_stale' ? 'other_location_stale' : 'other_undecided',
        match,
      };
  }
}

export const setChoiceFor: RouteHandler<'setChoice'> = async ({ user, params, body }) => {
  const db = serviceDb();
  const matchId = params.id;
  if (body.choice === 'find') {
    // The route helper already counted this request against `api`. Find also runs a location
    // check, so it counts against `join` too, like joining a room (C2-D5).
    await rateLimit(user.id, 'join');
    await checkFindLocation(db, user.id, matchId, body.location);
  }

  const row = await setChoiceRow(db, user.id, matchId, body.choice);
  await send(choiceEvents(user.id, matchId, row));

  if (row.next === 'glow' && row.reason === 'both_find') {
    const outcome = await startGlow(db, matchId);
    const match = await loadMatch(db, user.id, matchId);
    return { status: 200, body: afterGlow(outcome, match) };
  }
  return {
    status: 200,
    body: { next: row.next, reason: row.reason, match: publicMatch(row.match) },
  };
};
