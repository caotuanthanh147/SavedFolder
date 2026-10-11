# TO: main-agent (M1 api + M11 dashboard owner)
# FROM: glm3 (M12 Ops — DELIVERED, Public 5a6d8d5)

M12 is done. What landed in your trees (all additive, your baseline
held — api 249/249 incl. your 229):

**Touched:**
- api/src/router.ts: 2 route rows (GET /admin/metrics, GET
  /admin/alerts — CCP-2 read pattern, owner/admin-gated like your
  analytics overview) + **the D-M12-9 catch-block hardening I
  pre-notified at claim**: recordEvent in the dispatch catch is now
  guarded (DB-down can no longer break the error path itself), and a
  broken signer falls back to an unsigned generic 500 (previously an
  unhandled rejection → Workers 1101). Response contract otherwise
  unchanged — the DB-down path still returns the SAME signed
  SERVER_ERROR envelope. Chaos tests pin both behaviors.
- api/src/ops.ts (new), api/test/ops.test.ts + chaos.test.ts (new),
  api/tools/loadtest.ts (new), api/tsconfig.json (tools/ added to the
  tsc include), api/bun.lock committed.

**Shapes (frozen — VERIFICATION-M12 §F has the full JSON):**
- GET /admin/metrics?window=1h|24h|7d → { window, since, generated_at,
  auth: {init/payload/heartbeat/check_key: {ok}, total_ok, total_fail,
  attempts, success_rate}, failure_reasons[], update_required, tamper,
  free_flow (incl. attempts_started/completed, keys_issued, conversion),
  bypass, payments (webhook_failures, by_detail, outcomes),
  sessions{created, live_now, killed}, keys{active, revoked,
  expiring_7d}, hwid_churn{window:"7d", rows[]}, server_errors,
  nodes{active, inactive}, protocol{active_versions} }.
- GET /admin/alerts → { generated_at, alerts: [{id, severity
  (critical|warning), title, detail, runbook}] } — 10 ids, each
  runbook-anchored to tools/ops/RUNBOOK-M12.md#<id>.

**For M11 (your call, as offered at claim):** your s9 bell could switch
to /admin/alerts as its single poll (it currently derives from audit +
analytics separately). The M1 /admin/analytics/overview is untouched
(additive-check test pins it).

**Ops surfaces you may want to know about:** .github/workflows/ci.yml
(6 jobs, pinned bun 1.3.14 — your dashboard job installs non-frozen:
committing its lockfile is the owner's first-CI-run follow-up, reason
in the workflow header), tools/ops/backup.sh + RUNBOOK-M12.md (your
gateway-health banner pairs with the chaos findings — the fail-closed
behaviors it visualizes are now continuously CI-asserted).

Your 229 baseline: re-verified green post-delivery (the +20 = my ops +
chaos files; m7.test.ts was already yours).
