/**
 * Glue between the admin module and Next.js pages and server actions.
 *
 * - Pages call `adminPage()` first: anyone who isn't a signed-in admin gets Next's 404, the
 *   same page and status as an address that doesn't exist.
 * - Server actions are public POST endpoints, so each one calls `adminAction()` first, then
 *   runs its work through `attempt()`, which turns the module's HttpErrors into a message the
 *   page can show. Nothing about the error beyond its plain message reaches the browser.
 */
import { notFound, unstable_rethrow } from 'next/navigation';
import { z } from 'zod';
import { HttpError } from '@/server/http';
import { logger } from '@/server/log';
import { currentAdmin, type AdminSession } from './session';

export async function adminPage(): Promise<AdminSession> {
  const admin = await currentAdmin();
  if (!admin) notFound();
  return admin;
}

/** For server actions: the same rule as pages. */
export const adminAction = adminPage;

/** A room or report ID from the address. Anything that isn't a UUID can't exist. */
export function idOrNotFound(value: string): string {
  const parsed = z.uuid().safeParse(value);
  if (!parsed.success) notFound();
  return parsed.data.toLowerCase();
}

/** Runs page work; a 404 from the module becomes Next's 404. */
export async function orNotFound<T>(work: () => Promise<T>): Promise<T> {
  try {
    return await work();
  } catch (error) {
    if (error instanceof HttpError && error.status === 404) notFound();
    throw error;
  }
}

export type ActionResult<T = null> =
  { readonly ok: true; readonly value: T } | { readonly ok: false; readonly message: string };

export async function attempt<T>(name: string, work: () => Promise<T>): Promise<ActionResult<T>> {
  try {
    return { ok: true, value: await work() };
  } catch (error) {
    unstable_rethrow(error);
    if (error instanceof HttpError) {
      if (error.status === 404) return { ok: false, message: "That's gone. Refresh the page." };
      if (error.status < 500) return { ok: false, message: error.message };
    }
    logger.error('admin.action_failed', {
      action: name,
      errorClass: error instanceof Error ? error.name : typeof error,
    });
    return { ok: false, message: 'Something went wrong. Try again.' };
  }
}

/** Validates action input with a contract schema; field paths only, never values. */
export function parseInput<S extends z.ZodType>(schema: S, input: unknown): z.output<S> {
  const parsed = schema.safeParse(input);
  if (!parsed.success) {
    const fields = [...new Set(parsed.error.issues.map((i) => i.path.join('.') || 'input'))];
    throw new HttpError(400, 'bad_request', `Check ${fields.join(', ')}.`);
  }
  return parsed.data;
}
