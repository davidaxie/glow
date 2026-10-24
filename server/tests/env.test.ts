import { describe, expect, it } from 'vitest';
import {
  EnvError,
  REQUIRED_IN,
  detectProfile,
  formatEnvProblems,
  getEnv,
  parseEnv,
  resetEnvCacheForTests,
} from '@/env';
import { LOCAL_ENV, PRODUCTION_ENV } from './helpers/env';

const problemsOf = (source: Record<string, string | undefined>) => {
  const result = parseEnv(source);
  return result.ok ? [] : result.problems;
};
const names = (source: Record<string, string | undefined>) => problemsOf(source).map((p) => p.name);

describe('profiles', () => {
  it('is local unless Vercel says otherwise', () => {
    expect(detectProfile({})).toBe('local');
    expect(detectProfile({ VERCEL_ENV: 'development' })).toBe('local');
    expect(detectProfile({ VERCEL: '1', VERCEL_ENV: 'preview' })).toBe('preview');
    expect(detectProfile({ VERCEL: '1', VERCEL_ENV: 'production' })).toBe('production');
  });

  it('treats an unknown Vercel environment as a preview, the stricter of the two', () => {
    expect(detectProfile({ VERCEL: '1' })).toBe('preview');
  });
});

describe('local', () => {
  it('accepts the local Supabase keys and generated secrets alone', () => {
    const result = parseEnv(LOCAL_ENV);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.env.profile).toBe('local');
      expect(result.env.ALLOW_TEST_LOGIN).toBe(false);
      expect(result.env.ANTHROPIC_API_KEY).toBeUndefined();
    }
  });

  it.each(Object.keys(LOCAL_ENV))('stops when %s is missing', (name) => {
    expect(names({ ...LOCAL_ENV, [name]: undefined })).toEqual([name]);
  });

  it('treats a blank value as missing, like a freshly copied .env.example', () => {
    expect(names({ ...LOCAL_ENV, SUPABASE_URL: '   ' })).toEqual(['SUPABASE_URL']);
  });

  it('accepts the .env.example placeholders locally', () => {
    const result = parseEnv({
      ...LOCAL_ENV,
      JOIN_TICKET_SECRET: 'local-dev-only-join-ticket-secret-replace-me-0001',
    });
    expect(result.ok).toBe(true);
  });

  it('rejects secrets shorter than 32 random bytes', () => {
    expect(names({ ...LOCAL_ENV, JOIN_TICKET_SECRET: 'too-short' })).toEqual([
      'JOIN_TICKET_SECRET',
    ]);
  });

  it('rejects reusing one secret for two jobs', () => {
    expect(names({ ...LOCAL_ENV, CARD_URL_SECRET: LOCAL_ENV.JOIN_TICKET_SECRET })).toEqual([
      'CARD_URL_SECRET',
    ]);
  });

  it('catches the service key pasted where the anon key goes', () => {
    expect(
      names({ ...LOCAL_ENV, SUPABASE_ANON_KEY: 'sb_secret_aaaaaaaaaaaaaaaaaaaaaa' }),
    ).toContain('SUPABASE_ANON_KEY');
    const serviceJwt = `x.${Buffer.from(JSON.stringify({ role: 'service_role' })).toString('base64url')}.y`;
    expect(names({ ...LOCAL_ENV, SUPABASE_ANON_KEY: `${serviceJwt}padpadpadpad` })).toContain(
      'SUPABASE_ANON_KEY',
    );
  });

  it('catches the anon key pasted where the service key goes', () => {
    expect(
      names({ ...LOCAL_ENV, SUPABASE_SERVICE_ROLE_KEY: LOCAL_ENV.SUPABASE_ANON_KEY }),
    ).toContain('SUPABASE_SERVICE_ROLE_KEY');
  });

  it('wants all four Apple push variables or none', () => {
    expect(names({ ...LOCAL_ENV, APNS_KEY_ID: 'ABC123DEFG' }).sort()).toEqual([
      'APNS_BUNDLE_ID',
      'APNS_PRIVATE_KEY',
      'APNS_TEAM_ID',
    ]);
  });

  it('turns escaped newlines in the .p8 key into real ones', () => {
    const result = parseEnv({
      ...LOCAL_ENV,
      APNS_KEY_ID: PRODUCTION_ENV.APNS_KEY_ID,
      APNS_TEAM_ID: PRODUCTION_ENV.APNS_TEAM_ID,
      APNS_PRIVATE_KEY: PRODUCTION_ENV.APNS_PRIVATE_KEY,
      APNS_BUNDLE_ID: PRODUCTION_ENV.APNS_BUNDLE_ID,
    });
    expect(result.ok && result.env.APNS_PRIVATE_KEY).toBe(
      '-----BEGIN PRIVATE KEY-----\nTESTKEYTESTKEY\n-----END PRIVATE KEY-----',
    );
  });

  it('allows test sign-in only against a local Supabase', () => {
    expect(parseEnv({ ...LOCAL_ENV, ALLOW_TEST_LOGIN: '1' }).ok).toBe(true);
    expect(
      names({
        ...LOCAL_ENV,
        ALLOW_TEST_LOGIN: '1',
        SUPABASE_URL: 'https://abcdefghijklmnop.supabase.co',
      }),
    ).toEqual(['ALLOW_TEST_LOGIN']);
  });

  it('accepts the optional app link settings and checks their shape', () => {
    const ok = parseEnv({
      ...LOCAL_ENV,
      TESTFLIGHT_URL: 'https://testflight.apple.com/join/AbCdEf12',
      APPLE_APP_ID: 'ABCDE12345.com.davidxie.glow',
    });
    expect(ok.ok && ok.env.TESTFLIGHT_URL).toBe('https://testflight.apple.com/join/AbCdEf12');
    expect(ok.ok && ok.env.APPLE_APP_ID).toBe('ABCDE12345.com.davidxie.glow');
    expect(names({ ...LOCAL_ENV, TESTFLIGHT_URL: 'https://example.com/join/x' })).toEqual([
      'TESTFLIGHT_URL',
    ]);
    expect(names({ ...LOCAL_ENV, APPLE_APP_ID: 'com.davidxie.glow' })).toEqual(['APPLE_APP_ID']);
    expect(REQUIRED_IN.TESTFLIGHT_URL).toBeUndefined();
    expect(REQUIRED_IN.APPLE_APP_ID).toBeUndefined();
  });

  it('rejects an ALLOW_TEST_LOGIN value that might be misread', () => {
    expect(names({ ...LOCAL_ENV, ALLOW_TEST_LOGIN: 'yes' })).toEqual(['ALLOW_TEST_LOGIN']);
  });
});

