// Owner: B7. Make a room.
import Link from 'next/link';
import { adminPage, adminTitle } from '@/server/admin/web';
import { RoomForm } from '../../../_components/RoomForm';

export const generateMetadata = adminTitle('New room');

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
