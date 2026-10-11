# BYTECODE-M5 — LPVB bytecode & container specification (normative)

Owner: glm6 (module M5). Status: **pinned, format version 1**.
This document is the single source of truth for the M5 output consumed by
M6 (VM runtime generator), M7 (anti-tamper), M13 (build pipeline) and M1
(payload packaging). The implementing code is `obfuscator/compiler/src/`
(`opcode.ts`, `compile.ts`, `container.ts`, `interpreter.ts`); if code and
this document disagree, that is a bug — report it, do not fork silently.

Conventions: `u32le`/`u32be` = 32-bit unsigned little/big-endian;
`varint` = protobuf base-128 varint (7 bits/byte, MSB continuation,
little-endian groups); `K(...)` = HKDF-SHA256 key derivation; "instruction"
below ALWAYS means one decoded operation (1 or 2 words), never a word.

---

## 1. Value and type model

Values at runtime: nil, boolean, number (IEEE 754 binary64), byte-string,
table, function (closure or host). The AST front end is M4's
(`obfuscator/src/ast.ts`); constants in the pool are exactly:

| tag byte | meaning | encoding |
|---|---|---|
| 1 | boolean | 1 byte (0 = false, else true) |
| 2 | number | IEEE 754 double, 8 bytes little-endian |
| 3 | byte-string | varint length + raw bytes (M4 byte-string model) |

**Byte-string model (normative, D-M5-28):** a str const is a sequence of
bytes — in the TS interchange, a "latin1-style" JS string where every
code unit is one byte (0..0xFF), exactly the M4 contract
(`obfuscator/src/index.ts`: read source files with
`buf.toString('latin1')`; the lexer expands `\u{XXXX}` to UTF-8 bytes,
one code unit per byte). `pack` ENFORCES this: a str const carrying a
code unit > 0xFF fails LOUD (no silent `& 0xFF` truncation) — a > 0xFF
code unit means the input was decoded as UTF-8 TEXT somewhere upstream
(the corpus 2026-10-11 finding class). The container is byte-exact for
the contract: raw UTF-8 literals (em-dash/emoji/CJK), `\xNN` escapes,
and arbitrary binary round-trip unchanged (differential fixture
`byte-strings-unicode`, byte-equal vs real Lua 5.4). A Unicode-safe
re-encoding (UTF-8-in-pool) was REJECTED — Lua strings are byte
strings; the oracle compares bytes; `\xFF` must stay ONE byte (see
DECISIONS-M5 D-M5-28 for the full option comparison).

## 2. Instruction encoding (word code)

Every instruction is one 32-bit word, little-endian in the container,
optionally followed by one 32-bit AUX word (also little-endian). The
opcode occupies the LOW byte (bits 0..7). Three operand layouts:

