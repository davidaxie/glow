// Owner: B7. Rooms, newest first.
import type { Metadata } from 'next';
import Link from 'next/link';
import { listRooms } from '@/server/admin/rooms';
import { adminPage } from '@/server/admin/web';
import { formatTime, statusLabel } from '../_components/format';

export const metadata: Metadata = { title: 'Rooms' };

export default async function RoomsPage() {
  // Every page checks too: on client navigation the layout above doesn't run again.
  await adminPage();
  const rooms = await listRooms();
  return (
    <div className="ga-stack">
      <div className="ga-row ga-row--between">
        <h1>Rooms</h1>
        <Link href="/admin/rooms/new" className="ga-button">
          New room
        </Link>
      </div>
      {rooms.length === 0 ? (
        <p className="ga-muted">No rooms yet. Make one at the venue: it takes about a minute.</p>
      ) : (
        <ul className="ga-list">
          {rooms.map((room) => (
            <li key={room.id} className="ga-card">
              <div className="ga-row ga-row--between">
                <h2 style={{ margin: 0 }}>
                  <Link href={`/admin/rooms/${room.id}`}>{room.name}</Link>
                </h2>
                <span className={`ga-chip ga-chip--${room.status}`}>
                  {statusLabel(room.status)}
                </span>
              </div>
              <p className="ga-small ga-muted" style={{ margin: '8px 0 12px' }}>
                Code <span className="ga-code">{room.code}</span> ·{' '}
                {formatTime(room.startsAt, room.timezone)} to{' '}
                {formatTime(room.endsAt, room.timezone)}
                {room.demoMode ? ' · Demo mode' : ''}
              </p>
              <div className="ga-row">
                <Link
                  className="ga-button ga-button--secondary ga-button--small"
                  href={`/admin/rooms/${room.id}`}
                >
                  Manage
                </Link>
                <Link
                  className="ga-button ga-button--secondary ga-button--small"
                  href={`/admin/rooms/${room.id}/metrics`}
                >
                  Live numbers
                </Link>
                <a
                  className="ga-button ga-button--secondary ga-button--small"
                  href={`/display/${room.slug}`}
                  target="_blank"
                  rel="noopener"
                >
                  Display screen
                </a>
              </div>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
