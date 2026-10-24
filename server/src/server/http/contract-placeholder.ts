/**
 * TEMPORARY. A hand-written stand-in for A2's generated contract, so the route helper
 * and the 501 stubs work before codegen lands. A1 deletes this file when
 * `server/src/contracts` merges, and points `operations.ts` at the generated registry.
 *
 * Only paths, methods, auth and path params are meant to be right here. Request and
 * response schemas are deliberately empty: response schemas strip every field, so
 * nothing can leak through a placeholder. Don't build features against this file.
 */
import { z } from 'zod';
import { defineOperations } from './operation';

const id = z.object({ id: z.uuid() });
const cardId = z.object({ cardId: z.uuid() });
const photo = z.object({ id: z.uuid(), n: z.coerce.number().int().min(0).max(2) });
const slug = z.object({ slug: z.string().regex(/^[a-z0-9-]{1,64}$/) });

const json = z.unknown();
const placeholder = z.object({});
const ok = { 200: placeholder } as const;

export const placeholderOperations = defineOperations({
  // B1 · Sign in and onboarding
  getMe: { method: 'GET', path: '/api/me', auth: 'user', responses: ok },
  updateProfile: {
    method: 'PUT',
    path: '/api/me/profile',
    auth: 'user',
    body: json,
    responses: ok,
  },
  addProfilePhoto: {
    method: 'POST',
    path: '/api/me/photos',
    auth: 'user',
    body: 'multipart',
    responses: { 201: placeholder },
  },
  deleteProfilePhoto: {
    method: 'DELETE',
    path: '/api/me/photos/{id}',
    auth: 'user',
    params: id,
    responses: { 204: null },
  },
  testLogin: {
    method: 'POST',
    path: '/api/dev/test-login',
    auth: 'public',
    body: json,
    responses: ok,
  },

  // B8 · Safety
  setPaused: { method: 'POST', path: '/api/me/pause', auth: 'user', body: json, responses: ok },
  deleteAccount: { method: 'DELETE', path: '/api/me', auth: 'user', responses: { 204: null } },
  createBlock: { method: 'POST', path: '/api/blocks', auth: 'user', body: json, responses: ok },
  createReport: { method: 'POST', path: '/api/reports', auth: 'user', body: json, responses: ok },
  logCapture: {
    method: 'POST',
    path: '/api/abuse/capture',
    auth: 'user',
    body: json,
    responses: { 204: null },
  },
  runPurge: { method: 'GET', path: '/api/cron/purge', auth: 'cron', responses: ok },

  // B5 · Push and realtime
  registerDevice: {
    method: 'POST',
    path: '/api/devices',
    auth: 'user',
    body: json,
    responses: { 201: placeholder },
  },
  deleteDevice: {
    method: 'DELETE',
    path: '/api/devices/{id}',
    auth: 'user',
    params: id,
    responses: { 204: null },
  },

  // B2 · Rooms and joining
  resolveRoom: {
    method: 'POST',
    path: '/api/rooms/resolve',
    auth: 'user',
    body: json,
    responses: ok,
  },
  joinRoom: {
    method: 'POST',
    path: '/api/rooms/{id}/join',
    auth: 'user',
    params: id,
    body: json,
    responses: ok,
  },
  leaveRoom: {
    method: 'POST',
    path: '/api/rooms/{id}/leave',
    auth: 'user',
    params: id,
    responses: { 204: null },
  },
  getAppSiteAssociation: {
    method: 'GET',
    path: '/.well-known/apple-app-site-association',
    auth: 'public',
    responses: { 200: 'raw' },
  },
  getRoomWebPage: {
    method: 'GET',
    path: '/r/{slug}',
    auth: 'public',
    params: slug,
    responses: { 200: 'raw' },
  },

  // B3 · Check-in and private images
  createCheckin: {
    method: 'POST',
    path: '/api/rooms/{id}/checkin',
    auth: 'user',
    params: id,
    body: 'multipart',
    responses: { 201: placeholder },
  },
  getCardImage: {
    method: 'GET',
    path: '/api/cards/{cardId}/image',
    auth: 'user',
    params: cardId,
    responses: { 200: 'raw' },
  },
  getMatchPhoto: {
    method: 'GET',
    path: '/api/matches/{id}/photos/{n}',
    auth: 'user',
    params: photo,
    responses: { 200: 'raw' },
  },

  // B4 · Deck and matching
  getDeck: {
    method: 'POST',
    path: '/api/rooms/{id}/deck',
    auth: 'user',
    params: id,
    body: json,
    responses: ok,
  },
  createTap: {
    method: 'POST',
    path: '/api/rooms/{id}/taps',
    auth: 'user',
    params: id,
    body: json,
    responses: ok,
  },
  listMatches: { method: 'GET', path: '/api/matches', auth: 'user', responses: ok },

  // C2 · Mutual moment
  getMatch: {
    method: 'GET',
    path: '/api/matches/{id}',
    auth: 'user',
    params: id,
    responses: ok,
  },
  setChoice: {
    method: 'POST',
    path: '/api/matches/{id}/choice',
    auth: 'user',
    params: id,
    body: json,
    responses: ok,
  },

  // C3 · Glow
  getGlow: {
    method: 'GET',
    path: '/api/matches/{id}/glow',
    auth: 'user',
    params: id,
    responses: ok,
  },
  markGlowMet: {
    method: 'POST',
    path: '/api/matches/{id}/glow/met',
    auth: 'user',
    params: id,
    responses: ok,
  },
  cancelGlow: {
    method: 'POST',
    path: '/api/matches/{id}/glow/cancel',
    auth: 'user',
    params: id,
    responses: ok,
  },

  // C4 · Chat
  listMessages: {
    method: 'GET',
    path: '/api/matches/{id}/messages',
    auth: 'user',
    params: id,
    responses: ok,
  },
  sendMessage: {
    method: 'POST',
    path: '/api/matches/{id}/messages',
    auth: 'user',
    params: id,
    body: json,
    responses: { 201: placeholder },
  },
  unmatch: {
    method: 'POST',
    path: '/api/matches/{id}/unmatch',
    auth: 'user',
    params: id,
    responses: { 204: null },
  },
});
