/**
 * Everything C2 takes from other owners' modules, in one place. Owner: C2.
 *
 * Until those modules merge, these are C2's stand-ins with the same signatures. When one
 * merges, only the line below changes. Tests replace this module with `vi.mock`.
 */
export { checkFix, notify, rateLimit, recordLocationCheck, type UserEvent } from './stand-ins';
