# M5 — Obfuscator back end (bytecode compiler, container, differential harness)

Module card for LP1-M5 (doc.md §10.2 items 3, 4 + §10.3 + §5.9; repo layout
`obfuscator/compiler/`). Owner: glm6. Status: **delivered v1** (format
version 1 pinned).

## What this module owns

1. **Compiler to custom bytecode** (§10.2 item 3) — register-based (D4),
   M4's AST (`obfuscator/src/ast.ts`) → canonical instruction streams:
   `src/compile.ts` (1401 lines: scope/slot allocation, multret, upvalue
   capture, loop lowering, jump patching, compile-time limit enforcement).
2. **Per-build randomization** (§10.2 item 4) — opcode numbering: seeded
   Fisher-Yates permutation over a 64-slot universe, canonical↔emitted
   mapping applied at pack time; trap slots for unused ids:
   `src/opcode.ts`. Register-allocation-order and field-width
   randomization: designed-in slots, not built in v1 (VERIFICATION-M5 §4).
3. **§5.9 container + manifest** — `src/container.ts`: "LPVB" magic,
   version 1, build hash (SHA-256), depth-first function serialization,
   **per-function AEAD constant-pool blobs under chained HKDF keys**
   (§10.2 item 6: K_0 = HKDF(constKey, ∅, "const-key"); K_n =
   HKDF(K_{n-1}, u32be(n), "const-key") — bytes pinned in BYTECODE-M5 §6.2),
   CRC-32 trailer, manifest {build_hash, format_version, opcode_seed,
   created_at}.
4. **Differential harness** (§10.3) — `src/interpreter.ts` reference
   executor + `tests/differential.test.ts`: 17 source/AST fixture pairs,
   original = real Lua 5.4.7, protected = compile→pack→unpack→interpret,
   byte-equal stdout required.

## The normative spec

**BYTECODE-M5.md** — ISA (58 opcodes, word shapes, jump-unit rule),
container layout, key chain, permutation derivation, limits, and M6
implementation guidance. M6 (glm1) implements against this file; M7/M13/M1
consume the container as specified. Code-vs-spec disagreement = bug.

## Decision Log

DECISIONS-M5.md (D-M5-1..18: register model, byte-aligned word code,
seeded permutation, frame-carried varargs, REF-always upvalues, FORN/FORG
layouts, InterpString lowering, M1 chacha import, IntExpr rejection, no
debug info, SETLIST=50, real-Lua oracle, magic/versioning, Luau limits,
reference interpreter, per-function AEAD granularity + chain bytes,
sync HKDF location). Research backing: RESEARCH-M5.md (14 opened sources).

## Verification

VERIFICATION-M5.md (§22.1): `tsc --noEmit` clean + `bun test` 45/45
(392 expect calls), outside-source vectors (protobuf varints, RFC 1952
CRC-32, FIPS 180-4 SHA-256, RFC 5869 HKDF TC1-3 via
contracts/test_vectors.json, M1's audited ChaCha20-Poly1305), honest
NOT-RUN list (corpus end-to-end awaits M4's parser; fuzzing, coroutines,
performance ratios, real-executor runs), and the four session bugs found
→ fixed → regression-tested.

## Dependencies

- M4's AST (delivered, `obfuscator/src/ast.ts` — consumed, never modified).
- M1's pure-TS ChaCha20-Poly1305 (`api/src/chacha.ts`, source-direct
  import — D-M5-9: no duplication of audited crypto; node:crypto lacks the
  cipher in this sandbox, RESEARCH-M5 #14).
- Portable Lua 5.4.7 (bootstrap.sh install) as the differential oracle.

## Known limitations (summary — full list in VERIFICATION-M5 §4)

Corpus/fuzz phases gated on M4's parser; no coroutine/io/os libraries in
the reference interpreter; IntExpr rejected; wrong-opcode-seed rejection
is best-effort at decode (production runtimes bake the map —
BYTECODE-M5 §7).
