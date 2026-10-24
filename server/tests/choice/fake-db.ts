/**
 * A tiny stand-in for the supabase-js calls C2's routes make: `rpc()`,
 * `from().select().eq().maybeSingle()` and `from().insert().select().single()`.
 * It records every call, so tests can check exactly what reached the database.
 */
import { randomUUID } from 'node:crypto';
import type { Db } from '@/server/choice/db';

type Row = Record<string, unknown>;
export type Result = { data: unknown; error: { message: string; code?: string } | null };

export class FakeDb {
  readonly tables: Record<string, Row[]> = {};
  readonly inserts: { table: string; values: Row }[] = [];
  readonly reads: string[] = [];
  readonly rpcCalls: { name: string; args: Row }[] = [];
  rpcHandler: (name: string, args: Row) => Result = () => ({ data: null, error: null });

  constructor(seed: Record<string, Row[]> = {}) {
    for (const [table, rows] of Object.entries(seed))
      this.tables[table] = rows.map((r) => ({ ...r }));
  }

  from(table: string) {
    return new Query(this, table);
  }

  rpc(name: string, args: Row): Promise<Result> {
    this.rpcCalls.push({ name, args });
    return Promise.resolve(this.rpcHandler(name, args));
  }

  asDb(): Db {
    return this as unknown as Db;
  }
}

/** An expected database error, the way Postgres raises them (P0001 with the code). */
export const raise = (code: string): Result => ({
  data: null,
  error: { message: code, code: 'P0001' },
});

class Query {
  private kind: 'select' | 'insert' = 'select';
  private values: Row = {};
  private readonly filters: [string, unknown][] = [];

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

  eq(column: string, value: unknown) {
    this.filters.push([column, value]);
    return this;
  }

  private matching(): Row[] {
    return (this.db.tables[this.table] ?? []).filter((row) =>
      this.filters.every(([column, value]) => row[column] === value),
    );
  }

  maybeSingle(): Promise<Result> {
    this.db.reads.push(this.table);
    return Promise.resolve({ data: this.matching()[0] ?? null, error: null });
  }

  single(): Promise<Result> {
    if (this.kind === 'insert') {
      const row = { id: randomUUID(), ...this.values };
      this.db.inserts.push({ table: this.table, values: this.values });
      (this.db.tables[this.table] ??= []).push(row);
      return Promise.resolve({ data: row, error: null });
    }
    this.db.reads.push(this.table);
    const row = this.matching()[0];
    return Promise.resolve(
      row ? { data: row, error: null } : { data: null, error: { message: 'no rows' } },
    );
  }
}
