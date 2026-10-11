# RESEARCH-M12 — Ops (logging, metrics, alerts, CI, deployment, multi-hostname, runbooks)

Module card: LP1-M12, doc §18 + §19 + §22 (Ops chaos row) + §23. Owner: glm3.
Claimed 2026-10-11 session 7 (TASKS row 253, push a48acf9, BEFORE work).

## Method note (honesty per §22.1)

Live web access for external docs was NOT available in this sandbox at
research time (same placeholder-token 401 condition M7's RESEARCH-M7
documented on 2026-10-10). In-repo sources below were actually opened and
read this session (file + line-level). Entries marked **[model-knowledge]**
come from training knowledge of Cloudflare's platform, are flagged as such,
and every one of them is load-bearing only for RUNBOOK guidance or CI
config shape — not for any runtime code path. The code deliverables depend
ONLY on in-repo facts.

## A. In-repo sources (opened this session)

1. **api/src/router.ts** — route table (38 rows), `matchRoute`,
   `dispatch()`. Facts extracted:
   - `dispatch()` body-size gate → 405/404 paths → handler → catch block.
   - **Finding F1 (chaos-relevant bug):** the catch block calls
     `await recordEvent(ctx, null, "server_error", …)` UNGUARDED, then
     returns `signedResponse(...)`. If the DB is down, `recordEvent`
     throws INSIDE the catch → the dispatch promise rejects → Workers
     returns an unhandled-rejection 1101 page, not our generic envelope.
     If the SIGNER is broken, the `signedResponse` in the catch rejects
     the same way. Both violate the §22 chaos expectation (DB down /
     signing key missing → graceful generic failure). Fix is 2 guarded
     paths in the catch (see DECISIONS D-M12-9).
   - `server_error` events are already recorded on every handler throw
     (detail = Error name) — the only place exceptions become data.
2. **api/src/flow.ts** — `AppContext {db, limiter, nonce, nowSec}`,
   `RequestInput`, `recordEvent` (events table insert), `signedResponse`
   (x-sig over `code|message|canonicalJson(data)|ts`), `checkRequestGate`
   (ts window → nonce shape → per-IP limiter 60/min → x-proof HMAC →
   replay nonce). Facts:
   - `validate_fail` events with detail `proof` / `nonce-replay` are
     written at the GATE level (all gated routes lumped — no flow column).
   - `recordEvent` writes `{id, key_id, type, detail, created_at}` —
     detail strings are internal codes/slugs; verified NO key plaintext,
     token, or HWID raw value is ever placed in `detail` (freekey uses
     `start:<slug>`, `step:<n>/<m>`, `claim:<slug>`; auth uses field
     names; checkkey uses reason codes).
3. **api/src/auth.ts** — `deny()` = `recordEvent(validate_fail, detail)` +
   signed envelope; `validate_ok` details are EXACTLY `auth_init`,
   `auth_payload`, `heartbeat` (lines 348/511/561); tamper events
   `client:<check>` from §11 heartbeat reports (line 551) +
   `invalid-key-lockout` (line 226); `session_kill` on heartbeat kill;
   UPDATE_REQUIRED denials carry details `loader-version`, `init-build`,
   `version-gone`, `build-changed`; `server_error` `bundle-missing` when
   the blob ref resolves to null (line 490).
4. **api/src/checkkey.ts** — `validate_ok` detail `check_key` (line 131);
   `minLoaderGate` (protocol_versions min_loader + kill via statusActive?
   — gate reads `loaderGate.kill`); invalid-key lockout via
   `invalid:<ipHash>` limiter bucket (5 per 600 s) writing `tamper`
   events.
5. **api/src/freekey.ts** — full §14 funnel event taxonomy:
   `free_flow` details `start:<slug>` (start success), `start-*` (start
   rejects), `step:<n>/<m>` (step success), `step-*` rejects,
   `claim:<slug>` (claim SUCCESS, line 361), `claim-window-expired`;
   `free_bypass` details for every anti-bypass reject (cooldown-reentry,
   ip-burst, step-unknown-token, fingerprint-mismatch, step-too-fast,
   step-bad-secret, step-bad-postback, claim-*). Free keys insert
   `created_by = 'free-flow'` (line 346) → conversion is derivable as
   keys.created_by join.
6. **api/src/payments.ts** — `payment_events` table (provider, event_id,
   event_type, outcome, order_id, created_at; outcomes include `stored`,
   `ignored`, and failure classes updated at lines 410/423);
   module-owned tables created via `CREATE TABLE IF NOT EXISTS` inside
   module src (CCP-4 pattern — new tables are Tier 3; M12 needs NONE).
7. **api/src/admin.ts `handleAdminAnalytics`** (lines 397-421) — the
   existing fixed-24h snapshot (keys active/revoked, sessions 24h/live,
   validate_ok/fail 24h, tamper 24h). Auth model: `authenticate()` +
   role owner|admin → 401/403. M12's /admin/metrics GENERALIZES this
   (windowed, per-flow, funnel, churn, payments, nodes) without touching
   it — dashboard keeps consuming the old shape (no breakage).
8. **api/src/syncstatus.ts** — `/sync` (clock offset st, active node
   hostnames, active protocol version map) and `/status` (active flag,
   versions, nodes) — both public, no gate. `STATUS_ACTIVE` env var →
   `config.statusActive` (index.ts line 116). **Finding F2:** the kill
   switch is deploy-time static (env var); there is no runtime toggle —
   see D-M12-8 (documented procedure, not a new endpoint).
9. **api/src/index.ts** — Workers entry: env→config wiring (incl. the
   malformed-signing-key fallback path documented at line ~100: falls
   back to default signer, error "surfaces via SERVER_ERROR envelope");
   Durable bindings RATE_COUNTER/NONCE; D1 binding DB; R2 BUNDLES.
