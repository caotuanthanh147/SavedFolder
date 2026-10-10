# M2 Database — Research Log

Module: M2 "Database" (doc.md §7). Scope: migrations, indexes, seed data, backup notes.
Written BEFORE any code, per doc.md "Mandatory research". Research date: 2026-10-10.
Every URL below was opened and read during this session; key facts were taken from
the page content, not from memory.

## Sources

| Topic | Source URL | Version / date | Key finding | Used for |
|-------|-----------|----------------|-------------|----------|
| D1 limits | https://developers.cloudflare.com/d1/platform/limits/ | Last updated Apr 21, 2026 | Max DB size 10 GB (Paid) / 500 MB (Free); rows per table unlimited (storage-bound); max row/BLOB 2 MB; max SQL statement 100 KB; max 100 bound params/query; max query duration 30 s; Time Travel PITR 30 days (Paid) / 7 days (Free), 10 restores per 10 min per DB; 1000 queries per Worker invocation (Paid); per-statement limits apply inside `db.batch()` | D3 sizing, migration file size budget, batch usage |
| D1 migrations | https://developers.cloudflare.com/d1/reference/migrations/ | Last updated Jun 8, 2026 | `wrangler d1 migrations create/apply/list`; each migration is one `.sql` file with a version number in the filename, applied in sequential order; applied migrations recorded in the `d1_migrations` table; `migrations_dir`, `migrations_table`, `migrations_pattern` customizable in wrangler config; use `database_name` (not binding name) to avoid applying to the wrong binding | Migration file naming (NNNN_name.sql) + apply workflow |
| D1 Time Travel | https://developers.cloudflare.com/d1/reference/time-travel/ | Last updated Apr 21, 2026 | Time Travel = D1's backups + point-in-time recovery, always on, no extra cost; restore to any minute in the last 30 days; bookmarks are lexicographically sortable, derivable from Unix timestamps; restore can be undone; supports export to R2 via Workflows; requires `version: production` storage subsystem | Backup/restore plan (backup notes deliverable) |
| D1 batch semantics | https://developers.cloudflare.com/d1/worker-api/d1-database/ | Current (workers docs, opened via llms.txt markdown) | "Batched statements are SQL transactions. If a statement in the sequence fails, then an error is returned for that specific statement, and it aborts or rolls back the entire sequence." Statements execute sequentially, non-concurrently | Atomic multi-statement patterns for M1 (HWID bind race, doc §22) |
| D1 type handling | https://developers.cloudflare.com/d1/worker-api/ | Last updated Apr 21, 2026 | JS→D1 write conversion: Number→INTEGER (integral) or REAL, String→TEXT, Boolean→INTEGER 0/1, null→NULL; conversion is permanent/one-way; Cloudflare explicitly recommends STRICT tables to avoid type mismatches | STRICT table decision; M1 integration notes |
| D1 index best practice | https://developers.cloudflare.com/d1/best-practices/use-indexes/ | Last updated Aug 10, 2026 | Index columns used in predicates, uniqueness, multi-column query patterns, joins; naming convention `idx_TABLE_NAME_COLUMN_NAMES`; verify with `EXPLAIN QUERY PLAN`; run `PRAGMA optimize` after creating indexes; INTEGER-ROWID PKs need no extra index | Index migration content + test assertions |
| SQLite partial indexes | https://www.sqlite.org/partialindex.html | Current (SQLite docs) | Partial index = index over a subset of rows via `WHERE` clause on CREATE INDEX; can omit NULL entries; smaller files, better write performance when applicable | Documented as a future optimization; NOT used in v1 (stay literal to doc.md's index list) |
| SQLite STRICT tables | https://www.sqlite.org/stricttables.html | Current (SQLite docs; STRICT since 3.37.0, 2021-11-27) | `STRICT` table option enforces per-table rigid typing; datatypes must be INT/INTEGER/REAL/TEXT/BLOB/ANY; type violations are errors instead of silent coercion | STRICT added to all §6 tables (types are TEXT/INTEGER only — compatible) |
| D1 foreign keys | https://developers.cloudflare.com/d1/sql-api/foreign-keys/ | Current (opened via llms.txt markdown) | "By default, D1 enforces that foreign key constraints are valid within all queries and migrations", equivalent to `PRAGMA foreign_keys = on` for every transaction; `PRAGMA defer_foreign_keys = on` can defer within the current transaction only | Local tests must enable `PRAGMA foreign_keys = on` to mirror D1 |
| D1 SQL statements | https://developers.cloudflare.com/d1/sql-api/sql-statements/ | Current (opened via llms.txt markdown) | D1 supports a subset of SQLite PRAGMA statements; `PRAGMA table_list` reports a `strict` flag per table; supported SQLite extensions listed in workerd source | Test assertion method (strict flag check) |
| D1 docs index | https://developers.cloudflare.com/d1/llms.txt | Current | Machine-readable index of all D1 doc pages — used to locate the batch-semantics and foreign-key pages precisely | Navigation |
| Supabase/Postgres size model | https://supabase.com/docs/guides/platform/database-size | Current (opened 2026-10-10) | Postgres-side: database size vs disk size (WAL, system files) distinction; database can go read-only on plan limits; size = data + indexes + materialized views | D3 comparison, Postgres side |

