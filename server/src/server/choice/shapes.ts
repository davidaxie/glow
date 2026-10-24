/**
 * What C2's database functions return, parsed, and what the app may see of it. Owner: C2.
 *
 * `get_match` and `set_choice` return the contract's MatchDetail plus server-only fields
 * (`userIds`, `settled`, `recheckUserIds`, and `matchId`, `roomId` and `userIds` inside the
 * glow). Those are for `notify()` and must never reach an app (P1, D20). The route helper
 * already drops undeclared fields, but `publicMatch` rebuilds the reply from the contract's
 * fields by name anyway, so nothing depends on that alone.
 */
import { z } from 'zod';
import {
  zChoiceNext,
  zChoiceReason,
  zGlow,
  zMatchDetail,
  type Glow,
  type MatchDetail,
} from '@/contracts';

/** A timeout a function applied on the spot. The route that called it sends the events. */
export const zSettled = z.object({
  matchId: z.uuid(),
  kind: z.enum(['choice_timeout', 'glow_expired']),
  userIds: z.array(z.uuid()),
});
export type Settled = z.output<typeof zSettled>;

const zPair = z.array(z.uuid()).length(2);

/** `get_match`: MatchDetail plus both people's IDs and what it settled. */
export const zDbMatch = zMatchDetail.extend({
  userIds: zPair,
  settled: z.array(zSettled).default([]),
});
export type DbMatch = z.output<typeof zDbMatch>;

/** `set_choice`: what happens next, the match, what it settled, and who needs a recheck. */
export const zDbChoice = z.object({
  next: zChoiceNext,
  reason: zChoiceReason,
  match: zMatchDetail.extend({ userIds: zPair }),
  settled: z.array(zSettled).default([]),
  recheckUserIds: z.array(z.uuid()).optional(),
});
export type DbChoice = z.output<typeof zDbChoice>;

/** A database result that doesn't match what the function promises. Becomes a 500. */
export class UnexpectedResult extends Error {
  override readonly name = 'UnexpectedResult';
}

/** Parses a database result. On failure, says which fields broke, never their values. */
export function parseResult<S extends z.ZodType>(schema: S, value: unknown, what: string) {
  const parsed = schema.safeParse(value);
  if (!parsed.success) {
    const paths = parsed.error.issues.map((i) => i.path.join('.') || '(root)').join(',');
    throw new UnexpectedResult(`${what} returned an unexpected shape at ${paths}`);
  }
  return parsed.data as z.output<S>;
}

/** The glow as the app may see it: the contract's fields, by name. */
export function publicGlow(glow: Glow): Glow {
  return {
    id: glow.id,
    status: glow.status,
    color: glow.color,
    codeWord: glow.codeWord,
    ...(glow.meetingSpot
      ? { meetingSpot: { id: glow.meetingSpot.id, name: glow.meetingSpot.name } }
      : {}),
    startedAt: glow.startedAt,
    endsAt: glow.endsAt,
    ...(glow.endedAt ? { endedAt: glow.endedAt } : {}),
    youMet: glow.youMet,
    theyMet: glow.theyMet,
  };
}

/** The match as the app may see it: the contract's fields, by name. No user IDs (P1, D20). */
export function publicMatch(match: MatchDetail): MatchDetail {
  return {
    id: match.id,
    status: match.status,
    firstName: match.firstName,
    photoCount: match.photoCount,
    roomId: match.roomId,
    roomName: match.roomName,
    createdAt: match.createdAt,
    choiceDeadline: match.choiceDeadline,
    ...(match.yourChoice ? { yourChoice: match.yourChoice } : {}),
    otherHasChosen: match.otherHasChosen,
    ...(match.glow ? { glow: publicGlow(match.glow) } : {}),
  };
}
