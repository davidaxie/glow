import { decodeProtectedHeader, jwtVerify } from 'jose';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { apnsRequestFor, type GlowEvent } from '@/contracts';
import { ApnsClient, type ApnsPush } from '@/server/notify/apns';
import { bearerOf, startMockApns, testCredentials, type MockApns } from './helpers/apns-server';

const TOKEN = 'ab'.repeat(32);
const MATCH = 'f1c70000-0000-4000-8000-000000000001';

function pushFor(event: GlowEvent, overrides: Partial<ApnsPush> = {}): ApnsPush {
  const request = apnsRequestFor(event);
  if (!request) throw new Error('no push for this event');
  return {
    environment: 'sandbox',
    deviceToken: TOKEN,
    request,
    expiresAt: 1_900_000_000,
    ...overrides,
  };
}

let apns: MockApns;
let client: ApnsClient | undefined;
const key = testCredentials();

function makeClient(options: ConstructorParameters<typeof ApnsClient>[1] = {}) {
  client = new ApnsClient(key.credentials, {
    origins: { sandbox: apns.origin, production: apns.origin },
    retryDelayMs: 1,
    ...options,
  });
  return client;
}

beforeEach(async () => {
  apns = await startMockApns();
});

afterEach(async () => {
  client?.close();
  client = undefined;
  await apns.close();
});

