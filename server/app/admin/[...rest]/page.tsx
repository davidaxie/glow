// Owner: B7. Any other address under /admin gets the very same 404 page as a real admin page
// does for someone who isn't an admin, so nobody can tell which addresses exist.
import { notFound } from 'next/navigation';

export default function UnknownAdminPage() {
  notFound();
}
