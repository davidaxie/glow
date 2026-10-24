import { afterEach, describe, expect, it, vi } from 'vitest';
import { operations } from '@/contracts';
import { HttpError } from '@/server/http';
import {
  checkRateLimit,
  clientIp,
  limitRequest,
  memoryStore,
  policyForOperation,
  RATE_LIMIT_POLICIES,
  rateLimit,
  setRateLimitStoreForTests,
  type RateLimitStore,
} from '@/server/ratelimit';

const USER = '7e570000-0000-4000-8000-000000000001';

afterEach(() => setRateLimitStoreForTests(undefined));

function recordingStore(): RateLimitStore & { keys: string[] } {
  const inner = memoryStore();
  const keys: string[] = [];
  return {
    name: 'test',
    keys,
    hit(key, name, policy, now) {
      keys.push(key);
      return inner.hit(key, name, policy, now);
    },
  };
}

describe('memoryStore', () => {
  it('is a sliding window', async () => {
    const store = memoryStore();
    const policy = { limit: 3, windowSeconds: 10, use: 'test' };
    const at = (s: number) => store.hit('k', 'api', policy, 1_000_000 + s * 1000);
    expect((await at(0)).allowed).toBe(true);
    expect((await at(1)).allowed).toBe(true);
    expect(await at(2)).toMatchObject({ allowed: true, remaining: 0 });
    expect(await at(3)).toEqual({ allowed: false, remaining: 0, resetAt: 1_010_000 });
    expect((await at(9.9)).allowed).toBe(false);
    expect((await at(10.5)).allowed).toBe(true);
  });

  it('keeps memory bounded', async () => {
    const store = memoryStore(10);
    const policy = { limit: 1, windowSeconds: 60, use: 'test' };
    for (let i = 0; i < 50; i++) await store.hit(`k${i}`, 'api', policy, 1000);
    // The oldest keys were forgotten, so k0 is allowed again; the newest is still limited.
    expect((await store.hit('k0', 'api', policy, 1001)).allowed).toBe(true);
    expect((await store.hit('k49', 'api', policy, 1001)).allowed).toBe(false);
  });
});

describe('rateLimit', () => {
  it('allows up to the policy limit, then answers 429 with Retry-After', async () => {
    const { limit } = RATE_LIMIT_POLICIES.reports;
    for (let i = 0; i < limit; i++) await rateLimit(USER, 'reports');
    const error = await rateLimit(USER, 'reports').catch((e: unknown) => e);
    expect(error).toBeInstanceOf(HttpError);
    expect(error).toMatchObject({ status: 429, code: 'rate_limited' });
    const retryAfter = Number((error as HttpError).headers?.['Retry-After']);
    expect(retryAfter).toBeGreaterThan(0);
    expect(retryAfter).toBeLessThanOrEqual(RATE_LIMIT_POLICIES.reports.windowSeconds);
    // Another person, and another policy, are counted separately.
    await expect(rateLimit('7e570000-0000-4000-8000-000000000002', 'reports')).resolves.toBe(
      undefined,
    );
    await expect(rateLimit(USER, 'blocks')).resolves.toBe(undefined);
  });

  it('never hands the store a raw user ID or IP', async () => {
    const store = recordingStore();
    setRateLimitStoreForTests(store);
    await rateLimit(USER, 'deck');
    await rateLimit(USER, 'deck');
    await rateLimit(USER, 'taps');
    await limitRequest('resolveRoom', reqFrom('203.0.113.9'), null);
    const [a, b, c, d] = store.keys;
    expect(a).toBe(b);
    expect(a).not.toBe(c);
    for (const key of store.keys) {
      expect(key).not.toContain(USER);
      expect(key).not.toContain('203.0.113.9');
      expect(key).toMatch(/^[A-Za-z0-9_-]{43}$/);
    }
    expect(d).toBeDefined();
  });

  it('fails open, and logs, when the store is down', async () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => undefined);
    setRateLimitStoreForTests({
      name: 'test',
      hit: () => Promise.reject(new Error('redis down')),
    });
    await expect(checkRateLimit(USER, 'messages')).resolves.toMatchObject({ allowed: true });
    expect(warn.mock.calls.join('\n')).toContain('ratelimit.unavailable');
  });
});

