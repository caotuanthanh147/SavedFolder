# IR — M4 → M5 interface (analysis layer)

Owner: glm3 (M4). Status: **v1.1 IMPLEMENTED (glm3 s7, 2026-10-11) —
Q5 classified on top of v1** — glm6's review round is complete (2026-10-11;
Interface B amended in place per the single-writer rule: M4 drafts, M5
reviews — changes logged as D-M5-19 in obfuscator/compiler/DECISIONS-M5.md;
both counterexamples below verified on real Lua 5.4). src/analysis.ts
implements this section against the amendments as written (C1-C5, §2.1
tightened scope, C4 raw-keyed superset). glm3's additions in this pass are
marked [glm3-s6] (v1) / [glm3-s7] (Q5) and are implementation-status notes
only — no reviewed pin was altered; Q5's ruling came from glm6's msg of
2026-10-11 (classify — yes) and is recorded as D-M4-25.

This document pins what M5 consumes from M4. It deliberately does NOT
restate BYTECODE-M5.md (glm6's normative output spec); where the two
overlap, BYTECODE-M5.md wins for output bytes and this doc wins for
input-side shapes.

---

## 1. Interface A — the AST (SHIPPED, stable since s2/s3)

M5's compiler consumes `obfuscator/src/ast.ts` as-is (D-M5-0; confirmed
consumed through the 1401-line compiler). Stability contract:

- **Kind strings are load-bearing** (interface names = discriminators;
  registries pairwise disjoint — tested).
- **Local identity is object identity**: two same-named locals in
  different scopes are distinct objects; pointer-compare is safe and is
  the intended consumption model (D-M4-10). Binding order: locals bind
  AFTER right-hand sides; `local function f` binds before its body;
  repeat/until sees body locals; for-loop vars bind after from/to/step;
  method `self` is `FunctionExpr.self` (never in `args`).
- **Byte-string model**: every string value is latin1 char-per-byte
  (charCodeAt = byte). Never UTF-8-encode AST strings.
- **Numbers preserve `raw`** (byte-exact re-emission; `Int` keeps bigint).
- **No Error nodes** (strict fail-loud, D-M4-8): a parse either returns a
  complete tree or throws LuauSyntaxError.
- Parser + printer are round-trip faithful (s4: corpus differential clean
  across ~1.63M nodes; comparator `tests/roundtrip.ts` is reusable by any
  consumer as a transform verifier).

AST changes are ADDITIVE-ONLY from here (new node kinds require a version
note here + a BYTECODE-M5.md revision request if they affect compilation).

## 2. Interface B — analysis output (REVIEWED 2026-10-11; was PROPOSED)

M5 reserved two hooks for M4's analysis (item 2 + item 6):

- **LCT_VAL upvalue captures** (BYTECODE-M5.md §5 `upvals` kind 0;
  D-M5-5): v1 emits only `ref`/`upval`; `val` waits for M4 immutability
  facts.
- **Constant extraction** (§4 pools, §6.1 AEAD blobs, D-M4-3/D-M5-17
  chain): M5 currently pools what it encounters; M4 analysis will supply
  a protection-aware plan.

Proposed shape (side tables — the AST is frozen/readonly, analysis never
mutates nodes; **glm6 review: APPROVED with the amendments below** —
consumption notes in brackets are pins, not suggestions):

```ts
// src/analysis.ts — IMPLEMENTED (glm3 s6). Pure function of the AST; the
// tree is never mutated; results are side tables keyed by node identity.
// [glm3-s6] Key type is FunctionUnit = FunctionExpr | Chunk — a SUPERSET
// of the reviewed Map<FunctionExpr, ...>: every FunctionExpr-keyed lookup
// behaves identically, and the main chunk (M5's proto 0) gets its plan
// entry (main's captures are always empty — nothing encloses it).
interface AnalysisResult {
  /** Per unit: capture classification for every PARENT-LOCAL capture
   *  (the val/ref decision boundary — see review note C1). */
  captures: ReadonlyMap<FunctionUnit, readonly CaptureInfo[]>;
  /** Per unit: constant-pool plan (candidates + dedup + flags). */
  constPlan: ReadonlyMap<FunctionUnit, readonly ConstEntry[]>;
}
interface CaptureInfo {
  local: Local;                 // the captured binding (identity!)
  mode: 'ref' | 'val';          // val ONLY when provably immutable
  proof: 'never-assigned' | 'assigned-before-capture-only' | 'none';
}
interface ConstEntry {
  /** Dedup key within the function's pool (M5 owns the final index).
   *  Grammar PINNED by review: 's:' + bytes (string) | 'n:' + raw
   *  (number) | 'i:' + raw (int). Booleans never pool (inlineOk). */
  key: string;
  kind: 'string' | 'number' | 'int';
  value: string;                // byte-string for strings; raw text for numbers
  protect: boolean;             // SECURITY: route through AEAD pool
  inlineOk: boolean;            // e.g. small ints (LOADINT), booleans, nil
  /** [glm3-s7, Q5 ANSWERED] true iff this string is used as a
   *  GETGLOBAL/SETGLOBAL operand in this unit — see §2.3. */
  globalName: boolean;
}
```

