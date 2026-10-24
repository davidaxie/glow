'use client';
// Owner: B7. Re-renders the page from the server every few seconds while it's on screen.
import { useRouter } from 'next/navigation';
import { useEffect } from 'react';

export function AutoRefresh({ seconds }: { seconds: number }) {
  const router = useRouter();
  useEffect(() => {
    const timer = window.setInterval(() => {
      if (document.visibilityState === 'visible') router.refresh();
    }, seconds * 1000);
    return () => window.clearInterval(timer);
  }, [router, seconds]);
  return (
    <p className="ga-hint" style={{ margin: 0 }}>
      Updates every {seconds} seconds while this page is open.
    </p>
  );
}
