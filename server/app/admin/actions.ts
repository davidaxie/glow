'use server';
// Owner: B7. Server actions for the admin web. Each is a public POST endpoint, so each one
// checks the admin session first (anyone else gets 404) and validates its input.
import { redirect } from 'next/navigation';
import { z } from 'zod';
import {
  zAdminRemoveCard,
  zAdminRoomCreate,
  zAdminRoomUpdate,
  zMeetingSpotsReplace,
  zReportResolution,
  type AdminRoom,
} from '@/contracts';
import { cardImage, removeCard } from '@/server/admin/cards';
import { posterPdf } from '@/server/admin/poster';
import { qrSvg, type QrSvg } from '@/server/admin/qr-code';
import { resolveReport } from '@/server/admin/reports';
import {
  createRoom,
  getRoomRecord,
  replaceSpots,
  rotateStaticToken,
  screenTokenFor,
  updateRoom,
} from '@/server/admin/rooms';
import { deps } from '@/server/admin/context';
import {
  refreshSession,
  sendCode,
  signOut,
  testSignIn,
  verifyCode,
  type SendCodeResult,
} from '@/server/admin/session';
import { adminAction, attempt, parseInput, type ActionResult } from '@/server/admin/web';

const zEmail = z.email().max(254);
const zCode = z.string().regex(/^\d{6}$/);
const zId = z.uuid();

// ---------------------------------------------------------------- sign-in

export type SignInState =
  | { readonly step: 'email'; readonly message?: string }
  | { readonly step: 'code'; readonly email: string; readonly message?: string };

export async function sendCodeAction(_: SignInState, form: FormData): Promise<SignInState> {
  const email = zEmail.safeParse(
    String(form.get('email') ?? '')
      .trim()
      .toLowerCase(),
  );
  if (!email.success) return { step: 'email', message: 'Enter your email address.' };
  let result: SendCodeResult;
  try {
    result = await sendCode(email.data);
  } catch {
    return { step: 'email', message: 'Sign-in is briefly unavailable. Try again in a moment.' };
  }
  if (result === 'rate_limited') {
    return { step: 'email', message: 'Too many codes were sent. Wait a minute and try again.' };
  }
  return { step: 'code', email: email.data };
}

export async function verifyCodeAction(_: SignInState, form: FormData): Promise<SignInState> {
  const email = zEmail.safeParse(String(form.get('email') ?? ''));
  const code = zCode.safeParse(String(form.get('code') ?? '').replace(/\s/g, ''));
  if (!email.success) return { step: 'email' };
  if (!code.success) return { step: 'code', email: email.data, message: 'Enter the 6 digits.' };
  if ((await verifyCode(email.data, code.data)) !== 'ok') {
    return {
      step: 'code',
      email: email.data,
      message: "That code didn't work. Check the newest email, or send a new code.",
    };
  }
  redirect('/admin');
}

export async function testSignInAction(_: SignInState, form: FormData): Promise<SignInState> {
  const email = zEmail.safeParse(
    String(form.get('email') ?? '')
      .trim()
      .toLowerCase(),
  );
  if (!email.success || (await testSignIn(email.data)) !== 'ok') {
    return { step: 'email', message: 'Test sign-in only works for admin @glow.test addresses.' };
  }
  redirect('/admin');
}

export async function signOutAction(): Promise<void> {
  await signOut();
  redirect('/admin/sign-in');
}

/** Keeps a signed-in admin signed in. False means the session is over. */
export async function refreshSessionAction(): Promise<boolean> {
  try {
    return await refreshSession();
  } catch {
    return false;
  }
}

// ---------------------------------------------------------------- rooms

export async function createRoomAction(input: unknown): Promise<ActionResult<AdminRoom>> {
  const admin = await adminAction();
  return attempt('createRoom', () => createRoom(parseInput(zAdminRoomCreate, input), admin.userId));
}

export async function updateRoomAction(
  roomId: string,
  input: unknown,
): Promise<ActionResult<AdminRoom>> {
  const admin = await adminAction();
  return attempt('updateRoom', () =>
    updateRoom(parseInput(zId, roomId), parseInput(zAdminRoomUpdate, input), admin.userId),
  );
}

export async function replaceSpotsAction(
  roomId: string,
  spots: unknown,
): Promise<ActionResult<AdminRoom>> {
  const admin = await adminAction();
  return attempt('replaceSpots', () =>
    replaceSpots(
      parseInput(zId, roomId),
      parseInput(zMeetingSpotsReplace, { spots }).spots,
      admin.userId,
    ),
  );
}

export async function rotateStaticTokenAction(roomId: string): Promise<ActionResult<AdminRoom>> {
  const admin = await adminAction();
  return attempt('rotateStaticToken', () =>
    rotateStaticToken(parseInput(zId, roomId), admin.userId),
  );
}

export type PosterFile = { readonly base64: string; readonly filename: string };

export async function posterAction(roomId: string): Promise<ActionResult<PosterFile>> {
  await adminAction();
  return attempt('poster', async () => {
    const room = await getRoomRecord(parseInput(zId, roomId));
    const pdf = await posterPdf(room);
    return {
      base64: Buffer.from(pdf).toString('base64'),
      filename: `glow-poster-${room.slug}.pdf`,
    };
  });
}

// ---------------------------------------------------------------- display

export type DisplayFrame = {
  readonly state: 'live' | 'paused' | 'ended' | 'not_started';
  readonly name: string;
  readonly code: string;
  readonly startsAt: string;
  /** The current screen link as a QR, only while the room is live. */
  readonly qr: QrSvg | null;
  readonly windowEndsAt: string | null;
  readonly serverNow: string;
};

export async function displayFrameAction(roomId: string): Promise<ActionResult<DisplayFrame>> {
  await adminAction();
  return attempt('displayFrame', async () => {
    const now = deps().now();
    const room = await getRoomRecord(parseInput(zId, roomId));
    const state =
      room.status !== 'live'
        ? room.status
        : Date.parse(room.endsAt) <= now
          ? 'ended'
          : Date.parse(room.startsAt) > now
            ? 'not_started'
            : 'live';
    // A screen token only exists while it can get someone in: never for a paused or ended room.
    const token = state === 'live' ? screenTokenFor(room, now) : null;
    return {
      state,
      name: room.name,
      code: room.code,
      startsAt: room.startsAt,
      qr: token ? qrSvg(token.url) : null,
      windowEndsAt: token?.windowEndsAt ?? null,
      serverNow: new Date(now).toISOString(),
    };
  });
}

// ---------------------------------------------------------------- cards

export async function cardPhotoAction(cardId: string): Promise<ActionResult<string>> {
  const admin = await adminAction();
  return attempt('cardPhoto', async () => {
    const jpeg = await cardImage(parseInput(zId, cardId), admin.userId);
    return `data:image/jpeg;base64,${jpeg.toString('base64')}`;
  });
}

export async function removeCardAction(cardId: string, scope: unknown): Promise<ActionResult> {
  const admin = await adminAction();
  return attempt('removeCard', async () => {
    const body = parseInput(zAdminRemoveCard, { scope });
    await removeCard(parseInput(zId, cardId), body.scope, admin.userId);
    return null;
  });
}

// ---------------------------------------------------------------- reports

export async function resolveReportAction(
  reportId: string,
  action: unknown,
): Promise<ActionResult> {
  const admin = await adminAction();
  return attempt('resolveReport', async () => {
    const body = parseInput(zReportResolution, { action });
    await resolveReport(parseInput(zId, reportId), body.action, admin.userId);
    return null;
  });
}
