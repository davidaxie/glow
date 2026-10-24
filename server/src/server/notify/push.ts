/**
 * Apple push for an event: every registered device of the people it's for.
 *
 * The payload is exactly `apnsRequestFor(event)` from the generated contract: fixed lock
 * screen text (never a name, P6) plus the event's own `type` and `matchId` or `roomId`.
 * Without the four APNS_* variables (local development, previews before the Apple account
 * exists) nothing is sent and the outcome says so.
 */
import {
  apnsRequestFor,
  CHECKIN_EXPIRY_WARNING_SECONDS,
  CHOICE_WINDOW_SECONDS,
  GLOW_TTL_SECONDS,
  type GlowEvent,
  type GlowEventType,
} from '@/contracts';
import { getEnv } from '@/env';
import { logger } from '@/server/log';
import { ApnsClient, type ApnsOptions, type ApnsResult } from './apns';
import { devicesFor, markDevicesOk, pruneDevices } from './devices';

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

/**
 * How long Apple keeps trying to deliver each push, in seconds (B5-D7). A glow, a stale Find
 * or a check-in warning is useless once it's over; a match or a message still matters an hour
 * later. Events without an entry get an hour.
 */
export const PUSH_LIFETIME: Readonly<Partial<Record<GlowEventType, number>>> = {
  'match.created': 3600,
  'match.recheck': CHOICE_WINDOW_SECONDS,
  'glow.started': GLOW_TTL_SECONDS,
  'message.created': 3600,
  'checkin.expiring': CHECKIN_EXPIRY_WARNING_SECONDS,
};
const DEFAULT_LIFETIME = 3600;

let client: ApnsClient | null | undefined;
let clientOptions: ApnsOptions = {};

/** The APNs client for this server, or null when APNS_* isn't configured. */
function apns(): ApnsClient | null {
  if (client !== undefined) return client;
  const env = getEnv();
  if (!env.APNS_KEY_ID || !env.APNS_TEAM_ID || !env.APNS_PRIVATE_KEY || !env.APNS_BUNDLE_ID) {
    client = null;
    return client;
  }
  client = new ApnsClient(
    {
      keyId: env.APNS_KEY_ID,
      teamId: env.APNS_TEAM_ID,
      privateKey: env.APNS_PRIVATE_KEY,
      bundleId: env.APNS_BUNDLE_ID,
    },
    clientOptions,
  );
  return client;
}

/** For tests: forget the client, and build the next one with these options (say, a local origin). */
export function resetApnsForTests(options: ApnsOptions = {}): void {
  client?.close();
  client = undefined;
  clientOptions = options;
}

/** Pushes the event to every registered device of these people. Null if it has no push. */
export async function sendPushes(
  userIds: readonly string[],
  event: GlowEvent,
): Promise<PushOutcome | null> {
  const request = apnsRequestFor(event);
  if (!request) return null;
  const sender = apns();
  if (!sender) return { sent: 0, failed: 0, pruned: 0, skipped: 'apns_not_configured' };

  const devices = await devicesFor(userIds);
  if (devices.length === 0) return { sent: 0, failed: 0, pruned: 0, skipped: 'no_devices' };

  const expiresAt = Math.floor(Date.now() / 1000) + (PUSH_LIFETIME[event.type] ?? DEFAULT_LIFETIME);
  const results = await Promise.all(
    devices.map(async (device) => ({
      device,
      result: await sender.send({
        environment: device.environment,
        deviceToken: device.token,
        request,
        expiresAt,
      }),
    })),
  );

  const ok = results.filter((r) => r.result.ok).map((r) => r.device.id);
  const dead = results.filter((r) => isDead(r.result)).map((r) => r.device.id);
  const failures = results.filter((r) => !r.result.ok && !isDead(r.result));
  for (const { result } of failures) {
    if (!result.ok) {
      logger.warn('notify.push_rejected', {
        type: event.type,
        status: result.status,
        reason: result.reason,
      });
    }
  }

  await Promise.all([
    pruneDevices(dead).catch(() => logger.warn('notify.prune_failed', { count: dead.length })),
    markDevicesOk(ok).catch(() => logger.warn('notify.mark_ok_failed', { count: ok.length })),
  ]);
  return { sent: ok.length, failed: failures.length, pruned: dead.length };
}

function isDead(result: ApnsResult): boolean {
  return !result.ok && result.dead;
}
