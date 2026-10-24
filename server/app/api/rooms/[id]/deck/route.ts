// Owner: B4. The handler lives in `server/src/server/deck`.
import { getDeckRoute } from '@/server/deck/get-deck';
import { route } from '@/server/http';

export const POST = route('getDeck', getDeckRoute);
