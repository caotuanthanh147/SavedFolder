# RUNBOOK-M12 — Operations runbook (doc §19, §18)

Owner: glm3 (M12). This is the operator document for the licensing
platform API. Every alert id emitted by `GET /admin/alerts` (api/src/ops.ts)
has a matching section anchor below — the alert's `runbook` field links
here. Procedures marked **[owner]** need Cloudflare account access and
cannot be executed by CI or the sandbox.

## Quick reference

| Signal | Where | Notes |
|--------|-------|-------|
| Alert feed | `GET /admin/alerts` (admin token) | stateless evaluation of 1h + 24h windows; poll-consumable |
| Metrics | `GET /admin/metrics?window=1h\|24h\|7d` | same derivation, full snapshot |
| Service status | `GET /status` | `active` reflects the `STATUS_ACTIVE` deploy var |
| Structured logs | `wrangler tail --format pretty` **[owner]** | request ids + colo + status; the API itself never logs secrets (pinned by api/test/ops.test.ts hygiene scan) |
| Chaos regression | `cd api && bun test test/chaos.test.ts` | DB/blob/signer/node faults asserted on every push |
| Load check | `cd api && bun run tools/loadtest.ts 500 10` | in-process numbers; see §load |

## Alert response procedures

### server-errors-1h <a id="server-errors-1h"></a>

**Meaning:** ≥10 `server_error` events in 1h (ALERT_THRESHOLDS). Includes
signing failures — they surface as thrown errors.

1. `GET /admin/metrics?window=1h` → `server_errors.by_detail` names the top
   error classes (`bundle-missing` = blob store trouble; `OperationError` =
   DB trouble; anything else = handler exception, match against a recent
   deploy).
2. `wrangler tail` **[owner]** for live request ids and stack traces of new
   occurrences.
3. If the detail is `bundle-missing`: check the R2 bucket/namespace — the
   script version row points at a `blob_ref` that the store cannot serve.
   Re-upload the blob or roll the script version back
   (`POST /admin/scripts/:id/versions` with the previous build, then
   activate it).
4. If DB-shaped: Cloudflare status page for D1; if regional, failover is
   automatic — watch that the error rate recovers.

### tamper-spike-1h <a id="tamper-spike-1h"></a>

**Meaning:** ≥20 (warning) / ≥100 (critical) tamper events in 1h.
`by_detail` separates `invalid-key-lockout` (brute force, expected under
attack) from `client:<check>` (M7 §11 environment-check failures — real
tampered clients).

1. Lockout storms: no action unless the volume threatens the error budget —
   the escalating lockout (5/10min per IP hash) is the control.
2. `client:*` clusters: pull the key ids from events (`key_id` column),
   cross-reference `/admin/abuse-scores`, and revoke or blacklist via the
   admin API if the pattern says a distributed tool.

### auth-fail-spike-1h <a id="auth-fail-spike-1h"></a>

**Meaning:** ≥200 validate_fail in 1h AND fail ratio ≥ 0.5 — brute-force
shape. `failure_reasons` in the metrics snapshot names the top details.

1. `not-found`/`checksum` dominated → credential stuffing. Lockouts are
   already engaging; consider a temporary WAF rate-limit rule on
   `/check_key` and `/auth/:id/init` **[owner]** (doc §18 per-IP limits).
2. `hwid` dominated → one key shared widely; see hwid-churn-7d.
3. `loader-version`/`init-build` dominated → NOT an attack; a loader
   release mismatch. See versioned-API gate ops below.

### error-budget-24h <a id="error-budget-24h"></a>

**Meaning:** ≥500 auth attempts in 24h with fail ratio ≥ 5% (the v1 error
budget). Sustained service-quality problem, not a spike.

1. Identify the dominant failure class from the 24h `failure_reasons`.
2. If genuine user-facing failures (e.g. `hwid` after an executor update
   changed identity headers — D10): raise a `reset-hwid` batch or fix the
   D10 header list; communicate.
3. Track recovery: the alert clears when the 24h ratio drops below 5%.

### free-bypass-spike-1h <a id="free-bypass-spike-1h"></a>

