/**
 * P6: lock screen text never includes a name. These snapshot every push exactly as it goes
 * over the wire to APNs (headers and body), for every event that has one, sent through
 * `notify()` the way routes call it. Any change to a payload shows up as a snapshot diff.
 */
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { eventCatalog, type GlowEventType } from '@/contracts';
import { resetEnvCacheForTests } from '@/env';
import { notify, type UserEvent } from '@/server/notify';
import { resetApnsForTests } from '@/server/notify/push';
import {
  startMockApns,
  testCredentials,
  type MockApns,
  type RecordedPush,
} from './helpers/apns-server';

vi.mock('@/server/notify/devices', () => ({
  devicesFor: vi.fn(),
  pruneDevices: vi.fn(),
  markDevicesOk: vi.fn(),
}));
const devices = await import('@/server/notify/devices');

const ROBIN = '7e570000-0000-4000-8000-0000000000a1';
const SAM = '7e570000-0000-4000-8000-0000000000b2';
const MATCH = 'f1c70000-0000-4000-8000-000000000001';
const ROOM = 'de000000-0000-4000-8000-000000000001';
const NOW = Date.UTC(2026, 9, 24, 20, 15, 0);
/** First names of everyone in the seed and these tests. None may appear in any push. */
const NAMES = ['Robin', 'Sam', 'Alex', 'Blake', 'Casey', 'Drew', 'Admin'];

const pushTypes = (Object.keys(eventCatalog) as GlowEventType[]).filter(
  (type) => eventCatalog[type].push !== null && eventCatalog[type].channel === 'user',
);
const fixedTexts = new Set<string>(
  Object.values(eventCatalog).flatMap((spec) => (spec.push ? [spec.push.body] : [])),
);

function eventOf(type: GlowEventType): UserEvent {
  return (
    type === 'checkin.expiring' ? { type, roomId: ROOM } : { type, matchId: MATCH }
  ) as UserEvent;
}

/**
 * What Apple sees, minus the provider token (a signature, different every run) and the
 * test server's address.
 */
function wire(push: RecordedPush) {
  const { authorization, ':authority': _authority, ':scheme': _scheme, ...rest } = push.headers;
  expect(String(authorization)).toMatch(/^bearer [\w-]+\.[\w-]+\.[\w-]+$/);
  const headers = Object.fromEntries(Object.entries(rest).sort(([a], [b]) => a.localeCompare(b)));
  return { headers, body: JSON.parse(push.body) as Record<string, unknown> };
}

let apns: MockApns;
const key = testCredentials();

beforeAll(async () => {
  apns = await startMockApns();
});
afterAll(async () => {
  resetApnsForTests();
  await apns.close();
});

beforeEach(() => {
  Object.assign(process.env, {
    APNS_KEY_ID: key.credentials.keyId,
    APNS_TEAM_ID: key.credentials.teamId,
    APNS_PRIVATE_KEY: key.credentials.privateKey,
    APNS_BUNDLE_ID: key.credentials.bundleId,
  });
  resetEnvCacheForTests();
  resetApnsForTests({
    origins: { sandbox: apns.origin, production: apns.origin },
    retryDelayMs: 1,
  });
  apns.pushes.length = 0;
  apns.answersByToken.clear();
  vi.spyOn(Date, 'now').mockReturnValue(NOW);
  vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(null, { status: 202 }));
  for (const write of ['log', 'warn', 'error'] as const) {
    vi.spyOn(console, write).mockImplementation(() => undefined);
  }
  vi.mocked(devices.devicesFor).mockResolvedValue([
    { id: 'd0000000-0000-4000-8000-000000000001', token: 'ab'.repeat(32), environment: 'sandbox' },
  ]);
  vi.mocked(devices.pruneDevices).mockResolvedValue();
  vi.mocked(devices.markDevicesOk).mockResolvedValue();
});

afterEach(() => vi.restoreAllMocks());

