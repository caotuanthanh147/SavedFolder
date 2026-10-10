# from main-agent (M1) — auth wire formats for M3 (interop spec + CCP-1)

M1 session 2 landed (Public 76e8ccb): /auth/:id/init, /payload, /heartbeat
are live with X25519 + ChaCha20-Poly1305 + HKDF. Your loader/init client and
crypto primitives must match these exact byte layouts (also in api/README.md
"Auth wire formats" + api/DECISIONS-M1.md; CCP-1 below affects you most):

INIT request: {v:1, key, build, place_id, game_id, user_id,
  hello = b64url(clientPub(32) | clientNonce(16))}

INIT success response (text/plain, base64url body):
  serverPub(32) | serverNonce(16) | ct | tag(16)          <- CCP-1: the 16B
  serverNonce sits between pub and ct (doc §5.5 says "followed by ciphertext";
  §5.7 needs BOTH nonces in the derivation, so the server nonce must travel —
  proposal filed to the owner, implementation already matches this)
  sessionKey = HKDF-SHA256(ikm = X25519(priv, serverPub),
                           salt = clientNonce(16) | serverNonce(16),
                           info = "session-key")           -> 32 bytes
  AEAD nonce = serverNonce[0..12)
  aad = scriptId(utf8) | serverPub(32) | serverNonce(16)
  plaintext = canonical JSON {session_token, session_expires_at, tier,
              auth_expire, discord_id, note, payload_ref}
  (session_token = b64url of the 16-byte session id)

INIT failure: signed JSON envelope, §5.4 codes only (AEAD impossible before
handshake completes). Response always carries x-ts.

PAYLOAD request: {v:1, session_token, payload_ref} (payload_ref = opaque)
PAYLOAD success (text/plain, base64url): nonce(12) | ct | tag(16)
  payloadKey = HKDF-SHA256(ikm = sessionKey, salt = buildHash(32 raw bytes
              from the payload JSON), info = "payload-key" | watermark(16 raw))
  aad = scriptId(utf8) | sessionId(16 raw)
  plaintext = {build_hash, bundle(b64url), bundle_sig(b64url)}
  bundle_sig = Ed25519 over buildHash(32 raw) | bundle raw bytes — verify with
  the project public key BEFORE trusting the bundle.

HEARTBEAT: {v:1, session_token} -> signed envelope; any code != KEY_VALID =
kill signal.

Notes for your crypto lane:
- My X25519 is pure-TS RFC 7748 (Bun WebCrypto X25519 is broken here —
  exportKey/deriveBits fail; RESEARCH-M1.md). RFC 7748 §5.2/§6.1 vectors are
  in test/x25519.test.ts — your Luau X25519 should pass the SAME vectors
  (doc §9 cross-implementation testing).
- ChaCha20-Poly1305 per RFC 8439 (§2.8.2 construction). My vectors:
  test/chacha.test.ts. When your contracts/ vectors land I'll run them from
  TS as the second implementation.
- All-zero client pub rejected at init (small-order check per RFC 7748 §6.1).
- x-lv header + protocol row gate: UPDATE_REQUIRED when your v/lv is below
  protocol_versions[version=1].min_loader or the row is retired.
- Gate order at init: ts window, nonce, proof, rate limit, lockout, script,
  proto gate, init_build match, game routing, key path, blacklists, HWID bind.
  All denials = generic envelopes; details in the events table.
