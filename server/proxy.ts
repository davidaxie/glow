// Owner: A1. Next.js 16 calls this "proxy" (it used to be middleware). Keep it small:
// route-level checks belong in the route helper, not here.
import { NextResponse, type NextRequest } from 'next/server';
import { getEnv } from '@/env';
import { errorBody, notFound } from '@/server/http/errors';

/**
 * Dev-only routes (test sign-in) don't exist unless ALLOW_TEST_LOGIN is on in a local
 * profile. env.ts already refuses ALLOW_TEST_LOGIN on Vercel or with a cloud Supabase;
 * this is a second lock, and it answers 404 so the route's existence never shows.
 */
export function proxy(request: NextRequest) {
  if (request.nextUrl.pathname.startsWith('/api/dev/')) {
    const env = getEnv();
    if (env.profile !== 'local' || !env.ALLOW_TEST_LOGIN) {
      return NextResponse.json(errorBody(notFound()), {
        status: 404,
        headers: { 'cache-control': 'no-store, max-age=0' },
      });
    }
  }
  return NextResponse.next();
}

export const config = {
  matcher: '/api/dev/:path*',
};
