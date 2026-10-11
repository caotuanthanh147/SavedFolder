# RESEARCH-M5 — Obfuscator back end (bytecode compiler, container, differential harness)

Module LP1-M5 (doc.md §10.2 items 3, 4 + §10.3, §5.9). Owner: glm6.
Written BEFORE any code, per doc.md "Mandatory research" (v4 READ FIRST).
All URLs below were actually opened (curl) on 2026-10-10. Local copies of
fetched artifacts: /tmp/m5research/ (session scratch, not part of delivery).

## Research Log

| # | Topic | Source URL | Version / date | Key finding | Used for |
|---|-------|-----------|----------------|-------------|----------|
| 1 | Lua 5.1 instruction format + opcode set | https://www.lua.org/ftp/lua-5.1.5.tar.gz → src/lopcodes.h | Lua 5.1.5 (2007-2012, MIT) | 32-bit instructions: op(6)+A(8)+B(9)+C(9); iABx Bx(18); iAsBx excess-K signed. 38 opcodes. RK operand encoding: BITRK=1<<8 marks constant-vs-register. B=0/C=0 "open" conventions propagate `top` for CALL/RETURN/VARARG/SETLIST; SETLIST C=0 reads next word. OP_FORPREP/FORLOOP layout R(A)..R(A+3) = [index(internal), limit, step, visible-copy]; OP_TFORLOOP generic-for; OP_CLOSE closes upvalues; OP_CLOSURE's upvalue descriptors are inline pseudo-instructions; LFIELDS_PER_FLUSH=50. | Register-VM design precedent; multret/vararg/upvalue mechanics; SETLIST chunking constant |
| 2 | Luau bytecode format (current) | https://raw.githubusercontent.com/luau-lang/luau/0.742/Common/include/Luau/Bytecode.h (moved from VM/src/ in master — master restructured to Bytecode/ + Common/ during 2026-10; tag pinned for stability) | 0.742 tag, fetched 2026-10-10, MIT | "Word code": 32-bit words, opcode in LSB byte. Encodings: ABC (A/B/C 8-bit), AD (A 8-bit + signed D 16-bit), E (signed 24-bit); optional AUX 32-bit word follows. Limits: registers 0-254, upvalues 0-199, constants 23-bit, child closures 15-bit, jumps ±2^23 in WORD increments (AUX counts). MULTRET: CALL B=0 (args to top)/C=0 (results adjust top); RETURN B=0; GETVARARGS B=0; SETLIST C=0. PREPVARARGS+GETVARARGS pair. NEWCLOSURE+CAPTURE(LCT_VAL/LCT_REF/LCT_UPVAL). FORNPREP/FORNLOOP layout [limit, step, index, variable] (limit/step immutable); FORGPREP/FORGLOOP layout [generator, state, index, vars...] with AUX var-count. NAMECALL must be followed directly by CALL (__namecall). Constant types incl. LBC_CONSTANT_INTEGER. Bytecode VERSIONED (v3..v14, target 9) — "bytecode isn't a durable storage format"; enums order-sensitive. | Word-encoding shape (op8/A8/B8/C8 + D16/E24 + AUX32); limits; FORN/FORG register layouts; MULTRET conventions; version-field practice for my container |
| 3 | Luau compiler lowering of string interpolation | https://raw.githubusercontent.com/luau-lang/luau/0.742/Compiler/src/Compiler.cpp (compileExprInterpString, L2634-2700) | 0.742 tag, fetched 2026-10-10, MIT | `` `a{x}b{y}c` `` compiles to `string.format(fmt, x, y)` where fmt escapes `%`→`%%` in literal parts and uses `%*` per expression; string-constant expressions are inlined into fmt (also %-escaped). | InterpString lowering in my compiler |
| 4 | `%*` format specifier semantics | https://raw.githubusercontent.com/luau-lang/luau/0.742/VM/src/lstrlib.cpp (L1082-1088) + VM/src/laux.cpp (luaL_addvalueany, L525+) | 0.742 tag, fetched 2026-10-10, MIT | `%*` appends the argument via luaL_addvalueany = tostring-style conversion (nil→"nil", bools, numbers, strings raw, else __tostring/tostring). | Reference-interpreter string.format must implement `%*` for interp-string parity |
| 5 | Luau vs Lua 5.1 language surface | https://luau.org/compatibility (fetched 2026-10-10) | current site | "Luau is based on Lua 5.1 … incorporates all features of 5.1 except sandboxing removals"; keeps getfenv/setfenv. Limits: 200 locals/function (incl. args), 200 upvalues (5.1: 60), 255 registers. | Compile-time limit checks; upvalue count limit decision |
| 6 | Luau number model + syntax additions | https://luau.org/syntax (fetched 2026-10-10) | current site | Single 64-bit IEEE754 double (2^53 exact integers); continue (contextual keyword, last-in-block); compound assignments; string interpolation; if-then-else exprs; `//` floor div incl. __idiv metamethod, a//0=±inf, 0//0=NaN; \x/\u/\z escapes. | NumberExpr/LOADINT bounds; FloorDiv semantics in interpreter; continue lowering rules |
| 7 | VM-obfuscation design + weakness (survey) | https://arxiv.org/abs/2601.10261 (XuanJia: A Comprehensive Virtualization-Based Code Obfuscator for Binary Protection) | 2601.10261v1, fetched 2026-10-10 | VM-based obfuscation is "one of the strongest protection mechanisms"; known weakness studied: exposed metadata (e.g. exception-handling) leaks stack layouts, control-flow boundaries, object lifetimes that aid RE; they protect it end-to-end. | Confirms: metadata leakage is a concrete attack class → my container must NOT carry debug names/line info |
| 8 | Deobfuscation techniques vs VMs (trace limits) | https://arxiv.org/abs/2603.18355 (Pushan: Trace-Free Deobfuscation of Virtualization-Obfuscated Binaries) | 2603.18355v1, fetched 2026-10-10 | Existing automated deobfuscation mostly works on EXECUTION TRACES (misses unreached logic) and depends on dynamic symbol execution; Pushan is trace-free. | Threat model: static+semantic lifting is state of art → per-build randomization (opcode permutation) + keeping constants encrypted until use matters more than trace-resistant dispatch alone |
| 9 | Automated semantic extraction from VM obfuscation | https://arxiv.org/abs/2605.30902 (VMPredator: core-structure-based automated analysis) | 2605.30902v1, fetched 2026-10-10 | Tools extract "semantic units" from VM handlers with memory+trace analysis, VM-structure-agnostic. | Design consequence: handler-level semantics WILL be recovered by determined analysts (doc §10.4 admits this) — value = raising cost, not impossibility; keep M5 layer honest and let M6/M7 add layers |
| 10 | Prior art: open-source Lua 5.1 VM obfuscator | https://github.com/Trollicus/ironbrew-2 (tree via API + README @ master) | fetched 2026-10-10; MIT license; 86 stars; last push 2023-09-21 | Architecture: C# CLI shells out to real `luac.exe` (Lua 5.1) → parses the FIXED Lua 5.1 bytecode format → re-encodes into custom VM format + emitted Luau-source VM template; ships LuaSrcDiet minifier + compression. | Prior-art contrast: M5 compiles M4's AST DIRECTLY (no luac dependency, Luau-aware, per-build opcode permutation native). Not adapted (different language/stack); MIT license noted |
| 11 | Prior art: deobfuscator exists for IB2 | https://github.com/Gork3m/IronBrew2-Deobfuscator (repo via API) | fetched 2026-10-10; no license; 26 stars | A public deobfuscator for IronBrew2's output exists since 2021. | Evidence that fixed/known VM layouts get tooling; motivates per-build seeds + versioned container |
| 12 | base-128 varint definition | https://developers.google.com/protocol-buffers/docs/encoding ("Base 128 Varints") | fetched 2026-10-10 | Canonical base-128 varints: 7 bits/byte, MSB continuation, little-endian byte order. | Container "function count (varint)" (§5.9) + all length fields |
| 13 | CRC-32 definition | https://www.rfc-editor.org/rfc/rfc1952.txt (RFC 1952 §2.3.1 + §8) | fetched 2026-10-10 | CRC-32 polynomial per ISO 3309 / ITU-T V.42 (the gzip CRC: reflected poly 0xEDB88320, init/final 0xFFFFFFFF). | Trailer checksum algorithm; test vector cross-checked with a second implementation (Python 3.12 zlib: crc32(b"123456789") = 0xCBF43926) |
| 14 | ChaCha20-Poly1305 availability in this sandbox | runtime test (bun 1.3.14 x64, `createCipheriv('chacha20-poly1305')`) | 2026-10-10 | **Bun node:crypto does NOT support the `chacha20-poly1305` cipher** ("Unknown cipher", ERR_CRYPTO_UNKNOWN_CIPHER). Same environment class as M1's RESEARCH-M1 WebCrypto X25519 finding. | Container const-pool AEAD must reuse M1's pure-TS RFC 8439 implementation (api/src/chacha.ts) instead of node:crypto |

