// Owner: B8. The handler lives in `server/src/server/safety`.
//
// Called every PURGE_INTERVAL by Vercel Cron (server/vercel.json) or any outside scheduler,
// with `Authorization: Bearer $CRON_SECRET`. Safe to call more often, or twice at once.
import { route } from '@/server/http';
import { runPurge } from '@/server/safety/routes';

// A sweep of both buckets can take a little while; never let a platform default cut it short.
export const maxDuration = 60;

export const GET = route('runPurge', runPurge);
