/**
 * Owner: X1. Calls the blind_* database functions and maps their expected failures to the
 * contract's errors. Never logs arguments or results (message text, IDs), only the function
 * name and an error code.
 */
import { conflict, notFound, type HttpError } from '@/server/http';
import { dbError, serviceDb, type DbFunction } from '@/server/safety/db';
import type { Database } from '@/contracts';

type Functions = Database['public']['Functions'];

const EXPECTED: Readonly<Record<string, () => HttpError>> = {
  not_found: notFound,
  onboarding_incomplete: () =>
    conflict('onboarding_incomplete', 'Finish your Glow profile before joining Blind.'),
  right_cap_reached: () => conflict('right_cap_reached', 'No right swipes left today.'),
  chat_closed: () => conflict('chat_closed', 'This chat has ended.'),
};

export async function blindRpc<F extends DbFunction>(
  fn: F,
  args: Functions[F]['Args'],
): Promise<unknown> {
  const { data, error } = await serviceDb().rpc(fn, args as never);
  if (error) {
    if (error.code === 'P0001' && EXPECTED[error.message]) throw EXPECTED[error.message]!();
    throw dbError(fn, error);
  }
  return data;
}
