# CCP-M10 — Contract Change Proposals from module M10

Filed 2026-10-10 by main-agent (author of M1, M9, M10, M11). Per doc.md "Decision
authority" Tier 3: the current contract stands in the main code; the patches
below are additive and clearly marked. The owner may accept or reject each.

---

## CCP-4 — orders / payment_events / payment_products tables for payments

**Contract and section affected:** doc.md §6 data model; §17 "store the order reference".

**Problem:** §17 requires storing order references and reconciling provider orders against issued keys, but the §6 schema has no orders table. Without it, payments cannot record what was paid, which key an order produced, or whether it was refunded.

**Proposed change:** three additive tables (already M10-applied as `CREATE TABLE IF NOT EXISTS` in `api/src/payments.ts` — `PAYMENTS_SCHEMA_SQL` — the same pattern CCP-3's `dash_totp` used pending ruling):

| Table | Purpose | Key constraint |
|---|---|---|
| `orders` | provider order → issued key (order reference, buyer discord/email, amount_minor, currency, status paid/refunded/disputed) | `UNIQUE(provider, provider_order_id)` — a provider order issues exactly one key |
| `payment_events` | the idempotency gate (at-least-once delivery; `outcome` records issued/duplicate/ignored/refunded/disputed) | `PRIMARY KEY (provider, event_id)` |
| `payment_products` | provider product ref → project/tier/days/scripts entitlement mapping, `refund_blacklists` flag | `UNIQUE(provider, product_ref)` |

**Impact:** M2 (three tables in a migration when accepted), M10 (owns them), M8 (bot `/stats` can read orders), M12 (webhook failure alerts join payment_events).

**Migration:** additive tables only; zero backfill; M10-applied today so no coordination is blocking.

**Risk if not changed:** order state lives in a module-private table indefinitely; reconciliation becomes best-effort.

---

## CCP-5 — admin read/mint endpoints for Users, Resellers, Payments pages

**Contract and section affected:** doc.md §16 "Admin API" endpoint table (extends CCP-2).

**Problem:** §16's dashboard page list requires Users (Discord link, HWID and session history) and Resellers pages, and M10 needs admin surfaces for orders/products/reconciliation — the endpoint table defines none of them.

**Proposed change (implemented in `api/src/adminread.ts`, `api/src/admin.ts`, `api/src/payments.ts`):

| Endpoint | Returns |
|---|---|
| `GET /admin/users?q=` | end-user identity aggregation (discord-first, roblox fallback) with key counts, active keys, HWID bindings, executions, first/last seen |
| `POST /admin/resellers` | owner-only: mint a reseller admin (adm_<id>.<secret> per owner Q2; plaintext once; only sha256(secret) stored) |
| `GET /admin/payments/orders` | order rows (reseller role also allowed, like /admin/keys) |
| `GET /admin/payments/products` | product mapping rows |
| `POST /admin/payments/products` | upsert a product mapping (validated: provider, project, tier ∈ paid/lifetime/reseller, days 1..3650, lifetime⇒days null) |
| `POST /admin/payments/reconcile` | §17 reconciliation report (see below) |

**Impact:** M11 (Users/Resellers/Payments pages), M8 (bot `/mykeys`, `/stats` can reuse both /admin/users aggregation and orders listing).

**Migration:** none — additive routes.

**Risk if not changed:** dashboard pages stay unimplementable against the contract API; module owners keep inventing private endpoints that drift.

---

## Notes

- The webhook route `POST /webhooks/payments/:provider` is **not** a CCP: §5.3's public-endpoint lane already covers provider callbacks, and §17 explicitly specifies the webhook. Providers implemented: `stripe` (Stripe-Signature t=/v1= scheme per RESEARCH-M10) and `custom` (dev/test). Adding a provider = one `ProviderVerifier` implementation + event-type map.
- Reconciliation without a provider API configured reports local drift classes only and says `provider_cross_check: "not-configured"` (honest, per §22.1).
