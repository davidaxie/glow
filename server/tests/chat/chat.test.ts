/**
 * Owner: C4. Chat logic without a database: paging at millisecond edges, what a message
 * looks like to each person, the order of checks when sending, and that message text never
 * reaches a log. The same routes run against a real Supabase in chat.integration.test.ts.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { HttpError, notFound } from '@/server/http';

const rpc = vi.hoisted(() => vi.fn());
const update = vi.hoisted(() => vi.fn());
const notify = vi.hoisted(() => vi.fn(async () => ({ realtime: 'sent', push: null })));
const notifyRoom = vi.hoisted(() => vi.fn(async () => ({ realtime: 'sent', push: null })));
const moderateText = vi.hoisted(() => vi.fn());
/** Rows the open check-ins query answers with. */
const checkins = vi.hoisted(() => ({ rows: [] as { room_id: string }[] }));

vi.mock('@/server/chat/db', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@/server/chat/db')>();
  const chain = { eq: () => chain, then: (resolve: (v: unknown) => void) => resolve(update()) };
  const select = {
    in: () => select,
    is: () => select,
    gt: () => select,
    then: (resolve: (v: unknown) => void) => resolve({ data: checkins.rows, error: null }),
  };
  return {
    ...actual,
    rpc,
    serviceDb: () => ({ from: () => ({ update: () => chain, select: () => select }) }),
  };
});

vi.mock('@/server/chat/dependencies', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@/server/chat/dependencies')>();
  return { ...actual, notify, notifyRoom, moderateText };
});

const { pageOf, sendMessageFor, toMessage } = await import('@/server/chat/messages');
const { unmatchFor } = await import('@/server/chat/unmatch');
const { logger } = await import('@/server/log');

const ME = '11111111-1111-4111-8111-111111111111';
const THEM = '22222222-2222-4222-8222-222222222222';
const MATCH = '33333333-3333-4333-8333-333333333333';

const row = (i: number, createdAt: string, sender = ME) => ({
  id: `00000000-0000-4000-8000-${String(i).padStart(12, '0')}`,
  sender_id: sender,
  body: `m${i}`,
  created_at: createdAt,
  client_id: null,
});

describe('pageOf', () => {
  it('returns everything, with no next page, when it fits', () => {
    const rows = [row(2, '2026-10-24T20:00:00.002+00:00'), row(1, '2026-10-24T20:00:00.001+00:00')];
    expect(pageOf(rows, 2)).toEqual({ rows });
  });

  it('ends a full page on a millisecond boundary and starts the next just after it', () => {
    const rows = [
      row(4, '2026-10-24T20:00:00.004+00:00'),
      row(3, '2026-10-24T20:00:00.003+00:00'),
      row(2, '2026-10-24T20:00:00.002+00:00'),
    ];
    // Distinct milliseconds: the page keeps 4, and 3 opens the next page.
    expect(pageOf(rows, 2)).toEqual({ rows: [rows[0]], nextBefore: '2026-10-24T20:00:00.004Z' });
  });

  it('never splits a millisecond between pages', () => {
    const rows = [
      row(4, '2026-10-24T20:00:00.005123+00:00'),
      row(3, '2026-10-24T20:00:00.004900+00:00'),
      row(2, '2026-10-24T20:00:00.004100+00:00'),
      row(1, '2026-10-24T20:00:00.004050+00:00'),
    ];
    const { rows: kept, nextBefore } = pageOf(rows, 3);
    expect(kept.map((r) => r.body)).toEqual(['m4']);
    expect(nextBefore).toBe('2026-10-24T20:00:00.005Z');
    // Every message of millisecond .004 is older than nextBefore, so the next page has them.
    for (const r of rows.slice(1))
      expect(Date.parse(r.created_at)).toBeLessThan(Date.parse(nextBefore!));
  });

  it('falls back to a plain cut if a whole page shares one millisecond', () => {
    const rows = [1, 2, 3].map((i) => row(i, `2026-10-24T20:00:00.004${i}00+00:00`));
    expect(pageOf(rows, 2)).toEqual({
      rows: rows.slice(0, 2),
      nextBefore: '2026-10-24T20:00:00.004Z',
    });
  });
});

