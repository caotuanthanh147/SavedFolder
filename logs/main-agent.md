
---
## 2026-10-10 session 2 — big-project round: SAC3 cleanup + M1 session 1

- User order: "next, it's not a game, this is a big project so I may run
  this a several times for serveral days even and clean up the github, you
  guys leave several unused files there". Public 923cb8b/2a56aa9 = doc.md
  v2 (999 lines, Self-Hosted Lua Script Licensing & Protection Platform,
  14 modules) + HTTPSpy_1791633846.txt (Luarmor capture, clean-room source).
- Rule 19/18: guide + ONBOARDING reread (headers + protocol sections);
  cold-started after sandbox reset (token re-wired silently).
- SAC3 (user order): 36 unused files removed from working tree — 23 stale
  msgs (closed FNAF/PST/cat rounds, handled inbox), 7 section/layer build
  intermediates, 4 qa_load one-offs, 2 closed-round zips (SCP Incremental,
  tdref — history retains). worklog.md summary refreshed to 2026-10-10
  state; changelog entry. Canonical scripts/harnesses/analyses untouched.
  Commit 08806b3, ls-remote verified.
- glm1 opened the round (ac451f) and claimed M3 (Lua SDK+crypto) — my
  natural first pick taken; claimed **LP1-M1 API core** (a52b6e2) instead.
- Research log BEFORE code (doc mandate): 6+ sources actually opened via
  web-reader (Workers limits, D1 limits, WebCrypto — Ed25519/X25519/HKDF
  native ✓, nodejs compat default-on, Durable Objects strongly consistent
  GA, Luarmor public docs user-facing-only clean-room) + RFC 4231/5869
  fetched for exact HMAC/HKDF vectors. api/RESEARCH-M1.md.
- M1 session 1 BUILT (Public 35a8772): zero-dep TS core — contracts
  (codes/canonical JSON/base64url), WebCrypto layer (SHA-256/HMAC/Ed25519
  sign+verify/HKDF), keys (base32 25+1 checksum format, pepper hash,
  per-project HWID salt via HMAC), D1+SQLite adapters (doc §6 schema
  verbatim as the single source), state interfaces + memory impls, DO
  classes (hit/blocked sliding window + alarm sweep nonces), gate flow
  (x-ts window/nonce/proof/60-per-min-IP/16KB cap), check_key full matrix,
  admin keys API (create/bulk/patch/revoke/reset-hwid cooldown+cap+quota,
  audit_log every mutation), table router, Workers entry. 59/59 bun tests
  (incl. RFC known-answer + x-sig verify + replay + lockout + HWID race
  via conditional UPDATE + monthly cap + reseller quota) + tsc strict 0.
- Harness caught real bugs pre-delivery (the discipline works): route
  handler signature mismatch (args-object vs tuple), quota counting
  create-calls instead of keys, dead lockout event path, utf8/b64url
  import mixups.
- M2 landed in parallel (glm3 50dfbc3) — cross-checked vs DOC_SCHEMA_SQL:
  compatible (STRICT + verbatim columns; index names differ, cosmetic).
- Open: M1 session 2 (auth init/payload handshake + ChaCha20-Poly1305 TS +
  heartbeat + rest of admin surface); M3 contracts/ from glm1 pending —
  cross-implementation tests against Lua when it lands.
