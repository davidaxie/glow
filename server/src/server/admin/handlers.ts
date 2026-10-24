/**
 * The `/api/admin/*` handlers. Each one checks the caller is an admin before anything else,
 * and anyone who isn't gets the same 404 as a room that doesn't exist (P11). The admin web
 * calls the same functions through server actions, with the session from its cookie.
 */
import type { RouteHandler } from '@/server/http';
import { requireAdmin } from './access';
import { cardImage, listCards, removeCard } from './cards';
import { roomMetrics } from './metrics';
import { posterPdf } from './poster';
import { listReports, resolveReport } from './reports';
import {
  createRoom,
  displayTokenFor,
  getRoom,
  getRoomRecord,
  listRooms,
  replaceSpots,
  rotateStaticToken,
  updateRoom,
} from './rooms';

const NO_STORE = 'no-store, max-age=0';

export function jpegResponse(bytes: Uint8Array): Response {
  return new Response(new Uint8Array(bytes), {
    status: 200,
    headers: {
      'content-type': 'image/jpeg',
      'cache-control': NO_STORE,
      'content-disposition': 'inline',
      'x-content-type-options': 'nosniff',
    },
  });
}

export function pdfResponse(bytes: Uint8Array, slug: string): Response {
  return new Response(new Uint8Array(bytes), {
    status: 200,
    headers: {
      'content-type': 'application/pdf',
      'cache-control': NO_STORE,
      'content-disposition': `inline; filename="glow-poster-${slug}.pdf"`,
    },
  });
}

export const adminListRoomsHandler: RouteHandler<'adminListRooms'> = async ({ user }) => {
  await requireAdmin(user.id);
  return { status: 200, body: { rooms: await listRooms() } };
};

export const adminCreateRoomHandler: RouteHandler<'adminCreateRoom'> = async ({ user, body }) => {
  await requireAdmin(user.id);
  return { status: 201, body: await createRoom(body, user.id) };
};

export const adminGetRoomHandler: RouteHandler<'adminGetRoom'> = async ({ user, params }) => {
  await requireAdmin(user.id);
  return { status: 200, body: await getRoom(params.id) };
};

export const adminUpdateRoomHandler: RouteHandler<'adminUpdateRoom'> = async ({
  user,
  params,
  body,
}) => {
  await requireAdmin(user.id);
  return { status: 200, body: await updateRoom(params.id, body, user.id) };
};

export const adminReplaceSpotsHandler: RouteHandler<'adminReplaceSpots'> = async ({
  user,
  params,
  body,
}) => {
  await requireAdmin(user.id);
  return { status: 200, body: await replaceSpots(params.id, body.spots, user.id) };
};

export const adminRoomPosterHandler: RouteHandler<'adminRoomPoster'> = async ({ user, params }) => {
  await requireAdmin(user.id);
  const room = await getRoomRecord(params.id);
  return pdfResponse(await posterPdf(room), room.slug);
};

export const adminDisplayTokenHandler: RouteHandler<'adminDisplayToken'> = async ({
  user,
  params,
}) => {
  await requireAdmin(user.id);
  return { status: 200, body: await displayTokenFor(params.id) };
};

export const adminRotateStaticTokenHandler: RouteHandler<'adminRotateStaticToken'> = async ({
  user,
  params,
}) => {
  await requireAdmin(user.id);
  return { status: 200, body: await rotateStaticToken(params.id, user.id) };
};

export const adminRoomMetricsHandler: RouteHandler<'adminRoomMetrics'> = async ({
  user,
  params,
  query,
}) => {
  await requireAdmin(user.id);
  return { status: 200, body: await roomMetrics(params.id, query.since) };
};

export const adminListCardsHandler: RouteHandler<'adminListCards'> = async ({ user, params }) => {
  await requireAdmin(user.id);
  return { status: 200, body: { cards: await listCards(params.id) } };
};

export const adminCardImageHandler: RouteHandler<'adminCardImage'> = async ({ user, params }) => {
  await requireAdmin(user.id);
  return jpegResponse(await cardImage(params.cardId, user.id));
};

export const adminRemoveCardHandler: RouteHandler<'adminRemoveCard'> = async ({
  user,
  params,
  body,
}) => {
  await requireAdmin(user.id);
  await removeCard(params.cardId, body.scope, user.id);
  return { status: 204 };
};

export const adminListReportsHandler: RouteHandler<'adminListReports'> = async ({
  user,
  query,
}) => {
  await requireAdmin(user.id);
  return { status: 200, body: { reports: await listReports(query.status ?? 'open') } };
};

export const adminResolveReportHandler: RouteHandler<'adminResolveReport'> = async ({
  user,
  params,
  body,
}) => {
  await requireAdmin(user.id);
  return { status: 200, body: await resolveReport(params.id, body.action, user.id) };
};
