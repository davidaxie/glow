// Owner: B5. The handler lives in `server/src/server/notify/routes.ts`.
import { route } from '@/server/http';
import { registerDeviceRoute } from '@/server/notify/routes';

export const POST = route('registerDevice', registerDeviceRoute);