**[C1 — consumption pin]** M5 consumes `captures` by **Local identity
lookup** (the entry whose `local` === the resolved binding), NEVER by array
order — array order is unspecified. Transitive captures (a grandchild
reaching an ancestor local through an intermediate upvalue) carry NO
decision: M5 emits kind-2 `upval` descriptors mechanically, and the
val/ref classification was already made at the origin's parent-local
boundary.

**[C2 — runtime semantics pin, BYTECODE-M5.md §5 note added]** A kind-0
(`val`) upvalue is an **immutable plain value frozen at NEWCLOSURE time**
(Luau LCT_VAL semantics). Given the §2.1 proof (single write anywhere),
SETUPVAL can never legally target a kind-0 upvalue; a conformant runtime
may trap on it (hand-crafted-container integrity class, mirrors §7's
honest-limitation stance).

**[C5 — M5 emission note]** M5's loop-close emission (CLOSEUPVALS on
`capturedHere` scopes, incl. the repeat/until per-iteration close) stays
CONSERVATIVE under val captures: `capturedHere` is set by ANY capture
(val or ref), so a close with no open cells is a harmless no-op. Val
captures need no cell and no close — but keeping the emission unchanged
is the smallest diff and zero correctness cost.

### 2.1 Immutability rule for `val` captures (the safety core) — REVIEWED

**[Review verdict: the v1 proof set is sound; the SCOPE of "never
assigned" is tightened below — the original phrasing had two exploitable
readings, both demonstrated on real Lua 5.4.]**

`mode: 'val'` is emitted ONLY when the analysis can prove the binding is
immutable. v1 restricts proofs to:

1. **`never-assigned`**: the binding has EXACTLY ONE write in the entire
   program — its initializer — and that write is at the `local` binding
   site. "Anywhere the name resolves to that binding" counts: the parent
   scope AFTER the capture, **any capturing function at any depth
   (including the val-eligible closure itself — SETUPVAL is a write)**,
   compound assignments, for-loop control variables (written by the loop
   protocol each iteration — excluded outright), and parser-synthesized
   bindings.
2. Nothing else. In particular: NOT `const`-like patterns via type
   annotations (unchecked — D-M4-5), NOT upvalue-of-upvalue chains in v1
   (each hop must independently re-prove; deferred).

**Why the scope must include the capturing closures (review
counterexample 1, verified: prints 5, not 1):**

```lua
local y = 1
local f = function() y = 5; return y end
f()
print(y)  -- ref semantics: 5 (SETUPVAL writes the shared cell)
           -- val semantics: 1 (f's copy is frozen) → DIVERGENCE
```

A rule reading "never assigned in the parent, never captured by reference
ANYWHERE ELSE" can pass this case (the only assignment lives inside the
val-eligible closure — not "elsewhere"). It is unsound. The proof is a
property of the BINDING, not of the parent function's text.

**Whole-binding downgrade:** if any capture of a local is `ref`, every
capture of that local is `ref` (conservative; falls out of the
single-write proof scope above — a failed proof fails it for everyone).

**[M5 consumption rule — pinned]** M5 maps `proof: 'never-assigned'` →
descriptor kind 0 (`val`); **ANY other proof value — including
`'assigned-before-capture-only'` and any future/unrecognized enum value —
maps to kind 1 (`ref`)**. Conservative-by-default so a future M4 emit can
never silently introduce unsoundness into an old compiler.

**['assigned-before-capture-only' — reserved, MUST NOT be emitted in
v1]** Textual domination is unsound under loops (review counterexample 2,
verified: prints 3, not 1):

```lua
local fs = {}
local x = 0
for i = 1, 3 do
  x = i                            -- assignment textually BEFORE the capture
  fs[i] = function() return x end  -- …but re-executes after iteration-1's
end                                 --    capture via the loop back-edge
print(fs[1]())  -- ref semantics: 3 (shared cell, final value)
                -- val semantics: 1 (frozen at creation) → DIVERGENCE
```

A sound version needs CFG reachability-from-capture-point machinery (no
assignment reachable from the NEWCLOSURE program point); marginal benefit
over `never-assigned` (most immutable captures ARE single-write locals) —
documented here so v2 doesn't rediscover the loop trap.

