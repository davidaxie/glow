/**
 * Owner: B8. `DELETE /api/me`: every row, storage object and device token for this person,
 * then the auth user. In order:
 *
 * 1. Read what has to go: their card photos, profile photos (the rows and the storage
 *    folder), the matches that end for someone else, and the rooms they're in.
 * 2. Delete the photos from storage.
 * 3. Delete the rows. `card_views` that other people have of this person's cards aren't
 *    tied to them by a foreign key, so those go first; then the profile, which cascades to
 *    every other table (photos, devices, check-ins, taps, matches, messages, glows, blocks,
 *    reports, abuse signals, location checks, room days, admin rights).
 * 4. Delete the auth user (and with it their identities and sessions), then the entries
 *    Supabase Auth's audit log keeps about them (`forget_account_traces`, migration 0003).
 * 5. Tell the other person in each match (`match.ended`) and the rooms (`deck.changed`).
 *
 * Every step is idempotent, so a retry after a failure finishes the job. A storage failure
 * doesn't stop the deletion: those files have no row left that could serve them, and the
 * purge cron's orphan sweep deletes them within PURGE_INTERVAL.
 */
import { logger } from '@/server/log';
import { unavailable } from '@/server/http';
import { announceEnded, openRoomsOf } from './announce';
import { dbError, rpc, serviceDb } from './db';
import { objectsIn, removeObjects } from './storage';

function countOf(value: unknown, key: string): number {
  const n = (value as Record<string, unknown> | null)?.[key];
  return typeof n === 'number' ? n : 0;
}

export async function deleteAccountFor(userId: string): Promise<void> {
  const db = serviceDb();

  const [checkins, photos, matches, rooms, folder] = await Promise.all([
    db.from('checkins').select('id, card_path').eq('user_id', userId),
    db.from('profile_photos').select('path').eq('user_id', userId),
    db
      .from('matches')
      .select('id, user_a, user_b')
      .or(`user_a.eq.${userId},user_b.eq.${userId}`)
      .neq('status', 'ended'),
    openRoomsOf(userId),
    objectsIn('profile-photos', userId).catch(() => [] as string[]),
  ]);
  for (const result of [checkins, photos, matches]) {
    if (result.error) throw dbError('delete_account.read', result.error);
  }
  const cardIds = (checkins.data ?? []).map((c) => c.id);
  const cardPaths = (checkins.data ?? []).map((c) => c.card_path);
  const photoPaths = [...new Set([...(photos.data ?? []).map((p) => p.path), ...folder])];

  const [cardsRemoved, photosRemoved] = await Promise.all([
    removeObjects('room-cards', cardPaths),
    removeObjects('profile-photos', photoPaths),
  ]);

  if (cardIds.length > 0) {
    const views = await db.from('card_views').delete().in('checkin_id', cardIds);
    if (views.error) throw dbError('delete_account.card_views', views.error);
  }
  const profile = await db.from('profiles').delete().eq('id', userId);
  if (profile.error) throw dbError('delete_account.profile', profile.error);

  const auth = await db.auth.admin.deleteUser(userId);
  if (auth.error && auth.error.status !== 404) {
    logger.error('safety.delete_account_auth_failed', { status: auth.error.status ?? null });
    throw unavailable();
  }

  // Supabase Auth's audit log still names them (email, IP), including the deletion itself.
  // The account is already gone, so a failure here is logged, not returned: the purge cron's
  // audit retention (AUTH_AUDIT_RETENTION) removes those entries within days regardless.
  const traces = await rpc('forget_account_traces', { p_user_id: userId }).catch(() => {
    logger.error('safety.forget_traces_failed', {});
    return null;
  });

  logger.info('safety.delete_account', {
    cards: cardPaths.length,
    cardsRemoved,
    photos: photoPaths.length,
    photosRemoved,
    endedMatches: matches.data?.length ?? 0,
    rooms: rooms.length,
    auditEntries: countOf(traces, 'auditEntries'),
  });

  // Only the other person: the deleted person has no devices or channel left.
  await announceEnded({
    endedMatchIds: [],
    endedMatches: (matches.data ?? []).map((m) => ({
      id: m.id,
      userIds: [m.user_a === userId ? m.user_b : m.user_a],
    })),
    roomIds: rooms,
  });
}
