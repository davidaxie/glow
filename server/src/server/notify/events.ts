/**
 * Which events go where, derived from contracts/events.json (through the generated
 * `eventCatalog`), so a contract change can't leave these types behind.
 */
import { eventCatalog, zGlowEvent, type GlowEvent, type GlowEventType } from '@/contracts';

type Catalog = typeof eventCatalog;

/** Event types sent to one person's private `user:{id}` channel. */
export type UserEventType = {
  [K in GlowEventType]: Catalog[K]['channel'] extends 'user' ? K : never;
}[GlowEventType];

/** Event types sent to everyone checked into a room, on `room:{id}`. */
export type RoomEventType = {
  [K in GlowEventType]: Catalog[K]['channel'] extends 'room' ? K : never;
}[GlowEventType];

/** An event for one person, for example `{ type: 'match.created', matchId }`. */
export type UserEvent = Extract<GlowEvent, { type: UserEventType }>;

/** An event for a whole room, for example `{ type: 'deck.changed', roomId }`. */
export type RoomEvent = Extract<GlowEvent, { type: RoomEventType }>;

/**
 * Parses an event with the contract's schema and returns only the contract's fields.
 * Anything extra a caller passes (a user ID, a name) is dropped here, so it can never
 * reach a channel or a push (P1, P6). Returns null for an event that isn't in the contract.
 */
export function contractEvent(event: unknown): GlowEvent | null {
  const parsed = zGlowEvent.safeParse(event);
  if (!parsed.success) return null;
  // zod objects strip unknown keys, but be explicit: rebuild from the declared keys only.
  const value = parsed.data;
  if ('matchId' in value)
    return { type: value.type, matchId: value.matchId.toLowerCase() } as GlowEvent;
  return { type: value.type, roomId: value.roomId.toLowerCase() } as GlowEvent;
}

export function channelOf(type: GlowEventType): 'user' | 'room' {
  return eventCatalog[type].channel;
}
