// Shared file. Each owner edits only their own export line:
//   GET is B1, with its handler in `server/src/server/profiles`.
//   DELETE is B8, with its handler in `server/src/server/safety`.
import { route } from '@/server/http';
import { getMe } from '@/server/profiles/me';
import { deleteAccount } from '@/server/safety/routes';

export const GET = route('getMe', getMe);
export const DELETE = route('deleteAccount', deleteAccount);
