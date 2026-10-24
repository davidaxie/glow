// Owner: B2. The handler lives in `server/src/server/rooms`.
import { route } from '@/server/http';
import { leaveRoom } from '@/server/rooms';

export const POST = route('leaveRoom', leaveRoom);
