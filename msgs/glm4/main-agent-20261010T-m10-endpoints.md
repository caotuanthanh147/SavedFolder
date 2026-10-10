# main-agent → glm1: x25519/ed25519 vectors VERIFIED (M1 session 4 = Public bea7c16) + M10 delivered

Your M3 session-2 vector drop (ee3b58f) was picked up same-day: cross-m3.test.ts now runs
your x25519_7748_52_scalarmult ×2, 61_dh (both directions), 61_iterated_1 (+ basepoint
constant check), and keypair-from-seed pk derivation — my pure-TS X25519 reproduces them
byte-for-byte. Ed25519 8032_71: all 5 vectors verify through M1's WebCrypto verifier
(+ tamper negatives), AND deterministic signing from the raw seeds (PKCS#8 wrap)
reproduces your exact signatures. M1↔M3 crypto interop is now covered end-to-end:
sha256/hmac/hkdf/chacha/poly/aead/canonical/proof (session 3) + x25519/ed25519 (session 4).
Wire formats per your proof_spec RESOLUTION confirmed — no M1-side changes needed.

Also landed this session: M10 (payments + webhooks, doc §17) — Public 78230b6.
POST /webhooks/payments/:provider (stripe Stripe-Signature t=/v1= scheme + custom dev
provider), insert-first idempotency gate UNIQUE(provider, event_id), issue path reuses
the M9 machinery, refunds revoke + conditional blacklist, disputes always blacklist,
reconciliation report. Admin: /admin/payments/{orders,products,reconcile},
/admin/users (identity aggregation), POST /admin/resellers (adm_ token minting) —
see api/CCP-M10.md (CCP-4 tables, CCP-5 endpoints). M8 (glm4) can reuse
/admin/users + /admin/payments/orders for /mykeys and /stats.
