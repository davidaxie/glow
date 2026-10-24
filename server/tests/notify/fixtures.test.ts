/**
 * ios/fixtures/push/ has one `.apns` file per event, for `scripts/sim.sh push A <event>`.
 * This test keeps them identical to what the server sends, so the Simulator sees exactly the
 * real payload. To rewrite them after a contract change:
 *
 *   GLOW_WRITE_PUSH_FIXTURES=1 pnpm --filter server exec vitest run tests/notify/fixtures.test.ts
 */
import { readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { apnsRequestFor, eventCatalog, type GlowEvent, type GlowEventType } from '@/contracts';

const FIXTURES = fileURLToPath(new URL('../../../ios/fixtures/push/', import.meta.url));
const BUNDLE_ID = 'com.davidxie.glow';
const WRITE = process.env.GLOW_WRITE_PUSH_FIXTURES === '1';

/** Fixture IDs. The match is made up; the room is the seeded demo room. */
const FIXTURE_MATCH_ID = 'f1c70000-0000-4000-8000-000000000001';
const FIXTURE_ROOM_ID = 'de000000-0000-4000-8000-000000000001';

const types = Object.keys(eventCatalog) as GlowEventType[];

function fixtureEvent(type: GlowEventType): GlowEvent {
  return (
    type === 'checkin.expiring' || type === 'deck.changed'
      ? { type, roomId: FIXTURE_ROOM_ID }
      : { type, matchId: FIXTURE_MATCH_ID }
  ) as GlowEvent;
}

/**
 * Events with a push get the server's payload, byte for byte. Events without one never get a
 * push from the server; their fixture is a Simulator-only stand-in (marked `glowFixture`) so
 * `sim.sh push` can still check that a tap on that event opens the right screen (docs/DECISIONS.md,
 * "Push fixtures for events without a push").
 */
function fixtureFor(type: GlowEventType): Record<string, unknown> {
  const event = fixtureEvent(type);
  const request = apnsRequestFor(event);
  if (request) return { 'Simulator Target Bundle': BUNDLE_ID, ...request.payload };
  return {
    'Simulator Target Bundle': BUNDLE_ID,
    glowFixture: 'simulator-only: the server never pushes this event, it arrives over Realtime',
    aps: { alert: { body: `Simulator test: ${type}` }, 'thread-id': 'glow.fixture' },
    ...event,
  };
}

const fileFor = (type: GlowEventType) => `${type.replace('.', '_')}.apns`;
const render = (value: unknown) => `${JSON.stringify(value, null, 2)}\n`;

describe('push fixtures for sim.sh', () => {
  it.each(types)('%s matches what the server sends', (type) => {
    const expected = render(fixtureFor(type));
    const path = FIXTURES + fileFor(type);
    if (WRITE) writeFileSync(path, expected);
    expect(readFileSync(path, 'utf8')).toBe(expected);
  });

  it('has a fixture for every event and nothing else', () => {
    const files = readdirSync(FIXTURES).filter((f) => f.endsWith('.apns'));
    expect(files.sort()).toEqual(types.map(fileFor).sort());
  });

  it('marks every stand-in, and only stand-ins', () => {
    for (const type of types) {
      const json = JSON.parse(readFileSync(FIXTURES + fileFor(type), 'utf8')) as object;
      expect('glowFixture' in json).toBe(eventCatalog[type].push === null);
    }
  });
});
