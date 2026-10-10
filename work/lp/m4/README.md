# M4 — Obfuscator front end (Luau parser, analysis, constant protection)

Module card for LP1-M4 (doc.md §10.2 items 1, 2, 6; repo layout
`obfuscator/parser/`). Owner: glm3. Status: **in progress**.

## What this module owns

1. **Parser** — strict Luau syntax: Lua 5.1 base grammar + Luau additions
   (type annotations, `continue`, compound assignment, string interpolation,
   if-expressions, generics, `::` casts, `//` floor division, attributes).
2. **Semantic analysis** — scope resolution, upvalue capture, vararg
   handling, method calls, multiple assignment/returns (§10.2 item 2).
3. **Constant and string protection** — build-time extraction into
   per-function pools with a chained-key derivation (§10.2 item 6); runtime
   lazy decryption belongs to M6.

M5 owns the bytecode compiler + container; the M4→M5 handoff (IR format)
will be pinned in `IR.md` (see RESEARCH-M4 Q-M4a).

## Decision Log

Required by doc.md v4 ("Decision authority"): see DECISIONS-M4.md — parser
strategy, IR doc location, const-key label (\u00a75.7), byte-string model,
test oracle strategy, tooling. Research backing: RESEARCH-M4.md.

## D1 decision (recorded in RESEARCH-M4.md, sources checked 2026-10-10)

**Custom hand-written recursive-descent TypeScript parser.** No existing
package is Luau-complete + maintained + licensed + TS-native + strict:
`luaparse` (Lua-only, dead since 2021), `luau-parser` npm (5 weeks old, no
license), `tree-sitter-luau` (error-tolerant CST — silently accepts invalid
code, wrong for an obfuscator), `full-moon` (Rust, stack mismatch),
official `luau-lang/luau` C++ parser (no maintained npm/WASM binding).

The behavioral spec for the lexer is the reference implementation itself
(luau-lang/luau @ master, MIT — used as a SPEC, no code copied; our target
language is TypeScript).

## Status

| Component | State |
|---|---|
| Lexer (all Luau tokens: names, numbers, quoted/long/interpolated strings, attributes, operators incl. `//` `..=` `::` compound assigns) | **done, tested** — 62/62 spec-derived tests, tsc clean |
| Number literal validation/conversion (`parseNumberLiteral`: `_` separators, `0x`/`0b` u64 bit patterns, strtod-shape decimals, `i` int64 suffix, no hex floats) | **done, tested** |
| Byte-string model (latin1; `\u{...}` → UTF-8 bytes; arbitrary bytes in strings) | **done, tested** |
| Parser → AST | next session |
| Semantic analysis | later |
| Constant/string extraction + key chain | later (pinned against §5.7 labels; see RESEARCH-M4 Q-M4b) |
| AST printer (round-trip) | later |

## Layout

```
src/tokens.ts    token model, reserved words (verbatim Luau kReserved)
src/errors.ts    LuauSyntaxError (fail-loud, single error, positions)
src/lexer.ts     the lexer + parseNumberLiteral
tests/           bun test suite (spec-derived: every case cites its source)
tests/corpus.ts  private corpus runner (not run against shipped files)
```

## Usage

```typescript
import { tokenize } from './src/lexer';
const tokens = tokenize(sourceLatin1); // throws LuauSyntaxError on malformed input
```

Files must be read byte-exact (latin1): `buf.toString('latin1')` — the lexer
treats each char code as one byte, matching Lua byte-string semantics.

## §22.1 compliance

See VERIFICATION-M4.md: commands + outputs for every claim, external-source
derivation for every test, and the honest NOT-RUN list.
