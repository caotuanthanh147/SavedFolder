# VERIFICATION-M9-M11 — §22.1 transcript

Author: main-agent. Date: 2026-10-10. Environment: sandbox (bun 1.3.14, node 24.21.0, next 16.4.0). All commands run in the delivered working tree.

## Module M9 (free-key flow) — tests

Command: `cd api && bun test` (full suite incl. M1 regression)

```
163 pass
 0 fail
764 expect() calls
Ran 163 tests across 13 files. [6.93s]
```

New M9/M11 test files (external-source derivation):
- `test/freekey.test.ts` — 15 tests; oracle = doc.md §14 clauses (each §14.3/§14.5 verification rule maps to a test) + cross-module check via the REAL `handleCheckKey` (the claimed free key validates KEY_VALID through M1's handler).
- `test/totp.test.ts` — 11 tests; oracle = RFC 6238 Appendix B Table 1 official vectors (8-digit SHA1, T=59/1111111109/1111111111/1234567890/2000000000/20000000000) + RFC 4648 base32.

Covered failure paths: token replay, skipped steps, fast completion (< min_seconds), wrong step secret, cooldown re-entry (same fingerprint), multi-account (same IP, different HWID → distinct fingerprints allowed, identical fingerprint blocked), IP-switch mid-flow (fingerprint mismatch), double claim, unknown slug, per-IP start limit (6th start in a minute), malformed checkpoint config (SERVER_ERROR), timing-mode provider link, envelope x-sig verification on /free responses.

NOT-RUN list (honest limits): real Linkvertise/Lootlabs server-side verification (needs creator accounts — owner-only); real Workers deployment; real Discord OAuth exchange (needs app credentials — routes are wired and state-checked, runtime-gated); load numbers.

## Typecheck

Command: `cd api && bunx tsc --noEmit` (excludes index.ts/durable.ts, Workers-only types, unchanged from M1)

```
(no output — exit 0)
```

## Module M11 (dashboard) — lint + runtime

Command: `cd <sandbox root> && bun run lint`

```
$ eslint
(exit 0)
```

Command: `bun run dev` (next dev, Turbopack) + curl/browser session:

```
GET /                     → 200 (page renders: shell, nav, footer)
GET /api/dash/info        → 200 {dev_mode, project, free limits}
GET /api/gw/sync          → 200 {"st":…,"nodes":[…],"colo":"DASH"}          (real M1 endpoint)
GET /api/gw/admin/analytics/overview → 200 {keys_active:4,…}               (real M1 endpoint)
GET /api/gw/admin/keys    → 200 rows[…]                                    (CCP-2 endpoint)
GET /api/gw/admin/scripts → 200 rows[…] (versions, game routing)
GET /api/gw/admin/audit   → 200 entries[…]
POST /api/gw/free/start   → 200 KEY_VALID {token, step 1/2, url with embedded secret}
POST /api/gw/free/step    → 200 KEY_VALID (after 8s min time) / BAD_REQUEST (before min time — bypass logged)
POST /api/gw/free/claim   → 200 KEY_VALID {key: YURI-…, tier: free}
POST /api/dash/validate-key → 200 KEY_VALID "The provided key is valid."   (real check_key round trip, server-signed proof)
```

Browser (agent-browser) end-to-end session on /:
- Overview renders live analytics cards, node list, protocol versions.
- Keys: 5 seeded rows render; "Create keys" dialog → 3 keys created → plaintext shown once (`3 plaintext keys: YURI-GFMAQ-…`); validate widget POST /api/dash/validate-key → 200 (network log).
- Free-key flow: start → early completion attempt rejected (server min-time) → real completion after timer → checkpoint 2 → claim → `CLAIMED: YURI-NRCKH-ZQZ44-SLGOO-ONBXW-FAMOQF`.
- Audit log: `free-flow claim audited ✓` (create_key action with free-flow actor visible).
- Settings: TOTP enroll → secret + otpauth URI displayed; dev admin token visible only in dev mode.
- Screenshots: /tmp/dash-final.png, /tmp/dash-validate.png (session artifacts).

Sandbox reaper caveat (environmental, not app): the sandbox kills the dev server BETWEEN tool invocations, so browser flows were verified in single-invocation batches; each batch restarted the server. Within every batch the app behaved deterministically.

## Commands to reproduce

```
cd api && bun test && bunx tsc --noEmit
cd dashboard && bun install && bun run lint && bun run dev
# then: open http://localhost:3000/ — Overview renders; Keys create;
# Free-key flow: Start → wait timer → Complete ×2 → Claim → validate the key in Keys.
```
