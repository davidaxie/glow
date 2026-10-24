// Owner: A1. Runs once when a server instance starts.
import * as Sentry from '@sentry/nextjs';
import { getEnv } from '@/env';
import { scrubEvent } from '@/server/observability';

export async function register() {
  // Fails the instance with the same readable message as next.config.ts, in case the
  // runtime environment differs from the build's (as it can on Vercel).
  const env = getEnv();

  if (process.env.NEXT_RUNTIME === 'nodejs' && env.SENTRY_DSN) {
    Sentry.init({
      dsn: env.SENTRY_DSN,
      environment: env.profile,
      // Collect nothing about people or requests. Local variables can hold
      // coordinates or message text, so stack frame variables are off too (P2).
      dataCollection: {
        userInfo: false,
        cookies: false,
        httpHeaders: false,
        httpBodies: [],
        urlQueryParams: false,
        graphQL: { document: false, variables: false },
        genAI: { inputs: false, outputs: false },
        databaseQueryData: false,
        queues: false,
        stackFrameVariables: false,
      },
      tracesSampleRate: 0,
      beforeSend: scrubEvent,
      beforeBreadcrumb: (crumb) => (crumb.category === 'console' ? null : crumb),
    });
  }
}

// A no-op when Sentry was never initialised (SENTRY_DSN unset).
export const onRequestError = Sentry.captureRequestError;
