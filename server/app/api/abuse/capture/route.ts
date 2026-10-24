// Owner: B8. The handler lives in `server/src/server/safety`.
import { route } from '@/server/http';
import { logCapture } from '@/server/safety/routes';

export const POST = route('logCapture', logCapture);
