// Owner: C2. The handler lives in `server/src/server/choice`.
import { setChoiceFor } from '@/server/choice';
import { route } from '@/server/http';

export const POST = route('setChoice', setChoiceFor);
