// Owner: B4. The handler lives in `server/src/server/taps`.
import { route } from '@/server/http';
import { createTapRoute } from '@/server/taps/create-tap';

export const POST = route('createTap', createTapRoute);
