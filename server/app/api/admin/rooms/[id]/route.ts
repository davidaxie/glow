// Owner: B7. Admins only: everyone else gets 404 (P11). Logic in server/src/server/admin.
import { route } from '@/server/http';
import { adminGetRoomHandler, adminUpdateRoomHandler } from '@/server/admin/handlers';

export const GET = route('adminGetRoom', adminGetRoomHandler);
export const PATCH = route('adminUpdateRoom', adminUpdateRoomHandler);
