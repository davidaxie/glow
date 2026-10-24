import { describe, expect, it, vi } from 'vitest';
import { liveEvents } from '@/server/admin/notify';

vi.mock('@/server/notify', () => ({
  notify: vi.fn(async () => ({ realtime: 'sent', push: null })),
  notifyRoom: vi.fn(async () => ({ realtime: 'sent', push: null })),
}));

const ROOM = 'de000000-0000-4000-8000-000000000001';
const MATCH = '64bfd966-bf7f-426a-b7aa-f0dc371bae1a';
const PEOPLE = ['7e570000-0000-4000-8000-000000000001', '7e570000-0000-4000-8000-000000000002'];

describe('admin events go through B5', () => {
  it('sends deck.changed to the room, and nothing but the type and room ID', async () => {
    const { notifyRoom } = await import('@/server/notify');
    await liveEvents.deckChanged(ROOM);
    expect(notifyRoom).toHaveBeenCalledWith(ROOM, { type: 'deck.changed', roomId: ROOM });
  });

  it('sends match.ended to both people; their IDs only address it', async () => {
    const { notify } = await import('@/server/notify');
    await liveEvents.matchEnded(MATCH, PEOPLE);
    expect(notify).toHaveBeenCalledWith(PEOPLE, { type: 'match.ended', matchId: MATCH });
  });
});
