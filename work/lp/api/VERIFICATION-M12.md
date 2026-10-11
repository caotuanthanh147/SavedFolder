# VERIFICATION-M12 — Ops module (§22.1 evidence)

Owner: glm3. Everything below was RUN in this sandbox on 2026-10-11
(bun 1.3.14, Linux x86_64). Commands are copy-pasteable. Where something
could NOT be run, it says so explicitly with the reason.

## A. api package — suite + typecheck

```
$ cd api && bun install --frozen-lockfile
Checked 5 installs across 6 packages (no changes)

$ cd api && bun run typecheck        # tsc --noEmit
(no output = 0 errors)

$ cd api && bun test
249 pass / 0 fail, 1205 expect() calls, 18 files  [7.15s]
```

Breakdown of the M12 additions:
- `test/ops.test.ts` — 8 tests (metrics derivation over REAL router
  traffic + synthetic volume rows; window fallback; auth gates 401/403;
  M1 analytics unchanged; alert rule firing w/ severities + runbook
  anchors; pure evaluateAlerts coverage of every rule incl. boundary
  constants from ALERT_THRESHOLDS; §18 hygiene route scan; §18 no-console
  source scan).
- `test/chaos.test.ts` — 12 tests (see §B).
- Baseline before M12: 237/237 (main-agent's 229 + 8 ops tests landed
  mid-session by this lane — both counts re-verified this session).

## B. Chaos (doc §22 Ops row) — test/chaos.test.ts, 12/12

```
$ cd api && bun test test/chaos.test.ts
12 pass / 0 fail, 94 expect() calls  [62ms]
```

Fault matrix, each driving the REAL dispatch (real router + handlers):

| Fault | Injection | Result (asserted) |
|-------|-----------|-------------------|
| DB down | DbAdapter with all methods rejecting | /check_key, /sync, /admin/metrics → SIGNED `SERVER_ERROR` envelope, status 200; body carries no driver strings/stack (`sqlite`, `d1 unavailable`, `error:` … all asserted absent); `x-sig` present |
| DB down, no partial state | same | events/sessions/keys row counts byte-identical after the faulted requests |
| Signing key missing | Signer rejecting | previously-CRASHING path (D-M12-9 fix) → unsigned generic `500 {"error":"server_error"}`, no `x-sig` header; error path still records `server_error` event (+1) alongside the successful validation's `validate_ok` (+1) — count pinned at +2 |
| Bundle absent | BlobStore get → null | auth payload → `SERVER_ERROR` envelope + exactly ONE `server_error`/`bundle-missing` event; session rows untouched |
| Blob store erroring | BlobStore get → reject | auth payload → signed generic `SERVER_ERROR` envelope |
| No payload leak | both blob faults | bundle bytes never present in any response body |
| One node down | SQL active=0 | /sync serves the survivor; check_key fully functional |
| All nodes down | SQL active=0 all | /sync still 200 (empty list); /admin/alerts fires `nodes-degraded` critical; check_key still KEY_VALID |

## C. Load test (doc §19, D-M12-10) — in-process numbers

```
$ cd api && bun run tools/loadtest.ts 500 10
op                n     p50µs    p95µs    p99µs     req/s   err
GET /sync         500     15.0     35.2     71.8   56,225     0
GET /status       500     17.3     30.3     54.3   51,453     0
POST /check_key   500    299.7    503.0   1522.6    2,130     0
GET /admin/metrics   500   645.2    772.0    869.4    1,503     0
mixed ×10 conc    500        -        -        -    3,961     0
```

What this measures: ROUTER+HANDLER+SQL on the in-memory SQLite adapter,
proof verification included, 500 events rows accumulated during the run
(metrics cost grows with data — visible and honest). What it does NOT
measure: network, TLS, CF edge, D1-over-RPC. Deployed-edge load testing
before public launch is an owner action (RUNBOOK-M12 §load). check_key
p99 spike = rate-limiter bucket growth across 500 distinct IP buckets.

## D. Backup script (tools/ops/backup.sh) — end-to-end local proof

```
$ tools/ops/backup.sh --local /tmp/bktest/app.db --out /tmp/bk --keep 2   (×3, 1.1s apart)
backup OK: /tmp/bk/backup-20261011T032306Z.sqlite (8192 bytes, sha256 201c…f741)
$ cat /tmp/bk/manifest.log       # 3 entries + 1 prune line
2026-10-11T03:23:03Z … sha256=201c…f741 bytes=8192 …
2026-10-11T03:23:06Z prune /tmp/bk/backup-20261011T032303Z.sqlite
$ bun -e '…open newest backup read-only…'
rows in backup: [{"id":1,"v":"hello"},{"id":2,"v":"world"}]
```

Verified: VACUUM INTO snapshot, PRAGMA integrity_check gate (exit 3 path),
sha256 manifest, retention prune at --keep 2, readable restore.
NOT RUN: `--remote` mode (wrangler d1 export) — requires owner CF
credentials; the script wraps the documented command and its failure
paths (rm partial file, exit 2) are code-reviewed, honestly flagged here.

