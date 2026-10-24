/**
 * Who counts as an admin: a signed-in person with a row in `admins` who isn't banned.
 * Everyone else gets 404, never 403, so the admin area's contents never show (P11).
 */
import { notFound } from '@/server/http';
import { deps } from './context';

export async function isAdmin(userId: string): Promise<boolean> {
  return deps().repo.isAdmin(userId);
}

/** Throws the route helper's 404 unless `userId` is an admin. */
export async function requireAdmin(userId: string): Promise<void> {
  if (!(await isAdmin(userId))) throw notFound();
}
