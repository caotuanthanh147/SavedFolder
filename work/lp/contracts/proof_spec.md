# Request Proof, Signature, and Key Derivation Spec (M3)

Clarifications M3 had to make where doc.md §5 leaves gaps. Each is
flagged as a Contract Issue in the module report; M1 must confirm or
amend. The SDK and the M3 test mock-server both implement this file.

## Common request headers (SDK/stub -> API), doc.md §5.2

| Header | Value |
|---|---|
| `x-ts` | client unix time + offset from `/sync` (decimal string) |
| `x-nonce` | 16 random bytes, base64url, single use |
| `x-lv` | loader/SDK version string |
| `x-proof` | see below |

## x-proof (spam filter, not a trust anchor)

`x-proof = hex( HMAC-SHA256( proof_key, method "|" path "|" x-ts "|" x-nonce "|" hex(SHA-256(body)) ) )`

- `method`: uppercase HTTP method.
- `path`: URL path only, no query string, no host. Keys are never in
  URLs (doc.md §5.1), so the path never carries secrets.
- Empty body: SHA-256 of the empty string
  (`e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`).
- All API calls (including GET /sync, /status) carry the four headers.

## x-sig (response authenticity)

`x-sig = base64url( Ed25519_sign( server_sk, code "|" message "|" canonical(data) "|" x-ts ) )`

- `canonical(data)`: contracts/canonical_json.md.
- `x-ts` here is the SERVER time response header (decimal string).
- The SDK verifies before trusting a `KEY_VALID`; verification failure
  is a generic denial (SERVER_ERROR + generic message), never a
  distinguishing error.

## Session and payload key derivation (doc.md §5.7 clarified)

    session_key = HKDF-SHA256(ikm = X25519(eph_sk, server_eph_pk),
                              salt = client_nonce (16B) || server_nonce (16B),
                              info = "session-key", L = 32)

    payload_key = HKDF-SHA256(ikm = session_key,
                              salt = build_id || watermark_id (ASCII),
                              info = "payload-key", L = 32)

Clarifications:

- **C1 (server nonce transport):** doc.md §5.5 says the init response
  is `server_eph_pk (32B clear) || ciphertext || tag` but §5.7 needs
  the server nonce BEFORE decryption. M3 reads the server nonce from
  the response `x-nonce` header (symmetric with the request header).
- **C2 (AEAD nonce):** ChaCha20-Poly1305 needs a 12-byte nonce; the
  session key and payload key each encrypt exactly ONE message, so
  the nonce is 12 zero bytes (no reuse possible; standard
  one-message-one-key construction).
- **C3 (null in canonical data):** see canonical_json.md — null-valued
  keys are dropped before signing.
- **C4 (watermark id transport):** doc.md §12 gives each session a
  watermark_id and §5.7 makes it an input to the payload key, but
  §5.5's init response does not include it. M3's handshake reads an
  optional `watermark_id` field from the decrypted init response
  (the mock server sends it; recommended for M1) and also accepts it
  as an explicit `payload()` argument.
- **C5 (payload response layout):** the payload response body is
  `base64url( ciphertext || tag )` (no server ephemeral prefix; the
  session already exists), encrypted with payload_key, zero nonce.
- **C6 (salt ordering):** `salt = build_id || watermark_id` (ASCII
  concatenation). `build_id` is the client's requested build
  identifier (the same string sent in the init request's `build`
  field), not the 32-byte build hash — the client cannot know the
  build hash before decrypting.
