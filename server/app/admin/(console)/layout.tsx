// Owner: B7. Every admin page except sign-in lives under this layout, which answers 404 to
// anyone who isn't a signed-in admin before anything else renders.
import Link from 'next/link';
import type { ReactNode } from 'react';
import { adminPage } from '@/server/admin/web';
import { signOutAction } from '../actions';
import { SessionKeeper } from '../_components/SessionKeeper';
import { NavLinks } from '../_components/NavLinks';

export default async function ConsoleLayout({ children }: { children: ReactNode }) {
  await adminPage();
  return (
    <>
      <nav className="ga-nav" aria-label="Admin">
        <Link href="/admin" className="ga-nav__brand">
          Glow admin
        </Link>
        <NavLinks />
        <form action={signOutAction}>
          <button className="ga-button ga-button--secondary ga-button--small">Sign out</button>
        </form>
      </nav>
      <SessionKeeper />
      <main className="ga-page">{children}</main>
    </>
  );
}
