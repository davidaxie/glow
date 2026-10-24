/**
 * Push tokens, one row per phone in `devices`. Only the server reads or writes them.
 *
 * - Registering a token that already exists moves it to the signed-in person. If it belonged
 *   to someone else, the old row is deleted and the person gets a fresh device ID, so two
 *   accounts on one phone can't be linked through the ID (B5-D3).
 * - Removing a device that isn't yours is the same 404 as one that doesn't exist (P11).
 * - Tokens Apple rejects are pruned by the push sender.
 */
import type { ApnsEnvironment, DeviceRegistration } from '@/contracts';
import { serviceDb } from './db';

export type DeviceTarget = {
  readonly id: string;
  readonly token: string;
  readonly environment: ApnsEnvironment;
};

/** A database failure, carrying only the operation and Postgres code (never values). */
export class DeviceStoreError extends Error {
  override readonly name = 'DeviceStoreError';
  constructor(
    readonly operation: string,
    readonly code: string | undefined,
  ) {
    super(`devices.${operation} failed${code ? ` (${code})` : ''}`);
  }
}

export async function registerDevice(
  userId: string,
  registration: DeviceRegistration,
): Promise<{ readonly id: string }> {
  const db = serviceDb();
  const token = registration.apnsToken.toLowerCase();

  const moved = await db.from('devices').delete().eq('apns_token', token).neq('user_id', userId);
  if (moved.error) throw new DeviceStoreError('register', moved.error.code);

  const { data, error } = await db
    .from('devices')
    .upsert(
      {
        user_id: userId,
        apns_token: token,
        apns_environment: registration.environment,
        app_version: registration.appVersion ?? null,
      },
      { onConflict: 'apns_token' },
    )
    .select('id')
    .single();
  if (error || !data) throw new DeviceStoreError('register', error?.code);
  return { id: data.id };
}

/** Deletes one of this person's devices. False if there's no such device of theirs. */
export async function removeDevice(userId: string, deviceId: string): Promise<boolean> {
  const { data, error } = await serviceDb()
    .from('devices')
    .delete()
    .eq('id', deviceId)
    .eq('user_id', userId)
    .select('id');
  if (error) throw new DeviceStoreError('remove', error.code);
  return (data ?? []).length > 0;
}

/** Every registered device of these people. */
export async function devicesFor(userIds: readonly string[]): Promise<DeviceTarget[]> {
  if (userIds.length === 0) return [];
  const { data, error } = await serviceDb()
    .from('devices')
    .select('id, apns_token, apns_environment')
    .in('user_id', [...userIds]);
  if (error) throw new DeviceStoreError('list', error.code);
  return (data ?? []).map((row) => ({
    id: row.id,
    token: row.apns_token,
    environment: row.apns_environment,
  }));
}

/** Deletes devices whose tokens Apple says are dead. */
export async function pruneDevices(deviceIds: readonly string[]): Promise<void> {
  if (deviceIds.length === 0) return;
  const { error } = await serviceDb()
    .from('devices')
    .delete()
    .in('id', [...deviceIds]);
  if (error) throw new DeviceStoreError('prune', error.code);
}

/** Records that Apple accepted a push for these devices. */
export async function markDevicesOk(deviceIds: readonly string[]): Promise<void> {
  if (deviceIds.length === 0) return;
  const { error } = await serviceDb()
    .from('devices')
    .update({ last_ok_at: new Date().toISOString() })
    .in('id', [...deviceIds]);
  if (error) throw new DeviceStoreError('mark_ok', error.code);
}
