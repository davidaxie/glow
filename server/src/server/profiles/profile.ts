/**
 * `PUT /api/me/profile`: first name, birthday, gender and who I want to see.
 *
 * Under 18 is 422 `under_18`, decided before anything is written, so a minor's birthdate is
 * never stored (P10). The database trigger refuses it too, in case a route ever forgets.
 */
import { HttpError, badRequest, unavailable, type RouteHandler } from '@/server/http';
import { logger } from '@/server/log';
import { EARLIEST_BIRTHDATE, isAdult, parseIsoDate, todayInLastTimezone } from './age';
import { serviceDb } from './db';
import { loadMe } from './me';

export const under18 = () =>
  new HttpError(422, 'under_18', 'Glow is only for people 18 and older.');

const issue = (path: string, code: string, message: string) => ({ path, code, message });

export const updateProfile: RouteHandler<'updateProfile'> = async ({ user, body }) => {
  const firstName = body.firstName.trim();
  if (firstName.length === 0) {
    throw badRequest('The body is not valid.', [
      issue('body.firstName', 'too_small', 'A first name is needed.'),
    ]);
  }

  const date = parseIsoDate(body.birthdate);
  if (!date || body.birthdate < EARLIEST_BIRTHDATE || body.birthdate > todayInLastTimezone(new Date())) {
    // Not a real date, or impossibly early or late. Field path only, never the value (P10).
    throw badRequest('The body is not valid.', [
      issue('body.birthdate', 'invalid_value', 'That date is not possible.'),
    ]);
  }

  if (!isAdult(body.birthdate)) {
    // Nothing about this attempt is stored or logged beyond the outcome.
    logger.info('profiles.under_18_refused');
    throw under18();
  }

  const db = serviceDb();
  // Upsert, in case the sign-up trigger's row is somehow missing.
  const { error } = await db.from('profiles').upsert({
    id: user.id,
    first_name: firstName,
    birthdate: body.birthdate,
    gender: body.gender,
    show_me: [...new Set(body.showMe)],
  });
  if (error) {
    // The trigger's own 18+ check (D24) raises P0001 with the message `under_18`.
    if (error.message === 'under_18') {
      logger.info('profiles.under_18_refused', { by: 'database' });
      throw under18();
    }
    logger.error('profiles.update_failed', { code: error.code });
    throw unavailable();
  }

  return { status: 200, body: await loadMe(db, user.id) };
};
