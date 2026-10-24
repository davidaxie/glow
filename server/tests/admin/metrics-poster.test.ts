import jsQR from 'jsqr';
import { PDFDocument } from 'pdf-lib';
import { afterEach, describe, expect, it } from 'vitest';
import { setAdminDepsForTests } from '@/server/admin/context';
import { roomLink } from '@/server/admin/links';
import { roomMetrics, startOfRoomDay } from '@/server/admin/metrics';
import { posterPdf } from '@/server/admin/poster';
import { qrPixels, qrSvg } from '@/server/admin/qr-code';
import { FakeRepo, ROOM_ID, card, fakeDeps, room } from './fake-repo';

afterEach(() => setAdminDepsForTests(undefined));

describe('the room day', () => {
  it.each([
    // 19:00 UTC on 24 Oct is noon in Los Angeles (PDT, UTC-7): the day began at 07:00 UTC.
    ['America/Los_Angeles', '2026-10-24T19:00:00.000Z', '2026-10-24T07:00:00.000Z'],
    // 03:00 UTC on 25 Oct is still 24 Oct, 20:00, in Los Angeles.
    ['America/Los_Angeles', '2026-10-25T03:00:00.000Z', '2026-10-24T07:00:00.000Z'],
    ['UTC', '2026-10-24T19:00:00.000Z', '2026-10-24T00:00:00.000Z'],
    ['Asia/Tokyo', '2026-10-24T19:00:00.000Z', '2026-10-24T15:00:00.000Z'],
    // The day after the clocks go back (1 Nov 2026 in the US) starts at UTC-8.
    ['America/Los_Angeles', '2026-11-02T12:00:00.000Z', '2026-11-02T08:00:00.000Z'],
    // The day the clocks go back started at UTC-7 (midnight was still daylight time).
    ['America/Los_Angeles', '2026-11-01T20:00:00.000Z', '2026-11-01T07:00:00.000Z'],
  ])('%s at %s starts at %s', (tz, now, start) => {
    expect(startOfRoomDay(tz, Date.parse(now)).toISOString()).toBe(start);
  });
});

describe('metrics', () => {
  it('counts the room day by default, with no tap count at all', async () => {
    const repo = new FakeRepo((r) => {
      const open = card();
      r.cards.set(open.id, open);
      r.activity.push(
        { roomId: ROOM_ID, kind: 'checkin', n: 1, at: '2026-10-24T06:59:00.000Z' }, // yesterday
        { roomId: ROOM_ID, kind: 'checkin', n: 1, at: '2026-10-24T08:00:00.000Z' },
        { roomId: ROOM_ID, kind: 'card_view', n: 7, at: '2026-10-24T09:00:00.000Z' },
        { roomId: ROOM_ID, kind: 'tap', n: 3, at: '2026-10-24T09:00:00.000Z' },
        { roomId: ROOM_ID, kind: 'match', n: 1, at: '2026-10-24T09:01:00.000Z' },
        { roomId: ROOM_ID, kind: 'glow_met', n: 1, at: '2026-10-24T09:20:00.000Z' },
      );
    });
    setAdminDepsForTests(fakeDeps(repo).deps);
    const m = await roomMetrics(ROOM_ID);
    expect(m).toMatchObject({
      since: '2026-10-24T07:00:00.000Z',
      activeCheckins: 1,
      checkins: 1,
      cardViews: 7,
      matches: 1,
      glowsStarted: 0,
      glowsMet: 1,
      reports: 0,
    });
    // P5: taps never show, whatever the counters hold.
    expect((m as { taps?: number }).taps ?? 0).toBe(0);
  });
});

describe('QR codes', () => {
  it('encodes exactly the link, readable by a QR decoder', () => {
    const link = roomLink('demo', 'DEMOSTATICTOKEN2');
    const { width, data } = qrPixels(link, 4);
    expect(jsQR(data, width, width)?.data).toBe(link);
  });

  it('draws as one SVG path inside its quiet zone', () => {
    const svg = qrSvg(roomLink('demo', 'ABCDEFGH'));
    expect(svg.path).toMatch(/^M\d/);
    expect(svg.path).not.toMatch(/M[0-3] /); // nothing in the left quiet zone
    expect(svg.viewBox).toBeGreaterThan(29);
  });
});

describe('poster', () => {
  it('is one US Letter page that names nothing about the venue but its name', async () => {
    const pdf = await posterPdf(room({ name: 'Café Hall' }));
    const doc = await PDFDocument.load(pdf);
    expect(doc.getPageCount()).toBe(1);
    expect(doc.getPage(0).getSize()).toEqual({ width: 612, height: 792 });
    expect(doc.getTitle()).toBe('Glow poster: Cafe Hall');
    expect(doc.getAuthor()).toBeUndefined();
    const text = Buffer.from(pdf).toString('latin1');
    expect(text).not.toContain('37.8029');
    expect(text).not.toContain('-122.4484');
  });
});
