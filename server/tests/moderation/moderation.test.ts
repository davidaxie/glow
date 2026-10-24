import { afterEach, describe, expect, it, vi } from 'vitest';
import { parseEnv } from '@/env';
import { HttpError } from '@/server/http';
import {
  decideImage,
  messageRejected,
  moderateImage,
  moderateText,
  moderationFixtureJpeg,
  ModerationUnavailableError,
  photoRejected,
  reviewText,
  setModerationModelForTests,
  TEXT_FIXTURE,
  type ImageFindings,
} from '@/server/moderation';
import { activeModel, ModelRefusal, type ModerationModel } from '@/server/moderation/model';
import { imageFixtureFlags } from '@/server/moderation/fake';
import { PRODUCTION_ENV } from '../helpers/env';

const clean: ImageFindings = {
  personPresent: true,
  faceVisible: false,
  nudity: false,
  outfitVisible: true,
  possiblyUnder18: false,
};

afterEach(() => {
  setModerationModelForTests(undefined);
  vi.useRealTimers();
});

describe('decideImage', () => {
  it('approves a clean outfit card and a clean profile photo', () => {
    expect(decideImage('card', clean)).toMatchObject({ decision: 'approved' });
    expect(decideImage('profile', { ...clean, faceVisible: true })).toMatchObject({
      decision: 'approved',
    });
  });

  it.each([
    [{ faceVisible: true }, 'face_visible'],
    [{ nudity: true }, 'nudity'],
    [{ outfitVisible: false }, 'no_outfit'],
    [{ personPresent: false, outfitVisible: false }, 'no_person'],
    [{ possiblyUnder18: true }, 'possibly_minor'],
    [{ nudity: true, faceVisible: true }, 'nudity'],
    [{ faceVisible: true, possiblyUnder18: true }, 'face_visible'],
  ] as const)('rejects a card with %o as %s', (change, reason) => {
    expect(decideImage('card', { ...clean, ...change })).toMatchObject({
      decision: 'rejected',
      reason,
    });
  });

  it('rejects nudity and empty profile photos, and holds a possible minor for review', () => {
    expect(decideImage('profile', { ...clean, nudity: true })).toMatchObject({
      decision: 'rejected',
      reason: 'nudity',
    });
    expect(decideImage('profile', { ...clean, personPresent: false })).toMatchObject({
      decision: 'rejected',
      reason: 'no_person',
    });
    expect(decideImage('profile', { ...clean, possiblyUnder18: true })).toMatchObject({
      decision: 'held',
      reason: 'possibly_minor',
    });
  });
});

describe('moderateImage with the local fake', () => {
  it('uses the fake locally when there is no Anthropic key', () => {
    expect(activeModel().name).toBe('fake');
  });

  it('approves a plain photo', async () => {
    const photo = await moderationFixtureJpeg([]);
    await expect(moderateImage('card', photo)).resolves.toMatchObject({ decision: 'approved' });
  });

  it('rejects the face-visible and nude fixtures as cards', async () => {
    const face = await moderationFixtureJpeg(['face_visible']);
    const nude = await moderationFixtureJpeg(['nudity']);
    await expect(moderateImage('card', face)).resolves.toMatchObject({
      decision: 'rejected',
      reason: 'face_visible',
    });
    await expect(moderateImage('card', nude)).resolves.toMatchObject({
      decision: 'rejected',
      reason: 'nudity',
    });
    await expect(moderateImage('profile', nude)).resolves.toMatchObject({
      decision: 'rejected',
      reason: 'nudity',
    });
  });

  it('holds a possibly-minor profile photo and rejects the same card', async () => {
    const photo = await moderationFixtureJpeg(['possibly_minor']);
    await expect(moderateImage('profile', photo)).resolves.toMatchObject({ decision: 'held' });
    await expect(moderateImage('card', photo)).resolves.toMatchObject({
      decision: 'rejected',
      reason: 'possibly_minor',
    });
  });

  it('rejects anything that is not a readable JPEG without asking the model', async () => {
    const model = { ...spyModel(), classifyImage: vi.fn() };
    setModerationModelForTests(model);
    const png = Buffer.from('89504e470d0a1a0a0000000d49484452', 'hex');
    await expect(moderateImage('card', new Uint8Array(png))).resolves.toMatchObject({
      decision: 'rejected',
      reason: 'unreadable',
    });
    await expect(moderateImage('card', new Uint8Array([1, 2, 3]))).resolves.toMatchObject({
      decision: 'rejected',
      reason: 'unreadable',
    });
    expect(model.classifyImage).not.toHaveBeenCalled();
  });

  it('fails closed with a 503 when moderation is down', async () => {
    const photo = await moderationFixtureJpeg(['error']);
    const error = await moderateImage('card', photo).catch((e: unknown) => e);
    expect(error).toBeInstanceOf(ModerationUnavailableError);
    expect(error).toBeInstanceOf(HttpError);
    expect(error).toMatchObject({ status: 503, code: 'unavailable', reason: 'moderation' });
  });

  it('fails closed when moderation takes longer than MODERATION_TIMEOUT', async () => {
    const photo = await moderationFixtureJpeg(['slow']);
    vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
    const result = moderateImage('card', photo).catch((e: unknown) => e);
    await vi.advanceTimersByTimeAsync(2499);
    await vi.advanceTimersByTimeAsync(2);
    await expect(result).resolves.toBeInstanceOf(ModerationUnavailableError);
  });

  it('treats a model refusal as a rejection', async () => {
    setModerationModelForTests({
      ...spyModel(),
      classifyImage: () => Promise.reject(new ModelRefusal('refusal')),
    });
    const photo = await moderationFixtureJpeg([]);
    await expect(moderateImage('card', photo)).resolves.toMatchObject({
      decision: 'rejected',
      reason: 'unreadable',
    });
  });

  it('sends the model a small JPEG with no metadata, never the original', async () => {
    const model = spyModel();
    setModerationModelForTests(model);
    const big = await moderationFixtureJpeg([], { width: 1536, height: 1920 });
    await moderateImage('card', big);
    const sent = model.images[0];
    expect(sent).toBeDefined();
    const { default: sharp } = await import('sharp');
    const meta = await sharp(sent!).metadata();
    expect(meta.format).toBe('jpeg');
    expect(Math.max(meta.width ?? 0, meta.height ?? 0)).toBeLessThanOrEqual(768);
    expect(imageFixtureFlags(sent!).size).toBe(0);
    expect(meta.exif).toBeUndefined();
  });
});

