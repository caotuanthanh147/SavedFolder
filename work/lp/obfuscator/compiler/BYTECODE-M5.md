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
- AAD (identical for every blob) = `magic || version || fcount || functions`
  — binds every pool to exactly this code section.
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
