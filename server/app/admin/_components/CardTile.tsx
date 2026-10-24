'use client';
// Owner: B7. One card, for moderation. The photo loads only when asked, watermarked with the
// admin's own code, and is never cached.
import { useRouter } from 'next/navigation';
import { useState, useTransition } from 'react';
import type { AdminCard } from '@/contracts';
import { cardPhotoAction, removeCardAction } from '../actions';
import { describeTags } from './format';

export function CardTile({ card, timeZone }: { card: AdminCard; timeZone: string }) {
  const router = useRouter();
  const [photo, setPhoto] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  function show() {
    setMessage(null);
    startTransition(async () => {
      const result = await cardPhotoAction(card.id);
      if (result.ok) setPhoto(result.value);
      else setMessage(result.message);
    });
  }

  function remove(scope: 'card' | 'person') {
    const question =
      scope === 'card'
        ? 'Remove this card? Its photo is deleted. They can check in again with a new one.'
        : 'Remove this person from the room? Their card is deleted and their check-in ends.';
    if (!window.confirm(question)) return;
    setMessage(null);
    startTransition(async () => {
      const result = await removeCardAction(card.id, scope);
      if (!result.ok) setMessage(result.message);
      router.refresh();
    });
  }

  const joined = new Intl.DateTimeFormat('en-US', {
    timeZone,
    hour: 'numeric',
    minute: '2-digit',
  }).format(new Date(card.joinedAt));

  return (
    <li className="ga-card ga-stack">
      <div className="ga-row ga-row--between">
        <span className="ga-small ga-muted">
          Joined {joined} · watermark <span className="ga-code">{card.viewerCode}</span>
        </span>
        {!card.visible ? <span className="ga-chip ga-chip--ended">Removed</span> : null}
      </div>
      <div className="ga-tags">
        {describeTags(card.tags).map((tag) => (
          <span key={tag} className="ga-chip">
            {tag}
          </span>
        ))}
      </div>
      {photo ? (
        // A data URL from a server action: nothing to cache, nothing next/image could add.
        // eslint-disable-next-line @next/next/no-img-element
        <img className="ga-photo" src={photo} alt="Outfit photo on this card, faces blurred" />
      ) : card.visible ? (
        <button
          type="button"
          className="ga-button ga-button--secondary ga-button--small"
          onClick={show}
          disabled={pending}
        >
          Show photo
        </button>
      ) : null}
      {card.visible ? (
        <div className="ga-row">
          <button
            type="button"
            className="ga-button ga-button--danger ga-button--small"
            onClick={() => remove('card')}
            disabled={pending}
          >
            Remove card
          </button>
          <button
            type="button"
            className="ga-button ga-button--danger ga-button--small"
            onClick={() => remove('person')}
            disabled={pending}
          >
            Remove from room
          </button>
        </div>
      ) : null}
      {message ? (
        <p className="ga-message ga-message--error" role="alert">
          {message}
        </p>
      ) : null}
    </li>
  );
}
