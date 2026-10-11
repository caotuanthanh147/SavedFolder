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

## §8 — Session 5 (2026-10-11: packWatermarked + R1/R2 + corpus end-to-end)

Claims, each with the command that produced it (run on the delivered tree):

1. **R1 fixed (glm3's finding, executable evidence was theirs in
   obfuscator/tests/analysis.test.ts):** the number-const dedup key now
   uses the raw u32 pair; the colliding doubles stay two pool entries and
   print distinctly end-to-end. Command:
   `cd ~/Public/obfuscator && bun test compiler/tests/opcode.test.ts` →
   `28 pass / 0 fail` incl. "R1: doubles differing below the 53-bit key
   ulp stay TWO pool entries", "R1: bit-exact round-trip", "R2: -0 takes
   the pool path (never LOADINT) and divides to -inf".
2. **CCP-M7 v1 implemented (packWatermarked + PackParts + extractor):**
   29 new tests. Command:
   `bun test compiler/tests/watermark.test.ts` → `29 pass / 0 fail` —
   v1-runtime transparency (all 17 differential fixtures re-run through
   WATERMARKED containers vs real Lua 5.4.7, byte-equal stdout), exact
   watermark recovery + carrier-1 consistency, canonical→null, two
   sessions from one parts (unique containers, each recovers its own
   watermark), determinism (same inputs → byte-identical; nonce or
   watermark change → different bytes), corrupted-JSON ingestion fails
   closed, junk bytes survive the JSON round-trip, >256-const chain
   (block-boundary safety + invariant).
3. **Full merged suites:** `cd ~/Public/obfuscator && bun test` →
   `396 pass / 0 fail, 12705 expect() calls, 16 files, 16.43s`;
   `cd ~/Public/obfuscator/vm && bun test` → `63 pass / 0 fail, 15.78s`;
   `npx tsc --noEmit` clean in both packages.
4. **Corpus end-to-end (§10.3, structural — corpus scripts cannot EXECUTE
   outside a Roblox world, stated in the runner header):** 131-corpus
   restored from git object 4e974c3 into /tmp (no working-tree pollution):
   `bun run compiler/tests/corpus_compile.ts /tmp/corpus131/obfsucatortest` →
   `files: 130  parse-rejects: 3  compiled: 127  compile-rejects: 0 /
   functions: 19325  instructions: 961673  pool entries: 178302 /
   watermarked+inverse+extraction OK: 127/127  ALL GREEN`.
   Private corpus (SavedFolder work/lua): same command with
   `/home/z/SavedFolder/work/lua` → `49/49 ALL GREEN` (1 parse-reject =
   potato-harness-core.lua, Lua 5.3 `>>`, out of Luau spec).
   The runner asserts per function: canonical pack/unpack instruction+
   const parity; watermarked pool = permuted live + junk tail with every
   live VALUE at its perm position; referenced set == live set; every
   K operand === perm(canonical operand) (the forward-map check —
   semantic preservation at the pool-reference level); extraction
   recovers the exact watermark + carrier-1 consistency.
5. **D-M5-26 (hash-bound AAD) measurement:** before:
   `pack(protos)` on Alliance.lua (296 protos / 18,210 insns) ≈ 2.0s per
   pack (instrumented section timers: pool loop 1,925ms of 1,981ms;
   aeadSeal ×300 with the ~20-90KB functions-section AAD = 418ms vs 11ms
   with a 200B AAD). After: corpus-wide 130-file run ~20s total including
   2 packs + 2 unpacks + extraction per file. M6 runtime sync:
   `vm/src/emit.ts` decode template now computes the same
   `head || sha256(functions)` AAD — vm suite 63/63 after the sync
   (was 20/63 with the old template vs new containers).
6. **Compiler bug fixes the corpus exposed (each reproduced → minimal
   shape → fixed → regression-covered):**
   - plain `function foo() end` (Global name) and `function f() end`
     (visible-local name) statements were unsupported — compileFunctionStat
     only handled `function a.b() end` (Camera.lua-class reject, 125/130).
   - compileCall's post-call frontier RESET dropped caller reservations
     when a call sat below the live frontier (method call as a concat
     operand — Camera.lua UpdateMacroLabel; same shape reachable via
     interp-string expression slots). Fixed: frontier = max(results
     window, entry frontier).
   - closeScope's `freeReg = localBase` reset dropped caller reservations
     made before openScope (IfElse expression compiled into the
     return-value slot — CountryRNG.lua / Zombies.lua). Fixed: floor at
     the scope's entry frontier.
   - arithK peek pollution: the two `addNumber`-then-check sites added
     unreferenced pool entries when the index exceeded the 8-bit C
     operand (breaks the junk-detection invariant). Fixed with
     peekNumberIndex (D-M5-22); regression = the >256-const chain test.
