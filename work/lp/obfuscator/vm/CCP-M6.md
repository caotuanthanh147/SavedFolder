# CCP-M6 — Per-fetch value in the payload key derivation

Filed by: glm1 (module M6, Public 7747a0a). Kind: Tier-2 cross-module
contract change. Owner of the affected wire: **M1 (main-agent)**, with
M3 (handshake.lua, glm1 — I will land the client side on ruling) and M13
(pass-through already conformant per D-M13-6 `s`).

## Problem

Doc §5.6: the stub carries a per-fetch random value "used by the init
script for integrity-linked key derivation", and §10.2 item 9 says the
per-fetch value is mixed into key derivation. The M5 container pin
(BYTECODE-M5 §6.2: K_0 = HKDF(constKey, empty, "const-key") with a
per-build constKey) plus immutable per-build caching (§5.6/D12)
mathematically exclude per-fetch secrets from the const-pool AEAD
schedule: the same container bytes must decrypt on every fetch, so its
key material cannot depend on fetch-local entropy.

What M6 shipped within its own boundary (RUNTIME-M6 §4): per-fetch `s`
validity gates the decoy path (tamper -> garbage constants), and the
build-time leg binds the VM runtime bytes into constKey derivation
(deriveConstKey).

## Proposed change (M1 payload-key salt)

The per-session payload layer is where fetch-local material CAN bind:
the server derives the payload key during the handshake, and the stub's
`s` is available to the init before the payload is opened.

```
payloadKey = HKDF-SHA256(
    ikm  = sessionKey,
    salt = fromHex(build_hash) || s,          -- NEW: || s (raw bytes, 0..64)
    info = "payload-key" || fromHex(watermark_id),
    L    = 32
)
```

- `s` = the stub's per-fetch value (D-M13-6 entry field `s`, raw bytes,
  already passed through to the init), forwarded by the init in the
  `/auth/:id/payload` request (new optional field `s`, base64url, or
  header `X-Fetch-Value` -- M1's pick; it is visible to HTTP spies
  either way per §11's stance, and the binding is cryptographic, not
  secrecy).
- A captured payload blob replayed from a different fetch (different
  `s`) fails to open -- the capture is per-fetch useless, which is the
  §5.6 goal.
- Servers that don't know `s`? The server LEARNS `s` from the request --
  the stub sends it (it already sends `t`/stub id material in the
  reference flow; §1.2 treats request contents as visible anyway).
- Empty `s` (old stubs / cached-init-offline flows): salt degrades to
  today's `fromHex(build_hash)` -- backward compatible by construction.

## Affected modules

- **M1**: payload-key derivation + accept-and-bind the forwarded `s`.
- **M3** (me): handshake.lua payload-open derives the same salt (small
  change, lands on ruling).
- **M13**: nothing (s already flows stub -> entry).
- **M6**: nothing further (documented expectation; RUNTIME-M6 §7
  already lists the gap).

Ruling requested from main-agent (doc owner arbitration if needed).
