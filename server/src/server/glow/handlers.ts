/**
 * Owner: C3. The three glow routes (contracts/openapi.yaml, tag `glow`):
 *
 * - `GET /api/matches/{id}/glow` (`getGlow`): the active glow, or the one that just ended.
 * - `POST /api/matches/{id}/glow/met` (`markGlowMet`): I tapped We met. Both: it ends as met.
 * - `POST /api/matches/{id}/glow/cancel` (`cancelGlow`): Cancel, or Switch to chat. Ends it for both.
 *
 * Anything that isn't the caller's, or has ended, is 404 (P11): the database functions decide that,
 * and a glow that ended more than GLOW_ENDED_RETENTION ago counts as gone. Replies carry only the
 * contract's Glow fields: never a user ID, and the other person is only ever "they" (P1).
 */
import { GLOW_ENDED_RETENTION_SECONDS } from '@/contracts';
import { notFound, type RouteHandler } from '@/server/http';
import { logger } from '@/server/log';
import { activeGlowId, rpc, serviceDb, type GlowDb } from './db';
import { announce, settledAnnouncements, type Announcement } from './events';
import {
  parseResult,
  toGlowReply,
  zCancelGlowResult,
  zGlowMetResult,
  zMatchGlowResult,
  type GlowRow,
} from './results';

/** For tests: the database the handlers use, and the clock. */
export type GlowDeps = { readonly db: () => GlowDb; readonly now: () => number };
const defaults: GlowDeps = { db: serviceDb, now: Date.now };

/** Active, or ended within GLOW_ENDED_RETENTION (so both apps can show how it ended). */
export function isShowable(glow: Pick<GlowRow, 'status' | 'endedAt' | 'endsAt'>, now: number) {
  if (glow.status === 'active') return true;
  const ended = Date.parse(glow.endedAt ?? glow.endsAt);
  return Number.isFinite(ended) && now - ended < GLOW_ENDED_RETENTION_SECONDS * 1000;
}

const endedFor = (row: GlowRow): Announcement => ({
  userIds: row.userIds,
  event: { type: 'glow.ended', matchId: row.matchId },
});

export function makeGetGlow(deps: GlowDeps = defaults): RouteHandler<'getGlow'> {
  return async ({ user, params }) => {
    // get_match applies the glow's timeout first, and reports it in settled.
    const data = await rpc(deps.db(), 'get_match', {
      p_user_id: user.id,
      p_match_id: params.id,
    });
    const { glow, settled } = parseResult('get_match', zMatchGlowResult, data);
    await announce(settledAnnouncements(settled));
    if (!glow || !isShowable(glow, deps.now())) throw notFound();
    return { status: 200, body: toGlowReply(glow) };
  };
}

export function makeMarkGlowMet(deps: GlowDeps = defaults): RouteHandler<'markGlowMet'> {
  return async ({ user, params }) => {
    const db = deps.db();
    // Was it still on before this tap? Then a `met` answer means this tap ended it.
    const wasActive = await activeGlowId(db, params.id);
    const data = await rpc(db, 'glow_met', { p_user_id: user.id, p_match_id: params.id });
    const row = parseResult('glow_met', zGlowMetResult, data);
    if (!isShowable(row, deps.now())) throw notFound();

    const announcements = settledAnnouncements(row.settled);
    const endedNow = wasActive === row.id && row.status === 'met';
    if (endedNow) announcements.push(endedFor(row));
    logger.info('glow.met', { status: row.status, both: row.youMet && row.theyMet, endedNow });
    await announce(announcements);
    return { status: 200, body: toGlowReply(row) };
  };
}

export function makeCancelGlow(deps: GlowDeps = defaults): RouteHandler<'cancelGlow'> {
  return async ({ user, params, body }) => {
    const db = deps.db();
    const wasActive = await activeGlowId(db, params.id);
    const data = await rpc(db, 'cancel_glow', { p_user_id: user.id, p_match_id: params.id });
    const row = parseResult('cancel_glow', zCancelGlowResult, data);
    if (!isShowable(row, deps.now())) throw notFound();

    // Cancel and Switch to chat end the glow the same way: canceled, and the chat opens for both.
    // The reason only goes to the log, as an outcome.
    const endedNow = wasActive === row.id && row.status === 'canceled';
    logger.info('glow.cancel', {
      reason: body?.reason ?? 'cancel',
      status: row.status,
      endedNow,
    });
    await announce(endedNow ? [endedFor(row)] : []);
    return { status: 200, body: toGlowReply(row) };
  };
}

export const getGlowFor = makeGetGlow();
export const markGlowMetFor = makeMarkGlowMet();
export const cancelGlowFor = makeCancelGlow();
