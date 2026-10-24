/**
 * Tells the right phones that something happened, without ever saying who (P1, P6).
 *
 *   import { notify, notifyRoom } from '@/server/notify';
 *
 *   // After record_tap made a match: both people, from the function's userIds.
 *   await notify(result.userIds, { type: 'match.created', matchId: result.matchId });
 *
 *   // After someone paused, left or blocked: everyone checked into the room.
 *   await notifyRoom(roomId, { type: 'deck.changed', roomId });
 *
 *   // After any function that returns `settled` timeouts (get_match, set_choice, …).
 *   await notifySettled(result.settled);
 *
 * Each event goes over Realtime to the person's private `user:{id}` channel, and as an
 * Apple push when contracts/events.json gives it lock screen text. Payloads are built
 * only from the contract: `{ type, matchId }` or `{ type, roomId }`. Anything else on
 * the event object is dropped before it leaves the server.
 *
 * `notify` never throws and never fails the request that called it: a missed
 * notification is logged, and the app refetches on its next open. To keep a slow push
 * off your response time, wrap it in Next's `after()`:
 *
 *   import { after } from 'next/server';
 *   after(() => notify(userIds, event));
 */
import { z } from 'zod';
import { roomTopic, userTopic } from '@/contracts';
import { logger } from '@/server/log';
import { channelOf, contractEvent, type RoomEvent, type UserEvent } from './events';
import { sendPushes, type PushOutcome } from './push';
import { broadcast } from './realtime';

export type { RoomEvent, RoomEventType, UserEvent, UserEventType } from './events';
export type { PushOutcome } from './push';

export type NotifyOutcome = {
  /** Whether Realtime accepted the broadcast. */
  readonly realtime: 'sent' | 'failed' | 'skipped';
  /** What happened to the push, or null when the event has no push. */
  readonly push: PushOutcome | null;
};

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const NOTHING: NotifyOutcome = { realtime: 'skipped', push: null };

/**
 * Sends a `user:{id}` event to one person or several (for example both people in a
 * match). Duplicate and malformed user IDs are ignored.
 */
export async function notify(
  userIds: string | readonly string[],
  event: UserEvent,
): Promise<NotifyOutcome> {
  const parsed = contractEvent(event);
  if (!parsed || channelOf(parsed.type) !== 'user') {
    logger.error('notify.invalid_event', {
      type: typeof event?.type === 'string' ? event.type : null,
    });
    return NOTHING;
  }
  const people = [
    ...new Set((typeof userIds === 'string' ? [userIds] : userIds).map(lower)),
  ].filter((id) => UUID.test(id));
  if (people.length === 0) return NOTHING;

  const [realtime, push] = await Promise.all([
    safeBroadcast(
      people.map((id) => ({ topic: userTopic(id), event: parsed })),
      parsed.type,
    ),
    sendPushes(people, parsed).catch((error: unknown) => {
      logger.error('notify.push_failed', { type: parsed.type, error: errorName(error) });
      return null;
    }),
  ]);
  logger.info('notify.sent', {
    type: parsed.type,
    people: people.length,
    realtime,
    pushSent: push?.sent ?? 0,
    pushFailed: push?.failed ?? 0,
    pushPruned: push?.pruned ?? 0,
  });
  return { realtime, push };
}

/** Sends a `room:{id}` event to everyone with an open check-in in that room. Never a push. */
export async function notifyRoom(roomId: string, event: RoomEvent): Promise<NotifyOutcome> {
  const parsed = contractEvent(event);
  if (!parsed || channelOf(parsed.type) !== 'room' || !UUID.test(roomId)) {
    logger.error('notify.invalid_event', {
      type: typeof event?.type === 'string' ? event.type : null,
    });
    return NOTHING;
  }
  const realtime = await safeBroadcast([{ topic: roomTopic(roomId), event: parsed }], parsed.type);
  logger.info('notify.sent', { type: parsed.type, realtime });
  return { realtime, push: null };
}

/** One entry of a database function's `settled` list (docs/CONTRACTS.md, "Settled timeouts"). */
const zSettled = z.object({
  matchId: z.uuid(),
  kind: z.string(),
  userIds: z.array(z.uuid()),
});

/** Which event each settled timeout sends to both people. */
export const SETTLED_EVENTS: Readonly<Record<string, UserEvent['type']>> = {
  choice_timeout: 'match.choice',
  glow_expired: 'glow.ended',
};

/**
 * Sends the events for a database function's `settled` timeouts: `match.choice` for
 * `choice_timeout` and `glow.ended` for `glow_expired`, to both people in `userIds`.
 * Pass the raw field from the function's result; missing means nothing settled.
 *
 *   const result = await rpc('get_match', …);
 *   after(() => notifySettled(result.settled));
 *
 * Malformed entries and unknown kinds are logged and skipped, never sent. Never throws.
 */
export async function notifySettled(settled: unknown): Promise<NotifyOutcome[]> {
  if (settled === undefined || settled === null) return [];
  if (!Array.isArray(settled)) {
    logger.error('notify.settled_invalid');
    return [];
  }
  const sends: Promise<NotifyOutcome>[] = [];
  for (const raw of settled) {
    const entry = zSettled.safeParse(raw);
    const type = entry.success ? SETTLED_EVENTS[entry.data.kind] : undefined;
    if (!entry.success || !type) {
      logger.error('notify.settled_invalid');
      continue;
    }
    sends.push(notify(entry.data.userIds, { type, matchId: entry.data.matchId } as UserEvent));
  }
  return Promise.all(sends);
}

async function safeBroadcast(
  messages: Parameters<typeof broadcast>[0],
  type: string,
): Promise<'sent' | 'failed'> {
  try {
    if (await broadcast(messages)) return 'sent';
    logger.warn('notify.realtime_refused', { type });
  } catch (error) {
    logger.warn('notify.realtime_failed', { type, error: errorName(error) });
  }
  return 'failed';
}

const lower = (id: string): string => id.toLowerCase();

function errorName(error: unknown): string {
  return error instanceof Error ? error.name : 'unknown';
}