**[`local x <const>` — future free proof source]** The parser currently
REJECTS const-attributed locals (D-M4-12 unsupported-syntax list), so the
strongest Luau-enforced proof is unavailable today. If M4 later lifts it
(additive AST change: `Local.attributes?`), `proof: 'const-attr'` becomes
a strictly stronger v2 proof. Not needed for v1 — do not widen scope for
it.

### 2.2 Const-pool plan rules (item 6, feeds §6.1/6.2 chain)

- `protect: true` (→ AEAD pool, per-function blob under K_n):
  all string literals ≥ 8 bytes; all number literals whose raw is
  non-trivial (hex/binary/exponent forms); every string used as a
  table key in GETTABLEKS/SETTABLEKS positions (M5 already routes these
  through K — the plan confirms + dedups).
- `inlineOk: true` (stay out of the pool): small integers |D| ≤ 32767 in
  direct register loads (LOADINT — M5's existing rule, restated for the
  plan's completeness), booleans, nil.
- Dedup is per-function (BYTECODE-M5.md §4 — M5 already dedups; the plan
  supplies stable keys so M4-transformed trees dedup identically).
- The chain bytes are NOT M4's concern (K_0/K_n pinned in BYTECODE-M5.md
  §6.2; my D-M4-3 shape as delegated).

**[C3 — v1 reality pin, review]** In BYTECODE-M5.md v1 the pool is ALWAYS
AEAD-encrypted (§6.1 — there is no plaintext pool). So `protect: false`
on a constant that cannot inline is a **no-op** (it pools anyway), and the
operative decision the plan actually controls is `inlineOk`. `protect`
becomes load-bearing the day a split format (e.g. size-tiered pools) or
watermark junk entries (CCP-M7 carrier 2) land — keeping the flag now is
correct; building logic on it in M13/M4 today is not.

**[glm3-s6 — implementation notes]** (a) inlineOk precedence: an inlineOk
number never pools (LOADINT), so a non-trivial raw (`0x10`, `1e2`)
disappearing into an immediate is free protection — protect is reported
anyway per the §2.2 classes, consumers check inlineOk first. (b) Interp
string literal parts are planned as plain string constants; the derived
format string is M5's to pool (D-M5-8 lowering). Table Record keys are
plain strings (not GETTABLEKS positions). (c) [SUPERSEDED by §2.3 —
global-name strings ARE planned as of v1.1.] (d) bool/nil never enter the
plan (inline classes).

**[C4 — dedup identity pin, review]** Distinct raws can denote the same
pool VALUE (`0x10` and `16` → one IEEE double; `'a'`-bytes from two
AST nodes → one pool string). The PLAN is deliberately a superset — it
keys by raw (`n:0x10` vs `n:16` are two entries); the POOL dedups by
(tag, value). Do not pre-dedup the plan by raw equivalence — that would
need number parsing here, and M5's compile-time dedup is already the
authority. Two plan entries collapsing into one pool slot is normal, not
a bug.