**Meaning:** ≥30 free_bypass events in 1h — someone is scripting the
free-key flow (§14 anti-bypass surfaces are rejecting them).

1. No service action needed — the controls (rotating tokens, HMAC step
   secrets, min-time, fingerprint cooldowns) are doing their job.
2. If the volume is abusive, tighten `FreeFlowConfig` limits
   (deploy-time vars) and/or add the fingerprint pattern to the dashboard
   watchlist. Escalation to WAF rules only if D1 write volume matters.

### webhook-failures-24h <a id="webhook-failures-24h"></a>

**Meaning:** ≥10 rejected/failed payment webhooks in 24h.
`payments.by_detail` separates `bad-signature:*` (secret mismatch or an
attacker) from mapping problems (`no-product-ref`, `no-product-mapping`).

1. `bad-signature` after a provider rotation → the provider's new signing
   secret is not in `PAYMENTS_WEBHOOK_SECRETS` for that provider. Add the
   new secret alongside the old (the list exists precisely for the
   dual-secret window), then remove the old one after 24h. **[owner]**
2. Mapping problems → fix the product mapping via
   `POST /admin/payments/products`; the events carry the productRef.
3. Provider retry storms cannot happen for unknown types (200-ignored,
   D-M10-3) — a high count means real failures.

### hwid-churn-7d <a id="hwid-churn-7d"></a>

**Meaning:** any key with ≥5 distinct session HWIDs in 7d — shared key
distribution. The metrics `hwid_churn.rows` lists offenders with their
`hwid_resets` history.

1. Correlate with `/admin/leak/lookup` for the key — a leak trail turns
   this into a revoke + blacklist decision (RUNBOOK §leak flow).
2. Otherwise message the owner (discord_id on the key) before revoking;
   repeat offenders with `hwid_resets` already > 0 → revoke.

### nodes-degraded <a id="nodes-degraded"></a>

**Meaning:** active nodes < 2 (warning) or 0 (critical) in the `nodes`
table. The multi-hostname setup (doc §19) exists so one blocked domain
does not stop the service.

1. Check why the row went inactive: `GET /admin/audit?limit=50` shows the
   admin action, if any (`admin.node.*`).
2. Real hostname blocked/down: register a replacement hostname first
   (`POST /admin/nodes`), verify `GET /sync` lists both, then deactivate
   the dead one. Loaders retry across the list.
3. DNS/CF side: the hostname must be proxied through Cloudflare with the
   Worker route attached **[owner]**.

### protocol-inactive <a id="protocol-inactive"></a>

**Meaning:** zero active rows in `protocol_versions` — the min-loader gate
has nothing to enforce; check_key/auth degrade (gate reads no minimum).

1. Immediate: `POST /admin/protocol-versions` re-activating the latest
   version row (audit-log the action).
2. Root-cause why it was deactivated — this should be a two-person
   operation per §18 admin hygiene.

### sessions-stalled-1h <a id="sessions-stalled-1h"></a>

**Meaning:** zero `validate_ok` in 1h while failures exist — service-up-
but-rejecting (worst user-facing state: loaders get errors, not silence).

1. `GET /admin/metrics?window=1h` → which failure detail is eating
   everything.
2. Check the last deploy: `wrangler deployments list` **[owner]**; roll
   back if the correlation is tight.
3. If STATUS_ACTIVE was flipped off intentionally, /status says so and
   this alert is expected during the maintenance window — mute it at the
   poller (the bell/bot), not in code.

## Outage plan (doc §19 "status page and an outage plan")

When the API is unreachable the loader does not run the script — fail-closed
by design (M3 contract; no partial loads — pinned by chaos tests).

1. **Detect:** poller (dashboard bell / bot /admin/alerts) or CF health
   check **[owner]**.
2. **Communicate:** flip the status page; `STATUS_ACTIVE=false` makes
   `/status` report `active:false` so tooling can show a maintenance state
   (deploy-time env var — D-M12-8: flipped via CF dashboard/wrangler var
   + redeploy, NOT a runtime endpoint).
3. **Restore order:** CF incident? wait. DB down? D1 incidents resolve
   regionally; verify with a direct `wrangler d1 execute ... SELECT 1`
   **[owner]**. Bad deploy? `wrangler rollback` **[owner]**.
