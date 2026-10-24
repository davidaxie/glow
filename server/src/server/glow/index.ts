/**
 * Owner: C3. Glow mode on the server.
 *
 *   import { startGlow } from '@/server/glow';            // C2's setChoice
 *   const outcome = await startGlow(db, matchId);
 *
 * The routes under `/api/matches/{id}/glow` use the handlers. See `start-glow.ts` for which events
 * each result sends, and `words.ts` for the code words.
 */
export { startGlow, type StartGlowOutcome } from './start-glow';
export { cancelGlowFor, getGlowFor, markGlowMetFor } from './handlers';
export { CODE_WORDS, type CodeWord } from './words';
