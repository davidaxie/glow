// Owner: X1. Blind mode. Logic in server/src/server/blind.
import { route } from '@/server/http';
import { blindGetCardImage } from '@/server/blind/handlers';

export const GET = route('blindGetCardImage', blindGetCardImage);
