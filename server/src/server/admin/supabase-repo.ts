/**
 * The live AdminRepo: plain table reads and writes with the service role, plus `unmatch`.
 * Times from PostgREST arrive as `+00:00`; everything leaving here is `toISOString()` (the
 * contract's `...000Z` form).
 */
import type { CardTags, Database } from '@/contracts';
import { serviceDb, type Db } from './db';
import {
  RepoConflict,
  type ActivityTotals,
  type AdminRepo,
  type CardRecord,
  type NewRoom,
  type PhotoRecord,
  type ReportRecord,
  type RoomPatch,
  type RoomRecord,
} from './repo';

type Tables = Database['public']['Tables'];
type RoomRow = Tables['rooms']['Row'];
type SpotRow = Pick<Tables['meeting_spots']['Row'], 'id' | 'name' | 'sort'>;
type CheckinRow = Tables['checkins']['Row'];
type ReportRow = Tables['reports']['Row'];

const iso = (value: string) => new Date(value).toISOString();
const PAGE = 1000;
const CARDS_BUCKET = 'room-cards';
const PHOTOS_BUCKET = 'profile-photos';
const PHOTO_COLUMNS =
  'id, user_id, path, position, moderation_status, created_at, profiles (viewer_code)';

type PhotoRow = Pick<
  Tables['profile_photos']['Row'],
  'id' | 'user_id' | 'path' | 'position' | 'moderation_status' | 'created_at'
> & { profiles: { viewer_code: string } | null };

function toPhoto(row: PhotoRow): PhotoRecord {
  return {
    id: row.id,
    userId: row.user_id,
    path: row.path,
    position: row.position,
    moderationStatus: row.moderation_status,
    createdAt: iso(row.created_at),
    viewerCode: row.profiles?.viewer_code ?? '',
  };
}

const ROOM_COLUMNS =
  'id, slug, name, code, lat, lng, radius_m, timezone, qr_secret, static_qr_token, allow_static_qr, demo_mode, status, starts_at, ends_at, created_at, meeting_spots (id, name, sort)';

const CARD_COLUMNS =
  'id, room_id, user_id, card_path, top_color, hair_length, hair_color, extras, visible, joined_at, expires_at, left_at, profiles (viewer_code)';

const REPORT_COLUMNS =
  'id, reporter_id, reported_id, room_id, context, context_id, reason, details, evidence, status, created_at, reporter:profiles!reports_reporter_id_fkey (viewer_code), reported:profiles!reports_reported_id_fkey (viewer_code)';

type RoomWithSpots = Omit<RoomRow, 'updated_at'> & { meeting_spots: SpotRow[] | null };
type CheckinWithCode = Omit<CheckinRow, 'expiry_warned_at'> & {
  profiles: { viewer_code: string } | null;
};
type ReportWithCodes = Omit<ReportRow, 'resolved_at' | 'resolved_by'> & {
  reporter: { viewer_code: string } | null;
  reported: { viewer_code: string } | null;
};

/** A supabase-js error, minus what we don't need. */
type PgError = { code?: string; message: string; details?: string | null } | null;

class RepoError extends Error {
  override readonly name = 'RepoError';
  constructor(operation: string, error: NonNullable<PgError>) {
    // The code and constraint only: never row values, which can hold personal data.
    super(`${operation} failed (${error.code ?? 'unknown'})`);
  }
}

function check(operation: string, error: PgError): void {
  if (error) throw new RepoError(operation, error);
}

function toRoom(row: RoomWithSpots): RoomRecord {
  return {
    id: row.id,
    slug: row.slug,
    name: row.name,
    code: row.code,
    latitude: row.lat,
    longitude: row.lng,
    radiusM: row.radius_m,
    timezone: row.timezone,
    qrSecret: row.qr_secret,
    staticQrToken: row.static_qr_token,
    allowStaticQr: row.allow_static_qr,
    demoMode: row.demo_mode,
    status: row.status,
    startsAt: iso(row.starts_at),
    endsAt: iso(row.ends_at),
    createdAt: iso(row.created_at),
    spots: [...(row.meeting_spots ?? [])]
      .sort((a, b) => a.sort - b.sort)
      .map((s) => ({ id: s.id, name: s.name, sort: s.sort })),
  };
}

