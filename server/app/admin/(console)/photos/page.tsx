// Owner: B7. Profile photos held for a person to look at, oldest first. Until one is approved,
// its owner stays in onboarding and nobody else ever sees it (D50, P10).
import { listPhotos } from '@/server/admin/photos';
import { DEFAULT_TIMEZONE } from '@/server/admin/rooms';
import { adminPage, adminTitle } from '@/server/admin/web';
import { PhotoTile } from '../../_components/PhotoTile';

export const generateMetadata = adminTitle('Photos');

export default async function PhotosPage() {
  await adminPage();
  const photos = await listPhotos('held');
  return (
    <div className="ga-stack">
      <h1>Photos to review</h1>
      <p className="ga-muted" style={{ margin: 0 }}>
        Profile photos moderation held back, often because the person might be under 18. Only
        approve a photo if you’re sure. Photos show only when you ask, with your own watermark.
      </p>
      {photos.length === 0 ? (
        <p className="ga-muted">Nothing to review.</p>
      ) : (
        <ul className="ga-list">
          {photos.map((photo) => (
            <PhotoTile key={photo.id} photo={photo} timeZone={DEFAULT_TIMEZONE} />
          ))}
        </ul>
      )}
    </div>
  );
}
