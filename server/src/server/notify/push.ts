/**
 * Apple push for an event. Interfaces-only version: decides whether the event has a push,
 * and skips sending until the APNs sender lands (B5's full PR).
 */
import { apnsRequestFor, type GlowEvent } from '@/contracts';

export type PushOutcome = {
  /** Pushes Apple accepted. */
  readonly sent: number;
  /** Pushes that failed for a reason other than a dead token. */
  readonly failed: number;
  /** Device tokens Apple rejected, now deleted. */
  readonly pruned: number;
  /** Set when nothing was sent on purpose. */
  readonly skipped?: 'apns_not_configured' | 'no_devices';
};

/** Pushes the event to every registered device of these people. Null if it has no push. */
export async function sendPushes(
  _userIds: readonly string[],
  event: GlowEvent,
): Promise<PushOutcome | null> {
  if (!apnsRequestFor(event)) return null;
  return { sent: 0, failed: 0, pruned: 0, skipped: 'apns_not_configured' };
}
