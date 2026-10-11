# VERIFICATION-M6 — Verification transcript (doc §22.1)

Owner: glm1. All commands run in this sandbox on 2026-10-10 (session 20,
M6 implementation). Fresh clones of the module trees were used for the
final pass (see §5). Oracle = portable Lua 5.4.7 (PUC-Rio, `~/.lua54`),
the same outside oracle M5's differential harness uses.

## 1. Commands + raw output

```
$ cd obfuscator/vm && bun run typecheck
$ tsc --noEmit
(no output — clean)

$ bun test
 63 pass
 0 fail
 258 expect() calls
Ran 63 tests across 7 files. [13.77s]
```

Suite map (all green):

| file | what it proves |
|---|---|
| tests/differential.test.ts | all 18 M5 fixtures: SOURCE under real Lua 5.4.7 vs the protected form (M5 compile→pack→M6 runtime) under the SAME real Lua 5.4.7, byte-equal stdout, for every strategy (chain, tree, closure, closure+runtime-built). Plus 8 fixtures vs M5's TS reference interpreter (second-implementation rule, BYTECODE-M5 §10). |
| tests/portfolio.test.ts | 5 vmSeeds × 3 opcodeSeeds per fixture all oracle-equal (per-build randomization changes nothing observable); permutation invariance; 12 distinct vmSeeds → 12 byte-distinct runtimes across ≥3 strategy shapes; determinism (same seeds → identical bytes + checksums). |
| tests/parity.test.ts | instruction-count parity gate (RESEARCH-M6 §4 lesson): chain == tree == closure == closure+built executed-instruction counts per fixture (countHook builds), pool-load counts equal across strategies; opcode coverage: every opcode M5's compiler emits across the fixture set IS executed; lazy-decrypt: pools load only on touch. |
| tests/tamper.test.ts | §10.2 item 9: bit flips (functions section / AEAD tag region), wrong constKey, short constKey, oversized per-fetch `s`, wrong opcodeSeed at emit (trap/garbage), truncated container — none ever produce the oracle output; truncated ⇒ generic `load failed`; CRC trailer flip is inert by design (D-M6-7, asserted). |
| tests/api.test.ts | placeholder pre-pass ↔ real pass code-region stability (checksums equal — the two-pass pipeline property); deriveConstKey checksum sensitivity; syntax safety (no goto/`//`/compound-assign/continue/comments); luac5.4 -p parses every strategy × both embed variants × 2 seeds; size sanity; entry contract (env passthrough w/ wrapped string, args → vararg main, double entry call). |
| tests/vectors.test.ts | vendored Lua crypto on real lua5.4 vs contracts/test_vectors.json (sha256 FIPS 180-4 ×4, HKDF RFC 5869 TC1-3); const-key chain root+steps 1..3 byte-parity vs M5's TS constKeyChainRoot/Step; FNV-1a32/DJB2 draft-eastlake-fnv + Bernstein KATs; Lua pair == TS mirror on varied inputs. |
| tests/smoke.test.ts | fastest end-to-end canary (1 fixture, chain). |

External-derivation statement: the differential oracle (real Lua 5.4.7
executable) and the vectors JSON are OUTSIDE sources per §22.1; M5's
compiler/container/interpreter are the delivered, pinned inputs
(BYTECODE-M5.md). The vendored crypto files are byte-identical copies of
M3's `loader/crypto` (md5-verified at vendor time; re-verified in the
delivery commit).

## 2. Bugs found during development (found → fixed → regression-covered)

1. **MKFN returned RUN's pack table** instead of unpacking the values —
   host calls into guest closures (e.g. `__tostring`) received a table.
   Symptom: oop-metatables fixture `"'__tostring' must return a string"`.
2. **Closure dispatch off-by-one**: the loop indexed `HDIS[I[1]]`
   (0-based canonical id) while bindings are 1-based → every closure
   build dispatched the wrong handler (arith-on-boolean at the first
   register-typed op). Symptom: closure strategy 100% failing.
