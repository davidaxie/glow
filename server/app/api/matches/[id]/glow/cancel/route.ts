// Owner: C3. The handler lives in server/src/server/glow.
import { route } from '@/server/http';
import { cancelGlowFor } from '@/server/glow';

export const POST = route('cancelGlow', cancelGlowFor);
