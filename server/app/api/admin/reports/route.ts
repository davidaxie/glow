// Owner: B7. Admins only: everyone else gets 404 (P11). Logic in server/src/server/admin.
import { route } from '@/server/http';
import { adminListReportsHandler, adminOnly } from '@/server/admin/handlers';

export const GET = route('adminListReports', adminListReportsHandler, { authorize: adminOnly });
