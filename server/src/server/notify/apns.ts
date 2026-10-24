/**
 * Apple Push Notification service over HTTP/2, with token-based auth (a JWT signed with the
 * .p8 key, ES256, through jose). No third-party push service.
 *
 * - One HTTP/2 connection per APNs host, reused across pushes and closed when idle.
 * - The provider token is reused for 50 minutes (Apple wants 20 to 60) and refreshed once if
 *   Apple says it expired.
 * - Dead tokens (410, BadDeviceToken, DeviceTokenNotForTopic) are reported so the caller can
 *   prune them. Throttling and Apple's own errors are retried once.
 *
 * Nothing here logs a device token, a payload or the provider token.
 */
import http2, { type ClientHttp2Session, type IncomingHttpHeaders } from 'node:http2';
import { importPKCS8, SignJWT, type CryptoKey } from 'jose';
import type { ApnsEnvironment, ApnsRequest } from '@/contracts';

export const APNS_ORIGINS: Readonly<Record<ApnsEnvironment, string>> = {
  sandbox: 'https://api.sandbox.push.apple.com',
  production: 'https://api.push.apple.com',
};

export type ApnsCredentials = {
  readonly keyId: string;
  readonly teamId: string;
  /** The .p8 file's contents: a PKCS #8 EC P-256 key. */
  readonly privateKey: string;
  /** The app's bundle ID, sent as `apns-topic`. */
  readonly bundleId: string;
};

export type ApnsOptions = {
  /** Where each environment's pushes go. Tests point these at a local HTTP/2 server. */
  readonly origins?: Readonly<Record<ApnsEnvironment, string>>;
  /** How long one push may take, in milliseconds. */
  readonly timeoutMs?: number;
  /** Closes a connection after this long without pushes, in milliseconds. */
  readonly idleMs?: number;
  readonly now?: () => number;
  /** Wait before the single retry of a throttled or failed push. */
  readonly retryDelayMs?: number;
};

export type ApnsPush = {
  readonly environment: ApnsEnvironment;
  /** The device token as lowercase hex. */
  readonly deviceToken: string;
  readonly request: ApnsRequest;
  /** When Apple should stop trying to deliver it, in Unix seconds. 0 means now or never. */
  readonly expiresAt: number;
};

export type ApnsResult =
  | { readonly ok: true; readonly status: 200 }
  | {
      readonly ok: false;
      readonly status: number;
      /** Apple's reason, like `BadDeviceToken`, or `Timeout` / `NetworkError`. */
      readonly reason: string;
      /** The token will never work again: delete it. */
      readonly dead: boolean;
    };

const TOKEN_LIFETIME_MS = 50 * 60 * 1000;
const DEAD_REASONS = new Set(['BadDeviceToken', 'DeviceTokenNotForTopic', 'Unregistered']);
const RETRY_STATUSES = new Set([429, 500, 503]);
const TOKEN_HEX = /^[0-9a-f]{64,200}$/;

type ProviderToken = { readonly jwt: string; readonly issuedAt: number };

export class ApnsClient {
  private readonly origins: Readonly<Record<ApnsEnvironment, string>>;
  private readonly timeoutMs: number;
  private readonly idleMs: number;
  private readonly now: () => number;
  private readonly retryDelayMs: number;
  private readonly sessions = new Map<string, ClientHttp2Session>();
  private readonly active = new Map<ClientHttp2Session, number>();
  private key: Promise<CryptoKey> | undefined;
  private token: ProviderToken | undefined;

  constructor(
    private readonly credentials: ApnsCredentials,
    options: ApnsOptions = {},
  ) {
    this.origins = options.origins ?? APNS_ORIGINS;
    this.timeoutMs = options.timeoutMs ?? 5000;
    this.idleMs = options.idleMs ?? 60_000;
    this.now = options.now ?? Date.now;
    this.retryDelayMs = options.retryDelayMs ?? 300;
  }

  /** Sends one push. Never throws: every failure is a result. */
  async send(push: ApnsPush): Promise<ApnsResult> {
    if (!TOKEN_HEX.test(push.deviceToken)) {
      return { ok: false, status: 400, reason: 'BadDeviceToken', dead: true };
    }
    let result = await this.attempt(push);
    if (!result.ok && result.status === 403 && result.reason === 'ExpiredProviderToken') {
      this.token = undefined;
      result = await this.attempt(push);
    } else if (!result.ok && (RETRY_STATUSES.has(result.status) || result.status === 0)) {
      await new Promise((resolve) => setTimeout(resolve, this.retryDelayMs));
      result = await this.attempt(push);
    }
    return result;
  }

  /** Closes every connection. */
  close(): void {
    for (const session of this.sessions.values()) session.close();
    this.sessions.clear();
    this.active.clear();
  }

