// Owner: B7. Times in a room's own timezone, the way people at the venue read them.
export function formatTime(iso: string, timeZone: string): string {
  return new Intl.DateTimeFormat('en-US', {
    timeZone,
    weekday: 'short',
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  }).format(new Date(iso));
}

export function statusLabel(status: 'live' | 'paused' | 'ended'): string {
  return status === 'live' ? 'Live' : status === 'paused' ? 'Paused' : 'Ended';
}

/** "black top, short brown hair, glasses" */
export function describeTags(tags: {
  topColor: string;
  hairLength?: string;
  hairColor?: string;
  extras: readonly string[];
}): string[] {
  const hair = [tags.hairLength, tags.hairColor].filter(Boolean).join(' ');
  return [`${tags.topColor} top`, ...(hair ? [`${hair} hair`] : []), ...tags.extras];
}
