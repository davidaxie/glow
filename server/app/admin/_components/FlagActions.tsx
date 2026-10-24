'use client';
// Owner: B7. Ban someone B8 flagged for repeated screenshots of the deck.
import { useRouter } from 'next/navigation';
import { useState, useTransition } from 'react';
import { banFlaggedAction } from '../actions';

export function FlagActions({ viewerCode }: { viewerCode: string }) {
  const router = useRouter();
  const [message, setMessage] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  function ban() {
    if (!window.confirm(`Ban ${viewerCode}? They leave every room and match, and can’t sign in.`)) {
      return;
    }
    setMessage(null);
    startTransition(async () => {
      const result = await banFlaggedAction(viewerCode);
      if (!result.ok) setMessage(result.message);
      router.refresh();
    });
  }

  return (
    <>
      <button
        type="button"
        className="ga-button ga-button--danger ga-button--small"
        onClick={ban}
        disabled={pending}
      >
        Ban
      </button>
      {message ? (
        <p className="ga-message ga-message--error" role="alert">
          {message}
        </p>
      ) : null}
    </>
  );
}
