/**
 * Supabase Realtime broadcasts from the server, over Realtime's REST endpoint, so a
 * serverless function never has to hold a WebSocket open.
 *
 * Every message is private: only people the Realtime policy lets in can receive it
 * (D27). The event name is the event type and the payload is the event itself
 * (contracts/events.json, `realtime`).
 */
import { getEnv } from '@/env';
import type { GlowEvent } from '@/contracts';

/** How long to wait for Realtime before giving up on a broadcast. */
export const REALTIME_TIMEOUT_MS = 3000;

export type BroadcastMessage = {
  readonly topic: string;
  readonly event: GlowEvent;
};

/** Sends every message in one request. Resolves true if Realtime accepted them. */
export async function broadcast(messages: readonly BroadcastMessage[]): Promise<boolean> {
  if (messages.length === 0) return true;
  const env = getEnv();
  const url = new URL('/realtime/v1/api/broadcast', env.SUPABASE_URL);
  const key = env.SUPABASE_SERVICE_ROLE_KEY;
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      apikey: key,
      // A legacy service_role JWT also goes in Authorization. A new `sb_secret_` key must
      // not: the gateway swaps it for a short-lived JWT on its own.
      ...(isJwt(key) ? { authorization: `Bearer ${key}` } : {}),
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      messages: messages.map(({ topic, event }) => ({
        topic,
        event: event.type,
        payload: event,
        private: true,
      })),
    }),
    signal: AbortSignal.timeout(REALTIME_TIMEOUT_MS),
  });
  // Drain the body so the connection can be reused.
  await res.arrayBuffer().catch(() => undefined);
  return res.status >= 200 && res.status < 300;
}

function isJwt(key: string): boolean {
  return /^[\w-]+\.[\w-]+\.[\w-]+$/.test(key);
}
