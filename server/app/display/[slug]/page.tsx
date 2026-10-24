// Owner: B7. The display screen: one big QR code whose token changes every QR_ROTATION seconds,
// for a laptop or TV in the room. Admins only, like everything else that hands out a working
// token: a screen token copied out of the room would be no different from a poster.
import type { Metadata, Viewport } from 'next';
import { notFound } from 'next/navigation';
import { zRoomSlug } from '@/contracts';
import { getRoomBySlug } from '@/server/admin/rooms';
import { adminPage, orNotFound } from '@/server/admin/web';
import { displayFrameAction } from '../../admin/actions';
import { SessionKeeper } from '../../admin/_components/SessionKeeper';
import { DisplayScreen } from './DisplayScreen';
import '../../admin/admin.css';

export const metadata: Metadata = {
  title: 'Glow',
  robots: { index: false, follow: false, nocache: true },
};

export const viewport: Viewport = { themeColor: '#0B0B10', colorScheme: 'dark' };

export const dynamic = 'force-dynamic';

export default async function DisplayPage({ params }: { params: Promise<{ slug: string }> }) {
  await adminPage();
  const slug = zRoomSlug.safeParse((await params).slug);
  if (!slug.success) notFound();
  const room = await orNotFound(() => getRoomBySlug(slug.data));
  const first = await displayFrameAction(room.id);
  if (!first.ok) notFound();
  return (
    <div className="ga">
      <SessionKeeper />
      <DisplayScreen roomId={room.id} initial={first.value} />
    </div>
  );
}
