/**
 * Database functions fail with SQLSTATE P0001 and an error code as the message
 * (docs/CONTRACTS.md, "Database errors"). This turns them into the API's errors.
 */
import {
  badRequest,
  conflict,
  notFound,
  unavailable,
  unprocessable,
  type ErrorCode,
  type HttpError,
} from '@/server/http';

type PostgrestLikeError = { readonly code?: string; readonly message?: string } | null | undefined;

const CONFLICT_CODES = new Set<ErrorCode>([
  'room_not_live',
  'onboarding_incomplete',
  'tap_limit_reached',
  'chat_not_open',
]);
const UNPROCESSABLE_CODES = new Set<ErrorCode>([
  'location_required',
  'join_ticket_invalid',
  'not_in_room',
]);

/** The database's own error code, if this is one of our P0001 errors. */
export function dbErrorCode(error: PostgrestLikeError): string | null {
  if (!error || error.code !== 'P0001' || typeof error.message !== 'string') return null;
  return /^[a-z_]{3,40}$/.test(error.message) ? error.message : null;
}

/** The HTTP error for a failed database call. Anything unexpected is a 503, never details. */
export function httpErrorFor(error: PostgrestLikeError): HttpError {
  const code = dbErrorCode(error);
  if (code === 'not_found') return notFound();
  if (code === 'invalid_input') return badRequest();
  if (code && CONFLICT_CODES.has(code as ErrorCode)) {
    return conflict(code as ErrorCode, 'Not possible right now.');
  }
  if (code && UNPROCESSABLE_CODES.has(code as ErrorCode)) {
    return unprocessable(code as ErrorCode, 'Not possible right now.');
  }
  return unavailable();
}
