# M1 — API core (session 2)

Cloudflare Workers (TypeScript) implementation of the licensing platform's
public + admin API per `doc.md` §5/§6/§8/§16. Research first: see
`RESEARCH-M1.md` (mandatory per doc.md READ FIRST — research log before code).

## Run the tests

```sh
bun install
bun test          # 131 checks, RFC known-answer vectors included
bun run typecheck # tsc --noEmit (strict; Workers-only files excluded, see tsconfig)
```

The tests run the exact shipped code paths: `globalThis.crypto.subtle`
(WebCrypto) is the same API on Workers and Bun, and the SQLite adapter runs
the same SQL that D1 runs in production. Rate limiting and nonce replay use
in-memory implementations of the same interfaces the Durable Objects
implement in production.

## Built (this session)

- `GET /sync` — `{ st, nodes: ["https://..."], colo }` from the `nodes` table
- `GET /status` — `{ active, versions, nodes }` from `protocol_versions` + `nodes`
- `POST /check_key` — full contract flow:
  - gate: `x-ts` ±60 s window, 16-byte single-use `x-nonce`,
    HMAC-SHA256 `x-proof` over `m1-proof-v1|method|path|x-ts|x-nonce|sha256(body)`,
    60 req/min/IP, 16 KB body cap
  - invalid-key lockout: 5 failures/10 min per IP blocks before key lookup
  - key checksum → hash lookup (SHA-256 + server pepper) → status/expiry →
    project/script entitlement → blacklist (key status, HWID, IP) →
    atomic HWID bind-or-match (single conditional UPDATE — no bind race) →
    `KEY_VALID` envelope with `{ note, auth_expire, total_executions }`
  - every envelope response carries `x-ts` + `x-sig` (Ed25519 over
    `code|message|canonical(data)|x-ts`, canonical JSON = sorted keys,
    tight separators)
  - every failure is a known code from §5.4 with a generic message; details
    go to the `events` table
- Admin API (Bearer token → `admins.api_token_hash`):
  - `POST /admin/keys` — one or bulk (≤500), tier/days/note/scripts, plaintext
    shown once, hash-only storage, reseller quota (lifetime keys count),
    audit-logged
  - `PATCH /admin/keys/:id` — extend_days / tier / note, audit-logged
  - `POST /admin/keys/:id/revoke`, `POST /admin/keys/:id/reset-hwid`
    (7-day cooldown + 2/month cap counted from `audit_log`, `hwid_resets`
    counter), audit-logged
  - `GET /admin/audit` — recent entries
- Durable Objects: `RateCounterDO` (hit/blocked sliding window),
  `NonceDO` (single-use with alarm sweep) — deployed via `src/index.ts`,
  not unit-testable locally; the interfaces they implement are fully covered
  by the in-memory tests
- `src/keys.ts` — key generation `PREFIX-XXXXX-XXXXX-XXXXX-XXXXX` + checksum
  char (6-char tail group), base32, per-project HWID salt derivation
- RFC known-answer vectors in CI: SHA-256, HMAC-SHA-256 (RFC 4231 TC1/TC2),
  HKDF-SHA-256 (RFC 5869 A.1)

## Built (session 2)

- Pure-TS crypto, RFC-vector-pinned (`src/x25519.ts`, `src/chacha.ts`):
  X25519 per RFC 7748 (BigInt Montgomery ladder; Bun 1.3.14 WebCrypto cannot
  export/derive X25519 keys — evidence in RESEARCH-M1.md), ChaCha20-Poly1305
  per RFC 8439. 19 vector/property tests: RFC 7748 §5.2 ×2 + §6.1 DH, RFC 8439
  §2.3.2 + A.1 ×3 block vectors, §2.4.2 ciphertext, §2.5.2 Poly1305, §2.6.2
  keygen, §2.8.2 AEAD seal/open/tamper, small-order rejection.
- `POST /auth/<script_id>/init` — the full §8.7-8.8 flow: request gate (same
  as check_key), script lookup, keyless handling, key gate (checksum → hash →
  status → expiry → project/script entitlement → game routing via
  `script_games`), blacklist (key/ip/hwid/roblox_user/discord), invalid-key
  lockout, atomic HWID bind, loader/init-build version gates, X25519
  handshake, HKDF "session-key", session row + unique watermark, sealed
  `payload_ref`, AEAD-encrypted §5.5 response (text/plain base64url wire).
- `POST /auth/<script_id>/payload` — ref unseal (server-only key), session
  revocation/expiry kill checks, version pinning, per-session rate limit
  (5/min), bundle fetch via `BlobStore` (R2 in production, memory in tests),
  HKDF "payload-key", AEAD response, `bundle_sig` = Ed25519 over
  `build_hash | bundle` with the project signing key.
- `POST /auth/<script_id>/heartbeat` — §8.11 kill signal (revoked /
  blacklisted / expired sessions get the matching envelope code; live
  sessions get `KEY_VALID` + `session_expires_at`; no per-beat DB writes).
