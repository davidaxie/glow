// Owner: B7. The admin web's shell: styles only. Sign-in is checked by (console)/layout.tsx.
import type { Metadata, Viewport } from 'next';
import type { ReactNode } from 'react';
import './admin.css';

export const metadata: Metadata = {
  title: { default: 'Glow admin', template: '%s · Glow admin' },
  robots: { index: false, follow: false, nocache: true },
  // Map tiles come from OpenStreetMap, whose tile policy asks browsers to send a referrer.
  // The origin is all it gets: never a path, so never a room ID.
  referrer: 'strict-origin',
};

export const viewport: Viewport = {
  width: 'device-width',
  initialScale: 1,
  themeColor: '#0B0B10',
  colorScheme: 'dark',
};

// Every admin page reads the session cookie, so nothing here is ever prerendered or cached.
export const dynamic = 'force-dynamic';

export default function AdminLayout({ children }: { children: ReactNode }) {
  return <div className="ga">{children}</div>;
}
