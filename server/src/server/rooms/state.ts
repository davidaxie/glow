/**
 * GET /api/rooms/{id} (getRoomState). Owner: B2.
 *
 * The room, my open check-in there (with a fresh signed image link to my own card),
 * and the taps and card views I have left today. How the app restores the room home
 * after a relaunch, and how C1's room home knows where it stands. Calls `get_room_state`.
 */
import type { CardTags, MyCheckin, RoomState, RoomSummary } from '@/contracts';
import { notFound, type RouteHandler } from '@/server/http';
import { serviceDb } from './db';
import { signedCardImage } from './stand-ins';

/** What `get_room_state` returns (docs/CONTRACTS.md). */
type DbRoomState = {
  room: RoomSummary;
  checkin?: {
    id: string;
    roomId: string;
    tags: CardTags;
    visible: boolean;
    joinedAt: string;
    expiresAt: string;
  };
  tapsLeftToday: number;
  viewsLeftToday: number;
};

export const getRoomState: RouteHandler<'getRoomState'> = async ({ user, params }) => {
  const db = serviceDb();
  const { data, error } = await db.rpc('get_room_state', {
    p_user_id: user.id,
    p_room_id: params.id,
  });
  if (error) {
    if (error.message === 'not_found') throw notFound();
    throw new Error('get_room_state failed');
  }
  const state = data as unknown as DbRoomState;
  const now = new Date();

  const room: RoomSummary = {
    ...state.room,
    status:
      state.room.status === 'live' && now.getTime() >= Date.parse(state.room.endsAt)
        ? 'ended'
        : state.room.status,
  };
  const checkin: MyCheckin | undefined = state.checkin
    ? {
        cardId: state.checkin.id,
        roomId: state.checkin.roomId,
        tags: state.checkin.tags,
        visible: state.checkin.visible,
        joinedAt: state.checkin.joinedAt,
        expiresAt: state.checkin.expiresAt,
        image: signedCardImage(state.checkin.id, user.id, now),
      }
    : undefined;

  const body: RoomState = {
    room,
    ...(checkin ? { checkin } : {}),
    tapsLeftToday: state.tapsLeftToday,
    viewsLeftToday: state.viewsLeftToday,
  };
  return { status: 200, body };
};
