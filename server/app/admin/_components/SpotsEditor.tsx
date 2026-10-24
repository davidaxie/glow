'use client';
// Owner: B7. A room's meeting spots. Renaming keeps each spot, so a glow already sending two
// people to "Main entrance" keeps its spot under the new name.
import { useRouter } from 'next/navigation';
import { useState, useTransition } from 'react';
import type { AdminMeetingSpot } from '@/contracts';
import { replaceSpotsAction } from '../actions';
import { MEETING_SPOTS_MAX, MEETING_SPOTS_MIN } from '@/contracts/constants';

export function SpotsEditor({ roomId, spots }: { roomId: string; spots: AdminMeetingSpot[] }) {
  const router = useRouter();
  const [names, setNames] = useState(spots.map((s) => s.name));
  const [message, setMessage] = useState<{ text: string; error: boolean } | null>(null);
  const [pending, startTransition] = useTransition();

  function save(event: React.FormEvent) {
    event.preventDefault();
    setMessage(null);
    const clean = names.map((n) => n.trim()).filter(Boolean);
    if (clean.length < MEETING_SPOTS_MIN || clean.length > MEETING_SPOTS_MAX) {
      setMessage({ text: `Keep ${MEETING_SPOTS_MIN} to ${MEETING_SPOTS_MAX} spots.`, error: true });
      return;
    }
    startTransition(async () => {
      const result = await replaceSpotsAction(roomId, clean);
      setMessage(
        result.ok ? { text: 'Saved.', error: false } : { text: result.message, error: true },
      );
      if (result.ok) router.refresh();
    });
  }

  return (
    <form onSubmit={save} className="ga-card ga-stack" aria-labelledby="spots-title">
      <h2 id="spots-title">Meeting spots</h2>
      {names.map((name, i) => (
        <div key={i} className="ga-row">
          <label className="ga-visually-hidden" htmlFor={`edit-spot-${i}`}>
            Meeting spot {i + 1}
          </label>
          <input
            id={`edit-spot-${i}`}
            className="ga-input"
            style={{ flex: 1 }}
            value={name}
            maxLength={60}
            onChange={(e) => setNames(names.map((n, j) => (j === i ? e.target.value : n)))}
          />
          {names.length > MEETING_SPOTS_MIN ? (
            <button
              type="button"
              className="ga-button ga-button--secondary ga-button--small"
              onClick={() => setNames(names.filter((_, j) => j !== i))}
              aria-label={`Remove meeting spot ${i + 1}`}
            >
              Remove
            </button>
          ) : null}
        </div>
      ))}
      <div className="ga-row">
        {names.length < MEETING_SPOTS_MAX ? (
          <button
            type="button"
            className="ga-button ga-button--secondary ga-button--small"
            onClick={() => setNames([...names, ''])}
          >
            Add a spot
          </button>
        ) : null}
        <button className="ga-button ga-button--small" disabled={pending}>
          {pending ? 'Saving…' : 'Save spots'}
        </button>
      </div>
      {message ? (
        <p
          className={`ga-message ${message.error ? 'ga-message--error' : 'ga-message--ok'}`}
          role={message.error ? 'alert' : 'status'}
        >
          {message.text}
        </p>
      ) : null}
    </form>
  );
}
