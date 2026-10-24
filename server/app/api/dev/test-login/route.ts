// Owner: B1. Debug-only test sign-in: `proxy.ts` and the handler both answer 404 unless
// ALLOW_TEST_LOGIN is on in a local profile. The handler lives in `server/src/server/profiles`.
import { route } from '@/server/http';
import { testLogin } from '@/server/profiles/test-login';

export const POST = route('testLogin', testLogin);
