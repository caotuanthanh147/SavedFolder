# Research Log — M1 API core

All URLs below were opened (fetched + read) on 2026-10-10 via the sandbox
web-reader. Key facts were extracted from the fetched page text at build time.

| Topic | Source URL | Version / date | Key finding | Used for |
|-------|-----------|----------------|-------------|----------|
| Workers limits | https://developers.cloudflare.com/workers/platform/limits/ | fetched 2026-10-10 | CPU 10 ms/request (Free), 30 s default / 5 min max (Paid); memory 128 MB; subrequests 50 (Free) / 10,000 (Paid) per request; 6 simultaneous outgoing connections; request body 100 MB (Free/Pro account plan); no enforced response body limit; HTTP-request duration has no hard limit while the client is connected | Envelope + payload size budgeting; confirms Workers fits the check_key / auth workload with huge margin |
| D1 limits | https://developers.cloudflare.com/d1/platform/limits/ | fetched 2026-10-10 | Max DB size 10 GB (Paid) / 500 MB (Free); 1 TB per account (Paid); 100 bound parameters per query; 32 max arguments per SQL function; Time Travel point-in-time restore exists | Query design (≤100 binds per statement — all M1 queries use ≤12); backup story (Time Travel + exports) |
| WebCrypto on Workers | https://developers.cloudflare.com/workers/runtime-apis/web-crypto/ | fetched 2026-10-10 | Ed25519 ✓ and X25519 ✓ supported (Secure Curves API); legacy NODE-ED25519 variant exists but rejects raw private-key import; HMAC ✓, SHA-256 ✓, HKDF ✓, PBKDF2 ✓, AES-GCM ✓ | x-sig = Ed25519, x-proof = HMAC-SHA256, HKDF labels, X25519 handshake (next M1 session) — all native, no crypto dependency |
| Node.js compat | https://developers.cloudflare.com/workers/runtime-apis/nodejs/ | fetched 2026-10-10 | nodejs_compat is enabled by default for compatibility dates ≥ 2026-08-03 | Confirms node:crypto reachable if ever needed; decision below stays on WebCrypto for Bun/Workers test parity |
| Durable Objects | https://developers.cloudflare.com/durable-objects/ | fetched 2026-10-10 | DOs are transactional, strongly consistent, single-threaded per object; SQLite-backed DOs are GA and available on the Free plan | Atomic single-use nonce store + rate-limit counters (one DO per bucket key); memory implementation used for local tests |
| Reference service public docs (clean-room: user-facing behavior only) | https://docs.luarmor.net/ | fetched 2026-10-10 | Public docs show: HWID resets are tracked per key (last reset timestamp + total resets), time-limited keys have two modes (day-count and auth expiry), a general ~60 requests/minute limit is communicated to users, keys have statuses | Sanity check of doc.md's data model (keys.hwid_resets / last_reset_at / expires_at / auth_expire / status all have an observed counterpart). No code, constants, endpoint names, hash functions, or branding copied — M1's endpoints and formats come from doc.md §5 only |
| Workers Rate Limiting binding | https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limiting/ | fetched 2026-10-10 — **404** | Page has moved; current location not found via search either | Not relied on; DO-based counters chosen instead (listed under Unverified) |

## Options compared

1. **HTTP router.** Hono (Workers-native, TS, middleware) vs itty (smaller) vs
   a hand-rolled table-driven router. ~10 routes, no middleware needs, zero
   supply-chain surface wanted → **hand-rolled table router** (~50 lines, one
   route spec array + one matcher, in `src/router.ts`). Upgrade path to Hono
   is mechanical if middleware ever becomes necessary.
