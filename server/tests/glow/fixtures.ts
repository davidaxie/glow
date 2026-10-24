/** Owner: C3. Shared values for the glow unit tests. Test data only. */
import type { GlowRow } from '@/server/glow/results';

export const MATCH_ID = '3c1f0a9e-5d2b-4e7a-9c11-0a2b3c4d5e6f';
export const ROOM_ID = 'de000000-0000-4000-8000-000000000001';
export const GLOW_ID = '453803c0-4199-465b-a12d-1981639daadd';
export const SPOT_ID = 'de000000-0000-4000-8000-0000000005f3';
export const OTHER_ID = '9b2d7c4e-1a3f-4b5c-8d6e-7f8091a2b3c4';
export const OTHER_MATCH_ID = '5e6f7a8b-9c0d-4e1f-a2b3-c4d5e6f70819';
export const STRANGER_A = '1a2b3c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d';
export const STRANGER_B = '2b3c4d5e-6f7a-4b8c-9d0e-1f2a3b4c5d6e';

export const NOW = Date.parse('2026-10-24T20:20:00.000Z');

/** What private.glow_json returns: the contract's Glow plus server-only fields. */
export function glowRow(me: string, overrides: Partial<GlowRow> = {}): GlowRow {
  return {
    id: GLOW_ID,
    matchId: MATCH_ID,
    roomId: ROOM_ID,
    status: 'active',
    color: 'aqua',
    codeWord: 'lantern',
    meetingSpot: { id: SPOT_ID, name: 'Water station' },
    startedAt: '2026-10-24T20:12:00.000Z',
    endsAt: '2026-10-24T20:27:00.000Z',
    youMet: false,
    theyMet: false,
    userIds: [me, OTHER_ID],
    ...overrides,
  };
}

/** The Glow fields the contract allows in a reply, and nothing else. */
export const GLOW_KEYS = [
  'codeWord',
  'color',
  'endedAt',
  'endsAt',
  'id',
  'meetingSpot',
  'startedAt',
  'status',
  'theyMet',
  'youMet',
];
