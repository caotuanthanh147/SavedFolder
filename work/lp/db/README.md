# M2 — Database (migrations, indexes, seed, backup notes)

Implements doc.md section 6. Research log with primary sources:
[RESEARCH-M2.md](./RESEARCH-M2.md) (written before any code, per doc.md rules).

**D3 decision: Cloudflare D1** (SQLite). Native Workers binding, `db.batch()`
gives SQL-transaction atomicity with rollback, Time Travel gives always-on
30-day point-in-time recovery at no cost, and `wrangler d1 migrations` is the
built-in migration tool. Postgres remains the documented fallback if write
volume outgrows a single SQLite writer. Full reasoning and sources:
RESEARCH-M2.md, "Options compared".

## Layout

```
db/
  RESEARCH-M2.md           research log (read first)
  migrations/
    0001_initial_schema.sql   all 15 doc.md 6 tables, columns verbatim, STRICT
    0002_indexes.sql          the documented index list
  seed/
    seed.ts                   config-driven idempotent bootstrap (nodes,
                              protocol_versions, first owner admin)
  tests/
    run_tests.py              26 checks, python3 stdlib + bun for the seed
```

## Applying migrations (remote D1)

Standard wrangler flow (see RESEARCH-M2.md sources for the exact docs):

```sh
# in the Worker project that binds the D1 database (api/):
npx wrangler d1 migrations apply <DATABASE_NAME> --remote
```

wrangler config (already conventional for the api/ module):

```jsonc
{
  "d1_databases": [
    {
      "binding": "DB",
      "database_name": "<DATABASE_NAME>",
      "database_id": "<UUID>",
      "migrations_dir": "../db/migrations"
    }
  ]
}
```

`migrations_dir` points at this folder; applied migrations are recorded in the
`d1_migrations` table wrangler creates. Use `database_name` (not the binding)
on the command line so the wrong binding can never be targeted.

After applying 0002, run `PRAGMA optimize;` once via
`wrangler d1 execute <DATABASE_NAME> --remote --command "PRAGMA optimize;"`
(collects planner statistics — D1 best practice, source in RESEARCH-M2.md).

## Seeding

The seed is configuration-driven; nothing is hardcoded. It inserts:

- `nodes` — from `LP_SEED_NODES` (comma-separated hostnames; optional
  `LP_SEED_NODE_REGIONS`), upserted by hostname
- `protocol_versions` — from `LP_SEED_PROTO_VERSION` + `LP_SEED_PROTO_HANDLER`
  (set together), optional `LP_SEED_PROTO_MIN_LOADER`, `LP_SEED_PROTO_ACTIVE`
  (default 1), upserted by version
- `admins` — one `owner` row, only if no owner exists; a 32-byte base64url
  bearer token is generated, printed to stderr exactly once, and stored only
  as its SHA-256 hex hash

```sh
LP_SEED_NODES=auth-a.example.com,auth-b.example.com \
LP_SEED_NODE_REGIONS=eu,us \
LP_SEED_PROTO_VERSION=1 LP_SEED_PROTO_HANDLER=default LP_SEED_PROTO_MIN_LOADER=1.0.0 \
LP_SEED_ADMIN_DISCORD_ID=<your discord id> \
bun db/seed/seed.ts --print > /tmp/seed.sql

npx wrangler d1 execute <DATABASE_NAME> --remote --file /tmp/seed.sql
```

Local development against a SQLite file (migrations applied first):

```sh
bun db/seed/seed.ts --local dev.db
```

`--print` with no `LP_SEED_*` variables emits only the owner bootstrap
statement — safe to re-run at any time (idempotent).

## Tests

```sh
python3 db/tests/run_tests.py
```

26 checks: schema (15 tables, verbatim columns, STRICT on every table),
indexes (all documented indexes + EXPLAIN QUERY PLAN index usage for every
doc.md 6 access pattern, including `key_hash` via the UNIQUE implicit index),
constraints (UNIQUE, foreign keys, NOT NULL defaults, STRICT violations),
seed (values, idempotency, config upsert, owner token hashing), batch-style
transaction atomicity, and the auth-init join pattern from doc.md 8 step 7.
Local SQLite runs with `PRAGMA foreign_keys = on` to mirror D1's default
foreign-key enforcement.

