'use client';
// Owner: B7. Dismiss a report, remove the reported person's card, or ban them.
import { useRouter } from 'next/navigation';
import { useState, useTransition } from 'react';
import { resolveReportAction } from '../actions';

type Action = 'dismiss' | 'remove_card' | 'ban';

const CONFIRM: Record<Action, string | null> = {
  dismiss: null,
  remove_card: "Remove the reported person's card? Its photo is deleted.",
  ban: 'Ban this person? They leave every room and every match, and can no longer sign in.',
};

export function ReportActions({ reportId }: { reportId: string }) {
  const router = useRouter();
  const [message, setMessage] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  function run(action: Action) {
    const question = CONFIRM[action];
    if (question && !window.confirm(question)) return;
    setMessage(null);
    startTransition(async () => {
      const result = await resolveReportAction(reportId, action);
      if (!result.ok) setMessage(result.message);
      router.refresh();
    });
  }

  return (
    <div className="ga-stack">
      <div className="ga-row">
        <button
          type="button"
          className="ga-button ga-button--secondary ga-button--small"
          onClick={() => run('dismiss')}
          disabled={pending}
        >
          Dismiss
        </button>
        <button
          type="button"
          className="ga-button ga-button--danger ga-button--small"
          onClick={() => run('remove_card')}
          disabled={pending}
        >
          Remove card
        </button>
        <button
          type="button"
          className="ga-button ga-button--danger ga-button--small"
          onClick={() => run('ban')}
          disabled={pending}
        >
          Ban
        </button>
      </div>
      {message ? (
        <p className="ga-message ga-message--error" role="alert">
          {message}
        </p>
      ) : null}
    </div>
  );
}
