// SQLite handle for the dashboard's in-process deployment of the real api/
// router (module M11 dev harness). Node's built-in node:sqlite (DatabaseSync,
// Node >= 22.5) provides the raw {run, query} shape that api/src/db.ts
// SqliteAdapter expects. `next dev` runs on Node; the api/ test suite covers
// the bun:sqlite path separately against the same adapter.

import { DatabaseSync } from "node:sqlite";

interface SqliteStatement {
  run: (...params: unknown[]) => { changes: number | bigint; lastInsertRowid: number | bigint };
  all: (...params: unknown[]) => unknown[];
}

interface SqliteDatabase {
  exec: (sql: string) => void;
  prepare: (sql: string) => SqliteStatement;
}

export interface RawSqlite {
  run: (sql: string, params: unknown[]) => { changes: number; lastInsertRowid: number | bigint };
  query: (sql: string, params: unknown[]) => unknown[];
  exec: (sql: string) => void;
}

export function openRawSqlite(path: string): RawSqlite {
  const db = new DatabaseSync(path) as unknown as SqliteDatabase;
  return {
    run: (sql, params) => {
      const r = db.prepare(sql).run(...params);
      return { changes: Number(r.changes), lastInsertRowid: r.lastInsertRowid };
    },
    query: (sql, params) => db.prepare(sql).all(...params),
    exec: (sql) => db.exec(sql),
  };
}