- Admin session 2 endpoints (all audit-logged, owner/admin roles):
  `POST /admin/nodes` (add/disable auth hostnames), `POST /admin/protocol-versions`
  (register/retire, upsert), `POST /admin/scripts/:id/versions` (upload build,
  optional activate), `POST /admin/scripts/:id/activate` (switch/rollback),
  `POST /admin/blacklist` (§16 gap from session 1 — hwid/ip/roblox_user/discord,
  server-side hashing), `GET /admin/analytics/overview` (24h counts).
- Admin token per owner answer Q2: `adm_<admin id>.<secret>`, 32-byte CSPRNG
  secret base64url (43 chars), only `SHA-256(secret)` stored, constant-time
  compare, id-prefixed lookup. Old whole-token format rejected (clean break).

### Auth wire formats (M3 interop — mirror of DECISIONS-M1.md)

```
init request  body: {v:1, key, build, place_id, game_id, user_id, hello}
              hello = b64url( clientPub(32) | clientNonce(16) )
init response (success, text/plain): b64url( serverPub(32) | serverNonce(16) | ct | tag(16) )
              sessionKey = HKDF-SHA256(ikm = X25519 shared, salt = clientNonce|serverNonce, info = "session-key")
              AEAD nonce = serverNonce[0..12), aad = scriptId-utf8 | serverPub | serverNonce
init response (failure): signed JSON envelope (§5.4 codes)
payload request: {v:1, session_token, payload_ref}   (both opaque b64url)
payload response (success): b64url( nonce(12) | ct | tag(16) )
              payloadKey = HKDF-SHA256(ikm = sessionKey, salt = buildHash(32 raw), info = "payload-key" | watermark(16 raw))
              aad = scriptId-utf8 | sessionId(16 raw); plaintext = {build_hash, bundle, bundle_sig}
              bundle_sig = Ed25519 over buildHash(32 raw) | bundle bytes
heartbeat: {v:1, session_token} → signed envelope
```

`payload_ref` is sealed with a server-only key (`SESSION_SEAL_KEY` env → HKDF)
and carries the session key statelessly — no schema change, no KV (eventual
consistency would break payload reads).

## Not built yet (tracked in TASKS.md LP1-M1)

- loader stub endpoint `/loaders/<script_id>.lua` (M13 lane, needs M1 auth)
- real Workers deployment + DO smoke test (owner/ops lane)
- M3 Lua cross-implementation vectors in `/contracts` (glm1 in flight)

## Workers deployment (env contract)

Bindings: `DB` (D1), `RATE_COUNTER` + `NONCE` (Durable Object namespaces,
classes exported from `src/index.ts`), `BUNDLES` (R2 bucket for script
bundles). Vars/secrets: `SERVER_PEPPER`, `SIGNING_PRIVATE_KEY_B64URL` (PKCS8
base64url — raw private import is not supported for Ed25519 on Workers),
`PROOF_KEY_B64URL` (32 bytes), `EXECUTOR_HWID_HEADERS` (comma list, e.g.
`Delta-User-Identifier,Delta-Fingerprint` — D10: header names are config, not
code), `STATUS_ACTIVE`, `SESSION_TTL_SEC` (default 3600),
`SESSION_SEAL_KEY` (seals payload_refs), `PROJECT_SIGNING_KEYS` (optional
JSON map of per-project bundle signing keys, doc §18).
`wrangler.jsonc` documents the shape; deploy/CI wiring is M12's lane. No
secrets in this repo.

## Integration notes

- **M2**: `db/` migrations must match `DOC_SCHEMA_SQL` in `src/db.ts`
  byte-for-byte (it is doc.md §6 verbatim + the §6 index list). Tests build
  their schema from it directly.
- **M3 (SDK)**: consume `src/contracts.ts` as the canonical-JS reference for
  canonical JSON, base64url (no padding), the code list, and the `x-sig`
  payload layout; key format + checksum from `src/keys.ts`; HWID salt
  derivation = HMAC-SHA256(pepper, "hwid-salt|project_id") (documented so
  both sides derive identical hashes server-side only).
- **M8/M11**: admin auth is `Authorization: Bearer <token>`; admin responses
  use plain JSON `{ error }` shapes (not the SDK envelope) — see Contract
  Issues.
- **M13**: stub endpoint consumes the same gate (proof/nonce/rate) once built.

## Contract Issues

1. Key format: doc.md §6 shows 4 groups of 5; implementation ships 4 groups
   of 5 + a 6-char tail group (25 random base32 chars + 1 checksum char =
   125 bits + typo detection). Documented in RESEARCH-M1.md; flagging for
   the M14 review pass.
2. §5.4's `data` block is `null` on denials (per the envelope example) —
   SDKs must treat `data: null` and `data: {...}` both as valid envelope
   shapes.
3. Admin endpoints do not use the §5.4 code envelope (they are not
   SDK-facing); they use HTTP status + `{ error }` bodies. If M14 rules
   otherwise, the fix is mechanical.
4. `auth_expire` is `0` for non-expiring keys (per §5.4 example), not null.
