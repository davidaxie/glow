/**
 * Owner: B8. The route handlers for B8's endpoints. Each route file is one line:
 *
 *   export const POST = route('createBlock', createBlock);
 *
 * Each handler counts the request against its rate limit policy first (`limitRequest`
 * counts a request once, so this stays right when the route helper does it too).
 */
import type { RouteHandler } from '@/server/http';
import { limitRequest } from '@/server/ratelimit';
import { deleteAccountFor } from './account';
import { blockFor, reportFor } from './block';
import { logCaptureFor } from './capture';
import { setPausedFor } from './pause';
import { runPurgeJob } from './purge';

export const createBlock: RouteHandler<'createBlock'> = async ({ req, user, body }) => {
  await limitRequest('createBlock', req, user);
  await blockFor(user.id, body);
  return { status: 204 };
};

export const createReport: RouteHandler<'createReport'> = async ({ req, user, body }) => {
  await limitRequest('createReport', req, user);
  await reportFor(user.id, body);
  return { status: 204 };
};

export const setPaused: RouteHandler<'setPaused'> = async ({ req, user, body }) => {
  await limitRequest('setPaused', req, user);
  return { status: 200, body: await setPausedFor(user.id, body.paused) };
};

export const logCapture: RouteHandler<'logCapture'> = async ({ req, user, body }) => {
  await limitRequest('logCapture', req, user);
  await logCaptureFor(user.id, body);
  return { status: 204 };
};

export const deleteAccount: RouteHandler<'deleteAccount'> = async ({ req, user }) => {
  await limitRequest('deleteAccount', req, user);
  await deleteAccountFor(user.id);
  return { status: 204 };
};

export const runPurge: RouteHandler<'runPurge'> = async () => ({
  status: 200,
  body: await runPurgeJob(),
});