describe('toMessage', () => {
  it('says fromMe and never who sent it', () => {
    const mine = toMessage({ ...row(1, '2026-10-24T20:00:00.123456+00:00'), client_id: 'c' }, ME);
    expect(mine).toEqual({
      id: '00000000-0000-4000-8000-000000000001',
      fromMe: true,
      body: 'm1',
      createdAt: '2026-10-24T20:00:00.123Z',
      clientId: 'c',
    });
    const theirs = toMessage({ ...row(2, '2026-10-24T20:00:01+00:00', THEM), client_id: 'k' }, ME);
    expect(theirs).toEqual({
      id: '00000000-0000-4000-8000-000000000002',
      fromMe: false,
      body: 'm2',
      createdAt: '2026-10-24T20:00:01.000Z',
    });
    expect(JSON.stringify([mine, theirs])).not.toContain(THEM);
  });
});

describe('sendMessageFor', () => {
  const open = { id: MATCH, status: 'chatting', userIds: [ME, THEM] };
  const stored = (body: string, moderation = 'pending') => ({
    id: '44444444-4444-4444-8444-444444444444',
    matchId: MATCH,
    body,
    moderation,
    createdAt: '2026-10-24T20:15:00.123Z',
    recipientId: THEM,
  });

  beforeEach(() => {
    rpc.mockReset();
    update.mockReset().mockReturnValue({ error: null });
    moderateText.mockReset().mockResolvedValue({ decision: 'passed' });
  });

  it('checks the thread before the text goes to moderation', async () => {
    rpc.mockRejectedValueOnce(notFound());
    await expect(sendMessageFor(ME, MATCH, { body: 'hello' })).rejects.toMatchObject({
      status: 404,
    });
    expect(moderateText).not.toHaveBeenCalled();
    expect(notify).not.toHaveBeenCalled();
  });

  it('is 409 while choosing, before moderation', async () => {
    rpc.mockResolvedValueOnce({ ...open, status: 'choosing' });
    const error = await sendMessageFor(ME, MATCH, { body: 'hello' }).catch((e: unknown) => e);
    expect(error).toBeInstanceOf(HttpError);
    expect(error).toMatchObject({ status: 409, code: 'chat_not_open' });
    expect(moderateText).not.toHaveBeenCalled();
  });

  it('refuses flagged text without storing or notifying', async () => {
    rpc.mockResolvedValueOnce(open);
    moderateText.mockResolvedValueOnce({ decision: 'flagged', category: 'harassment' });
    await expect(sendMessageFor(ME, MATCH, { body: 'bad' })).rejects.toMatchObject({
      status: 422,
      code: 'message_rejected',
    });
    expect(rpc).toHaveBeenCalledTimes(1);
    expect(rpc.mock.calls[0]![0]).toBe('get_match');
    expect(notify).not.toHaveBeenCalled();
  });

  it('marks a passed message, and tells only the recipient', async () => {
    rpc.mockResolvedValueOnce(open).mockResolvedValueOnce(stored('hello'));
    const message = await sendMessageFor(ME, MATCH, { body: 'hello' });
    expect(message).toEqual({
      id: '44444444-4444-4444-8444-444444444444',
      fromMe: true,
      body: 'hello',
      createdAt: '2026-10-24T20:15:00.123Z',
    });
    expect(update).toHaveBeenCalledTimes(1);
    expect(notify).toHaveBeenCalledWith([THEM], { type: 'message.created', matchId: MATCH });
  });

  it('leaves a pending message pending, and still delivers it', async () => {
    rpc.mockResolvedValueOnce(open).mockResolvedValueOnce(stored('hello'));
    moderateText.mockResolvedValueOnce({ decision: 'pending' });
    await sendMessageFor(ME, MATCH, { body: 'hello' });
    expect(update).not.toHaveBeenCalled();
    expect(notify).toHaveBeenCalledWith([THEM], { type: 'message.created', matchId: MATCH });
  });

  it('never marks the first message passed for a retry that carried different text', async () => {
    const clientId = '55555555-5555-4555-8555-555555555555';
    rpc.mockResolvedValueOnce(open).mockResolvedValueOnce({ ...stored('first'), clientId });
    const message = await sendMessageFor(ME, MATCH, { body: 'second', clientId });
    expect(message.body).toBe('first');
    expect(update).not.toHaveBeenCalled();
  });

  it('notifies about timeouts get_match applied on the way', async () => {
    rpc
      .mockResolvedValueOnce({
        ...open,
        settled: [{ matchId: MATCH, kind: 'choice_timeout', userIds: [ME, THEM] }],
      })
      .mockResolvedValueOnce(stored('hello'));
    await sendMessageFor(ME, MATCH, { body: 'hello' });
    expect(notify).toHaveBeenCalledWith([ME, THEM], { type: 'match.choice', matchId: MATCH });
  });

  it('never writes the message text to a log', async () => {
    const lines: string[] = [];
    for (const level of ['debug', 'info', 'warn', 'error'] as const) {
      vi.spyOn(logger, level).mockImplementation((event, fields) => {
        lines.push(JSON.stringify({ event, fields }));
      });
    }
    const secret = 'my number is 555 0100, call me';
    rpc.mockResolvedValueOnce(open).mockResolvedValueOnce(stored(secret));
    update.mockReturnValueOnce({ error: { code: 'XX000' } });
    await sendMessageFor(ME, MATCH, { body: secret });
    rpc.mockResolvedValueOnce(open);
    moderateText.mockResolvedValueOnce({ decision: 'flagged', category: 'scam' });
    await sendMessageFor(ME, MATCH, { body: secret }).catch(() => undefined);
    expect(lines.length).toBeGreaterThan(0);
    for (const line of lines) {
      expect(line).not.toContain('555 0100');
      expect(line).not.toContain(ME);
      expect(line).not.toContain(THEM);
    }
  });
});

