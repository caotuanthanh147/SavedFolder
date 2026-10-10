# VERIFICATION-M4 — §22.1 compliance record (sessions 1-3: lexer + AST + parser)

Scope: proves the session-1 (lexer) and session-2-start (AST module) claims
with commands and outputs; lists what was NOT run. Per doc.md §22.1 (added
doc v3, Public cd2ad33).

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

Session 2 (AST module added — src/ast.ts + tests/ast.test.ts):

```
 70 pass
 0 fail
 405 expect() calls
Ran 70 tests across 2 files. [20.00ms]
```

The AST kitchen-sink fixture (one literal of every node kind) caught a real
pre-merge defect: the statement 'TypeFunction' and annotation 'TypeFunction'
kind strings collided across STAT_KINDS/TYPE_KINDS — fixed by renaming the
annotation kind to 'FunctionType' (matching its interface) and adding a
pairwise-disjoint registry test. This is the §22.1 discipline working: the
fixture derives from the reference node set (Ast.h), not from my code's
self-consistency.

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

1. **The parser itself is not built yet.** Delivered so far: the lexer +
   number validation (session 1) and the AST TYPE module (session 2 start:
   node set per reference Ast.h, kitchen-sink fixture, registries). The
   token→AST parser, the printer, and round-trip differential
   (parse → print → parse → AST-equal) are the next session's work; the
   corpus run above exercises tokenization only. The AST module has no
   runtime of its own — its §22.1 evidence is tsc-clean compilation of the
   fixture (shape proof) + registry disjointness tests.
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

---

# Session 3 (2026-10-10): token→AST parser

## What I ran, and the output

### 1. Test suite (now includes tests/parser.test.ts — 101 parser cases + 4 lexer regressions)

Command: `bun test`

```
 175 pass
 0 fail
 840 expect() calls
Ran 175 tests across 3 files. [50.00ms]
```

Every parser case cites an outside source in its name: [L5.1] §2.4/§2.5/§3.3
(statement/assignment/expression/precedence/scoping — expected shapes computed
from the manual's priority table, e.g. `-a^2 == -(a^2)`, `..` right-assoc),
[LuauSyntax] (compound assigns, continue, if-else exprs, `::` assertions,
interpolation), [luau.org/types] (annotations, function/table/typeof types,
generics, singletons), [Parser.cpp] (contextual-keyword resolution,
&&/||/!=/! confusable messages, self insertion, isStatLast, ambiguous-call
line check, expectMatchAndConsume reporting, FInt::LuauRecursionLimit).

### 2. Type check

Command: `bun run typecheck` → exit 0, no errors.

### 3. Corpus: FULL PARSE (new `--parse` mode in tests/corpus.ts: tokenize →
parse → count AST nodes; every lex-accept that parse-rejects gets triaged)

Private corpus (work/lua, 50 files, 2,240,420 B / 424,026 tokens):

```
accepted:     49        total nodes: 362,862
rejected:      1  → potato-harness-core.lua 189:30 — file uses Lua 5.3+
                   bitwise operators (>> << | &); Luau has none (bit32
                   library instead); parser correct to fail-loud.
```

User-pushed 131-file corpus (Public 4e974c3, retrieved via
`git checkout 4e974c3 -- obfsucatortest/`; 130 .lua files, 8,646,341 B /
1,524,435 tokens):

```
accepted:     127       total nodes: 1,270,409
rejected:      3  → Dupe.lua 465:23 — corrupt file (raw \n in quoted string,
                   od-verified by glm1's reviewer run; known)
                   DinoHunters.lua 65:0 — file contains `local funcition
                   notyuri()` (typo'd keyword) → orphan `end`; broken in any
                   Lua. WaveDefenseOVERDRIVE.lua 189:6 — file contains
                   `local 5 = 20`; broken in any Lua.
```

luagrapheg.lua (Luraph sample, Public root): lexes (2,036 tok / 75 ms,
glm1-verified) but parse-rejects at 6:1118344 — the sample's VM loop uses
`...` at main-chunk top level, legal in Lua 5.1 (vararg main) but NOT in
Luau (D-M4-11 context stack starts non-vararg). Out-of-spec input, correct
fail-loud; documented, not a parser gap.

### 4. Session bugs found + fixed + regression-tested

1. **Lone `T?` assembled as a 1-element TypeUnion([TypeOptional])** instead
   of a bare TypeOptional (D-M4-15) — caught by the spec-derived test
   asserting `y: string?` annotation shape. Regression: type-annotations
   suite.
2. **`!=` confusable branch was dead code** — it tested for `TokenType.Equal`
   (`==`) but `!=` lexes as Bang + single-`=` **Assign**; `a != b` fell
   through to a generic "expected name" error instead of the reference's
   "did you mean '~='?" message (&& / || worked, != didn't). Regression:
   confusable-operators suite.
3. **reservedWordType prototype pollution** — `RESERVED['toString']` returns
   the inherited `Object.prototype.toString` function (truthy!), which
   leaked into token.type as a bogus keyword; ANY identifier named
   toString/constructor/valueOf/hasOwnProperty/isPrototypeOf/
   propertyIsEnumerable/toLocaleString mis-lexed (dotted access `t.toString`,
   bare `local toString = 1`, method calls, function fields). Caught by the
   corpus parse run (Ascension.lua 1078, TapIncremental.lua 272) — glm1's
   lex-only review could not see it because tokenize() doesn't inspect
   type values. Fix: `Object.hasOwn` guard. Regressions in BOTH suites
   (lexer + parser). Lesson logged to shared/lessons.md.

### 5. Type-narrowing batch (25 tsc errors)

TS does not invalidate property-path narrowing (`this.current.type`) across
method calls (advance/parse*) — a known soundness hole producing 22 false
TS2367s + 2 TS2345s + 1 real TS2322 (parseIf return type). Fixed via a
`curType()` fresh-read helper, parseSimpleType/parseFunctionType overloads
(allowPack: false ⇒ pack impossible), and parseIf(): IfStat. No runtime
behavior change (verified: same 175/175 before/after where applicable).

## NOT run (honest gaps — session 3 scope)

1. **Printer + round-trip differential** (parse → print → parse → AST-equal)
   — the next session's work (s4); corpus above proves tokens→AST only.
2. **No differential against the official Luau binary** (unchanged; the
   sandbox has no Luau runtime — lua5.4 ≠ Luau).
3. **No fuzzing yet** (doc §10.3 random program generator — pairs with the
   printer round-trip oracle).
4. **Performance not benchmarked** — indicative only: 1.95M tokens +
   ~1.63M AST nodes across both corpora in seconds under `bun run`.
5. **IR.md not pinned yet** (D-M4-2 content) — M4↔M5 interface lands with
   the analysis/constant-extraction pass, agreed with glm6 at claim time.

## Fresh-clone verification of delivered bytes

After the Public delivery commit: `git show HEAD:obfuscator/parser/src/parser.ts`
diffed against the canonical copy, and `bun install && bun test && bun run
typecheck` re-run from a clean checkout of the delivered tree — same
175/175 + tsc exit 0 (recorded in the session log).
