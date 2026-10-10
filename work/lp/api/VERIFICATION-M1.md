# VERIFICATION-M1 (§22.1 — command + output attached, nothing claimed without proof)

Module M1 "API core", session 1 (re-land). Written for the doc.md §22.1
verification bar. Companion documents: `RESEARCH-M1.md` (research log, written
before code), `DECISIONS-M1.md` (decision log).

## Environment

| Item | Value | How obtained |
|------|-------|--------------|
| Runtime (tests) | Bun 1.3.14 | `bun --version` |
| Type checker | tsc via `bun run typecheck` (strict) | see transcript |
| SQLite driver (tests) | `bun:sqlite` (`test/helpers.ts:1`) — same SQL text as the D1 adapter path | `src/db.ts` |
| Crypto (Ed25519 / HKDF / HMAC / SHA-256) | `globalThis.crypto.subtle` (WebCrypto) — same API surface as Cloudflare Workers | `src/crypto.ts` |
| Target runtime (production) | Cloudflare Workers | not run here, see NOT RUN |

## What was run, verbatim

Command: `bun test` (in `api/`, after `bun install`). Tail of the output (session 2 suite):

```
test/contracts.test.ts:
(pass) contract codes > the SDK-visible code list matches doc.md §5.4 exactly [0.04ms]
(pass) contract codes > unknown codes are denied [0.03ms]
(pass) canonical JSON > keys are sorted recursively and separators are tight [0.10ms]
(pass) canonical JSON > array order is preserved [0.02ms]
(pass) canonical JSON > non-integer numbers are rejected [0.04ms]
(pass) base64url > roundtrip without padding [0.13ms]
(pass) base64url > invalid characters are rejected [0.05ms]
(pass) hex > roundtrip and validation [0.05ms]

 137 pass
 0 fail
 694 expect() calls
Ran 137 tests across 11 files. [275.00ms]
```

Session 1 re-run before the re-land (unchanged suite): 59 pass / 0 fail /
472 expect() calls / 110 ms. The 137-check session 2 total = session 1's 59 +
19 x25519/chacha RFC vector tests + 32 auth handshake/payload/heartbeat/protocol-gate
tests + 25 admin session-2 endpoint tests + 2 cross-module compatibility
probes (M1's exact SQL against M2's real `db/migrations` files: STRICT tables,
sessions FK ON DELETE RESTRICT verified by a failing DELETE, keyless NULL
key_id, atomic HWID bind, protocol upsert, analytics counts).

Command: `bun run typecheck` → `$ tsc --noEmit` → exit code 0, no output.

## Why the tests count as *external* derivation (§22.1)

The suite does not restate the implementation. Every crypto claim is checked
against an outside source; every contract claim is checked against doc.md §5:

| Test group | Outside source |
|------------|----------------|
| HMAC-SHA256 | RFC 4231 Test Case 1 and Test Case 2 (exact key/message/digest bytes) |
| HKDF-SHA256 | RFC 5869 Test Case A.1 (IKM/salt/info → OKM, exact 32 bytes; a memory-truncated OKM was caught during development by this vector) |
| SHA-256 | FIPS 180-4 known-answer tests (empty string, "abc", long input) |
| X25519 | RFC 7748 §5.2 scalar-multiplication vectors 1-2 and §6.1 Diffie-Hellman vector (both directions + shared-secret equality) |
| ChaCha20 block | RFC 8439 §2.3.2 (key 00..1f, counter 1) and Appendix A.1 vectors 1-3 (fetched from rfc-editor.org; test constants were extracted programmatically from the fetched text, not hand-typed — hand-typing produced 3 wrong bytes that the vectors caught) |
| ChaCha20 cipher | RFC 8439 §2.4.2 full "Ciphertext Sunscreen" (114 bytes) |
| Poly1305 | RFC 8439 §2.5.2 tag vector and §2.6.2 key-generation vector |
| AEAD_CHACHA20_POLY1305 | RFC 8439 §2.8.2 full seal (exact ciphertext + tag), open, tampered-tag rejection, wrong-AAD rejection |
| Ed25519 | sign→verify roundtrip, tamper detection, cross-key rejection (property tests over the WebCrypto primitive, not a re-implementation); bundle_sig verified through the independent public-key path in the auth tests |
| base64url / hex / canonical JSON | RFC 4648 §5 semantics and doc.md §5.4 canonicalization rules |
| Envelope codes | doc.md §5.4 code list is embedded as data in the test; any drift fails |
| check_key / admin behavior | doc.md §5.5/§8 gate order and §16 endpoint list; matrix includes failure paths (stale ts, nonce replay, bad proof, blacklisted key/HWID/IP, HWID mismatch, lockout, oversized body) |

## NOT RUN (honest list)

| Item | Why not run | Planned |
|------|-------------|---------|
| Real Cloudflare Workers deployment (`wrangler deploy`) | No account/credentials in this environment | Owner deploys; `wrangler.jsonc` provided |
| `wrangler dev` local Workers runtime | Same credentials reason; also D1 local binding is not the same SQLite build | Phase: pre-deploy smoke test by owner |
| Durable Objects (RateCounterDO, NonceDO) in production | DOs only exist inside a deployed Workers project | Same as above; in-memory implementations of the same interfaces are what the tests exercise |
| Real D1 (batch semantics, read replication) | Requires deployment | M2's migration files are the single schema source; adapter SQL is identical text |
| Load / latency numbers | Out of scope for session 1 | Phase "Load test before launch" (doc §19) |
| Lua (M3) cross-implementation decrypt of a server-produced payload | glm1's loader/crypto module is still in flight | Merge checklist item "Loader decrypts a payload produced by the API for the same session"; the TS-side second implementation in test/auth.test.ts (client re-derives session/payload keys and verifies bundle_sig) covers the TS side now |
| compat-db.test.ts in an isolated api/ checkout | test skips when `../db/migrations` is absent (describe.skipIf) | runs in the repo layout where api/ and db/ are siblings, which is the merge-checklist configuration |

## Consequences of failures found by the suite during development

Caught before delivery (kept here so they are not hidden): route handler
argument-object vs tuple mismatch; reseller quota counting calls instead of
created keys; a dead lockout event path (moved to the lockout branch); import
mixups across modules. Each was found by a failing test, then fixed, then
re-run green.
