/**
 * GET /api/matches/{id}/photos/{n} (getMatchPhoto): the other person's nth approved profile
 * photo, for a match that hasn't ended (P1, P4, P11).
 *
 * `match_photo_path` decides: it answers only for someone in the match, while it isn't ended,
 * for an approved photo that exists. Everything else is the same 404. Like card photos, the
 * photo is watermarked with the viewer's code, so a leaked screenshot can be traced.
 */
import type { RouteHandler } from '@/server/http';
import { httpErrorFor } from './db-errors';
import { readPrivateObject, viewerCodeOf, watermarkedResponse } from './serve';
import { PROFILE_BUCKET, serviceClient } from './supabase';

export const getMatchPhoto: RouteHandler<'getMatchPhoto'> = async ({ user, params }) => {
  const db = serviceClient();
  const path = await db.rpc('match_photo_path', {
    p_viewer_id: user.id,
    p_match_id: params.id,
    p_n: params.n,
  });
  if (path.error) throw httpErrorFor(path.error);
  if (typeof path.data !== 'string' || path.data.length === 0) throw httpErrorFor(null);

  const [bytes, code] = await Promise.all([
    readPrivateObject(PROFILE_BUCKET, path.data, db),
    viewerCodeOf(user.id, db),
  ]);
  return watermarkedResponse(bytes, code);
};
