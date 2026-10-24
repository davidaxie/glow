import { randomUUID } from 'node:crypto';
import sharp from 'sharp';
import { afterEach, describe, expect, it } from 'vitest';
import { zAdminCard, zAdminReport } from '@/contracts';
import { cardImage, listCards, removeCard } from '@/server/admin/cards';
import { setAdminDepsForTests } from '@/server/admin/context';
import {
  banByViewerCode,
  banPerson,
  captureFlags,
  listReports,
  resolveReport,
} from '@/server/admin/reports';
import { HttpError } from '@/server/http';
import {
  ADMIN_ID,
  FakeRepo,
  OTHER_ID,
  PERSON_ID,
  ROOM_ID,
  card,
  fakeDeps,
  report,
} from './fake-repo';

afterEach(() => setAdminDepsForTests(undefined));

function setup(init?: (repo: FakeRepo) => void) {
  const repo = new FakeRepo(init);
  const { deps, events } = fakeDeps(repo);
  setAdminDepsForTests(deps);
  return { repo, events };
}

async function status(promise: Promise<unknown>): Promise<number> {
  try {
    await promise;
    return 200;
  } catch (error) {
    if (error instanceof HttpError) return error.status;
    throw error;
  }
}

const USER_ID_FIELDS = /userId|reporterId|reportedId|user_id/;

describe('cards', () => {
  it('lists open cards with no user ID in them', async () => {
    const open = card();
    const gone = card({ leftAt: '2026-10-24T18:30:00.000Z' });
    setup((r) => {
      r.cards.set(open.id, open);
      r.cards.set(gone.id, gone);
    });
    const cards = await listCards(ROOM_ID);
    expect(cards.map((c) => c.id)).toEqual([open.id]);
    expect(JSON.stringify(cards)).not.toMatch(USER_ID_FIELDS);
    expect(JSON.stringify(cards)).not.toContain(PERSON_ID);
    zAdminCard.parse(cards[0]);
  });

  it('removing a card hides it and deletes its photo; they can check in again', async () => {
    const c = card();
    const { repo, events } = setup((r) => r.cards.set(c.id, c));
    await removeCard(c.id, 'card', ADMIN_ID);
    expect(repo.cards.get(c.id)).toMatchObject({ visible: false, leftAt: null });
    expect(repo.deletedPhotos).toEqual([c.cardPath]);
    expect(events.deckChanged).toEqual([ROOM_ID]);
  });

  it('removing the person also ends their check-in', async () => {
    const c = card();
    const { repo } = setup((r) => r.cards.set(c.id, c));
    await removeCard(c.id, 'person', ADMIN_ID);
    expect(repo.cards.get(c.id)?.leftAt).not.toBeNull();
    expect(repo.deletedPhotos).toEqual([c.cardPath]);
  });

  it('is 404 for an unknown or already ended card', async () => {
    const ended = card({ leftAt: '2026-10-24T18:30:00.000Z' });
    setup((r) => r.cards.set(ended.id, ended));
    expect(await status(removeCard(randomUUID(), 'card', ADMIN_ID))).toBe(404);
    expect(await status(removeCard(ended.id, 'card', ADMIN_ID))).toBe(404);
    expect(await status(cardImage(ended.id, ADMIN_ID))).toBe(404);
  });

  it("watermarks the photo with the admin's own code", async () => {
    const c = card();
    const jpeg = await sharp({
      create: { width: 320, height: 400, channels: 3, background: '#335533' },
    })
      .jpeg()
      .withMetadata({ exif: { IFD0: { Copyright: 'leaky' } } })
      .toBuffer();
    setup((r) => {
      r.cards.set(c.id, c);
      r.photos.set(c.cardPath, jpeg);
    });
    const out = await cardImage(c.id, ADMIN_ID);
    const meta = await sharp(out).metadata();
    expect([meta.format, meta.width, meta.height]).toEqual(['jpeg', 320, 400]);
    expect(meta.exif).toBeUndefined();
    expect(out.equals(jpeg)).toBe(false);
  });
});

