import { describe, expect, it, vi } from 'vitest';
import { REDACTED, isSensitiveField, logger, redact } from '@/server/log';

describe('logger', () => {
  it('redacts coordinates and personal data under any spelling (P2)', () => {
    for (const key of [
      'lat',
      'lng',
      'latitude',
      'userLongitude',
      'coords',
      'location',
      'accuracy',
      'firstName',
      'first_name',
      'email',
      'messageBody',
      'text',
      'accessToken',
      'authorization',
      'photo',
      'ip',
    ]) {
      expect(isSensitiveField(key), key).toBe(true);
    }
  });

  it('keeps IDs, counts and outcomes', () => {
    expect(redact({ roomId: 'r1', matchId: 'm1', passed: true, status: 200, ms: 12 })).toEqual({
      roomId: 'r1',
      matchId: 'm1',
      passed: true,
      status: 200,
      ms: 12,
    });
  });

  it('writes one JSON line without the sensitive values', () => {
    const lines: string[] = [];
    vi.spyOn(console, 'log').mockImplementation((line: string) => lines.push(line));
    logger.info('room.join', { roomId: 'r1', lat: 37.7749, lng: -122.4194, passed: false });
    expect(lines).toHaveLength(1);
    const entry = JSON.parse(lines[0]!) as Record<string, unknown>;
    expect(entry).toMatchObject({ event: 'room.join', level: 'info', roomId: 'r1', passed: false });
    expect(entry.lat).toBe(REDACTED);
    expect(lines[0]).not.toContain('37.7749');
    expect(lines[0]).not.toContain('122.4194');
  });

  it('cannot be tricked into overwriting the event name', () => {
    const lines: string[] = [];
    vi.spyOn(console, 'log').mockImplementation((line: string) => lines.push(line));
    logger.info('real.event', { event: 'fake', level: 'error' });
    expect(JSON.parse(lines[0]!)).toMatchObject({ event: 'real.event', level: 'info' });
  });
});
