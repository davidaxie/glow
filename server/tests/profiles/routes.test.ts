/**
 * B1's routes end to end against a real local Supabase: real tokens through the route helper's
 * sign-in check, real rows, real storage, and B8's moderation (its deterministic fake, since
 * tests have no ANTHROPIC_API_KEY).
 */
import sharp from 'sharp';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { GET as getMe } from '../../app/api/me/route';
import { PUT as putProfile } from '../../app/api/me/profile/route';
import { POST as postPhoto } from '../../app/api/me/photos/route';
import { DELETE as deletePhoto, GET as getPhoto } from '../../app/api/me/photos/[id]/route';
import { POST as testLogin } from '../../app/api/dev/test-login/route';
import { POST as complete } from '../../app/api/me/onboarding/complete/route';
import { moderationFixtureJpeg, type ImageFixtureFlag } from '@/server/moderation';
import { assertOnboardingComplete, finishOnboarding } from '@/server/profiles';
import { serviceDb } from '@/server/profiles/db';
import { HttpError } from '@/server/http';
import {
  admin,
  base64,
  call,
  newPerson,
  removePerson,
  supabaseUp,
  useLiveSupabase,
  uuidsIn,
  type TestPerson,
} from './live';

const ADULT = {
  firstName: 'Robin',
  birthdate: '1999-04-12',
  gender: 'nonbinary',
  showMe: ['woman', 'man'],
};

/** Today minus 17 years: someone who is 17. */
function seventeenToday(): string {
  const d = new Date();
  d.setUTCFullYear(d.getUTCFullYear() - 17);
  return d.toISOString().slice(0, 10);
}

const people: TestPerson[] = [];
async function person(): Promise<TestPerson> {
  const p = await newPerson();
  people.push(p);
  return p;
}

const me = async (p: TestPerson) => (await call(getMe, { path: '/api/me', token: p.token })).json();

const finish = (p: TestPerson) =>
  call(complete, { method: 'POST', path: '/api/me/onboarding/complete', token: p.token });

const saveProfile = (p: TestPerson, body: unknown = ADULT) =>
  call(putProfile, { method: 'PUT', path: '/api/me/profile', token: p.token, json: body });

async function upload(p: TestPerson, position: number, flags: ImageFixtureFlag[] = []) {
  const photo = await moderationFixtureJpeg(flags);
  return call(postPhoto, {
    method: 'POST',
    path: '/api/me/photos',
    token: p.token,
    json: { position, photo: base64(photo) },
  });
}

