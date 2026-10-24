// Owner: B1. The handler lives in `server/src/server/profiles`.
import { route } from '@/server/http';
import { updateProfile } from '@/server/profiles/profile';

export const PUT = route('updateProfile', updateProfile);
