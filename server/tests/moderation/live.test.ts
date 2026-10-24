/**
 * Real Claude moderation. Runs only when ANTHROPIC_API_KEY is set (read once at import,
 * before tests/setup.ts resets the env), and spends a few cents each run.
 *
 * - p95 latency under MODERATION_TIMEOUT (2.5 s) for card photos and chat messages, over
 *   SAMPLES sequential calls each.
 * - Every photo in tests/moderation/fixtures/live/ is decided as its name says:
 *   `approve-*.jpg`, `reject-face_visible-*.jpg`, `reject-nudity-*.jpg` (any reject reason),
 *   or `hold-*.jpg` (a profile photo held for review). These need real photos that the
 *   people in them agreed to, so none are committed; see docs/HANDOFFS.md, Needs David.
 */
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { MODERATION_TIMEOUT_MS } from '@/contracts';
import {
  moderateImage,
  moderateText,
  setModerationModelForTests,
  type ImageKind,
} from '@/server/moderation';
import { claudeModerationModel } from '@/server/moderation/claude';

const KEY = process.env.ANTHROPIC_API_KEY;
const SAMPLES = 20;
const SYNTHETIC = new URL('../../../ios/fixtures/photos/', import.meta.url);
const LIVE_FIXTURES = new URL('./fixtures/live/', import.meta.url);

const jpegs = (dir: URL) =>
  existsSync(dir)
    ? readdirSync(dir)
        .filter((f) => f.endsWith('.jpg'))
        .sort()
    : [];

const p95 = (ms: number[]) => [...ms].sort((a, b) => a - b)[Math.ceil(ms.length * 0.95) - 1] ?? 0;

async function timed<T>(work: () => Promise<T>): Promise<number> {
  const started = performance.now();
  try {
    await work();
  } catch {
    return Number.POSITIVE_INFINITY; // a timeout or outage counts as too slow
  }
  return performance.now() - started;
}

describe.skipIf(!KEY)('Claude moderation, live', () => {
  beforeAll(() => setModerationModelForTests(claudeModerationModel(KEY!)));
  afterAll(() => setModerationModelForTests(undefined));

  it(`answers card photos in under ${MODERATION_TIMEOUT_MS} ms at p95`, async () => {
    const photos = jpegs(SYNTHETIC).map((f) => new Uint8Array(readFileSync(new URL(f, SYNTHETIC))));
    expect(photos.length).toBeGreaterThan(0);
    const ms: number[] = [];
    for (let i = 0; i < SAMPLES; i++) {
      ms.push(await timed(() => moderateImage('card', photos[i % photos.length]!)));
    }
    expect(p95(ms)).toBeLessThan(MODERATION_TIMEOUT_MS);
  }, 180_000);

  it(`answers chat messages in under ${MODERATION_TIMEOUT_MS} ms at p95`, async () => {
    const bodies = ['hey, I like your jacket', 'want to meet by the stage?', 'see you at 9!'];
    const ms: number[] = [];
    for (let i = 0; i < SAMPLES; i++) {
      const started = performance.now();
      const verdict = await moderateText(bodies[i % bodies.length]!);
      ms.push(verdict.decision === 'pending' ? Infinity : performance.now() - started);
    }
    expect(p95(ms)).toBeLessThan(MODERATION_TIMEOUT_MS);
  }, 180_000);

  it('passes small talk and flags a threat', async () => {
    await expect(moderateText('Want to grab a drink by the stage?')).resolves.toEqual({
      decision: 'passed',
    });
    const threat = await moderateText('Tell me where you live or I will find you and hurt you.');
    expect(threat.decision).toBe('flagged');
  }, 30_000);

  const live = jpegs(LIVE_FIXTURES);
  it.skipIf(live.length === 0)(
    'decides every consented fixture as its name says',
    async () => {
      for (const file of live) {
        const bytes = new Uint8Array(readFileSync(new URL(file, LIVE_FIXTURES)));
        const [verdict, reason] = file.replace(/\.jpg$/, '').split('-');
        const kind: ImageKind = verdict === 'hold' ? 'profile' : 'card';
        const result = await moderateImage(kind, bytes);
        if (verdict === 'approve') expect(result, file).toMatchObject({ decision: 'approved' });
        if (verdict === 'hold') expect(result, file).toMatchObject({ decision: 'held' });
        if (verdict === 'reject') {
          expect(result, file).toMatchObject({ decision: 'rejected', reason });
        }
      }
    },
    180_000,
  );
});
