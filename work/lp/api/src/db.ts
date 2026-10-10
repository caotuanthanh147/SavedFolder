export interface DbResult {
  changes: number;
}

export interface DbAdapter {
  run(sql: string, params: unknown[]): Promise<DbResult>;
  first<T>(sql: string, params: unknown[]): Promise<T | null>;  
  all<T>(sql: string, params: unknown[]): Promise<T[]>;
  batch(statements: { sql: string; params: unknown[] }[]): Promise<DbResult[]>;
}

export interface D1PreparedStatement {
  bind: (...values: unknown[]) => D1PreparedStatement;
  first: <T>() => Promise<T | null>;
  all: <T>() => Promise<{ results: T[] }>;
  run: () => Promise<unknown>;
}

export interface D1Like {
  prepare: (sql: string) => D1PreparedStatement;
  batch: (statements: D1PreparedStatement[]) => Promise<unknown[]>;
}

export class SqliteAdapter implements DbAdapter {
  constructor(
    private readonly db: {
      run: (sql: string, params: unknown[]) => { changes: number; lastInsertRowid: number | bigint };
      query: (sql: string, params: unknown[]) => unknown[];
    },
  ) {}

  run(sql: string, params: unknown[]): Promise<DbResult> {
    return Promise.resolve({ changes: Number(this.db.run(sql, params).changes) });
  }

  first<T>(sql: string, params: unknown[]): Promise<T | null> {
    const rows = this.db.query(sql, params) as T[];
    return Promise.resolve(rows.length > 0 ? rows[0] : null);
  }

  all<T>(sql: string, params: unknown[]): Promise<T[]> {
    return Promise.resolve(this.db.query(sql, params) as T[]);
  }

  batch(statements: { sql: string; params: unknown[] }[]): Promise<DbResult[]> {
    return Promise.all(statements.map((s) => this.run(s.sql, s.params)));
  }
}

export class D1Adapter implements DbAdapter {
  constructor(private readonly d1: D1Like) {}

  run(sql: string, params: unknown[]): Promise<DbResult> {
    return this.d1
      .prepare(sql)
      .bind(...params)
      .run()
      .then((r) => ({ changes: Number((r as { meta?: { changes?: number } }).meta?.changes ?? 0) }));
  }

  first<T>(sql: string, params: unknown[]): Promise<T | null> {
    return this.d1.prepare(sql).bind(...params).first<T>();
  }

  all<T>(sql: string, params: unknown[]): Promise<T[]> {
    return this.d1
      .prepare(sql)
      .bind(...params)
      .all<T>()
      .then((r) => (r as { results: T[] }).results ?? []);
  }

  batch(statements: { sql: string; params: unknown[] }[]): Promise<DbResult[]> {
    return this.d1
      .batch(statements.map((s) => this.d1.prepare(s.sql).bind(...s.params)))
      .then((rs) => rs.map((r) => ({ changes: Number((r as { meta?: { changes?: number } }).meta?.changes ?? 0) })));
  }
}

