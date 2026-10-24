// Owner: B7. Make a room.
import type { Metadata } from 'next';
import Link from 'next/link';
import { adminPage } from '@/server/admin/web';
import { RoomForm } from '../../../_components/RoomForm';

export const metadata: Metadata = { title: 'New room' };

export default async function NewRoomPage() {
  await adminPage();
  return (
    <div className="ga-stack">
      <p className="ga-small" style={{ margin: 0 }}>
        <Link href="/admin">← Rooms</Link>
      </p>
      <h1 style={{ marginTop: 0 }}>New room</h1>
      <RoomForm />
    </div>
  );
}
