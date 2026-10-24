// Owner: C2. The handler lives in `server/src/server/choice`.
import { getMatchFor } from '@/server/choice';
import { route } from '@/server/http';

export const GET = route('getMatch', getMatchFor);
