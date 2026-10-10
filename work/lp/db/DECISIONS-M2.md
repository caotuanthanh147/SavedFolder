# DECISIONS-M2 — Decision Log (doc.md "Decision authority", v4/18555ec)

Backfilled for M2 (delivered before doc v4 existed) + the 2026-10-10 owner
rulings (SavedFolder msgs/docowner.txt — direct answers to RESEARCH-M2
Q1–Q4).

| # | Decision | Options considered | Choice | Why (with evidence) | Tier | Reversibility | Affects modules |
|---|----------|--------------------|--------|---------------------|------|---------------|-----------------|
| D-M2-1 | Database engine (Open Decision D3) | Cloudflare D1 vs Postgres (Supabase) | **D1** | Native Workers binding (doc §4 stack pairs API=Workers); `db.batch()` = implicit SQL transactions (Cloudflare D1 docs) covers the HWID-bind race; Time Travel 30-day PITR always-on; `wrangler d1 migrations` fits the pipeline. Supabase adds a second vendor + network hop for the same relational job. Sources in RESEARCH-M2.md (12 opened) | 1→2 | medium (migration path = export/import; schema is portable SQLite SQL) | M1 (binding), M12 (ops) |
| D-M2-2 | STRICT tables | plain (affinity) tables vs `STRICT` | **STRICT** | sqlite.org STRICT docs: columns enforce declared types; all §6 types are TEXT/INTEGER so fully compatible; Cloudflare's own D1 examples use STRICT. Catches type bugs at write time | 1 | high (one-word per table) | M1 (insert shapes) |
| D-M2-3 | sessions FKs (owner Q3 ruling) | no FK (old draft) vs FK ON DELETE RESTRICT vs CASCADE | **keys(id) + scripts(id), both ON DELETE RESTRICT; key_id nullable for keyless scripts** | Owner ruling verbatim: "sessions gets foreign keys to keys(id) (nullable for keyless scripts) and scripts(id), with ON DELETE RESTRICT. Revoke or deactivate instead of hard-deleting." RESTRICT preserves session history for audit | 3→resolved by owner | low (owner-set) | M1 (delete paths must revoke/deactivate, never hard-delete keys/scripts with sessions) |
| D-M2-4 | events FK (owner Q3 ruling) | FK to keys vs no FK | **no FK** | Owner ruling: "failed validations can involve keys that don't exist and audit history should outlive deletions" — rationale documented in 0001 comment | 3→resolved by owner | low | M1 (may log events for unknown keys) |
| D-M2-5 | checkpoints/free_attempts project_id (owner Q4 ruling) | bare column (old draft) vs REFERENCES ... CASCADE | **REFERENCES projects(id) ON DELETE CASCADE** | Owner ruling: "The gap in the doc was an oversight, so the contract issue is accepted and the doc follows the migrations." | 3→resolved by owner | low | none beyond db |
| D-M2-6 | Applying the owner's schema rulings: edit 0001 in place vs append a 0003 rebuild migration | in-place edit of the initial schema vs SQLite table-rebuild migration (CREATE new → INSERT SELECT → DROP → RENAME) | **in-place edit of 0001** | Project is pre-launch: no D1 database has been created/applied anywhere (migrations run only in local tests so far; deployment hasn't happened — no wrangler.toml/D1 binding in api/). SQLite cannot ALTER TABLE ADD CONSTRAINT, so a 0003 rebuild is ~150 lines of copy-dance for zero deployed consumers. Column LISTS are unchanged (only REFERENCES clauses added) so M1's DOC_SCHEMA_SQL column check does not drift. Contingency logged: if any DB was applied from the old 0001, run the rebuild equivalent before 0002 | 2 | high (if a deployed DB exists: one rebuild migration, documented) | M1 (schema constant — columns unchanged) |
| D-M2-7 | Admin token format (owner Q2 ruling) | opaque random token vs `adm_<id>.<secret>` | **`adm_<admin id>.<secret>`; secret = 32B CSPRNG base64url; store ONLY SHA-256(secret) hex; full token printed once** | Owner ruling verbatim (id prefix = one lookup + one comparison + secret-scanner friendly). Runtime constant-time compare is M1's job (WebCrypto timingSafeEqual equivalent) | 3→resolved by owner | low | M1 (auth: parse id prefix, look up, constant-time compare SHA-256(secret)) |
| D-M2-8 | Admin scope/expiry columns (owner Q2: "if you add ... log them as Tier 2") | add scope/expiry now vs defer | **defer — not added** | doc §6 admins table has no such columns; no current feature needs them (single owner at bootstrap); adding speculative columns contradicts "do not add features not in the document". When roles beyond 'owner' arrive, add via new migration | 2 | high (additive migration later) | M1 (only when added) |
| D-M2-9 | Seed protocol defaults (owner Q1 ruling) | env-required vs owner defaults w/ env override | **defaults: version 1, handler v1, min_loader 1.0.0, active; LP_SEED_PROTO_* env overrides** | Owner ruling: "first protocol_versions row: version 1, handler v1, min_loader 1.0.0, active. Raise min_loader only when retiring old loaders. ... If your research shows better seed values, use them and log it." No better values found | 1 | high | M1 (/status serves this row) |
| D-M2-10 | D11 seed shape | seed N nodes vs exactly 1 | **exactly one node row per launch config (env-driven; fixture = 1)** | Owner ruling: "For D11, launch with one hostname and one nodes row. The node list stays in the contract for later." Hostnames are deployment config (Hard Rule: no hardcoded URLs) — env-driven with the one-row launch expectation documented | 2 | high | M1 (/sync node list) |
| D-M2-11 | FK enforcement verification (owner Q3: "verify ... before relying on them") | assume SQLite defaults vs verify D1's documented behavior | **verified: D1 enforces FKs; only `PRAGMA defer_foreign_keys` can defer within a transaction, never disable** | Cloudflare D1 docs (developers.cloudflare.com, SQL support page, checked 2026-10-10): defer_foreign_keys defers constraints inside the current transaction; the docs + D1 team clarifications state enforcement cannot be turned off. Local harness mirrors this with `PRAGMA foreign_keys = on` per connection (SQLite default is OFF — difference documented for M1: D1 = always on) | 1 | high | M1 (no per-connection PRAGMA needed on D1; local dev needs it) |

## Contingency note (D-M2-6)

If a database was already created from the pre-ruling 0001 (no known case),
apply this rebuild before 0002 for each affected table (sessions,
checkpoints, free_attempts):

```sql
-- example for sessions; same pattern for the other two
PRAGMA defer_foreign_keys = on;
CREATE TABLE sessions_new ( ...same columns + REFERENCES clauses... ) STRICT;
INSERT INTO sessions_new SELECT * FROM sessions;
DROP TABLE sessions;
ALTER TABLE sessions_new RENAME TO sessions;
```
