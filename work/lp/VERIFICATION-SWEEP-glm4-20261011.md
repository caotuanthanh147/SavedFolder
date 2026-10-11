# VERIFICATION-SWEEP-glm4 — 2026-10-11 (repo-wide independent re-run, merged tree c7fa21f)

Reviewer: glm4 (author of M8 only; every other module reviewed by an instance
≠ its author, per doc §22.1 "reviewer ≠ author and runs tests itself").
Tree under test: Public origin/main c7fa21f (= glm3's 1f7be55 M4-s7 + glm4's
M8 delivery on top; working tree clean, `git status` empty for all touched
packages). Toolchain: bun 1.3.14 (frozen installs per package where a lockfile
exists), TypeScript per each package's committed bun.lock, Lua 5.4.7 from
SavedFolder shared/tools/lua54.tar.gz (extracted to ~/.lua54).

## Results (command → output → verdict)

| # | Suite (owner) | Exact command | Result | Verdict |
|---|---|---|---|---|
| 1 | api/ bun test (M1 main-agent, M10, M12) | `cd api && bun test` | 249 pass / 0 fail, 1208 expects, 18 files — **with glm4's CCP-M8 patch mounted** (P4 url.search fix incl.) | ✓ |
| 2 | api/ tsc | `cd api && bun run typecheck` | exit 0 | ✓ |
| 3 | bot/ (M8 glm4 — self) | `cd bot && bun test` / `bun run typecheck` | 44/44, 136 expects / exit 0 | ✓ (author self-run; needs an independent reviewer per §22.1) |
| 4 | obfuscator/ parser (M4 glm3) | `cd obfuscator && bun test` / `bun run typecheck` | 428/428, 32608 expects / exit 0 | ✓ |
| 5 | obfuscator/compiler (M5 glm6) | `cd obfuscator/compiler && bun install --frozen-lockfile && ./node_modules/.bin/tsc --noEmit` | **exit 2 — 4 errors** (see finding F1) | ✗ |
| 5b | obfuscator/compiler tests | `cd obfuscator/compiler && bun test` | 78/78, 450 expects | ✓ |
| 6 | obfuscator/vm (M6 glm1) | `cd obfuscator/vm && bun test` / `bun run typecheck` | 84/84, 360 expects / exit 0 | ✓ |
| 7 | M3 loader Lua suite | `lua5.4 tests/run.lua` (repo root) | 101 passed, 0 failed | ✓ |
| 8 | M7 checks Lua suite | `lua5.4 tests/m7_checks_test.lua` | 40 passed, 0 failed | ✓ |
| 9 | loader/stub (M13 glm4 — self) | `cd loader/stub && bun install --frozen-lockfile && bun test && bun run typecheck` | 42/42, 179 expects / exit 0 | ✓ (self) |
| 10 | loader/assembly (M3 s3 glm1) | `cd loader/assembly && bun install --frozen-lockfile && bun test && bun run typecheck` | 9/9, 20 expects / exit 0 | ✓ |
| 11 | db seed smoke (M2 glm3) | `bun db/seed/seed.ts --print --test-fixtures` | 861-char SQL output incl. owner-bootstrap row + one-time adm token line | ✓ |
| 12 | .github/workflows/ci.yml (M12 glm3) | `python3 -c "import yaml; yaml.safe_load(...)"` | **ScannerError line 94 col 37** (see finding F2) | ✗ |

## Findings

**F1 (msg'd glm6, paste-ready fixes attached):** compiler package tsc fails on
delivered s5 bytes — `src/watermark.ts(31)` unused `Insn` import;
`tests/corpus_compile.ts(27)` unused `pack` import; `tests/watermark.test.ts(75)`
unused `x`; `tests/watermark.test.ts(173)` `.kind` missing from a too-narrow
JSON cast (`serializePackParts` does emit `kind` — watermark.ts:503 — so the
runtime is correct; widening the cast is sound). Tests 78/78 unaffected.
Consequence: CI "Typecheck x3" step fails at the compiler line. Likely miss
mechanism: root-level `tsc --noEmit` in obfuscator/ is clean because the root
tsconfig includes only root src/tests (verified: exit 0) — the compiler
package's own tsconfig was never run against s5's new files.

**F2 (msg'd glm3, paste-ready fixes attached):** ci.yml as delivered never
runs on GitHub — (a) line 94 `- name: Install (lockfile TODO: owner first CI
run — see file header)` has an unquoted `: ` → YAML ScannerError → workflow
file rejected entirely, zero jobs; (b) line 16 `branches: ain]` (should be
`[main]`) — parses as string "ain]", never matches, so pushes to main would
not trigger even after (a) is fixed.

**F3 (observational, no msg needed):** M8 (mine) and M13 (mine) rows are
self-verified here; per §22.1 they still need an independent reviewer — the
bot suite is runnable in one command (`cd bot && bun test`) with no external
services needed (real HTTP to an in-process api router; Discord layer faked
to doc shapes).

## NOT-RUN (honest list)

- Corpus end-to-end (131-file): corpus not committed (project-captured
  material, M4 corpus.ts convention) — not runnable from the repo alone.
- dashboard/ lint + install: no lockfile in tree; CI header itself marks it
  owner-first-run follow-up.
- dependency-audit job: informational (`continue-on-error: true`) — skipped;
  no runtime deps changed by the sweep.
- Real-deploy surfaces (Workers, D1, R2, Discord gateway): unchanged scope,
  owner checklist.
- M5 differential fixtures vs real Lua oracle: covered inside the compiler
  bun suite (78/78 includes the 17 differential fixtures per VERIFICATION-M5);
  not re-run separately under lua5.4.

## Sweep method notes

- Rebase discipline: sweep ran AFTER glm4's session-8 rebase onto the fleet's
  overnight commits; `git status` clean in every package before each run.
- Exit codes captured directly (not through pipes) for every tsc run — an
  earlier `… | tail -2; echo $?` shape masks tsc's code with tail's (noted
  here because it nearly mis-reported F1 as 2 errors instead of 4).
- The M12 api tests include ops+chaos suites (glm3) and M10 payments suites —
  covered transitively by run #1.
