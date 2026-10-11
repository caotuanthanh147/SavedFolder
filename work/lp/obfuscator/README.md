# M4 — Obfuscator front end (Luau parser, analysis, constant protection)

Module card for LP1-M4 (doc.md §10.2 items 1, 2, 6). Owner: glm3.
Status: **delivered** (s1 lexer + s2 AST + s3 parser + s4 printer +
s5 fuzzer + s6 analysis/const-plan; IR.md Interface B v1 implemented,
revision-gated on glm6's review — open Q1/Q2/Q4/Q5).

## What this module owns

1. **Parser** — strict Luau syntax: Lua 5.1 base grammar + Luau additions
   (type annotations, `continue`, compound assignment, string interpolation,
   if-expressions, generics, `::` casts, `//` floor division, attributes).
   **Printer** (s4) — AST → source, round-trip faithful: `print(parse(src))`
   re-parses to a structurally identical AST (tests/roundtrip.ts comparator;
   corpus differential ~1.63M nodes clean). Parens-are-data policy: D-M4-17.
2. **Semantic analysis** — upvalue capture sets + immutability proofs
   (§10.2 item 2): per-function capture tables in first-use order with
   `ref`/`val` classification (`val` ⇔ never-assigned after binding,
   whole-binding downgrade; loop vars always `ref`; type-level subtrees
   erased exactly like M5's compiler). `src/analysis.ts`.
3. **Constant and string protection** — build-time extraction plan
   (§10.2 item 6): per-function pool candidates with exact dedup keys,
   `protect` (AEAD routing: strings ≥ 8 bytes, non-trivial number raws,
   ALL member names) and `inlineOk` (LOADINT range) flags. The chain
   bytes stay M5's (BYTECODE-M5.md §6.2). `src/analysis.ts` + IR.md §2.2.

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
| Parser → AST | **done, tested** — 101 spec-derived cases; corpus 127/130 + 49/50 (rejects = broken/out-of-spec files) |
| AST printer (round-trip) | **done, tested** — corpus differential ~1.63M nodes clean; parens-are-data D-M4-17 |
| §10.3 fuzzer | **done, tested** — seeded generator + round-trip + mutation oracles; 5000-soak clean |
| Semantic analysis (item 2) | **done, tested** — capture sets + val/ref proofs; corpus invariants OK (boundary captures per C1 — private: 6,494 captures, 83.0% val; 131-corpus: 24,493 captures, 90.0% val) |
| Constant extraction (item 6) | **done, tested** — pool plans with exact keys (R1: collision-free, unlike computed-Number keys) + protect/inlineOk flags; corpus invariants OK |
| IR.md Interface B | **v1 implemented**, revision-gated on glm6 (Q1/Q2/Q4/Q5 open; Q3 resolved by glm1's correction) |

## Layout

```
src/tokens.ts    token model, reserved words (verbatim Luau kReserved)
src/errors.ts    LuauSyntaxError (fail-loud, single error, positions)
src/lexer.ts     the lexer + parseNumberLiteral
src/parser.ts    tokens → AST (full Luau grammar)
src/printer.ts   AST → source (round-trip faithful; D-M4-17)
src/analysis.ts  semantic analysis + const plan (IR.md Interface B v1)
src/index.ts     package entry (public API re-exports)
tests/           bun test suite (spec-derived: every case cites its source)
tests/corpus.ts  private corpus runner (not run against shipped files)
tests/fuzz.ts    §10.3 seeded generator + oracles
IR.md            the M4→M5 interface (A: AST contract; B: analysis)
```

## Usage

```typescript
import { tokenize, parse, print, analyze } from './src/index';
const tokens = tokenize(sourceLatin1); // throws LuauSyntaxError on malformed input
const chunk = parse(sourceLatin1);     // → Chunk (AST)
const src2 = print(chunk);             // byte-faithful re-emission
const { captures, constPlan } = analyze(chunk); // IR.md Interface B side tables
```

Files must be read byte-exact (latin1): `buf.toString('latin1')` — the lexer
treats each char code as one byte, matching Lua byte-string semantics.

## §22.1 compliance

See VERIFICATION-M4.md: commands + outputs for every claim, external-source
derivation for every test, and the honest NOT-RUN list.
