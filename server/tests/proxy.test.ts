import { NextRequest } from 'next/server';
import { describe, expect, it } from 'vitest';
import { resetEnvCacheForTests } from '@/env';
import { proxy } from '../proxy';

const devRequest = () => new NextRequest('http://localhost/api/dev/test-login', { method: 'POST' });

describe('proxy', () => {
  it('hides dev routes behind a 404 unless test sign-in is on', async () => {
    const res = proxy(devRequest());
    expect(res.status).toBe(404);
    expect(await res.json()).toEqual({ error: { code: 'not_found', message: 'Not found.' } });
  });

  it('lets dev routes through locally when ALLOW_TEST_LOGIN is on', () => {
    process.env.ALLOW_TEST_LOGIN = '1';
    resetEnvCacheForTests();
    const res = proxy(devRequest());
    expect(res.headers.get('x-middleware-next')).toBe('1');
  });
});
