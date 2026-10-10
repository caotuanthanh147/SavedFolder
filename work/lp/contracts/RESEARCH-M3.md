# Research Log — M3 Loader SDK and crypto (Lua)

Compiled 2026-10-10 (glm1). Every URL below was opened during this
session; RFC texts were downloaded and the vectors in
contracts/test_vectors.json were extracted from them mechanically
(scripts: no hand transcription).

| Topic | Source URL | Version / date | Key finding | Used for |
|-------|-----------|----------------|-------------|----------|
| EdDSA (Ed25519 verify, sign reference, test vectors) | https://www.rfc-editor.org/rfc/rfc8032.txt | RFC 8032, Jan 2017 (downloaded today) | Verify = decompress A/R, reject S >= L, h = SHA512(R||A||M) mod L, check [S]B == R + [h]A via cross-multiplication; reference Python in §5.1/§7.1 | ed25519.lua, tests/ed25519_sign.lua, vectors |
| X25519 (ladder, clamping, vectors) | https://www.rfc-editor.org/rfc/rfc7748.txt | RFC 7748, Jan 2016 (downloaded today) | Montgomery ladder with cswap, clamp k[0]&=248 / k[31]&=127 / k[31]|=64; §5.2 vectors + §6.1 DH example | x25519.lua, vectors |
| ChaCha20 + Poly1305 AEAD | https://www.rfc-editor.org/rfc/rfc8439.txt | RFC 8439, June 2018 (downloaded today) | Block/cipher/OTK construction; Poly1305 clamp is 0x0ffffffc0ffffffc0ffffffc**0fffffff** (pseudocode line, confirmed against a verbatim donna-32 port); tag over aad||pad||ct||pad||le64(len aad)||le64(len ct) | chacha20.lua, poly1305.lua, aead.lua, vectors |
| HMAC-SHA2 vectors | https://www.rfc-editor.org/rfc/rfc4231.txt | RFC 4231, Dec 2005 (downloaded today) | TC1 key is 20 bytes of 0x0b (not 16); TC6 exercises a 131-byte key (hash-key-first path) | hmac.lua, vectors |
| HKDF vectors | https://www.rfc-editor.org/rfc/rfc5869.txt | RFC 5869, May 2010 (downloaded today) | Extract-then-expand; TC3 zero-length salt/info | hkdf.lua, vectors |
| poly1305-donna-32 (prior art, public domain) | https://raw.githubusercontent.com/floodyberry/poly1305-donna/master/poly1305-donna-32.h | fetched today | Limb structure and the block absorption/finalization shape; ported to Python to validate the RFC clamp and to generate cross-checks. Algorithm only (clean-room: no vendor code copied — this is Bernstein's public-domain reference, not the captured service) | poly1305.lua validation |
| Executor crypto API (UNC) | https://docs.potassium.pro/llms.txt and /api-reference/Crypt Library/crypt.hash.md, crypt.hmac.md | fetched today | crypt.hash(data, "sha256"|"sha512"), crypt.hmac(key, data, alg), crypt.random(n) raw, crypt.generatebytes(n) b64, gethwid; NO X25519/Ed25519/ChaCha20 anywhere in the executor API | D2 decision, env_executor.lua |
| Executor HTTP + file API | same potassium docs + project guide §12 | fetched today | request(options) -> {Body, StatusCode, Headers}; readfile/writefile/isfile/makefolder; feature-check every alias | env_executor.lua |
| Luau bit32 | https://luau.org/library + devforum announcement thread (search) | fetched today | bit32 is the standard bitwise API in Luau (all executors); Lua 5.4 removed bit32 -> CI needs the pure fallback in bit.lua | bit.lua design |
| Reference behavior capture (clean-room, user's own capture) | Public/HTTPSpy_1791633846.txt | 2026-10-10 | Observed flow: /sync time+nodes -> check_key -> per-fetch stub -> cached init -> opaque auth blob; executor-injected identity headers (Delta-Fingerprint, Delta-User-Identifier). Behavior only; no constants/algorithms copied | Behavioral context only |

## Options compared (crypto representation)

1. **26-bit limb donna-style field arithmetic** — fastest pure-Lua
   option on paper, but products of (limb x 5*r-limb) exceed 2^53 in
   doubles -> precision corruption. Rejected.
2. **16-bit limb arithmetic (chosen)** — products < 2^33, sums < 2^37,
   fold multipliers 38x bounded, everything below 2^41. ~2M
   multiply-adds per X25519 (0.25s for 6 ladders in lua5.4), ~0.5s per
   Ed25519 verify. Safe and fast enough at load time.
3. **bit32-native + executor crypt fast path** — bit32 used
   opportunistically (bit.lua resolves bit32 -> bit -> pure); executor
   crypt.hash/crypt.hmac NOT wired into the shipped modules because
   equivalence testing on target executors is still pending (D2);
   wiring point documented in env_executor.lua.

## Prior art found

- poly1305-donna (floodyberry, public domain) — limb algorithm reference.
- RFC reference implementations (8032 Python, 8439 pseudocode) — normative.
- The captured vendor SDK (Luarmor) — explicitly NOT used for code or
  constants (clean-room rule, doc.md READ FIRST).

## Unverified items (Open Decisions)

- **D2 benchmarking on target executors** — pure-Lua timings were
  measured here (lua5.4): X25519 ~40ms/operation, Ed25519 verify
  ~500ms. Executor-native crypt.hash/crypt.hmac equivalence tests and
  on-device benchmarks are pending; the hook point is
  env_executor.lua / Crypto table injection.
- **D10 header names per executor** — the capture shows
  `Delta-Fingerprint`/`Delta-User-Identifier` for Delta Android;
  server-side per-executor config is M1's surface; SDK side needs no
  change (it must not strip unknown headers).

## Decisions made

- Pure-Lua/Luau for ALL primitives (option 2 above) — no executor
  exposes X25519/Ed25519/ChaCha20, so the pure path is mandatory
  anyway; hashes stay pure too for cross-implementation consistency
  until D2 benchmarks land.
- Ed25519 verification follows the RFC reference exactly (non-cofactored
  equation, h reduced mod L) — validated against all 5 §7.1 vectors.
- Ed25519 signs ONLY in the test harness (the loader never signs).
- All bignum values are represented as little-endian 16-bit limb
  arrays; every intermediate bounded < 2^53 (double-safe).
