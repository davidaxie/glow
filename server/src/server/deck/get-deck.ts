/**
 * Owner: B4. `POST /api/rooms/{id}/deck` (getDeck).
 *
 * Every deck rule in docs/SPEC.md ("Who appears in your deck"), the filters, the daily view
 * cap and the all-day shuffle are applied in one place, the `get_deck` database function, so
 * no route can skip one. This handler validates the filters, calls it, and turns each card
 * into the contract's shape with a signed image link bound to this viewer.
 *
 * A card carries its card ID (the check-in ID), its image link, its tags and whether *I*
 * tapped it. Never a user ID, name, face or distance (P1), and nothing about whether they
 * tapped me (P5).
 */
import {
  CARD_VIEWS_PER_ROOM_PER_DAY,
  type Card,
  type CardTags,
  type Deck,
  type DeckEmptyReason,
  type DeckFilters,
  type DeckRequest,
} from '@/contracts';
import { badRequest, type RouteHandler } from '@/server/http';
import type { ErrorIssue } from '@/server/http/errors';
import { rpc } from './db';
import { cardImageLink, rateLimit } from './dependencies';

/** What `get_deck` returns (docs/CONTRACTS.md). `cardPath` is storage-internal and never sent. */
type DbCard = {
  readonly id: string;
  readonly cardPath?: string;
  readonly tags: {
    readonly topColor: CardTags['topColor'];
    readonly hairLength?: CardTags['hairLength'] | null;
    readonly hairColor?: CardTags['hairColor'] | null;
    readonly extras?: CardTags['extras'] | null;
  };
  readonly tappedByMe: boolean;
};

type DbDeck = {
  readonly cards: readonly DbCard[];
  readonly viewsLeftToday: number;
  readonly hasMore: boolean;
  readonly nextOffset?: number | null;
  readonly emptyReason?: DeckEmptyReason | null;
};

const FILTER_KEYS = ['gender', 'topColor', 'hairLength', 'hairColor', 'extras'] as const;

/**
 * The contract's zod schemas check each value, but not `uniqueItems`. A repeated value is a
 * request that doesn't match the contract, so it's a 400 like any other, naming only the field.
 */
export function validateFilters(filters: DeckFilters | undefined): DeckFilters {
  if (!filters) return {};
  const issues: ErrorIssue[] = [];
  const clean: Record<string, string[]> = {};
  for (const key of FILTER_KEYS) {
    const values = filters[key] as readonly string[] | undefined;
    if (values === undefined) continue;
    if (new Set(values).size !== values.length) {
      issues.push({
        path: `body.filters.${key}`,
        code: 'not_unique',
        message: 'Each value may appear once.',
      });
      continue;
    }
    // An empty list means any, which is the same as leaving the field out.
    if (values.length > 0) clean[key] = [...values];
  }
  if (issues.length > 0) throw badRequest('The body is not valid.', issues);
  return clean as DeckFilters;
}

function toTags(tags: DbCard['tags']): CardTags {
  return {
    topColor: tags.topColor,
    ...(tags.hairLength ? { hairLength: tags.hairLength } : {}),
    ...(tags.hairColor ? { hairColor: tags.hairColor } : {}),
    extras: [...(tags.extras ?? [])],
  };
}

/** Builds the reply from exactly the fields the contract has, so nothing else can leak. */
export function toDeck(raw: DbDeck, viewerId: string, now = Date.now()): Deck {
  const cards: Card[] = raw.cards.map((card) => ({
    id: card.id,
    image: cardImageLink(card.id, viewerId, now),
    tags: toTags(card.tags),
    tappedByMe: card.tappedByMe === true,
  }));
  return {
    cards,
    viewsLeftToday: Math.max(0, raw.viewsLeftToday),
    hasMore: raw.hasMore === true && typeof raw.nextOffset === 'number',
    ...(raw.hasMore === true && typeof raw.nextOffset === 'number'
      ? { nextOffset: raw.nextOffset }
      : {}),
    ...(cards.length === 0 && raw.emptyReason ? { emptyReason: raw.emptyReason } : {}),
  };
}

/** One page of this viewer's deck in this room. Throws 404 if they never checked in there. */
export async function loadDeck(
  viewerId: string,
  roomId: string,
  request: DeckRequest | undefined,
  now = Date.now(),
): Promise<Deck> {
  const filters = validateFilters(request?.filters);
  // get_deck never shows more than CARD_VIEWS_PER_ROOM_PER_DAY cards in a day, so any offset
  // past that is the same empty last page. Clamping keeps huge offsets inside a Postgres integer.
  const offset = Math.min(request?.offset ?? 0, CARD_VIEWS_PER_ROOM_PER_DAY);
  const raw = (await rpc('get_deck', {
    p_viewer_id: viewerId,
    p_room_id: roomId,
    p_filters: filters,
    p_offset: offset,
  })) as unknown as DbDeck;
  return toDeck(raw, viewerId, now);
}

export const getDeckRoute: RouteHandler<'getDeck'> = async ({ user, params, body }) => {
  await rateLimit(user.id, 'deck');
  return { status: 200, body: await loadDeck(user.id, params.id, body) };
};
