/**
 * Owner: C4. `GET` and `POST /api/matches/{id}/messages` (listMessages, sendMessage).
 *
 * Reading: a page of the thread, oldest to newest, paging back with `before`. Messages say
 * `fromMe` and never carry a sender (D20). A message B8's after-the-fact review flagged is
 * hidden from the recipient; its sender still sees what they wrote.
 *
 * Sending, in this order, so each check costs as little as it can and reveals nothing:
 *   1. the per-person rate limit (B8's `messages` policy, 429), counted by A1's `route()`
 *   2. a blank body is 400
 *   3. the thread must be open to this person (`get_match`: 404 if it isn't theirs, they were
 *      blocked or it ended; 409 `chat_not_open` while choosing). Only then does the text go
 *      anywhere.
 *   4. moderation within MODERATION_TIMEOUT (B8): flagged is 422 `message_rejected` and is
 *      never stored; no answer in time means it goes through as `pending` and B8's purge
 *      cron reviews it afterwards
 *   5. `send_message`, which re-checks 3 in the same transaction as the insert (a block or
 *      unmatch that lands in between still wins), and returns the first message again for a
 *      retry with the same `clientId`
 *   6. message.created to the recipient, with the fixed lock screen text "New message"
 *
 * Message text is never logged, and never sent anywhere but moderation and the database.
 */
import { z } from 'zod';
import { MESSAGES_PAGE_SIZE, type Message, type MessagePage, type NewMessage } from '@/contracts';
import { badRequest, type RouteHandler } from '@/server/http';
import { logger } from '@/server/log';
import { announceMessage } from './announce';
import { DatabaseError, rpc, serviceDb, tableError } from './db';
import { messageRejected, moderateText } from './dependencies';
import { openThread } from './thread';

type MessageRow = {
  readonly id: string;
  readonly sender_id: string;
  readonly body: string;
  readonly created_at: string;
  readonly client_id: string | null;
};

/** A row as the app sees it: whose it is, never who sent it. */
export function toMessage(row: MessageRow, viewerId: string): Message {
  const fromMe = row.sender_id === viewerId;
  return {
    id: row.id,
    fromMe,
    body: row.body,
    createdAt: new Date(row.created_at).toISOString(),
    // "Echoed back on my own messages": the other person's idempotency keys are theirs.
    ...(fromMe && row.client_id ? { clientId: row.client_id } : {}),
  };
}

const ms = (iso: string) => Date.parse(iso);

/**
 * Cuts one page out of `rows` (newest first, at most limit + 1 of them) and says where the
 * next page starts.
 *
 * `before` and `nextBefore` have millisecond precision, but the database keeps microseconds.
 * If the page ended in the middle of a millisecond, an older message in that same
 * millisecond would be skipped. So the page drops the messages of its oldest millisecond
 * and the next page starts just after it, which picks them all up there.
 */
export function pageOf(
  rows: readonly MessageRow[],
  limit: number,
): { readonly rows: readonly MessageRow[]; readonly nextBefore?: string } {
  if (rows.length <= limit) return { rows };
  const page = rows.slice(0, limit);
  const boundary = Math.floor(ms(page[page.length - 1]!.created_at));
  const kept = page.filter((row) => Math.floor(ms(row.created_at)) > boundary);
  if (kept.length === 0) {
    // More than a page of messages in one millisecond: can't happen at human speed (and the
    // send rate limit). Fall back to a plain cut rather than looping forever.
    return { rows: page, nextBefore: new Date(boundary).toISOString() };
  }
  return { rows: kept, nextBefore: new Date(boundary + 1).toISOString() };
}

export async function listMessagesFor(
  viewerId: string,
  matchId: string,
  options: { readonly before?: string; readonly limit?: number },
): Promise<MessagePage> {
  await openThread(viewerId, matchId);
  const limit = Math.min(options.limit ?? MESSAGES_PAGE_SIZE, MESSAGES_PAGE_SIZE);

  let query = serviceDb()
    .from('messages')
    .select('id, sender_id, body, created_at, client_id')
    .eq('match_id', matchId)
    // Flagged messages are hidden from the recipient. viewerId is the signed-in person's
    // UUID from Supabase Auth, never input from the request.
    .or(`moderation.neq.flagged,sender_id.eq.${viewerId}`)
    .order('created_at', { ascending: false })
    .order('id', { ascending: false })
    .limit(limit + 1);
  if (options.before) query = query.lt('created_at', options.before);

  const { data, error } = await query;
  if (error) throw tableError('messages.list', error);
  const { rows, nextBefore } = pageOf(data ?? [], limit);

  return {
    messages: [...rows].reverse().map((row) => toMessage(row, viewerId)),
    hasMore: nextBefore !== undefined,
    ...(nextBefore ? { nextBefore } : {}),
  };
}

const SentMessage = z.looseObject({
  id: z.string(),
  matchId: z.string(),
  body: z.string(),
  moderation: z.enum(['pending', 'passed', 'flagged']),
  createdAt: z.string(),
  clientId: z.string().optional(),
  recipientId: z.string(),
});

export async function sendMessageFor(
  senderId: string,
  matchId: string,
  request: NewMessage,
): Promise<Message> {
  if (request.body.trim().length === 0) throw badRequest('The message is empty.');
  await openThread(senderId, matchId);

  const verdict = await moderateText(request.body);
  if (verdict.decision === 'flagged') {
    logger.info('chat.message_rejected', {});
    throw messageRejected();
  }

  const raw = await rpc('send_message', {
    p_sender_id: senderId,
    p_match_id: matchId,
    p_body: request.body,
    ...(request.clientId ? { p_client_id: request.clientId } : {}),
  });
  const parsed = SentMessage.safeParse(raw);
  if (!parsed.success) throw new DatabaseError('send_message returned an unexpected shape');
  const sent = parsed.data;

  // send_message stores every message as pending. Record a pass, but only for the text that
  // was actually checked: a retry with an old clientId returns the first message, whose body
  // may differ, and that one keeps whatever it had.
  if (
    verdict.decision === 'passed' &&
    sent.moderation === 'pending' &&
    sent.body === request.body
  ) {
    const { error } = await serviceDb()
      .from('messages')
      .update({ moderation: 'passed' })
      .eq('id', sent.id)
      .eq('moderation', 'pending');
    // Not fatal: a pending message is still delivered, and B8's review settles it later.
    if (error) logger.warn('chat.mark_passed_failed', { code: error.code ?? 'unknown' });
  }

  logger.info('chat.message_sent', {
    moderation: verdict.decision,
    retry: sent.body !== request.body,
  });
  await announceMessage(sent.recipientId, matchId);

  return {
    id: sent.id,
    fromMe: true,
    body: sent.body,
    createdAt: new Date(sent.createdAt).toISOString(),
    ...(sent.clientId ? { clientId: sent.clientId } : {}),
  };
}

export const listMessagesRoute: RouteHandler<'listMessages'> = async ({ user, params, query }) => ({
  status: 200,
  body: await listMessagesFor(user.id, params.id.toLowerCase(), query),
});

export const sendMessageRoute: RouteHandler<'sendMessage'> = async ({ user, params, body }) => ({
  status: 201,
  body: await sendMessageFor(user.id, params.id.toLowerCase(), body),
});
