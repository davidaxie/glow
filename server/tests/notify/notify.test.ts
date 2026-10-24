import { afterEach, describe, expect, it, vi } from 'vitest';
import { notify, notifyRoom, notifySettled, type UserEvent } from '@/server/notify';

const ALEX = '7E570000-0000-4000-8000-00000000000A';
const BLAKE = '7e570000-0000-4000-8000-00000000000b';
const MATCH = '3f2a0000-0000-4000-8000-0000000000aa';
const ROOM = 'de000000-0000-4000-8000-000000000001';

type Sent = { url: string; headers: Record<string, string>; body: unknown };

function captureFetch(status = 202) {
  const sent: Sent[] = [];
  vi.spyOn(globalThis, 'fetch').mockImplementation(async (input, init) => {
    sent.push({
      url: String(input),
      headers: Object.fromEntries(new Headers(init?.headers).entries()),
      body: JSON.parse(String(init?.body)),
    });
    return new Response(null, { status });
  });
  return sent;
}

function quietLogs() {
  const lines: string[] = [];
  const grab = (line: unknown) => void lines.push(String(line));
  vi.spyOn(console, 'log').mockImplementation(grab);
  vi.spyOn(console, 'warn').mockImplementation(grab);
  vi.spyOn(console, 'error').mockImplementation(grab);
  return lines;
}

afterEach(() => vi.restoreAllMocks());

describe('notify', () => {
  it('broadcasts the contract payload to each person’s private user channel', async () => {
    quietLogs();
    const sent = captureFetch();
    const outcome = await notify([ALEX, BLAKE, ALEX], { type: 'match.created', matchId: MATCH });

    expect(outcome.realtime).toBe('sent');
    expect(sent).toHaveLength(1);
    expect(sent[0]?.url).toBe('http://127.0.0.1:54421/realtime/v1/api/broadcast');
    expect(sent[0]?.headers.apikey).toBe(process.env.SUPABASE_SERVICE_ROLE_KEY);
    expect(sent[0]?.body).toEqual({
      messages: [
        {
          topic: `user:${ALEX.toLowerCase()}`,
          event: 'match.created',
          payload: { type: 'match.created', matchId: MATCH },
          private: true,
        },
        {
          topic: `user:${BLAKE}`,
          event: 'match.created',
          payload: { type: 'match.created', matchId: MATCH },
          private: true,
        },
      ],
    });
  });

  it('drops anything on the event that isn’t in the contract (P1)', async () => {
    quietLogs();
    const sent = captureFetch();
    const leaky = {
      type: 'message.created',
      matchId: MATCH,
      senderId: BLAKE,
      firstName: 'Blake',
      body: 'hi',
    } as unknown as UserEvent;
    await notify(ALEX, leaky);

    const text = JSON.stringify(sent);
    expect(text).not.toContain('Blake');
    expect(text).not.toContain(BLAKE);
    expect(text).not.toContain('"hi"');
    expect(sent[0]?.body).toMatchObject({
      messages: [{ payload: { type: 'message.created', matchId: MATCH } }],
    });
  });

  it('refuses room events, unknown events and bad IDs without throwing', async () => {
    const logs = quietLogs();
    const sent = captureFetch();
    expect(
      await notify(ALEX, { type: 'deck.changed', roomId: ROOM } as unknown as UserEvent),
    ).toEqual({ realtime: 'skipped', push: null });
    expect(
      await notify(ALEX, { type: 'match.secret', matchId: MATCH } as unknown as UserEvent),
    ).toEqual({ realtime: 'skipped', push: null });
    expect(await notify(['not-a-uuid'], { type: 'glow.ended', matchId: MATCH })).toEqual({
      realtime: 'skipped',
      push: null,
    });
    expect(sent).toHaveLength(0);
    expect(logs.join('\n')).toContain('notify.invalid_event');
  });

  it('never throws when Realtime is down', async () => {
    quietLogs();
    vi.spyOn(globalThis, 'fetch').mockRejectedValue(new TypeError('fetch failed'));
    await expect(notify(ALEX, { type: 'glow.ended', matchId: MATCH })).resolves.toEqual({
      realtime: 'failed',
      push: null,
    });
  });

  it('reports a refused broadcast as failed', async () => {
    quietLogs();
    captureFetch(401);
    expect((await notify(ALEX, { type: 'match.choice', matchId: MATCH })).realtime).toBe('failed');
  });

  it('logs only the type and counts, never IDs of people', async () => {
    const logs = quietLogs();
    captureFetch();
    await notify([ALEX, BLAKE], { type: 'glow.started', matchId: MATCH });
    const text = logs.join('\n');
    expect(text).toContain('notify.sent');
    expect(text).not.toContain(BLAKE);
    expect(text.toLowerCase()).not.toContain(ALEX.toLowerCase());
  });
});

describe('notifyRoom', () => {
  it('broadcasts deck.changed to the room channel only', async () => {
    quietLogs();
    const sent = captureFetch();
    const outcome = await notifyRoom(ROOM.toUpperCase(), { type: 'deck.changed', roomId: ROOM });
    expect(outcome).toEqual({ realtime: 'sent', push: null });
    expect(sent[0]?.body).toEqual({
      messages: [
        {
          topic: `room:${ROOM}`,
          event: 'deck.changed',
          payload: { type: 'deck.changed', roomId: ROOM },
          private: true,
        },
      ],
    });
  });

  it('refuses user events on a room channel', async () => {
    quietLogs();
    const sent = captureFetch();
    await notifyRoom(ROOM, { type: 'match.created', matchId: MATCH } as never);
    expect(sent).toHaveLength(0);
  });
});

describe('notifySettled', () => {
  it('sends match.choice for a choice timeout and glow.ended for an expired glow, to both', async () => {
    quietLogs();
    const sent = captureFetch();
    const other = 'f1c70000-0000-4000-8000-0000000000ee';
    const outcomes = await notifySettled([
      { matchId: MATCH, kind: 'choice_timeout', userIds: [ALEX, BLAKE] },
      { matchId: other, kind: 'glow_expired', userIds: [ALEX, BLAKE] },
    ]);
    expect(outcomes.map((o) => o.realtime)).toEqual(['sent', 'sent']);
    const messages = sent.flatMap(
      (s) => (s.body as { messages: { topic: string; payload: unknown }[] }).messages,
    );
    expect(messages).toHaveLength(4);
    expect(messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          topic: `user:${BLAKE}`,
          payload: { type: 'match.choice', matchId: MATCH },
        }),
        expect.objectContaining({
          topic: `user:${ALEX.toLowerCase()}`,
          payload: { type: 'glow.ended', matchId: other },
        }),
      ]),
    );
  });

  it('does nothing when nothing settled', async () => {
    const sent = captureFetch();
    expect(await notifySettled(undefined)).toEqual([]);
    expect(await notifySettled(null)).toEqual([]);
    expect(await notifySettled([])).toEqual([]);
    expect(sent).toHaveLength(0);
  });

  it('skips malformed entries and unknown kinds, and never throws', async () => {
    const logs = quietLogs();
    const sent = captureFetch();
    const outcomes = await notifySettled([
      { matchId: MATCH, kind: 'reveal_everyone', userIds: [ALEX] },
      { matchId: 'nope', kind: 'choice_timeout', userIds: [ALEX] },
      { matchId: MATCH, kind: 'choice_timeout' },
      'garbage',
    ]);
    expect(outcomes).toEqual([]);
    expect(await notifySettled({ not: 'a list' })).toEqual([]);
    expect(sent).toHaveLength(0);
    expect(logs.join('\n')).toContain('notify.settled_invalid');
  });
});
