'use client';
// Owner: B7.
import Link from 'next/link';
import { usePathname } from 'next/navigation';

const LINKS = [
  {
    href: '/admin',
    label: 'Rooms',
    match: (p: string) => p === '/admin' || p.startsWith('/admin/rooms'),
  },
  {
    href: '/admin/reports',
    label: 'Reports',
    match: (p: string) => p.startsWith('/admin/reports'),
  },
  { href: '/admin/photos', label: 'Photos', match: (p: string) => p.startsWith('/admin/photos') },
] as const;

export function NavLinks() {
  const path = usePathname();
  return (
    <>
      {LINKS.map((link) => (
        <Link key={link.href} href={link.href} aria-current={link.match(path) ? 'page' : undefined}>
          {link.label}
        </Link>
      ))}
    </>
  );
}
