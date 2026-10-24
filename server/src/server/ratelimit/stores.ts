/**
 * Where rate limit counts live. Upstash Redis when it's configured (every Vercel deploy
 * requires it, see server/src/env.ts), an in-memory sliding window in local development,
 * CI and tests.
 */
import { Ratelimit } from '@upstash/ratelimit';
import { Redis } from '@upstash/redis';
import type { RateLimitPolicyName, RateLimitPolicy } from './policies';

export type HitResult = {
  readonly allowed: boolean;
  readonly remaining: number;
  /** Milliseconds since the epoch when another request will be allowed. */
  readonly resetAt: number;
};

export interface RateLimitStore {
  readonly name: 'upstash' | 'memory' | 'test';
  hit(
    key: string,
    policyName: RateLimitPolicyName,
    policy: RateLimitPolicy,
    now?: number,
  ): Promise<HitResult>;
}

/**
 * A sliding window log per key. Each key keeps at most `limit` timestamps, and the map is
 * capped, so memory stays bounded however many keys come through.
 */
export function memoryStore(maxKeys = 50_000): RateLimitStore & { clear(): void } {
  const hits = new Map<string, number[]>();

  const evict = () => {
    // Map keeps insertion order and every hit re-inserts its key, so the first keys are
    // the ones touched longest ago.
    for (const key of hits.keys()) {
      if (hits.size <= maxKeys) break;
      hits.delete(key);
    }
  };

  return {
    name: 'memory',
    clear: () => hits.clear(),
    async hit(key, _name, policy, now = Date.now()) {
      const windowMs = policy.windowSeconds * 1000;
      const since = now - windowMs;
      const times = (hits.get(key) ?? []).filter((t) => t > since);
      hits.delete(key);
      if (times.length >= policy.limit) {
        hits.set(key, times);
        return { allowed: false, remaining: 0, resetAt: (times[0] ?? now) + windowMs };
      }
      times.push(now);
      hits.set(key, times);
      if (hits.size > maxKeys) evict();
      return {
        allowed: true,
        remaining: policy.limit - times.length,
        resetAt: (times[0] ?? now) + windowMs,
      };
    },
  };
}

/** Upstash, one sliding-window limiter per policy. Fails open after 1 second. */
export function upstashStore(url: string, token: string): RateLimitStore {
  const redis = new Redis({ url, token, enableTelemetry: false });
  const limiters = new Map<RateLimitPolicyName, Ratelimit>();

  const limiterFor = (name: RateLimitPolicyName, policy: RateLimitPolicy) => {
    let limiter = limiters.get(name);
    if (!limiter) {
      limiter = new Ratelimit({
        redis,
        limiter: Ratelimit.slidingWindow(policy.limit, `${policy.windowSeconds} s`),
        prefix: `glow:rl:${name}`,
        analytics: false,
        timeout: 1000,
      });
      limiters.set(name, limiter);
    }
    return limiter;
  };

  return {
    name: 'upstash',
    async hit(key, name, policy) {
      const result = await limiterFor(name, policy).limit(key);
      // Nothing is pending with analytics off and one region; don't leave it unhandled.
      result.pending.catch(() => undefined);
      return { allowed: result.success, remaining: result.remaining, resetAt: result.reset };
    },
  };
}