function toTags(row: CheckinWithCode): CardTags {
  return {
    topColor: row.top_color,
    ...(row.hair_length ? { hairLength: row.hair_length } : {}),
    ...(row.hair_color ? { hairColor: row.hair_color } : {}),
    extras: [...row.extras],
  };
}

function toCard(row: CheckinWithCode): CardRecord {
  return {
    id: row.id,
    roomId: row.room_id,
    userId: row.user_id,
    cardPath: row.card_path,
    tags: toTags(row),
    visible: row.visible,
    joinedAt: iso(row.joined_at),
    expiresAt: iso(row.expires_at),
    leftAt: row.left_at ? iso(row.left_at) : null,
    viewerCode: row.profiles?.viewer_code ?? '',
  };
}

function toReport(row: ReportWithCodes): ReportRecord {
  const evidence = Array.isArray(row.evidence) ? row.evidence : [];
  return {
    id: row.id,
    reporterId: row.reporter_id,
    reportedId: row.reported_id,
    roomId: row.room_id,
    context: row.context,
    contextId: row.context_id,
    reason: row.reason,
    details: row.details,
    evidence: evidence.flatMap((item) => {
      if (typeof item !== 'object' || item === null || Array.isArray(item)) return [];
      const { body, createdAt } = item as { body?: unknown; createdAt?: unknown };
      return typeof body === 'string' && typeof createdAt === 'string'
        ? [{ body, createdAt: iso(createdAt) }]
        : [];
    }),
    status: row.status,
    createdAt: iso(row.created_at),
    reporterViewerCode: row.reporter?.viewer_code ?? '',
    reportedViewerCode: row.reported?.viewer_code ?? '',
  };
}

function roomPatchRow(patch: RoomPatch): Tables['rooms']['Update'] {
  const row: Tables['rooms']['Update'] = {};
  if (patch.name !== undefined) row.name = patch.name;
  if (patch.latitude !== undefined) row.lat = patch.latitude;
  if (patch.longitude !== undefined) row.lng = patch.longitude;
  if (patch.radiusM !== undefined) row.radius_m = patch.radiusM;
  if (patch.timezone !== undefined) row.timezone = patch.timezone;
  if (patch.allowStaticQr !== undefined) row.allow_static_qr = patch.allowStaticQr;
  if (patch.demoMode !== undefined) row.demo_mode = patch.demoMode;
  if (patch.status !== undefined) row.status = patch.status;
  if (patch.startsAt !== undefined) row.starts_at = patch.startsAt;
  if (patch.endsAt !== undefined) row.ends_at = patch.endsAt;
  return row;
}

function conflictOf(error: PgError): RepoConflict | null {
  if (!error) return null;
  const text = `${error.message} ${error.details ?? ''}`;
  if (error.code === '23505') {
    if (text.includes('rooms_slug_key')) return new RepoConflict('slug');
    if (text.includes('rooms_code_key')) return new RepoConflict('code');
    if (text.includes('rooms_static_qr_token_key')) return new RepoConflict('static_token');
  }
  if (error.code === '23514') return new RepoConflict('check');
  return null;
}

