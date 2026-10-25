// Owner: X1. Blind mode. Logic in server/src/server/blind.
import { route } from '@/server/http';
import { blindSwipe } from '@/server/blind/handlers';

export const POST = route('blindSwipe', blindSwipe);