describe('unmatchFor', () => {
  const ROOM = '44444444-0000-4000-8000-000000000001';

  it('sends what a block sends: match.ended to both, deck.changed to their rooms', async () => {
    rpc.mockReset().mockResolvedValueOnce({ matchId: MATCH, roomId: ROOM, userIds: [ME, THEM] });
    checkins.rows = [{ room_id: ROOM }, { room_id: ROOM }];
    await unmatchFor(ME, MATCH);
    expect(notify).toHaveBeenCalledTimes(1);
    expect(notify).toHaveBeenCalledWith([ME, THEM], { type: 'match.ended', matchId: MATCH });
    expect(notifyRoom.mock.calls).toEqual([[ROOM, { type: 'deck.changed', roomId: ROOM }]]);
  });

  it('sends no room event when neither is checked in anywhere', async () => {
    rpc.mockReset().mockResolvedValueOnce({ matchId: MATCH, roomId: ROOM, userIds: [ME, THEM] });
    checkins.rows = [];
    await unmatchFor(ME, MATCH);
    expect(notify).toHaveBeenCalledTimes(1);
    expect(notifyRoom).not.toHaveBeenCalled();
  });

  it('is 404 when the match is not theirs or already ended, and tells nobody', async () => {
    rpc.mockReset().mockRejectedValueOnce(notFound());
    await expect(unmatchFor(ME, MATCH)).rejects.toMatchObject({ status: 404 });
    expect(notify).not.toHaveBeenCalled();
    expect(notifyRoom).not.toHaveBeenCalled();
  });
});
