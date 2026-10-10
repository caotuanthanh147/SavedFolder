# VERIFICATION-M10 (+ M11 session 2) — payments, dashboard Users/Resellers/Payments pages

Module M10 (payments + webhooks, doc §17) + M11 session 2 (Users/Resellers/Payments views, doc §16). Per doc.md §22.1: real commands and outputs, external-derivation statement, honest NOT-RUN list.

## §22.1 Verification transcript

### 1. api/ test suite (bun test)

```
$ cd api && bun test
 206 pass
 0 fail
 924 expect() calls
Ran 206 tests across 15 files. [7.05s]
```

Baseline before this session: 176/176. New: `test/payments.test.ts` — 28 tests + 2 M11 dashboard-endpoint tests. Every §17 row maps to tests:

- **§17 row 1 (webhook verifies provider signature + idempotency)**: stripe t=/v1= HMAC over `${t}.${rawBody}` happy path; rotation window (second secret validates); stale timestamp → 400; tampered body under valid header → 400 (raw-bytes binding); custom bad signature → 400 + nothing processed; header/payload event-id split → 400; malformed JSON → 400 + event row; same event id twice → `duplicate: true`, exactly one key; same order under a NEW event id → duplicate, still one key; per-IP rate limit → 429; no secret configured → 503 provider_disabled (fail closed); unknown provider → 404.
- **§17 row 2 (confirmed payment → create key, assign scripts, store order reference)**: full issue path asserts key row (tier/days from product, created_by `m10:<provider>`), key_scripts entitlements, order row (provider_order_id, amount_minor, currency, discord_id, email, status paid), audit `payment.issue`, and — cross-module — the issued key validates through the REAL `/check_key` handler (KEY_VALID). Lifetime product → null expiry. Unknown product → 200 ignored (no retry storm) + no key. Unknown event type → 200 ignored.
- **§17 row 3 (refunds/chargebacks revoke + optionally blacklist)**: refund revokes, no blacklist when product `refund_blacklists=0`; refund with flag=1 blacklists the discord id with the platform hash formula `sha256(pepper|discord|value)` (verified against admin.ts's exact formula); dispute always blacklists; refund for unknown order → ignored; stripe `charge.refunded` maps through `payment_intent` linkage (charge id ≠ session id — real Stripe events join on payment_intent; fixed during QA).
- **§17 row 4 (reconciliation job)**: report flags refunded-but-active (drift injected via direct SQL), paid-key-missing, orphan m10 keys; audit `admin.payment.reconcile`; provider fetch path (injected fetchImpl) reports `fetched` + order count; provider unreachable → `provider_unreachable` (not thrown).
- **M11 endpoints**: `/admin/users` aggregates discord-first/roblox-fallback identities with per-identity stats + prefix search + reseller-role 403; `/admin/resellers` mints a token matching `^adm_[0-9a-f]{32}\.[A-Za-z0-9_-]{43}$` that authenticates as a reseller (own-keys-only listing = 0), quota stored, owner-only (403 for reseller), bad discord id → 400, audit row.

```
$ cd api && ./node_modules/.bin/tsc --noEmit
(clean exit)
```

Harness-caught bugs (fixed before delivery): `db.first(sql)` missing-params spread crash in 3 test queries; SQLite rejects expressions in compound-SELECT ORDER BY (Users UNION wrapped in outer SELECT); Stripe refund linkage via payment_intent.

### 2. Dashboard lint

```
$ bun run lint
$ eslint
(clean — 0 errors, 0 warnings)
```

### 3. Browser verification (agent-browser; sandbox reaper kills the dev server between invocations — every batch below is a single self-healing invocation: restart server → open → interact → read)

- **Full 12-view walk** (nav: Overview, Keys, Scripts, Users, Resellers, Sessions, Blacklist, Audit log, Payments, Free-key flow, Nodes & protocol, Settings): every view renders its h1 + data; **zero JS errors** (`window.__errs`), zero network failures. Rows: Keys 6 (4 seed + 2 payment keys), Scripts 2, **Users 6** (203040/203041/203042/203043 + roblox 5512345 + 778899 from simulated purchase), **Resellers 2** (owner + seeded reseller), Sessions 2 (newly seeded watermark rows), Audit ≥1, **Payments 2** (seeded paid + refunded orders), Nodes 4.
- **Webhook simulator (real chain)**: "Send signed webhook" → HTTP 200, `outcome: "issued"`, `YURI-…` plaintext shown once in the response panel; orders tab 2 → **3 rows**. "Send tampered signature" → HTTP **400** `{"error":"invalid_signature"}` (verified both via the UI panel and direct POST /api/dash/simulate-webhook with `tamper:true`).
- **Refund flow via simulator**: payment.confirmed on `ord_dup_test_1` → issued; then payment.refunded on the same order → `outcome: refunded, key_revoked: true, blacklisted: false` (product has refund_blacklists=0) — matches D-M10-5.
- **Reconcile**: run → stat tiles 0/0/0 (demo data has no drift — correct), `Provider cross-check: not-configured` line rendered.
- **Reseller minting**: "New reseller" dialog → create → `adm_33ed2b975f5dbc6c…` token displayed once in an emerald card with the sha256-storage note; admins table shows the new row.
- **Users search**: real keyboard typing "20304" → table filters to **4 rows** (203040, 203041, 203042, 203043). API-level check: `/api/gw/admin/users?q=20304` → 4 rows (same). Earlier synthetic-event "failures" were eval artifacts, not product behavior — re-verified with native input events.
- Screenshots: qa-fullpass.png (12-view walk), qa-payments.png (simulator tab), qa-final-users.png, qa-users-search.png (filtered).

### External-derivation statement

- Test data derives only from the module's own code + doc §17 rows. No external service was called: the stripe verifier implements the documented Stripe-Signature scheme (sources in RESEARCH-M10: docs.stripe.com + webhooks.fyi spec catalog), verified against self-computed HMAC vectors — NOT against Stripe's live signature service.
- RFC-independent: no RFC vectors involved in M10 (HMAC-SHA256 machinery already covered by M1/M3 cross-vectors).

### NOT-RUN (honest list)

1. Real Stripe/PayPal webhook delivery (no live provider account; signature scheme implemented from their published docs).
2. Real Workers deployment of the webhook (in-process dispatch only; wrangler deploy = owner/ops).
3. Provider reconciliation against a live provider API (`provider_cross_check: not-configured` path exercised; fetched path exercised with an injected fetchImpl only).
4. Fee computations and regional restrictions (out of scope per DECISIONS-M10 D-M10-9; amount recorded verbatim).
5. DM/email delivery of issued keys (M8 bot / M12 ops territory; the plaintext-once response is the handoff point).
6. Load numbers for the webhook endpoint (rate limit 30/min per IP per provider by default; not load-tested).
7. Concurrency race: two DIFFERENT events for the same order arriving simultaneously (single-isolate D1 serialization assumed; the orders UNIQUE(provider, provider_order_id) constraint backstops, surfacing as SERVER_ERROR + provider retry rather than double-issue).
