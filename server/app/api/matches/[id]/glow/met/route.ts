// Owner: C3. The handler lives in server/src/server/glow.
import { route } from '@/server/http';
import { markGlowMetFor } from '@/server/glow';

export const POST = route('markGlowMet', markGlowMetFor);
