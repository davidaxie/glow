/**
 * A tiny in-memory stand-in for the supabase-js calls B2's routes make: enough of the
 * query builder (`from().select().eq().maybeSingle()`, `insert().select().single()`,
 * `update().eq().is().select()`), `rpc()` and `storage.from().remove()`.
 * It records every write, so tests can check exactly what reached the database.
 */
import { randomUUID } from 'node:crypto';
import type { Db } from '@/server/rooms/db';

type Row = Record<string, unknown>;
type Filter = { column: string; op: 'eq' | 'is'; value: unknown };
type Result = { data: unknown; error: { message: string } | null };

export type Write = { table: string; kind: 'insert' | 'update'; values: Row };

export class FakeDb {
  readonly tables: Record<string, Row[]> = {};
  readonly writes: Write[] = [];
  readonly removed: { bucket: string; paths: string[] }[] = [];
  readonly rpcCalls: { name: string; args: Row }[] = [];
  rpcHandler: (name: string, args: Row) => Result = () => ({ data: null, error: null });
  failInsertsInto = new Set<string>();

  constructor(seed: Record<string, Row[]> = {}) {
    for (const [table, rows] of Object.entries(seed))
      this.tables[table] = rows.map((r) => ({ ...r }));
  }

  rows(table: string): Row[] {
    return (this.tables[table] ??= []);
  }

  from(table: string) {
    return new Query(this, table);
  }

  rpc(name: string, args: Row): Promise<Result> {
    this.rpcCalls.push({ name, args });
    return Promise.resolve(this.rpcHandler(name, args));
  }

  readonly storage = {
    from: (bucket: string) => ({
      remove: (paths: string[]) => {
        this.removed.push({ bucket, paths });
        return Promise.resolve({ data: paths.map((name) => ({ name })), error: null });
      },
    }),
  };

  asDb(): Db {
    return this as unknown as Db;
  }
}

class Query implements PromiseLike<Result> {
  private kind: 'select' | 'insert' | 'update' = 'select';
  private values: Row = {};
  private readonly filters: Filter[] = [];

  constructor(
    private readonly db: FakeDb,
    private readonly table: string,
  ) {}

  select(_columns?: string) {
    return this;
  }

  insert(values: Row) {
    this.kind = 'insert';
    this.values = values;
    return this;
  }

  update(values: Row) {
    this.kind = 'update';
    this.values = values;
    return this;
  }

  eq(column: string, value: unknown) {
    this.filters.push({ column, op: 'eq', value });
    return this;
  }

  is(column: string, value: unknown) {
    this.filters.push({ column, op: 'is', value });
    return this;
  }

  maybeSingle(): Promise<Result> {
    const { data, error } = this.run();
    return Promise.resolve({ data: (data as Row[])[0] ?? null, error });
  }

  single(): Promise<Result> {
    const { data, error } = this.run();
    const first = (data as Row[])[0];
    return Promise.resolve(
      first ? { data: first, error } : { data: null, error: { message: 'no rows' } },
    );
  }

  then<A = Result, B = never>(
    onfulfilled?: ((value: Result) => A | PromiseLike<A>) | null,
    onrejected?: ((reason: unknown) => B | PromiseLike<B>) | null,
  ): PromiseLike<A | B> {
    return Promise.resolve(this.run()).then(onfulfilled, onrejected);
  }

  private matches(row: Row): boolean {
    return this.filters.every((f) =>
      f.op === 'is' ? (row[f.column] ?? null) === f.value : row[f.column] === f.value,
    );
  }

  private run(): Result {
    const rows = this.db.rows(this.table);
    if (this.kind === 'insert') {
      if (this.db.failInsertsInto.has(this.table))
        return { data: [], error: { message: 'refused' } };
      const row = { id: randomUUID(), created_at: new Date().toISOString(), ...this.values };
      rows.push(row);
      this.db.writes.push({ table: this.table, kind: 'insert', values: { ...this.values } });
      return { data: [row], error: null };
    }
    const hit = rows.filter((row) => this.matches(row));
    if (this.kind === 'update') {
      for (const row of hit) Object.assign(row, this.values);
      this.db.writes.push({ table: this.table, kind: 'update', values: { ...this.values } });
    }
    return { data: hit.map((row) => ({ ...row })), error: null };
  }
}

export const DEMO_ROOM_ID = 'de000000-0000-4000-8000-000000000001';
export const DEMO_CENTER = { latitude: 37.8029, longitude: -122.4484 };

/** The seeded demo room (supabase/seed.sql), live for the next day. Test data only. */
export function demoRoom(overrides: Row = {}): Row {
  const now = Date.now();
  return {
    id: DEMO_ROOM_ID,
    slug: 'demo',
    name: 'Glow demo room (test data)',
    code: 'HACK26',
    lat: DEMO_CENTER.latitude,
    lng: DEMO_CENTER.longitude,
    radius_m: 200,
    qr_secret: '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff',
    static_qr_token: 'DEMOSTATICTOKEN2',
    allow_static_qr: true,
    demo_mode: false,
    status: 'live',
    starts_at: new Date(now - 86_400_000).toISOString(),
    ends_at: new Date(now + 86_400_000).toISOString(),
    ...overrides,
  };
}

export function onboarded(userId: string, overrides: Row = {}): Row {
  return { id: userId, onboarding_step: 'complete', banned_at: null, ...overrides };
}