// doc.md §6 schema, verbatim, plus the §6 index list. M2 owns db/ migrations;
// this constant is the single source used by local tests and by the
// `api/scripts/init-d1.sql` bootstrap so the two can never drift silently.
export const DOC_SCHEMA_SQL = `
CREATE TABLE IF NOT EXISTS projects (
  id            TEXT PRIMARY KEY,
  name          TEXT NOT NULL,
  slug          TEXT NOT NULL UNIQUE,
  owner_id      TEXT NOT NULL,
  signing_key_id TEXT NOT NULL,
  created_at    INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS scripts (
  id            TEXT PRIMARY KEY,
  project_id    TEXT NOT NULL REFERENCES projects(id),
  name          TEXT NOT NULL,
  keyless       INTEGER NOT NULL DEFAULT 0,
  active_version INTEGER NOT NULL,
  created_at    INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS script_games (
  script_id     TEXT NOT NULL REFERENCES scripts(id),
  game_id       INTEGER NOT NULL,
  PRIMARY KEY (script_id, game_id)
);
CREATE TABLE IF NOT EXISTS script_versions (
  script_id     TEXT NOT NULL REFERENCES scripts(id),
  version       INTEGER NOT NULL,
  blob_ref      TEXT NOT NULL,
  build_hash    TEXT NOT NULL,
  init_build    TEXT NOT NULL,
  notes         TEXT,
  created_at    INTEGER NOT NULL,
  PRIMARY KEY (script_id, version)
);
CREATE TABLE IF NOT EXISTS keys (
  id            TEXT PRIMARY KEY,
  project_id    TEXT NOT NULL REFERENCES projects(id),
  key_hash      TEXT NOT NULL UNIQUE,
  tier          TEXT NOT NULL,
  status        TEXT NOT NULL,
  hwid_hash     TEXT,
  hwid_resets   INTEGER NOT NULL DEFAULT 0,
  last_reset_at INTEGER,
  discord_id    TEXT,
  roblox_user_id INTEGER,
  note          TEXT,
  total_executions INTEGER NOT NULL DEFAULT 0,
  created_by    TEXT NOT NULL,
  created_at    INTEGER NOT NULL,
  expires_at    INTEGER,
  first_used_at INTEGER,
  last_used_at  INTEGER
);
CREATE TABLE IF NOT EXISTS key_scripts (
  key_id        TEXT NOT NULL REFERENCES keys(id),
  script_id     TEXT NOT NULL REFERENCES scripts(id),
  PRIMARY KEY (key_id, script_id)
);
CREATE TABLE IF NOT EXISTS sessions (
  id            TEXT PRIMARY KEY,
  key_id        TEXT,
  script_id     TEXT NOT NULL,
  version       INTEGER NOT NULL,
  hwid_hash     TEXT NOT NULL,
  ip_hash       TEXT NOT NULL,
  roblox_user_id INTEGER,
  place_id      INTEGER,
  watermark_id  TEXT NOT NULL,
  created_at    INTEGER NOT NULL,
  expires_at    INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS blacklist (
  id            TEXT PRIMARY KEY,
  kind          TEXT NOT NULL,
  value_hash    TEXT NOT NULL,
  reason        TEXT,
  created_by    TEXT NOT NULL,
  created_at    INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS nodes (
  id            TEXT PRIMARY KEY,
  hostname      TEXT NOT NULL UNIQUE,
  region        TEXT,
  active        INTEGER NOT NULL DEFAULT 1
);
CREATE TABLE IF NOT EXISTS protocol_versions (
  version       TEXT PRIMARY KEY,
  handler       TEXT NOT NULL,
  min_loader    TEXT,
  active        INTEGER NOT NULL DEFAULT 1
);
CREATE TABLE IF NOT EXISTS checkpoints (
  id            TEXT PRIMARY KEY,
  project_id    TEXT NOT NULL,
  position      INTEGER NOT NULL,
  provider      TEXT NOT NULL,
  config        TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS free_attempts (
  id            TEXT PRIMARY KEY,
  project_id    TEXT NOT NULL,
  fingerprint   TEXT NOT NULL,
  step          INTEGER NOT NULL,
  token_hash    TEXT NOT NULL,
  started_at    INTEGER NOT NULL,
  step_started_at INTEGER NOT NULL,
  completed_at  INTEGER
);
CREATE TABLE IF NOT EXISTS admins (
  id            TEXT PRIMARY KEY,
  discord_id    TEXT,
  role          TEXT NOT NULL,
  api_token_hash TEXT,
  quota_keys    INTEGER,
  created_at    INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS audit_log (
  id            TEXT PRIMARY KEY,
  actor_id      TEXT NOT NULL,
  action        TEXT NOT NULL,
  target        TEXT,
  detail        TEXT,
  created_at    INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS events (
  id            TEXT PRIMARY KEY,
  key_id        TEXT,
  type          TEXT NOT NULL,
  detail        TEXT,
  created_at    INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_keys_key_hash ON keys(key_hash);
CREATE INDEX IF NOT EXISTS idx_keys_discord_id ON keys(discord_id);
CREATE INDEX IF NOT EXISTS idx_sessions_key_created ON sessions(key_id, created_at);
CREATE INDEX IF NOT EXISTS idx_events_key_created ON events(key_id, created_at);
CREATE INDEX IF NOT EXISTS idx_blacklist_kind_value ON blacklist(kind, value_hash);
CREATE INDEX IF NOT EXISTS idx_script_games_game ON script_games(game_id);
`;
