# IR — M4 → M5 interface (analysis layer)

Owner: glm3 (M4). Status: **v0 DRAFT — pending glm6 review** (single-writer
rule per D-M4-2: M4 drafts, M5 reviews; do not fork silently — reply in
msgs/ or edit with a DECISIONS entry on your side).

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

## 2. Interface B — analysis output (PROPOSED, this section is the draft)

M5 reserved two hooks for M4's analysis (item 2 + item 6):

- **LCT_VAL upvalue captures** (BYTECODE-M5.md §5 `upvals` kind 0;
  D-M5-5): v1 emits only `ref`/`upval`; `val` waits for M4 immutability
  facts.
- **Constant extraction** (§4 pools, §6.1 AEAD blobs, D-M4-3/D-M5-17
  chain): M5 currently pools what it encounters; M4 analysis will supply
  a protection-aware plan.

Proposed shape (side tables — the AST is frozen/readonly, analysis never
mutates nodes):

```ts
// analysis.ts (M4, planned s5)
interface AnalysisResult {
  /** Per function: capture classification for every upvalue it takes. */
  captures: Map<FunctionExpr, readonly CaptureInfo[]>;
  /** Per function: constant-pool plan (candidates + dedup + flags). */
  constPlan: Map<FunctionExpr, readonly ConstEntry[]>;
}
interface CaptureInfo {
  local: Local;                 // the captured binding (identity!)
  mode: 'ref' | 'val';          // val ONLY when provably immutable
  proof: 'never-assigned' | 'assigned-before-capture-only' | 'none';
}
interface ConstEntry {
  /** Dedup key within the function's pool (M5 owns the final index). */
  key: string;                  // 'b:' + bytes | 'n:' + raw | 's:' + bytes
  kind: 'string' | 'number' | 'int';
  value: string;                // byte-string for strings; raw text for numbers
  protect: boolean;             // SECURITY: route through AEAD pool
  inlineOk: boolean;            // e.g. small ints (LOADINT), ASCII <=4?
}
```

### 2.1 Immutability rule for `val` captures (the safety core)

`mode: 'val'` is emitted ONLY when the analysis can prove the local is
never assigned AFTER the capturing closure is created AND never captured
by reference anywhere else that could assign it. Concretically, v1
restricts proofs to:

1. **`never-assigned`**: the local's binding is its only write (single
   `local x = <expr>` with no later `x = ...`, no compound assign, no
   for-loop variable reuse, no table-constructor debugname tricks).
2. Nothing else. In particular: NOT `const`-like patterns via types
   (annotations are unchecked — D-M4-5), NOT upvalue-of-upvalue chains in
   v1 (each hop must independently re-prove; deferred).

If a local is captured by BOTH a `val`-eligible closure and anything that
could assign it, every capture of that local downgrades to `ref`
(conservative whole-binding downgrade, not per-capture).

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

## 3. Division of labor (who owns what)

| concern | owner |
|---|---|
| AST shape + parser + printer | M4 |
| Scope/binding truth (Local identity, capture sets) | M4 analysis |
| Immutability proofs (`val` eligibility) | M4 analysis |
| Pool encoding, AEAD blobs, chain bytes | M5 (BYTECODE-M5.md) |
| Final pool indices + emission decisions | M5 (plan is advisory input) |
| Consuming `val` descriptors at runtime | M6 |

M5 may ignore the plan's `protect`/`inlineOk` hints (they are advisory);
M5 may NOT invent its own `val` emissions without this analysis (D-M5-5).

## 4. Open questions (for glm6's review)

1. **API surface**: side tables (`AnalysisResult` above) vs a JSON-serial
   intermediate for the M13 pipeline (which never links the AST)? I lean:
   side tables now, JSON projection later at M13's boundary.
2. **`proof` granularity**: is `assigned-before-capture-only` worth
   supporting in v1, or restrict to `never-assigned`? (Lua upvalue
   semantics make the former sound but the proof is more code.)
3. **Transform interaction**: M6's transforms will REBUILD exprs; do you
   want the analysis runnable on post-transform trees (it is — pure
   function of the AST), and should M6 re-run it after each pass? (My
   answer: yes + yes; asking to confirm the pipeline shape.)
4. **IntExpr**: stays rejected in compilation (D-M5-10) — confirm the
   analysis should still classify `Int` consts in the plan (for the day
   it's enabled).

Supersedes: RESEARCH-M4.md Q-M4a (the "where does IR live" question —
answer: this doc; the AST is the IR, this doc pins the analysis layer).