export function supabaseRepo(db: Db = serviceDb()): AdminRepo {
  const nowIso = () => new Date().toISOString();

  async function findRoom(by: { id: string } | { slug: string }): Promise<RoomRecord | null> {
    const query = db.from('rooms').select(ROOM_COLUMNS);
    const { data, error } = await (
      'id' in by ? query.eq('id', by.id) : query.eq('slug', by.slug)
    ).maybeSingle<RoomWithSpots>();
    check('rooms.find', error);
    return data ? toRoom(data) : null;
  }

  const selectCards = () => db.from('checkins').select(CARD_COLUMNS);
  type CardQuery = ReturnType<typeof selectCards>;

  async function cardsWhere(build: (q: CardQuery) => CardQuery): Promise<CardRecord[]> {
    const { data, error } = await build(selectCards());
    check('checkins.select', error);
    return ((data ?? []) as unknown as CheckinWithCode[]).map(toCard);
  }

  return {
    async isAdmin(userId) {
      const { data, error } = await db
        .from('admins')
        .select('user_id, profiles!inner (banned_at)')
        .eq('user_id', userId)
        .is('profiles.banned_at', null)
        .maybeSingle();
      check('admins.find', error);
      return data !== null;
    },

    async viewerCode(userId) {
      const { data, error } = await db
        .from('profiles')
        .select('viewer_code')
        .eq('id', userId)
        .maybeSingle();
      check('profiles.viewer_code', error);
      return data?.viewer_code ?? null;
    },

    async listRooms() {
      const { data, error } = await db
        .from('rooms')
        .select(ROOM_COLUMNS)
        .order('created_at', { ascending: false })
        .returns<RoomWithSpots[]>();
      check('rooms.list', error);
      return (data ?? []).map(toRoom);
    },

    findRoom,

    async createRoom(room: NewRoom, spots) {
      // The code is the database's random default. Retry once on the (1 in a billion) clash.
      for (let attempt = 0; attempt < 2; attempt++) {
        const { data, error } = await db
          .from('rooms')
          .insert({
            slug: room.slug,
            name: room.name,
            lat: room.latitude,
            lng: room.longitude,
            radius_m: room.radiusM,
            timezone: room.timezone,
            allow_static_qr: room.allowStaticQr,
            demo_mode: room.demoMode,
            starts_at: room.startsAt,
            ends_at: room.endsAt,
          })
          .select('id')
          .single();
        const conflict = conflictOf(error);
        if (conflict?.what === 'code' && attempt === 0) continue;
        if (conflict) throw conflict;
        check('rooms.insert', error);
        const id = data!.id;
        const { error: spotsError } = await db
          .from('meeting_spots')
          .insert(spots.map((name, sort) => ({ room_id: id, name, sort })));
        if (spotsError) {
          // Leave nothing half made.
          await db.from('rooms').delete().eq('id', id);
          check('meeting_spots.insert', spotsError);
        }
        const created = await findRoom({ id });
        if (!created) throw new Error('rooms.insert: the new room vanished');
        return created;
      }
      throw new RepoConflict('code');
    },

    async updateRoom(id, patch) {
      const row = roomPatchRow(patch);
      if (Object.keys(row).length > 0) {
        const { data, error } = await db.from('rooms').update(row).eq('id', id).select('id');
        const conflict = conflictOf(error);
        if (conflict) throw conflict;
        check('rooms.update', error);
        if (!data || data.length === 0) return null;
      }
      return findRoom({ id });
    },

    async replaceSpots(roomId, names) {
      const room = await findRoom({ id: roomId });
      if (!room) return null;
      const existing = room.spots;
      // Park every existing spot on a negative sort first, so renumbering can't collide with
      // the unique (room_id, sort) constraint. IDs stay, so an active glow keeps its spot.
      for (const [i, spot] of existing.entries()) {
        const { error } = await db
          .from('meeting_spots')
          .update({ sort: -1 - i })
          .eq('id', spot.id);
        check('meeting_spots.park', error);
      }
      for (const [sort, name] of names.entries()) {
        const keep = existing[sort];
        const { error } = keep
          ? await db.from('meeting_spots').update({ name, sort }).eq('id', keep.id)
          : await db.from('meeting_spots').insert({ room_id: roomId, name, sort });
        check('meeting_spots.write', error);
      }
      const extra = existing.slice(names.length).map((s) => s.id);
      if (extra.length > 0) {
        // A glow using a removed spot keeps going without one (spot_id is set null).
        const { error } = await db.from('meeting_spots').delete().in('id', extra);
        check('meeting_spots.delete', error);
      }
      return findRoom({ id: roomId });
    },

    async setStaticToken(roomId, token) {
      const { data, error } = await db
        .from('rooms')
        .update({ static_qr_token: token })
        .eq('id', roomId)
        .select('id');
      const conflict = conflictOf(error);
      if (conflict) throw conflict;
      check('rooms.static_token', error);
      if (!data || data.length === 0) return null;
      return findRoom({ id: roomId });
    },

    openCards(roomId) {
      return cardsWhere((q) =>
        q
          .eq('room_id', roomId)
          .is('left_at', null)
          .gt('expires_at', nowIso())
          .order('joined_at', { ascending: false }),
      );
    },

    async findCard(cardId) {
      const [card] = await cardsWhere((q) => q.eq('id', cardId).limit(1));
      return card ?? null;
    },

    openCardsOf(userId, roomId) {
      return cardsWhere((q) => {
        const base = q.eq('user_id', userId).is('left_at', null).gt('expires_at', nowIso());
        return roomId ? base.eq('room_id', roomId) : base;
      });
    },

    async hideCards(cardIds, leave) {
      if (cardIds.length === 0) return [];
      const update: Tables['checkins']['Update'] = { visible: false };
      if (leave) update.left_at = nowIso();
      let query = db
        .from('checkins')
        .update(update)
        .in('id', [...cardIds]);
      // Ending a check-in twice would move left_at; only end open ones.
      if (leave) query = query.is('left_at', null);
      const { data, error } = await query.select(CARD_COLUMNS).returns<CheckinWithCode[]>();
      check('checkins.hide', error);
      return (data ?? []).map(toCard);
    },

    async closeRoomCheckins(roomId) {
      const { data, error } = await db
        .from('checkins')
        .update({ left_at: nowIso(), visible: false })
        .eq('room_id', roomId)
        .is('left_at', null)
        .select(CARD_COLUMNS)
        .returns<CheckinWithCode[]>();
      check('checkins.close_room', error);
      return (data ?? []).map(toCard);
    },

    async clampRoomCheckins(roomId, endsAt) {
      const { error } = await db
        .from('checkins')
        .update({ expires_at: endsAt })
        .eq('room_id', roomId)
        .is('left_at', null)
        .gt('expires_at', endsAt);
      check('checkins.clamp', error);
    },

    async deleteCardPhotos(paths) {
      if (paths.length === 0) return;
      const { error } = await db.storage.from(CARDS_BUCKET).remove([...paths]);
      if (error) throw new Error(`storage.remove failed (${error.name})`);
    },

    async cardPhoto(path) {
      const { data, error } = await db.storage.from(CARDS_BUCKET).download(path);
      if (error || !data) return null;
      return new Uint8Array(await data.arrayBuffer());
    },

    async activityTotals(roomId, since) {
      const totals: Record<keyof ActivityTotals, number> = {
        checkin: 0,
        card_view: 0,
        tap: 0,
        match: 0,
        glow_started: 0,
        glow_met: 0,
        report: 0,
      };
      // PostgREST caps a read at max_rows (1000), so page through by ID.
      let after = 0;
      for (;;) {
        const { data, error } = await db
          .from('room_activity')
          .select('id, kind, n')
          .eq('room_id', roomId)
          .gte('created_at', since)
          .gt('id', after)
          .order('id', { ascending: true })
          .limit(PAGE);
        check('room_activity.select', error);
        const rows = data ?? [];
        for (const row of rows) totals[row.kind] += row.n;
        if (rows.length < PAGE) break;
        after = rows[rows.length - 1]!.id;
      }
      return totals;
    },

    async activeCheckinCount(roomId) {
      const { count, error } = await db
        .from('checkins')
        .select('id', { count: 'exact', head: true })
        .eq('room_id', roomId)
        .is('left_at', null)
        .gt('expires_at', nowIso());
      check('checkins.count', error);
      return count ?? 0;
    },

    async demoSkipCount(roomId, since) {
      const { count, error } = await db
        .from('location_checks')
        .select('id', { count: 'exact', head: true })
        .eq('room_id', roomId)
        .eq('result', 'demo_skip')
        .gte('created_at', since);
      check('location_checks.count', error);
      return count ?? 0;
    },

    async listReports(status) {
      const { data, error } = await db
        .from('reports')
        .select(REPORT_COLUMNS)
        .eq('status', status)
        .order('created_at', { ascending: true })
        .limit(200)
        .returns<ReportWithCodes[]>();
      check('reports.list', error);
      return (data ?? []).map(toReport);
    },

    async findReport(id) {
      const { data, error } = await db
        .from('reports')
        .select(REPORT_COLUMNS)
        .eq('id', id)
        .maybeSingle<ReportWithCodes>();
      check('reports.find', error);
      return data ? toReport(data) : null;
    },

    async setReportStatus(ids, status, adminId) {
      if (ids.length === 0) return;
      const { error } = await db
        .from('reports')
        .update({ status, resolved_at: nowIso(), resolved_by: adminId })
        .in('id', [...ids]);
      check('reports.resolve', error);
    },

    async openReportIdsAbout(userId) {
      const { data, error } = await db
        .from('reports')
        .select('id')
        .eq('reported_id', userId)
        .eq('status', 'open');
      check('reports.open_about', error);
      return (data ?? []).map((r) => r.id);
    },

    async listPhotos(status) {
      const { data, error } = await db
        .from('profile_photos')
        .select(PHOTO_COLUMNS)
        .eq('moderation_status', status)
        .order('created_at', { ascending: true })
        .limit(200)
        .returns<PhotoRow[]>();
      check('profile_photos.list', error);
      return (data ?? []).map(toPhoto);
    },

    async findPhoto(id) {
      const { data, error } = await db
        .from('profile_photos')
        .select(PHOTO_COLUMNS)
        .eq('id', id)
        .maybeSingle<PhotoRow>();
      check('profile_photos.find', error);
      return data ? toPhoto(data) : null;
    },

    async profilePhoto(path) {
      const { data, error } = await db.storage.from(PHOTOS_BUCKET).download(path);
      if (error || !data) return null;
      return new Uint8Array(await data.arrayBuffer());
    },

    async approvePhoto(id) {
      const { error } = await db
        .from('profile_photos')
        .update({ moderation_status: 'approved' })
        .eq('id', id);
      check('profile_photos.approve', error);
    },

    async deletePhoto(photo) {
      // The image first: if the row went first and this failed, nothing would point at it.
      const { error: storageError } = await db.storage.from(PHOTOS_BUCKET).remove([photo.path]);
      if (storageError) throw new Error(`storage.remove failed (${storageError.name})`);
      const { error } = await db.from('profile_photos').delete().eq('id', photo.id);
      check('profile_photos.delete', error);
    },

    async captureFlags(since, threshold) {
      const counts = new Map<string, number>();
      let after = '';
      // Page through by ID: PostgREST caps a read at max_rows.
      for (;;) {
        let query = db
          .from('abuse_signals')
          .select('id, user_id')
          .gte('created_at', since)
          .order('id', { ascending: true })
          .limit(PAGE);
        if (after) query = query.gt('id', after);
        const { data, error } = await query;
        check('abuse_signals.select', error);
        const rows = data ?? [];
        for (const row of rows) counts.set(row.user_id, (counts.get(row.user_id) ?? 0) + 1);
        if (rows.length < PAGE) break;
        after = rows[rows.length - 1]!.id;
      }
      const flagged = [...counts].filter(([, n]) => n >= threshold);
      if (flagged.length === 0) return [];
      const { data, error } = await db
        .from('profiles')
        .select('id, viewer_code')
        .in(
          'id',
          flagged.map(([id]) => id),
        )
        .is('banned_at', null);
      check('profiles.viewer_codes', error);
      const codes = new Map((data ?? []).map((p) => [p.id, p.viewer_code]));
      return flagged
        .filter(([id]) => codes.has(id))
        .map(([userId, count]) => ({ userId, viewerCode: codes.get(userId)!, count }))
        .sort((a, b) => b.count - a.count);
    },

    async personByViewerCode(code) {
      const { data, error } = await db
        .from('profiles')
        .select('id')
        .eq('viewer_code', code)
        .maybeSingle();
      check('profiles.by_viewer_code', error);
      return data?.id ?? null;
    },

    async markBanned(userId) {
      const { data, error } = await db
        .from('profiles')
        .select('id, banned_at')
        .eq('id', userId)
        .maybeSingle();
      check('profiles.find', error);
      if (!data) return false;
      if (!data.banned_at) {
        const { error: updateError } = await db
          .from('profiles')
          .update({ banned_at: nowIso() })
          .eq('id', userId)
          .is('banned_at', null);
        check('profiles.ban', updateError);
      }
      return true;
    },

    async banAuthUser(userId) {
      // About 100 years. Supabase Auth then refuses every token this person holds.
      const { error } = await db.auth.admin.updateUserById(userId, { ban_duration: '876000h' });
      if (error) throw new Error(`auth.ban failed (${error.status ?? 'unknown'})`);
    },

    async activeMatchIdsOf(userId) {
      const { data, error } = await db
        .from('matches')
        .select('id')
        .or(`user_a.eq.${userId},user_b.eq.${userId}`)
        .neq('status', 'ended');
      check('matches.active', error);
      return (data ?? []).map((m) => m.id);
    },

    async unmatch(userId, matchId) {
      const { data, error } = await db.rpc('unmatch', { p_user_id: userId, p_match_id: matchId });
      if (error?.code === 'P0001' && error.message === 'not_found') return null;
      check('rpc.unmatch', error);
      const result = data as { roomId?: unknown; userIds?: unknown } | null;
      return {
        roomId: typeof result?.roomId === 'string' ? result.roomId : '',
        userIds: Array.isArray(result?.userIds)
          ? result.userIds.filter((u): u is string => typeof u === 'string')
          : [],
      };
    },
  };
}
