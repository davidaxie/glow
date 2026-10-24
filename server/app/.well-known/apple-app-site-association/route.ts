// Owner: B2. The file lives in `server/src/server/rooms/web.ts`.
import { route } from '@/server/http';
import { getAppSiteAssociation } from '@/server/rooms';

export const GET = route('getAppSiteAssociation', getAppSiteAssociation);
