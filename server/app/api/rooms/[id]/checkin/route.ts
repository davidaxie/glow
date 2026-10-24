// Owner: B3. The handler lives in `server/src/server/images/checkin.ts`.
import { route } from '@/server/http';
import { createCheckin } from '@/server/images';

export const POST = route('createCheckin', createCheckin);
