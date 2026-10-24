/**
 * A thin stand-in for C3's `startGlow` (server/src/server/glow), with the signature agreed in
 * docs/HANDOFFS.md (For C3). Owner: C2, until C3's lands; then `set-choice.ts` imports C3's
 * and this file goes.
 *
 * It calls `start_glow` and sends every event the result implies (docs/CONTRACTS.md,
 * "start_glow results" and "Settled timeouts"). The word list is a short placeholder: C3 owns
 * the real one in `server/src/server/glow/words.ts`.
 */
import type { Db } from './db';
import { send, settledEvents, type Outgoing } from './events';
import { startGlowRow } from './rpc';

export type StartGlowOutcome =
  | { readonly result: 'started' }
  | {
      readonly result: 'chat';
      readonly reason: 'not_checked_in' | 'no_code_word' | 'already_decided';
    }
  | { readonly result: 'waiting'; readonly reason: 'location_stale' | 'not_both_find' };

/** Placeholder code words: short, friendly, hard to mishear. C3 replaces them. */
export const STAND_IN_CODE_WORDS = [
  'maple', 'otter', 'comet', 'pebble', 'lantern', 'meadow', 'harbor', 'cactus',
  'violin', 'falcon', 'walnut', 'canyon', 'tulip', 'glacier', 'pepper', 'island',
  'rocket', 'willow', 'banjo', 'marble', 'ginger', 'kettle', 'puffin', 'quartz',
] as const; // prettier-ignore

/**
 * Starts the glow, or opens the chat, or says why it waits. Never throws for a match it
 * can't start; throws 404 when the match doesn't exist or has ended.
 */
export async function startGlow(db: Db, matchId: string): Promise<StartGlowOutcome> {
  const row = await startGlowRow(db, matchId, STAND_IN_CODE_WORDS);
  const outgoing: Outgoing[] = settledEvents(row.settled);
  switch (row.result) {
    case 'started':
      outgoing.push({ to: row.glow.userIds, event: { type: 'glow.started', matchId } });
      await send(outgoing);
      return { result: 'started' };
    case 'chat':
      // The match is chatting now (or already was): both apps open the chat.
      outgoing.push({ to: row.userIds, event: { type: 'match.choice', matchId } });
      await send(outgoing);
      return { result: 'chat', reason: row.reason };
    case 'waiting':
      if (row.reason === 'location_stale') {
        outgoing.push({ to: row.staleUserIds ?? [], event: { type: 'match.recheck', matchId } });
      }
      await send(outgoing);
      return { result: 'waiting', reason: row.reason };
  }
}
