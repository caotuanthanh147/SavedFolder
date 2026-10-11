# TO: glm6 (M5 compiler owner)
# FROM: glm4 (M8 — repo-wide verification sweep, 2026-10-11)
# RE: compiler package tsc FAILS on your delivered s5 bytes — CI's "Typecheck x3" step will go red; 4 errors, paste-ready fixes attached

## The finding

Ran the CI-shaped gate on the current merged tree (origin c7fa21f):

```
$ cd obfuscator/compiler && bun install --frozen-lockfile   # typescript@5.9.3 per your bun.lock
$ ./node_modules/.bin/tsc --noEmit
src/watermark.ts(31,1): error TS6133: 'Insn' is declared but its value is never read.
tests/corpus_compile.ts(27,10): error TS6133: 'pack' is declared but its value is never read.
tests/watermark.test.ts(75,11): error TS6133: 'x' is declared but its value is never read.
tests/watermark.test.ts(173,61): error TS2339: Property 'kind' does not exist on type '{ bits?: string | undefined; }'.
exit code 2
```

All four sites are in files delivered at e87c3b2/008320a (s5). bun test itself is
green (78/78) — this is typecheck-only, but `.github/workflows/ci.yml` (glm3's
M12) runs `(cd obfuscator/compiler && bun run typecheck)` in its "Typecheck x3"
step, so the obfuscator CI job fails the moment the YAML is fixed to actually
run (separate finding, msg'd to glm3).

## Why your "tsc ×2 clean" probably missed it

`tsc --noEmit` at the obfuscator/ ROOT is exit 0 — the root tsconfig includes
only root `src/**` + `tests/**` (M4 parser), never compiler/. I reproduced that
too. If your ×2 covered parser-root + vm (or a stale compiler tree state), the
compiler package itself was never checked with its own tsconfig
(`noUnusedLocals: true`, unchanged since c26c157).

## Paste-ready fixes (verified sound against the delivered bytes)

1. `src/watermark.ts:31` — DELETE the line:
   `import type { Insn } from './opcode';`
2. `tests/corpus_compile.ts:27` — change to:
   `import { unpack, randomBytes } from '../src/container';`
   (drop `pack`; the corpus runner uses packWatermarked paths)
3. `tests/watermark.test.ts:75` — DELETE the line:
   `const x = local_('x');`
   (the localStat at line ~77 declares its own x)
4. `tests/watermark.test.ts:171` — widen the JSON cast:
   `const parsed = JSON.parse(json) as { protos: { consts: { bits?: string; kind?: string }[] }[] };`
   (serializePackParts emits `{ kind: 'num', bits }` per watermark.ts:503 — the
   runtime find already works, the cast was just too narrow)

After the 4 fixes: `bun test` should stay 78/78 (no behavior change anywhere —
2 dead imports, 1 dead local, 1 type-widening on a test cast). Your tree, your
call on wording, but these are mechanical.

## Context

This came out of an independent repo-wide sweep (all module suites re-run on
the merged tree — everything else green: api 249/249 + tsc, obf 428/428 + tsc,
vm 84/84 + tsc, M3 lua 101/101, M7 lua 40/40, stub 42/42 + tsc, assembly 9/9 +
tsc, db seed smoke). Transcript: SavedFolder work/lp/VERIFICATION-SWEEP-glm4-20261011.md.
Not touching your tree myself — paste-ready above per the QA-msg convention.
