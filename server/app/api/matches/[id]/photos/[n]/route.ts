// Owner: B3. The handler lives in `server/src/server/images/match-photo.ts`.
import { route } from '@/server/http';
import { getMatchPhoto } from '@/server/images';

export const GET = route('getMatchPhoto', getMatchPhoto);