## Options compared

**D4 — bytecode model (register vs stack)** (doc pre-leans register):
register (Lua 5.1/Luau style) vs stack (classic JVM/z-machine style).
Evidence: doc §10.2 item 3 "A register-based design (like Lua 5.1) maps well
and is faster than stack-based"; both references I opened (#1, #2) are
register VMs; both production systems converged on registers for Lua-family
workloads. → **register** (Tier 3-adjacent but doc-fixed; D4 resolved by
doc + corroborating sources).

**Instruction encoding (fixed 32-bit Lua-5.1-style bitfields vs Luau-style
byte-aligned word code):**
- Lua 5.1: op(6)+A(8)+B(9)+C(9)/Bx(18) bitfields — compact, but fields cross
  byte boundaries; per-build field-width randomization (doc item 4) is harder.
- Luau: op(8)+A(8)+B(8)+C(8) / D(16) / E(24) + AUX word — byte-aligned,
  256-opcode space (headroom for per-build junk opcodes + permutation into a
  sparse space), 16-bit D covers 32K constants inline with AUX escape.
→ **Luau-style byte-aligned word code** (my own opcode set/numbering/semantics
— clean-room names and numbering; encoding SHAPE follows the byte-aligned
precedent for the item-4 randomization path).

**Upvalue capture strategy (VAL-copy vs REF-always):**
Luau emits LCT_VAL only when its analysis proves the local is never assigned
(const locals optimization). M4's semantic analysis (item 2) is not delivered
yet; correctness demands live references for mutable locals. → **always
LCT_REF for locals, LCT_UPVAL for enclosing upvalues; LCT_VAL reserved but
unused until M4's analysis provides immutability facts** (Tier 1, documented;
conservative-correct).

