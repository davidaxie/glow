'use client';
// Owner: B7. One held profile photo. It loads only when asked, watermarked with the admin's
// own code. Approve lets it count; Reject deletes it; Ban deletes it and bans the owner.
import { useRouter } from 'next/navigation';
import { useState, useTransition } from 'react';
import { photoImageAction, reviewPhotoAction } from '../actions';

type Photo = { id: string; position: number; createdAt: string; viewerCode: string };
type Decision = 'approve' | 'reject' | 'ban';

const CONFIRM: Record<Decision, string | null> = {
  approve: 'Approve this photo? Matches will see it.',
  reject: 'Reject this photo? It’s deleted, and they can add another.',
  ban: 'Ban this person? Their photo is deleted, they leave every room and match, and can’t sign in.',
};

export function PhotoTile({ photo, timeZone }: { photo: Photo; timeZone: string }) {
  const router = useRouter();
  const [image, setImage] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  function show() {
    setMessage(null);
    startTransition(async () => {
      const result = await photoImageAction(photo.id);
      if (result.ok) setImage(result.value);
      else setMessage(result.message);
    });
  }

  function decide(decision: Decision) {
    const question = CONFIRM[decision];
    if (question && !window.confirm(question)) return;
    setMessage(null);
    startTransition(async () => {
      const result = await reviewPhotoAction(photo.id, decision);
      if (!result.ok) setMessage(result.message);
      router.refresh();
    });
  }

  const added = new Intl.DateTimeFormat('en-US', {
    timeZone,
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  }).format(new Date(photo.createdAt));

  return (
    <li className="ga-card ga-stack">
      <p className="ga-small ga-muted" style={{ margin: 0 }}>
        Added {added} · photo {photo.position + 1} · watermark{' '}
        <span className="ga-code">{photo.viewerCode}</span>
      </p>
      {image ? (
        // A data URL from a server action: nothing to cache, nothing next/image could add.
        // eslint-disable-next-line @next/next/no-img-element
        <img className="ga-photo" src={image} alt="Profile photo held for review" />
      ) : (
        <button
          type="button"
          className="ga-button ga-button--secondary ga-button--small"
          onClick={show}
          disabled={pending}
        >
          Show photo
        </button>
      )}
      <div className="ga-row">
        <button
          type="button"
          className="ga-button ga-button--small"
          onClick={() => decide('approve')}
          disabled={pending}
        >
          Approve
        </button>
        <button
          type="button"
          className="ga-button ga-button--danger ga-button--small"
          onClick={() => decide('reject')}
          disabled={pending}
        >
          Reject
        </button>
        <button
          type="button"
          className="ga-button ga-button--danger ga-button--small"
          onClick={() => decide('ban')}
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
    </li>
  );
}
