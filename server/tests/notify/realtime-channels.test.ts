/**
 * Realtime channel isolation against the real local Realtime server: one person can't join
 * another person's channel, nobody can send from the app, and `notify()` reaches exactly the
 * right person. Skips when no local Supabase is running (CI starts one).
 */
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { notify, notifyRoom } from '@/server/notify';
import { resetApnsForTests } from '@/server/notify/push';
import {
  createPerson,
  deletePeople,
  eventually,
  join,
  localSupabaseIsUp,
  useLocalSupabase,
  type TestPerson,
} from './helpers/local-supabase';

const up = await localSupabaseIsUp();
const MATCH = 'f1c70000-0000-4000-8000-0000000000c1';
const DEMO_ROOM = 'de000000-0000-4000-8000-000000000001';

describe.skipIf(!up)('Realtime channels (local Supabase)', { timeout: 30_000 }, () => {
  let alex: TestPerson;
  let blake: TestPerson;

  beforeAll(async () => {
    alex = await createPerson();
    blake = await createPerson();
  });
  afterAll(async () => {
    await deletePeople([alex, blake].filter(Boolean));
  });
  beforeEach(() => {
    useLocalSupabase();
    resetApnsForTests();
    for (const write of ['log', 'warn', 'error'] as const) {
      vi.spyOn(console, write).mockImplementation(() => undefined);
    }
  });

  it('lets a person join their own user channel, and notify() reaches it', async () => {
    const own = await join(alex, `user:${alex.id}`);
    expect(own.status).toBe('SUBSCRIBED');

    const outcome = await notify(alex.id, { type: 'match.created', matchId: MATCH });
    expect(outcome.realtime).toBe('sent');
    expect(await eventually(() => own.received.length > 0)).toBe(true);
    expect(own.received).toEqual([
      { event: 'match.created', payload: { type: 'match.created', matchId: MATCH } },
    ]);
    await alex.client.removeChannel(own.channel);
  });

  it('refuses one person joining another person’s channel', async () => {
    const intruder = await join(blake, `user:${alex.id}`);
    expect(intruder.status).toBe('CHANNEL_ERROR');

    await notify(alex.id, { type: 'message.created', matchId: MATCH });
    await new Promise((resolve) => setTimeout(resolve, 1000));
    expect(intruder.received).toEqual([]);
    await blake.client.removeChannel(intruder.channel);
  });

  it('refuses an uppercase topic, even for your own ID', async () => {
    const upper = await join(alex, `user:${alex.id.toUpperCase()}`);
    expect(upper.status).toBe('CHANNEL_ERROR');
    await alex.client.removeChannel(upper.channel);
  });

  it('refuses a room channel without an open check-in there', async () => {
    const room = await join(alex, `room:${DEMO_ROOM}`);
    expect(room.status).toBe('CHANNEL_ERROR');
    await alex.client.removeChannel(room.channel);
  });

  it('delivers to the person it’s for and nobody else', async () => {
    const alexOwn = await join(alex, `user:${alex.id}`);
    const blakeOwn = await join(blake, `user:${blake.id}`);
    expect([alexOwn.status, blakeOwn.status]).toEqual(['SUBSCRIBED', 'SUBSCRIBED']);

    await notify(blake.id, { type: 'glow.ended', matchId: MATCH });
    expect(await eventually(() => blakeOwn.received.length > 0)).toBe(true);
    await new Promise((resolve) => setTimeout(resolve, 500));
    expect(alexOwn.received).toEqual([]);
    expect(blakeOwn.received).toEqual([
      { event: 'glow.ended', payload: { type: 'glow.ended', matchId: MATCH } },
    ]);
    await alex.client.removeChannel(alexOwn.channel);
    await blake.client.removeChannel(blakeOwn.channel);
  });

  it('never lets an app send on someone’s channel', async () => {
    const blakeOwn = await join(blake, `user:${blake.id}`);
    expect(blakeOwn.status).toBe('SUBSCRIBED');

    // Alex forges an event for Blake, over the socket and over REST.
    const forged = alex.client.channel(`user:${blake.id}`, { config: { private: true } });
    await forged.send({
      type: 'broadcast',
      event: 'match.created',
      payload: { type: 'match.created', matchId: MATCH },
    });
    await fetch(`${process.env.SUPABASE_URL}/realtime/v1/api/broadcast`, {
      method: 'POST',
      headers: {
        apikey: String(process.env.SUPABASE_ANON_KEY),
        authorization: `Bearer ${alex.accessToken}`,
        'content-type': 'application/json',
      },
      body: JSON.stringify({
        messages: [
          {
            topic: `user:${blake.id}`,
            event: 'match.created',
            payload: { type: 'match.created', matchId: MATCH },
            private: true,
          },
        ],
      }),
    });
    await new Promise((resolve) => setTimeout(resolve, 1500));
    expect(blakeOwn.received).toEqual([]);
    await alex.client.removeChannel(forged);
    await blake.client.removeChannel(blakeOwn.channel);
  });

  it('notifyRoom only reaches people allowed on the room channel', async () => {
    const outsider = await join(alex, `room:${DEMO_ROOM}`);
    const outcome = await notifyRoom(DEMO_ROOM, { type: 'deck.changed', roomId: DEMO_ROOM });
    expect(outcome.realtime).toBe('sent');
    await new Promise((resolve) => setTimeout(resolve, 1000));
    expect(outsider.received).toEqual([]);
    await alex.client.removeChannel(outsider.channel);
  });
});