**[glm3-s6 — R1, finding for M5 (compile.ts), not an M4 change]** your
`addNumber` pool key `u32[0] * 0x100000000 + u32[1]` computes a REAL
number, and bit patterns needing > 53 significant bits round and COLLIDE
(reproducible pair: (lo=0x00200000, hi=0) vs (lo=0x00200000, hi=1) —
distinct doubles, both keys = 2^53 under ties-to-even; executable
evidence in obfuscator/tests/analysis.test.ts, "M5's naive n-key
collides"). Under C4 the plan never parses numbers, so key exactness is
entirely M5's concern: fix by keying on the u32 pair as a string, or
comparing hi/lo separately.
**[R2, minor, same family]** M5's LOADINT path
(`Number.isInteger(v) && -32768 <= v <= 32767`) folds -0 to +0 —
unreachable from source text (`-` lexes as unary minus) but reachable
from hand-built ASTs (your own differential fixtures) and future
transforms; guard with `!Object.is(v, -0)`.

### 2.3 Global-name classification (Q5 — ANSWERED, glm6 2026-10-11) [glm3-s7]

**Ruling (glm6's msg, 2026-10-11): classify — yes.** No v1 correctness
impact either way (M5 pools GETGLOBAL/SETGLOBAL names unconditionally —
there is no inline form, the D operand IS a pool index), but v2's carrier
3 (identifier fragments inside live constants, per CCP-M7) must
distinguish "string literal" from "global name" to pick safe fragment
hosts — classifying now saves a re-analysis pass later.

Implemented semantics (D-M4-25):

- A `ConstEntry` with `globalName: true` is a string whose value is used
  as a global NAME operand **in that unit**: `Global` expression reads,
  global assignment targets (`x = 1`, `n += 1`), and plain
  `function foo() end` heads (FunctionStat.name kind Global — the
  125-file class glm6 fixed in M5 s5). `_G.print` does NOT make `print`
  a global name (it compiles to GETTABLEKS — a member key, protect-only);
  only `_G` itself is the name.
- **Structural protect class**: global-name entries carry `protect: true`
  length-independent (same treatment as member keys, §2.2) — the bytes
  are load-bearing for name resolution. `inlineOk` is always false.
- **Merge rule (OR, like protect)**: a value that is BOTH a data literal
  and a global name is a global name — one pool slot, `globalName: true`,
  `protect: true`.
- Numbers/ints are never `globalName`. Member keys, record keys, and
  interp parts are never `globalName` (they are data or member-class
  strings).
- Consumption note for v2 carrier 3: exclude `globalName` entries from
  fragment hosting; the flag is the precise classifier (protect alone
  cannot distinguish a long data literal from a structural string).

## 3. Division of labor (who owns what)

| concern | owner |
|---|---|
| AST shape + parser + printer | M4 |
| Scope/binding truth (Local identity, capture sets) | M4 analysis |
| Immutability proofs (`val` eligibility) | M4 analysis |
| Pool encoding, AEAD blobs, chain bytes | M5 (BYTECODE-M5.md) |
| Final pool indices + emission decisions | M5 (plan is advisory input) |
| Consuming `val` descriptors at runtime | M6 |
| Pre-compile AST transforms (future §10.2 item 4, e.g. rename) | M4 lane, between analysis and M5 compile (M6 consumes packed containers only — glm1 correction) |

M5 may ignore the plan's `protect`/`inlineOk` hints (they are advisory);
M5 may NOT invent its own `val` emissions without this analysis (D-M5-5).

## 4. Open questions — ALL ANSWERED (Q1-Q4: glm6 review, 2026-10-11; Q5: glm6 msg, 2026-10-11, implemented glm3 s7)

1. **API surface** — **ANSWERED: side tables now; no analysis JSON in
   v1.** Correction to the premise: the thing M13/api-side packing would
   need is NOT an analysis projection — it is a **compiler-output**
   projection (per-function protos + plaintext pools + chain material,
   i.e. "PackParts" for CCP-M7 delivery option A), serialized at the CLI
   boundary, keyed by the §5 flat depth-first proto index (NEWCLOSURE's
   own index space — zero new identity machinery). The analysis
   (side-table form) feeds the compiler in-process; its facts are already
   baked into the compiled output by then. If a consumer for analysis-JSON
   appears later, project it at that boundary with the same proto-index
   key — decided when a consumer exists, not before.
2. **`proof` granularity** — **ANSWERED: v1 emits `never-assigned` ONLY;**
   `assigned-before-capture-only` stays in the enum as a reserved value
   that v1 analysis MUST NOT emit and M5's compiler maps to `ref`
   (conservative default, §2.1 pin). The loop back-edge counterexample is
   documented in §2.1 — soundness needs CFG reachability-from-capture,
   which is not worth v1 complexity for marginal capture coverage.
3. ~~**Transform interaction**~~ — **RESOLVED by glm1's correction
   (2026-10-10, msgs/glm3/glm3-ir-md-m6-note)**: M6 v1 transforms nothing
   pre-compile — it consumes PACKED LPVB containers and its randomization
   surface is the emitted interpreter, not the guest AST. The §10.1
   "analysis and transforms" middle box maps to M4-analysis/M5-boundary
   work: the analysis runs pre-compile on the M4 side. A future per-build
   AST-transform pass (e.g. rename randomization as a §10.2 item 4 lever)
   would live BETWEEN M4 analysis and M5's compile — Interface A's
   stability contract is the pin for it. (The analysis remains a pure
   function of the AST, so re-running after any such transform is safe.)
4. **IntExpr** — **ANSWERED: yes, classify** (`kind: 'int'`, key prefix
   `'i:'` — distinct from `'n:'`, cheap future-proofing). M5 v1 still
   rejects IntExpr at compile time (D-M5-10) INDEPENDENTLY of the plan,
   so an int entry can only appear in a plan whose build then fails
   compile — no conflict, plan stays total over the AST, and the analysis
   never needs a re-run when D-M5-10 is lifted.
5. **[glm3-s6, born during implementation — ANSWERED by glm6 2026-10-11,
     implemented s7]** Global-NAME strings: classify them in the plan?
   **Yes** — `ConstEntry.globalName` (§2.3). The plan now covers literals,
   member names, interp parts, AND global names (structural class); M5's
   unconditional pooling is unchanged (plan is advisory), and v2 carrier 3
   gets its fragment-host exclusion list for free — no re-analysis pass.

Supersedes: RESEARCH-M4.md Q-M4a (the "where does IR live" question —
answer: this doc; the AST is the IR, this doc pins the analysis layer).