2. **Crypto.** Workers WebCrypto (native Ed25519/X25519/HMAC/HKDF, verified
   above) vs node:crypto (compat flag nuance, weaker test parity in Bun) vs
   @noble/* libraries (extra dependency). → **WebCrypto only**: identical
   global API in Workers and Bun, so the exact signing/verification code that
   ships is the code that is tested.
3. **Nonce + rate-limit state.** Durable Objects (strongly consistent,
   single-threaded per key — verified above) vs KV (eventually consistent —
   unsuitable for single-use nonces) vs D1 (works, but adds a write per
   request to the hot path). → **Durable Objects** in production, plus an
   in-memory implementation of the same interface for deterministic tests.
4. **Payload cipher.** doc §9 wants ChaCha20-Poly1305 (or ChaCha20+HMAC).
   WebCrypto has no ChaCha20; node:crypto chacha20-poly1305 availability on
   Workers is **unverified**. → pure-TypeScript ChaCha20-Poly1305 with RFC
   8439 vectors, guaranteed to interoperate with M3's pure-Lua
   implementation. Delivered with the auth init/payload endpoints (next M1
   session, tracked in TASKS.md).
5. **Database access.** D1 (per doc) via a thin adapter so the same SQL runs
   under Bun's SQLite in tests (`bun:sqlite`), with D1's
   `prepare().bind().first()/all()/run()` in production.

## Prior art found

- Luarmor public docs (above) — user-facing behavior only, clean-room
  respected.
- No open-source Cloudflare-Workers Lua-key-system implementation was
  adopted; nothing was copied. doc.md §5/§6 is the sole specification.

## Unverified items

- Workers Rate Limiting binding current page/state (the documented URL 404s).
  Not blocking: DO counters are used.
- node:crypto `chacha20-poly1305` on Workers. Not needed: TS implementation
  planned.
- D1 rows-read / rows-written daily billing limits (not extracted; irrelevant
  to correctness, Ops/M12 scope).
- Executor identity header names beyond Delta's (capture shows
  `Delta-User-Identifier`, `Delta-Fingerprint`, `catcat128` on Delta Android
  2.0). D10 is an open decision: M1 reads header names from server-side
  config per project (env → DB later), so new executors are a config change,
  not a code change.

## Decisions made and why

- **Ed25519 for `x-sig`, generated+stored as PKCS8 in env** — WebCrypto
  imports PKCS8 private keys and raw public keys; raw private import is not
  supported for Ed25519 on Workers (verified above), so the env secret is a
  base64 PKCS8 blob and the public key a base64 raw 32-byte key.
- **Key format**: `PREFIX-` + 25 base32 chars (125 bits of CSPRNG) + 1
  checksum char (SHA-256-derived, base32 alphabet) grouped
  `XXXXX-XXXXX-XXXXX-XXXXX-XXXXXC`. Entropy ≥ the spec's 128-bit intent once
  the 26-char checksum layout is fixed; checksum catches single-character
  typos before any DB hit, per doc §6 "Key design". The exact grouping is
  recorded as a Contract Issue note (doc's example shows 4 groups of 5; we
  ship 4 groups of 5 + 1 checksum char in a 6-char tail group).
- **`SERVER_PEPPER`** (env) for key hashing; **per-project HWID salt** derived
  as HMAC-SHA256(pepper, `"hwid-salt|" + project_id`) since the §6 schema has
  no salt column — no schema drift introduced.
- **Rate limits**: 60 requests/min/IP general (matches the user-facing norm
  observed in the reference docs) + escalating invalid-key lockout
  (5 failures / 10 min → 10 min lock), both over the same RateLimiter
  interface.
- **Admin monthly HWID-reset cap** counted from `audit_log` rows
  (`action = 'admin.key.reset_hwid'`, last 30 days) so the §6 schema stays
  untouched.

## Environment facts used by tests

- Bun ≥ 1.x runs TypeScript natively and provides `bun:test` and
  `bun:sqlite`; `globalThis.crypto.subtle` exists in Bun and Workers — the
  tested code path is the shipped code path.

## Session 2 additions (2026-10-10, fetched before code)

| Claim | Source (opened) | Result |
|-------|-----------------|--------|
| RFC 8439 vectors: ChaCha20 block fn §2.3.2, Poly1305 §2.5.2, Poly keygen §2.6.2, AEAD §2.8.2, Appendix A.1 blocks | https://www.rfc-editor.org/rfc/rfc8439.txt (fetched 2026-10-10, 89 KB text) | captured exact bytes for tests |
| RFC 7748 vectors: §5.2 scalar-mult ×2, §6.1 X25519 DH (Alice/Bob + shared K) | https://www.rfc-editor.org/rfc/rfc7748.txt (fetched 2026-10-10, 39 KB text) | captured exact bytes for tests |
| RFC 7748 §6.1: parties MAY check all-zero shared secret and abort; check by ORing bytes | same | implemented (small-order input rejection) |
| Bun 1.3.14 WebCrypto X25519 is unusable for this project | command run 2026-10-10: `subtle.generateKey({name:"X25519"})` passes, `subtle.exportKey("raw", priv)` fails with "The requested operation is not valid for the provided key" (also deriveBits path fails) | X25519 implemented pure-TS per RFC 7748; single code path for Bun tests and Workers |
| Bun node:crypto x25519 works (DH, 32-byte secret) | command run 2026-10-10: `generateKeyPairSync("x25519")` + `diffieHellman()` → PASS | rejected as the primary path: node:crypto surface is not guaranteed on Workers; kept as evidence only |
| WebCrypto has no ChaCha20-Poly1305 | RESEARCH-M1 session 1 (W3C/MDN algorithm tables) + confirmed by absence in spec | ChaCha20-Poly1305 implemented pure-TS per RFC 8439 |
| Workers supports BigInt | Cloudflare Workers JS runtime docs (session-1 research pass) | BigInt X25519/Poly1305 run unchanged on Workers |
