/**
 * An in-memory AdminRepo for the admin module's tests. It keeps just enough state to check
 * what the logic asks for, and records every call so tests can check the order of steps.
 */
import { randomUUID } from 'node:crypto';
import type {
  ActivityTotals,
  AdminRepo,
  CardRecord,
  NewRoom,
  PhotoRecord,
  ReportRecord,
  RoomPatch,
  RoomRecord,
} from '@/server/admin/repo';
import { RepoConflict } from '@/server/admin/repo';
import type { AdminDeps } from '@/server/admin/context';

export const ADMIN_ID = '7e570000-0000-4000-8000-000000000005';
export const PERSON_ID = '7e570000-0000-4000-8000-000000000001';
export const OTHER_ID = '7e570000-0000-4000-8000-000000000002';
export const ROOM_ID = 'de000000-0000-4000-8000-000000000001';
export const SECRET = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';

export function room(overrides: Partial<RoomRecord> = {}): RoomRecord {
  return {
    id: ROOM_ID,
    slug: 'demo',
    name: 'Glow demo room (test data)',
    code: 'HACK26',
    latitude: 37.8029,
    longitude: -122.4484,
    radiusM: 200,
    timezone: 'America/Los_Angeles',
    qrSecret: SECRET,
    staticQrToken: 'DEMOSTATICTOKEN2',
    allowStaticQr: true,
    demoMode: false,
    status: 'live',
    startsAt: '2026-10-23T06:00:00.000Z',
    endsAt: '2026-11-22T06:00:00.000Z',
    createdAt: '2026-10-23T06:00:00.000Z',
    spots: [
      { id: 'de000000-0000-4000-8000-0000000005f1', name: 'Main entrance', sort: 0 },
      { id: 'de000000-0000-4000-8000-0000000005f2', name: 'Food line', sort: 1 },
      { id: 'de000000-0000-4000-8000-0000000005f3', name: 'Water station', sort: 2 },
    ],
    ...overrides,
  };
}

export function card(overrides: Partial<CardRecord> = {}): CardRecord {
  const id = overrides.id ?? randomUUID();
  const roomId = overrides.roomId ?? ROOM_ID;
  return {
    id,
    roomId,
    userId: PERSON_ID,
    cardPath: `${roomId}/${id}.jpg`,
    tags: { topColor: 'green', hairLength: 'short', extras: ['glasses'] },
    visible: true,
    joinedAt: '2026-10-24T18:00:00.000Z',
    expiresAt: '2026-10-24T21:00:00.000Z',
    leftAt: null,
    viewerCode: 'YTVFCREQ',
    ...overrides,
  };
}

export function photo(overrides: Partial<PhotoRecord> = {}): PhotoRecord {
  const id = overrides.id ?? randomUUID();
  const userId = overrides.userId ?? PERSON_ID;
  return {
    id,
    userId,
    path: `${userId}/${id}.jpg`,
    position: 0,
    moderationStatus: 'held',
    createdAt: '2026-10-24T18:10:00.000Z',
    viewerCode: 'YTVFCREQ',
    ...overrides,
  };
}

export function report(overrides: Partial<ReportRecord> = {}): ReportRecord {
  return {
    id: randomUUID(),
    reporterId: OTHER_ID,
    reportedId: PERSON_ID,
    roomId: ROOM_ID,
    context: 'card',
    contextId: randomUUID(),
    reason: 'harassment',
    details: null,
    evidence: [],
    status: 'open',
    createdAt: '2026-10-24T18:30:00.000Z',
    reporterViewerCode: 'ABCDEFGH',
    reportedViewerCode: 'YTVFCREQ',
    ...overrides,
  };
}

export class FakeRepo implements AdminRepo {
  admins = new Set<string>([ADMIN_ID]);
  people = new Map<string, { viewerCode: string; bannedAt: string | null; authBanned: boolean }>([
    [ADMIN_ID, { viewerCode: 'ADMNC2DE', bannedAt: null, authBanned: false }],
    [PERSON_ID, { viewerCode: 'YTVFCREQ', bannedAt: null, authBanned: false }],
    [OTHER_ID, { viewerCode: 'ABCDEFGH', bannedAt: null, authBanned: false }],
  ]);
  rooms = new Map<string, RoomRecord>([[ROOM_ID, room()]]);
  cards = new Map<string, CardRecord>();
  reports = new Map<string, ReportRecord>();
  profilePhotos = new Map<string, PhotoRecord>();
  profileImages = new Map<string, Uint8Array>();
  deletedProfileImages: string[] = [];
  photos = new Map<string, Uint8Array>();
  deletedPhotos: string[] = [];
  matches = new Map<string, { roomId: string; userIds: [string, string]; ended: boolean }>();
  activity: { roomId: string; kind: keyof ActivityTotals; n: number; at: string }[] = [];
  demoSkips: { roomId: string; at: string }[] = [];
  calls: string[] = [];
  now = () => Date.parse('2026-10-24T19:00:00.000Z');

