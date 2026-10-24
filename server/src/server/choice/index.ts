// Owner: C2. The mutual moment and the Find or Chat choice: GET /api/matches/{id} and
// POST /api/matches/{id}/choice.
//
// For other agents:
// - C3: `setChoice` calls your `startGlow(db, matchId)` when both chose Find. Until it
//   merges, `./glow-start` stands in with the same signature (docs/HANDOFFS.md, For C3).
// - Anyone who needs a match from one person's side and its timeouts' events sent:
//   `loadMatch(db, userId, matchId)`.
export { getMatchFor, loadMatch } from './get-match';
export { setChoiceFor } from './set-choice';
