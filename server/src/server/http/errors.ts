/**
 * Errors a route can throw. The route helper turns each one into the contract's
 * error body. There is deliberately no `forbidden()`: anything the caller isn't
 * allowed to see is "not found" (P11), so its existence never leaks.
 */

export type ErrorCode =
  | 'bad_request'
  | 'unauthorized'
  | 'not_found'
  | 'conflict'
  | 'payload_too_large'
  | 'unsupported_media_type'
  | 'rate_limited'
  | 'internal'
  | 'not_implemented'
  | 'unavailable'
  | (string & {});

export type ErrorIssue = { readonly path: string; readonly code: string; readonly message: string };

export type ErrorBody = {
  readonly error: {
    readonly code: ErrorCode;
    readonly message: string;
    readonly issues?: readonly ErrorIssue[];
  };
};

export class HttpError extends Error {
  readonly status: number;
  readonly code: ErrorCode;
  readonly issues: readonly ErrorIssue[] | undefined;
  readonly headers: Readonly<Record<string, string>> | undefined;

  constructor(
    status: number,
    code: ErrorCode,
    message: string,
    options: { issues?: readonly ErrorIssue[]; headers?: Record<string, string> } = {},
  ) {
    super(message);
    this.name = 'HttpError';
    this.status = status;
    this.code = code;
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

export const conflict = (message = 'That conflicts with the current state.') =>
  new HttpError(409, 'conflict', message);

export const rateLimited = (retryAfterSeconds: number) =>
  new HttpError(429, 'rate_limited', 'Slow down a little and try again.', {
    headers: { 'Retry-After': String(Math.max(1, Math.ceil(retryAfterSeconds))) },
  });

export const unavailable = (message = 'Something is briefly unavailable. Try again.') =>
  new HttpError(503, 'unavailable', message, { headers: { 'Retry-After': '2' } });

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
      ...(error.issues && error.issues.length > 0 ? { issues: error.issues } : {}),
    },
  };
}
