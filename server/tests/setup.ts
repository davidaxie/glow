import { beforeEach } from 'vitest';
import { resetEnvCacheForTests } from '@/env';
import { LOCAL_ENV } from './helpers/env';

// Every test starts from a clean, valid local env and no cached getEnv().
beforeEach(() => {
  for (const key of Object.keys(process.env)) {
    if (key in LOCAL_ENV || key.startsWith('APNS_') || key.startsWith('UPSTASH_')) {
      delete process.env[key];
    }
  }
  delete process.env.VERCEL;
  delete process.env.VERCEL_ENV;
  delete process.env.SENTRY_DSN;
  delete process.env.ALLOW_TEST_LOGIN;
  Object.assign(process.env, LOCAL_ENV);
  resetEnvCacheForTests();
});
