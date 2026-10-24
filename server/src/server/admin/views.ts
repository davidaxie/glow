/**
 * Records to the contract's admin shapes. Only these leave the server. No user ID appears in
 * any of them: people are named by their watermark code, which is what a moderator matches
 * against a leaked screenshot.
 */
import type { AdminCard, AdminReport, AdminRoom } from '@/contracts';
import { roomLink } from './links';
import type { CardRecord, ReportRecord, RoomRecord } from './repo';

export function toAdminRoom(room: RoomRecord): AdminRoom {
  return {
    id: room.id,
    slug: room.slug,
    name: room.name,
    code: room.code,
    latitude: room.latitude,
    longitude: room.longitude,
    radiusM: room.radiusM,
    timezone: room.timezone,
    allowStaticQr: room.allowStaticQr,
    staticQrToken: room.staticQrToken,
    demoMode: room.demoMode,
    status: room.status,
    startsAt: room.startsAt,
    endsAt: room.endsAt,
    spots: room.spots.map((s) => ({ id: s.id, name: s.name, sort: s.sort })),
    link: roomLink(room.slug, room.staticQrToken),
  };
}

export function toAdminCard(card: CardRecord): AdminCard {
  return {
    id: card.id,
    tags: card.tags,
    visible: card.visible,
    joinedAt: card.joinedAt,
    expiresAt: card.expiresAt,
    viewerCode: card.viewerCode,
  };
}

export function toAdminReport(report: ReportRecord): AdminReport {
  return {
    id: report.id,
    context: report.context,
    contextId: report.contextId,
    reason: report.reason,
    ...(report.details ? { details: report.details } : {}),
    status: report.status,
    createdAt: report.createdAt,
    ...(report.roomId ? { roomId: report.roomId } : {}),
    reporterViewerCode: report.reporterViewerCode,
    reportedViewerCode: report.reportedViewerCode,
    evidence: report.evidence.map((e) => ({ body: e.body, createdAt: e.createdAt })),
  };
}
