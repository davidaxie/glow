'use client';
// Owner: B7. Running a room: pause, resume, end, demo mode, printed posters, the poster file
// and the display screen.
import { useRouter } from 'next/navigation';
import { useState, useTransition } from 'react';
import type { AdminRoom, AdminRoomUpdate } from '@/contracts';
import { posterAction, rotateStaticTokenAction, updateRoomAction } from '../actions';

export function RoomControls({ room }: { room: AdminRoom }) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const [message, setMessage] = useState<{ text: string; error: boolean } | null>(null);

  function update(change: AdminRoomUpdate, done: string) {
    setMessage(null);
    startTransition(async () => {
      const result = await updateRoomAction(room.id, change);
      setMessage(result.ok ? { text: done, error: false } : { text: result.message, error: true });
      router.refresh();
    });
  }

  function endRoom() {
    if (
      !window.confirm('End this room? Everyone checked in leaves now and their cards are deleted.')
    )
      return;
    update({ status: 'ended' }, 'The room has ended.');
  }

  function rotate() {
    if (!window.confirm('Make a new poster code? Posters you already printed stop working.'))
      return;
    setMessage(null);
    startTransition(async () => {
      const result = await rotateStaticTokenAction(room.id);
      setMessage(
        result.ok
          ? { text: 'New poster code made. Download and print the poster again.', error: false }
          : { text: result.message, error: true },
      );
      router.refresh();
    });
  }

  function downloadPoster() {
    setMessage(null);
    // Open the tab now, while this still counts as a tap, so Safari doesn't block it.
    const tab = window.open('', '_blank');
    startTransition(async () => {
      const result = await posterAction(room.id);
      if (!result.ok) {
        tab?.close();
        setMessage({ text: result.message, error: true });
        return;
      }
      const bytes = Uint8Array.from(atob(result.value.base64), (c) => c.charCodeAt(0));
      const url = URL.createObjectURL(new Blob([bytes], { type: 'application/pdf' }));
      if (tab) tab.location.href = url;
      else {
        const a = document.createElement('a');
        a.href = url;
        a.download = result.value.filename;
        a.click();
      }
      window.setTimeout(() => URL.revokeObjectURL(url), 60_000);
    });
  }

  const ended = room.status === 'ended';

  return (
    <div className="ga-stack">
      <section className="ga-card ga-stack" aria-labelledby="screens">
        <h2 id="screens">QR codes</h2>
        <div className="ga-row">
          <a className="ga-button" href={`/display/${room.slug}`} target="_blank" rel="noopener">
            Open display screen
          </a>
          <button
            type="button"
            className="ga-button ga-button--secondary"
            onClick={downloadPoster}
            disabled={pending}
          >
            Poster (PDF)
          </button>
        </div>
        <p className="ga-hint" style={{ margin: 0 }}>
          The display screen’s code changes every 30 seconds. Open it on the laptop by the stage and
          sign in there.
        </p>
        {!room.allowStaticQr ? (
          <p className="ga-message" role="note">
            Printed posters are off for this room, so a poster’s code won’t let anyone in. Turn on
            Printed posters below first.
          </p>
        ) : null}
        <label className="ga-switch">
          <input
            type="checkbox"
            checked={room.allowStaticQr}
            disabled={pending || ended}
            onChange={(e) =>
              update(
                { allowStaticQr: e.target.checked },
                e.target.checked ? 'Printed posters work now.' : 'Printed posters stopped working.',
              )
            }
          />
          <span>
            <strong>Printed posters</strong>
            <br />
            <span className="ga-hint">
              A poster’s code never changes, so a photo of it works anywhere. People still have to
              be inside the room to join.
            </span>
          </span>
        </label>
        <button
          type="button"
          className="ga-button ga-button--secondary ga-button--small"
          onClick={rotate}
          disabled={pending}
        >
          Make a new poster code
        </button>
      </section>

      <section className="ga-card ga-stack" aria-labelledby="running">
        <h2 id="running">Running the room</h2>
        <div className="ga-row">
          {room.status === 'live' ? (
            <button
              type="button"
              className="ga-button ga-button--secondary"
              onClick={() =>
                update({ status: 'paused' }, 'Paused. Nobody sees any cards until you resume.')
              }
              disabled={pending}
            >
              Pause room
            </button>
          ) : null}
          {room.status === 'paused' ? (
            <button
              type="button"
              className="ga-button"
              onClick={() => update({ status: 'live' }, 'The room is live again.')}
              disabled={pending}
            >
              Resume room
            </button>
          ) : null}
          {!ended ? (
            <button
              type="button"
              className="ga-button ga-button--danger"
              onClick={endRoom}
              disabled={pending}
            >
              End room
            </button>
          ) : (
            <button
              type="button"
              className="ga-button ga-button--secondary"
              onClick={() => update({ status: 'live' }, 'The room is open again.')}
              disabled={pending}
            >
              Reopen room
            </button>
          )}
        </div>
        <label className="ga-switch">
          <input
            type="checkbox"
            checked={room.demoMode}
            disabled={pending || ended}
            onChange={(e) =>
              update(
                { demoMode: e.target.checked },
                e.target.checked ? 'Demo mode is on.' : 'Demo mode is off.',
              )
            }
          />
          <span>
            <strong>Demo mode</strong>
            <br />
            <span className="ga-hint">
              Admins skip the location check here, so stage phones work wherever the stage is. Every
              skip is logged. Everyone else is still checked.
            </span>
          </span>
        </label>
      </section>

      {message ? (
        <p
          className={`ga-message ${message.error ? 'ga-message--error' : 'ga-message--ok'}`}
          role={message.error ? 'alert' : 'status'}
        >
          {message.text}
        </p>
      ) : null}
    </div>
  );
}
