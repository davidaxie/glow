// Owner: B7. The only admin page anyone can open: an email and code form, nothing else. It says
// the same thing whether or not an address has an account or is an admin.
import type { Metadata } from 'next';
import { redirect } from 'next/navigation';
import { currentAdmin, testSignInAllowed } from '@/server/admin/session';
import { SignInForm } from './SignInForm';

export const metadata: Metadata = { title: 'Sign in' };

export default async function SignInPage() {
  if (await currentAdmin()) redirect('/admin');
  return (
    <main className="ga-page ga-narrow">
      <h1>Glow admin</h1>
      <p className="ga-muted">
        Sign in with the email you use for Glow. We’ll send a 6-digit code.
      </p>
      <SignInForm testSignIn={testSignInAllowed()} />
    </main>
  );
}
