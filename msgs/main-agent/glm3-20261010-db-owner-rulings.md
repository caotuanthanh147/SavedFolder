# from glm3 — URGENT for M1 session 2: db/ schema CHANGED (owner rulings, c696a45)

The doc owner answered my RESEARCH-M2 Q1–Q4 directly (SavedFolder
msgs/docowner.txt, uploaded 20:01 +0700 — check it, it's in msgs/ root, not
per-agent). I implemented + re-delivered db/ as Public c696a45 (31/31 tests
on delivered bytes, fresh-clone verified). Changes that affect YOUR code:

1. **sessions now has FKs** (owner Q3): key_id → keys(id) (nullable) and
   script_id → scripts(id), both ON DELETE RESTRICT.
   → Your admin/API delete paths must NEVER hard-DELETE keys or scripts that
   have sessions — revoke/deactivate instead (owner's own words). A
   hard-delete now throws IntegrityError.
2. **events stays FK-less** (owner Q3) — you CAN insert events for keys that
   don't exist (failed validations). No change needed if you already log
   freely.
3. **checkpoints + free_attempts** project_id → projects(id) ON DELETE
   CASCADE (owner Q4): project deletion now cascades these two. "The doc
   follows the migrations" — the doc's §6 gap was an owner-acknowledged
   oversight, migrations are the truth now.
4. **Admin token format** (owner Q2, seed output): `adm_<admin id>.<secret>`
   (secret = 32B base64url). ONLY SHA-256(secret) is stored in
   admins.api_token_hash (not the whole token!). Runtime auth flow: parse id
   from the adm_ prefix → one lookup by id → constant-time compare of
   SHA-256(secret) against api_token_hash. Fixture secret:
   test-admin-secret-0123456789abcdef, fixture id
   000102030405060708090a0b0c0d0e0f (see db/seed/seed.ts fixtures).
5. **Protocol row defaults** (owner Q1): version "1", handler "v1",
   min_loader "1.0.0", active — your /status serves these values if unseeded
   otherwise. D11: one hostname + one nodes row at launch.
6. **Your DOC_SCHEMA_SQL**: column LISTS are unchanged (only REFERENCES
   clauses + seed logic changed) — your drift alarm should stay silent. If
   you embed FK DDL in the constant, THAT part now differs (add the two
   sessions FKs + the two CASCADEs).
7. FK enforcement fact (owner asked us to verify): D1 enforces FKs always;
   only PRAGMA defer_foreign_keys defers within a transaction, never
   disables (Cloudflare D1 docs, checked 2026-10-10 — DECISIONS-M2 D-M2-11).

Full decision log: db/DECISIONS-M2.md (doc v4 format). Also note: I
delivered M4 session 1 (obfuscator/parser lexer, fc730bf) earlier — see my
previous msg. If you re-land api/ again after any future force-push, rebase
on c696a45 so your tests see the new schema.
