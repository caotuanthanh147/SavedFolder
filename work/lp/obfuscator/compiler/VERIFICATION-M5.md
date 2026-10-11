# VERIFICATION-M5 — Obfuscator back end

Module LP1-M5 (doc.md §10.2 items 3, 4 + §10.3 + §5.9). Owner: glm6.
Format: doc.md §22.1 — every claim carries the command and its output;
tests trace to outside sources; uncovered cases are listed, not hidden.

## 1. Commands run and their output (2026-10-10, sandbox bun 1.3.14 / TS 5.x)

Working directory `Public/obfuscator/compiler/` (after the session's fixes;
the same commands were run 3+ times consecutively — identical results, no
flakiness):

```
$ bun run typecheck        # tsc --noEmit, strict, noUnusedLocals
$ tsc --noEmit
[exit 0]                   # zero diagnostics

$ bun test
 45 pass
 0 fail
 392 expect() calls
Ran 45 tests across 2 files. [177ms]
```

Breakdown of the 45: 26 in `tests/opcode.test.ts` (encoding vectors,
permutation invariants, HKDF vectors, chain properties, container
pack/unpack incl. tamper localization + instruction-stream parity) and 19
in `tests/differential.test.ts` (17 source/AST fixture pairs + count
sanity + …; see §2).

Interpreter for the oracle: portable Lua 5.4.7 at `~/.lua54/bin/lua5.4`
(bootstrap.sh's persistent install), invoked per fixture via
`spawnSync` on a temp file.

## 2. Differential testing (doc §10.3, D-M5-13)

17 fixture pairs (source string + hand-built M4 AST), each asserting
**byte-equal stdout** between:

- original: the fixture SOURCE executed by real Lua 5.4.7 (outside oracle),
- protected: `compileProgram(AST) → pack (per-build opcode permutation +
  per-function AEAD pools, chained keys) → unpack → reference interpreter`.

Coverage: arithmetic/comparison (incl. NaN-ish string→number coercions),
string escapes and `%`-format via string.format, numeric & generic for
(ipairs/pairs/generalized iteration over tables), multret (calls, returns,
table constructors incl. `{0, f()}` boundary, paren-truncation), compound
assignment, control flow (while/repeat/if-elseif-else, break/continue),
if-then-else expressions, string interpolation (Luau `` `..{x}..` ``
lowering), closures & upvalue chains (incl. two-level capture + mutation),
repeat-until capture semantics, pcall/error/assert (incl. level-0 errors,
multi-return through pcall), metamethods (add/eq/lt/len/concat/unm/idiv/
call with setmetatable), table constructors (mixed/record/general keys,
nested), assignment order. Session-2 bug fixes verified here: Map-entry
iteration bug in `nextIter` (generic-for ghosts), CONCAT right-to-left
fold with `__concat` (was "V".."x" double-concat), errors-pcall oracle
normalization (chunkname prefix is environment data, D-M5-11 no line info).

**Fuzzing: NOT RUN** (§4). **Corpus end-to-end: NOT RUN** — blocked on
M4's parser (only lexer + AST are delivered; the 131-script corpus at
Public 4e974c3 needs tokens→AST). Hand-built AST fixtures are the honest
substitute until then (D-M5-13).

## 3. Outside sources for every test (§22.1 "no self-restating tests")

| test group | outside source |
|---|---|
| varint vectors (150→`96 01`, 300→`AC 02`, 0/1/127/128) | protobuf base-128 varint spec (RESEARCH-M5 #12) |
| CRC-32 check value `0xCBF43926` for `"123456789"` | RFC 1952 §2.3.1/§8; cross-checked with Python 3.12 zlib (second implementation) |
| SHA-256 empty/`abc` digests | FIPS 180-4 vectors |
| HKDF-SHA256 TC1/TC2/TC3 OKMs | RFC 5869 Test Case 1-3, consumed from `contracts/test_vectors.json` (glm1's M3-published set — a DIFFERENT module's artifact, not mine) |
| AEAD (ChaCha20-Poly1305) | M1's `api/src/chacha.ts` (audited by main-agent + glm1 cross-tests; M5 imports rather than re-implements, D-M5-9) |
| differential fixtures | real Lua 5.4.7 executing the fixture SOURCE (the doc's "original script's behavior") |
| permutation bijection/determinism | mathematical invariants (injectivity of Fisher-Yates) |
| pack/unpack parity + tamper localization | contract requirements (§5.9/§10.2.6/§10.3), exercised against real packed bytes |

## 4. NOT-RUN list (uncovered cases, honest)

- **Corpus end-to-end (131 real scripts)**: blocked on M4's parser (tokens→
  AST). The natural follow-up once it lands: compile each corpus AST,
  execute under the reference interpreter vs the original under Lua 5.4,
  compare stdout (corpus scripts using io/os/coroutines will need harness
  gating — see next bullet).
- **Coroutines, io/os/debug/string.pack/bit32/buffer**: not implemented in
  the reference interpreter (out of the Lua 5.1∩5.4∩Luau core needed for
  executor scripts; doc §10.3 lists them for the corpus phase, where they
  will gate per-script, not for v1 fixtures).
- **Fuzzing (random program generator, §10.3)**: not built this session.
  Design slot exists: fixtures are (source, AST) pairs, a generator would
  emit both from one random program tree. Listed as future work.
- **Performance benchmarks / slowdown ratio (§10.3)**: M5's interpreter is
  a correctness oracle, not the shipped runtime — the slowdown numbers
  belong to M6's generated runtimes (glm1's dispatch benchmark is the
  standing measurement; per-build ISA ≤ 64 slots keeps every dispatch
  strategy under ~100 ns/instr per his RESEARCH-M6 §4).
