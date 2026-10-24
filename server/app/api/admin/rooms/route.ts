// Owner: B7. Admins only: everyone else gets 404 (P11). Logic in server/src/server/admin.
import { route } from '@/server/http';
import { adminCreateRoomHandler, adminListRoomsHandler } from '@/server/admin/handlers';

export const GET = route('adminListRooms', adminListRoomsHandler);
export const POST = route('adminCreateRoom', adminCreateRoomHandler);
