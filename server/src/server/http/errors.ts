/**
 * Errors a route can throw. The route helper turns each one into the contract's
 * error body. There is deliberately no `forbidden()`: anything the caller isn't
 * allowed to see is "not found" (P11), so its existence never leaks.
 *
 *   throw notFound();
 *   throw conflict('tap_limit_reached', 'You have no taps left in this room today.');
 *   throw unprocessable('not_in_room', 'Looks like you are not in this room yet.');
 *   throw unprocessable('photo_rejected', 'Try another photo.', { reason: 'face_visible' });
 */
import type { ErrorCode as ContractErrorCode } from '@/contracts';

/** Every code in the contract's `ErrorCode` enum, and nothing else. */
export type ErrorCode = ContractErrorCode;

export type ErrorIssue = { readonly path: string; readonly code: string; readonly message: string };

export type ErrorBody = {
  readonly error: {
    readonly code: ErrorCode;
    readonly message: string;
    readonly reason?: string;
    readonly issues?: readonly ErrorIssue[];
  };
};

type ErrorOptions = {
  readonly reason?: string;
  readonly issues?: readonly ErrorIssue[];
  readonly headers?: Record<string, string>;
};

export class HttpError extends Error {
  readonly status: number;
  readonly code: ErrorCode;
  readonly reason: string | undefined;
  readonly issues: readonly ErrorIssue[] | undefined;
  readonly headers: Readonly<Record<string, string>> | undefined;

  constructor(status: number, code: ErrorCode, message: string, options: ErrorOptions = {}) {
    super(message);
    this.name = 'HttpError';
    this.status = status;
    this.code = code;
    this.reason = options.reason;
    this.issues = options.issues;
    this.headers = options.headers;
  }
}

/** The one answer for "doesn't exist" and "you may not see it" alike (P11). */
export const notFound = () => new HttpError(404, 'not_found', 'Not found.');

export const badRequest = (message = 'The request is not valid.', issues?: readonly ErrorIssue[]) =>
  new HttpError(400, 'bad_request', message, issues ? { issues } : {});

export const unauthorized = () =>
  new HttpError(401, 'unauthorized', 'Sign in again to continue.', {
    headers: { 'WWW-Authenticate': 'Bearer' },
  });

/** 409: the request is fine, but the current state says no (`tap_limit_reached`, ...). */
export const conflict = (
  code: ErrorCode = 'conflict',
  message = 'That conflicts with the current state.',
  options: Pick<ErrorOptions, 'reason'> = {},
) => new HttpError(409, code, message, options);

/** 422: well-formed, but it can't be accepted (`not_in_room`, `photo_rejected`, ...). */
export const unprocessable = (
  code: ErrorCode,
  message: string,
  options: Pick<ErrorOptions, 'reason'> = {},
) => new HttpError(422, code, message, options);

export const rateLimited = (retryAfterSeconds: number) =>
  new HttpError(429, 'rate_limited', 'Slow down a little and try again.', {
    headers: { 'Retry-After': String(Math.max(1, Math.ceil(retryAfterSeconds))) },
  });

export const unavailable = (
  message = 'Something is briefly unavailable. Try again.',
  options: Pick<ErrorOptions, 'reason'> = {},
) => new HttpError(503, 'unavailable', message, { ...options, headers: { 'Retry-After': '2' } });

export const notImplementedError = () =>
  new HttpError(501, 'not_implemented', 'This endpoint is not built yet.');

/** Use as the handler for an endpoint nobody has built yet. */
export function notImplemented(): never {
  throw notImplementedError();
}

export function errorBody(error: HttpError): ErrorBody {
  return {
    error: {
      code: error.code,
      message: error.message,
      ...(error.reason ? { reason: error.reason } : {}),
      ...(error.issues && error.issues.length > 0 ? { issues: error.issues } : {}),
    },
  };
}
