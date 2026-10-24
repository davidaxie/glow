// Owner: B2. The handler lives in `server/src/server/rooms`.
import { route } from '@/server/http';
import { joinRoom } from '@/server/rooms';

export const POST = route('joinRoom', joinRoom);