describe.skipIf(!supabaseUp)('B1 routes on a live local Supabase', () => {
  beforeEach(() => useLiveSupabase());
  afterEach(async () => {
    await Promise.all(people.splice(0).map(removePerson));
  });

  it('GET /api/me needs sign-in', async () => {
    const res = await call(getMe, { path: '/api/me' });
    expect(res.status).toBe(401);
  });

  it('a new person starts at the profile step, and Me has only their own ID (P1)', async () => {
    const p = await person();
    const res = await call(getMe, { path: '/api/me', token: p.token });
    expect(res.status).toBe(200);
    expect(res.headers.get('cache-control')).toContain('no-store');
    const body = await res.json();
    expect(body).toMatchObject({ id: p.id, onboardingStep: 'profile', isAdmin: false, photos: [] });
    expect(body.profile).toEqual({
      showMe: [],
      paused: false,
      viewerCode: expect.stringMatching(/^[A-HJ-NP-Z2-9]{8}$/),
    });
    expect(uuidsIn(body)).toEqual([p.id]);
  });

  it('refuses an under-18 birthday with 422 under_18 and stores nothing (P10)', async () => {
    const p = await person();
    const res = await saveProfile(p, { ...ADULT, birthdate: seventeenToday() });
    expect(res.status).toBe(422);
    const body = await res.json();
    expect(body.error.code).toBe('under_18');
    expect(JSON.stringify(body)).not.toContain(seventeenToday());

    const { data } = await admin()
      .from('profiles')
      .select('first_name, birthdate, gender, show_me, onboarding_step')
      .eq('id', p.id)
      .single();
    expect(data).toEqual({
      first_name: null,
      birthdate: null,
      gender: null,
      show_me: [],
      onboarding_step: 'profile',
    });
  });

  it('the database refuses an under-18 birthdate even without the route (D24 backstop)', async () => {
    const p = await person();
    const { error } = await admin()
      .from('profiles')
      .update({ birthdate: seventeenToday() })
      .eq('id', p.id);
    expect(error?.message).toBe('under_18');
  });

  it.each([
    ['a blank first name', { ...ADULT, firstName: '   ' }, 'body.firstName'],
    ['a date that does not exist', { ...ADULT, birthdate: '2001-02-30' }, 'body.birthdate'],
    ['a birthday in the future', { ...ADULT, birthdate: '2999-01-01' }, 'body.birthdate'],
    ['a birthday before 1900', { ...ADULT, birthdate: '1899-12-31' }, 'body.birthdate'],
    ['nobody to see', { ...ADULT, showMe: [] }, 'body.showMe'],
  ])('refuses %s with 400 and the field path, never the value', async (_name, body, path) => {
    const p = await person();
    const res = await saveProfile(p, body);
    expect(res.status).toBe(400);
    const error = (await res.json()).error;
    expect(error.code).toBe('bad_request');
    expect(error.issues.map((i: { path: string }) => i.path)).toContain(path);
    const sent = (body as Record<string, unknown>)[path.split('.')[1]!];
    if (typeof sent === 'string' && sent.trim().length > 0) {
      expect(JSON.stringify(error)).not.toContain(sent);
    }
  });

  it('walks profile → photos → notifications → complete, and the guard opens only at the end', async () => {
    const p = await person();
    await expect(assertOnboardingComplete(p.id, serviceDb())).rejects.toMatchObject({
      status: 409,
      code: 'onboarding_incomplete',
    });

    const saved = await saveProfile(p, { ...ADULT, firstName: '  Robin  ' });
    expect(saved.status).toBe(200);
    const afterProfile = await saved.json();
    expect(afterProfile.onboardingStep).toBe('photos');
    expect(afterProfile.profile).toMatchObject({
      firstName: 'Robin',
      birthdate: '1999-04-12',
      gender: 'nonbinary',
      showMe: ['woman', 'man'],
    });

    // Finishing early is refused.
    const early = await finish(p);
    expect(early.status).toBe(409);
    expect((await early.json()).error.code).toBe('onboarding_incomplete');

    const added = await upload(p, 0);
    expect(added.status).toBe(201);
    const photo = await added.json();
    expect(photo).toMatchObject({
      position: 0,
      moderationStatus: 'approved',
      url: `/api/me/photos/${photo.id}`,
    });
    expect((await me(p)).onboardingStep).toBe('notifications');

    // Finishing doesn't depend on notifications: the app calls it whether or not push was allowed.
    const finished = await finish(p);
    expect(finished.status).toBe(200);
    const done = await finished.json();
    expect(done.onboardingStep).toBe('complete');
    expect(uuidsIn(done)).toEqual([p.id, photo.id, photo.id]);
    await expect(assertOnboardingComplete(p.id, serviceDb())).resolves.toBeUndefined();
    // Idempotent.
    expect((await (await finish(p)).json()).onboardingStep).toBe('complete');
  });

  it('serves my own photo without metadata and never caches it', async () => {
    const p = await person();
    const added = await (await upload(p, 0)).json();
    const res = await call(getPhoto, {
      path: `/api/me/photos/${added.id}`,
      token: p.token,
      params: { id: added.id },
    });
    expect(res.status).toBe(200);
    expect(res.headers.get('content-type')).toBe('image/jpeg');
    expect(res.headers.get('cache-control')).toContain('no-store');
    const bytes = new Uint8Array(await res.arrayBuffer());
    // The fixture's JPEG comment (its moderation marker) was stripped before storing.
    expect(Buffer.from(bytes).toString('latin1')).not.toContain('glow-moderation-fixture');
    const meta = await sharp(bytes).metadata();
    expect([meta.width, meta.height, meta.comments ?? []]).toEqual([64, 80, []]);
  });

  it("someone else's photo is 404, exactly like one that doesn't exist (P11)", async () => {
    const [owner, other] = await Promise.all([person(), person()]);
    const photo = await (await upload(owner, 0)).json();
    const missing = crypto.randomUUID();

    for (const id of [photo.id, missing]) {
      const read = await call(getPhoto, {
        path: `/api/me/photos/${id}`,
        token: other.token,
        params: { id },
      });
      const remove = await call(deletePhoto, {
        method: 'DELETE',
        path: `/api/me/photos/${id}`,
        token: other.token,
        params: { id },
      });
      expect([read.status, remove.status]).toEqual([404, 404]);
      expect(await read.json()).toEqual({ error: { code: 'not_found', message: 'Not found.' } });
    }
    // Still there for its owner.
    expect((await me(owner)).photos).toHaveLength(1);
  });

  it('a photo held as possibly under 18 is stored but never finishes onboarding (P10)', async () => {
    const p = await person();
    await saveProfile(p);
    const res = await upload(p, 0, ['possibly_minor']);
    expect(res.status).toBe(201);
    expect((await res.json()).moderationStatus).toBe('held');
    const body = await me(p);
    expect(body.onboardingStep).toBe('photos');
    await expect(finishOnboarding(serviceDb(), p.id)).rejects.toBeInstanceOf(HttpError);
  });

  it('a rejected photo is 422 photo_rejected with its reason, and nothing is stored', async () => {
    const p = await person();
    const res = await upload(p, 0, ['nudity']);
    expect(res.status).toBe(422);
    expect((await res.json()).error).toMatchObject({ code: 'photo_rejected', reason: 'nudity' });
    expect((await me(p)).photos).toEqual([]);
    const { data } = await admin().storage.from('profile-photos').list(p.id);
    expect(data).toEqual([]);
  });

  it('a moderation outage is 503 and stores nothing (fail closed)', async () => {
    const p = await person();
    const res = await upload(p, 0, ['error']);
    expect(res.status).toBe(503);
    expect((await res.json()).error).toMatchObject({ code: 'unavailable', reason: 'moderation' });
    expect((await me(p)).photos).toEqual([]);
  });

  it('refuses something that is not a 4:5 JPEG', async () => {
    const p = await person();
    const square = await sharp({
      create: { width: 80, height: 80, channels: 3, background: '#fff' },
    })
      .jpeg()
      .toBuffer();
    const png = await sharp({ create: { width: 64, height: 80, channels: 3, background: '#fff' } })
      .png()
      .toBuffer();
    const post = (photo: string) =>
      call(postPhoto, {
        method: 'POST',
        path: '/api/me/photos',
        token: p.token,
        json: { position: 0, photo },
      });

    expect((await post(base64(new Uint8Array(square)))).status).toBe(400);
    const notJpeg = await post(base64(new Uint8Array(png)));
    expect(notJpeg.status).toBe(422);
    expect((await notJpeg.json()).error).toMatchObject({
      code: 'photo_rejected',
      reason: 'unreadable',
    });
    expect((await post('not base64!')).status).toBe(400);
  });

  it('uploading to a used position replaces that photo, file and all', async () => {
    const p = await person();
    const first = await (await upload(p, 1)).json();
    const second = await (await upload(p, 1)).json();
    expect(second.id).not.toBe(first.id);
    const body = await me(p);
    expect(body.photos.map((x: { id: string }) => x.id)).toEqual([second.id]);
    const { data } = await admin().storage.from('profile-photos').list(p.id);
    expect(data?.map((f) => f.name)).toEqual([`${second.id}.jpg`]);
  });

  it('a finished profile keeps its last approved photo (409 last_photo); before that it can go', async () => {
    const p = await person();
    await saveProfile(p);
    const only = await (await upload(p, 0)).json();

    // Before finishing, removing it is fine and steps back to photos.
    const early = await call(deletePhoto, {
      method: 'DELETE',
      path: `/api/me/photos/${only.id}`,
      token: p.token,
      params: { id: only.id },
    });
    expect(early.status).toBe(204);
    expect((await me(p)).onboardingStep).toBe('photos');

    const again = await (await upload(p, 0)).json();
    const held = await (await upload(p, 1, ['possibly_minor'])).json();
    await finishOnboarding(serviceDb(), p.id);

    const del = (id: string) =>
      call(deletePhoto, {
        method: 'DELETE',
        path: `/api/me/photos/${id}`,
        token: p.token,
        params: { id },
      });
    const last = await del(again.id);
    expect(last.status).toBe(409);
    expect((await last.json()).error.code).toBe('last_photo');
    // A held one can go: it was never what kept the profile finished.
    expect((await del(held.id)).status).toBe(204);
    expect((await me(p)).onboardingStep).toBe('complete');
  });
});

