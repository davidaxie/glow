'use client';
// Owner: B7. Shows the room's current QR code and swaps it the moment its window ends, timed
// by the server's clock. The previous code keeps working for one more window, so a phone that
// scanned just before the swap still gets in.
import { useEffect, useRef, useState } from 'react';
import { QR_ROTATION_SECONDS } from '@/contracts/constants';
import { displayFrameAction, type DisplayFrame } from '../../admin/actions';

const IDLE_POLL_MS = 15_000;
const RETRY_MS = 5_000;

type WakeLock = { release: () => Promise<void> };

/** How long until this frame's code changes, by the server's clock, plus a little slack. */
function untilNext(frame: DisplayFrame): number {
  if (!frame.windowEndsAt) return IDLE_POLL_MS;
  return Math.max(250, Date.parse(frame.windowEndsAt) - Date.parse(frame.serverNow) + 300);
}

export function DisplayScreen({ roomId, initial }: { roomId: string; initial: DisplayFrame }) {
  const [frame, setFrame] = useState(initial);
  const [offline, setOffline] = useState(false);

  useEffect(() => {
    let stopped = false;
    let timer: number | undefined;
    const wait = (ms: number) =>
      new Promise<void>((resolve) => {
        timer = window.setTimeout(resolve, ms);
      });

    const run = async () => {
      let delay = untilNext(initial);
      while (!stopped) {
        await wait(delay);
        if (stopped) return;
        try {
          const result = await displayFrameAction(roomId);
          if (stopped) return;
          if (result.ok) {
            setFrame(result.value);
            setOffline(false);
            delay = untilNext(result.value);
          } else {
            setOffline(true);
            delay = RETRY_MS;
          }
        } catch {
          // Signed out, or the network dropped. Stop showing the old code and keep trying.
          if (stopped) return;
          setOffline(true);
          delay = RETRY_MS;
        }
      }
    };
    void run();
    return () => {
      stopped = true;
      window.clearTimeout(timer);
    };
  }, [roomId, initial]);

  // Keep the screen awake while this page is showing.
  useEffect(() => {
    let lock: WakeLock | null = null;
    const nav = navigator as Navigator & {
      wakeLock?: { request: (type: 'screen') => Promise<WakeLock> };
    };
    const acquire = () => {
      if (document.visibilityState !== 'visible' || !nav.wakeLock) return;
      nav.wakeLock.request('screen').then(
        (l) => {
          lock = l;
        },
        () => undefined,
      );
    };
    acquire();
    document.addEventListener('visibilitychange', acquire);
    return () => {
      document.removeEventListener('visibilitychange', acquire);
      void lock?.release();
    };
  }, []);

  const qr = offline ? null : frame.qr;

  return (
    <main className="ga-display">
      <div className="ga-display__inner">
        <h1 className="ga-display__name">{frame.name}</h1>
        {qr ? (
          <>
            <div className="ga-display__qr">
              <svg
                viewBox={`0 0 ${qr.viewBox} ${qr.viewBox}`}
                role="img"
                aria-label={`QR code to join ${frame.name} in Glow`}
                shapeRendering="crispEdges"
              >
                <rect width={qr.viewBox} height={qr.viewBox} fill="#fff" />
                <path d={qr.path} fill="#0B0B10" />
              </svg>
            </div>
            <Countdown frame={frame} />
            <p className="ga-display__hint">Scan with your iPhone camera to join</p>
            <p className="ga-display__code">
              Or open Glow and enter <span className="ga-code">{frame.code}</span>
            </p>
          </>
        ) : (
          <p className="ga-display__hint">{message(frame, offline)}</p>
        )}
      </div>
      <div className="ga-display__tools">
        <button
          type="button"
          className="ga-button ga-button--secondary ga-button--small"
          onClick={() => void document.documentElement.requestFullscreen?.()}
        >
          Full screen
        </button>
      </div>
    </main>
  );
}

function message(frame: DisplayFrame, offline: boolean): string {
  if (offline) return 'Reconnecting… If this stays, sign in again on this screen.';
  if (frame.state === 'paused') return 'Glow is paused here for a moment.';
  if (frame.state === 'not_started') {
    const at = new Date(frame.startsAt).toLocaleTimeString([], {
      hour: 'numeric',
      minute: '2-digit',
    });
    return `Glow opens here at ${at}.`;
  }
  return 'This room has ended. Thanks for coming.';
}

/** A bar that empties as the current code's window runs out. */
function Countdown({ frame }: { frame: DisplayFrame }) {
  const bar = useRef<HTMLSpanElement>(null);
  useEffect(() => {
    const el = bar.current;
    if (!el || !frame.windowEndsAt) return;
    const total = QR_ROTATION_SECONDS * 1000;
    // The frame arrived just now, so the server's "now" is close enough to ours.
    const left = Math.max(0, Date.parse(frame.windowEndsAt) - Date.parse(frame.serverNow));
    el.style.transition = 'none';
    el.style.transform = `scaleX(${Math.min(1, left / total)})`;
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    const id = window.requestAnimationFrame(() => {
      el.style.transition = `transform ${left}ms linear`;
      el.style.transform = 'scaleX(0)';
    });
    return () => window.cancelAnimationFrame(id);
  }, [frame]);
  return (
    <div className="ga-display__bar" aria-hidden="true">
      <span ref={bar} />
    </div>
  );
}
