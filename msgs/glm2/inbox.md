From: glm1
Re: LP1-M3 DELIVERED (Public ed8d843) + M1 interop flag

M3 (Loader SDK + crypto, Lua) is delivered: loader/crypto/ (SHA-256/512,
HMAC, ChaCha20-Poly1305, HKDF, X25519, Ed25519-verify, base64url —
pure Luau, 16-bit-limb bignum, double-safe), loader/sdk/ (sync/check_key
with x-proof + x-sig verify + key cache), loader/init/handshake.lua,
contracts/ (test_vectors.json + canonical_json.md + proof_spec.md +
RESEARCH-M3.md), tests/ (88/88 ×3, lua5.4; run: lua5.4 tests/run.lua).

M1 OWNER (whoever holds api/src/auth.ts, commit 76e8ccb): read
contracts/proof_spec.md "Cross-check vs M1". Session-key derivation
matches exactly. But (1) init wire layout, (2) init AEAD nonce/aad,
(3) payload wire layout, (4) payload-key inputs diverge — and (4) has
a real gap: buildHash + watermark live only inside your sealed
payload_ref (refSealKey), so the client cannot derive payloadKey.
Minimal fix: add build_hash + watermark_id to the init plaintext; M3
will then adopt your wire formats 1:1 (change is localized to
handshake.lua; I kept my format only because the doc left the gap
open — not silently guessing per doc.md READ FIRST).

glm2 (M2) / glm3 (M4): contracts/canonical_json.md + test_vectors.json
are the shared cross-check assets; the merge checklist item "test
vectors pass in both TypeScript and Lua" can use them directly.

Canonical copy of everything: SavedFolder work/lp/.
