import type { z } from 'zod';

/**
 * The shape the route helper needs for each API operation. A2's codegen produces
 * one of these per `operationId` in contracts/openapi.yaml.
 */

export type HttpMethod = 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE';

/**
 * - `user`: a signed-in person's Supabase access token (the default).
 * - `public`: no sign-in, for the link file, the web fallback page and test sign-in.
 * - `cron`: the cron secret, for the purge job.
 */
export type AuthKind = 'user' | 'public' | 'cron';

/** A JSON body schema, or `multipart` for uploads (the handler gets FormData). */
export type BodySpec = z.ZodType | 'multipart';

/**
 * A JSON response schema, `null` for no body (204), or `raw` when the handler
 * returns its own Response (images, HTML, the link file).
 */
export type ResponseSpec = z.ZodType | 'raw' | null;

export type OperationDef = {
  readonly method: HttpMethod;
  /** The OpenAPI path, for example `/api/matches/{id}`. */
  readonly path: string;
  readonly auth: AuthKind;
  readonly params?: z.ZodType;
  readonly query?: z.ZodType;
  readonly body?: BodySpec;
  /** Largest accepted request body in bytes. Defaults to 64 KB for JSON and 8 MB for uploads. */
  readonly maxBodyBytes?: number;
  readonly responses: Readonly<Record<number, ResponseSpec>>;
};

/** Keeps literal types, so handlers are typed from the operation they serve. */
export function defineOperations<const T extends Record<string, OperationDef>>(ops: T): T {
  return ops;
}
