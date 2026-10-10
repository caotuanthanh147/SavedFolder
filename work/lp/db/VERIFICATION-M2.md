# VERIFICATION-M2 — §22.1 compliance record

Scope: proves the M2 claims in README.md with commands and outputs, lists what
was NOT run. Written per doc.md §22.1 ("guards against claimed done, never
proven"), added in doc v3 (Public cd2ad33).

## Environment

| Item | Value |
|------|-------|
| OS | Linux (sandbox container) |
| Python | 3.12.14 |
| SQLite engine | 3.53.1 (via python `sqlite3` module; sqlite3 CLI not installed in sandbox) |
| Bun (seed tests) | available on PATH (version printed by test 18) |

## What I ran, and the output

Command: `python3 tests/run_tests.py` (from `db/`), which:

1. applies `migrations/0001_initial_schema.sql` then `0002_indexes.sql`
   sequentially into a fresh temp SQLite DB,
2. asserts schema/STRICT/index/constraint/seed/batch properties,
3. runs `seed/seed.ts` via bun in `--test-fixtures` mode and asserts seeded rows,
4. tears the DB down.

Output (full, verbatim tail):

```
[PASS] all 15 doc.md 6 tables created
[PASS] migrations applied as sequential .sql files
[PASS] every table is STRICT
[PASS] keys columns verbatim from doc.md 6
[PASS] documented indexes created
[PASS] index used: keys by key_hash (doc index list, via UNIQUE)
[PASS] index used: keys by discord_id
[PASS] index used: sessions by key_id, created_at
[PASS] index used: events by key_id, created_at
[PASS] index used: blacklist by kind + value_hash
[PASS] index used: script_games by game_id
[PASS] keys.key_hash UNIQUE enforced
[PASS] foreign key keys.project_id enforced
[PASS] foreign key key_scripts.key_id enforced
[PASS] STRICT rejects wrong types (text->INTEGER, blob->TEXT)
[PASS] keys defaults (hwid_resets=0, total_executions=0)
[PASS] keyless session (key_id NULL) insertable
[PASS] bun available on PATH for seed tests
[PASS] seed: 1 node row
[PASS] seed: node values from fixtures
[PASS] seed: protocol_versions row
[PASS] seed: owner admin with SHA-256 hex token hash
[PASS] seed: idempotent (re-apply keeps counts)
[PASS] seed: protocol row upserts on config change
[PASS] batch-style atomicity: failed sequence rolls back entirely
[PASS] auth-init join resolves key -> entitlement -> game

26/26 checks passed
```

Last full run: 2026-10-10, after the doc v3 force-push (re-verification on the
exact bytes re-delivered in this commit).

## Why the tests are not "restating my implementation"

Every assertion derives from an outside source, not from my code:

- Table/column/type names: verbatim from doc.md §6 (the contract). The test
  hard-codes the doc's column list, so any drift between doc and migration fails.
- STRICT rejection behavior, UNIQUE enforcement, FK enforcement, defaults:
  SQLite documented semantics (sqlite.org/lang_createtable.html — STRICT tables
  reject type-mismatched values; UNIQUE constraints; FK enforcement requires
  PRAGMA foreign_keys=ON, which the test enables explicitly).
- Index usage: `EXPLAIN QUERY PLAN` (SQLite-documented introspection) shows the
  chosen index for each §6 access pattern — this proves the index helps, not
  just that it exists.
- Batch atomicity: Cloudflare D1 documents `db.batch()` as an implicit
  transaction (docs: "Batched statements are SQL transactions"); the test
  simulates the equivalent (BEGIN…ROLLBACK on mid-sequence failure) per
  sqlite.org/lang_transaction.html.
- Seed idempotency: requirement from README §seed semantics (upsert contract),
  asserted by re-running and comparing row counts.

## NOT run (honest gaps)

1. **Real Cloudflare D1.** Everything above ran on local SQLite 3.53.1. D1 is a
   SQLite-derived service; RESEARCH-M2.md cites D1 docs for where behavior can
   differ (row size caps, SQL support notes). A `wrangler d1 migrations apply`
   against a real database is **not run** from this sandbox (no Cloudflare
   account/network access). First real-D1 smoke test belongs to M1 integration
   or the doc owner.
2. **Time Travel restore drill** (30-day PITR): documented from Cloudflare docs
   only; not executable locally.
3. **Concurrent migration application:** D1 applies migrations serially per
   Cloudflare docs; a concurrency race cannot be reproduced locally.
4. **Seed randomness quality** (owner token): the seed uses crypto-random bytes;
   statistical quality is not tested (out of scope for a seed script).
5. **Load/soak of §6 access patterns:** EXPLAIN proves index selection, not
   throughput. Numbers need real traffic (doc §22 real-environment tests).

## Independent review status

- Cross-checked by main-agent (M1 author, different instance) against their
  `DOC_SCHEMA_SQL`: COMPATIBLE — same columns/constraints; index-name deltas
  cosmetic (names not referenced by SQL). Their msg 2026-10-10T12:45Z.
- Per §22.1, security-critical double review: M2 is not on the crypto/HWID/
  replay critical list (it is schema + seed), so single cross-check + M14
  final pass applies. M14 has NOT yet run (M14 is always last per doc §7).
