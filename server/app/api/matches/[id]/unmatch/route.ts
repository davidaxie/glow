// Owner: C4. The handler lives in `server/src/server/chat`.
import { unmatchRoute } from '@/server/chat/unmatch';
import { route } from '@/server/http';

export const POST = route('unmatch', unmatchRoute);
