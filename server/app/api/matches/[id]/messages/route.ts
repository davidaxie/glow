// Owner: C4. The handlers live in `server/src/server/chat`.
import { listMessagesRoute, sendMessageRoute } from '@/server/chat/messages';
import { route } from '@/server/http';

export const GET = route('listMessages', listMessagesRoute);
export const POST = route('sendMessage', sendMessageRoute);
