# VERIFICATION-M4 — §22.1 compliance record (session 1: lexer)

Scope: proves the session-1 claims with commands and outputs; lists what was
NOT run. Per doc.md §22.1 (added doc v3, Public cd2ad33).

## Environment

| Item | Value |
|------|-------|
| OS | Linux (build sandbox) |
| Bun | 1.x (bun test runner) |
| TypeScript | 5.x via `tsc --noEmit` |

## What I ran, and the output

### 1. Test suite (spec-derived; every case cites Lua 5.1 manual, luau.org/syntax, or luau-lang/luau Lexer.cpp/Parser.cpp @ master — the outside sources, NOT my implementation)

Command: `bun test` (from `obfuscator/parser/`)

Output (tail):

```
 64 pass
 0 fail
 242 expect() calls
Ran 64 tests across 1 file. [19.00ms]
```

Coverage: reserved words (exact kReserved set; `continue`/`type`/`export`
contextual), Lua 5.1 manual number examples, hex/binary/u64-overflow/`i`
suffix conversion rules, all escape forms (`\xHH` exact-2, `\ddd` ≤ 255,
`\z`, `\u{...}` UTF-8 including 4-byte code points, escaped newlines),
long-string levels + first-newline skip + CRLF normalization + `[=` without
closing bracket rejection (skipLongSeparator sep ≤ -2 case), interpolated
strings (Begin/Mid/End/Simple split, brace stack with nested tables, quoted
`"}"` inside interpolation, `\u{` lookahead, `{{` rejection), operators
(compound assigns, `//`, `..=`, `::`, max-munch splits), comments (line,
level blocks, `---`, UTF-8 allowed, `--[=` fallback), attributes, error
positions, line tracking (only `\n` advances), NUL-byte-as-EOF C-string
semantics.

### 2. Type check

Command: `bun run typecheck` → `tsc --noEmit`

Output: no errors (exit 0).

### 3. Private corpus run (real Luau sources; NOT shipped — captured material stays in the private repo)

Command: `bun run tests/corpus.ts <private-corpus-root>`

Output:

```
corpus files: 50
accepted:     50
rejected:     0
total bytes:  2240420
total tokens: 424026
```

50 real executor-target scripts (autofarm builds, harnesses, the shared
Template — 2.24 MB) all tokenize cleanly.

## Why the tests are not "restating my implementation"

Assertions check grammar-documented BEHAVIOR (Lua 5.1 manual lexical
conventions and examples; luau.org/syntax; Lexer.cpp/Parser.cpp @ master
behaviors I read as spec), with expected values computed from the spec, not
from running my code. Example: `\u{1F600}` must decode to bytes
F0 9F 98 80 (toUtf8 spec), `0b12` must be malformed (binary digits only),
`continue` must lex as a Name (kReserved list), `{{` must reject
(BrokenInterpDoubleBrace).

## NOT run (honest gaps — session 1 scope)

1. **The parser itself is not built yet.** This session delivers the lexer +
   number validation only. Statements/expressions/types → AST, the printer,
   and round-trip differential (parse → print → parse → AST-equal) are the
   next session's work; the corpus run above exercises tokenization only.
2. **No differential against the official Luau binary.** The sandbox has no
   Luau runtime (lua5.4 ≠ Luau). Building luau-lang/luau locally for a
   reject/accept diff harness is possible future work (documented; not done).
3. **No fuzzing yet** (doc §10.3 asks for a random program generator for the
   supported subset — belongs with the parser + printer, since round-trip is
   the oracle).
4. **Lexer performance not benchmarked** (424k tokens in well under a second
   on the corpus — indicative only, not a measured benchmark).
5. **No integration with M5** — IR format not pinned yet (RESEARCH-M4 Q-M4a).

## Independent review status

- Not yet reviewed by another instance (M14 is always last per doc §7).
  Cross-check welcome: clone Public, `cd obfuscator/parser && bun install &&
  bun test`.
