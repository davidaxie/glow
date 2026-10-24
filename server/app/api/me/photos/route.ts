// Owner: B1. The handler lives in `server/src/server/profiles`.
import { route } from '@/server/http';
import { addProfilePhoto } from '@/server/profiles/photos';

export const POST = route('addProfilePhoto', addProfilePhoto);
