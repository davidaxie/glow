/**
 * Owner: B8. Deleting photos from the private buckets, and the sweep that catches any photo
 * whose database row is gone (a storage call that failed, a crash between upload and row).
 *
 * Buckets (docs/CONTRACTS.md): `room-cards/{roomId}/{cardId}.jpg` and
 * `profile-photos/{userId}/{photoId}.jpg`. A photo is an orphan when no `checkins.card_path`
 * or `profile_photos.path` names it. Orphans younger than ORPHAN_GRACE_SECONDS are left alone,
 * because B3 and B1 upload the photo a moment before they write its row.
 */
import { logger } from '@/server/log';
import { serviceDb } from './db';

export type Bucket = 'room-cards' | 'profile-photos';

export const ORPHAN_GRACE_SECONDS = 120;
const REMOVE_BATCH = 100;
const LIST_PAGE = 1000;
const IN_BATCH = 200;
/** Caps per sweep, so one run stays quick however much is stored. */
const MAX_FOLDERS = 500;
const MAX_OBJECTS_PER_FOLDER = 5000;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function chunks<T>(items: readonly T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += size) out.push(items.slice(i, i + size));
  return out;
}

/** Deletes objects; returns how many are gone. Failures are logged, never thrown. */
export async function removeObjects(bucket: Bucket, paths: readonly string[]): Promise<number> {
  const unique = [...new Set(paths)];
  let removed = 0;
  for (const batch of chunks(unique, REMOVE_BATCH)) {
    const { data, error } = await serviceDb().storage.from(bucket).remove(batch);
    if (error) {
      logger.error('safety.storage_remove_failed', { bucket, objects: batch.length });
      continue;
    }
    removed += data?.length ?? 0;
  }
  return removed;
}

type Listed = { readonly name: string; readonly createdAt: number | null; readonly folder: boolean };

/** Lists one level of a bucket. Folders come back with no id. */
async function list(bucket: Bucket, prefix: string, max: number): Promise<Listed[]> {
  const out: Listed[] = [];
  for (let offset = 0; offset < max; offset += LIST_PAGE) {
    const { data, error } = await serviceDb()
      .storage.from(bucket)
      .list(prefix, { limit: LIST_PAGE, offset, sortBy: { column: 'name', order: 'asc' } });
    if (error) throw new Error(`list ${bucket} failed`);
    for (const item of data) {
      out.push({
        name: item.name,
        createdAt: item.created_at ? Date.parse(item.created_at) : null,
        folder: item.id === null,
      });
    }
    if (data.length < LIST_PAGE) break;
  }
  return out;
}

/** Every object under `{folder}/`, as full paths. */
export async function objectsIn(bucket: Bucket, folder: string): Promise<string[]> {
  const items = await list(bucket, folder, MAX_OBJECTS_PER_FOLDER);
  return items.filter((i) => !i.folder).map((i) => `${folder}/${i.name}`);
}

/** Which of `values` exist in `table.column`. */
async function existing(
  table: 'checkins' | 'profile_photos' | 'profiles',
  column: 'card_path' | 'path' | 'id',
  values: readonly string[],
): Promise<Set<string>> {
  const found = new Set<string>();
  for (const batch of chunks(values, IN_BATCH)) {
    const { data, error } = await serviceDb()
      .from(table)
      .select(column)
      .in(column, batch as string[]);
    if (error || !data) throw new Error(`lookup in ${table} failed`);
    for (const row of data as unknown as Record<string, string>[]) {
      const value = row[column];
      if (value) found.add(value);
    }
  }
  return found;
}

export type SweepResult = { readonly cardPhotos: number; readonly profilePhotos: number };

/** Deletes orphaned photos in both buckets. Best effort: failures are logged. */
export async function sweepOrphans(now = Date.now()): Promise<SweepResult> {
  const cutoff = now - ORPHAN_GRACE_SECONDS * 1000;
  const old = (item: Listed) => item.createdAt !== null && item.createdAt < cutoff;
  let cardPhotos = 0;
  let profilePhotos = 0;

  try {
    const rooms = (await list('room-cards', '', MAX_FOLDERS)).filter(
      (i) => i.folder && UUID.test(i.name),
    );
    for (const room of rooms) {
      const items = (await list('room-cards', room.name, MAX_OBJECTS_PER_FOLDER)).filter(
        (i) => !i.folder && old(i),
      );
      if (items.length === 0) continue;
      const paths = items.map((i) => `${room.name}/${i.name}`);
      const kept = await existing('checkins', 'card_path', paths);
      cardPhotos += await removeObjects(
        'room-cards',
        paths.filter((p) => !kept.has(p)),
      );
    }
  } catch (error) {
    logger.error('safety.sweep_failed', { bucket: 'room-cards', cause: errorName(error) });
  }

  try {
    const people = (await list('profile-photos', '', MAX_FOLDERS)).filter(
      (i) => i.folder && UUID.test(i.name),
    );
    const alive = await existing(
      'profiles',
      'id',
      people.map((p) => p.name),
    );
    for (const person of people) {
      const items = (await list('profile-photos', person.name, MAX_OBJECTS_PER_FOLDER)).filter(
        (i) => !i.folder && old(i),
      );
      if (items.length === 0) continue;
      const paths = items.map((i) => `${person.name}/${i.name}`);
      const kept = alive.has(person.name)
        ? await existing('profile_photos', 'path', paths)
        : new Set<string>();
      profilePhotos += await removeObjects(
        'profile-photos',
        paths.filter((p) => !kept.has(p)),
      );
    }
  } catch (error) {
    logger.error('safety.sweep_failed', { bucket: 'profile-photos', cause: errorName(error) });
  }

  return { cardPhotos, profilePhotos };
}

function errorName(error: unknown): string {
  return error instanceof Error ? error.name : typeof error;
}
