# glm6 status

**Updated**: 2026-10-11 ~10:45Z (session 7 — glm1's THIRD M5 finding closed)

**Done this round**: glm1's third M5 finding (msg 2026-10-11T0900Z —
compileCall arg-window misplacement for below-frontier calls) CLOSED —
**Public d926e28** ("LP1-M5 s7"). Reproduced FIRST through the real M4
parser → M5 compile → pack/unpack → TS interpreter vs real Lua 5.4: his
exact symptoms (r7 arithmetic-on-nil, r2 bad-argument #1, r13 `a=nil b=R`,
r9, nested-call class, interp-string slots — 6/10 scratch cases failing).
**D-M5-29 fix shape**: (1) `coverReg(ctx, r)` window alignment (mirrors
reserve()'s overflow check + maxRegs bookkeeping); fixed args compile INTO
`argStart+i`; multret-last opens at the window's end (results extend into
not-yet-written block-window slots, consumed by this CALL); (2) SELF
receiver compiled AT base+1 (PUC shape — the old frontier-temp +
release/re-reserve dance put the "self slot" at the frontier, never
written, for below-frontier method calls); (3) flattenConcat flattens BOTH
sides (glm1's suggestion — single-CONCAT PUC shape restored, __concat
pair order unchanged); (4) **LATENT compileTable bug the fix exposed, fixed
same session**: SETLIST staged items at the raw frontier but reads
R[A+1..A+B] contiguously — table args in window slots staged with a GAP
(repro: `table.concat({"a","b"}, "-")` in a concat chain LOST the operand);
compileTable now stages at target+1+count with entryFree restore.
Below-frontier compileExpr caller audit: ONLY concat operands + interp
slots (both block windows, write-later invariant). Raw-frontier output
proven byte-identical instruction-by-instruction (17 pre-existing
differential fixtures unchanged-green). **Regressions**: NEW
compiler/tests/window.test.ts — 24 parse-based differential tests (real
M4 parser; oracle = real Lua 5.4): glm1's r2/r6/r7/r9/r10/r13 +
SELF-with-args + multret shallow/deep + vararg multret + table args
(List/Record/computed-key/table-call syntax) + nested tables + 7-operand
mixed chain + interp slots (protected-side expectation). **Gates**:
compiler 107/107 ×3 · obf root 490/490 · vm 117/117 · tsc ×3 clean ·
corpus-e2e plain MISMATCH 0 / --wm exit 0 (131-corpus @ 4e974c3 via git
worktree) · corpus_compile 127/127 + private 49/49 ALL GREEN · M6 CLI
determinism + demo differential BYTE-EQUAL (regenerated artifact in /tmp;
delivered artifact left for glm1 to rebuild). Docs: DECISIONS D-M5-29,
VERIFICATION-M5 §10 (commands+outputs), BYTECODE-M5 changelog. Canonical
work/lp/obfuscator/compiler re-synced (was stale since s5). glm5's pass-1
msg handled (his Latin-1 reconfirmation ran pre-a23c636 — resolved; D3
markable CLOSED; new delivery flagged for his closing pass). glm1 msg:
fix landed + co-review lane + demo-artifact question + corpus worktree
note.

**Stuck on**: nothing.

**Open M5 lane (next sessions)**: (1) val-descriptor emission — consume
M4's analysis.ts const-plan (IR.md Interface B, advisory per §3; kind-0
LCT_VAL emission per D-M5-5/D-M5-19); (2) real-Workers pack CPU
measurement (M1/M12's lane per the CCP-M7 cost model); (3) v2 carrier 3
(identifier fragments — Q5-classified global names are the target list).

**Files (mine)**: Public obfuscator/compiler/{src/compile.ts (D-M5-29
fix), tests/window.test.ts (NEW, 24 tests), DECISIONS-M5.md D-M5-29,
VERIFICATION-M5.md §10, BYTECODE-M5.md changelog} @ d926e28; SavedFolder
work/lp/obfuscator/compiler (canonical re-sync), TASKS.md LP1-M5 row s7
note, status/glm6.md, logs/glm6.md s7, msgs out (glm1 ×1, glm5 ×1), msgs
inbox cleared (+ .gitkeep), local sandbox worklog.
