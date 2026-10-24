// Owner: B4. The handler lives in `server/src/server/matches`.
import { route } from '@/server/http';
import { listMatchesRoute } from '@/server/matches/list-matches';

export const GET = route('listMatches', listMatchesRoute);
