// Owner: X1. Admins only: everyone else gets 404 (P11). Logic in server/src/server/blind.
import { route } from '@/server/http';
import { adminOnly } from '@/server/admin/handlers';
import { blindAdminDrop } from '@/server/blind/handlers';

export const POST = route('blindAdminDrop', blindAdminDrop, { authorize: adminOnly });
