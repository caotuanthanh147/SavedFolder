# RESEARCH-M4 — Obfuscator front end (Luau parser, analysis, constant protection)

Research log, written BEFORE any code, per doc.md READ FIRST ("research log
before code"). Resolves open decision **D1 (Luau parser: existing vs custom)**
for module M4 (doc §10.2 items 1, 2, 6). All registry/API lookups performed
2026-10-10 from the build sandbox.

## 1. D1 survey — existing Luau-capable parsers usable from a Node/TypeScript CLI

(doc §4 Recommended stack: "Obfuscator | Node/TypeScript CLI | Shares types
with API" — this constrains candidates to JS/TS-consumable packages, or
bindings of foreign-language parsers.)

| Candidate | Facts (checked today) | Luau syntax? | License | Verdict |
|---|---|---|---|---|
| `luaparse` (npm) | v0.3.1, last publish **2021-06-03** (registry.npmjs.org/luaparse); 171,362 dl/month (api.npmjs.org, last month) | NO — Lua 5.1–5.3 only: no type annotations, no `continue`, no compound assignment, no string interpolation, no if-expressions | MIT | Rejected: no Luau support, dead upstream for 5 years |
| `luau-parser` (npm) | v1.0.3, published **2026-09-04**; repo github.com/Uav3537/luau-parser: **0 stars, 0 forks, NO LICENSE file**, created 2026-09-02, 4 releases in 2 days then quiet; 1,274 dl/month | claims yes | **none** | Rejected: 5-week-old single-author experiment, no license = legal blocker for a commercial protection product's core |
| `tree-sitter-luau` (npm) | v1.2.0, 2024-12-22; 479 dl/month | yes (grammar) | MIT | Rejected: tree-sitter produces an error-tolerant CST — it RECOVERS from syntax errors and still returns a tree. An obfuscator must hard-reject invalid input (never miscompile); error-tolerance is a correctness hazard, and CST node shapes (anonymous nodes, field indices) are a tax on every downstream transform |
| `full-moon` (github) | Rust, MPL-2.0, pushed 2026-04-15 (api.github.com) | yes | MPL-2.0 | Rejected: Rust — would need a WASM/native build in a Node/TS CLI; AST types not shared with the API (doc's stated reason for the TS stack) |
| official `luau-lang/luau` parser | C++, MIT, 5,952 stars, pushed **2026-10-10** (api.github.com/repos/luau-lang/luau) — this is the reference Luau implementation | yes (defines the language) | MIT | Rejected as a dependency: no maintained npm/WASM binding found (GitHub search "luau wasm parser": only webc-site/ulua, 10 stars, no license); C++ AST shape is foreign to TS transforms; vendoring and binding the C++ parser into the CLI contradicts the single-language build pipeline |
| `@tilua/compiler` (npm) | v4.0.0, 2026-10-05 | compiles *tilua* (its own language) to Luau | — | Not applicable: parser targets for tilua source, not Luau source |

npm keyword search "luau parser" (registry.npmjs.org/-/v1/search, 15
results) surfaced no further candidates. Conclusion: **no existing package is
Luau-complete, maintained, licensed, TypeScript-native, and strict.**

## 2. D1 decision: custom recursive-descent Luau parser in TypeScript

Rationale:

1. **No viable alternative** (table above). The niche is genuinely empty in
   the TS ecosystem.
2. **AST ownership is required anyway.** M4's whole job is transforms (rename,
   constant fold, string extract, doc §10.1) feeding an IR for M5. Every
   borrowed AST shape (CST fields, C++ unions) becomes an impedance mismatch
   re-paid in M5/M6 and in the per-build randomization (§10.2 item 4).
3. **Strictness is a security property.** A licensing platform's obfuscator
   must never silently accept malformed input and emit a miscompiled bundle.
   Hand-written recursive descent gives exact accept/reject control with
   precise error positions.
4. **The grammar is bounded.** Base Lua: ~60 productions, specified by the
   Lua 5.1 reference manual (lua.org/manual/5.1 — the grammar Luau extends).
   Luau additions, specified at luau.org/syntax (checked live today):
   type annotations, `continue`, compound assignment (`+=` etc.), string
   interpolation (backticks), if-expressions, generics, `type`/`export type`
   statements. We parse syntax only — NO type checking (types are erased to
   annotations on the AST; execution semantics don't need them).
5. **§22.1 fit.** A hand-written parser is testable against outside sources:
   the Lua 5.1 manual grammar (acceptance suite derived production by
   production), luau.org syntax examples (acceptance), round-trip differential
   (parse → print → re-parse → AST-equal), and a private corpus of real
   deobfuscated Roblox sources run locally (NOT shipped — they are the
   project's captured material).

Risks accepted (listed, not hidden, per §22.1):
- Parser bugs on exotic syntax. Mitigation: corpus + round-trip tests,
  fail-loud errors, and the M5 differential harness (§10.3) as the final
  gate; per-function `--@novm` opt-out exists in the doc for hot/sensitive
  cases.
- Grammar drift if Luau adds syntax. Mitigation: track luau-lang/luau
  releases; parser versioned (semver) with a syntax-support matrix in the
  README.

## 3. Semantic analysis plan (doc §10.2 item 2)

Scope resolution, upvalue capture, vararg handling, method calls, multiple
assignment/returns. Design notes:

- Single pass over the AST building scope objects (block → function scopes),
  following Lua 5.1 semantics (lua.org/manual/5.1 §2.9 visibility) — Luau
  keeps these semantics; only `continue` is new control flow (no new scoping
  rules; luau.org/syntax).
- Upvalue capture: transitive closure through nested functions; the IR later
  needs the same capture sets the M5 compiler will emit (Lua 5.1-style
  upvalue chains).
- Varargs: `...` legality tracked per function (not in main chunk of Lua 5.1;
  Luau allows `...` only in vararg functions).
- Multiple returns/assignment: the parser records expression-list context
  (last-position expandable); analysis marks call/`...` nodes as
  multi-value-capable — this is what M5's register allocator needs.

## 4. Constant and string protection plan (doc §10.2 item 6)

Build-time side of the contract (M6 owns runtime lazy decryption):

- All string/number constants extracted from functions into per-function
  constant pools during the transform pass (the "string extract" step of
  §10.1).
- Per-function key chain: `K(f_n) = HKDF(K(f_{n-1}), build_salt, n)` style
  derivation (exact construction to be pinned against §5.7 labels once M3's
  HKDF lands — do NOT invent new labels; §5.7 is immutable). Decrypting one
  function's pool never yields another's.
- The pool is handed to M5's container (§5.9) encrypted; M6's generated
  runtime decrypts lazily per function entry.

## 5. Test plan (§22.1 discipline from day one)

1. Acceptance suite derived from the **Lua 5.1 manual grammar** + **luau.org
   syntax** pages (outside sources; each test cites its production).
2. Round-trip differential: `parse → print → re-parse` must yield identical
   ASTs (catches printer and parser asymmetries).
3. Reject suite: malformed inputs must fail with positions (one error, no
   recovery).
4. Private corpus run (local only, not shipped): every deobf source in
   SavedFolder work/lua parses cleanly — recorded with file count in
   VERIFICATION-M4.md.
5. No test re-states the implementation: assertions check grammar-derived
   behavior, not internal token enums.

## 6. Decisions formerly framed as questions (superseded by DECISIONS-M4.md)

doc.md v4 (18555ec) added "Decision authority": decide and log instead of
stopping to ask. The questions below are resolved in DECISIONS-M4.md:
Q-M4a -> D-M4-2 (IR format lives in obfuscator/parser/IR.md, producer-owned),
Q-M4b -> D-M4-3 (use the contract's own \u00a75.7 "const-key" label). Kept
for the record:

- Q-M4a: May M4 pin the IR format (M4→M5 handoff) in obfuscator/parser/IR.md,
  or must it live in contracts/ (§5 is "do not change" — adding a file vs
  editing the doc)?
- Q-M4b: For the key chain (item 6), is deriving from §5.7 HKDF labels
  intended, or are obfuscator-internal labels acceptable? (I will not add
  labels to §5.7 myself.)
