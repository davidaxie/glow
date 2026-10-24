'use client';
// Owner: B7. Email, then the 6-digit code.
import { useActionState } from 'react';
import { sendCodeAction, testSignInAction, verifyCodeAction, type SignInState } from '../actions';

const START: SignInState = { step: 'email' };

export function SignInForm({ testSignIn }: { testSignIn: boolean }) {
  const [sent, send, sending] = useActionState(sendCodeAction, START);
  const [checked, verify, verifying] = useActionState(verifyCodeAction, START);
  const [tested, test, testing] = useActionState(testSignInAction, START);

  // The code step shows once a code was sent, and stays while codes are being checked.
  const codeState = checked.step === 'code' ? checked : sent.step === 'code' ? sent : null;
  const emailMessage = sent.step === 'email' ? sent.message : undefined;

  if (codeState) {
    return (
      <form action={verify} className="ga-stack" noValidate>
        <input type="hidden" name="email" value={codeState.email} />
        <p className="ga-message" role="status">
          If <strong>{codeState.email}</strong> can sign in, a code is on its way.
        </p>
        <div className="ga-field">
          <label className="ga-label" htmlFor="code">
            6-digit code
          </label>
          <input
            id="code"
            name="code"
            className="ga-input ga-input--code"
            inputMode="numeric"
            autoComplete="one-time-code"
            pattern="[0-9]{6}"
            maxLength={6}
            required
            autoFocus
            aria-invalid={checked.message ? true : undefined}
            aria-describedby={checked.message ? 'code-error' : undefined}
          />
        </div>
        {checked.step === 'code' && checked.message ? (
          <p id="code-error" className="ga-message ga-message--error" role="alert">
            {checked.message}
          </p>
        ) : null}
        <button className="ga-button ga-button--block" disabled={verifying}>
          {verifying ? 'Checking…' : 'Sign in'}
        </button>
        <button
          type="submit"
          formAction={send}
          formNoValidate
          className="ga-button ga-button--secondary ga-button--block"
          disabled={sending}
        >
          Send a new code
        </button>
      </form>
    );
  }

  return (
    <div className="ga-stack">
      <form action={send} className="ga-stack" noValidate>
        <div className="ga-field">
          <label className="ga-label" htmlFor="email">
            Email
          </label>
          <input
            id="email"
            name="email"
            type="email"
            className="ga-input"
            autoComplete="email"
            autoCapitalize="none"
            spellCheck={false}
            required
            autoFocus
            aria-invalid={emailMessage ? true : undefined}
            aria-describedby={emailMessage ? 'email-error' : undefined}
          />
        </div>
        {emailMessage ? (
          <p id="email-error" className="ga-message ga-message--error" role="alert">
            {emailMessage}
          </p>
        ) : null}
        <button className="ga-button ga-button--block" disabled={sending}>
          {sending ? 'Sending…' : 'Send code'}
        </button>
      </form>

      {testSignIn ? (
        <form action={test} className="ga-card ga-stack">
          <h2>Test sign-in</h2>
          <p className="ga-small ga-muted">
            Local only (ALLOW_TEST_LOGIN). Signs in an admin test person without an email.
          </p>
          <input type="hidden" name="email" value="admin@glow.test" />
          {tested.step === 'email' && tested.message ? (
            <p className="ga-message ga-message--error" role="alert">
              {tested.message}
            </p>
          ) : null}
          <button className="ga-button ga-button--secondary" disabled={testing}>
            Sign in as admin@glow.test
          </button>
        </form>
      ) : null}
    </div>
  );
}
