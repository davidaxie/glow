// Owner: B7. One room: QR codes, controls, meeting spots and details.
import type { Metadata } from 'next';
import Link from 'next/link';
import { demoSkipsToday } from '@/server/admin/metrics';
import { getRoom } from '@/server/admin/rooms';
import { adminPage, idOrNotFound, orNotFound } from '@/server/admin/web';
import { formatTime, statusLabel } from '../../../_components/format';
import { RoomControls } from '../../../_components/RoomControls';
import { RoomForm } from '../../../_components/RoomForm';
import { SpotsEditor } from '../../../_components/SpotsEditor';

export const metadata: Metadata = { title: 'Room' };

export default async function RoomPage({ params }: { params: Promise<{ id: string }> }) {
  await adminPage();
  const id = idOrNotFound((await params).id);
  const room = await orNotFound(() => getRoom(id));
  const skips = room.demoMode ? await demoSkipsToday(id) : 0;

  return (
    <div className="ga-stack">
      <p className="ga-small" style={{ margin: 0 }}>
        <Link href="/admin">← Rooms</Link>
      </p>
      <div>
        <div className="ga-row ga-row--between">
          <h1 style={{ marginTop: 0 }}>{room.name}</h1>
          <span className={`ga-chip ga-chip--${room.status}`}>{statusLabel(room.status)}</span>
        </div>
        <p className="ga-muted" style={{ margin: 0 }}>
          Room code <span className="ga-code">{room.code}</span> ·{' '}
          {formatTime(room.startsAt, room.timezone)} to {formatTime(room.endsAt, room.timezone)}
        </p>
        {room.demoMode ? (
          <p className="ga-small" style={{ marginTop: 8 }}>
            <span className="ga-chip ga-chip--demo">Demo mode</span>{' '}
            <span className="ga-muted">
              {skips === 1 ? '1 location check skipped' : `${skips} location checks skipped`} today
            </span>
          </p>
        ) : null}
      </div>

      <div className="ga-row">
        <Link className="ga-button ga-button--secondary" href={`/admin/rooms/${room.id}/metrics`}>
          Live numbers
        </Link>
        <Link className="ga-button ga-button--secondary" href={`/admin/rooms/${room.id}/cards`}>
          Cards in the room
        </Link>
      </div>

      <RoomControls room={room} />
      <SpotsEditor roomId={room.id} spots={room.spots} />

      <section className="ga-stack" aria-labelledby="details">
        <h2 id="details" style={{ marginBottom: 0 }}>
          Details
        </h2>
        <RoomForm room={room} />
      </section>
    </div>
  );
}
