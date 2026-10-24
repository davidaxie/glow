// Owner: B1. Handlers live in `server/src/server/profiles`.
import { route } from '@/server/http';
import { deleteProfilePhoto, getMyPhoto } from '@/server/profiles/photos';

export const DELETE = route('deleteProfilePhoto', deleteProfilePhoto);
export const GET = route('getMyPhoto', getMyPhoto);
