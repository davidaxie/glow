/**
 * `POST /api/devices` and `DELETE /api/devices/{id}`.
 */
import { zDeviceRegistration } from '@/contracts';
import { badRequest, notFound, type RouteHandler } from '@/server/http';
import { logger } from '@/server/log';
import { registerDevice, removeDevice } from './devices';

/** Registers (or moves to this person) a push token. */
export const registerDeviceRoute: RouteHandler<'registerDevice'> = async ({ user, body }) => {
  // The route helper validates the body against the contract already; parsing again keeps
  // this handler typed and safe on its own.
  const parsed = zDeviceRegistration.safeParse(body);
  if (!parsed.success) throw badRequest();
  const device = await registerDevice(user.id, parsed.data);
  logger.info('devices.registered', { environment: parsed.data.environment });
  return { status: 201, body: { id: device.id } };
};

/** Removes one of this person's push tokens. Someone else's is a 404, like a missing one (P11). */
export const deleteDeviceRoute: RouteHandler<'deleteDevice'> = async ({ user, params }) => {
  if (!(await removeDevice(user.id, params.id))) throw notFound();
  logger.info('devices.removed');
  return { status: 204 };
};
