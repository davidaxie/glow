// Owner: B7. Admins only: everyone else gets 404 (P11). Logic in server/src/server/admin.
import { route } from '@/server/http';
import { adminOnly, adminResolveReportHandler } from '@/server/admin/handlers';

export const POST = route('adminResolveReport', adminResolveReportHandler, {
  authorize: adminOnly,
});