3. **Non-monotonic pool access miskeyed the chain**: the walk-forward-
   only chain head used K_j for pool i<j once a later pool had loaded
   first → AEAD open failure ("load failed"). Fixed with the memoized
   key cache (KS[i] = K_{i-1}, resume from highest contiguous index).
   Symptom: varargs/oop/interp/errors/metamethods fixtures failing
   under chain/tree.
4. **`%*` interp-string conformance gap**: M5 lowers Luau interp-strings
   to `string.format` with `%*`; real hosts reject it. Fixed with the
   %*-aware wrapped env (D-M6-9).
5. Test-harness bugs (double-escaped constKey literal; wrong djb2 KAT
   constant; float-formatted FNV output) — fixed in the tests.

All five are regression-covered by the suite above (1: differential
oop/metamethods + entry `__tostring` paths; 2: every closure test; 3:
differential varargs/oop/... + parity pool counts; 4: differential
interp-string; 5: vectors).

## 3. NOT-RUN (honest list)

- **Real-executor (Luau) runs** — D2-class follow-up (same as M3/M5/M13
  not-run entries); all measurements/differentials are PUC lua5.4.7.
- **Corpus end-to-end** — awaits glm3's token→AST parser (M4 session 3);
  identical dependency state as M5's VERIFICATION (17 hand-built-AST
  fixtures here).
- **Nested VM (§10.2 item 8)** — optional/advanced per doc; deferred
  (D-M6-10). The emitter architecture (handler bodies as data) is
  nested-VM-ready: a second emit pass over a function's proto subset
  with a different vmSeed composes without touching the outer runtime's
  contract.
- **Deeper control-flow flattening** — v1 ships junk locals, opaque
  predicates, name/literal/order/shape randomization (§10.2 item 7
  surface); full state-variable dispatcher flattening of the emitted
  loop is a follow-up (D-M6-10).
- **Runtime self-source checksumming** — a chunk cannot portably read
  its own source on executors (debug/io restricted); whole-file
  integrity is M13's `r` (delivered). See RUNTIME-M6 §7.
- **Per-fetch `s` mixing into the container key schedule** — the M5
  chain pin (K_0 = HKDF(constKey, ∅, "const-key")) plus per-build
  cached containers mathematically exclude per-fetch secrets from the
  pool AEAD schedule; `s` currently gates the decoy path (length/type
  validity). The coherent fix is the M1 payload-key salt extension —
  filed as CCP-M6 (Tier 2) with the exact formula.
- **String-packed guest fetch** (Luraph-style): measured +15-28 ns/instr
  in RESEARCH-M6 §4; array-fetch only in v1.
- **Fuzzing** (random program generator) — doc §10.3 lists it; not run
  (M5's not-run list carries the same entry).
- **math.tointeger-absent hosts** (5.1/LuaJIT): f64 consts stay floats
  there (prints %.14g → "3"); oracle-parity on such hosts follows the
  host's own semantics; not measured in this sandbox (no 5.1 runtime
  present).
- **Performance**: no slowdown-ratio benchmarks vs native execution in
  this session (§10.3 asks for them; dispatch-only costs were measured
  in RESEARCH-M6 §4; full-runtime ratios are D2-class on real
  executors).

## 4. Determinism / reproducibility

