// Owner: B7. Live numbers for a room, from anonymous counters. There is deliberately no tap
// count (P5, D52): watching it tick up could tell an admin in the room who just tapped.
import Link from 'next/link';
import { roomMetrics } from '@/server/admin/metrics';
import { getRoom } from '@/server/admin/rooms';
import { adminPage, adminTitle, idOrNotFound, orNotFound } from '@/server/admin/web';
import { AutoRefresh } from '../../../../_components/AutoRefresh';
import { formatTime } from '../../../../_components/format';

export const generateMetadata = adminTitle('Live numbers');

export default async function MetricsPage({ params }: { params: Promise<{ id: string }> }) {
  await adminPage();
  const id = idOrNotFound((await params).id);
  const [room, m] = await orNotFound(() => Promise.all([getRoom(id), roomMetrics(id)]));
  const tiles = [
    { label: 'Checked in now', value: m.activeCheckins },
    { label: 'Joins today', value: m.checkins },
    { label: 'Cards viewed', value: m.cardViews },
    { label: 'Matches', value: m.matches },
    { label: 'Glows started', value: m.glowsStarted },
    { label: 'We met', value: m.glowsMet },
    { label: 'Reports', value: m.reports },
  ];
  return (
    <div className="ga-stack">
      <p className="ga-small" style={{ margin: 0 }}>
        <Link href={`/admin/rooms/${room.id}`}>← {room.name}</Link>
      </p>
      <h1 style={{ marginTop: 0 }}>Live numbers</h1>
      <p className="ga-muted" style={{ margin: 0 }}>
        Since {formatTime(m.since, room.timezone)}. Taps are never counted here, so nobody can work
        out who tapped whom.
      </p>
      <div className="ga-tiles" role="list">
        {tiles.map((tile) => (
          <div key={tile.label} className="ga-tile" role="listitem">
            <div className="ga-tile__value">{tile.value.toLocaleString('en-US')}</div>
            <div className="ga-tile__label">{tile.label}</div>
          </div>
        ))}
      </div>
      <AutoRefresh seconds={10} />
    </div>
  );
}
