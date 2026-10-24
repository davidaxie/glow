/**
 * The `devices` store against the local database. Skips when no local Supabase is running.
 */
import { randomBytes } from 'node:crypto';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import {
  devicesFor,
  markDevicesOk,
  pruneDevices,
  registerDevice,
  removeDevice,
} from '@/server/notify/devices';
import { serviceDb } from '@/server/notify/db';
import {
  createPerson,
  deletePeople,
  localSupabaseIsUp,
  useLocalSupabase,
  type TestPerson,
} from './helpers/local-supabase';

const up = await localSupabaseIsUp();
const freshToken = () => randomBytes(32).toString('hex');

describe.skipIf(!up)('device store (local Supabase)', { timeout: 30_000 }, () => {
  let alex: TestPerson;
  let blake: TestPerson;

  beforeAll(async () => {
    useLocalSupabase();
    alex = await createPerson();
    blake = await createPerson();
  });
  afterAll(async () => {
    await deletePeople([alex, blake].filter(Boolean));
  });
  beforeEach(() => useLocalSupabase());

  it('registers a token, and registering it again keeps the same device', async () => {
    const token = freshToken();
    const first = await registerDevice(alex.id, {
      apnsToken: token,
      environment: 'sandbox',
      appVersion: '1.0 (1)',
    });
    const again = await registerDevice(alex.id, {
      apnsToken: token,
      environment: 'production',
      appVersion: '1.0 (2)',
    });
    expect(again.id).toBe(first.id);

    const { data } = await serviceDb().from('devices').select('*').eq('id', first.id).single();
    expect(data).toMatchObject({
      user_id: alex.id,
      apns_token: token,
      apns_environment: 'production',
      app_version: '1.0 (2)',
    });
  });

  it('moves a token to the person now signed in, under a new device ID', async () => {
    const token = freshToken();
    const alexDevice = await registerDevice(alex.id, { apnsToken: token, environment: 'sandbox' });
    const blakeDevice = await registerDevice(blake.id, {
      apnsToken: token,
      environment: 'sandbox',
    });

    expect(blakeDevice.id).not.toBe(alexDevice.id);
    expect((await devicesFor([alex.id])).map((d) => d.token)).not.toContain(token);
    expect(await devicesFor([blake.id])).toContainEqual({
      id: blakeDevice.id,
      token,
      environment: 'sandbox',
    });
    // Alex's old ID is gone, so Alex can't remove (or learn anything about) Blake's device.
    expect(await removeDevice(alex.id, alexDevice.id)).toBe(false);
    expect(await removeDevice(alex.id, blakeDevice.id)).toBe(false);
  });

  it('removes only your own device', async () => {
    const device = await registerDevice(alex.id, {
      apnsToken: freshToken(),
      environment: 'sandbox',
    });
    expect(await removeDevice(blake.id, device.id)).toBe(false);
    expect(await removeDevice(alex.id, device.id)).toBe(true);
    expect(await removeDevice(alex.id, device.id)).toBe(false);
  });

  it('lists everyone’s devices, prunes dead ones and marks good ones', async () => {
    const a = await registerDevice(alex.id, { apnsToken: freshToken(), environment: 'sandbox' });
    const b = await registerDevice(blake.id, {
      apnsToken: freshToken(),
      environment: 'production',
    });
    const listed = (await devicesFor([alex.id, blake.id])).map((d) => d.id);
    expect(listed).toEqual(expect.arrayContaining([a.id, b.id]));

    await markDevicesOk([a.id]);
    await pruneDevices([b.id]);
    const { data } = await serviceDb()
      .from('devices')
      .select('id, last_ok_at')
      .in('id', [a.id, b.id]);
    expect(data).toHaveLength(1);
    expect(data?.[0]?.id).toBe(a.id);
    expect(data?.[0]?.last_ok_at).toBeTruthy();
  });

  it('does nothing for empty lists', async () => {
    expect(await devicesFor([])).toEqual([]);
    await expect(pruneDevices([])).resolves.toBeUndefined();
    await expect(markDevicesOk([])).resolves.toBeUndefined();
  });
});
