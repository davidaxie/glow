// Shared file. Each owner edits only their own export line:
//   GET is B1, with its handler in `server/src/server/profiles`.
//   DELETE is B8, with its handler in `server/src/server/safety`.
import { notImplemented, route } from '@/server/http';

export const GET = route('getMe', notImplemented);
export const DELETE = route('deleteAccount', notImplemented);
