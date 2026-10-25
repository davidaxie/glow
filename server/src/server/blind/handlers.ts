/**
 * Owner: X1. Blind mode routes (docs/briefs/blind-mode.md). Every rule lives in the blind_*
 * database functions; these handlers sign image links, gate the drop clock, run the give-away
 * check, and pick reply fields one by one, so nothing a function might add later (a user ID, a
 * side) can reach the app (B1). The route helper then drops anything the contract doesn't declare.
 */
import { z } from 'zod';
import { getEnv } from '@/env';
import { conflict, notFound, type RouteHandler } from '@/server/http';
import { logger } from '@/server/log';
import { readPrivateObject, viewerCodeOf, watermarkedResponse } from '@/server/images/serve';
import { PROFILE_BUCKET, serviceClient } from '@/server/images/supabase';
import { announceEnded } from '@/server/safety/announce';
import { serviceDb } from '@/server/safety/db';
import { blindRpc } from './db';
import { checkLeak } from './leak-check';
import {
  blindCardLink,
  blindPhotoLink,
  isValidBlindCardLink,
  isValidBlindPhotoLink,
} from './links';
import { dropGate, todaysDrop } from './schedule';

const Count = z.number().int().min(0);
const Me = z.object({
  member: z.boolean(),
  hasPhoto: z.boolean(),
  rightRemaining: Count,
  rightCount: Count,
  canDrop: z.boolean(),
});
const Counters = z.object({ rightRemaining: Count, rightCount: Count });
const Pool = z.object({ rightCount: Count, rightRemaining: Count, canDrop: z.boolean() });
const Cards = z.object({ cards: z.array(z.object({ id: z.uuid() })) });
const Opened = z.object({ opened: Count });
const DropChats = z.object({ chats: z.array(z.object({ id: z.uuid(), codename: z.string() })) });
const Status = z.enum(['open', 'left', 'revealed']);
const LastMessage = z.object({ mine: z.boolean(), text: z.string(), at: z.string() });
const ChatList = z.object({
  chats: z.array(
    z.object({
      id: z.uuid(),
      codename: z.string(),
      status: Status,
      unread: z.boolean(),
      lastMessage: LastMessage.optional(),
    }),
  ),
});
const Chat = z.object({
  id: z.uuid(),
  codename: z.string(),
  status: Status,
  iTappedReveal: z.boolean(),
  theyLeft: z.boolean(),
  partner: z.object({ name: z.string(), photoCount: Count }).optional(),
  guessCorrect: z.boolean().optional(),
});
const Message = z.object({
  id: z.number().int().min(1),
  mine: z.boolean(),
  text: z.string(),
  at: z.string(),
});
const Messages = z.object({ messages: z.array(Message) });
const Block = z.object({ endedMatchIds: z.array(z.string()), roomIds: z.array(z.string()) });

function parse<T>(schema: z.ZodType<T>, fn: string, raw: unknown): T {
  const parsed = schema.safeParse(raw);
  if (!parsed.success) {
    logger.error('blind.unexpected_shape', { fn });
    throw new Error(`${fn} returned an unexpected shape`);
  }
  return parsed.data;
}

const me = (raw: unknown) => {
  const m = parse(Me, 'blind_me', raw);
  return {
    member: m.member,
    hasPhoto: m.hasPhoto,
    rightRemaining: m.rightRemaining,
    rightCount: m.rightCount,
    canDrop: m.canDrop,
  };
};

function cardsFor(raw: unknown, fn: string, viewerId: string) {
  const now = Date.now();
  return {
    cards: parse(Cards, fn, raw).cards.map((c) => ({
      id: c.id,
      photoUrl: blindCardLink(c.id, viewerId, now),
    })),
  };
}

// ------------------------------------------------------------------ membership
export const blindGetMe: RouteHandler<'blindGetMe'> = async ({ user }) => ({
  status: 200,
  body: me(await blindRpc('blind_me', { p_user_id: user.id })),
});

export const blindJoin: RouteHandler<'blindJoin'> = async ({ user }) => {
  const body = me(await blindRpc('blind_join', { p_user_id: user.id }));
  logger.info('blind.join', {});
  return { status: 200, body };
};

export const blindLeave: RouteHandler<'blindLeave'> = async ({ user }) => {
  await blindRpc('blind_leave', { p_user_id: user.id });
  logger.info('blind.leave', {});
  return { status: 204 };
};

// ------------------------------------------------------------------ deck, swipes, pool
export const blindGetDeck: RouteHandler<'blindGetDeck'> = async ({ user, query }) => ({
  status: 200,
  body: cardsFor(
    await blindRpc('blind_deck', { p_viewer_id: user.id, p_limit: query.limit ?? 10 }),
    'blind_deck',
    user.id,
  ),
});

