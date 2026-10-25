// Owner: X1. Blind mode. Logic in server/src/server/blind.
import { route } from '@/server/http';
import { blindGuess } from '@/server/blind/handlers';

export const POST = route('blindGuess', blindGuess);
