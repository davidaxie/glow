/**
 * The moderation model behind `moderateImage` and `moderateText`, as an interface so tests
 * and local development can run without an Anthropic key.
 *
 * Which one runs (`activeModel()`):
 * - `ANTHROPIC_API_KEY` set: Claude (`./claude.ts`). Card photos fail closed on any error.
 * - no key and the env profile is `local` (laptop, CI, Vitest): the deterministic fake in
 *   `./fake.ts`, which approves everything except fixtures marked otherwise.
 * - no key anywhere else: refuse. `server/src/env.ts` already makes the key required on
 *   every Vercel deploy, so this branch only guards against that rule ever changing.
 */
import { getEnv } from '@/env';
import { logger } from '@/server/log';
import { claudeModerationModel } from './claude';
import { fakeModerationModel } from './fake';
import type { ImageFindings, ImageKind, TextFindings } from './types';

export type ImageInput = {
  readonly kind: ImageKind;
  /** The photo as uploaded. Only the fake reads it, to find fixture markers. */
  readonly original: Uint8Array;
  /** The downscaled, metadata-free JPEG that goes to the model. */
  readonly jpeg: Uint8Array;
  readonly signal: AbortSignal;
};

export type TextInput = {
  readonly body: string;
  readonly signal: AbortSignal;
};

/** A model refused to classify. Treated as a reject for photos and a flag for text. */
export class ModelRefusal extends Error {
  override readonly name = 'ModelRefusal';
}

export interface ModerationModel {
  readonly name: 'claude' | 'fake' | 'test';
  classifyImage(input: ImageInput): Promise<ImageFindings>;
  classifyText(input: TextInput): Promise<TextFindings>;
}

let override: ModerationModel | undefined;
let claude: { key: string; model: ModerationModel } | undefined;
let warnedFake = false;

export function activeModel(): ModerationModel {
  if (override) return override;
  const env = getEnv();
  if (env.ANTHROPIC_API_KEY) {
    if (claude?.key !== env.ANTHROPIC_API_KEY) {
      claude = { key: env.ANTHROPIC_API_KEY, model: claudeModerationModel(env.ANTHROPIC_API_KEY) };
    }
    return claude.model;
  }
  if (env.profile === 'local') {
    if (!warnedFake) {
      warnedFake = true;
      logger.warn('moderation.fake_in_use', { profile: env.profile });
    }
    return fakeModerationModel;
  }
  throw new Error('ANTHROPIC_API_KEY is required outside local development.');
}

/** For tests only: use this model until called again with `undefined`. */
export function setModerationModelForTests(model: ModerationModel | undefined): void {
  override = model;
}
