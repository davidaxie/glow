// Owner: B5. The handler lives in `server/src/server/notify/routes.ts`.
import { route } from '@/server/http';
import { deleteDeviceRoute } from '@/server/notify/routes';

export const DELETE = route('deleteDevice', deleteDeviceRoute);
