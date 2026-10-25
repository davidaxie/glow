// Owner: X1. Blind mode. Logic in server/src/server/blind.
import { route } from '@/server/http';
import { blindListMessages, blindSendMessage } from '@/server/blind/handlers';

export const GET = route('blindListMessages', blindListMessages);
export const POST = route('blindSendMessage', blindSendMessage);
