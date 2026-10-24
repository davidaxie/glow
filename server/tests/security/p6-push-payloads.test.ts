/**
 * P6: lock screen text never includes a name. P1: no event or push carries a user ID.
 *
 * Builds the APNs request for every event in contracts/events.json with the generated
 * `apnsRequestFor` (what B5's sender sends), from an event stuffed with extra fields an
 * owner might pass by mistake, after `contractEvent` (what notify() does first).
 */
import { describe, expect, it } from 'vitest';
import { apnsRequestFor, eventCatalog, type GlowEvent } from '@/contracts';
import { contractEvent } from '@/server/notify/events';

const MATCH = '64bfd966-bf7f-426a-b7aa-f0dc371bae1a';
const ROOM = 'de000000-0000-4000-8000-000000000001';
const USER = '7e570000-0000-4000-8000-000000000001';
const NAME = 'Blakely';

describe('P6 and P1: every push and event', () => {
  const types = Object.keys(eventCatalog) as (keyof typeof eventCatalog)[];

  it('covers every event in the contract', () => {
    expect(types.length).toBeGreaterThanOrEqual(9);
  });

  for (const type of types) {
    it(`${type}: only its type and a match or room ID, and fixed lock screen text`, () => {
      const id = eventCatalog[type].channel === 'room' ? { roomId: ROOM } : { matchId: MATCH };
      const stuffed = {
        type,
        ...id,
        userId: USER,
        firstName: NAME,
        name: NAME,
        body: `${NAME} says hi`,
        otherUserId: USER,
      };
      const event = contractEvent(stuffed) as GlowEvent | null;
      expect(event).not.toBeNull();
      expect(Object.keys(event!).sort()).toEqual(['type', ...Object.keys(id)].sort());

      const spec = eventCatalog[type].push;
      const request = apnsRequestFor(event!);
      if (!spec) {
        expect(request).toBeNull();
        return;
      }
      expect(request).not.toBeNull();
      const text = JSON.stringify(request);
      expect(text).not.toContain(USER);
      expect(text).not.toContain(NAME);
      const aps = request!.payload.aps as { alert: { body: string } };
      // Fixed text: no template slot could ever take a name.
      expect(aps.alert.body).toBe(spec.body);
      expect(aps.alert.body).not.toMatch(/[{}%$]/);
      expect(Object.keys(aps.alert)).toEqual(['body']);
      expect(Object.keys(request!.payload).sort()).toEqual(['aps', 'type', ...Object.keys(id)].sort());
      for (const value of [request!.collapseId, (request!.payload.aps as Record<string, string>)['thread-id']]) {
        expect(value).toMatch(/^[a-z.]+:[0-9a-f-]{36}$/);
      }
    });
  }
});
