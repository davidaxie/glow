/**
 * A local stand-in for Apple's APNs: an HTTP/2 (cleartext) server that records every push and
 * answers whatever the test scripts. Plus a throwaway P-256 key, in .p8 (PKCS #8) form.
 */
import { generateKeyPairSync, type KeyObject } from 'node:crypto';
import http2, { type Http2Server, type IncomingHttpHeaders } from 'node:http2';
import type { AddressInfo } from 'node:net';
import type { ApnsCredentials } from '@/server/notify/apns';

export type RecordedPush = {
  readonly headers: IncomingHttpHeaders;
  readonly body: string;
};

export type Answer = {
  readonly status: number;
  readonly reason?: string;
  /** Wait this long before answering, in milliseconds. */
  readonly delayMs?: number;
};

export type MockApns = {
  readonly origin: string;
  readonly pushes: RecordedPush[];
  /** Answers for the next pushes, in order. After they run out, every push gets 200. */
  readonly answers: Answer[];
  /** A fixed answer for every push to this device token, ahead of `answers`. */
  readonly answersByToken: Map<string, Answer>;
  close(): Promise<void>;
};

export async function startMockApns(): Promise<MockApns> {
  const pushes: RecordedPush[] = [];
  const answers: Answer[] = [];
  const answersByToken = new Map<string, Answer>();
  const server: Http2Server = http2.createServer();
  server.on('stream', (stream, headers) => {
    const chunks: Buffer[] = [];
    stream.on('data', (chunk: Buffer) => chunks.push(chunk));
    stream.on('end', () => {
      pushes.push({ headers, body: Buffer.concat(chunks).toString('utf8') });
      const token =
        String(headers[':path'] ?? '')
          .split('/')
          .pop() ?? '';
      const answer = answersByToken.get(token) ?? answers.shift() ?? { status: 200 };
      const reply = () => {
        if (stream.destroyed) return;
        stream.respond({ ':status': answer.status, 'apns-id': 'test-apns-id' });
        stream.end(answer.reason ? JSON.stringify({ reason: answer.reason }) : undefined);
      };
      if (answer.delayMs) setTimeout(reply, answer.delayMs);
      else reply();
    });
  });
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  const { port } = server.address() as AddressInfo;
  return {
    origin: `http://127.0.0.1:${port}`,
    pushes,
    answers,
    answersByToken,
    close: () =>
      new Promise<void>((resolve) => {
        server.close(() => resolve());
        // Drop any open client connections so close() doesn't wait for them.
        (server as unknown as { closeAllConnections?: () => void }).closeAllConnections?.();
      }),
  };
}

export type TestKey = { readonly credentials: ApnsCredentials; readonly publicKey: KeyObject };

/** A fresh .p8-style key and the matching credentials. Test values only. */
export function testCredentials(): TestKey {
  const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' });
  const pem = privateKey.export({ type: 'pkcs8', format: 'pem' }).toString().trim();
  return {
    credentials: {
      keyId: 'TESTKEY123',
      teamId: 'TEAM456789',
      privateKey: pem,
      bundleId: 'com.davidxie.glow',
    },
    publicKey,
  };
}

/** The token from a recorded push's `authorization: bearer …` header. */
export function bearerOf(push: RecordedPush): string {
  const header = String(push.headers.authorization ?? '');
  return header.replace(/^bearer /, '');
}
