// Owner: B7. Cards in a room right now, for moderation.
import Link from 'next/link';
import { listCards } from '@/server/admin/cards';
import { getRoom } from '@/server/admin/rooms';
import { adminPage, adminTitle, idOrNotFound, orNotFound } from '@/server/admin/web';
import { CardTile } from '../../../../_components/CardTile';

export const generateMetadata = adminTitle('Cards');

export default async function CardsPage({ params }: { params: Promise<{ id: string }> }) {
  await adminPage();
  const id = idOrNotFound((await params).id);
  const [room, cards] = await orNotFound(() => Promise.all([getRoom(id), listCards(id)]));
  return (
    <div className="ga-stack">
      <p className="ga-small" style={{ margin: 0 }}>
        <Link href={`/admin/rooms/${room.id}`}>← {room.name}</Link>
      </p>
      <h1 style={{ marginTop: 0 }}>Cards in the room</h1>
      <p className="ga-muted" style={{ margin: 0 }}>
        {cards.length === 1 ? '1 card' : `${cards.length} cards`}, newest first. Photos show only
        when you ask, with your own watermark.
      </p>
      {cards.length === 0 ? (
        <p className="ga-muted">Nobody is checked in right now.</p>
      ) : (
        <ul className="ga-list">
          {cards.map((card) => (
            <CardTile key={card.id} card={card} timeZone={room.timezone} />
          ))}
        </ul>
      )}
    </div>
  );
}