  constructor(init?: (repo: FakeRepo) => void) {
    init?.(this);
  }

  private open(c: CardRecord): boolean {
    return c.leftAt === null && Date.parse(c.expiresAt) > this.now();
  }

  async isAdmin(userId: string) {
    this.calls.push('isAdmin');
    return this.admins.has(userId) && !this.people.get(userId)?.bannedAt;
  }
  async viewerCode(userId: string) {
    return this.people.get(userId)?.viewerCode ?? null;
  }
  async listRooms() {
    return [...this.rooms.values()].sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  }
  async findRoom(by: { id: string } | { slug: string }) {
    if ('id' in by) return this.rooms.get(by.id) ?? null;
    return [...this.rooms.values()].find((r) => r.slug === by.slug) ?? null;
  }
  async createRoom(input: NewRoom, spots: readonly string[]) {
    this.calls.push('createRoom');
    if ([...this.rooms.values()].some((r) => r.slug === input.slug)) throw new RepoConflict('slug');
    const id = randomUUID();
    const created = room({
      ...input,
      id,
      code: 'NEWCD2',
      qrSecret: 'ab'.repeat(32),
      staticQrToken: 'ABCDEFGHIJKLMNOP',
      createdAt: new Date(this.now()).toISOString(),
      spots: spots.map((name, sort) => ({ id: randomUUID(), name, sort })),
    });
    this.rooms.set(id, created);
    return created;
  }
  async updateRoom(id: string, patch: RoomPatch) {
    this.calls.push('updateRoom');
    const before = this.rooms.get(id);
    if (!before) return null;
    const after = { ...before, ...patch };
    this.rooms.set(id, after);
    return after;
  }
  async replaceSpots(roomId: string, names: readonly string[]) {
    const before = this.rooms.get(roomId);
    if (!before) return null;
    const spots = names.map((name, sort) => ({
      id: before.spots[sort]?.id ?? randomUUID(),
      name,
      sort,
    }));
    const after = { ...before, spots };
    this.rooms.set(roomId, after);
    return after;
  }
  async setStaticToken(roomId: string, token: string) {
    const before = this.rooms.get(roomId);
    if (!before) return null;
    const after = { ...before, staticQrToken: token };
    this.rooms.set(roomId, after);
    return after;
  }
  async openCards(roomId: string) {
    return [...this.cards.values()]
      .filter((c) => c.roomId === roomId && this.open(c))
      .sort((a, b) => b.joinedAt.localeCompare(a.joinedAt));
  }
  async findCard(cardId: string) {
    return this.cards.get(cardId) ?? null;
  }
  async openCardsOf(userId: string, roomId?: string) {
    return [...this.cards.values()].filter(
      (c) => c.userId === userId && this.open(c) && (!roomId || c.roomId === roomId),
    );
  }
  async hideCards(cardIds: readonly string[], leave: boolean) {
    this.calls.push(leave ? 'hideCards:leave' : 'hideCards');
    const changed: CardRecord[] = [];
    for (const id of cardIds) {
      const c = this.cards.get(id);
      if (!c || (leave && c.leftAt !== null)) continue;
      const after = {
        ...c,
        visible: false,
        leftAt: leave ? new Date(this.now()).toISOString() : c.leftAt,
      };
      this.cards.set(id, after);
      changed.push(after);
    }
    return changed;
  }
  async closeRoomCheckins(roomId: string) {
    this.calls.push('closeRoomCheckins');
    const open = [...this.cards.values()].filter((c) => c.roomId === roomId && c.leftAt === null);
    return this.hideCards(
      open.map((c) => c.id),
      true,
    );
  }
  async clampRoomCheckins(roomId: string, endsAt: string) {
    this.calls.push('clampRoomCheckins');
    for (const c of this.cards.values()) {
      if (c.roomId === roomId && c.leftAt === null && c.expiresAt > endsAt) {
        this.cards.set(c.id, { ...c, expiresAt: endsAt });
      }
    }
  }
  async deleteCardPhotos(paths: readonly string[]) {
    this.calls.push('deleteCardPhotos');
    for (const p of paths) {
      this.photos.delete(p);
      this.deletedPhotos.push(p);
    }
  }
  async cardPhoto(path: string) {
    return this.photos.get(path) ?? null;
  }
  async activityTotals(roomId: string, since: string) {
    const totals = {
      checkin: 0,
      card_view: 0,
      tap: 0,
      match: 0,
      glow_started: 0,
      glow_met: 0,
      report: 0,
    };
    for (const a of this.activity) if (a.roomId === roomId && a.at >= since) totals[a.kind] += a.n;
    return totals;
  }
  async activeCheckinCount(roomId: string) {
    return (await this.openCards(roomId)).length;
  }
  async demoSkipCount(roomId: string, since: string) {
    return this.demoSkips.filter((d) => d.roomId === roomId && d.at >= since).length;
  }
  async listReports(status: string) {
    return [...this.reports.values()]
      .filter((r) => r.status === status)
      .sort((a, b) => a.createdAt.localeCompare(b.createdAt));
  }
  async findReport(id: string) {
    return this.reports.get(id) ?? null;
  }
  async setReportStatus(ids: readonly string[], status: ReportRecord['status']) {
    this.calls.push(`setReportStatus:${status}:${ids.length}`);
    for (const id of ids) {
      const r = this.reports.get(id);
      if (r) this.reports.set(id, { ...r, status });
    }
  }
  async openReportIdsAbout(userId: string) {
    return [...this.reports.values()]
      .filter((r) => r.reportedId === userId && r.status === 'open')
      .map((r) => r.id);
  }
  async listPhotos(status: PhotoRecord['moderationStatus']) {
    return [...this.profilePhotos.values()]
      .filter((p) => p.moderationStatus === status)
      .sort((a, b) => a.createdAt.localeCompare(b.createdAt));
  }
  async findPhoto(id: string) {
    return this.profilePhotos.get(id) ?? null;
  }
  async profilePhoto(path: string) {
    return this.profileImages.get(path) ?? null;
  }
  async approvePhoto(id: string) {
    this.calls.push('approvePhoto');
    const p = this.profilePhotos.get(id);
    if (p) this.profilePhotos.set(id, { ...p, moderationStatus: 'approved' });
  }
  async deletePhoto(photo: PhotoRecord) {
    this.calls.push('deletePhoto');
    this.profileImages.delete(photo.path);
    this.deletedProfileImages.push(photo.path);
    this.profilePhotos.delete(photo.id);
  }
  async markBanned(userId: string) {
    this.calls.push('markBanned');
    const p = this.people.get(userId);
    if (!p) return false;
    p.bannedAt ??= new Date(this.now()).toISOString();
    return true;
  }
  async banAuthUser(userId: string) {
    this.calls.push('banAuthUser');
    const p = this.people.get(userId);
    if (p) p.authBanned = true;
  }
  async activeMatchIdsOf(userId: string) {
    return [...this.matches.entries()]
      .filter(([, m]) => !m.ended && m.userIds.includes(userId))
      .map(([id]) => id);
  }
  async unmatch(userId: string, matchId: string) {
    this.calls.push('unmatch');
    const m = this.matches.get(matchId);
    if (!m || m.ended || !m.userIds.includes(userId)) return null;
    m.ended = true;
    return { roomId: m.roomId, userIds: [...m.userIds] };
  }
}

export function fakeDeps(repo: FakeRepo) {
  const events = {
    deckChanged: [] as string[],
    matchEnded: [] as { matchId: string; recipients: readonly string[] }[],
  };
  const deps: AdminDeps = {
    repo,
    now: () => repo.now(),
    events: {
      async deckChanged(roomId) {
        repo.calls.push('deckChanged');
        events.deckChanged.push(roomId);
      },
      async matchEnded(matchId, recipients) {
        repo.calls.push('matchEnded');
        events.matchEnded.push({ matchId, recipients });
      },
    },
  };
  return { deps, events };
}