**Opcode numbering (fixed canonical vs per-build permutation):**
doc item 4 mandates per-build randomization of opcode numbering. Canonical
numbering needed internally (compiler emits canonical, encoder maps at pack
time). → **canonical opcode enum in the compiler; container stores
opcode_seed-derived permutation** (Fisher-Yates over a 64-slot space, real
opcodes scattered; unused slots = invalid-opcode trap). Field-width/order
randomization and register-allocation-order randomization: designed-IN later
sessions (need liveness info); documented as not-built in VERIFICATION-M5.

**Differential oracle (what plays "original" in §10.3):**
(a) hand-computed expected outputs (self-restating — banned by §22.1),
(b) real Lua interpreter executing the fixture SOURCE (original behavior =
outside source), (c) wait for M4 parser to feed the corpus end-to-end.
→ **(b) now + (c) when parser lands**: fixtures are pairs (source.lua,
hand-built AST) in the Lua 5.1∩5.4 common subset; source runs under the
installed portable Lua 5.4.7 (child_process); AST compiles+packs+loads+runs
in my reference interpreter; stdout must match byte-for-byte. Corpus-wide
end-to-end (50 files) is blocked on M4's parser → NOT-RUN list.

**Const-pool encryption runtime:**
(a) bun node:crypto chacha20-poly1305 — **verified unavailable** (#14),
(b) re-implement RFC 8439 — duplicates M1's audited pure-TS implementation,
(c) import M1's api/src/chacha.ts cross-package.
→ **(c)**: `aeadSeal/aeadOpen` are exactly the needed surface; crypto must be
byte-compatible with M3's Luau side anyway (same AEAD on both ends);
duplication in security-critical code is the worse evil. Tier 2 decision
(reversible import; main-agent notified by msg).

## Prior art found

- **Trollicus/ironbrew-2** (MIT): Lua 5.1 VM obfuscator, luac-frontend
  architecture (see #10). Design contrast recorded; nothing adapted.
- **Gork3m/IronBrew2-Deobfuscator**: public counter-tooling for a fixed VM
  layout (see #11) — motivates per-build seeds.
- **XuanJia / Pushan / VMPredator** (arxiv): academic state of the art on
  VM obfuscation + deobfuscation (see #7-#9) — threat model calibration for
  doc §10.4's "realistic limits" stance.
- Commercial Lua obfuscators (Luraph et al.): deliberately NOT studied beyond
  the HTTP-spy capture already in doc.md §1 — clean-room rule.

## Unverified items

- **Luau `42i` integer-literal runtime semantics** (LBC_CONSTANT_INTEGER is
  "experimental" in the version history I opened): M5 v1 REJECTS IntExpr
  nodes with a clear compile error rather than guess a storage model.
  Executor-target scripts do not use `42i` today (same reasoning as M4's
  D-M4-7 declare deferral).
- **Real-executor performance** of the eventual M6 runtime: not measurable in
  this sandbox (doc §22.1 real-environment table owns it).
- **`__iter` metamethod in generalized iteration**: luau.org documents
  generalized iteration; the exact metamethod contract was not verified from
  source this session. v1 reference interpreter implements: function iterator
  → as-is; table without __iter → next/state; table with __iter → call it for
  the triple. Flagged for M6 + corpus verification when M4's parser lands.

## Decisions made and why (full log in DECISIONS-M5.md)

D4 = register-based (doc + both primary bytecode sources). Encoding =
byte-aligned word code. Opcode numbering = per-build seeded permutation over
64 slots. Upvalues = REF-always until M4 analysis. Oracle = real-Lua
differential now, corpus later. Const pool = ChaCha20-Poly1305 via M1's
chacha.ts import. IntExpr = rejected in v1. No debug info in container
(metadata-leak lesson, #7).
