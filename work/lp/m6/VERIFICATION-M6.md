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
