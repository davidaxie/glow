// Owner: B2. The handler lives in `server/src/server/rooms`.
import { route } from '@/server/http';
import { getRoomState } from '@/server/rooms';

export const GET = route('getRoomState', getRoomState);
