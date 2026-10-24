/**
 * A real push through Apple's sandbox to a real device or Simulator. Skips unless every
 * variable below is set, which needs an Apple Developer account and a .p8 key (B9):
 *
 *   APNS_KEY_ID=... APNS_TEAM_ID=... APNS_BUNDLE_ID=com.davidxie.glow \
 *   APNS_PRIVATE_KEY="$(cat AuthKey_XXXXXXXXXX.p8)" \
 *   APNS_TEST_DEVICE_TOKEN=<hex token the app registered> \
 *   pnpm --filter server exec vitest run tests/notify/apns-live.test.ts
 *
 * The app never logs its token. Read it from the `devices` row a signed-in Debug build
 * registered: `select apns_token from devices order by created_at desc limit 1`. A Simulator
 * on Apple silicon gets real sandbox tokens once the build is signed with a team.
 * APNS_TEST_ENVIRONMENT=production targets a TestFlight build instead of sandbox.
 */
import { describe, expect, it } from 'vitest';
import { apnsRequestFor } from '@/contracts';
import { ApnsClient } from '@/server/notify/apns';

// Read at import, before tests/setup.ts clears APNS_* for every test.
const live = {
  keyId: process.env.APNS_KEY_ID,
  teamId: process.env.APNS_TEAM_ID,
  privateKey: process.env.APNS_PRIVATE_KEY?.replace(/\\n/g, '\n').trim(),
  bundleId: process.env.APNS_BUNDLE_ID,
  token: process.env.APNS_TEST_DEVICE_TOKEN?.toLowerCase(),
  environment: process.env.APNS_TEST_ENVIRONMENT === 'production' ? 'production' : 'sandbox',
} as const;
const ready = Boolean(live.keyId && live.teamId && live.privateKey && live.bundleId && live.token);

describe.skipIf(!ready)('real APNs sandbox push', () => {
  it('delivers match.created to the registered device', { timeout: 20_000 }, async () => {
    const client = new ApnsClient({
      keyId: live.keyId!,
      teamId: live.teamId!,
      privateKey: live.privateKey!,
      bundleId: live.bundleId!,
    });
    try {
      const request = apnsRequestFor({
        type: 'match.created',
        matchId: 'f1c70000-0000-4000-8000-000000000001',
      });
      const result = await client.send({
        environment: live.environment,
        deviceToken: live.token!,
        request: request!,
        expiresAt: Math.floor(Date.now() / 1000) + 300,
      });
      expect(result).toEqual({ ok: true, status: 200 });
    } finally {
      client.close();
    }
  });
});