## E. Repo-wide suites (CI-equivalent runs)

```
$ cd obfuscator && bun test           → 385 pass / 0 fail  [18.2s]
$ cd obfuscator/compiler && bun test  →  45 pass / 0 fail  [182ms]
$ cd obfuscator/vm && bun test        →  84 pass / 0 fail  [17.6s]
$ lua5.4 tests/run.lua                →  95 passed, 0 failed (pre-rebase)
$ lua5.4 tests/run.lua (post-rebase onto glm1 M3-s3) → 101 passed, 0 failed
$ lua5.4 tests/m7_checks_test.lua     →  40 passed, 0 failed
$ bun db/seed/seed.ts --print --test-fixtures | head → INSERTs emitted, exit 0
$ (api) bun x npm i --package-lock-only && bun x npm audit --omit=dev
  → found 0 vulnerabilities
```

tsc --noEmit × 4 packages (api incl. tools/, obfuscator ×3): 0 errors,
with `--frozen-lockfile` installs verified for all four (compiler's
bun.lock newly committed this delivery).

## CI (D-M12-11)

`.github/workflows/ci.yml` — 6 jobs (api / obfuscator / lua / db-seed /
dashboard / dependency-audit). **GitHub Actions cannot run in this
sandbox** — §E above lists the exact locally-run equivalent of every job's
commands, all green, except:
- `dashboard` job (bun install + eslint): NOT re-run here — the dashboard
  tree has no committed lockfile and no node_modules in this clone; it was
  developed and lint-verified in the web sandbox (main-agent s3-s11,
  `lint 0` recorded in their TASKS rows). Committing its lockfile is the
  owner's first-CI-run follow-up.
- `dependency-audit` for obfuscator ×3: the npm-lockfile generation trick
  was proven on api (same two devDependencies everywhere); expected 0
  vulnerabilities but marked continue-on-error as an informational pass.

## Not done / out of v1 (honest list, D-M12-4 + RESEARCH §C)

- auth latency distribution + CDN hit ratio — need hot-path
  instrumentation; Workers Analytics Engine recommended (owner decision).
- runtime maintenance toggle — STATUS_ACTIVE deploy-var procedure instead
  (D-M12-8).
- real CF deployment, staging separation, wrangler d1 export remote mode,
  GitHub Actions execution — owner account actions; runbook carries the
  procedures.
- Alerts are stateless (no ack table): dedupe/muting lives at the poller
  (dashboard bell / M8 bot) by design (D-M12-2).

## F. Frozen response shapes (exact JSON, delivered contract)

`GET /admin/metrics?window=1h` on a fresh env (all-zero is the minimal
shape; every field is always present):

```json
{
 "window": "1h", "since": 1791685706, "generated_at": 1791689306,
 "auth": { "init": {"ok":0}, "payload": {"ok":0}, "heartbeat": {"ok":0},
           "check_key": {"ok":0}, "total_ok": 0, "total_fail": 0,
           "attempts": 0, "success_rate": null },
 "failure_reasons": [], "update_required": 0,
 "tamper": { "total": 0, "by_detail": [] },
 "free_flow": { "starts": 0, "steps": 0, "claims": 0,
                "attempts_started": 0, "attempts_completed": 0,
                "keys_issued": 0, "conversion": null },
 "bypass": { "total": 0, "by_detail": [] },
 "payments": { "webhook_failures": 0, "by_detail": [], "outcomes": [] },
 "sessions": { "created": 0, "live_now": 0, "killed": 0 },
 "keys": { "active": 0, "revoked": 0, "expiring_7d": 0 },
 "hwid_churn": { "window": "7d", "rows": [] },
 "server_errors": { "total": 0, "by_detail": [] },
 "nodes": { "active": 2, "inactive": 0 },
 "protocol": { "active_versions": 2 }
}
```

Row item shapes: `by_detail[]/outcomes[]/failure_reasons[]` = `{detail, n}`;
`hwid_churn.rows[]` = `{key_id, distinct_hwids, hwid_resets}`.

`GET /admin/alerts`:

```json
{ "generated_at": 1791689306, "alerts": [] }
```

Alert row shape (firing example from the tests): `{id, severity:
"critical"|"warning", title, detail, runbook}` where `runbook` =
`tools/ops/RUNBOOK-M12.md#<id>` and ids are: server-errors-1h,
tamper-spike-1h, auth-fail-spike-1h, error-budget-24h, free-bypass-spike-1h,
webhook-failures-24h, hwid-churn-7d, nodes-degraded, protocol-inactive,
sessions-stalled-1h. Thresholds are exported constants
(`ALERT_THRESHOLDS` in api/src/ops.ts) — the numbers live in DECISIONS-M12
D-M12-6, not duplicated here.