describe('moderateText', () => {
  it('passes ordinary messages and flags the fixture', async () => {
    await expect(moderateText('Want to grab a drink by the stage?')).resolves.toEqual({
      decision: 'passed',
    });
    await expect(moderateText(`hey ${TEXT_FIXTURE.flag}`)).resolves.toEqual({
      decision: 'flagged',
      category: 'harassment',
    });
  });

  it('lets the message through as pending when moderation is slow', async () => {
    vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
    const result = moderateText(`hi ${TEXT_FIXTURE.slow}`);
    await vi.advanceTimersByTimeAsync(2501);
    await expect(result).resolves.toEqual({ decision: 'pending' });
  });

  it('lets the message through as pending when moderation is down', async () => {
    await expect(moderateText(`hi ${TEXT_FIXTURE.error}`)).resolves.toEqual({
      decision: 'pending',
    });
    await expect(reviewText(`hi ${TEXT_FIXTURE.error}`)).resolves.toEqual({
      decision: 'pending',
    });
  });

  it('flags a message the model refuses to classify', async () => {
    setModerationModelForTests({
      ...spyModel(),
      classifyText: () => Promise.reject(new ModelRefusal('refusal')),
    });
    await expect(moderateText('something')).resolves.toEqual({
      decision: 'flagged',
      category: 'other',
    });
  });

  it('never logs the message text', async () => {
    const lines: string[] = [];
    const capture = (line: unknown) => void lines.push(String(line));
    vi.spyOn(console, 'log').mockImplementation(capture);
    vi.spyOn(console, 'warn').mockImplementation(capture);
    vi.spyOn(console, 'error').mockImplementation(capture);
    await moderateText('secret-words-4417 meet me at the bar');
    await moderateText(`secret-words-4417 ${TEXT_FIXTURE.error}`);
    expect(lines.length).toBeGreaterThan(0);
    expect(lines.join('\n')).not.toContain('secret-words-4417');
  });
});

describe('errors for routes', () => {
  it('builds the contract errors', () => {
    expect(photoRejected('face_visible')).toMatchObject({
      status: 422,
      code: 'photo_rejected',
      reason: 'face_visible',
    });
    expect(messageRejected()).toMatchObject({ status: 422, code: 'message_rejected' });
  });
});

describe('the fake is local only', () => {
  it('relies on env.ts requiring ANTHROPIC_API_KEY on every Vercel deploy', () => {
    const { ANTHROPIC_API_KEY: _key, ...withoutKey } = PRODUCTION_ENV;
    for (const VERCEL_ENV of ['production', 'preview']) {
      const result = parseEnv({ ...withoutKey, VERCEL_ENV });
      expect(result.ok).toBe(false);
      if (!result.ok) expect(result.problems.map((p) => p.name)).toContain('ANTHROPIC_API_KEY');
    }
  });

  it('uses Claude whenever a key is set, even locally', () => {
    process.env.ANTHROPIC_API_KEY = 'sk-ant-test-0000000000000000000000';
    try {
      expect(activeModel().name).toBe('claude');
    } finally {
      delete process.env.ANTHROPIC_API_KEY;
    }
  });
});

function spyModel(): ModerationModel & { images: Uint8Array[] } {
  const images: Uint8Array[] = [];
  return {
    name: 'test',
    images,
    async classifyImage({ jpeg }) {
      images.push(jpeg);
      return clean;
    },
    async classifyText() {
      return { flagged: false, category: 'none' };
    },
  };
}
