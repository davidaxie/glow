/**
 * Owner: C3. What the glow database functions return (docs/CONTRACTS.md and migrations 0001 and
 * 0002), checked with zod before anything is sent anywhere.
 *
 * These shapes are server only: `userIds`, `staleUserIds` and `settled` say who to notify and must
 * never reach an app (P1). Replies are built field by field with `toGlowReply`, so only the
 * contract's Glow fields ever leave, even before the route helper strips the rest.
 */
import { z } from 'zod';
import { zGlow, type Glow } from '@/contracts';

const userIds = z.array(z.uuid()).min(1);

/** A timeout a function applied on the spot. The route that called it sends the events. */
export const zSettled = z.array(
  z.object({
    matchId: z.uuid(),
    kind: z.string(),
    userIds,
  }),
);
export type Settled = z.infer<typeof zSettled>;

/** `private.glow_json`: the contract's Glow plus the match, the room and both people. */
export const zGlowRow = zGlow.extend({
  matchId: z.uuid(),
  roomId: z.uuid(),
  userIds,
});
export type GlowRow = z.infer<typeof zGlowRow>;

/** `start_glow`, from migration 0002 (CONTRACTS.md, "start_glow results"). */
export const zStartGlowResult = z.discriminatedUnion('result', [
  z.object({ result: z.literal('started'), glow: zGlowRow, settled: zSettled }),
  z.object({
    result: z.literal('chat'),
    reason: z.enum(['not_checked_in', 'no_code_word', 'already_decided']),
    matchId: z.uuid(),
    userIds,
    settled: zSettled,
  }),
  z.object({
    result: z.literal('waiting'),
    reason: z.enum(['location_stale', 'not_both_find']),
    matchId: z.uuid(),
    userIds,
    staleUserIds: z.array(z.uuid()).optional(),
    settled: zSettled,
  }),
]);
export type StartGlowResult = z.infer<typeof zStartGlowResult>;

/** `glow_met`: Glow from that person's side, plus what it settled. */
export const zGlowMetResult = zGlowRow.extend({ settled: zSettled });

/** `cancel_glow`: Glow from that person's side. */
export const zCancelGlowResult = zGlowRow;

/** The parts of `get_match` a glow route needs: the latest glow, from my side, and what settled. */
export const zMatchGlowResult = z.object({
  glow: zGlowRow.optional(),
  settled: zSettled.default([]),
});

/** The reply: exactly the contract's Glow fields, nothing else (P1). */
export function toGlowReply(row: GlowRow): Glow {
  return {
    id: row.id,
    status: row.status,
    color: row.color,
    codeWord: row.codeWord,
    ...(row.meetingSpot
      ? { meetingSpot: { id: row.meetingSpot.id, name: row.meetingSpot.name } }
      : {}),
    startedAt: row.startedAt,
    endsAt: row.endsAt,
    ...(row.endedAt ? { endedAt: row.endedAt } : {}),
    youMet: row.youMet,
    theyMet: row.theyMet,
  };
}

/** Parses a database result, or fails as a 500 that names only the function (never the data). */
export function parseResult<S extends z.ZodType>(
  fn: string,
  schema: S,
  data: unknown,
): z.output<S> {
  const parsed = schema.safeParse(data);
  if (!parsed.success) {
    throw new UnexpectedResult(
      `${fn} returned an unexpected shape at ${parsed.error.issues
        .map((issue) => issue.path.join('.') || '(root)')
        .join(',')}`,
    );
  }
  return parsed.data;
}

export class UnexpectedResult extends Error {
  override readonly name = 'UnexpectedResult';
}