10. **api/src/blobs.ts** — `BlobStore {get}` + `R2BlobStore` wrapping an
    R2BucketLike → chaos case "blob store down" = a get() that REJECTS
    (vs. resolves null = the existing `bundle-missing` path).
11. **api/src/db.ts** — DOC_SCHEMA_SQL (single schema source used by
    tests AND the dashboard gw): events, sessions, keys, free_attempts,
    nodes, protocol_versions, blacklist, admins, checkpoints… all
    derivation inputs live here. `SqliteAdapter` for in-process use.
12. **api/test/helpers.ts** — `buildEnv()` (in-memory bun:sqlite +
    DOC_SCHEMA_SQL + seeded project/script/version/nodes/protocol
    versions/admins/checkpoints + MemoryBlobStore + real signing pair),
    `makeSignedInput` (x-ts/x-nonce/x-lv/x-proof per the proof formula),
    `createKey`, `envelopeOf` — the loadtest reuses this machinery.
13. **wrangler.jsonc** — bindings + vars + secrets inventory (SERVER_PEPPER,
    SIGNING_PRIVATE_KEY_B64URL, PROOF_KEY_B64URL, SESSION_SEAL_KEY,
    PROJECT_SIGNING_KEYS map, PAYMENTS_* comma-lists for rotation
    windows, FREE_SECRET). Multi-secret comma-lists = the §18 rotation
    window pattern ALREADY in place for webhooks; PROJECT_SIGNING_KEYS
    map = per-project key rotation surface.
14. **db/README.md §Backup and restore** (M2) — Time Travel
    point-in-time recovery, R2 export, "a backup that has never been
    restored is not a backup". M12's backup script wraps this; no
    duplication.
15. **doc.md §18/§19/§22/§23** — requirements list (read this session):
    metrics = sync/check_key success rates, auth latency, tamper, free
    conversion, build failures, CDN hit ratio; alerts = failure spikes,
    many-HWIDs-per-key, signing errors, webhook failures, error budget;
    chaos = DB down, blob store down, signing key missing, one node
    unreachable; status page + outage plan; versioned API gate;
    multi-hostname; load test; CI dep scanning + pinned versions.
16. **tests/run.lua** (repo root) — M3 Lua suite entry (`lua5.4
    tests/run.lua`, 95/95) → CI lua job command.
17. **Existing fleet suites for CI wiring** (from TASKS rows +
    VERIFICATION files): api `bun test` + `tsc --noEmit` (229/229 at
    e4b44ee); obfuscator merged tree `bun test` (364/364) + tsc ×3;
    dashboard `eslint`; db seed `--print` smoke (M2).

## B. [model-knowledge] Cloudflare platform entries (flagged — runbook/CI guidance only)

18. **Workers Logs / `wrangler tail`** — Workers emit console + exception
    logs to a rolling in-portal log stream; `observability` flag in
    wrangler config enables it. Not relied on by code; runbook references
    it as the place exception NAMES (already in `server_error` events)
    can be correlated with request logs.
19. **Workers Analytics Engine** — a write-once time-series binding
    (`writeDataPoint`) suitable for per-request latency/success counters
    without D1 writes; queried via GraphQL API. This is the RECOMMENDED
    production path for the two §19 metrics v1 does not derive (auth
    latency distribution, CDN hit ratio for init files). Documented in
    DECISIONS D-M12-4 as not-built + why (binding + dashboard query
    surface = owner infrastructure decision).
20. **D1 Time Travel / `wrangler d1 export`** — point-in-time restore
    windows and SQL-file export; the backup script (tools/ops/backup.sh)
    wraps `wrangler d1 export` + SHA-256 + retention, matching M2's
    documented procedure. Version-fragile details are in the script's
    USAGE header, not in code paths.
21. **Secrets rotation via `wrangler secret put`** — secret updates take
    effect on next deploy/isolate refresh; rotation windows therefore
    need dual-valid lists — ALREADY the api's pattern for webhook
    secrets (source 13). The SERVER_PEPPER rotation caveat (hashes of
    keys/hwids/ips are pepper-derived — rotating it invalidates ALL
    stored hashes) is a RUNBOOK hard rule, not code.
22. **GitHub Actions + oven-sh/setup-bun** — standard CI shape for bun
    repos: setup-bun with pinned bun version, `bun install
    --frozen-lockfile`, `bun test`, `tsc --noEmit`, `bun audit` for
    dependency scanning. The workflow file is config-only (this sandbox
    cannot run Actions — VERIFICATION-M12 documents the locally-run
    equivalent commands instead, per §22.1 honesty).
23. **Multi-hostname behind Cloudflare** — the service ALREADY serves
    the node list from D1 (source 9) and the doc's "at least two
    hostnames" is an ADMIN registration procedure (runbook §node
    failover) + an alert when active nodes < 2 (implemented in code from
    source-1 facts, not from this entry).

## C. Gaps found (feeds DECISIONS)

- F1 (source 1): unguarded `recordEvent` + unguarded signed-response in
  the dispatch catch → DB-down / signer-down produce unhandled
  rejections. Chaos tests reproduce; fix delivered with regression tests.
- F2 (source 8/9): kill switch is deploy-static; no runtime maintenance
  toggle. Documented procedure instead of new endpoint (D-M12-8).
- F3: auth latency + CDN hit ratio are NOT derivable from existing
  tables without new hot-path writes → v1 excludes them, recommends
  Workers-native (D-M12-4).
- F4: validate_fail events carry no flow column → per-flow FAILURE split
  is impossible from data; failures reported as totals + reason
  breakdown (D-M12-5). Per-flow SUCCESS split IS possible (distinct
  validate_ok details).
