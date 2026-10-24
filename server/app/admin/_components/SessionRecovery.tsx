'use client';
// Owner: B7. On the admin 404 page: if this browser's admin access token just expired but the
// session is still good, refresh it and reload once. For anyone else it does nothing.
import { useRouter } from 'next/navigation';
import { useEffect, useRef } from 'react';
import { refreshSessionAction } from '../actions';

export function SessionRecovery() {
  const router = useRouter();
  const tried = useRef(false);
  useEffect(() => {
    if (tried.current) return;
    tried.current = true;
    const key = 'glow-admin-recovered';
    // At most once a minute, so a page that really doesn't exist can't loop.
    const last = Number(sessionStorage.getItem(key) ?? 0);
    if (Date.now() - last < 60_000) return;
    void refreshSessionAction().then((ok) => {
      if (ok) {
        sessionStorage.setItem(key, String(Date.now()));
        router.refresh();
      }
    });
  }, [router]);
  return null;
}
