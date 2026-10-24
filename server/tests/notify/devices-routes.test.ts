/**
 * `POST /api/devices` and `DELETE /api/devices/{id}` through the real route helper and the
 * generated contract, with the device store mocked.
 */
import { NextRequest } from 'next/server';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { DELETE } from '../../app/api/devices/[id]/route';
import { POST } from '../../app/api/devices/route';
import { fakeAccessToken, mockVerify, USER_ID } from '../helpers/auth';

vi.mock('@/server/auth/verify', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@/server/auth/verify')>();
  return { ...actual, verifyAccessToken: vi.fn() };
});
vi.mock('@/server/notify/devices', () => ({
  registerDevice: vi.fn(),
  removeDevice: vi.fn(),
}));
const devices = await import('@/server/notify/devices');

const DEVICE = 'd0000000-0000-4000-8000-000000000001';
const TOKEN = 'ab'.repeat(32);

function post(body: unknown, token: string | null = fakeAccessToken()) {
  const req = new NextRequest('http://localhost/api/devices', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify(body),
  });
  return POST(req, { params: Promise.resolve({}) });
}

function del(id: string, token: string | null = fakeAccessToken()) {
  const req = new NextRequest(`http://localhost/api/devices/${id}`, {
    method: 'DELETE',
    headers: token ? { authorization: `Bearer ${token}` } : {},
  });
  return DELETE(req, { params: Promise.resolve({ id }) });
}

const logs: string[] = [];
beforeEach(async () => {
  logs.length = 0;
  for (const write of ['log', 'warn', 'error'] as const) {
    vi.spyOn(console, write).mockImplementation((line: unknown) => void logs.push(String(line)));
  }
  await mockVerify();
  vi.mocked(devices.registerDevice).mockResolvedValue({ id: DEVICE });
  vi.mocked(devices.removeDevice).mockResolvedValue(true);
});

describe('POST /api/devices', () => {
  it('registers the token for the signed-in person', async () => {
    const res = await post({ apnsToken: TOKEN, environment: 'sandbox', appVersion: '1.0 (42)' });
    expect(res.status).toBe(201);
    expect(await res.json()).toEqual({ id: DEVICE });
    expect(res.headers.get('cache-control')).toContain('no-store');
    expect(devices.registerDevice).toHaveBeenCalledWith(USER_ID, {
      apnsToken: TOKEN,
      environment: 'sandbox',
      appVersion: '1.0 (42)',
    });
  });

  it('never logs the token', async () => {
    await post({ apnsToken: TOKEN, environment: 'production' });
    expect(logs.join('\n')).not.toContain(TOKEN);
  });

  it.each([
    { apnsToken: 'AB'.repeat(32), environment: 'sandbox' },
    { apnsToken: 'ab'.repeat(10), environment: 'sandbox' },
    { apnsToken: TOKEN, environment: 'staging' },
    { apnsToken: TOKEN },
    { apnsToken: TOKEN, environment: 'sandbox', appVersion: 'x'.repeat(33) },
  ])('refuses a malformed registration: %j', async (body) => {
    const res = await post(body);
    expect(res.status).toBe(400);
    expect(devices.registerDevice).not.toHaveBeenCalled();
  });

  it('ignores fields the contract doesn’t have, like someone else’s user ID', async () => {
    const other = '7e570000-0000-4000-8000-00000000000b';
    const res = await post({ apnsToken: TOKEN, environment: 'sandbox', userId: other });
    expect(res.status).toBe(201);
    expect(devices.registerDevice).toHaveBeenCalledWith(USER_ID, {
      apnsToken: TOKEN,
      environment: 'sandbox',
    });
  });

  it('needs sign-in', async () => {
    const res = await post({ apnsToken: TOKEN, environment: 'sandbox' }, null);
    expect(res.status).toBe(401);
    expect(devices.registerDevice).not.toHaveBeenCalled();
  });
});

describe('DELETE /api/devices/{id}', () => {
  it('removes one of your devices', async () => {
    const res = await del(DEVICE);
    expect(res.status).toBe(204);
    expect(devices.removeDevice).toHaveBeenCalledWith(USER_ID, DEVICE);
  });

  it('answers 404 for someone else’s device, exactly like a missing one (P11)', async () => {
    vi.mocked(devices.removeDevice).mockResolvedValue(false);
    const theirs = await del(DEVICE);
    const missing = await del('d0000000-0000-4000-8000-0000000000ff');
    expect(theirs.status).toBe(404);
    expect(missing.status).toBe(404);
    expect(await theirs.json()).toEqual(await missing.json());
  });

  it('answers 404 for a malformed ID without touching the store', async () => {
    const res = await del('not-a-uuid');
    expect(res.status).toBe(404);
    expect(devices.removeDevice).not.toHaveBeenCalled();
  });

  it('needs sign-in', async () => {
    expect((await del(DEVICE, null)).status).toBe(401);
  });
});