describe('Vercel', () => {
  it('accepts a complete production env', () => {
    const result = parseEnv(PRODUCTION_ENV);
    expect(result.ok).toBe(true);
    expect(result.ok && result.env.profile).toBe('production');
  });

  it('needs moderation and rate limits on previews, but not Apple push', () => {
    const preview = {
      ...PRODUCTION_ENV,
      VERCEL_ENV: 'preview',
      APNS_KEY_ID: undefined,
      APNS_TEAM_ID: undefined,
      APNS_PRIVATE_KEY: undefined,
      APNS_BUNDLE_ID: undefined,
    };
    expect(parseEnv(preview).ok).toBe(true);
    expect(names({ ...preview, ANTHROPIC_API_KEY: undefined })).toEqual(['ANTHROPIC_API_KEY']);
    expect(names({ ...preview, UPSTASH_REDIS_REST_TOKEN: undefined })).toEqual([
      'UPSTASH_REDIS_REST_TOKEN',
    ]);
  });

  it('needs Apple push in production', () => {
    expect(names({ ...PRODUCTION_ENV, APNS_TEAM_ID: undefined })).toEqual(['APNS_TEAM_ID']);
  });

  it('refuses ALLOW_TEST_LOGIN on Vercel', () => {
    expect(names({ ...PRODUCTION_ENV, ALLOW_TEST_LOGIN: 'true' })).toContain('ALLOW_TEST_LOGIN');
  });

  it('refuses a local Supabase URL', () => {
    expect(names({ ...PRODUCTION_ENV, SUPABASE_URL: 'http://127.0.0.1:54421' })).toContain(
      'SUPABASE_URL',
    );
  });

  it('refuses the placeholder secrets from .env.example', () => {
    expect(
      names({
        ...PRODUCTION_ENV,
        CRON_SECRET: 'local-dev-only-cron-secret-replace-me-000000000000003',
      }),
    ).toEqual(['CRON_SECRET']);
  });

  it('refuses the local Supabase demo JWT keys', () => {
    const demo = `eyJhbGciOiJIUzI1NiJ9.${Buffer.from(JSON.stringify({ iss: 'supabase-demo', role: 'anon' })).toString('base64url')}.signature`;
    expect(names({ ...PRODUCTION_ENV, SUPABASE_ANON_KEY: demo })).toContain('SUPABASE_ANON_KEY');
  });

  it('lists every requirement for every variable', () => {
    expect(REQUIRED_IN.SUPABASE_SERVICE_ROLE_KEY).toEqual(['local', 'preview', 'production']);
    expect(REQUIRED_IN.ANTHROPIC_API_KEY).toEqual(['preview', 'production']);
    expect(REQUIRED_IN.APNS_PRIVATE_KEY).toEqual(['production']);
    expect(REQUIRED_IN.SENTRY_DSN).toBeUndefined();
    expect(REQUIRED_IN.ALLOW_TEST_LOGIN).toBeUndefined();
  });
});

describe('the stop message', () => {
  it('names each variable and never prints a value', () => {
    const secretValue = 'this-is-a-value-that-must-not-be-printed';
    const result = parseEnv({
      ...LOCAL_ENV,
      SUPABASE_ANON_KEY: undefined,
      CRON_SECRET: secretValue.slice(0, 10),
    });
    expect(result.ok).toBe(false);
    if (result.ok) return;
    const message = formatEnvProblems(result.profile, result.problems);
    expect(message).toContain("Glow server can't start: 2 environment variables need fixing");
    expect(message).toContain('SUPABASE_ANON_KEY');
    expect(message).toContain('CRON_SECRET');
    expect(message).toContain('pnpm env:setup');
    expect(message).not.toContain(secretValue.slice(0, 10));
    for (const value of Object.values(LOCAL_ENV)) expect(message).not.toContain(value);
  });

  it('getEnv throws an EnvError carrying that message', () => {
    delete process.env.SUPABASE_URL;
    resetEnvCacheForTests();
    expect(() => getEnv()).toThrow(EnvError);
    expect(() => getEnv()).toThrow(/SUPABASE_URL\s+is missing/);
  });
});
