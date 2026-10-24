/**
 * The events a choice or a refetch implies, and sending them. Owner: C2.
 *
 * Every event is only `{ type, matchId }` (P1, P6). Who gets it comes from the database
 * function's server-only `userIds`, never from the request.
 */
import { notify, type UserEvent } from './deps';

/** A `user:{id}` event about a match: only its type and the match ID. */
export type MatchUserEvent = Extract<UserEvent, { matchId: string }>;

export type Outgoing = { readonly to: readonly string[]; readonly event: MatchUserEvent };

/** Merges the list so each person gets each event once, grouped by event. */
export function merge(outgoing: readonly Outgoing[]): Outgoing[] {
  const groups = new Map<string, { event: MatchUserEvent; people: Set<string> }>();
  for (const { to, event } of outgoing) {
    const key = `${event.type}|${event.matchId.toLowerCase()}`;
    const group = groups.get(key) ?? { event, people: new Set<string>() };
    for (const id of to) group.people.add(id.toLowerCase());
    groups.set(key, group);
  }
  return [...groups.values()]
    .filter((group) => group.people.size > 0)
    .map(({ event, people }) => ({ to: [...people].sort(), event }));
}

/** Sends every event in the list, each person getting each event once, all at once. */
export async function send(outgoing: readonly Outgoing[]): Promise<void> {
  // notify never throws, so one failed send can't stop the others or fail the request.
  await Promise.all(merge(outgoing).map(({ to, event }) => notify(to, event)));
}