export const blindSwipe: RouteHandler<'blindSwipe'> = async ({ user, body }) => {
  const c = parse(
    Counters,
    'blind_record_swipe',
    await blindRpc('blind_record_swipe', {
      p_swiper_id: user.id,
      p_card_id: body.targetId,
      p_kind: body.kind,
    }),
  );
  logger.info('blind.swipe', { kind: body.kind });
  return { status: 200, body: { rightRemaining: c.rightRemaining, rightCount: c.rightCount } };
};

export const blindGetPool: RouteHandler<'blindGetPool'> = async ({ user }) => {
  const p = parse(Pool, 'blind_pool', await blindRpc('blind_pool', { p_user_id: user.id }));
  return {
    status: 200,
    body: { rightCount: p.rightCount, rightRemaining: p.rightRemaining, canDrop: p.canDrop },
  };
};

export const blindGetPoolCards: RouteHandler<'blindGetPoolCards'> = async ({ user }) => ({
  status: 200,
  body: cardsFor(
    await blindRpc('blind_pool_cards', { p_user_id: user.id }),
    'blind_pool_cards',
    user.id,
  ),
});

export const blindGetCardImage: RouteHandler<'blindGetCardImage'> = async ({
  user,
  params,
  query,
}) => {
  if (!isValidBlindCardLink(params.cardId, user.id, query.exp, query.sig)) throw notFound();
  const path = await blindRpc('blind_card_photo_path', {
    p_viewer_id: user.id,
    p_card_id: params.cardId,
  });
  if (typeof path !== 'string' || path.length === 0) throw notFound();
  const db = serviceClient();
  const [bytes, code] = await Promise.all([
    readPrivateObject(PROFILE_BUCKET, path, db),
    viewerCodeOf(user.id, db),
  ]);
  return watermarkedResponse(bytes, code);
};

// ------------------------------------------------------------------ drops
async function pool(userId: string) {
  return parse(Pool, 'blind_pool', await blindRpc('blind_pool', { p_user_id: userId }));
}

export const blindGetDrop: RouteHandler<'blindGetDrop'> = async ({ user }) => {
  const p = await pool(user.id);
  const gate = dropGate(new Date(), getEnv().BLIND_DEMO_MODE === true);
  return {
    status: 200,
    body: { ...gate, rightCount: p.rightCount, canDrop: p.canDrop },
  };
};

export const blindOpenDrop: RouteHandler<'blindOpenDrop'> = async ({ user }) => {
  const now = new Date();
  const demo = getEnv().BLIND_DEMO_MODE === true;
  await pool(user.id); // not a member is 404 before the clock says anything
  if (!dropGate(now, demo).ready) throw conflict('drop_not_ready', 'Your drop opens at 8pm.');
  // Outside demo mode only matches made before today's drop time open (Double Blind F-01).
  await blindRpc('blind_run_drop', {
    p_user_id: user.id,
    ...(demo ? {} : { p_cutoff: todaysDrop(now).toISOString() }),
  });
  const chats = parse(
    DropChats,
    'blind_drop_new_chats',
    await blindRpc('blind_drop_new_chats', { p_user_id: user.id }),
  ).chats.map((c) => ({ id: c.id, codename: c.codename }));
  logger.info('blind.drop', { opened: chats.length, demo });
  return { status: 200, body: { opened: chats.length, chats } };
};

async function dropAll() {
  const r = parse(Opened, 'blind_run_drop_all', await blindRpc('blind_run_drop_all', {}));
  logger.info('blind.drop_all', { opened: r.opened });
  return { status: 200 as const, body: { opened: r.opened } };
}
export const blindAdminDrop: RouteHandler<'blindAdminDrop'> = () => dropAll();
export const blindCronDrop: RouteHandler<'blindCronDrop'> = () => dropAll();

// ------------------------------------------------------------------ chats
export const blindListChats: RouteHandler<'blindListChats'> = async ({ user }) => {
  const list = parse(
    ChatList,
    'blind_chat_list',
    await blindRpc('blind_chat_list', { p_user_id: user.id }),
  );
  return {
    status: 200,
    body: {
      chats: list.chats.map((c) => ({
        id: c.id,
        codename: c.codename,
        status: c.status,
        unread: c.unread,
        ...(c.lastMessage
          ? {
              lastMessage: {
                mine: c.lastMessage.mine,
                text: c.lastMessage.text,
                at: new Date(c.lastMessage.at).toISOString(),
              },
            }
          : {}),
      })),
    },
  };
};

export const blindGetChat: RouteHandler<'blindGetChat'> = async ({ user, params }) => {
  const c = parse(
    Chat,
    'blind_get_chat',
    await blindRpc('blind_get_chat', { p_user_id: user.id, p_chat_id: params.id }),
  );
  const revealed = c.status === 'revealed';
  const now = Date.now();
  return {
    status: 200,
    body: {
      id: c.id,
      codename: c.codename,
      status: c.status,
      iTappedReveal: c.iTappedReveal,
      theyLeft: c.status === 'left' && c.theyLeft,
      // B1: the partner exists only once both tapped Reveal.
      ...(revealed
        ? {
            partner: {
              name: c.partner?.name ?? '',
              photos: Array.from({ length: Math.min(c.partner?.photoCount ?? 0, 3) }, (_, n) =>
                blindPhotoLink(c.id, n, user.id, now),
              ),
            },
          }
        : {}),
      ...(revealed && c.guessCorrect !== undefined ? { guessCorrect: c.guessCorrect } : {}),
    },
  };
};

