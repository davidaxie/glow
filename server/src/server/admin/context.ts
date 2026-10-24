/**
 * What the admin module depends on: the data, the events and the clock. Tests swap these
 * with `setAdminDepsForTests`; everything else calls `deps()`.
 */
import { pendingEvents, type AdminEvents } from './notify';
import type { AdminRepo } from './repo';
import { supabaseRepo } from './supabase-repo';

export type AdminDeps = {
  readonly repo: AdminRepo;
  readonly events: AdminEvents;
  readonly now: () => number;
};

let live: AdminDeps | undefined;
let override: AdminDeps | undefined;

export function deps(): AdminDeps {
  if (override) return override;
  live ??= { repo: supabaseRepo(), events: pendingEvents, now: () => Date.now() };
  return live;
}

export function setAdminDepsForTests(next: AdminDeps | undefined): void {
  override = next;
}
