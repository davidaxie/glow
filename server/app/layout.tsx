import type { Metadata, Viewport } from 'next';
import type { ReactNode } from 'react';

export const metadata: Metadata = {
  title: 'Glow',
  description: 'Find out, privately, that you noticed each other.',
  robots: { index: false, follow: false },
};

export const viewport: Viewport = {
  themeColor: '#0B0B10',
  colorScheme: 'dark',
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body
        style={{
          margin: 0,
          minHeight: '100vh',
          background: '#0B0B10',
          color: '#F4F4F6',
          fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif',
        }}
      >
        {children}
      </body>
    </html>
  );
}
