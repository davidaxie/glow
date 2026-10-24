/**
 * The only logger server code should use. It writes one JSON line per event and
 * redacts any field whose name suggests personal data, so coordinates (P2), names,
 * message text, tokens and photos can't reach logs by accident.
 *
 *   logger.info('room.join', { roomId, passed: true });
 *
 * Log event names, IDs, counts and outcomes. Never log request bodies, coordinates,
 * names, emails, message text or image bytes, under any field name. The redaction
 * is a safety net, not permission.
 */

export type LogValue = string | number | boolean | null | undefined;
export type LogFields = Readonly<Record<string, LogValue>>;
export type LogLevel = 'debug' | 'info' | 'warn' | 'error';

/** If any word of a field name is in this list, the field's value is redacted. */
const SENSITIVE_WORDS = new Set([
  'lat',
  'lng',
  'lon',
  'long',
  'latitude',
  'longitude',
  'coord',
  'coords',
  'coordinate',
  'coordinates',
  'location',
  'geo',
  'accuracy',
  'altitude',
  'body',
  'text',
  'message',
  'content',
  'caption',
  'name',
  'firstname',
  'lastname',
  'email',
  'phone',
  'birthdate',
  'birthday',
  'dob',
  'token',
  'jwt',
  'authorization',
  'cookie',
  'password',
  'secret',
  'photo',
  'image',
  'bytes',
  'base64',
  'ip',
  'address',
]);

export const REDACTED = '[redacted]';

/** Splits `firstName`, `first_name` and `first-name` into words. */
function words(key: string): string[] {
  return key
    .replace(/([a-z0-9])([A-Z])/g, '$1_$2')
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .filter(Boolean);
}

export function isSensitiveField(key: string): boolean {
  const parts = words(key);
  return parts.some((w) => SENSITIVE_WORDS.has(w)) || SENSITIVE_WORDS.has(parts.join(''));
}

export function redact(fields: LogFields = {}): Record<string, LogValue> {
  const out: Record<string, LogValue> = {};
  for (const [key, value] of Object.entries(fields)) {
    out[key] = isSensitiveField(key) ? REDACTED : value;
  }
  return out;
}

function write(level: LogLevel, event: string, fields?: LogFields): void {
  const line = JSON.stringify({ ...redact(fields), level, event, at: new Date().toISOString() });
  if (level === 'error') console.error(line);
  else if (level === 'warn') console.warn(line);
  else console.log(line);
}

export const logger = {
  debug: (event: string, fields?: LogFields) => {
    if (process.env.NODE_ENV !== 'production') write('debug', event, fields);
  },
  info: (event: string, fields?: LogFields) => write('info', event, fields),
  warn: (event: string, fields?: LogFields) => write('warn', event, fields),
  error: (event: string, fields?: LogFields) => write('error', event, fields),
};
