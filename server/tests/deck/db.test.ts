/**
 * Owner: B4. Database error mapping (docs/CONTRACTS.md, "Database errors").
 */
import { describe, expect, it, vi } from 'vitest';
import { HttpError } from '@/server/http';
import { DatabaseError, mapDbError, rpc, serviceDb } from '@/server/deck/db';

function captureConsole() {
  const lines: string[] = [];
  const grab = (...args: unknown[]) => lines.push(args.map(String).join(' '));
  vi.spyOn(console, 'log').mockImplementation(grab);
  vi.spyOn(console, 'warn').mockImplementation(grab);
  vi.spyOn(console, 'error').mockImplementation(grab);
  return lines;
}

describe('mapDbError', () => {
  it.each([
    ['not_found', 404, 'not_found'],
    ['invalid_input', 400, 'bad_request'],
    ['tap_limit_reached', 409, 'tap_limit_reached'],
    ['room_not_live', 409, 'room_not_live'],
    ['onboarding_incomplete', 409, 'onboarding_incomplete'],
  ])('P0001 %s is %i %s', (message, status, code) => {
    const error = mapDbError('record_tap', { code: 'P0001', message });
    expect(error).toBeInstanceOf(HttpError);
    expect((error as HttpError).status).toBe(status);
    expect((error as HttpError).code).toBe(code);
  });

  it('a database the API cannot reach is 503, so the app retries', () => {
    captureConsole();
    for (const code of ['PGRST000', 'PGRST001', 'PGRST002', 'PGRST003', '57014']) {
      expect((mapDbError('get_deck', { code }) as HttpError).status).toBe(503);
    }
  });

  it('anything else is a 500, logged by function and code only (never the message)', () => {
    const lines = captureConsole();
    const error = mapDbError('get_deck', { code: '42883', message: 'secret detail 37.80,-122.45' });
    expect(error).toBeInstanceOf(DatabaseError);
    expect(lines.join('\n')).toContain('"fn":"get_deck"');
    expect(lines.join('\n')).not.toContain('secret detail');
  });
});

describe('rpc', () => {
  it('a fetch failure (status 0) is 503', async () => {
    captureConsole();
    const client = serviceDb();
    vi.spyOn(client, 'rpc').mockResolvedValue({
      data: null,
      error: { code: '', message: 'TypeError: fetch failed', details: '', hint: '' },
      status: 0,
      statusText: '',
      count: null,
    } as never);
    await expect(rpc('list_matches', { p_user_id: 'x' })).rejects.toMatchObject({ status: 503 });
  });

  it('returns the data on success', async () => {
    const client = serviceDb();
    vi.spyOn(client, 'rpc').mockResolvedValue({
      data: { matches: [] },
      error: null,
      status: 200,
      statusText: 'OK',
      count: null,
    } as never);
    await expect(rpc('list_matches', { p_user_id: 'x' })).resolves.toEqual({ matches: [] });
  });
});
