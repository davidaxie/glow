/**
 * A hosted deploy (Vercel preview or production) cannot run with the test shortcuts: test
 * sign-in, the moderation stand-in that approves every photo, and an in-memory rate limit.
 * The server refuses to start (env.ts), so a wrong setting is a failed deploy, not a hole.
 */
import { describe, expect, it } from 'vitest';
import { parseEnv } from '@/env';
import { PRODUCTION_ENV } from '../helpers/env';

const problems = (source: Record<string, string | undefined>) => {
  const result = parseEnv(source);
  return result.ok ? [] : result.problems.map((p) => p.name);
};

describe('hosted deploys cannot run the test shortcuts', () => {
  it('control: the base production env is valid', () => {
    expect(problems({ ...PRODUCTION_ENV })).toEqual([]);
    expect(problems({ ...PRODUCTION_ENV, VERCEL_ENV: 'preview' })).toEqual([]);
  });

  it('production and preview refuse ALLOW_TEST_LOGIN, in any spelling', () => {
    for (const profile of [{ ...PRODUCTION_ENV }, { ...PRODUCTION_ENV, VERCEL_ENV: 'preview' }]) {
      for (const on of ['1', 'true', 'TRUE', 'yes', 'on']) {
        expect(problems({ ...profile, ALLOW_TEST_LOGIN: on }), on).toContain('ALLOW_TEST_LOGIN');
      }
    }
  });

  it('a local-looking Supabase URL cannot be paired with test sign-in on a hosted deploy', () => {
    const local = {
      ...PRODUCTION_ENV,
      SUPABASE_URL: 'http://127.0.0.1:54421',
      ALLOW_TEST_LOGIN: '1',
    };
    expect(problems(local)).toContain('ALLOW_TEST_LOGIN');
  });

  it('production needs a real Anthropic key, so the approve-everything stand-in never runs', () => {
    const { ANTHROPIC_API_KEY: _key, ...withoutKey } = PRODUCTION_ENV;
    expect(problems(withoutKey)).toContain('ANTHROPIC_API_KEY');
    expect(problems({ ...PRODUCTION_ENV, ANTHROPIC_API_KEY: 'short' })).toContain(
      'ANTHROPIC_API_KEY',
    );
  });

  it('production needs the real rate limit store and the cron secret', () => {
    for (const name of [
      'UPSTASH_REDIS_REST_URL',
      'UPSTASH_REDIS_REST_TOKEN',
      'CRON_SECRET',
    ] as const) {
      const { [name]: _gone, ...rest } = PRODUCTION_ENV;
      expect(problems(rest), name).toContain(name);
    }
  });
});