describe('limitRequest and policies', () => {
  it('has a policy for every operation in the contract, and none for the purge cron', () => {
    for (const id of Object.keys(operations)) {
      const policy = policyForOperation(id);
      if (id === 'runPurge') expect(policy).toBeNull();
      else expect(policy && RATE_LIMIT_POLICIES[policy]).toBeTruthy();
    }
    expect(policyForOperation('sendMessage')).toBe('messages');
    expect(policyForOperation('createTap')).toBe('taps');
    expect(policyForOperation('getDeck')).toBe('deck');
    expect(policyForOperation('joinRoom')).toBe('join');
    expect(policyForOperation('createReport')).toBe('reports');
    expect(policyForOperation('testLogin')).toBe('signIn');
    expect(policyForOperation('adminListRooms')).toBe('admin');
  });

  it('keys signed-in requests by person and the rest by IP', async () => {
    const store = recordingStore();
    setRateLimitStoreForTests(store);
    await limitRequest('getMe', reqFrom('198.51.100.1'), { id: USER });
    await limitRequest('getMe', reqFrom('198.51.100.2'), { id: USER });
    await limitRequest('testLogin', reqFrom('198.51.100.1'), null);
    await limitRequest('testLogin', reqFrom('198.51.100.2'), null);
    await limitRequest('runPurge', reqFrom('198.51.100.1'), null);
    const [me1, me2, ip1, ip2] = store.keys;
    expect(me1).toBe(me2);
    expect(ip1).not.toBe(ip2);
    expect(store.keys).toHaveLength(4);
  });

  it('reads the client IP the way Vercel sends it', () => {
    expect(clientIp(reqFrom('203.0.113.9, 10.0.0.1'))).toBe('203.0.113.9');
    expect(clientIp(new Request('http://x/', { headers: { 'x-real-ip': '192.0.2.4' } }))).toBe(
      '192.0.2.4',
    );
    expect(clientIp(new Request('http://x/'))).toBe('unknown');
  });
});

describe('Upstash', () => {
  it('is used when configured, with one prefixed sliding window per policy', async () => {
    vi.resetModules();
    const limit = vi.fn(async () => ({
      success: false,
      remaining: 0,
      reset: Date.now() + 30_000,
      limit: 10,
      pending: Promise.resolve(),
    }));
    const configs: Record<string, unknown>[] = [];
    vi.doMock('@upstash/ratelimit', () => {
      class Ratelimit {
        static slidingWindow = (tokens: number, window: string) => ({ tokens, window });
        constructor(config: Record<string, unknown>) {
          configs.push(config);
        }
        limit = limit;
      }
      return { Ratelimit };
    });
    process.env.UPSTASH_REDIS_REST_URL = 'https://example-upstash.upstash.io';
    process.env.UPSTASH_REDIS_REST_TOKEN = 'upstash-test-token-000000000000';
    const env = await import('@/env');
    env.resetEnvCacheForTests();
    const fresh = await import('@/server/ratelimit');
    const result = await fresh.checkRateLimit(USER, 'reports');
    expect(result.allowed).toBe(false);
    expect(result.retryAfterSeconds).toBeGreaterThanOrEqual(29);
    expect(configs[0]).toMatchObject({
      prefix: 'glow:rl:reports',
      analytics: false,
      timeout: 1000,
      limiter: { tokens: 10, window: '3600 s' },
    });
    vi.doUnmock('@upstash/ratelimit');
  });
});

function reqFrom(ip: string): Request {
  return new Request('http://localhost/api/x', { headers: { 'x-forwarded-for': ip } });
}
