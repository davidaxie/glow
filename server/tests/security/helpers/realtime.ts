/**
 * A minimal Supabase Realtime client (the Phoenix v1 JSON protocol over Node's WebSocket),
 * so the tests can do exactly what an attacker's script could: join any topic, public or
 * private, with any token, try presence, and try to send.
 */
import type { Live } from './live';

type Frame = { topic: string; event: string; payload: Record<string, unknown>; ref: string | null };

export type Received = {
  readonly topic: string;
  readonly event: string;
  readonly payload: unknown;
};

export class RealtimeProbe {
  private ws!: WebSocket;
  private ref = 0;
  private readonly waiting = new Map<string, (frame: Frame) => void>();
  readonly received: Received[] = [];

  private constructor(private readonly live: Live) {}

  static async connect(live: Live): Promise<RealtimeProbe> {
    const probe = new RealtimeProbe(live);
    const url = new URL('/realtime/v1/websocket', live.url.replace(/^http/, 'ws'));
    url.searchParams.set('apikey', live.anonKey);
    url.searchParams.set('vsn', '1.0.0');
    probe.ws = new WebSocket(url);
    await new Promise<void>((resolve, reject) => {
      probe.ws.addEventListener('open', () => resolve(), { once: true });
      probe.ws.addEventListener('error', () => reject(new Error('realtime connect failed')), {
        once: true,
      });
    });
    probe.ws.addEventListener('message', (message) => probe.onMessage(String(message.data)));
    return probe;
  }

  private onMessage(data: string): void {
    const frame = JSON.parse(data) as Frame;
    const done = frame.ref ? this.waiting.get(frame.ref) : undefined;
    if (done && frame.event === 'phx_reply') {
      this.waiting.delete(frame.ref as string);
      done(frame);
      return;
    }
    if (['broadcast', 'presence_state', 'presence_diff'].includes(frame.event)) {
      this.received.push({ topic: frame.topic, event: frame.event, payload: frame.payload });
    }
  }

  private send(topic: string, event: string, payload: Record<string, unknown>): Promise<Frame> {
    const ref = String(++this.ref);
    const reply = new Promise<Frame>((resolve) => {
      this.waiting.set(ref, resolve);
      setTimeout(() => {
        if (this.waiting.delete(ref)) {
          resolve({ topic, event: 'timeout', payload: { status: 'timeout' }, ref });
        }
      }, 2500);
    });
    this.ws.send(JSON.stringify({ topic, event, payload, ref, join_ref: ref }));
    return reply;
  }

  /** Joins `topic` (for example `user:{id}`). Resolves 'ok' or 'error' (or 'timeout'). */
  async join(
    topic: string,
    options: { token?: string; private: boolean; presenceKey?: string },
  ): Promise<string> {
    const reply = await this.send(`realtime:${topic}`, 'phx_join', {
      config: {
        broadcast: { self: false, ack: true },
        presence: { key: options.presenceKey ?? '', enabled: options.presenceKey !== undefined },
        postgres_changes: [],
        private: options.private,
      },
      ...(options.token ? { access_token: options.token } : {}),
    });
    return String((reply.payload as { status?: unknown }).status ?? 'unknown');
  }

  /** Tries to broadcast on a joined topic. With ack on, Realtime replies to each send. */
  async broadcast(topic: string, event: string, payload: Record<string, unknown>): Promise<string> {
    const reply = await this.send(`realtime:${topic}`, 'broadcast', {
      type: 'broadcast',
      event,
      payload,
    });
    return String((reply.payload as { status?: unknown }).status ?? 'unknown');
  }

  /** Tries to announce presence on a joined topic. */
  async track(topic: string): Promise<string> {
    const reply = await this.send(`realtime:${topic}`, 'presence', {
      type: 'presence',
      event: 'track',
      payload: { who: 'd2' },
    });
    return String((reply.payload as { status?: unknown }).status ?? 'unknown');
  }

  /** Waits a moment for anything still in flight to arrive. */
  async settle(ms = 1500): Promise<void> {
    await new Promise((r) => setTimeout(r, ms));
  }

  close(): void {
    this.ws.close();
  }
}
