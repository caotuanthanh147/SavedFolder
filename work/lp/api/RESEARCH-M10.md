# RESEARCH-M10 — Payments and webhooks (Module M10)

Research completed BEFORE code, per doc.md READ FIRST. All sources below were returned by live web_search with dates, on 2026-10-10 (this session). SavedFolder TASKS claim e24645d was pushed before this research + code.

## Research Log

| Topic | Source URL | Version / date | Key finding | Used for |
|---|---|---|---|---|
| Stripe webhook signature scheme (authoritative) | https://docs.stripe.com/webhooks (via web_search result) | opened 2026-10-10 | Stripe signs webhooks with HMAC-SHA256; header `Stripe-Signature: t=<unix>,v1=<hex>`; signed payload = `${t}.${rawBody}`; Stripe libraries default to a **5-minute tolerance** between `t` and current time | D6: signature verifier reference implementation |
| Stripe signature format cross-check | https://webhooks.fyi (spec catalog) | 2026 | Confirms: header `Stripe-Signature`, hash sha256, hex encoding, format `t=timestamp, v1=hash`; multiple `v1` entries may appear (one per secret during rotation) — verifier should accept any valid v1 | Multi-secret rotation window (doc §18 signing-key rotation pattern) |
| Downgrade protection | forum discussion via web_search (bubble.io plugin request) | May 13, 2024 | "To prevent downgrade attacks, ignore all schemes" other than the expected HMAC entries | Verifier parses only `t=` and `v1=` fields, ignores everything else |
| Refund / dispute / completion events | https://docs.stripe.com webhooks events + gist stripe-events.ts via web_search | 2026 | Event vocabulary: `checkout.session.completed` (purchase confirmed), `charge.refunded` (refund), `charge.dispute.created` (chargeback opened), `charge.dispute.closed` (resolved) | D6: event mapping table |
| Provider delivery semantics | https://dev.to "Stripe Webhooks: Handle Payment Events Without Losing" + webhooker.eu | Apr 7, 2026 / Sep 11, 2026 | "Stripe retries failed webhooks. Your handler must be safe to be called multiple times with the same event" — **at-least-once delivery** is the provider norm | Idempotency requirement (doc §17 line 1) |
| Webhook idempotency patterns | https://hookdeck.com "How to Implement Webhook Idempotency" | 2026 | Store the processed event id with a **unique constraint**; on conflict, skip re-processing and return the original outcome (200) | processed-event gate implementation |
| Event id uniqueness caveat | community.hubspot.com via web_search | Mar 29, 2025 | "eventId is not guaranteed to be unique [across redeliveries]. developers should prepare for the possibility of duplicate eventIds" | Gate on (provider, event_id) pair, not event_id alone |
| Idempotency-key scope | trykitchenhub.com POS dedupe guide + hooklistener.com "Webhook Idempotency 2026" | Jun 10, 2026 | "store a stable key such as the [provider event id]" with a DB unique index; dedupe layer before business logic | orders.processed_events UNIQUE(provider, event_id) |
| Reconciliation (doc §17 line 4) | hookdeck.com + Stripe docs (list-all-events / export patterns) | 2026 | Reconciliation = compare the provider's order list (via provider API or event log) against locally issued keys; flag: paid-but-no-key, refunded-but-active, key-without-order | /admin/payments/reconcile report shape |
| Fees / regional restrictions (doc M10 research list) | Stripe docs via web_search | 2026 | Provider fee structures and regional availability are account-level concerns outside the webhook contract; the platform only needs amount/currency passthrough + product mapping | D6: fees noted as NOT-RUN (no live account); amount recorded verbatim from event |
| Raw-body requirement | yepcode.io "Validate Stripe Webhook Signatures using request raw body" | Sep 8, 2025 | Signature is computed over the **raw body bytes**, not re-serialized JSON — re-serialization breaks verification | Verifier takes raw bytes (api router already carries bodyBytes) |

## Options compared

**D6 — payment provider + webhook format**
- A) Hard-require Stripe (or PayPal) with their SDK: rejected — sandbox has no live provider account; SDK would be dead code we cannot verify against the real service (violates §22.1 honesty).
- B) **Provider-agnostic verifier interface with two implementations** — `stripe` (reference: `Stripe-Signature` t=/v1= HMAC-SHA256 hex over `${t}.${rawBody}`, 5-min default tolerance, multi-v1 rotation) and `custom` (dev/test: `X-Event-Id` + `X-Signature: hex HMAC-SHA256(rawBody, secret)`): **chosen** — mirrors the D5 resolution pattern from M9 (provider-agnostic + custom dev provider), lets tests prove the security properties with real crypto, and adding a third provider later is one interface impl.
- C) Shared-secret plain digest with no timestamp: rejected — replay window unlimited (Stripe's own t= exists for this).

**Idempotency model**
- A) Check "order with same provider_order_id exists" only: insufficient — different event types (payment vs refund) share an order id.
- B) **UNIQUE(provider, event_id) processed-event gate**: insert-first, process-second — a duplicate insert conflict short-circuits to the stored outcome: **chosen** — at-least-once delivery handled at the door, per hookdeck/hubspot findings.

**Refund/chargeback behavior (doc §17 "revoke the key and optionally blacklist")**
- A) Always blacklist on refund: too aggressive — friendly refunds would brick the buyer's HWID forever.
- B) **Revoke always; blacklist only when the product row sets `refund_blacklists = 1`** (default 0) or the event is a dispute (chargebacks are fraud-shaped): **chosen** — operator-controllable, matches doc's "optionally".

**Key issuance on confirmed payment**
- Reuse the M9 tier-key issuance machinery (full keys row + key_scripts entitlements + audit entry) with `created_by = "m10:<provider>"`, tier/days/scripts from a product mapping row — same pattern as free-flow issuance, one code path, tested through the REAL check_key in tests.

**Product mapping storage**
- A) Hardcode products in env: no multi-script mapping, no dashboard view.
- B) **`payment_products` table** (provider, product_ref → project_id, tier, days, script ids, refund_blacklists): **chosen** — additive M10-applied table, CCP-4 filed for the §6 schema.

**Order reference storage (doc §17 "store the order reference")**
- **`orders` table** (provider, provider_order_id, provider_event_id, product_ref, key_id, discord_id/email delivery target, amount_minor, currency, status) + processed-event gate table: additive M10-applied tables; CCP-4 filed (§6 has no orders table).

## Fees / regional restrictions (doc M10 research list, resolved as scope notes)

- Fees: the platform records `amount_minor` + `currency` verbatim from the event; net-after-fee computation belongs to the provider dashboard, not the licensing API. NOT-RUN against a live account.
- Regional restrictions: provider-side (Stripe Radar / PayPal country lists). The webhook path is region-agnostic. Nothing to implement in M10.
