// Owner: B2. The page lives in `server/src/server/rooms/web.ts`.
import { route } from '@/server/http';
import { getRoomWebPage } from '@/server/rooms';

export const GET = route('getRoomWebPage', getRoomWebPage);