describe('reports', () => {
  it('lists open reports oldest first, naming people only by watermark code', async () => {
    const older = report({ createdAt: '2026-10-24T18:00:00.000Z', details: 'Kept staring.' });
    const newer = report({ createdAt: '2026-10-24T18:45:00.000Z' });
    const done = report({ status: 'dismissed' });
    setup((r) => [older, newer, done].forEach((x) => r.reports.set(x.id, x)));
    const reports = await listReports();
    expect(reports.map((r) => r.id)).toEqual([older.id, newer.id]);
    for (const r of reports) zAdminReport.parse(r);
    const text = JSON.stringify(reports);
    expect(text).not.toMatch(USER_ID_FIELDS);
    expect(text).not.toContain(PERSON_ID);
    expect(text).not.toContain(OTHER_ID);
  });

  it('dismiss only closes the report', async () => {
    const r = report();
    const { repo } = setup((x) => x.reports.set(r.id, r));
    const after = await resolveReport(r.id, 'dismiss', ADMIN_ID);
    expect(after.status).toBe('dismissed');
    expect(repo.calls).not.toContain('markBanned');
    expect(repo.calls).not.toContain('hideCards');
  });

  it("remove_card on a card report removes that card, if it's the reported person's", async () => {
    const c = card();
    const r = report({ contextId: c.id });
    const { repo } = setup((x) => {
      x.cards.set(c.id, c);
      x.reports.set(r.id, r);
    });
    expect((await resolveReport(r.id, 'remove_card', ADMIN_ID)).status).toBe('actioned');
    expect(repo.cards.get(c.id)?.visible).toBe(false);
    expect(repo.deletedPhotos).toEqual([c.cardPath]);
  });

  it("remove_card on a chat report removes the reported person's card in that room", async () => {
    const theirs = card();
    const elsewhere = card({ roomId: randomUUID() });
    const reporters = card({ userId: OTHER_ID });
    const r = report({ context: 'chat' });
    const { repo } = setup((x) => {
      [theirs, elsewhere, reporters].forEach((c) => x.cards.set(c.id, c));
      x.reports.set(r.id, r);
    });
    await resolveReport(r.id, 'remove_card', ADMIN_ID);
    expect(repo.cards.get(theirs.id)?.visible).toBe(false);
    expect(repo.cards.get(elsewhere.id)?.visible).toBe(true);
    expect(repo.cards.get(reporters.id)?.visible).toBe(true);
  });

  it('is 404 for a report that does not exist', async () => {
    setup();
    expect(await status(resolveReport(randomUUID(), 'dismiss', ADMIN_ID))).toBe(404);
  });
});

describe('ban', () => {
  it('hides first, then signs out, clears cards and matches, and closes every report', async () => {
    const c1 = card();
    const c2 = card({ roomId: randomUUID() });
    const r1 = report();
    const r2 = report({ context: 'match' });
    const matchId = randomUUID();
    const { repo, events } = setup((x) => {
      x.cards.set(c1.id, c1);
      x.cards.set(c2.id, c2);
      x.reports.set(r1.id, r1);
      x.reports.set(r2.id, r2);
      x.matches.set(matchId, { roomId: ROOM_ID, userIds: [PERSON_ID, OTHER_ID], ended: false });
    });

    const after = await resolveReport(r1.id, 'ban', ADMIN_ID);

    expect(after.status).toBe('actioned');
    expect(repo.calls.indexOf('markBanned')).toBeLessThan(repo.calls.indexOf('banAuthUser'));
    expect(repo.calls.indexOf('banAuthUser')).toBeLessThan(repo.calls.indexOf('hideCards:leave'));
    expect(repo.people.get(PERSON_ID)).toMatchObject({ authBanned: true });
    expect(repo.people.get(PERSON_ID)?.bannedAt).not.toBeNull();
    expect([...repo.cards.values()].every((c) => c.leftAt !== null && !c.visible)).toBe(true);
    expect(repo.deletedPhotos.sort()).toEqual([c1.cardPath, c2.cardPath].sort());
    expect(new Set(events.deckChanged)).toEqual(new Set([c1.roomId, c2.roomId]));
    expect(repo.matches.get(matchId)?.ended).toBe(true);
    expect(events.matchEnded).toEqual([{ matchId, recipients: [PERSON_ID, OTHER_ID] }]);
    expect(repo.reports.get(r2.id)?.status).toBe('actioned');
  });

  it('can run twice', async () => {
    setup();
    await banPerson(PERSON_ID, ADMIN_ID);
    await banPerson(PERSON_ID, ADMIN_ID);
  });

  it("won't ban yourself, and is 404 for nobody", async () => {
    setup();
    expect(await status(banPerson(ADMIN_ID, ADMIN_ID))).toBe(400);
    expect(await status(banPerson(randomUUID(), ADMIN_ID))).toBe(404);
  });
});

describe('screenshot flags', () => {
  it('lists people with 3 or more captures in 24 hours, by watermark code only', async () => {
    const at = (h: number) =>
      new Date(Date.parse('2026-10-24T19:00:00.000Z') - h * 3600_000).toISOString();
    const { repo } = setup((r) => {
      r.captures.push(
        { userId: PERSON_ID, at: at(1) },
        { userId: PERSON_ID, at: at(2) },
        { userId: PERSON_ID, at: at(3) },
        { userId: OTHER_ID, at: at(1) },
        { userId: OTHER_ID, at: at(2) },
        { userId: OTHER_ID, at: at(30) },
      );
    });
    const flags = await captureFlags();
    expect(flags).toEqual([{ viewerCode: 'YTVFCREQ', count: 3 }]);
    expect(JSON.stringify(flags)).not.toContain(PERSON_ID);
    await banByViewerCode('YTVFCREQ', ADMIN_ID);
    expect(repo.people.get(PERSON_ID)?.bannedAt).not.toBeNull();
    expect(await captureFlags()).toEqual([]);
  });

  it('is 404 for a code nobody has', async () => {
    setup();
    expect(await status(banByViewerCode('ZZZZZZZZ', ADMIN_ID))).toBe(404);
    expect(await status(banByViewerCode('not a code', ADMIN_ID))).toBe(404);
  });
});