## Backup and restore

Primary source: Cloudflare D1 Time Travel docs (URL in RESEARCH-M2.md).

1. **Point-in-time recovery (Time Travel).** Always on, no configuration.
   Restore to any minute in the last 30 days (Workers Paid; 7 days on Free):
   ```sh
   npx wrangler d1 time_travel restore <DATABASE_NAME> --timestamp <unix-seconds>
   ```
   A restore can itself be undone (a second restore back to a bookmark after
   the first one). Rate limit: 10 restores per 10 minutes per database.
2. **Bookmarks before risky operations.** Before applying a migration to
   production, record a bookmark so the pre-migration state is addressable:
   ```sh
   npx wrangler d1 time_travel bookmark <DATABASE_NAME>
   ```
3. **Off-platform copy (R2 export).** Time Travel's Workflows-based export
   writes a SQL dump to R2 for retention beyond 30 days or restores outside
   Cloudflare. Schedule per doc.md 19 (daily backups with retention).
4. **Restore drill (doc.md 18 "tested restores").** Quarterly, in staging:
   restore a production bookmark into a scratch database, run
   `python3 db/tests/run_tests.py` against a local copy, and record the
   result in the audit log. A backup that has never been restored is not a
   backup.

## Integration notes (for M1 API core)

- **Atomic multi-statement writes**: use `env.DB.batch([...])` — batched
  statements are SQL transactions; a failed statement aborts/rolls back the
  whole sequence (source in RESEARCH-M2.md). This is the primitive for the
  HWID-bind race (doc.md 22) — do the read-then-conditional-write inside one
  batch.
- **Foreign keys are enforced by D1 on every query and migration** (default
  on). Insert parents before children, or use `PRAGMA defer_foreign_keys = on`
  at the start of a transaction that must violate ordering temporarily.
- **STRICT tables**: every table is STRICT. D1's write conversion (Number →
  INTEGER/REAL, String → TEXT, Boolean → 0/1) matches the declared types.
  Be aware: integer values passed to TEXT columns are accepted and stringified;
  non-numeric strings into INTEGER columns are errors, not silent NULLs.
- **Bound parameters**: max 100 per query — chunk bulk DML (e.g. blacklist
  imports, bulk key inserts) into batches of ≤ 100 parameter sets per
  statement, multiple statements per `batch()` call.
- **Row size**: max 2 MB per row; `events.detail` / `audit_log.detail` should
  stay well under it (log references, not payloads).
- **`keys.key_hash` is indexed** through its UNIQUE constraint (implicit
  `sqlite_autoindex`); there is deliberately no second index on it.

## Contract notes (owner rulings 2026-10-10 — msgs/docowner.txt)

- `sessions.key_id REFERENCES keys(id)` (nullable, keyless scripts) and
  `sessions.script_id REFERENCES scripts(id)`, both **ON DELETE RESTRICT**
  (owner Q3): never hard-DELETE keys/scripts that have sessions — revoke or
  deactivate instead.
- `events.key_id` stays WITHOUT a foreign key (owner Q3): failed validations
  may reference non-existent keys; audit history outlives deletions.
- `checkpoints.project_id` and `free_attempts.project_id` now
  **REFERENCES projects(id) ON DELETE CASCADE** (owner Q4; "the doc follows
  the migrations" — the doc's §6 gap was an owner-acknowledged oversight).
- Admin tokens (owner Q2, seed output): format `adm_<admin id>.<secret>`
  with a 32-byte base64url secret. **Only SHA-256(secret) is stored.**
  Runtime auth: parse the id prefix → one lookup → constant-time compare of
  the secret hash (M1).
- Protocol row (owner Q1): version `1`, handler `v1`, min_loader `1.0.0`,
  active — seed defaults, env-overridable. Raise min_loader only when
  retiring old loaders.
- The doc index list entry `keys(key_hash)` is satisfied by the UNIQUE
  constraint's implicit index; no duplicate index is created (no unnecessary
  code). Tests assert index usage for that lookup.
- Decision Log for all of the above (doc v4 format): DECISIONS-M2.md.