4. **Verify:** `GET /status` 200 + `GET /admin/alerts` empty (or only
   expected alerts), then a real `POST /check_key` with a test key.
5. **Post-incident:** events from the window (`server_error` details) go
   into the incident doc; adjust thresholds only via DECISIONS-M12 change.

## Backups and DR (doc §19 "Daily backups with retention")

- **Daily job (cron on the owner workstation):**
  `tools/ops/backup.sh --remote <D1_DATABASE_NAME> --out /backups --keep 14`
  (wrangler d1 export; a Worker cannot do cross-database export, D-M12-12).
  Dev/self-host: `--local app.db --out /backups --keep 14` (VACUUM INTO
  snapshot, integrity-checked before it counts, sha256 manifest.log).
- **Tested restores:** at least monthly, restore into a scratch D1/
  sqlite and run the api test suite against it (see VERIFICATION-M12 §B
  for the local-mode restore proof pattern: open the backup read-only,
  count rows, spot-check a key hash lookup).
- **DR:** the repo IS the code recovery source (Public repo + SavedFolder
  mirror); the backup file is the data recovery source. RTO target:
  redeploy Worker + import D1 + flip STATUS_ACTIVE — under 30 min with
  the runbook in hand.

## Secret rotation (doc §18 "rotation procedure")

- `SERVER_PEPPER` — **CAVEAT: rotating it invalidates every stored key
  hash / HWID hash / IP hash** (all peppered). Never rotate on a live DB.
  Procedure: run a migration that re-hashes from plaintext sources you do
  NOT have → impossible. Therefore: pepper rotation = new deployment +
  re-issue keys (communicate, set expiry grace). Practically: treat the
  pepper as a lifetime secret; its exposure instead triggers mass key
  reissue.
- `PROJECT_SIGNING_KEYS` — per-project signing keypairs. The dual-window
  pattern (doc §18): deploy with BOTH old and new keys in the list
  (`bundleSignerFor` selects by signingKeyId), let sessions drain (TTL),
  then remove the old key. Verification key rotation on the client side
  rides the loader update gate (`UPDATE_REQUIRED`).
- Webhook secrets — see webhook-failures-24h above (list-based dual
  window, same pattern).
- Admin tokens — `adm_<id>.<secret>`; rotate by inserting a new secret
  hash for the admin row + dropping the old (the M1 owner flow).

## Versioned-API gate ops (doc §19 UPDATE_REQUIRED)

- Bump flow: add the new `protocol_versions` row (active), deploy the new
  handler, THEN deactivate the old row once loader adoption (metrics:
  `update_required` counter) reaches ~0. Never deactivate all rows
  (protocol-inactive alert guards this).

## Multi-hostname nodes

- Minimum two hostnames behind Cloudflare (nodes-degraded warning guards
  the table; the DNS/CF wiring is owner config **[owner]**). Register/
  deactivate via the admin API so the audit trail matches /sync output.

## Load (doc §19 "load test before launch")

- In-repo: `cd api && bun run tools/loadtest.ts 500 10` — in-process
  dispatch numbers (router+handler+SQL; no network/edge/D1-RPC). Baseline
  recorded in api/VERIFICATION-M12.md. Regressions >2× on any op block a
  release.
- Before public launch **[owner]**: a k6/CF load test against a staging
  deployment with real D1-over-RPC — the in-process numbers cannot
  substitute for edge latency under TLS+RPC overhead.

## Logging (doc §19 "structured logs with request ids")

- Workers-native: `wrangler tail --format json` carries per-request ids,
  colo, method/path/status. The API adds no console logging (hygiene test
  pins it); its diagnostics live in the `events` table (secret-free,
  detail strings are masked internal codes).

## Latency + CDN ratio (NOT in v1 — D-M12-4)

- Auth latency distribution and init-file CDN hit ratio need per-request
  instrumentation the tables don't carry. Recommended: Workers Analytics
  Engine `writeDataPoint` (binding + cost = owner decision), or CF
  dashboard cache analytics for the CDN ratio. Revisit trigger: first
  real-traffic latency complaints.