describe('ApnsClient', () => {
  it('sends an alert push with the headers Apple needs', async () => {
    const result = await makeClient().send(pushFor({ type: 'match.created', matchId: MATCH }));
    expect(result).toEqual({ ok: true, status: 200 });

    const [push] = apns.pushes;
    expect(push?.headers[':method']).toBe('POST');
    expect(push?.headers[':path']).toBe(`/3/device/${TOKEN}`);
    expect(push?.headers['apns-topic']).toBe('com.davidxie.glow');
    expect(push?.headers['apns-push-type']).toBe('alert');
    expect(push?.headers['apns-priority']).toBe('10');
    expect(push?.headers['apns-expiration']).toBe('1900000000');
    expect(push?.headers['apns-collapse-id']).toBe(`match.created:${MATCH}`);
    expect(JSON.parse(push?.body ?? '')).toEqual(
      apnsRequestFor({ type: 'match.created', matchId: MATCH })?.payload,
    );
  });

  it('marks glow.started time sensitive', async () => {
    await makeClient().send(pushFor({ type: 'glow.started', matchId: MATCH }));
    const body = JSON.parse(apns.pushes[0]?.body ?? '') as { aps: Record<string, unknown> };
    expect(body.aps['interruption-level']).toBe('time-sensitive');
  });

  it('signs an ES256 provider token with the key ID and team ID', async () => {
    const before = Math.floor(Date.now() / 1000);
    await makeClient().send(pushFor({ type: 'match.created', matchId: MATCH }));
    const jwt = bearerOf(apns.pushes[0]!);
    expect(decodeProtectedHeader(jwt)).toEqual({ alg: 'ES256', kid: 'TESTKEY123' });
    const { payload } = await jwtVerify(jwt, key.publicKey, { issuer: 'TEAM456789' });
    expect(payload.iat).toBeGreaterThanOrEqual(before);
    expect(Object.keys(payload).sort()).toEqual(['iat', 'iss']);
  });

  it('reuses the provider token for 50 minutes, then makes a new one', async () => {
    let now = Date.now();
    const sender = makeClient({ now: () => now });
    await sender.send(pushFor({ type: 'match.created', matchId: MATCH }));
    now += 49 * 60_000;
    await sender.send(pushFor({ type: 'match.created', matchId: MATCH }));
    now += 2 * 60_000;
    await sender.send(pushFor({ type: 'match.created', matchId: MATCH }));
    const [first, second, third] = apns.pushes.map(bearerOf);
    expect(second).toBe(first);
    expect(third).not.toBe(first);
  });

  it('uses one HTTP/2 connection for many pushes', async () => {
    const sender = makeClient();
    await Promise.all(
      Array.from({ length: 5 }, () =>
        sender.send(pushFor({ type: 'message.created', matchId: MATCH })),
      ),
    );
    expect(apns.pushes).toHaveLength(5);
    // @ts-expect-error reading a private field to count connections
    expect(sender.sessions.size).toBe(1);
  });

  it.each([
    { status: 410, reason: 'Unregistered' },
    { status: 410, reason: 'ExpiredToken' },
    { status: 400, reason: 'BadDeviceToken' },
    { status: 400, reason: 'DeviceTokenNotForTopic' },
  ])('reports a dead token: $status $reason', async (answer) => {
    apns.answers.push(answer);
    const result = await makeClient().send(pushFor({ type: 'match.created', matchId: MATCH }));
    expect(result).toEqual({ ok: false, status: answer.status, reason: answer.reason, dead: true });
    expect(apns.pushes).toHaveLength(1);
  });

  it('keeps tokens that failed for other reasons', async () => {
    apns.answers.push({ status: 400, reason: 'PayloadTooLarge' });
    const result = await makeClient().send(pushFor({ type: 'match.created', matchId: MATCH }));
    expect(result).toEqual({ ok: false, status: 400, reason: 'PayloadTooLarge', dead: false });
  });

  it('makes a new provider token once when Apple says it expired', async () => {
    let now = Date.now();
    const sender = makeClient({ now: () => now });
    await sender.send(pushFor({ type: 'match.created', matchId: MATCH }));
    now += 1000;
    apns.answers.push({ status: 403, reason: 'ExpiredProviderToken' });
    const result = await sender.send(pushFor({ type: 'match.created', matchId: MATCH }));
    expect(result.ok).toBe(true);
    const tokens = apns.pushes.map(bearerOf);
    expect(tokens[1]).toBe(tokens[0]);
    expect(tokens[2]).not.toBe(tokens[0]);
  });

  it.each([429, 500, 503])('retries a %i once', async (status) => {
    apns.answers.push({ status, reason: 'TooManyRequests' });
    const result = await makeClient().send(pushFor({ type: 'match.created', matchId: MATCH }));
    expect(result.ok).toBe(true);
    expect(apns.pushes).toHaveLength(2);
  });

  it('gives up after one retry', async () => {
    apns.answers.push(
      { status: 503, reason: 'ServiceUnavailable' },
      { status: 503, reason: 'ServiceUnavailable' },
    );
    const result = await makeClient().send(pushFor({ type: 'match.created', matchId: MATCH }));
    expect(result).toEqual({ ok: false, status: 503, reason: 'ServiceUnavailable', dead: false });
  });

  it('times out a push Apple never answers', async () => {
    apns.answers.push({ status: 200, delayMs: 1000 }, { status: 200, delayMs: 1000 });
    const result = await makeClient({ timeoutMs: 50 }).send(
      pushFor({ type: 'match.created', matchId: MATCH }),
    );
    expect(result).toEqual({ ok: false, status: 0, reason: 'Timeout', dead: false });
  });

  it('reports an unreachable APNs as a network error, without throwing', async () => {
    const origin = apns.origin;
    await apns.close();
    client = new ApnsClient(key.credentials, {
      origins: { sandbox: origin, production: origin },
      retryDelayMs: 1,
    });
    const result = await client.send(pushFor({ type: 'match.created', matchId: MATCH }));
    expect(result).toMatchObject({ ok: false, status: 0, dead: false });
    apns = await startMockApns();
  });

  it('refuses a malformed device token without calling Apple', async () => {
    const result = await makeClient().send(
      pushFor({ type: 'match.created', matchId: MATCH }, { deviceToken: '../../etc' }),
    );
    expect(result).toEqual({ ok: false, status: 400, reason: 'BadDeviceToken', dead: true });
    expect(apns.pushes).toHaveLength(0);
  });

  it('sends each environment to its own host', async () => {
    const other = await startMockApns();
    try {
      client = new ApnsClient(key.credentials, {
        origins: { sandbox: apns.origin, production: other.origin },
      });
      await client.send(
        pushFor({ type: 'match.created', matchId: MATCH }, { environment: 'production' }),
      );
      await client.send(
        pushFor({ type: 'match.created', matchId: MATCH }, { environment: 'sandbox' }),
      );
      expect(other.pushes).toHaveLength(1);
      expect(apns.pushes).toHaveLength(1);
    } finally {
      client?.close();
      await other.close();
    }
  });
});
