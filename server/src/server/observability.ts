/**
 * Error reporting. Sentry only runs when SENTRY_DSN is set (see instrumentation.ts);
 * otherwise every call here is a no-op. Reports carry the error and a few tags, never
 * request bodies, headers, coordinates or names.
 */
import * as Sentry from '@sentry/nextjs';
import type { ErrorEvent } from '@sentry/nextjs';

export function captureError(error: unknown, tags: Readonly<Record<string, string>> = {}): void {
  if (!process.env.SENTRY_DSN) return;
  Sentry.captureException(error, { tags: { ...tags } });
}

/** Strips everything about the request except its method and route, before sending. */
export function scrubEvent(event: ErrorEvent): ErrorEvent {
  if (event.request) {
    const { method, url } = event.request;
    event.request = {
      ...(method ? { method } : {}),
      ...(url ? { url: url.split('?')[0] } : {}),
    };
  }
  delete event.user;
  delete event.extra;
  if (event.contexts) {
    delete event.contexts.geo;
    delete event.contexts.location;
  }
  event.breadcrumbs = (event.breadcrumbs ?? []).map((b) => ({
    ...(b.timestamp !== undefined ? { timestamp: b.timestamp } : {}),
    ...(b.category !== undefined ? { category: b.category } : {}),
    ...(b.level !== undefined ? { level: b.level } : {}),
  }));
  return event;
}
