/**
 * C2's database calls. Owner: C2.
 *
 * Expected failures come back as SQLSTATE P0001 with the code as the message
 * (docs/CONTRACTS.md, "Database errors"). Anything else is a 500, and the database's own
 * message is never passed on or logged, since it can quote the values involved.
 */
import type { MatchChoice } from '@/contracts';
import { badRequest, notFound, unprocessable } from '@/server/http';
import type { Db } from './db';
import {
  parseResult,
  zDbChoice,
  zDbMatch,
  zDbStartGlow,
  type DbChoice,
  type DbMatch,
  type DbStartGlow,
} from './shapes';

/** A database call that failed for a reason the contract doesn't name. Becomes a 500. */
export class DatabaseError extends Error {
  override readonly name = 'DatabaseError';
}

export const locationRequired = () =>
  unprocessable('location_required', 'Find needs a fresh location. Try again.');

type RpcError = { readonly message?: string; readonly code?: string } | null;

function failure(fn: string, error: NonNullable<RpcError>): Error {
  if (error.code === 'P0001') {
    switch (error.message) {
      case 'not_found':
        return notFound();
      case 'location_required':
        return locationRequired();
      case 'invalid_input':
        return badRequest();
    }
  }
  return new DatabaseError(`${fn} failed`);
}

/** `get_match`: one match from this person's side, after applying timeouts. */
export async function getMatchRow(db: Db, userId: string, matchId: string): Promise<DbMatch> {
  const { data, error } = await db.rpc('get_match', { p_user_id: userId, p_match_id: matchId });
  if (error) throw failure('get_match', error);
  return parseResult(zDbMatch, data, 'get_match');
}

/** `set_choice`: saves Find or Chat and says what happens next. */
export async function setChoiceRow(
  db: Db,
  userId: string,
  matchId: string,
  choice: MatchChoice,
): Promise<DbChoice> {
  const { data, error } = await db.rpc('set_choice', {
    p_user_id: userId,
    p_match_id: matchId,
    p_choice: choice,
  });
  if (error) throw failure('set_choice', error);
  return parseResult(zDbChoice, data, 'set_choice');
}

/** `start_glow`: starts the glow, opens the chat, or says why it waits. Never raises for those. */
export async function startGlowRow(
  db: Db,
  matchId: string,
  codeWords: readonly string[],
): Promise<DbStartGlow> {
  const { data, error } = await db.rpc('start_glow', {
    p_match_id: matchId,
    p_code_words: [...codeWords],
  });
  if (error) throw failure('start_glow', error);
  return parseResult(zDbStartGlow, data, 'start_glow');
}