7. **Artifacts:** src/watermark.ts (new, ~560 lines), src/compile.ts
   (R1/R2 + FunctionStat + register-accounting fixes + peekNumberIndex),
   src/container.ts (poolNonces option + hash-bound AAD), src/index.ts
   (exports), tests/watermark.test.ts (new), tests/opcode.test.ts (R1/R2
   regressions), tests/corpus_compile.ts (new runner),
   vm/src/emit.ts (AAD sync, clearly marked), BYTECODE-M5.md (§6.1 AAD
   + §6.5 watermark pin + §11 changelog), DECISIONS-M5.md D-M5-21..26,
   this section.

5b. **D-M5-27 (session constKey option, glm1's co-sign follow-up):**
   `bun test compiler/tests/watermark.test.ts` → 30/30 incl.
   "session-random constKey: packs under the override, per-version key
   cannot open (AEAD auth failure), override key extracts (watermark +
   carrier-1 green)".
**NOT-RUN (honest):** no real-Workers CPU measurement (M1/M12's lane per
the ruling's cost model — the local measurement in item 5 is the proxy);
no real-executor runs of watermarked containers (M6's D2 lane); corpus
scripts not EXECUTED (Roblox-world globals — structural proof only, plus
the 17-fixture execution differential on watermarked containers); carrier
3 (v2, per the ruling); no CPU benchmark of extractWatermark on adversarial
inputs. Val-descriptor emission (IR.md Interface B consumption) NOT started
this session — M4's analysis.ts landed mid-session and is advisory; next
M5 session's lane.

## §9 — Session 6 (2026-10-11: the str-encoding corpus finding — root cause + fail-loud guard + gate re-green)

glm1's M6 session-22 msg (msgs/glm6/2026-10-11-glm1-m6s2-wm-e2e-strfinding.md)
reported "container str encoding LOSSY for code units > 0xFF", 26/130 corpus
files, `--wm` gate left EXPECTED-RED for me. Investigation, fix, and evidence
below; every claim carries its command + output (§22.1).

**Root cause (evidence-first, before any code):** the container's
charCodeAt&0xFF pack is byte-exact for the DOCUMENTED M4 interchange contract
(byte-string model: latin1 char-per-byte — `obfuscator/src/index.ts` header,
`buf.toString('latin1')`). The loss entered at glm1's corpus runner input
decode: `vm/tests/corpus-e2e.ts` L122 `readFileSync(file, 'utf8')` — raw
UTF-8 source bytes (em-dashes/emoji in game-UI text) decoded to single code
units > 0xFF BEFORE my code ever ran. Repro (both paths, same file):

```
$ bun run vm/tests/glm6-repro-str.ts        # session scratch, deleted after capture
file bytes      : ... 3a e2 80 94 65 ...    (em-dash = e2 80 94)
oracle stdout   : hex 656d2d646173683ae28094656e640a
(a) utf8 read   : const code units = [... 2014] (len 12) → round-trip "em-dash:\u0014end" → matches oracle? false
(b) latin1 read : const code units = [... e2 80 94] (len 14) → round-trip byte-exact → matches oracle? true
```

Decision: keep the byte-string encoding (Lua 5.4 manual §2.1, opened via
curl: "The type string represents immutable sequences of bytes … 8-bit clean
… encoding-agnostic" — a UTF-8-in-pool re-encode corrupts `\xFF` escapes and
binary consts), add a FAIL-LOUD pack guard (D-M5-28), fix the runner's input
decode (marked, owner notified), and make the test oracles byte-exact.
Alternatives compared in DECISIONS-M5 D-M5-28.

**Commands + outputs (this session):**

1. BEFORE fix — reproduce glm1's gate (his runner, unmodified):
   `bun run vm/tests/corpus-e2e.ts /tmp/m5-corpus/obfsucatortest --wm`
   → `MISMATCH: 26` (all "watermark extraction: extraction failed post-pack"),
   `parse-reject: 3`, exit 1 — matches his report exactly.

2. Fix applied: `compiler/src/container.ts` appendConst — throws
   "string const violates the byte-string model" on any code unit > 0xFF
   (no format change; D-M5-28). `vm/tests/corpus-e2e.ts` L122 →
   `readFileSync(file).toString('latin1')` + L56 write `'latin1'`
   (both marked `// glm6 2026-10-11 str-model fix`; glm1 owns the file,
   notified via msg). Differential + watermark oracle I/O made byte-exact
   (spawnSync `encoding:'buffer'` + `.toString('latin1')`).

3. New regression tests: differential fixture `byte-strings-unicode`
   (raw em-dash U+2014 / emoji U+1F600 / CJK U+4E2D U+6587 / bullet U+2022 /
   `\xFF`+`\x80\x7F` escapes / concat / `#` length — AST consts hold the
   UTF-8 BYTE sequences) + watermark tests: pack throws on text consts
   (plain AND watermarked paths), high-byte live pools round-trip byte-exact
   with watermark lockstep green.

4. `cd obfuscator/compiler && bun test` → **83 pass / 0 fail** (461 expects;
   was 80 — +1 differential fixture, +3 byte-string contract tests).

5. `cd obfuscator && bun test` (root, M4 suite) → **462 pass / 0 fail**.

6. `cd obfuscator/vm && bun test` → **113 pass / 0 fail** (500 expects;
   glm1's 28 watermark-e2e runtime tests re-verified on the fixed tree).

7. tsc ×3 (glm4's sweep lesson — all THREE tsconfigs, not ×2):
   root `./node_modules/.bin/tsc --noEmit` → clean;
   `compiler` → clean; `vm` → clean.

8. Corpus gates AFTER the fix (131-corpus, git 4e974c3, fresh extract):
   `bun run vm/tests/corpus-e2e.ts /tmp/m5-corpus/obfsucatortest --wm`
   → **MISMATCH: 0**, exit 0 (was 26/exit 1);
   plain mode → **MISMATCH: 0**, exit 0.
   The `--wm` gate is GREEN; glm1 can drop the EXPECTED-RED posture.

**NOT-RUN (honest):** stdout compared as decoded strings in glm1's runner
(spawnSync `encoding:'utf8'`) — byte-equal outputs compare equal, but two
DIFFERENT byte sequences with invalid UTF-8 could theoretically decode equal
(false-pass direction only); recommendation msg'd to glm1 (buffer compare is
his call — minimal footprint in his file). Real-executor runs, real-Workers
CPU, carrier 3: unchanged lanes from §8's NOT-RUN list.

## §10 — Session 7 (2026-10-11: glm1's third M5 finding — arg-window placement — CLOSED)

**The finding (msg glm1-20261011T0900Z.md):** compileCall compiled fixed
args via `reserve(1)` at the ALLOCATION FRONTIER while `CALL A=base B=n+1`
reads its window at base+1 (base+2 for self calls). Any call compiled
below the live frontier — concat-chain operand positions (right-nested
trees from the M4 parser bypassed the left-spine-only flattenConcat),
interp-string expression slots — misplaces args. His repros: r7
(`print("a"..g(1)..","..g(2))` → arithmetic-on-nil), r2
(string.byte pair → bad-argument), r13 (pcall/tostring → `a=nil b=R`),
r9 (parenthesized). Invisible to the corpus (deobf material restructures
concat chains; error-parity scripts die at executor boundaries first).
Fixed by me this session (D-M5-29), plus the SELF path he flagged for
sweep, plus BOTH-SIDE flattenConcat (his suggestion), plus one LATENT
compileTable bug the fix exposed (SETLIST staged at the frontier, reads
contiguously at target+1 — table args in window slots staged with a gap).

**Reproduction BEFORE the fix (evidence-first; scratch runner through the
real M4 parser → M5 compile → pack/unpack → reference interpreter):**
r7 oracle `"a2,3\n"` vs protected `"<RUNTIME-ERROR> attempt to perform
arithmetic on a nil value"`; r2 `bad argument #1 to 'string.byte'`;
r13 `"a=nil b=R\n"`; r9 arithmetic-on-nil; nested-call class
arithmetic-on-nil — 6 of 10 scratch cases failing.

**Fix shape (compile.ts):** `coverReg(ctx, r)` (mirrors reserve()'s
overflow check + maxRegs bookkeeping) aligns the frontier to each window
slot; fixed args compile into `argStart+i`; multret-last opens at the
window's end; SELF receiver compiled AT base+1 (replaces the
frontier-temp + release/re-reserve dance); flattenConcat flattens BOTH
sides (single-CONCAT PUC shape restored; __concat pair order unchanged);
compileTable stages at `target+1+count` with entryFree restore. Raw-
frontier instruction streams proven byte-identical (instruction-by-
instruction analysis in D-M5-29 + all 17 pre-existing differential
fixtures unchanged-green).

**Commands and outputs (fresh clone of this delivery's tree):**

    $ cd obfuscator/compiler && bun test          # 107/107 pass, 485 expects (x3 runs)
    $ cd obfuscator && bun test                   # 490/490 pass, 32807 expects (19 files)
    $ cd obfuscator/vm && bun test                # 117/117 pass, 524 expects
    $ for d in . compiler vm; do (cd $d && bunx tsc --noEmit); done   # ×3 clean
    $ cd obfuscator/vm && bun run tests/corpus-e2e.ts /tmp/corpus-4e974c3/obfsucatortest
      # MISMATCH: 0, parse-reject: 3 (known: Dupe corrupt / DinoHunters / WaveDefense),
      # compile-reject: 0, oracle-fail: 0, no-output: 0, nondeterministic: 0, emit-reject: 0
    $ bun run tests/corpus-e2e.ts /tmp/corpus-4e974c3/obfsucatortest --wm
      # exit 0 — MISMATCH: 0 (same buckets; --wm extraction lockstep green per file)
    $ cd obfuscator/compiler && bun run tests/corpus_compile.ts /tmp/corpus-4e974c3/obfsucatortest
      # files: 130  parse-rejects: 3  compiled: 127  compile-rejects: 0
      # functions: 19325  instructions: 959164  pool entries: 178302
      # watermarked+inverse+extraction OK: 127/127  ALL GREEN (exit 0)
    $ bun run tests/corpus_compile.ts ~/SavedFolder/work/lua
      # files: 50  parse-rejects: 1  compiled: 49  compile-rejects: 0
      # watermarked+inverse+extraction OK: 49/49  ALL GREEN (exit 0)
    $ cd obfuscator/vm && bun run tools/obfuscate.ts demo/lp1-demo.lua /tmp/r1.obf.lua --seed lp1-demo-001 --dispatch closure
    $ bun run tools/obfuscate.ts demo/lp1-demo.lua /tmp/r2.obf.lua --seed lp1-demo-001 --dispatch closure
    $ cmp /tmp/r1.obf.lua /tmp/r2.obf.lua               # determinism: byte-identical
    $ lua5.4 /tmp/r1.obf.lua > a.txt; lua5.4 demo/lp1-demo.lua > b.txt; cmp a.txt b.txt
      # DEMO DIFFERENTIAL BYTE-EQUAL (regenerated artifact, post-fix compiler)

**Regression suite added:** `compiler/tests/window.test.ts` — 24
parse-based differential tests (real M4 parser; oracle = real Lua 5.4):
glm1's r2/r6/r7/r9/r10/r13 classes + SELF-with-args below frontier +
multret-last (shallow + deep 5-chain) + vararg multret + table args
(List/Record/computed-key/table-call syntax in window slots — the latent
compileTable bug) + nested tables in call args + 7-operand mixed chain +
doubly-nested call args + 2 interp-string cases (protected-side expected
output — plain lua5.4 cannot parse backtick syntax, fixtures.ts
discipline).

**NOT-RUN (honest):** real-executor runs (D2 lane, unchanged); the
delivered demo artifact `demo/lp1-demo.obf.lua` itself was NOT regenerated
in-repo (glm1's artifact, built pre-fix; regeneration verified equivalent
in /tmp — his call whether to rebuild in-repo); corpus e2e runners are
glm1's files (no edits made this session); M4/M6 suites re-run as
delivered, no changes to their trees.
