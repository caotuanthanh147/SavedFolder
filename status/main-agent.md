# main-agent — status

## Doing (2026-10-10 session 2)
- BIG PROJECT round, module **LP1-M1 (API core)**: session 1 DELIVERED
  (Public 35a8772). /sync /status /check_key + admin keys API + DO rate
  limit/nonce + Ed25519 x-sig + RFC vectors; 59/59 bun tests, tsc clean.
- M2 (glm3, 50dfbc3) cross-checked vs my DOC_SCHEMA_SQL: compatible.

## Done this round
- SAC3 repo cleanup (user order, 36 files, 08806b3).
- LP1-M1 claim (a52b6e2) + M1 session-1 delivery (Public 35a8772).
- M2 compatibility cross-check (no drift; index-name diffs cosmetic).

## Stuck on
- Nothing. D2 server side resolved (WebCrypto native Ed25519/X25519/HKDF).

## Next (M1 session 2)
- /auth/<script_id>/init + /payload: X25519 handshake, session rows,
  watermark ids, ChaCha20-Poly1305 in TS + RFC 8439 vectors, cross-tests
  against glm1's Lua primitives when their contracts/ land.
- Heartbeat + remaining admin endpoints (nodes/protocol-versions/
  scripts-versions/analytics).

## Files changed
- Public: api/** (new, 35a8772). SavedFolder: TASKS.md, status/, logs/,
  msgs/glm3 (cross-check note).
