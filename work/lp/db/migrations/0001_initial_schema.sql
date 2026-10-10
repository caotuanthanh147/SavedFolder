-- M2 Database migration 0001: initial schema (doc.md section 6, verbatim
-- columns/constraints/defaults) with SQLite STRICT table option.
-- STRICT enforces the declared TEXT/INTEGER types (SQLite 3.37.0+; D1
-- supports it and recommends it). Foreign keys are enforced by D1 on every
-- query and migration (PRAGMA foreign_keys = on equivalent).

CREATE TABLE projects (
  id            TEXT PRIMARY KEY,
  name          TEXT NOT NULL,
  slug          TEXT NOT NULL UNIQUE,
  owner_id      TEXT NOT NULL,
  signing_key_id TEXT NOT NULL,
  created_at    INTEGER NOT NULL
) STRICT;

CREATE TABLE scripts (
  id            TEXT PRIMARY KEY,
  project_id    TEXT NOT NULL REFERENCES projects(id),
  name          TEXT NOT NULL,
  keyless       INTEGER NOT NULL DEFAULT 0,
  active_version INTEGER NOT NULL,
  created_at    INTEGER NOT NULL
) STRICT;

CREATE TABLE script_games (
  script_id     TEXT NOT NULL REFERENCES scripts(id),
  game_id       INTEGER NOT NULL,
  PRIMARY KEY (script_id, game_id)
) STRICT;

CREATE TABLE script_versions (
  script_id     TEXT NOT NULL REFERENCES scripts(id),
  version       INTEGER NOT NULL,
  blob_ref      TEXT NOT NULL,
  build_hash    TEXT NOT NULL,
  init_build    TEXT NOT NULL,
  notes         TEXT,
  created_at    INTEGER NOT NULL,
  PRIMARY KEY (script_id, version)
) STRICT;

CREATE TABLE keys (
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
) STRICT;

CREATE TABLE key_scripts (
  key_id        TEXT NOT NULL REFERENCES keys(id),
  script_id     TEXT NOT NULL REFERENCES scripts(id),
  PRIMARY KEY (key_id, script_id)
) STRICT;

CREATE TABLE sessions (
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
) STRICT;

CREATE TABLE blacklist (
  id            TEXT PRIMARY KEY,
  kind          TEXT NOT NULL,
  value_hash    TEXT NOT NULL,
  reason        TEXT,
  created_by    TEXT NOT NULL,
  created_at    INTEGER NOT NULL
) STRICT;

CREATE TABLE nodes (
  id            TEXT PRIMARY KEY,
  hostname      TEXT NOT NULL UNIQUE,
  region        TEXT,
  active        INTEGER NOT NULL DEFAULT 1
) STRICT;

CREATE TABLE protocol_versions (
  version       TEXT PRIMARY KEY,
  handler       TEXT NOT NULL,
  min_loader    TEXT,
  active        INTEGER NOT NULL DEFAULT 1
) STRICT;

CREATE TABLE checkpoints (
  id            TEXT PRIMARY KEY,
  project_id    TEXT NOT NULL,
  position      INTEGER NOT NULL,
  provider      TEXT NOT NULL,
  config        TEXT NOT NULL
) STRICT;

CREATE TABLE free_attempts (
  id            TEXT PRIMARY KEY,
  project_id    TEXT NOT NULL,
  fingerprint   TEXT NOT NULL,
  step          INTEGER NOT NULL,
  token_hash    TEXT NOT NULL,
  started_at    INTEGER NOT NULL,
  step_started_at INTEGER NOT NULL,
  completed_at  INTEGER
) STRICT;

CREATE TABLE admins (
  id            TEXT PRIMARY KEY,
  discord_id    TEXT,
  role          TEXT NOT NULL,
  api_token_hash TEXT,
  quota_keys    INTEGER,
  created_at    INTEGER NOT NULL
) STRICT;

CREATE TABLE audit_log (
  id            TEXT PRIMARY KEY,
  actor_id      TEXT NOT NULL,
  action        TEXT NOT NULL,
  target        TEXT,
  detail        TEXT,
  created_at    INTEGER NOT NULL
) STRICT;

CREATE TABLE events (
  id            TEXT PRIMARY KEY,
  key_id        TEXT,
  type          TEXT NOT NULL,
  detail        TEXT,
  created_at    INTEGER NOT NULL
) STRICT;