describe.skipIf(!supabaseUp)('POST /api/dev/test-login', () => {
  afterEach(async () => {
    await Promise.all(people.splice(0).map(removePerson));
  });

  it('is a 404 unless ALLOW_TEST_LOGIN is on', async () => {
    useLiveSupabase();
    const res = await call(testLogin, {
      method: 'POST',
      path: '/api/dev/test-login',
      json: { email: 'nobody@glow.test' },
    });
    expect(res.status).toBe(404);
  });

  it('signs in a @glow.test person with a real session, creating them if needed', async () => {
    useLiveSupabase({ testLogin: true });
    const email = `b1-test-${crypto.randomUUID().slice(0, 12)}@glow.test`;
    const res = await call(testLogin, {
      method: 'POST',
      path: '/api/dev/test-login',
      json: { email },
    });
    expect(res.status).toBe(200);
    const session = await res.json();
    expect(session).toMatchObject({ userId: expect.any(String), expiresIn: expect.any(Number) });
    people.push({ id: session.userId, email, token: session.accessToken });

    // The token works on the real API, and a second sign-in is the same person.
    const body = await (await call(getMe, { path: '/api/me', token: session.accessToken })).json();
    expect(body.id).toBe(session.userId);
    const again = await (
      await call(testLogin, { method: 'POST', path: '/api/dev/test-login', json: { email } })
    ).json();
    expect(again.userId).toBe(session.userId);
  });

  it('refuses anything that is not a @glow.test address', async () => {
    useLiveSupabase({ testLogin: true });
    for (const email of ['someone@example.com', 'Alex@glow.test', 'alex@glow.test.example.com']) {
      const res = await call(testLogin, {
        method: 'POST',
        path: '/api/dev/test-login',
        json: { email },
      });
      expect(res.status).toBe(400);
    }
  });
});
