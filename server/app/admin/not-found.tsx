// Owner: B7. What anyone who isn't a signed-in admin sees anywhere under /admin, with a 404
// status: the same page as an address that doesn't exist. A browser that has signed in as an
// admin before also gets a sign-in link.
import Link from 'next/link';
import { hasAdminHint } from '@/server/admin/session';
import { SessionRecovery } from './_components/SessionRecovery';

export default async function AdminNotFound() {
  const hint = await hasAdminHint();
  return (
    <main className="ga-page ga-narrow">
      <h1>Not found</h1>
      <p className="ga-muted">There’s nothing here.</p>
      {hint ? (
        <>
          <p className="ga-small ga-muted">
            If you were signed in, your session may have ended.{' '}
            <Link href="/admin/sign-in">Sign in again</Link>.
          </p>
          <SessionRecovery />
        </>
      ) : null}
    </main>
  );
}
