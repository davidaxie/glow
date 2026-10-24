// Owner: A1. Any /api path that isn't in the contract gets the same JSON 404.
import { errorBody, notFound } from '@/server/http/errors';

function notInContract(): Response {
  return Response.json(errorBody(notFound()), {
    status: 404,
    headers: { 'cache-control': 'no-store, max-age=0' },
  });
}

export const GET = notInContract;
export const POST = notInContract;
export const PUT = notInContract;
export const PATCH = notInContract;
export const DELETE = notInContract;