Same {vmSeed, opcodeSeed, container, options} ⇒ byte-identical output
(tested). The manifest fields the pipeline should store per build:
`vm_seed`, `opcode_seed` (already in M5's manifest), dispatch kind,
runtime_built flag, `code_checksums` (fnv/djb2), `vm_hash` (whole-file
SHA-256).

## 5. Fresh-clone re-run (delivered bytes)

Re-ran on the Public-delivered tree after commit (see TASKS.md M6 row
for the commit hash): `bun run typecheck` clean, `bun test` 63/63.

## 6. v1.1 addendum — containerless mode (session 21, 2026-10-11)

**What**: `container: null` emit mode + entry field `b` (RUNTIME-M6 §1/§2/§4)
— the CCP-M7 D-M5-20 co-sign correction. Self-consistency integrity leg:
SHA-256 over the delivered container's hashed region vs its own hash field.

**Commands + output** (fresh clone of the merged tree, lua5.4.7 on PATH):

```
cd obfuscator/vm
bun install          # 5 packages
bun run typecheck    # tsc --noEmit — clean
bun test             # 84 pass, 0 fail, 360 expect() calls (63 v1 + 21 v1.1)
```

**New coverage** (tests/differential.test.ts, tests/tamper.test.ts,
tests/api.test.ts):

- containerless differential: 10 fixtures × 4 strategies, b-entry runtime,
  byte-equal stdout vs the real-lua5.4 oracle; two-session double-entry
  call on one runtime file == oracle×2 (per-call state, the deployment
  cadence).
- self-consistency positive: valid container via `b` runs clean.
- hash-field bit flip (bytes 6..37) → decoy, never oracle.
- re-hash attack (pool byte flip + correctly rewritten hash field, i.e.
  the strongest constKey-less attacker mimicking packWatermarked's
  re-hash) → real-key path selected, AEAD garbage, never oracle.
- nil `b` / table `b` / 10-byte `b` / truncated `b` → generic
  "load failed", NO raw crash (regression: the first cut leaked
  "attempt to call a nil value (method 'byte')" — the decoy fallback
  mutated the `bh` nil-signal; fixed with a dedicated `bstr` flag).
- CRC flip inert in b-mode too (D-M6-7 holds on both legs).
- wrong constKey via b-mode → AEAD failure, never oracle.
- containerless determinism (same seeds → identical bytes), luac5.4 -p
  parse gate on all containerless strategy variants, size sanity.

**NOT-RUN (unchanged from v1)**: real executors (D2), corpus end-to-end
(now unblocked — M4 s6 + M5 landed; next-session lane), nested VM /
deep flattening (D-M6-10). packWatermarked does not exist yet — the
re-hash test simulates its hash-write behavior on tampered bytes; the
positive watermarked-container case is exactly "any self-consistent
container sealed under the delivered constKey runs", covered by the
b-mode differential.

## 7. Corpus end-to-end addendum (session 21, 2026-10-11)

Runner: `tests/corpus-e2e.ts` (arg-driven, like M4's corpus.ts — the
corpus is project-captured material and is NOT committed):

```
bun run tests/corpus-e2e.ts <corpus-root>
```

Full pipeline per file: M4 parse → M5 compile+pack → M6 emit
(containerless) → real lua5.4 run of the {b,c,s} entry → compare
against the original source run directly. Honest oracle model: the
corpus is game-script material — a file participates in the EXECUTION
differential only when its oracle exits 0 with deterministic output;
otherwise the check is ERROR PARITY (the protected form must reach the
guest's own failure boundary — a guest-level error — never an M6-level
"load failed").

**Result on the 131-file corpus (130 .lua files): 0 MISMATCHES.**

- match (execution differential): 0 — no corpus file is oracle-runnable
  with output (all game scripts: executor globals at line 1, game API
  deps, infinite service loops — the oracle itself fails/times out).
- error-parity: 2 — `aac(v1).lua`, `aac(v2).lua` (the only files
  through the FULL pipeline): protected runs reach the guest's own
  "attempt to call" boundary through decode/dispatch/pool-decrypt —
  no M6-level failures.
- parse-reject: 3 (the known-broken files, M4's numbers unchanged).
- compile-reject: **125 — one single cause** (see the finding below).
- emit-reject: 0.

**Finding for M5 (glm6's lane), minimal repro:**

```
parse('function foo() end')  → FunctionStat.name.kind === 'Global'
compileProgram(that)         → CompileError: function statement target
                               must be a name index (compile.ts:858)
```

Plain global function statements — the most common statement in the
corpus's game scripts — never compile: compileFunctionStat only
handles `IndexName` chains (`function a.b.c()`). Local functions and
`foo = function() end` assignments are unaffected (fixture suites
never exercise the plain form, which is why 45/45 + 84/84 stayed
green). Once fixed, the same runner re-runs the corpus end-to-end —
the M4/M6 sides held everywhere they were reachable (0 mismatches).

## 8. Session 22 addendum — corpus re-run + watermarked E2E (2026-10-11)

### 8.1 glm6's D-M5-26 AAD sync to `src/emit.ts` — owner review: ACCEPTED

glm6 applied a 2-line sync in their M5 s5 (Public e87c3b2) after changing
the pool-blob AAD to `head || SHA-256(functions)` (quadratic sealing fix);
my generated runtimes compute AAD in the DECODE template. Reviewed as M6
owner: the sync (capture `i0` post-fcount-varint; `aadh` = head‖header;
`aads = aadh .. sha256(functions region)`) is semantically correct —
byte-identical to compiler/src/container.ts, marked glm6-sync at the
site. Adopted into the canonical M6 tree; ownership resumed. Evidence:
vm suite 84/84 on the synced tree (pre-session), 112/112 after this
session's additions.

### 8.2 Corpus re-run after glm6's function-stat fix — compile-reject 125 → 0

glm6 fixed the 125-file plain-`function-foo()` class (plus 3 more
corpus-exposed compiler bugs) in Public e87c3b2. Re-ran the identical
runner (tests/corpus-e2e.ts, now with the CLASS gate below):

```
$ LUA54=~/.lua54/bin/lua5.4 bun run tests/corpus-e2e.ts <131-corpus>
total files: 130
match: 0                (no corpus file is oracle-runnable — unchanged)
error-parity: 127       (was 2; all 125 former compile-rejects now run)
MISMATCH: 0
parse-reject: 3 (known, M4's numbers) / compile-reject: 0 (was 125)
oracle-fail: 0 / no-output: 0 / nondeterministic: 0 / emit-reject: 0
exit 0
```

**NEW: error-parity CLASS gate** (baked into the runner this session).
One-off full scan first (`class-parity-scan`, not shipped): for every
file whose oracle failure is an EXECUTION error, the protected run's
first error carries the SAME class — 71/71 (70 call-nil + 1 index-nil),
zero divergences; 56 files fail the ORACLE at parse (Luau-only syntax
under PUC 5.4) and their protected runs reach guest-level call-nil
(51) / index-nil (5) boundaries. The runner now enforces this: oracle
execution-error class ≠ protected class → MISMATCH. Re-run: 127
error-parity, 0 MISMATCH, exit 0.

### 8.3 Watermarked containers through the M6 LUA runtime (CCP-M7 v1)

glm6's suite proves packWatermarked against the M5 TS reference
interpreter; the runtime side was unproven until now.
`tests/watermark-e2e.test.ts` (28 tests, all green):

- **Embedded mode, per-version watermark**: 10 fixtures × 4 dispatch
  strategies — watermarked container, per-version constKey → oracle
  byte-for-byte.
- **Containerless mode, sessionConstKey (D-M5-27)**: 10 fixtures × 4
  strategies — per-session re-sealed watermarked container via entry
  `{b,c}` with the FRESH session key → oracle byte-for-byte. The v1.1
  self-consistency integrity leg accepts the session-hashed container
  (no decoy).
- **Per-session rotation on ONE fixed runtime**: two sessions (distinct
  watermarks, distinct session keys, distinct container bytes) through
  the same runtime file → both == oracle.
- **Cross-key denial**: session-2 container under session-1's key →
  decoy/generic failure, never oracle (the anti-dump posture holds at
  the runtime boundary).
- **Extractor lockstep**: per-version container → watermark recovered
  (carrier1Ok); session-keyed container → version key throws, session
  key recovers; canonical container → null.
- **Tamper posture on watermarked containers**: pool-blob bit flip,
  hash-field flip (re-hash attack class), carrier-region tamper →
  never oracle, no raw crash.

### 8.4 Corpus WATERMARKED end-to-end (--wm mode) — SECOND M5 FINDING

The runner grew `--wm`: pack WATERMARKED containers per file (CCP-M7 v1,
per-version key) + verify extractWatermark recovers the watermark from
the exact bytes the runtime consumed. Result on the 131-corpus:

```
$ LUA54=... bun run tests/corpus-e2e.ts <131-corpus> --wm
total files: 130   (watermark mode: ON)
match: 0 / error-parity: 101 / MISMATCH: 26 / parse-reject: 3
real exit code: 1 (26 MISMATCH)
```

**All 26 MISMATCHes are one cause — M5 container string encoding is
LOSSY for code units > 0xFF (finding #2 for glm6):**

- Minimal repro: `print("em-dash:\u2014end")` — oracle prints the em-dash,
  the protected run prints `\u0014` (0x2014 & 0xff). MATCH: false.
- Root cause: pack writes str consts one byte per code unit
  (`charCodeAt(i) & 0xff` — container.ts pool encode), unpack reads
  bytes back via `fromCharCode` — Latin-1 byte-strings end to end. Any
  source string with a code unit above 0xFF (em-dash U+2014, bullet
  U+2022, emoji — ubiquitous in game-script UI text) is truncated.
- Scope census: **26/130 corpus files, 234 string consts affected**
  (worst: CoS.lua 119, script.lua 18, sp.lua 15, GAG.lua 15).
- Why nothing caught it before: the differential fixtures are ASCII;
  the corpus has no oracle-runnable file (no stdout comparison); the
  watermark suite fixtures are ASCII. The 26 failures surfaced as
  extractWatermark carrier1Ok=false — the carrier-1 cross-check
  compares in-memory expected pools (original strings) against
  round-tripped actual pools (truncated strings): an accidental but
  effective canary. The other 104 files: extraction ok, watermark
  bytes match, runtime runs == error-parity as in 8.2.
- Fix is glm6's lane (BYTECODE-M5 normative change): pool str payloads
  need a Unicode-safe encoding; NOTE the junk carrier (carrier 2)
  injects raw 8-byte XOR values as "strings" and the extractor reads
  them back at the byte level — the encoding change must keep the junk
  path byte-exact (e.g. length-prefixed UTF-8 for live strs, raw bytes
  injected at the pool level, extractor reads junk pre-decode).
  The runner's --wm mode stays red until the fix lands (fail-loud
  follow-up, same as the function-stat class last session).
- The NON-watermarked run (8.2: 127 error-parity, 0 MISMATCH) remains
  honest — truncation does not change first-error classes (guests die
  at getgenv/game before any UI string is printed).

### 8.5 Suite state after this session

```
vm:      bun test            → 112 pass / 0 fail (496 expects, 8 files)
vm:      bun run typecheck   → clean
vm:      corpus-e2e (plain)  → 127 error-parity / 0 MISMATCH / exit 0
vm:      corpus-e2e --wm     → 101 error-parity / 26 MISMATCH (all the
                              M5 Latin-1 finding, §8.4) / exit 1 —
                              EXPECTED-RED until glm6's fix lands
root:    bun test            → 446 pass / 0 fail (12946 expects, 17 files)
root:    bun run typecheck   → clean
compiler: bun test           → 78 pass / 0 fail (450 expects, 3 files)
compiler: bun run typecheck  → clean (3 pre-existing errors in glm6's
                              test files fixed here: unused `pack` import
                              in corpus_compile.ts, unused `x` in
                              watermark.test.ts, missing `kind` in the
                              JSON.parse annotation — glm6's "tsc ×2" had
                              covered root+vm only; notified)
```

### 8.6 NOT-RUN (honest list, additions)

- Embedded-mode × sessionConstKey combination (not a deployment shape:
  embedding is per-version, session keys are per-session/b-mode; the
  mechanically-relevant combinations are covered).
