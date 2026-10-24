import type { NextConfig } from 'next';
import { parseEnv, formatEnvProblems } from './src/env.ts';

// Stop `next dev`, `next build` and `next start` right away if the environment is
// wrong, with a message that names each variable. Values are never printed.
const result = parseEnv(process.env);
if (!result.ok) {
  console.error(`\n${formatEnvProblems(result.profile, result.problems)}\n`);
  process.exit(1);
}

const securityHeaders = [
  { key: 'X-Content-Type-Options', value: 'nosniff' },
  { key: 'Referrer-Policy', value: 'no-referrer' },
  { key: 'X-Frame-Options', value: 'DENY' },
  // Admin web (B7) uses this page's own location to set a room's center.
  { key: 'Permissions-Policy', value: 'camera=(), microphone=(), geolocation=(self)' },
  { key: 'Strict-Transport-Security', value: 'max-age=63072000; includeSubDomains' },
];

const nextConfig: NextConfig = {
  poweredByHeader: false,
  reactStrictMode: true,
  // Keep the server's TypeScript honest on every build.
  typescript: { ignoreBuildErrors: false },
  async headers() {
    return [
      { source: '/:path*', headers: securityHeaders },
      {
        // Nothing from the API is ever cached by a browser, proxy or CDN.
        source: '/api/:path*',
        headers: [{ key: 'Cache-Control', value: 'no-store, max-age=0' }],
      },
    ];
  },
};

export default nextConfig;
