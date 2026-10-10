-- M2 Database migration 0002: indexes for the doc.md section 6 access patterns.
-- Naming follows the D1 best-practice convention idx_<table>_<columns>.
-- Run PRAGMA optimize after applying (D1 best practices) — see README.

-- keys(key_hash) from the doc index list is satisfied by the UNIQUE
-- constraint on keys.key_hash: SQLite automatically creates a unique index
-- for every UNIQUE column (sqlite_autoindex_*). A second index on the same
-- column would add write cost with no read benefit, so it is not created.
-- tests/run_tests.py asserts index usage for key_hash lookups via
-- EXPLAIN QUERY PLAN.

CREATE INDEX IF NOT EXISTS idx_keys_discord_id ON keys(discord_id);

CREATE INDEX IF NOT EXISTS idx_sessions_key_id_created_at ON sessions(key_id, created_at);

CREATE INDEX IF NOT EXISTS idx_events_key_id_created_at ON events(key_id, created_at);

CREATE INDEX IF NOT EXISTS idx_blacklist_kind_value_hash ON blacklist(kind, value_hash);

CREATE INDEX IF NOT EXISTS idx_script_games_game_id ON script_games(game_id);
