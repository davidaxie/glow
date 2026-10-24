/**
 * Moderating cards in a room: list them, look at one (watermarked with the admin's own code),
 * and remove a card or the person behind it.
 */
import type { AdminCard } from '@/contracts';
import { notFound } from '@/server/http';
import { logger } from '@/server/log';
import { deps } from './context';
import type { CardRecord } from './repo';
import { toAdminCard } from './views';
import { watermarkJpeg } from './watermark';

export type RemoveScope = 'card' | 'person';

export async function listCards(roomId: string): Promise<AdminCard[]> {
  const { repo } = deps();
  if (!(await repo.findRoom({ id: roomId }))) throw notFound();
  return (await repo.openCards(roomId)).map(toAdminCard);
}

/** The card photo with the admin's watermark, or 404 if the card or its photo is gone. */
export async function cardImage(cardId: string, adminId: string): Promise<Buffer> {
  const { repo } = deps();
  const card = await repo.findCard(cardId);
  if (!card || card.leftAt !== null) throw notFound();
  const [photo, code] = await Promise.all([
    repo.cardPhoto(card.cardPath),
    repo.viewerCode(adminId),
  ]);
  if (!photo || !code) throw notFound();
  logger.info('admin.card_viewed', { cardId, adminId });
  return watermarkJpeg(photo, code);
}

/** Hides cards (and with `person`, ends the check-ins), deletes their photos, tells rooms. */
export async function hideAndNotify(
  cardIds: readonly string[],
  scope: RemoveScope,
): Promise<CardRecord[]> {
  const { repo, events } = deps();
  const changed = await repo.hideCards(cardIds, scope === 'person');
  const paths = [...new Set(changed.map((c) => c.cardPath))];
  if (paths.length > 0) await repo.deleteCardPhotos(paths);
  for (const roomId of new Set(changed.map((c) => c.roomId))) await events.deckChanged(roomId);
  return changed;
}

export async function removeCard(
  cardId: string,
  scope: RemoveScope,
  adminId: string,
): Promise<void> {
  const card = await deps().repo.findCard(cardId);
  // A check-in that already ended has nothing left to remove.
  if (!card || card.leftAt !== null) throw notFound();
  await hideAndNotify([card.id], scope);
  logger.info('admin.card_removed', { cardId, roomId: card.roomId, adminId, scope });
}