## Options compared (D3: D1 vs Postgres)

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| **Cloudflare D1 (SQLite)** | Native Workers binding (no HTTP hop, no connection pooling); `db.batch()` = SQL transactions with rollback (opened source above); Time Travel PITR always-on, 30 days, free; `wrangler d1 migrations` built in; 10 GB per DB ≫ projected size for this platform (keys/sessions/events are small rows; 2 MB row cap irrelevant); read replication available via Sessions API for later scale-out | Single-writer per database (SQLite); no stored procedures; 100 bound params per query shapes batch sizes; SQL dialect is SQLite, not Postgres | **Chosen** — see Decisions |
| **Postgres (Supabase or similar)** | Full SQL (stored procedures, richer types), mature migration tooling, high write throughput | From Workers it needs an HTTP driver or Hyperdrive (extra hop + failure mode); separate platform/auth to operate; PITR is tier/feature dependent (Supabase size/read-only behavior per opened docs page); second infrastructure to secure (doc §18 wants least privilege + tested restores — two systems to test) | Not chosen for v1; documented fallback |

Postgres-side throughput numbers were not verified from primary sources this
session (the Supabase comparison pages found by search were marketing pages and
one docs URL 404'd). The D3 decision does not depend on them: doc.md §4 lists
D1 first for this architecture and M1 (API core) is being built natively on
Workers. Revisit only if measured write volume outgrows a single SQLite writer.

## Prior art found

- `Cretezy/cloudflare-d1-backup` (GitHub): script that exports a D1 database via
  the D1 HTTP API to SQL. Discovered via search; NOT opened this session, so no
  URL claims are made beyond the repo name. Time Travel + Workflows export
  (opened source above) covers the same need first-party.
- The captured reference service (doc.md §1) stores its state behind Cloudflare
  too [observed]; no further structural inference made (clean-room rule).

## Unverified items

1. **Postgres write-throughput advantage magnitude** — no primary source opened;
   irrelevant at v1 scale (see D3 above).
2. **Production node hostnames / count** — deployment-time configuration (doc
   D11); the seed takes them from environment variables, nothing hardcoded.
3. **Initial `protocol_versions` row values** (version string, handler name,
   min_loader) — doc.md defines the table and the `/status` shape but not the
   concrete first row's values. Seed accepts them from configuration; flagged
   in "Assumptions and questions" for the doc owner.
4. **Admin token format** — doc.md §5.8 says `Authorization: Bearer <admin
   token>` and the `admins` table stores `api_token_hash`, but the token's
   alphabet/length is unspecified. Seed generates 32 random bytes, base64url,
   stores SHA-256 hex (doc §5.1 "Hashes: SHA-256, hex"); flagged for the doc
   owner.

## Decisions made and why

1. **D3 = Cloudflare D1.** M1 (API core) runs on Workers (doc §4 stack table);
   D1 is the native binding there, `db.batch()` provides the transactional
   atomicity doc §22 requires for the HWID-bind race (opened batch-semantics
   source), and Time Travel covers doc §18 "tested restores" without a second
   system. Limits (opened limits page): 10 GB per DB vs projected low-GB
   storage for ~10^5–10^6 small rows; 100 bound params per query is the only
   shape constraint (batch DML in chunks ≤ 100 rows).
2. **STRICT tables.** Cloudflare's own binding docs recommend STRICT to avoid
   type mismatches (opened type-handling source), doc §6 uses only TEXT and
   INTEGER types (STRICT-compatible per the SQLite STRICT page), and the D1
   write conversion table (Number→INTEGER/REAL, String→TEXT, Boolean→0/1)
   maps cleanly onto STRICT columns. Column names, types, constraints, and
   defaults are kept verbatim from doc §6 — STRICT only enforces what §6
   already declares.
3. **Index strategy.** The doc §6 index list is implemented as literal
   `CREATE INDEX` statements with the `idx_<table>_<columns>` naming from the
   opened D1 best-practices page, EXCEPT `keys(key_hash)`: that column already
   carries a `UNIQUE` constraint, for which SQLite automatically creates a
   unique index (visible as `sqlite_autoindex_*`); creating another index on
   the same column would double write cost for zero read benefit (doc hard
   rule: no unnecessary code). The requirement "key_hash lookups are indexed"
   is satisfied by the implicit unique index; tests assert it via
   `EXPLAIN QUERY PLAN`. Partial indexes (opened SQLite source) documented as a
   future optimization for nullable columns; not used in v1 to stay literal to
   the doc's index list.
4. **Migration layout.** `wrangler d1 migrations` conventions (opened
   migrations page): sequential `NNNN_name.sql` files; v1 ships two —
   `0001_initial_schema.sql` (all 15 §6 tables, verbatim columns + STRICT) and
   `0002_indexes.sql` (the documented index list). Splitting the §6 snapshot
   into more files would invent a history the document does not define.
5. **Seed = configuration-driven, idempotent, secret-free at rest.** Only rows
   the doc's boot flows require: `nodes` (for `/sync`), `protocol_versions`
   (for `/status`), and a first `admins` owner row (for §5.8 admin API
   bootstrap). Hostnames/protocol values come from environment variables (doc
   hard rule: no hardcoded secrets/URLs). The owner bootstrap token is
   generated at seed time, printed once, stored only as a SHA-256 hash.
   `--print` emits plain SQL so the exact same statements can be applied with
   `wrangler d1 execute` remotely or a local SQLite for tests.
6. **Backup/restore = Time Travel + R2 export + restore drill** (opened Time
   Travel page): PITR to any minute in the last 30 days, bookmarks before
   risky migrations, R2 export for off-platform copies, and a quarterly restore
   drill documented in README (doc §18 "tested restores", §19 daily backups).
   Time Travel restores are limited to 10 per 10 minutes per DB (opened limits
   page) — the runbook notes this rate.
7. **Local test parity with D1.** Tests run the migration SQL against local
   SQLite with `PRAGMA foreign_keys = on` (mirroring the opened D1 default-FK
   source) and assert STRICT flags via `PRAGMA table_list` (opened
   sql-statements source). Transaction-atomicity is tested with an explicit
   BEGIN/ROLLBACK, mirroring the documented `db.batch()` abort semantics.

## Assumptions and questions (for the doc owner / Open Decisions)

- Q1: Initial `protocol_versions` row values (version string, handler name,
  min_loader) are configuration inputs, not schema decisions — please confirm
  the intended first values at deploy time (relates to D11).
- Q2: Admin token format (length/alphabet) is unspecified — confirm or accept
  the seed's 32-byte base64url proposal.
- Q3: `sessions.script_id` and `events.key_id` have no `REFERENCES` clause in
  doc §6 while other tables do — assumed intentional (session/event history
  should survive key/script deletion); see Contract Issues.
- Q4: `checkpoints.project_id` and `free_attempts.project_id` also lack
  `REFERENCES` in doc §6 — same treatment as Q3.
