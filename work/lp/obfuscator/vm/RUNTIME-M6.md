# RUNTIME-M6 — Generated VM runtime contract (normative)

Owner: glm1 (module M6). Status: **pinned, v1**. This document defines
what `obfuscator/vm` (generateRuntime) emits and the contract the
surrounding pipeline (M13 init assembly, M1 payload contents, M3 loader
handshake) relies on. BYTECODE-M5.md stays the normative pin for the
container; this pins the runtime that consumes it.

---

## 1. Shape

`generateRuntime` returns Lua **5.1-syntax-safe** source (no `goto`, no
`//`, no compound assignment, no `continue`; luac5.4 -p gate in the test
suite) that, when loaded as a chunk, evaluates to the **entry function**
(compatible with M13's stub→init contract D-M13-6: the stub `pcall`s the
chunk and expects a function).

Per-build randomization (deterministic from the 32-byte `vmSeed`):
dispatch strategy {if/elseif chain, balanced comparison tree, closure
table}, random branch/definition orders, optional runtime-built handler
table (numeric re-indexing through a baked permutation), \ddd vs hex
container embed, randomized identifier set, junk locals + opaque
predicates, numeric literal forms. Same `vmSeed` + `opcodeSeed` +
container ⇒ byte-identical output (tested).

**Two emit modes (v1.1):** `container: <bytes>` embeds the container
(original shape — harness + one-artifact use); `container: null` emits a
CONTAINERLESS runtime: no blob/hash literals, and the container arrives
per entry call via `b` (§2). Containerless is the DEPLOYMENT shape of
doc §8 step 10 — the runtime lives in the immutable init build
(M13 content-addressed), the container is delivered per-session as the
`bundle` over the M1 payload wire (CCP-M7 D-M5-20 option A makes those
bytes per-session watermarked).

## 2. Entry table (consumed)

| field | type | meaning |
|---|---|---|
| `s` | string, 0..64 bytes, optional | §5.6 per-fetch value (from the stub). Length/type violation ⇒ silent decoy path (§4) |
| `c` | string, exactly 32 bytes | **constKey** (M5 PackOptions.constKey) — delivered per session via the encrypted payload (M1 wire), never baked into the runtime |
| `b` | string, optional (REQUIRED in containerless builds) | **LPVB container bytes** — the per-session bundle. Non-string / shorter than the 42-byte floor ⇒ silent decoy path (§4). Embedded builds ignore it |
| `env` | table, optional | guest environment; defaults to `_G` |
| `args` / `nargs` | array + count, optional | guest vararg main arguments (the chunk proto is vararg) |
| `dbg` | table, optional | countHook builds only: filled with `count`, `ops`, `pools` |

Unknown fields are ignored. The entry returns all guest main return
values.

The runtime hands the guest a **wrapped env**: reads fall through to
`env`/`_G`, guest `SETGLOBAL` writes THROUGH to it (rawset), and only
`string` is replaced by a %*-aware table (D-M6-9) — M5 lowers Luau
interp-strings to `string.format` with `%*` (RESEARCH-M5 #4), which real
Lua 5.1/5.4 `string.format` rejects.

## 3. What the runtime embeds

Embedded builds:

- the **LPVB container** (per-build escaped or hex-encoded),
- the container's **build hash** (32B) — integrity anchor (§4 embedded
  leg),
- the **inverse opcode map** derived from the pack-time `opcodeSeed`
  (the seed itself never appears; traps refuse to load, BYTECODE-M5 §7),
- shape/aux tables for all 58 canonical opcodes,
- vendored pure-Lua crypto (byte-identical copies of M3
  `loader/crypto/{bit,sha2,hmac,hkdf,chacha20,poly1305,aead}.lua` +
  the M13-family FNV-1a32/DJB2 pair).

Containerless builds embed everything EXCEPT the container and its hash
literal (a `b`-shaped entry consumes them per call); the inverse opcode
map still pins the per-VERSION opcodeSeed — the api-side per-session
pack (CCP-M7 option A) MUST pack under the same seed or the runtime
dispatches through the wrong permutation (traps/garbage).

## 4. Integrity feeds derivation — never a detectable branch (§10.2 item 9)

At entry the runtime computes SHA-256 over the container's hashed-bytes
region (magic|version|fcount|functions|pool, excluding the hash field
and CRC trailer) and the per-fetch `s` validity, and uses them to SELECT
the chain root. The hash LEG depends on the emit mode:

- **embedded builds**: the recomputed hash is compared against the
  build-time hash PINNED as a literal in the runtime — tamper ⇒ decoy.
  This pin is only legitimate for the one-artifact shape (the runtime
  and its container ship together).
