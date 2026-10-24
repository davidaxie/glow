// Owner: C3. The handler lives in server/src/server/glow.
import { route } from '@/server/http';
import { getGlowFor } from '@/server/glow';

export const GET = route('getGlow', getGlowFor);
