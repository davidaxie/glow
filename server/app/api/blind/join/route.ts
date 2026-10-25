// Owner: X1. Blind mode. Logic in server/src/server/blind.
import { route } from '@/server/http';
import { blindJoin, blindLeave } from '@/server/blind/handlers';

export const POST = route('blindJoin', blindJoin);
export const DELETE = route('blindLeave', blindLeave);