export const blindGetPartnerPhoto: RouteHandler<'blindGetPartnerPhoto'> = async ({
  user,
  params,
  query,
}) => {
  if (!isValidBlindPhotoLink(params.id, params.n, user.id, query.exp, query.sig)) throw notFound();
  const path = await blindRpc('blind_partner_photo_path', {
    p_viewer_id: user.id,
    p_chat_id: params.id,
    p_n: params.n,
  });
  if (typeof path !== 'string' || path.length === 0) throw notFound();
  const db = serviceClient();
  const [bytes, code] = await Promise.all([
    readPrivateObject(PROFILE_BUCKET, path, db),
    viewerCodeOf(user.id, db),
  ]);
  return watermarkedResponse(bytes, code);
};

const pickMessage = (m: z.infer<typeof Message>) => ({
  id: m.id,
  mine: m.mine,
  text: m.text,
  at: new Date(m.at).toISOString(),
});

export const blindListMessages: RouteHandler<'blindListMessages'> = async ({
  user,
  params,
  query,
}) => {
  const list = parse(
    Messages,
    'blind_list_messages',
    await blindRpc('blind_list_messages', {
      p_user_id: user.id,
      p_chat_id: params.id,
      p_after: query.after ?? 0,
    }),
  );
  return { status: 200, body: { messages: list.messages.map(pickMessage) } };
};

async function ownFirstName(userId: string): Promise<string | null> {
  const { data } = await serviceDb()
    .from('profiles')
    .select('first_name')
    .eq('id', userId)
    .maybeSingle();
  return data?.first_name ?? null;
}

export const blindSendMessage: RouteHandler<'blindSendMessage'> = async ({
  user,
  params,
  body,
}) => {
  if (body.confirm !== true) {
    // Make sure the chat is mine and open before saying anything about the text (P11).
    const chat = parse(
      Chat,
      'blind_get_chat',
      await blindRpc('blind_get_chat', { p_user_id: user.id, p_chat_id: params.id }),
    );
    if (chat.status === 'left') throw conflict('chat_closed', 'This chat has ended.');
    const leak = checkLeak(body.text, await ownFirstName(user.id));
    if (leak.leak) {
      logger.info('blind.warning_shown', {});
      return { status: 200, body: { warning: { reason: leak.reason } } };
    }
  }
  const m = parse(
    Message,
    'blind_send_message',
    await blindRpc('blind_send_message', {
      p_user_id: user.id,
      p_chat_id: params.id,
      p_body: body.text,
    }),
  );
  logger.info('blind.message_sent', {});
  return { status: 200, body: { message: pickMessage(m) } };
};

export const blindReveal: RouteHandler<'blindReveal'> = async ({ user, params }) => {
  const r = parse(
    z.object({ status: Status }),
    'blind_tap_reveal',
    await blindRpc('blind_tap_reveal', { p_user_id: user.id, p_chat_id: params.id }),
  );
  logger.info('blind.reveal_tapped', { mutual: r.status === 'revealed' });
  return { status: 200, body: { status: r.status } };
};

export const blindLeaveChat: RouteHandler<'blindLeaveChat'> = async ({ user, params }) => {
  await blindRpc('blind_leave_chat', { p_user_id: user.id, p_chat_id: params.id });
  logger.info('blind.chat_left', {});
  return { status: 200, body: { ok: true } };
};

export const blindGuess: RouteHandler<'blindGuess'> = async ({ user, params, body }) => {
  await blindRpc('blind_record_guess', {
    p_user_id: user.id,
    p_chat_id: params.id,
    p_card_id: body.guessId,
  });
  return { status: 200, body: { ok: true } };
};

export const blindBlock: RouteHandler<'blindBlock'> = async ({ user, params }) => {
  const r = parse(
    Block,
    'blind_block',
    await blindRpc('blind_block', { p_user_id: user.id, p_chat_id: params.id }),
  );
  logger.info('blind.block', { endedMatches: r.endedMatchIds.length });
  await announceEnded(r);
  return { status: 200, body: { ok: true } };
};

export const blindReport: RouteHandler<'blindReport'> = async ({ user, params, body }) => {
  const r = parse(
    Block,
    'blind_report',
    await blindRpc('blind_report', {
      p_user_id: user.id,
      p_chat_id: params.id,
      p_details: body.reason,
      p_reason: body.category ?? 'other',
    }),
  );
  logger.info('blind.report', { category: body.category ?? 'other' });
  await announceEnded(r);
  return { status: 200, body: { ok: true } };
};
