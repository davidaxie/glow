/**
 * Rate limit policies. One per kind of action, each a sliding window per person (or per
 * client IP for routes without sign-in). These are burst limits that stop scripts and
 * floods; the product caps (3 taps per room per day, 50 card views) live in the database.
 */

export type RateLimitPolicyName =
  | 'signIn'
  | 'join'
  | 'checkin'
  | 'deck'
  | 'taps'
  | 'messages'
  | 'reports'
  | 'blocks'
  | 'capture'
  | 'photos'
  | 'account'
  | 'admin'
  | 'api';

export type RateLimitPolicy = {
  /** Requests allowed in each window. */
  readonly limit: number;
  readonly windowSeconds: number;
  readonly use: string;
};

export const RATE_LIMIT_POLICIES = {
  signIn: {
    limit: 10,
    windowSeconds: 600,
    use: 'Server-side sign-in steps (test sign-in), per IP',
  },
  join: { limit: 20, windowSeconds: 600, use: 'Resolving, joining and leaving rooms' },
  checkin: { limit: 10, windowSeconds: 600, use: 'Card photo uploads (each one is moderated)' },
  deck: { limit: 60, windowSeconds: 60, use: 'Deck pages' },
  taps: { limit: 20, windowSeconds: 60, use: 'Taps (the daily cap is separate, in the database)' },
  messages: { limit: 30, windowSeconds: 60, use: 'Sending chat messages' },
  reports: { limit: 10, windowSeconds: 3600, use: 'Reports' },
  blocks: { limit: 60, windowSeconds: 3600, use: 'Blocks' },
  capture: { limit: 60, windowSeconds: 3600, use: 'Screenshot and recording logs' },
  photos: { limit: 20, windowSeconds: 600, use: 'Profile photo uploads and removals' },
  account: { limit: 30, windowSeconds: 600, use: 'Profile edits, pause, devices, delete account' },
  admin: { limit: 300, windowSeconds: 60, use: 'Admin web and API' },
  api: { limit: 300, windowSeconds: 60, use: 'Everything else, mostly reads' },
} as const satisfies Record<RateLimitPolicyName, RateLimitPolicy>;

/** Which policy each contract operation uses. Anything not listed uses `api`. */
const OPERATION_POLICIES: Readonly<Record<string, RateLimitPolicyName | null>> = {
  testLogin: 'signIn',
  updateProfile: 'account',
  setPaused: 'account',
  deleteAccount: 'account',
  registerDevice: 'account',
  deleteDevice: 'account',
  addProfilePhoto: 'photos',
  deleteProfilePhoto: 'photos',
  resolveRoom: 'join',
  joinRoom: 'join',
  leaveRoom: 'join',
  createCheckin: 'checkin',
  getDeck: 'deck',
  createTap: 'taps',
  sendMessage: 'messages',
  createReport: 'reports',
  createBlock: 'blocks',
  logCapture: 'capture',
  // The cron secret protects purge; an outside scheduler must never be throttled.
  runPurge: null,
};

/** The policy for an operation, or null for none. */
export function policyForOperation(operationId: string): RateLimitPolicyName | null {
  if (operationId in OPERATION_POLICIES) return OPERATION_POLICIES[operationId] ?? null;
  if (operationId.startsWith('admin')) return 'admin';
  return 'api';
}
