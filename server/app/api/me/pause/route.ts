// Owner: B8. The handler lives in `server/src/server/safety`.
import { route } from '@/server/http';
import { setPaused } from '@/server/safety/routes';

export const POST = route('setPaused', setPaused);
