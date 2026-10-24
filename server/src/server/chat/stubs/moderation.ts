/**
 * Owner: C4. STAND-IN for B8's `moderateText(body)` and `messageRejected()` from
 * `@/server/moderation` (PR #12), until it merges (AGENTS.md, "Mocks"). Same signatures and
 * the same fixture markers as B8's local fake, so the tests pass unchanged against the real
 * module. When #12 merges, point `../dependencies.ts` at `@/server/moderation` and delete
 * this file.
 *
 * B8's version asks Claude (or, without ANTHROPIC_API_KEY and only locally, a deterministic
 * fake) within MODERATION_TIMEOUT, and never throws. This one passes everything except the
 * markers below, and answers `pending` at once for the slow and outage markers. It never
 * logs the body.
 */
import { unprocessable, type HttpError } from '@/server/http';

export const TEXT_FIXTURE = {
  flag: '[glow-test:flag]',
  slow: '[glow-test:slow]',
  error: '[glow-test:error]',
} as const;

export type TextModeration =
  | { readonly decision: 'passed' }
  | { readonly decision: 'flagged'; readonly category: string }
  | { readonly decision: 'pending' };

export async function moderateText(body: string): Promise<TextModeration> {
  if (body.includes(TEXT_FIXTURE.flag)) return { decision: 'flagged', category: 'harassment' };
  if (body.includes(TEXT_FIXTURE.slow) || body.includes(TEXT_FIXTURE.error)) {
    return { decision: 'pending' };
  }
  return { decision: 'passed' };
}

/** 422 `message_rejected`, for a flagged chat message. */
export function messageRejected(): HttpError {
  return unprocessable('message_rejected', 'This message cannot be sent.');
}