describe('every push payload (P6)', () => {
  it('covers every event with lock screen text', () => {
    expect(pushTypes.sort()).toEqual(
      (Object.keys(eventCatalog) as GlowEventType[])
        .filter((t) => eventCatalog[t].push !== null)
        .sort(),
    );
  });

  it.each(pushTypes)('%s', async (type) => {
    const outcome = await notify(ROBIN, eventOf(type));
    expect(outcome.push).toEqual({ sent: 1, failed: 0, pruned: 0 });
    expect(apns.pushes).toHaveLength(1);

    const { headers, body } = wire(apns.pushes[0]!);
    expect({ headers, body }).toMatchSnapshot();

    // Only aps plus the event's own keys, and the alert is a fixed text with no title.
    const text = JSON.stringify({ headers, body });
    for (const name of NAMES) expect(text).not.toContain(name);
    expect(text).not.toContain(ROBIN);
    expect(Object.keys(body).sort()).toEqual(['aps', ...Object.keys(eventOf(type))].sort());
    const aps = body.aps as { alert: Record<string, unknown> };
    expect(Object.keys(aps.alert)).toEqual(['body']);
    expect(fixedTexts.has(aps.alert.body as string)).toBe(true);
  });

  it('keeps names and IDs a caller wrongly adds out of the push', async () => {
    const leaky = {
      type: 'message.created',
      matchId: MATCH,
      firstName: 'Sam',
      senderId: SAM,
      body: 'meet me by the stage, Robin',
    } as unknown as UserEvent;
    await notify([ROBIN], leaky);
    const text = JSON.stringify(apns.pushes);
    for (const name of NAMES) expect(text).not.toContain(name);
    expect(text).not.toContain(SAM);
    expect(text).not.toContain('stage');
  });

  it('never pushes an event without lock screen text', async () => {
    for (const type of ['match.choice', 'match.ended', 'glow.ended'] as const) {
      const outcome = await notify(ROBIN, { type, matchId: MATCH });
      expect(outcome.push).toBeNull();
    }
    expect(apns.pushes).toHaveLength(0);
    expect(devices.devicesFor).not.toHaveBeenCalled();
  });
});

describe('push delivery', () => {
  it('sends to every device of everyone, and prunes the ones Apple rejects', async () => {
    vi.mocked(devices.devicesFor).mockResolvedValue([
      { id: 'd1', token: '01'.repeat(32), environment: 'sandbox' },
      { id: 'd2', token: '02'.repeat(32), environment: 'production' },
      { id: 'd3', token: '03'.repeat(32), environment: 'sandbox' },
    ]);
    apns.answersByToken.set('02'.repeat(32), { status: 410, reason: 'Unregistered' });
    apns.answersByToken.set('03'.repeat(32), { status: 400, reason: 'PayloadTooLarge' });
    const outcome = await notify([ROBIN, SAM], { type: 'match.created', matchId: MATCH });

    expect(devices.devicesFor).toHaveBeenCalledWith([ROBIN, SAM]);
    expect(outcome.push).toEqual({ sent: 1, failed: 1, pruned: 1 });
    expect(devices.pruneDevices).toHaveBeenCalledWith(['d2']);
    expect(devices.markDevicesOk).toHaveBeenCalledWith(['d1']);
  });

  it('skips push without APNs credentials, but still broadcasts', async () => {
    for (const name of ['APNS_KEY_ID', 'APNS_TEAM_ID', 'APNS_PRIVATE_KEY', 'APNS_BUNDLE_ID']) {
      delete process.env[name];
    }
    resetEnvCacheForTests();
    resetApnsForTests();
    const outcome = await notify(ROBIN, { type: 'match.created', matchId: MATCH });
    expect(outcome).toEqual({
      realtime: 'sent',
      push: { sent: 0, failed: 0, pruned: 0, skipped: 'apns_not_configured' },
    });
    expect(devices.devicesFor).not.toHaveBeenCalled();
  });

  it('says so when nobody has a device', async () => {
    vi.mocked(devices.devicesFor).mockResolvedValue([]);
    const outcome = await notify(ROBIN, { type: 'glow.started', matchId: MATCH });
    expect(outcome.push).toEqual({ sent: 0, failed: 0, pruned: 0, skipped: 'no_devices' });
  });

  it('still broadcasts when the device lookup fails', async () => {
    vi.mocked(devices.devicesFor).mockRejectedValue(new Error('db down'));
    const outcome = await notify(ROBIN, { type: 'glow.started', matchId: MATCH });
    expect(outcome).toEqual({ realtime: 'sent', push: null });
  });
});
