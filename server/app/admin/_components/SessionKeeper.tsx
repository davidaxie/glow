'use client';
// Owner: B7. Keeps an open admin page (or the display screen) signed in by refreshing the
// session every few minutes and whenever the tab comes back. When the session is over, the
// page reloads into the 404 page.
import { useRouter } from 'next/navigation';
import { useEffect } from 'react';
import { refreshSessionAction } from '../actions';

const EVERY_MS = 10 * 60 * 1000;

export function SessionKeeper() {
  const router = useRouter();
  useEffect(() => {
    let stopped = false;
    const refresh = () => {
      void refreshSessionAction().then((ok) => {
        if (!ok && !stopped) router.refresh();
      });
    };
    const timer = window.setInterval(refresh, EVERY_MS);
    const onVisible = () => {
      if (document.visibilityState === 'visible') refresh();
    };
    document.addEventListener('visibilitychange', onVisible);
    return () => {
      stopped = true;
      window.clearInterval(timer);
      document.removeEventListener('visibilitychange', onVisible);
    };
  }, [router]);
  return null;
}
