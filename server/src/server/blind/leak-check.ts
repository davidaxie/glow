/**
 * Owner: X1. The give-away warning, ported from Double Blind (web/lib/leak-check.ts), regex
 * first. Says whether a blind chat message looks like it reveals who the sender is, and why, in
 * words the app can show. The text is never logged.
 */
export type LeakResult =
  { readonly leak: false } | { readonly leak: true; readonly reason: string };

const RULES: readonly { readonly re: RegExp; readonly reason: string }[] = [
  {
    re: /\b(insta(gram)?|ig|snap(chat)?|tiktok|twitter|x\.com|linkedin|discord|telegram|whatsapp|venmo|github)\b/i,
    reason: 'This looks like a social handle.',
  },
  { re: /(^|\s)@[a-z0-9._]{2,}/i, reason: 'This looks like a social handle.' },
  { re: /[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}/i, reason: 'This looks like an email address.' },
  { re: /(\+?\d[\s().-]?){7,}/, reason: 'This looks like a phone number.' },
  {
    re: /\bhttps?:\/\/|\bwww\.|\b[a-z0-9-]+\.(com|io|dev|me|net|org|app)\b/i,
    reason: 'This looks like a link.',
  },
  {
    re: /\b(my name is|i'?m called|call me|it'?s me,?)\s+[a-z]/i,
    reason: 'This looks like it says your name.',
  },
  {
    re: /\b(table|booth|seat|row|room)\s*#?\s*\d+\b/i,
    reason: 'This looks like it says where you are.',
  },
];

/** `ownName` is the sender's own first name: saying it gives them away. */
export function checkLeak(text: string, ownName?: string | null): LeakResult {
  for (const rule of RULES) if (rule.re.test(text)) return { leak: true, reason: rule.reason };
  const name = ownName?.trim();
  if (name && name.length >= 2) {
    const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    if (new RegExp(`\\b${escaped}\\b`, 'i').test(text)) {
      return { leak: true, reason: 'This looks like it says your name.' };
    }
  }
  return { leak: false };
}
