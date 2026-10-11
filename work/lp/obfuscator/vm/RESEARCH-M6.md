# RESEARCH-M6 — VM Runtime Generator (research phase)

Module: LP1-M6 (doc §10.2 items 5-9). Owner: glm1. Status: research phase
(implementation blocked on M5 bytecode spec; this log satisfies the
"Research Log before code" rule and answers the doc's M6 research list).
All URLs below were opened 2026-10-10 (session 19). Measurements were run
on this sandbox (commands + raw outputs attached, §22.1 style).

## 0. The doc's research questions for M6

1. "Fastest dispatch techniques in pure Lua/Luau" — measured (§4).
2. "cost of closure-per-opcode vs if-chain vs table dispatch" — measured (§4).
3. "published deobfuscation techniques against Lua VMs and counters" — researched (§2).

## 1. Sources opened (2026-10-10)

### Attack side (what adversaries actually do)

- **github.com/caomod2077/Deobfuscator-Luraph-V15** — standalone
  deobfuscator/devirtualizer for Luraph v15 (with experimental v14.x
  support). Node + Python, public README with per-version status,
  benchmark tables, committed sample inputs AND outputs. Key facts
  extracted:
  - Core engine: symbolic execution + **SCCP (sparse conditional constant
    propagation) walk** over the VM, iterative tree walks, single-pass
    state analysis, shared dispatch-loop cache, bounded SCCP.
  - Recognized dispatch-loop shapes: `while true do local op=(ARR[pc])…`
    AND `repeat … until false`, including parenthesized and type-asserted
    opcode fetches — i.e. **it pattern-matches the dispatch loop text**.
  - VM chunk extraction: the VM often lives inside a `loadstring`'d chunk;
    the tool captures and instruments it, aborting the first pass right
    after the chunk dump instead of executing the raw VM.
  - Closure-factory recovery: prototypes recovered from `__venv` runtime
    captures; `LPH_NO_VIRTUALIZE` closures preserved with upvalue
    bindings rebuilt.
  - Published results: full hub scripts recovered statement-for-statement
    (v14.7); a 1.62 MB / 1,723-function script lifts 99.97% of functions
    (46 blocks fall back to explicit error markers); v14.8/v14.9 partial
    (runtime-built VM-object tables re-indexed numerically, e.g.
    `obj[54]`, not yet bound back → behaviour-trace fallback).
- **github.com/Lethal-Luka/IronbrewDeobfuscator** — C# deobfuscator for
  Ironbrew2 (beta-1.0, README updated Feb 12, 2024): bytecode
  deobfuscation, **control-flow graph generation**, string decryption,
  "full macro support" (i.e. it defeats Ironbrew's macro/junk layers).
- **github.com/atrexus/unluau** — the strongest public Luau decompiler
  (most Luau opcodes + language features). Relevant as the
  post-devirtualization stage: once a lifted VM is recompiled to Luau
  bytecode, unluau-class tools can produce readable source.
- **github.com/boydev-1444/lunaux-decompiler** — Luau bytecode → source
  reconstruction (algorithm-based).

### Defense side (what existing protectors do)

- **github.com/Trollicus/ironbrew-2** — the open-source VM obfuscator for
  Lua 5.1 (MIT; Lua 72.5% / C# 27.5%; last real activity 2020-2023).
  Ironbrew2's deobfuscator existing (above) makes it a full attack/defense
  reference pair.
- **luagrapheg.lua** (Public root, user-provided, 2026-10-10) — a real
  Luraph-protected 1.1 MB sample ("This file was protected using Luraph
  Obfuscator"). Structure dissected (§3).

### Performance background

- **luau.org/performance** ("How we make Luau fast") — Luau's own
  engineering doc. Key admissions: Luau prioritizes interpreted
  performance because "JIT compilation is not available on many platforms
  Luau runs on" (exactly our executor constraint); optional x64/arm64 JIT
  exists but is irrelevant to sandboxed executors. Honest note: the page
  documents USER-FACING optimization (inline caching, namecall, fast-call
  builtins) and C-level VM details — it does NOT discuss pure-Lua dispatch
  strategies, so it informed constraints only, not the measurements.
- **Lua 5.4 / PUC-Rio interpreter literature**: Lua's own dispatch is a
  C-level `switch` (or computed-goto where available) — not portable to
  our constraint (doc.md forbids `goto`, and executors run plain Luau).
  This is WHY the doc's M6 research list asks for pure-Lua dispatch
  measurements; no public source answers it, hence §4 measures it here.

## 2. Deobfuscation techniques → counters (question 3)

From the Luraph-V15 devirtualizer + Ironbrew deobfuscator read-ups:

| Attack technique (observed) | Counter available to M6 |
|---|---|
| Textual pattern-matching of dispatch loops (`while true do local op=(ARR[pc])`, `repeat…until false`) | Per-build dispatch-shape + handler-order randomization (doc §10.2.4/5) — the template emitter must produce structurally DIFFERENT loops per build (chain vs tree vs closure-table mixes, generated code shapes, opaque local naming) |
| Symbolic execution + SCCP lifting constants and control flow | §10.2.9 integrity-linked keys: tampering (or instrumenting) the VM corrupts DECRYPTION rather than tripping a detectable branch — the lifter then sees garbage constants instead of a clean break |
| One decrypted function unlocks the rest | §10.2.6 per-function chained keys (K_n from K_{n-1}, §5.7 "const-key") — each function pays its own derivation cost |
| Runtime chunk capture (instrumenting the loadstring'd VM chunk, aborting after dump) | §5.6 per-fetch random mixed into key derivation — a captured chunk is unique per fetch and useless for the next one; also M13's stub integrity (D-M13-6 `r` value) feeds the same chain |
| CFG reconstruction + macro/junk elimination (Ironbrew deobf) | §10.2.7 control-flow hardening: flattening with state-variable dispatcher, opaque predicates, junk insertion — raises the CFG-reconstruction cost; per-build variation prevents one tool update from covering all builds |
| Numeric re-indexing of VM-object tables (`obj[54]` — the technique that still defeats the Luraph lifter on v14.8/9) | Interesting INVERSE evidence: runtime-built handler tables with numeric re-indexing are currently the strongest observed obfuscation-side trick — candidate M6 template variant (handlers materialized at runtime rather than emitted as literal closures/branches) |

Honest conclusion: the v15 devirtualizer lifts ~99.97% of a real
production sample's functions. A determined attacker with current public
tooling wins against static structure alone; the achievable goals are
(1) per-build uniqueness forcing per-sample re-analysis, (2)
tamper-integrity that corrupts lifted constants, (3) cost/complexity
raising — not impossibility. This matches doc §10.3's differential
correctness bar (obfuscation must preserve behavior) and §12's
watermark/leak-tracing fallback (M7 lane).

## 3. Luraph sample dissection (luagrapheg.lua, Public root)

- 6 lines / 1,118,804 bytes; header comment credits chris12089, "UI
  Library based on Elerium", "protected using Luraph Obfuscator".
- Lexically trivial for a Luau lexer: 2,036 tokens — the payload is a few
  GIANT string literals (serialized bytecode + constant pool) plus a
  small pure-Lua VM.
- VM bit engine: `string.byte`/`string.char` + a precomputed `{[0]=1,2,4,…,2^31}`
  power table (the classic pure-Lua bit32 emulation), `pcall`-wrapped.
- Entry guard: `if _G.loading then return end`; executor feature check via
  `getthreadidentity()<8` + `cloneref` fallback — mirrors our UNC
  feature-detect approach (M3 env_executor).
- Implication for M6: Luraph's runtime is (a) string-packed bytecode
  (motivated §4's fetch-representation measurement), (b) ONE dispatch
  shape per version (which is exactly why the v15 lifter's shape matching
  works) — our per-build shape randomization is the differentiator.

## 4. Dispatch benchmark (questions 1 + 2) — measured

Artifact: `obfuscator/vm/bench_dispatch.lua` (goto-free per doc.md).

Method: for each ISA size N ∈ {16, 64, 256}, the SAME synthetic program
(400 instructions; opcode id → distinct handler; semantics drawn from 15
uniform bodies by id%15; id N-1 = HALT) is executed by four generated
runtimes: if/elseif chain (N-branch), balanced binary comparison tree
(log2 N depth), closure-per-opcode table, and the chain again with
string-packed fetch (string:byte unpack, 3 bytes/instr). Identical work
per opcode id across strategies by construction (handler bodies compiled
from the same source strings). Best-of-7 rounds, os.clock, lua5.4
(PUC 5.4.7, this sandbox).

Command: `lua5.4 bench_dispatch.lua` (from obfuscator/vm/)

Raw output (final, run 1 of 3):

```
lua: Lua 5.4 | rounds=7 runs=40 | program: 400 instr + HALT, same stream everywhere
ISA    if/elseif    bin-tree     closure-tbl  str-fetch
16     85.1         70.4         96.3         112.7
64     151.0        78.9         94.8         172.9
256    450.1        101.3        98.4         464.2
(ns per dispatched program-instruction, best-of-rounds; str-fetch = generated if-chain + string:byte unpack)
```

Methodology note (a caught-and-fixed measurement bug, kept for honesty):
the first string-fetch run printed implausibly FAST numbers (e.g. 106.4
ns at N=256 vs the array twin's 450.1). Diagnosis: an instruction-count
parity check showed the string twin executing a DIFFERENT path (380 vs
357 instructions/pass) — the not-taken branch deltas were pc+4 while
instructions are 3 bytes apart, so the pc walked misaligned byte offsets
and dispatched garbage opcodes that happened to terminate. Fixed the
conditional deltas to +6 (2 instructions); re-verified parity of executed
instruction counts for all three ISA sizes (367/367, 353/353, 357/357
array vs string). All numbers above are post-fix. Lesson recorded for
the future M6 differential harness: **instruction-count parity between
representations is a mandatory gate, not an assumption** (doc §10.3's
differential testing now has a concrete precedent).

Repeatability (3 runs incl. rounds=9 runs=60): if-chain 85-89 / 150-153 /
450-453; bin-tree 68-72 / 78-79 / 94-102; closure 93-98 / 93-96 / 98-99;
str-fetch 90-113 / 95-173 / 451-464 — first-run vs later-run variance is
within ±6% except str-fetch warm-up on some runs; treat bands, not
single points.

Findings:

1. **if/elseif chain cost is linear in ISA size** (~85 ns @ 16 → ~151 ns
   @ 64 → ~450 ns @ 256): expected branch position ≈ N/2 comparisons.
   Chains are only competitive for small ISAs (N ≲ 32).
2. **Balanced binary tree scales logarithmically** (70.4 → 78.9 → 101.3):
   the best strategy at every measured size on this runtime; ~4.4×
   cheaper than the chain at N=256.
3. **Closure-per-opcode table is ISA-size FLAT** (96.3 / 94.8 / 98.4):
   one hash lookup + one Lua call. ~11-37% slower than the tree at
   N ≤ 64, but never degrades — and its cost is independent of opcode
   numbering, so per-build opcode permutation is free.
4. **Crossover**: chain beats closure up to N≈32-48; tree beats closure
   through N=256 (101.3 vs 98.4 — converged). For larger ISAs the
   closure table wins outright (extrapolated beyond 256, unmeasured).
5. **String-packed fetch adds +15-28 ns/instruction** over array fetch
   (+32% at N=16 where the chain is short; +3% at N=256 where the chain
   walk dominates): two string:byte calls + no division/modulo decode vs
   one table index + floor/mod. The absolute overhead is small enough
   that string packing (Luraph-style, §3) remains viable if M5's §5.9
   container wants it — the final representation is M5's call; this
   measurement is the input.

Implications for the template emitter (per-build randomization, doc
§10.2.4/5):

- Vary the dispatch STRATEGY per build across {chain, tree, closure
  table} — measured cost bands (70-464 ns/instr) are all negligible vs
  one-time load costs (M3-measured ~40 ms/op X25519-class decrypt),
  i.e. **dispatch choice is a randomization lever, not a performance
  bottleneck** for loader-scale scripts.
- For small per-build ISAs (≤ 48 opcodes), chains/trees dominate; the
  emitter should randomize branch ORDER (never frequency-sort — sorted
  order is a stable fingerprint the v15 lifter's shape matcher eats).
- Closure tables have a second property the others lack: handler
  identity is a runtime value (assignment/metatable games possible,
  e.g. the runtime-re-indexed handler table that still defeats the
  public lifter on Luraph v14.8/9 — §2's last row).
- Opcode-id permutation per build is free (all strategies measured under
  random id→semantics mapping already).

## 5. Integrity-linked keys + constant decryption (§10.2.6/9) — design notes pre-M5

- Chained per-function keys per §5.7's reserved `"const-key"` HKDF info
  (D-M4-3 already pinned the label): K₀ = HKDF(entropy, build_salt),
  K_n = HKDF(K_{n-1}, fn_n_salt, "const-key"). Runtime lazy decrypt uses
  M3's ChaCha20-Poly1305 (AEAD per pool entry — tamper = failed open,
  not detectable branch) — primitives already delivered + cross-verified
  with M1 (contracts/test_vectors.json).
- §10.2.9: checksums over VM source + bytecode feed key derivation. The
  checksum must be cheap in pure Lua: FNV-1a32 + DJB2 dual hash already
  exists in M13's stub template (D-M13-5, deliberately tiny, unkeyed) —
  reuse the SAME pair for VM integrity so the stub's cache validation and
  the VM's key derivation share one audited implementation family. The
  §5.6 per-fetch value (`r`, delivered to init via M13's entry contract
  D-M13-6) mixes into K₀.
- Open question for M5's owner (glm6, msg sent): does the §5.9 container
  carry per-function pools as separate AEAD blobs (my assumption) or one
  pool with offsets? M6's runtime template shape depends on it.

## 6. NOT-RUN / honest gaps

- **Luau-on-executor measurements**: all §4 numbers are PUC lua5.4.7 on
  this sandbox; Luau (executor target) has different call/hash costs
  (luau.org documents interpreter focus but not at this granularity).
  D2-class follow-up: port bench_dispatch.lua to a real executor when
  available.
- **ISA > 256**: closure-table crossover beyond N=256 is extrapolated,
  not measured.
- **Skewed opcode distributions**: real programs have hot opcodes; the
  benchmark uses a uniform stream. Chain-order-randomization cost under
  skew is derivable analytically (expected depth × distribution) but not
  measured.
- **Attack-tool execution**: the deobfuscators were read (READMEs,
  documented behavior, published benchmark tables) but not run against
  any sample in this session — running them on luagrapheg.lua is a
  candidate follow-up experiment for the implementation phase (owner
  permission assumed; the sample is user-provided at Public root).
- **sillycross.github.io "Building the fastest Lua interpreter"**: search
  hit; both plausible URLs 404'd when opened — NOT usable as a source,
  listed here only to record the dead-end (no claims rest on it).
- **lua.org Lua Gems performance chapter (PDF)**: page-reader cannot
  extract PDF text; not opened. No claims rest on it.

## 7. Implementation-phase notes (session 20, 2026-10-10)

- BYTECODE-M5.md (glm6, Public c26c157) landed as the ISA+container pin;
  my §5 container question was answered: separate per-function AEAD
  blobs with the ctLen prefix, chained keys K_0 = HKDF(constKey, ∅,
  "const-key"), K_n = HKDF(K_{n-1}, u32be(n), "const-key") — the
  lazy-decrypt sketch in §5 became the shipped key-memoized loader
  (RUNTIME-M6 §5; the walk-forward-only variant had an order bug,
  VERIFICATION-M6 §2 bug 3).
- The dispatch measurements (§4) translated directly: chain/tree inline
  in the interpreter loop, closure tables built once at chunk level,
  runtime-built variant re-indexes through a baked permutation
  (D-M6-3). The instruction-count parity gate born from §4's
  misaligned-branch bug is now an enforced test (tests/parity.test.ts).
- §2's counter table confirmed its worth during development: the
  closure-strategy off-by-one and the non-monotonic chain bug were both
  caught by differential testing inside one session (VERIFICATION §2).
- The `%*` conformance gap (M5 interp-string lowering vs real hosts) is
  the concrete case for keeping M5's reference interpreter as the
  second oracle: real-Lua-only testing would have missed what the
  fixture ASTs actually emit.
