import { randomUUID } from 'node:crypto';
import sharp from 'sharp';
import { afterEach, describe, expect, it } from 'vitest';
import { setAdminDepsForTests } from '@/server/admin/context';
import { listPhotos, photoImage, reviewPhoto } from '@/server/admin/photos';
import { HttpError } from '@/server/http';
import { ADMIN_ID, FakeRepo, PERSON_ID, card, fakeDeps, photo } from './fake-repo';

afterEach(() => setAdminDepsForTests(undefined));

function setup(init?: (repo: FakeRepo) => void) {
  const repo = new FakeRepo(init);
  setAdminDepsForTests(fakeDeps(repo).deps);
  return repo;
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

describe('held profile photos', () => {
  it('lists held photos oldest first, with no user ID', async () => {
    const older = photo({ createdAt: '2026-10-24T18:00:00.000Z' });
    const newer = photo({ createdAt: '2026-10-24T18:20:00.000Z' });
    const approved = photo({ moderationStatus: 'approved' });
    setup((r) => [older, newer, approved].forEach((p) => r.profilePhotos.set(p.id, p)));
    const photos = await listPhotos();
    expect(photos.map((p) => p.id)).toEqual([older.id, newer.id]);
    expect(photos[0]).toEqual({
      id: older.id,
      position: 0,
      moderationStatus: 'held',
      createdAt: older.createdAt,
      viewerCode: 'YTVFCREQ',
      image: `/api/admin/photos/${older.id}/image`,
    });
    expect(JSON.stringify(photos)).not.toContain(PERSON_ID);
  });

  it('never lists or opens approved or rejected photos', async () => {
    const approved = photo({ moderationStatus: 'approved' });
    setup((r) => r.profilePhotos.set(approved.id, approved));
    expect(await status(listPhotos('approved'))).toBe(400);
    expect(await status(listPhotos('rejected'))).toBe(400);
    expect(await status(photoImage(approved.id, ADMIN_ID))).toBe(404);
    expect(await status(reviewPhoto(approved.id, 'reject', ADMIN_ID))).toBe(404);
  });

  it("shows a held photo watermarked with the admin's code", async () => {
    const p = photo();
    const jpeg = await sharp({
      create: { width: 200, height: 250, channels: 3, background: '#777' },
    })
      .jpeg()
      .toBuffer();
    setup((r) => {
      r.profilePhotos.set(p.id, p);
      r.profileImages.set(p.path, jpeg);
    });
    const out = await photoImage(p.id, ADMIN_ID);
    expect((await sharp(out).metadata()).format).toBe('jpeg');
    expect(out.equals(jpeg)).toBe(false);
  });

  it('approve lets it count', async () => {
    const p = photo();
    const repo = setup((r) => r.profilePhotos.set(p.id, p));
    expect((await reviewPhoto(p.id, 'approve', ADMIN_ID)).moderationStatus).toBe('approved');
    expect(repo.profilePhotos.get(p.id)?.moderationStatus).toBe('approved');
  });

  it('reject deletes the image and the row', async () => {
    const p = photo();
    const repo = setup((r) => {
      r.profilePhotos.set(p.id, p);
      r.profileImages.set(p.path, new Uint8Array([1]));
    });
    expect((await reviewPhoto(p.id, 'reject', ADMIN_ID)).moderationStatus).toBe('rejected');
    expect(repo.profilePhotos.has(p.id)).toBe(false);
    expect(repo.deletedProfileImages).toEqual([p.path]);
  });

  it('ban deletes the photo and bans the owner everywhere', async () => {
    const p = photo();
    const c = card();
    const repo = setup((r) => {
      r.profilePhotos.set(p.id, p);
      r.cards.set(c.id, c);
    });
    await reviewPhoto(p.id, 'ban', ADMIN_ID);
    expect(repo.profilePhotos.has(p.id)).toBe(false);
    expect(repo.people.get(PERSON_ID)).toMatchObject({ authBanned: true });
    expect(repo.cards.get(c.id)?.leftAt).not.toBeNull();
  });

  it('is 404 for a photo that does not exist', async () => {
    setup();
    expect(await status(reviewPhoto(randomUUID(), 'approve', ADMIN_ID))).toBe(404);
  });
});
