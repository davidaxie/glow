/**
 * Owner: B4. `POST /api/rooms/{id}/taps` (createTap).
 *
 * `record_tap` does all of it in one transaction: the card must be in my deck right now and
 * the deck must have shown it to me, today's tap cap, saving the tap, and making the match
 * if they already tapped me. An advisory lock on the pair means two taps at the same moment
 * make exactly one match.
 *
 * P5: a one-sided tap is never revealed. `sent` says nothing about the other person, and
 * nobody but the tapper hears about it: no event, no push, no count. Only a mutual tap
 * notifies, and then it notifies both people with match.created.
 *
 * Errors: a card that isn't in my deck right now (or never existed, or is in another room)
 * is 404 (P11). No taps left today is 409 `tap_limit_reached`. Tapping the same card again
 * is free and answers `sent` again.
 */
import type { TapRequest, TapResult } from '@/contracts';
import { rpc } from '@/server/deck/db';
import type { RouteHandler } from '@/server/http';
import { announceMatch } from '@/server/matches/announce';

type DbTapResult = {
  readonly result: 'sent' | 'mutual';
  readonly tapsLeftToday: number;
  readonly matchId?: string | null;
};

export async function recordTap(
  viewerId: string,
  roomId: string,
  request: TapRequest,
): Promise<TapResult> {
  const raw = (await rpc('record_tap', {
    p_viewer_id: viewerId,
    p_room_id: roomId,
    p_checkin_id: request.cardId,
  })) as unknown as DbTapResult;

  const tapsLeftToday = Math.max(0, raw.tapsLeftToday);
  if (raw.result === 'mutual' && raw.matchId) {
    await announceMatch(raw.matchId);
    return { result: 'mutual', tapsLeftToday, matchId: raw.matchId };
  }
  // Exactly these two fields, whatever the other person did or didn't do.
  return { result: 'sent', tapsLeftToday };
}

// Rate limits (B8's `taps` policy) are applied by route() before this runs.
export const createTapRoute: RouteHandler<'createTap'> = async ({ user, params, body }) => ({
  status: 200,
  body: await recordTap(user.id, params.id, body),
});