- **containerless builds (v1.1, CCP-M7 D-M5-20)**: SELF-CONSISTENCY —
  the recomputed hash is compared against the DELIVERED container's own
  hash field (bytes 6..37). Per-session watermarked containers (the
  packer writes the session hash over the final bytes) flow through
  unchanged; tamper-without-rehash ⇒ decoy; rehash-without-constKey ⇒
  AEAD garbage (the honest-forging boundary is the ruling's, not ours).

Both legs select identically:

- hash matches + `s`/`c` well-formed ⇒ `K_0 = HKDF(c, ∅, "const-key")`
  (the pinned M5 chain, BYTECODE-M5 §6.2), or
- anything off ⇒ `K_0 = HKDF(bh, bh[1..8], "const-key")` — a **decoy**
  derivation: constants decrypt to garbage (AEAD tag failures surface as
  a generic `load failed`, never an explanatory message).

Tampering with the embedded container therefore corrupts DECRYPTION
instead of tripping a labeled check. The CRC-32 trailer is deliberately
NOT verified by the runtime (D-M6-7): AEAD tags + build hash are the
integrity mechanisms; CRC is transport-layer, and M13's stub already
validates the whole served file (size + FNV/DJB2, D-M13-5).

Build-time leg (pipeline): `deriveConstKey(masterKey, vmChecksums)` =
`HKDF-SHA256(masterKey, salt = u32be(fnv)|u32be(djb2), info =
"vm-const-key", 32)` — the checksums are FNV-1a32+DJB2 over the emitted
**code region** (everything except the container/build-hash literals).
Pipeline order (non-circular, tested for code-region stability):

```
vmSeed, opcodeSeed  →  emit(placeholderLength)  →  vmChecksums
                   →  constKey = deriveConstKey(master, vmChecksums)
                   →  pack(protos, { constKey, opcodeSeed })        (M5)
                   →  emit(container, same seeds)  →  init source
```

## 5. Constant pools — lazy, order-independent (§10.2 item 6)

Pools decrypt on first touch (blobs are skippable via their ctLen
prefix). Derived keys are memoized per entry call (KS[i] = K_{i-1}), so
ANY access order pays each HKDF step at most once and always uses the
right chain position — a walk-forward-only cache would miskey pool i<j
after j (bug found and fixed during development, see VERIFICATION-M6).

## 6. Dispatch (§10.2 item 5)

One semantic source per opcode (handlers.ts) is shared by every
strategy, so strategy choice cannot change semantics; the instruction-
count parity gate + differential suite verify this per build family.
Goto-free everywhere. Closure-strategy handlers return either nil
(continue) or the RETURN values pack.

## 7. Conformance notes / known divergences (v1)

- **Arithmetic/comparison/metatables/native stdlib**: host-native —
  the runtime executes on the same engine the guest source would
  (oracle-true by construction). Documented edges: `x % 0` and `x // 0`
  follow the HOST (5.4 errors; M5's TS interpreter returns NaN/±inf —
  no fixture exercises them, D-M6-8); IDIV is `math.floor(x/y)` with
  M5-mirrored ±inf/NaN edges plus manual `__idiv` dispatch (no `//`
  operator dependency).
- **f64 → Lua number**: integral floats integerize via
  `math.tointeger` when present (5.4/Luau) — matches the oracle for
  integer-literal scripts; whole-float literals (`3.0`) print as `3`
  (fixture discipline excludes them; D-M6-8).
- **Runtime-source self-integrity**: a Lua chunk cannot read its own
  source portably (debug/io restricted on executors), so the runtime
  binds the container bytes + build hash, and whole-file integrity is
  M13's `r` validation; deeper self-checksumming is a D2-class
  follow-up. Not silently assumed — listed in VERIFICATION-M6 NOT-RUN.
- **Guest pcall** can catch lazy-pool AEAD failures that occur during
  execution (M5's eager reference decrypts before running). Fixtures do
  not exercise; documented.
- **env identity**: guest sees the wrapped env (§2); `env == _G`
  comparisons inside guest code fail. `env._G` still reaches the real
  `_G`.
- **%\* interp-strings (D-M6-9)**: M5 lowers Luau interp-strings to
  `string.format` with `%\*` (BYTECODE-M5 §10) — the wrapped `string`
  table is a CONFORMANCE REQUIREMENT for any runtime of this container,
  not a courtesy (real hosts reject `%\*`).
- **kind-0 upvalues (BYTECODE-M5 §5)**: immutable plain value frozen at
  NEWCLOSURE; SETUPVAL against kind-0 is impossible-by-construction
  (M4 analysis proves single-write-anywhere); conformant runtimes may
  trap on it. v1 containers carry zero kind-0 descriptors (M5 emits
  ref-only), so this is a forward pin, not a live path.

## 8. Changes to this contract

- **v1.1 (2026-10-11)**: additive — entry field `b` + containerless
  emit mode (`container: null`) + the §4 self-consistency leg. Entry
  fields remain a superset; embedded builds are byte-for-byte the v1
  behavior (63/63 suite re-run green). CCP-M7 D-M5-20 co-sign delivered
  with this change.

Additive entries (new optional entry fields, new per-build variants)
may land without a version bump; anything consumers rely on
structurally (entry field semantics, chunk-returns-entry, wrapped-env
behavior) requires a version bump here + a note to M13/M1 owners.
