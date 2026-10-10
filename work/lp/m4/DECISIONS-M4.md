# DECISIONS-M4 — Decision Log (doc.md "Decision authority", added v4/18555ec)

Format per doc: Decision | Options considered | Choice | Why (with evidence)
| Tier | Reversibility | Affects modules.

| # | Decision | Options considered | Choice | Why (with evidence) | Tier | Reversibility | Affects modules |
|---|----------|--------------------|--------|---------------------|------|---------------|-----------------|
| D-M4-1 | Luau parser: existing library vs custom | luaparse; luau-parser (npm); tree-sitter-luau; full-moon (Rust); official luau-lang/luau C++ parser via WASM; custom recursive-descent TS | **custom recursive-descent TypeScript** | Registry/API survey 2026-10-10 (RESEARCH-M4.md §1, sources opened): luaparse = Lua-only, last publish 2021; luau-parser npm = 5 weeks old, 0 stars, NO LICENSE (legal blocker for a commercial product core); tree-sitter = error-tolerant CST, silently accepts invalid input (correctness hazard for an obfuscator); full-moon = Rust (doc §4 pins Node/TS CLI "shares types with API"); no maintained WASM binding of the C++ parser. AST ownership is required for transforms anyway; strict accept/reject is a security property | 1 (library choice inside module, researched) | medium — parse layer swap keeps AST/analysis if AST types hold | M5, M6 (consume the AST/IR) |
| D-M4-2 | Where the M4→M5 IR handoff format lives | `contracts/IR.md` (shared root) vs `obfuscator/parser/IR.md` (producer module) | **`obfuscator/parser/IR.md`**, referenced from this README | doc repo layout places parser under `obfuscator/`; `contracts/` carries the immutable cross-wave Shared Contracts (§5) — an M4↔M5 interface is a wave-internal agreement (doc §7 Wave 2 "after interfaces are agreed"). Producer-owned doc keeps §5 untouched (no silent contract additions, per Hard Rules) | 2 (reversible choice touching one other module) | high — moving a doc file | M5 |
| D-M4-3 | Constant-pool key chain label | invent internal label vs use §5.7 `const-key` | **use §5.7 `"const-key"`** | The contract already reserves `"const-key"` "used inside the VM bundle for constant encryption chains" — the per-function chain construction (K_n = HKDF(K_{n-1}, build_salt, n) shape) is internal, but the HKDF info string is contract-fixed. My earlier draft question (RESEARCH-M4 Q-M4b) was answered by reading §5.7 — no CCP needed | 1 (contract already covers it) | high — chain construction is internal until M5 container pins bytes | M3 (HKDF primitive), M5 (container), M6 (runtime decrypt) |
| D-M4-4 | Source & string value model | UTF-8 JS strings vs byte-string (latin1 char-per-byte) | **byte-string (latin1)** | Lua/Luau strings are byte arrays, not UTF-8 (Lua 5.1 manual §2.1; Luau keeps this). Round-tripping arbitrary bytes (e.g. `\255`, deobf payloads) through UTF-16/UTF-8 would corrupt them. Latin1 decode keeps charCodeAt = byte, matches the reference's byte-buffer lexer | 1 | medium — model is pervasive but internal | none (internal) |
| D-M4-5 | Test oracle strategy | tests against my own output vs spec-derived assertions + private corpus | **spec-derived + private corpus** | doc §22.1: "tests must come from an outside source". Every lexer test cites Lua 5.1 manual / luau.org/syntax / Lexer.cpp-Parser.cpp behavior; corpus run (50 real scripts, 2.24 MB) validates against captured real-world Luau | 1 | high | none (internal) |
| D-M4-6 | Runtime/tooling | node+tsc+jest vs bun + bun test | **bun + bun test, tsc --noEmit for types** | db/seed.ts and api/ (M1) already run under bun in this project (M1's 59/59 = bun test); zero runtime deps keeps the parser vendorable into the build pipeline | 1 | high | none (internal; consistent with M1/M2 choices) |

## Notes

- RESEARCH-M4.md §6 "Questions for the doc owner" predates doc v4 (18555ec)
  and is superseded by this log: Q-M4a → D-M4-2, Q-M4b → D-M4-3 (answered
  by §5.7 `const-key`).
- Provisional decisions: none currently. The IR format itself (D-M4-2's
  content) will be pinned in `obfuscator/parser/IR.md` when the AST→IR pass
  lands (next session), agreed with M5's owner at claim time.
