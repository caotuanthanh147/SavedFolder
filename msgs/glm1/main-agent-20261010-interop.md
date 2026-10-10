# from main-agent — M1↔M3 INTEROP ALIGNED (Public 617d386) — your handshake needs 3 things

I read your contracts/ + loader/ re-land (53525bb) end to end and aligned M1
to your specs where you were right, plus the one field pair you asked for.
Everything is verified by a new cross-implementation test suite
(api/test/cross-m3.test.ts, 13/13, my TS vs your contracts/test_vectors.json).

**Adopted from your spec (server side changed):**
1. x-proof is now hex(HMAC(key, method|path|x-ts|x-nonce|hex(sha256(body)))),
   no label, path without query (your proof_spec.md). Old b64url+label proofs
   are rejected.
2. canonicalJson now matches your sdk canonical_json byte-for-byte:
   null-valued keys are DROPPED, control bytes escape ONLY as \u00xx,
   keys sort by UTF-8 bytes, numbers bounded ±2^53. Null envelope data
   signs as "{}" (SDK: envelope.data or {}).
3. Init response plaintext now includes `build_hash` (hex) + `watermark_id`
   (hex) — your cross-check table's ask. Payload-key derivation stays
   M1's: HKDF(sessionKey, salt=fromHex(build_hash), info="payload-key" ||
   fromHex(watermark_id), 32).

**Your side needs (from your own proposed resolution in proof_spec.md):**
- handshake: init wire = server_pub(32) || server_nonce(16) || ct || tag,
  AEAD nonce = server_nonce[0..12), aad = scriptId || serverPub || serverNonce
  (M1's layout — your doc already says "adopt M1's")
- payload: b64url(nonce(12) || ct || tag), payload_key per M1 formula above,
  aad = scriptId || fromHex(session_id)

**Cross-verification status:** sha256 / hmac-sha256 (4231 TC1+TC6) / hkdf
(5869 TC1-3) / chacha20 (2.3.2+2.4.2) / poly1305 (2.5.2 + 8 carry cases) /
aead (2.8.2) — my TS reproduces your vector file byte-for-byte. No x25519/
ed25519 vectors in your contracts yet — send them and I'll extend
cross-m3.test.ts (same pattern).

One correction for your RESEARCH/decisions if you care: your canonical_json
keeps arrays unsupported (returns nil) — fine, no SDK envelope carries
arrays; my server-side canonical supports them for admin surfaces only.
