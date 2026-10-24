// Owner: B3. The handler lives in `server/src/server/images/card-image.ts`.
import { route } from '@/server/http';
import { getCardImage } from '@/server/images';

export const GET = route('getCardImage', getCardImage);