  private async attempt(push: ApnsPush): Promise<ApnsResult> {
    let jwt: string;
    try {
      jwt = await this.providerToken();
    } catch {
      return { ok: false, status: 0, reason: 'InvalidSigningKey', dead: false };
    }
    let session: ClientHttp2Session;
    try {
      session = this.session(this.origins[push.environment]);
    } catch {
      return { ok: false, status: 0, reason: 'NetworkError', dead: false };
    }
    return this.request(session, jwt, push);
  }

  private request(session: ClientHttp2Session, jwt: string, push: ApnsPush): Promise<ApnsResult> {
    return new Promise((resolve) => {
      let settled = false;
      const finish = (result: ApnsResult) => {
        if (settled) return;
        settled = true;
        this.release(session);
        resolve(result);
      };
      this.hold(session);

      let stream: http2.ClientHttp2Stream;
      try {
        stream = session.request({
          ':method': 'POST',
          ':path': `/3/device/${push.deviceToken}`,
          authorization: `bearer ${jwt}`,
          'apns-topic': this.credentials.bundleId,
          'apns-push-type': 'alert',
          'apns-priority': '10',
          'apns-expiration': String(push.expiresAt),
          'apns-collapse-id': push.request.collapseId,
          'content-type': 'application/json',
        });
      } catch {
        finish({ ok: false, status: 0, reason: 'NetworkError', dead: false });
        return;
      }

      let status = 0;
      const chunks: Buffer[] = [];
      stream.setTimeout(this.timeoutMs, () => {
        stream.close(http2.constants.NGHTTP2_CANCEL);
        finish({ ok: false, status: 0, reason: 'Timeout', dead: false });
      });
      stream.on('response', (headers: IncomingHttpHeaders) => {
        status = Number(headers[':status'] ?? 0);
      });
      stream.on('data', (chunk: Buffer) => chunks.push(chunk));
      stream.on('error', () =>
        finish({ ok: false, status: 0, reason: 'NetworkError', dead: false }),
      );
      // A stream closed before it ended (the connection dropped) is a network error.
      stream.on('close', () =>
        finish({ ok: false, status: 0, reason: 'NetworkError', dead: false }),
      );
      stream.on('end', () => {
        if (status === 200) {
          finish({ ok: true, status: 200 });
          return;
        }
        const reason =
          reasonFrom(Buffer.concat(chunks)) ?? (status ? `Status${status}` : 'NetworkError');
        finish({ ok: false, status, reason, dead: status === 410 || DEAD_REASONS.has(reason) });
      });
      stream.end(JSON.stringify(push.request.payload));
    });
  }

  private session(origin: string): ClientHttp2Session {
    const existing = this.sessions.get(origin);
    if (existing && !existing.closed && !existing.destroyed) return existing;

    const session = http2.connect(origin);
    const forget = () => {
      if (this.sessions.get(origin) === session) this.sessions.delete(origin);
      this.active.delete(session);
    };
    session.on('error', forget);
    session.on('goaway', forget);
    session.on('close', forget);
    session.setTimeout(this.idleMs, () => session.close());
    // Only keep the process alive while a push is in flight.
    session.unref();
    this.sessions.set(origin, session);
    return session;
  }

  private hold(session: ClientHttp2Session): void {
    const count = this.active.get(session) ?? 0;
    if (count === 0) session.ref();
    this.active.set(session, count + 1);
  }

  private release(session: ClientHttp2Session): void {
    const count = (this.active.get(session) ?? 1) - 1;
    if (count <= 0) {
      this.active.delete(session);
      if (!session.destroyed) session.unref();
    } else {
      this.active.set(session, count);
    }
  }

  private async providerToken(): Promise<string> {
    const now = this.now();
    if (this.token && now - this.token.issuedAt < TOKEN_LIFETIME_MS) return this.token.jwt;
    this.key ??= importPKCS8(this.credentials.privateKey, 'ES256').catch((error: unknown) => {
      this.key = undefined;
      throw error;
    });
    const jwt = await new SignJWT({})
      .setProtectedHeader({ alg: 'ES256', kid: this.credentials.keyId })
      .setIssuer(this.credentials.teamId)
      .setIssuedAt(Math.floor(now / 1000))
      .sign(await this.key);
    this.token = { jwt, issuedAt: now };
    return jwt;
  }
}

function reasonFrom(body: Buffer): string | undefined {
  if (body.length === 0) return undefined;
  try {
    const parsed: unknown = JSON.parse(body.toString('utf8'));
    if (parsed && typeof parsed === 'object' && 'reason' in parsed) {
      const reason = (parsed as { reason: unknown }).reason;
      return typeof reason === 'string' && /^[A-Za-z]{1,64}$/.test(reason) ? reason : undefined;
    }
  } catch {
    // Not JSON: fall through.
  }
  return undefined;
}
