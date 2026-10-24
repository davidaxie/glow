/**
 * Everything the admin module reads or writes, as one interface. The live implementation is
 * `supabase-repo.ts` (service role, server only); tests use an in-memory one. Records carry
 * user IDs only where the server needs them to act; nothing here is ever sent to a browser
 * as is. `views.ts` turns records into the contract's shapes.
 */
import type { CardTags, ReportContext, ReportReason, ReportStatus, RoomStatus } from '@/contracts';

export type SpotRecord = { readonly id: string; readonly name: string; readonly sort: number };

export type RoomRecord = {
  readonly id: string;
  readonly slug: string;
  readonly name: string;
  readonly code: string;
  readonly latitude: number;
  readonly longitude: number;
  readonly radiusM: number;
  readonly timezone: string;
  /** HMAC key for rotating screen tokens, 32 bytes as hex. Never leaves the server. */
  readonly qrSecret: string;
  readonly staticQrToken: string;
  readonly allowStaticQr: boolean;
  readonly demoMode: boolean;
  readonly status: RoomStatus;
  readonly startsAt: string;
  readonly endsAt: string;
  readonly createdAt: string;
  /** Sorted by `sort`. */
  readonly spots: readonly SpotRecord[];
};

export type NewRoom = {
  readonly slug: string;
  readonly name: string;
  readonly latitude: number;
  readonly longitude: number;
  readonly radiusM: number;
  readonly timezone: string;
  readonly allowStaticQr: boolean;
  readonly demoMode: boolean;
  readonly startsAt: string;
  readonly endsAt: string;
};

export type RoomPatch = Partial<{
  name: string;
  latitude: number;
  longitude: number;
  radiusM: number;
  timezone: string;
  allowStaticQr: boolean;
  demoMode: boolean;
  status: RoomStatus;
  startsAt: string;
  endsAt: string;
}>;

/** A check-in, which is a card. */
export type CardRecord = {
  readonly id: string;
  readonly roomId: string;
  readonly userId: string;
  readonly cardPath: string;
  readonly tags: CardTags;
  readonly visible: boolean;
  readonly joinedAt: string;
  readonly expiresAt: string;
  readonly leftAt: string | null;
  /** The card owner's watermark code. */
  readonly viewerCode: string;
};

export type ReportRecord = {
  readonly id: string;
  readonly reporterId: string;
  readonly reportedId: string;
  readonly roomId: string | null;
  readonly context: ReportContext;
  readonly contextId: string;
  readonly reason: ReportReason;
  readonly details: string | null;
  readonly evidence: readonly { readonly body: string; readonly createdAt: string }[];
  readonly status: ReportStatus;
  readonly createdAt: string;
  readonly reporterViewerCode: string;
  readonly reportedViewerCode: string;
};

/** A profile photo, for review. */
export type PhotoRecord = {
  readonly id: string;
  readonly userId: string;
  readonly path: string;
  readonly position: number;
  readonly moderationStatus: 'pending' | 'approved' | 'held' | 'rejected';
  readonly createdAt: string;
  /** The owner's watermark code. */
  readonly viewerCode: string;
};

/** Counts from room_activity, by kind, since a time. */
export type ActivityTotals = {
  readonly checkin: number;
  readonly card_view: number;
  readonly tap: number;
  readonly match: number;
  readonly glow_started: number;
  readonly glow_met: number;
  readonly report: number;
};

/** Thrown by the repo for expected failures, so logic can map them to HTTP errors. */
export class RepoConflict extends Error {
  override readonly name = 'RepoConflict';
  constructor(readonly what: 'slug' | 'code' | 'static_token' | 'check') {
    super(`conflict: ${what}`);
  }
}

export interface AdminRepo {
  // People
  isAdmin(userId: string): Promise<boolean>;
  viewerCode(userId: string): Promise<string | null>;

  // Rooms
  listRooms(): Promise<RoomRecord[]>;
  findRoom(by: { readonly id: string } | { readonly slug: string }): Promise<RoomRecord | null>;
  /** Throws RepoConflict('slug') if the slug is taken. */
  createRoom(room: NewRoom, spots: readonly string[]): Promise<RoomRecord>;
  updateRoom(id: string, patch: RoomPatch): Promise<RoomRecord | null>;
  /** Renames spots in place by position (so a glow's spot keeps its ID), adds and removes the rest. */
  replaceSpots(roomId: string, names: readonly string[]): Promise<RoomRecord | null>;
  /** Throws RepoConflict('static_token') on the (vanishingly rare) clash. */
  setStaticToken(roomId: string, token: string): Promise<RoomRecord | null>;

  // Cards (check-ins)
  /** Open check-ins in a room (not left, not expired), newest first. */
  openCards(roomId: string): Promise<CardRecord[]>;
  findCard(cardId: string): Promise<CardRecord | null>;
  /** Open check-ins of one person, in one room or everywhere. */
  openCardsOf(userId: string, roomId?: string): Promise<CardRecord[]>;
  /** Hides cards; with `leave`, also ends the check-ins. Returns the cards it changed. */
  hideCards(cardIds: readonly string[], leave: boolean): Promise<CardRecord[]>;
  /** Ends every open check-in in the room. Returns them. */
  closeRoomCheckins(roomId: string): Promise<CardRecord[]>;
  /** No open check-in in the room may outlast `endsAt` (a future time). */
  clampRoomCheckins(roomId: string, endsAt: string): Promise<void>;
  deleteCardPhotos(paths: readonly string[]): Promise<void>;
  cardPhoto(path: string): Promise<Uint8Array | null>;

  // Metrics
  activityTotals(roomId: string, since: string): Promise<ActivityTotals>;
  activeCheckinCount(roomId: string): Promise<number>;
  demoSkipCount(roomId: string, since: string): Promise<number>;

  // Reports
  listReports(status: ReportStatus): Promise<ReportRecord[]>;
  findReport(id: string): Promise<ReportRecord | null>;
  setReportStatus(ids: readonly string[], status: ReportStatus, adminId: string): Promise<void>;
  openReportIdsAbout(userId: string): Promise<string[]>;

  // Profile photos waiting for review
  /** Photos with this status, oldest first. */
  listPhotos(status: PhotoRecord['moderationStatus']): Promise<PhotoRecord[]>;
  findPhoto(id: string): Promise<PhotoRecord | null>;
  profilePhoto(path: string): Promise<Uint8Array | null>;
  approvePhoto(id: string): Promise<void>;
  /** Deletes the stored image and the row. */
  deletePhoto(photo: PhotoRecord): Promise<void>;

  // Screenshot and recording flags (B8's abuse_signals)
  /** People with at least `threshold` captures since `since`, most first. Unbanned only. */
  captureFlags(
    since: string,
    threshold: number,
  ): Promise<{ userId: string; viewerCode: string; count: number }[]>;
  /** The person behind a watermark code, or null. */
  personByViewerCode(code: string): Promise<string | null>;

  // Bans
  /** Sets profiles.banned_at (once). False if there's no such person. */
  markBanned(userId: string): Promise<boolean>;
  /** Bans the auth user, so every token they hold stops working (D3). */
  banAuthUser(userId: string): Promise<void>;
  activeMatchIdsOf(userId: string): Promise<string[]>;
  /** `unmatch` for that person. The user IDs are for notify(), never for a reply. */
  unmatch(userId: string, matchId: string): Promise<{ roomId: string; userIds: string[] } | null>;
}