| shape | bits 8..15 | bits 16..31 | AUX word |
|---|---|---|---|
| `ABC` | A (u8) | B (u8) << 16 \| C (u8) << 24 | never |
| `AD`  | A (u8) | D = signed 16-bit (two's complement) | never |
| `E`   | — | D = signed 24-bit (two's complement) in bits 8..31 | never |
| +AUX  | as per shape | as per shape | raw u32 (meaning per opcode) |

**Jump offsets (D in JUMP*/FOR*/FORG* opcodes) are INSTRUCTION-relative.**
`D = 0` means "fall through to the next instruction"; `D = 1` skips one
instruction even when that instruction carries an AUX word. Decoders must
advance pc by the instruction width (1 or 2 words), never by a fixed
amount — this is the misaligned-branch bug class measured in M6's
dispatch benchmark; the container's unit choice makes the rule mechanical.

The **emitted** opcode byte in a container is NOT the canonical id — see
§7 (per-build permutation). Canonical ids are the numbering below.

## 3. Canonical opcode table (v1, 58 opcodes, ids 0..57)

| id | name | shape | AUX | semantics |
|---:|---|---|---|---|
| 0 | NOP | E | – | no operation (also the canonical anchor for trap slots) |
| 1 | LOADNIL | AD | – | R(A) := nil |
| 2 | LOADBOOL | ABC | – | R(A) := (B ≠ 0) |
| 3 | LOADINT | AD | – | R(A) := D (signed 16-bit) |
| 4 | LOADK | AD | – | R(A) := K(D), D ≤ 32767 |
| 5 | LOADKX | AD | yes | R(A) := K(AUX) (24-bit index) |
| 6 | MOVE | ABC | – | R(A) := R(B) |
| 7 | GETGLOBAL | AD | – | R(A) := Env[K(D)] |
| 8 | SETGLOBAL | AD | – | Env[K(D)] := R(A) |
| 9 | GETUPVAL | ABC | – | R(A) := Upval(B) |
| 10 | SETUPVAL | ABC | – | Upval(B) := R(A) |
| 11 | CLOSEUPVALS | AD | – | close all open upvalue cells bound to registers ≥ A |
| 12 | GETTABLE | ABC | – | R(A) := R(B)[R(C)] |
| 13 | GETTABLEKS | ABC | yes | R(A) := R(B)[K(AUX)] (constant-key fast path) |
| 14 | SETTABLE | ABC | – | R(B)[R(C)] := R(A) |
| 15 | SETTABLEKS | ABC | yes | R(B)[K(AUX)] := R(A) |
| 16 | NEWTABLE | ABC | – | R(A) := new table (B, C = size hints) |
| 17 | SELF | ABC | – | R(A+1) := R(B); R(A) := R(B)[R(C)] (method call setup) |
| 18 | SELFKS | ABC | yes | R(A+1) := R(B); R(A) := R(B)[K(AUX)] |
| 19–25 | ADD SUB MUL DIV MOD POW IDIV | ABC | – | R(A) := R(B) op R(C); IDIV = floor division (`//`, Luau semantics incl. `__idiv`) |
| 26–32 | ADDK SUBK MULK DIVK MODK POWK IDIVK | ABC | – | R(A) := R(B) op K(C), C ≤ 255 |
| 33 | AND | ABC | – | R(A) := truthy(R(B)) ? R(C) : R(B) |
| 34 | OR | ABC | – | R(A) := truthy(R(B)) ? R(B) : R(C) |
| 35 | CONCAT | ABC | – | R(A) := R(B) .. R(B+1) .. … .. R(C), folded RIGHT-TO-LEFT; `__concat` (left operand's meta first, then right's) receives `[left, rightAcc]` and its result REPLACES the accumulator |
| 36 | NOT | ABC | – | R(A) := not truthy(R(B)) |
| 37 | MINUS | ABC | – | R(A) := -R(B) (`__unm`) |
| 38 | LENGTH | ABC | – | R(A) := #R(B) (`__len`; strings = byte length) |
| 39 | JUMP | E | – | pc += D |
| 40 | JUMPIF | AD | – | if truthy(R(A)) then pc += D |
| 41 | JUMPIFNOT | AD | – | if not truthy(R(A)) then pc += D |
| 42 | JUMPIFEQ | AD | yes | AUX bit 31 = negate; if (R(A) == R(AUX & 0x7fffffff)) xor negate then pc += D |
| 43 | JUMPIFLT | AD | yes | if R(A) < R(AUX) then pc += D |
| 44 | JUMPIFLE | AD | yes | if R(A) ≤ R(AUX) then pc += D |
| 45 | JUMPIFEQKNIL | AD | yes | AUX bit 31 = negate; compare R(A) against nil |
| 46 | JUMPIFEQKB | AD | yes | AUX bit 31 = negate; compare R(A) against boolean (AUX & 1) |
| 47 | JUMPIFEQKN | AD | yes | AUX bit 31 = negate; compare R(A) against number K(AUX & 0x7fffffff) |
| 48 | JUMPIFEQKS | AD | yes | AUX bit 31 = negate; compare R(A) against string K(AUX & 0x7fffffff) |
| 49 | CALL | ABC | – | B = nargs+1, **0 = args are regs A+1..top**; C = nresults+1, **0 = results go to regs A.. and adjust top** (MULTRET); `__call` honored |
| 50 | RETURN | ABC | – | B = n+1, **0 = return regs A..top-1**; frame teardown closes the frame's open upvalue cells |
| 51 | GETVARARGS | ABC | – | B = n+1, 0 = all varargs to regs A.. and adjust top |
| 52 | NEWCLOSURE | AD | – | R(A) := closure of child proto D (flat index, §5); upvalue cells captured per the child's descriptors |
| 53 | FORNPREP | AD | – | numeric-for setup: A base of `[limit, step, index, visible]` (D-M5-6, limit/step immutable after this); if not (initial index in range) pc += D (skip body) |
| 54 | FORNLOOP | AD | – | index += step; if in range: visible := index, pc += D (loop) |
| 55 | FORGPREP | AD | – | generalized-for setup (D-M5-7): A base of `[gen, state, index, vars...]`; table → (next, table, nil) unless `__iter`; function → as-is; pc += D to first FORGLOOP |
| 56 | FORGLOOP | AD | yes | AUX = nvars; `res = gen(state, index)`; if res[0] ≠ nil: index := res[0], vars := res[0..nvars-1], pc += D (loop), else exit |
| 57 | SETLIST | ABC | yes | R(A)[AUX+1 .. AUX+B] := R(A+1)..R(A+B); **B = 0 → up to top** (multret table constructor tail); compiler flushes every 50 items (D-M5-12) |

Frames: explicit objects `{ regs[0..maxRegs+7], top, varargs, openCells, env }`
— no PREPVARARGS (D-M5-4): varargs ride the frame. Parameters bind to
R(0)..R(numParams-1) (missing → nil; extras → varargs if the proto is
vararg). `top` tracks the multret boundary; CALL/RETURN/GETVARARGS/SETLIST
with the 0-count convention read/write through it.

## 4. Constants per function

Each proto owns a pool; indices are per-function (K(D)/K(C)/K(AUX) all
index the CURRENT function's pool). Compiler deduplicates per function.
Plain pool bytes (pre-encryption) for fcount functions:

```
pool_n = varint(count) || const_1 || … || const_count     (per §1 encodings)
```

## 5. Function serialization (depth-first)

```
function := varint(numParams) || varint(maxRegs) || u8(flags)
        || varint(nInst) || words… || varint(nUpvals) || upvals…
flags    : bit 0 = isVararg
words    : for each instruction: u32le(word) [, u32le(aux) if the shape has AUX]
upvals   : u8(kind) || varint(src)     kind 0 = 'val' (src = parent reg)
                                    kind 1 = 'ref' (src = parent reg)
                                    kind 2 = 'upval' (src = parent upvalue index)
```

Order: the compiler emits the main proto first, then every child proto
depth-first immediately after its creating parent. **NEWCLOSURE's D is a
flat index into this order.** v1 emits only `ref` (locals) and `upval`
(enclosing upvalues) descriptors — `val` is reserved for M4 analysis
(D-M5-5).

*Clarifying note (added 2026-10-11, IR.md review round; additive, no
byte change):* a kind-0 `val` descriptor means the upvalue is an
**immutable plain value frozen at NEWCLOSURE time** (Luau LCT_VAL
semantics — the parent register's content is copied into the closure).
Emission is legal ONLY under M4's `never-assigned` proof (IR.md §2.1:
the binding has exactly one write, its initializer, anywhere the name
resolves to it — including inside capturing closures). SETUPVAL against
a kind-0 upvalue is therefore impossible-by-construction; a conformant
runtime may trap on it (hand-crafted-container class). M5's compiler
maps every proof other than `never-assigned` to `ref` (conservative
default).

## 6. Container layout (§5.9 wire shape, v1)

```
offset  field
0       magic "LPVB" (4 bytes: 4c 50 56 42)
4       format version (u8) = 1
5       build hash (32 bytes: SHA-256 of §"hashed bytes" below)
37      fcount (varint)
…       functions (§5 serialization, fcount entries)
…       encrypted constant pool: fcount AEAD blobs, concatenated
…       trailer CRC-32 (4 bytes u32le, RFC 1952 / ISO 3309)
```

### 6.1 Per-function AEAD blobs (doc §10.2 item 6)

```
blob_n = varint(ctLen) || nonce(12) || ciphertext(ctLen) || tag(16)
```

- AEAD = ChaCha20-Poly1305 (RFC 8439) under the chained key K_n (§6.2).
- AAD (identical for every blob) = `magic || version || fcount ||
  SHA-256(functions)` — binds every pool to exactly this code section via
  its hash (D-M5-26: the pre-2026-10-11 form used the RAW functions bytes,
  which made sealing O(fcount × fnsBytes) — Poly1305 re-absorbs the whole
  AAD per blob under a per-blob key, so no caching was possible;
  hash-binding preserves the binding strength at O(fnsBytes + fcount)).
- `ctLen` makes blobs skippable: a lazy runtime can walk to blob n without
  decrypting blobs < n (M6 lazy-decrypt option, §10.2.6 "decrypted lazily").
- The reference interpreter decrypts eagerly at unpack; both are conformant.

### 6.2 Const-key chain (bytes pinned here; §5.7 label, D-M4-3)

```
info    = "const-key"                                     (9 ASCII bytes)
K_0     = HKDF-SHA256(ikm = constKey, salt = ∅, info, 32)
K_n     = HKDF-SHA256(ikm = K_{n-1}, salt = u32be(n), info, 32)   n ≥ 1
```

`constKey` (32 bytes) is the build-pipeline input (PackOptions.constKey);
salt for K_0 is EMPTY (RFC 5869 zero-salt rule). `n` is the flat
depth-first function index. One-way chain: a decrypted function's key
derives only SUBSEQUENT keys, each at full HKDF cost — one decrypted
function does not freely unlock others (§10.2.6). M3's Luau HKDF is
byte-compatible (same RFC construction; verified by the RFC 5869 TC1-3
vectors in `contracts/test_vectors.json`, which the M5 test suite runs
against the TS side).

### 6.3 Hashes and checksums

- **build hash** = SHA-256 over `magic || version || fcount || functions ||
  pool section` (the hash field itself at offset 5..37 is excluded).
  M1's `bundle_sig` signs `build_hash || bundle` above this — composes
  without conflict.
- **trailer CRC-32** covers ALL preceding bytes (including the build-hash
  field). Transport-level integrity; per-blob AEAD is the cryptographic
  one (a tamper that also fixes the CRC is still caught by the tag).

### 6.4 Manifest (per build, doc §5.9)

```json
{ "build_hash": "<64 hex>", "format_version": 1, "opcode_seed": "<64 hex>", "created_at": <unix seconds> }
```

`opcode_seed` is stored server-side (manifest) for debugging — it is NOT
carried in the container (the runtime knows the mapping by construction,
§7).

### 6.5 Watermark carriers (CCP-M7 v1 — `packWatermarked`, D-M5-20)

A watermarked container is an ordinary v1 container (NO version bump):
carriers only permute pool order and append junk entries, so an unmodified
v1 runtime consumes it transparently. All derivations below are normative
(the implementation is `compiler/src/watermark.ts`; the leak-side
reference extractor is `extractWatermark` in the same module — M7's
`api/src/leak.ts` consumes it or mirrors it in lockstep).

**Inputs:** watermark `W` = 16 bytes (sessions.watermark_id, M1 `randomId`);
`buildSalt` = 32 random bytes per build, carried in PackParts (NOT in the
manifest — its shape is a §5.9 fixed contract); flat function index `f`.

```
layout stream   T_f    = HKDF-SHA256(ikm = W, salt = buildSalt || u32be(f),
                                     info = "wm-layout", 32)
junk count      J_f    = 2 + (T_f[0] & 1)                       → 2 or 3
PRNG seed       σ_f    = u32be read from T_f[1..5)
keystream       S(f,p) = HKDF-SHA256(ikm = buildSalt,
                                     salt = u32be(f) || u32be(p),
                                     info = "wm-junk", 8)
```

The two info strings are container-internal labels (D-M5-21) — they are
NOT part of doc §5.7's loader/API derivation chain.

**Carrier 1 — pool order permutation.** `π_f` = block-closed Fisher-Yates
over the LIVE indices `[0, nLive)` with blocks `[0,256)` / `[256,32768)` /
`[32768,nLive)` (empty blocks skipped, drawn in that order), PRNG =
xorshift32 seeded `σ_f` (zero seed → the documented constant
`0x9e3779b9`), descending `i`, `j = lo + (next() mod (i-lo+1))` inside the
block. Every K-reference operand of the function is reindexed through
`π_f` (C-field arithK ops, D-field LOADK/GETGLOBAL/SETGLOBAL, AUX-field
LOADKX/GETTABLEKS/SETTABLEKS/SELFKS, AUX|NOT-field JUMPIFEQKN/KS where
the NOT bit is bit 31 and the index lives in bits 0..30). Block closure
guarantees no rewritten operand outgrows its field width — no opcode-kind
rewrites, no instruction insertion, jump offsets untouched. NEWCLOSURE D
operands (child proto indices) are NEVER pool references and are never
reindexed.

**Carrier 2 — junk entries.** `J_f` STR constants of 8 bytes each are
APPENDED after the live entries (positions p = 0..J_f-1):

```
junk[f][p] = STR( W_half(p) XOR S(f,p) )   where W_half(p) =
             p even → W[0..8)   (bytes 0-7 of the watermark)
             p odd  → W[8..16)  (bytes 8-15)
```

Extraction (leak workflow): decrypt the pool (server holds constKey via
PackParts), the UNREFERENCED indices are exactly the junk (invariant:
the compiler emits only referenced live entries — enforced fail-loud by
`verifyPackParts`, D-M5-22), decode `W_half(p) = junk[f][p] XOR S(f,p)`, 
assemble the halves; every function independently carries both halves,
so a watermark is recoverable from any single function's junk, and
cross-function disagreement signals tampering. Carrier-1 consistency
(secondary): re-derive `π_f` + junk from the recovered W and compare pool
contents — `extractWatermark(...).carrier1Ok`.

**Integrity:** the session build hash covers the FINAL session bytes
(watermark region included) — same §6.3 rule as any container. The
canonical (pre-watermark) build hash stays in `PackParts.canonicalManifest`
and the DB (`script_versions.build_hash`); the per-session `/auth/:id/payload`
response's `build_hash` field carries the SESSION hash (CCP-M7 ruling,
M1 impact).

**Honest scope (mirrors CCP-M7-RULING.md):** carriers 1+2 trace a DUMP,
not a recompile — an attacker holding the decrypted bundle holds constKey
(RUNTIME-M6 §2) and can re-pack a stripped container with a valid hash.
Carrier 3 (identifier fragments in live constants) is deferred to v2.

**PackParts (CLI-boundary projection, option A):** JSON, bit-exact across
processes — `serializePackParts` / `deserializePackParts` in watermark.ts;
num consts ride as 16-hex-char f64 bit patterns (JSON numbers cannot carry
NaN/-0/payload bits). `deserializePackParts` FAILS CLOSED: it re-packs with
the recorded canonical nonces and requires the canonical build hash to
reproduce. PackParts contains constKey — SERVER-SECRET, never delivered.
PackParts also pins the per-version `opcodeSeed` (the inverse opcode map
is baked into the immutable runtime — a per-session seed would dispatch
through the wrong permutation; glm1's CCP-M7 co-sign item). **constKey
posture (D-M5-27):** default = the per-version PackParts key (direct
extraction per the ruling); `packWatermarked(..., { sessionConstKey })`
optionally re-seals the pools under a fresh per-session key (better
anti-dump posture — a leaked decrypted bundle decrypts ONE session's
pools). Trade-off: the watermark lives inside the encrypted pools, so
session-key builds extract only with that session's key — the leak
workflow trials candidate session keys (an AEAD open IS the session
identification; admin-investigation cost, not a hot path). The runtime
receives whichever key via the payload (RUNTIME-M6 §2 entry c).

## 7. Per-build opcode permutation (doc §10.2 item 4)

Canonical→emitted map over a **64-slot universe** (D-M5-3):
deterministic Fisher-Yates driven by `SHA-256(seed || u32le(i))` blocks
(4 bytes per draw, `j = v mod (i+1)`), taking `map[k] = slots[k]` for
canonical ids k < 58. Slots ≥ 58 (i.e. slots not hit by any canonical id)
are **traps**: a decoder that maps an emitted byte to no canonical id must
refuse to load. Implementation: `opcodeMapFromSeed` / `inverseMap`
(opcode.ts) — intentionally simple and Luau-reimplementable (M6 may bake
the mapping into the generated runtime instead of deriving it at runtime;
both are conformant because the container only ever stores emitted bytes).

**Limitation (honest scope):** the container does not authenticate the
opcode INTERPRETATION — a wrong seed surfaces only through decode traps /
structural errors (probabilistically for small functions) or as a garbage
instruction stream. This is by design: production runtimes BAKE the
mapping, the seed never being a runtime input; the reference decoder's
wrong-seed rejection is best-effort robustness, not a security boundary.
The constant pools, functions and CRC are unaffected by the seed.

## 8. Limits (D-M5-15, Luau's documented limits)

200 locals per function (incl. parameters), 200 upvalues, 255 registers
(maxRegs), D16 constants inline with LOADKX/AUX escape beyond, jump range
±32767 instructions (AD) / ±8388607 (E). Compiler rejects violations with
`CompileError` before any bytes are emitted.

## 9. What v1 deliberately does NOT carry

No debug names, no line tables, no source text (D-M5-11 — metadata
leakage is a documented RE attack class). No coroutine/io/os/debug
library coverage in the reference interpreter (VERIFICATION-M5 lists the
full not-run set). IntExpr (`42i`) rejected at compile time (D-M5-10).

## 10. Conformance oracles shipped with M5

- `src/interpreter.ts` — reference executor (TS) for the canonical decoded
  form; the differential harness runs fixture SOURCE under real Lua 5.4.7
  and the protected form under this interpreter, requiring byte-equal
  stdout (D-M5-13). M6's generated runtimes are differentially tested
  against THIS interpreter (second-implementation rule, §22.1).
- `tests/opcode.test.ts` — encoding vectors (protobuf varints, RFC 1952
  CRC-32, FIPS 180-4 SHA-256, RFC 5869 HKDF), permutation invariants,
  pack/unpack round-trip incl. full instruction-stream parity, per-blob
  tamper localization, CRC/AEAD failure modes.
- *Conformance note (added 2026-10-11 after glm1's M6 differential;
additive, no byte change):* the interp-string lowering (D-M5-8) emits
`string.format` with `%*` placeholders. **Real hosts reject `%*`** — it
is a Luau-internal extension this container relies on by design. The TS
reference interpreter implements `%*` internally, so M5's own suite
cannot catch host-side `%*` rejection; a conformant runtime MUST provide
a `%*`-aware `string.format` to guest code (M6 ships a wrapped guest env
per D-M6-9 — that wrap is a conformance REQUIREMENT, not an optional
courtesy). Any future runtime inherits the same requirement.

## 11. Changes to this format

Format evolution = version bump in the container + a new section here
(Luau's own versioned-bytecode practice; old blobs retire at the loader's
discretion). Anything that changes BYTES a conformant runtime relies on
(opcode semantics, encodings, chain construction, layout) requires a
version bump. Additive notes that change no bytes (clarifications, M6
guidance) do not.

- 2026-10-11 (session 6): §1 byte-string model made FAIL-LOUD (D-M5-28):
  `pack` now throws on a str const code unit > 0xFF instead of silently
  truncating to `& 0xFF`. No container-format change — the encoding was
  already "varint length + raw bytes" (M4 byte-string model); the guard
  converts contract violations (UTF-8-decoded TEXT input — glm1's corpus
  2026-10-11 finding, 26/130 files) into an error at the exact violation
  point, mirroring the D-M5-22 junk-invariant posture. Root cause was the
  M6 corpus runner's `readFileSync(file, 'utf8')` input decode (M4
  contract is latin1); fixed in `vm/tests/corpus-e2e.ts` (marked). The
  `--wm` corpus gate is GREEN again: 0 MISMATCH. Byte-exact comparison
  adopted in the differential/watermark oracles (buffer stdout + latin1),
  with a new `byte-strings-unicode` fixture (raw UTF-8 + `\xFF` escapes,
  byte-equal vs real Lua 5.4). No version bump: bytes for conformant
  inputs are unchanged.
- 2026-10-11: §6.5 added — normative watermark-carrier pin (CCP-M7 v1,
  `packWatermarked`). Additive for v1 runtimes (no version bump); the
  junk bit-layout + permutation derivation become normative knowledge for
  the extractor side from this point on.
- 2026-10-11: §6.1 AAD changed to `magic || version || fcount ||
  SHA-256(functions)` (D-M5-26 — pool-sealing was quadratic in the functions
  section). TAG values change; blob layout does NOT. No version bump:
  nothing is deployed (pre-launch, all consumers in-repo) — M6's runtime
  template synced in the same session (vm/src/emit.ts decode: `aadh ..
  sha256(fns)`); glm1 notified. Old containers (pre-change) fail AEAD auth
  under new decoders — none exist outside test fixtures.
- 2026-10-11 (same session, earlier): R1 fix — the compiler's number-const
  DEDUP KEY changed from a computed `hi*2^32+lo` number (collides beyond 53
  significant bits) to the raw `hi:lo` pair. No container-format change
  (the pool serialization always carried exact f64 bytes); pools compiled
  before the fix could silently MERGE distinct doubles — rebuild affected
  builds.
- 2026-10-11 (session 7): arg-window placement fix (D-M5-29, glm1's third
  M5 finding) — compiler-side register discipline only: below-frontier
  calls (concat operands — right-nested trees now flatten BOTH sides into
  the single-CONCAT PUC shape; interp-string slots) compile args INTO the
  CALL window (coverReg alignment), SELF receiver lands at base+1, and
  compileTable stages SETLIST items at target+1 (latent gap bug the fix
  exposed). NO ISA, field, or container change: raw-frontier output is
  byte-identical; below-frontier output was previously miscompiled.
  Chained-key/AAD/pool layouts untouched.
