/**
 * P4: every image is checked per request; there are no public storage links. With the app's
 * anon key, signed out or signed in, nobody can read, list, sign, upload over or delete a
 * real card photo or profile photo through Supabase Storage. Images only come out of the
 * API's routes, which check the viewer every time (journey.live.test.ts covers the links).
 */
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { LIVE, supa, type Live } from './helpers/live';
import { World, type Card, type Person } from './helpers/world';

const live = LIVE as Live;
let world: World;
let owner: Person;
let attacker: Person;
let card: Card;
let photoPath: string;

beforeAll(async () => {
  if (!LIVE) return;
  world = new World(live);
  [owner, attacker] = await Promise.all([world.person(), world.person()]);
  const roomId = await world.room();
  card = await world.checkIn(owner, roomId);
  const photos = await world.db.from('profile_photos').select('path').eq('user_id', owner.id);
  photoPath = photos.data![0]!.path;
}, 60_000);

afterAll(async () => {
  if (LIVE) await world.cleanup();
});

describe.skipIf(!LIVE)('P4: storage is closed to the app (live)', () => {
  const objects = (): [string, string][] => [
    ['room-cards', card.path],
    ['profile-photos', photoPath],
  ];

  it('control: the objects exist (the service role can read them)', async () => {
    for (const [bucket, path] of objects()) {
      const res = await fetch(`${live.url}/storage/v1/object/${bucket}/${path}`, {
        headers: { apikey: live.serviceKey, authorization: `Bearer ${live.serviceKey}` },
      });
      expect(res.status, `${bucket}/${path}`).toBe(200);
    }
  });

  for (const who of ['anon', 'signed-in owner', 'signed-in attacker'] as const) {
    it(`${who}: no read, public link, signed link, listing, overwrite or delete`, async () => {
      const token =
        who === 'anon' ? undefined : who === 'signed-in owner' ? owner.token : attacker.token;
      for (const [bucket, path] of objects()) {
        const at = `${bucket}/${path}`;
        for (const route of ['object', 'object/authenticated', 'object/public']) {
          const res = await fetch(`${live.url}/storage/v1/${route}/${at}`, {
            headers: { apikey: live.anonKey, authorization: `Bearer ${token ?? live.anonKey}` },
          });
          expect(res.status, `${route}/${at}`).not.toBe(200);
          await res.arrayBuffer();
        }
        const sign = await supa(live, 'POST', `/storage/v1/object/sign/${at}`, {
          ...(token ? { token } : {}),
          body: { expiresIn: 3600 },
        });
        expect(sign.json.signedURL ?? sign.json.signedUrl, `sign ${at}`).toBeUndefined();

        const folder = path.slice(0, path.lastIndexOf('/'));
        const list = await supa(live, 'POST', `/storage/v1/object/list/${bucket}`, {
          ...(token ? { token } : {}),
          body: { prefix: folder, limit: 100 },
        });
        expect(Array.isArray(list.json) ? list.json : [], `list ${bucket}/${folder}`).toEqual([]);

        const put = await fetch(`${live.url}/storage/v1/object/${at}`, {
          method: 'PUT',
          headers: {
            apikey: live.anonKey,
            authorization: `Bearer ${token ?? live.anonKey}`,
            'content-type': 'image/jpeg',
            'x-upsert': 'true',
          },
          body: new Uint8Array([0xff, 0xd8, 0xff, 0xd9]),
        });
        expect(put.status, `overwrite ${at}`).not.toBe(200);
        await put.arrayBuffer();

        const del = await supa(live, 'DELETE', `/storage/v1/object/${bucket}`, {
          ...(token ? { token } : {}),
          body: { prefixes: [path] },
        });
        expect(Array.isArray(del.json) ? del.json : [], `delete ${at}`).toEqual([]);
      }

      const buckets = await supa(live, 'GET', '/storage/v1/bucket', {
        ...(token ? { token } : {}),
      });
      expect(Array.isArray(buckets.json) ? buckets.json : []).toEqual([]);
      const newBucket = await supa(live, 'POST', '/storage/v1/bucket', {
        ...(token ? { token } : {}),
        body: { id: 'd2-open', name: 'd2-open', public: true },
      });
      expect(newBucket.status).not.toBe(200);
    });
  }

  it('the objects are still there, untouched, and both buckets are private', async () => {
    for (const [bucket, path] of objects()) {
      const res = await fetch(`${live.url}/storage/v1/object/${bucket}/${path}`, {
        headers: { apikey: live.serviceKey, authorization: `Bearer ${live.serviceKey}` },
      });
      expect(res.status).toBe(200);
      expect((await res.arrayBuffer()).byteLength).toBeGreaterThan(4);
    }
    const buckets = await supa(live, 'GET', '/storage/v1/bucket', { key: 'service' });
    const ours = (buckets.json as unknown as { id: string; public: boolean }[]).filter((b) =>
      ['room-cards', 'profile-photos'].includes(b.id),
    );
    expect(ours).toHaveLength(2);
    expect(ours.every((b) => b.public === false)).toBe(true);
  });
});
