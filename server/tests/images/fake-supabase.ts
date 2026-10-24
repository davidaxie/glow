import { vi } from 'vitest';

type Result<T> = {
  data: T | null;
  error: { code?: string; message?: string; status?: number } | null;
};

/**
 * An in-memory stand-in for the service-role client the image routes use: two private buckets,
 * the `checkins` and `profiles` rows they read, and the database functions they call. Every
 * call is recorded so tests can check what was (and wasn't) touched.
 */
export function fakeSupabase() {
  const buckets = new Map<string, Map<string, Uint8Array>>([
    ['room-cards', new Map()],
    ['profile-photos', new Map()],
  ]);
  const tables: Record<string, Record<string, Record<string, unknown>>> = {
    checkins: {},
    profiles: {},
  };
  const rpcHandlers: Record<string, (args: Record<string, unknown>) => Result<unknown>> = {};

  const rpc = vi.fn(async (name: string, args: Record<string, unknown>) => {
    const handler = rpcHandlers[name];
    if (!handler) return { data: null, error: { code: 'PGRST202', message: 'no such function' } };
    return handler(args);
  });

  const from = vi.fn((table: string) => ({
    select: (_columns: string) => ({
      eq: (column: string, value: string) => ({
        maybeSingle: async (): Promise<Result<Record<string, unknown>>> => {
          if (column !== 'id') throw new Error('fake only filters by id');
          return { data: tables[table]?.[value] ?? null, error: null };
        },
      }),
    }),
  }));

  const storageFrom = vi.fn((bucket: string) => {
    const objects = buckets.get(bucket);
    if (!objects) throw new Error(`no bucket ${bucket}`);
    return {
      upload: vi.fn(async (path: string, body: Uint8Array, _options?: unknown) => {
        if (objects.has(path)) return { data: null, error: { message: 'exists', status: 409 } };
        objects.set(path, new Uint8Array(body));
        return { data: { path }, error: null };
      }),
      download: vi.fn(async (path: string) => {
        const bytes = objects.get(path);
        if (!bytes) return { data: null, error: { message: 'Object not found', status: 400 } };
        return { data: new Blob([bytes as Uint8Array<ArrayBuffer>]), error: null };
      }),
      remove: vi.fn(async (paths: string[]) => {
        for (const path of paths) objects.delete(path);
        return { data: [], error: null };
      }),
    };
  });

  return {
    client: { rpc, from, storage: { from: storageFrom } },
    rpc,
    from,
    storageFrom,
    buckets,
    tables,
    onRpc(name: string, handler: (args: Record<string, unknown>) => Result<unknown>) {
      rpcHandlers[name] = handler;
    },
  };
}

export type FakeSupabase = ReturnType<typeof fakeSupabase>;

/** A database function failing the way ours do: P0001 with the code as the message. */
export const dbError = (code: string) => ({ data: null, error: { code: 'P0001', message: code } });
