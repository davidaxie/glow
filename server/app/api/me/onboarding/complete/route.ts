// Owner: B1. The handler lives in `server/src/server/profiles`.
import { route } from '@/server/http';
import { completeOnboarding } from '@/server/profiles/finish';

export const POST = route('completeOnboarding', completeOnboarding);
