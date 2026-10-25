/**
 * Owner: X1. The Blind drop clock, ported from Double Blind (web/app/api/drop/_lib/schedule.ts).
 * The nightly drop is at 8pm America/Los_Angeles (the Cal Hacks venue). Outside demo mode,
 * `POST /api/blind/drop` works from then until midnight there; before, 409 drop_not_ready.
 * BLIND_DEMO_MODE (stage only) opens drops at any time.
 */
export const DROP_HOUR = 20;
export const DROP_TZ = 'America/Los_Angeles';

type Parts = {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
  second: number;
};

function partsIn(tz: string, at: Date): Parts {
  const fmt = new Intl.DateTimeFormat('en-US', {
    timeZone: tz,
    hourCycle: 'h23',
    year: 'numeric',
    month: 'numeric',
    day: 'numeric',
    hour: 'numeric',
    minute: 'numeric',
    second: 'numeric',
  });
  const out: Record<string, number> = {};
  for (const p of fmt.formatToParts(at)) if (p.type !== 'literal') out[p.type] = Number(p.value);
  return {
    year: out.year ?? 1970,
    month: out.month ?? 1,
    day: out.day ?? 1,
    hour: out.hour ?? 0,
    minute: out.minute ?? 0,
    second: out.second ?? 0,
  };
}

/** The instant the wall clock in `tz` reads y-m-d hour:00 (DST-safe). */
function zonedTime(tz: string, y: number, m: number, d: number, hour: number): Date {
  const wall = Date.UTC(y, m - 1, d, hour, 0, 0);
  let guess = wall;
  for (let i = 0; i < 2; i++) {
    const p = partsIn(tz, new Date(guess));
    guess += wall - Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute, p.second);
  }
  return new Date(guess);
}

export function todaysDrop(now: Date): Date {
  const p = partsIn(DROP_TZ, now);
  return zonedTime(DROP_TZ, p.year, p.month, p.day, DROP_HOUR);
}

export function nextDropAt(now: Date): Date {
  const today = todaysDrop(now);
  if (today.getTime() > now.getTime()) return today;
  const p = partsIn(DROP_TZ, now);
  const t = new Date(Date.UTC(p.year, p.month - 1, p.day + 1));
  return zonedTime(DROP_TZ, t.getUTCFullYear(), t.getUTCMonth() + 1, t.getUTCDate(), DROP_HOUR);
}

export function inDropWindow(now: Date): boolean {
  return partsIn(DROP_TZ, now).hour >= DROP_HOUR;
}

export function dropGate(now: Date, demo: boolean) {
  return { ready: demo || inDropWindow(now), demo, nextDropAt: nextDropAt(now).toISOString() };
}
