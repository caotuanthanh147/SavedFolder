# DECISIONS-M12 — Ops module

Owner: glm3. Format per doc "Decision authority". Research backing:
RESEARCH-M12.md (source numbers cited as R#).

- **D-M12-1 — Metrics are PURE-DERIVED from existing tables. No new
  tables, no migrations, no hot-path writes.** (R3-R8, R11)
  Alternatives: (a) new `ops_metrics` counters table written from
  handlers — rejected: D1 write per request on the auth hot path (cost +
  latency + a Tier-3 CCP for schema); (b) sampled async writes —
  rejected for v1: complexity + still D1 writes; (c) pure derivation —
  chosen: every §19 metric EXCEPT latency distribution and CDN ratio is
  already persisted as data (events taxonomy, sessions, keys,
  free_attempts, payment_events). Rollback: none needed (additive
  reads). Affected modules: none (zero schema/interface change).

- **D-M12-2 — Alert evaluation is server-side, stateless, and
  threshold-constant in v1.** `/admin/alerts` evaluates pure functions
  over the same derived windows; no alert-state table (an alert "firing"
  is a function of current data, not stored state — dashboard/bot can
  poll; dedupe/muting is the poller's concern, matching M11 s9's
  existing bell pattern). Thresholds are exported constants
  (THRESHOLDS in ops.ts) pinned by tests. Config-from-env was rejected:
  ApiConfig is M1's interface; extending it for tunables is not worth a
  cross-module touch in v1.

- **D-M12-3 — Windows: 1h, 24h, 7d (query param, default 24h).** The
  doc's alert classes are spike-shaped (1h) and budget-shaped (24h);
  7d serves trend review. /admin/alerts always evaluates BOTH 1h and 24h
  internally (spike rules read 1h, budget/churn rules read 24h/7d).

- **D-M12-4 — NOT built in v1: auth latency distribution, CDN hit ratio
  for init files.** (R19, gap F3) Both need per-request instrumentation
  that existing tables don't carry. Recommended production path:
  Workers Analytics Engine `writeDataPoint` (R19) or Workers Logs
  sampling — an owner infrastructure decision (binding + query surface +
  cost). RESEARCH-M12 §B documents it; runbook carries the procedure
  placeholder. Honest NOT-RUN list in VERIFICATION-M12.

- **D-M12-5 — Failure reporting shape.** Per-flow SUCCESS counts come
  from distinct `validate_ok` details (auth_init / auth_payload /
  heartbeat / check_key — R3/R4). Per-flow FAILURE split is impossible
  (no flow column on validate_fail — gap F4), so failures are reported
  as: total, top reason details (masked internal codes, verified
  secret-free in R2), and UPDATE_REQUIRED subset (details
  loader-version/init-build/version-gone/build-changed). Success rate =
  ok/(ok+fail) over ALL gated flows. Schema-faithful; changing it would
  be a Tier-3 events-schema proposal for marginal value.

- **D-M12-6 — Alert rules v1 (ids stable, runbook-anchored).**
  Each rule maps to a doc §19 alert class; severities critical/warning:
  1. `server-errors-1h` critical — server_error events in 1h ≥ 10
     (includes signing failures — they surface as thrown errors →
     server_error, R1/R9).
  2. `tamper-spike-1h` warning ≥ 20, critical ≥ 100.
  3. `auth-fail-spike-1h` warning — validate_fail ≥ 200 in 1h AND
     fail-ratio ≥ 0.5 (brute-force shape).
  4. `error-budget-24h` warning — fail-ratio ≥ 0.05 over ≥ 500 attempts.
  5. `free-bypass-spike-1h` warning — free_bypass ≥ 30 in 1h.
  6. `webhook-failures-24h` warning — payment_events failure-class
     outcomes ≥ 10 in 24h.
  7. `hwid-churn-7d` warning — any key with ≥ 5 distinct session HWIDs
     in 7d (doc: "many HWIDs per key"); payload lists top 3 offenders.
  8. `nodes-degraded` critical — active nodes = 0; warning — < 2
     (doc §19 "at least two hostnames").
  9. `protocol-inactive` critical — active protocol_versions = 0 (every
     auth init would UPDATE_REQUIRED/kill — R4 minLoaderGate).
  10. `sessions-stalled-1h` warning — zero validate_ok in 1h while ≥ 1
      validate_fail (service-up-but-rejecting shape). Chosen over a
      traffic-floor rule: absolute floors are workload-dependent
      (owner-tunable later via D-M12-2 constants).

- **D-M12-7 — Chaos harness lives as TESTS (api/test/chaos.test.ts),
  not a separate tool.** §22 chaos cases (DB down, blob store down,
  signing key missing, node unreachable) are expressed as in-process
  dispatch tests with broken adapters — they run in CI on every push
  (the whole point of chaos: continuously asserted, not run once).
  Adapters: ThrowingDbAdapter (run/query reject), ThrowingBlobStore
  (get rejects), ThrowingSigner (sign rejects), node-deactivation via
  SQL. Assertions: generic SERVER_ERROR envelope (or unsigned 500 JSON
  when the signer itself is broken), no stack/error-class names in the
  response body, no script bytes, no partial loads, /sync stays
  functional where required.

- **D-M12-8 — Maintenance/kill-switch = documented procedure, NOT a new
  runtime endpoint.** (R8/R9, gap F2) STATUS_ACTIVE is a deploy-time
  env var; a runtime toggle would add a hot-path DB read or a new
  config surface in M1's ApiConfig for marginal gain. Runbook:
  flip via CF dashboard/wrangler var + redeploy; /status reflects it;
  loaders get status.active=false → no script load (M3 contract).

- **D-M12-9 — dispatch() catch-block hardening (the F1 fix; touches
  M1's router.ts with main-agent pre-notified via claim msg).** The
  catch now (a) wraps recordEvent in try/catch (DB-down must not break
  the error path itself), (b) falls back to an unsigned
  `500 {"error":"server_error"}` JSON when the signed response itself
  rejects (signing-key-missing must not produce an unhandled
  rejection). Tier-2 robustness (reversible, additive guards, no
  contract change — response envelope for the DB-down path stays the
  SAME SERVER_ERROR signed envelope; only the previously-CRASHING
  signer-down path gains a generic unsigned 500). Regression: chaos
  tests pin both. Alternatives rejected: moving the guard into flow.ts
  (would change signedResponse' contract), or a wrapper route (dup).

- **D-M12-10 — Load test = in-process dispatch storm
  (api/tools/loadtest.ts), reusing test/helpers.buildEnv machinery.**
  Measures p50/p95/p99 µs + RPS for /sync (public read), /status
  (public read), /check_key (gated write path, real key, real proof
  headers), /admin/metrics (admin read). In-process = honest about what
  it measures: ROUTER+HANDLER+SQL cost, excluding network + CF edge +
  D1-over-RPC. Runbook states this explicitly; real-edge load testing
  before launch is an owner action (doc §19 "load test before launch").
  Numbers recorded in VERIFICATION-M12 §numbers.

- **D-M12-11 — CI = one workflow, five jobs, config-only deliverable.**
  .github/workflows/ci.yml: api (install --frozen, tsc, test),
  obfuscator (tsc ×3 + merged test), lua (apt lua5.4 + tests/run.lua),
  db (seed --print smoke), dashboard (lint) + dependency-audit job
  (bun audit, non-blocking on failure with explicit continue-on-error —
  first pass is informational; blocking is an owner policy call).
  Pinned: bun version in setup-bun + lockfiles committed (R22). This
  sandbox cannot execute Actions — VERIFICATION-M12 lists the exact
  locally-run equivalents for every job (per §22.1: no "should work").

- **D-M12-12 — Runbook location: tools/ops/RUNBOOK-M12.md** (with
  backup.sh), referenced from api/VERIFICATION-M12.md. Repo layout
  (doc) puts build scripts/tools under tools/ — ops tooling is that
  class. Alert ids in /admin/alerts are runbook anchors (stable ids,
  D-M12-6).

- **D-M12-13 — URL/hygiene scan as a TEST (api/test/ops.test.ts).**
  §18 "Keys, tokens, and HWIDs never in URLs or logs": (a) static
  route-table assertion — no route pattern has secret-valued params
  (path params are ids only; the raw key travels in the POST body,
  verified R3/R4); (b) source scan — no `console.*` in api/src (the
  event table IS the log, R2; Workers Logs pick up exceptions via the
  server_error event path).

- **D-M12-14 — /admin/metrics response shape is additive and versioned
  by `window` param; /admin/analytics/overview (M1) is NOT modified**
  — dashboard + bot consumers keep working; they can migrate at will.
  Shape frozen at delivery (VERIFICATION-M12 carries the exact JSON).