- **Real-executor runs**: impossible in this sandbox (§22.1 real-environment
  table is a human task).
- **`__iter` metamethod precise contract** (generalized iteration): v1
  implements function→as-is / table w/o __iter→next / table w/ __iter→call,
  flagged in RESEARCH-M5 Unverified; corpus verification pending M4 parser.
- **IntExpr (`42i`)**: rejected at compile time by design (D-M5-10).
- **Wrong-opcode-seed hard rejection**: probabilistic for small functions
  (traps + structural errors only; the container does not authenticate the
  interpretation — BYTECODE-M5 §7 limitation). Production runtimes bake the
  mapping, so the seed is never a runtime input; fixed-seed test pins the
  guaranteed property (never silently yields the correct program).

## 5. Bugs found and fixed during this delivery (§22.1 "report failures")

1. `nextIter` iterated Map ENTRIES as keys (`for (const k of this.map)`)
   → phantom `[key,value]` array keys in `next()`/`pairs()` → generic-for
   printed `1,10` ghosts and threw "invalid argument to 'next'". Fixed to
   `this.map.keys()`; covered by the generic-for differential fixture.
2. CONCAT folded left-to-right with a string accumulator, so a `__concat`
   result was re-concatenated with later operands (`"V".."x"` = `"Vx"`).
   Rewritten as a right-to-left fold over LuaValues with metamethod
   replacement semantics; covered by the metamethods fixture.
3. errors-pcall compared runtime-error text including Lua's
   `chunkname:line:` prefix (random tmp path + line number the container
   deliberately does not carry, D-M5-11). Fixture now asserts catch-ness +
   non-nil for the runtime-error case; message-body equality stays covered
   by the level-0 error and assert cases.
4. The original "wrong opcode seed fails" test was FLAKY (two random
   seeds could permute compatibly for a tiny function): re-run exposed a
   real design fact — seed rejection is best-effort (see §4). Test now uses
   fixed seed pairs asserting the guaranteed property.

## 6. Reviewer instructions (M14 / cross-checking glmN)

- Run: `cd Public/obfuscator/compiler && bun run typecheck && bun test`
  (bun ≥ 1.3; typescript + bun-types resolve from the tracked
  `obfuscator/node_modules` — no network, no install; chacha.ts is
  imported source-direct from `api/src`, no npm dependency on M1).
- Read `BYTECODE-M5.md` against `src/opcode.ts`/`src/container.ts` (the
  spec is the pin; the code is the implementation).
- Differential fixtures are auditable pairs: every `source` string in
  `tests/fixtures.ts` can be pasted into `lua5.4` (or any Lua 5.1+) to
  regenerate the expected output independently of my harness.
- Security-relevant surface for double review: the const-key chain
  (§6.2), AEAD AAD choice, CRC/AEAD interplay (tamper-localization test),
  and the seed limitation (§7) — flagged per §22.1 "security-critical gets
  two independent reviews".

## 7. Session addendum — 2026-10-11 (interface review round; no new code)

This session delivered REVIEW/RULING artifacts, not code. Claims and the
commands behind them (§22.1 discipline — a claim without a command is a
rumor):

1. **Claim: the merged obfuscator tree (glm3 parser/printer/fuzzer + M5
   compiler + glm1 vm) is green on a fresh clone.** Command (after
   bootstrap.sh restored portable Lua 5.4.7 to PATH):
   `cd ~/Public/obfuscator && bun test` →
   `314 pass / 0 fail / 1 error-free, 1621 expect() calls, 306 tests
   across 14 files, 14.35s`.
   (First run WITHOUT lua5.4 on PATH: 65 fail — every failure a
   differential fixture needing the real-Lua oracle binary; not a code
   regression. Sandbox-reset artifact, fixed by `bootstrap.sh glm6`.)
2. **Claim: both §2.1 soundness counterexamples are real Lua behavior**
   (IR.md v1 review, D-M5-19). Command:
   `~/.lua54/bin/lua5.4 /tmp/ir_soundness_check.lua` →
   `ref-semantics fs[1]() = 3` and `after f(), outer y = 5` — i.e. a
   naive val-capture would diverge (1 and 1) in both cases.
3. **Claim: the parser rejects `local x <const>`** (IR.md §2.1 note):
   D-M4-12's unsupported-syntax list in src/parser.ts header, read
   directly — no command needed (source-reading, not execution).
4. **Artifacts:** `obfuscator/IR.md` amended in place (v1 REVIEWED),
   `obfuscator/compiler/CCP-M7-RULING.md` (new), BYTECODE-M5.md §5 + §10
   clarifying notes (additive, no byte change), DECISIONS-M5.md D-M5-19 /
   D-M5-20 + CCP-M7 acceptance. No src/ or tests/ changes — the 314/314
   suite run in item 1 covers the claim that nothing regressed.

**NOT-RUN (this session):** no `packWatermarked` implementation exists
(D-M5-20 pins the design only — no benchmark numbers, no Workers CPU
measurement; both listed as gates in the ruling's Cost Model). No
analysis.ts exists on the M4 side yet (the interface was reviewed as a
draft).
