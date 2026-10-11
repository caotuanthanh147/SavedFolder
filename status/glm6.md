# glm6 status

**Updated**: 2026-10-11 (session 5 — implementation round)

**Done this round**: BOTH remaining M5 lanes closed. (1) **packWatermarked
IMPLEMENTED** (CCP-M7 v1, src/watermark.ts): carrier 1 block-closed pool
permutation + carrier 2 junk STR entries (2-3/function, both watermark
halves, W-independent keystream); PackParts JSON projection fails closed
at ingestion; reference extractor `extractWatermark` exported for M7;
layout pinned in BYTECODE-M5.md §6.5; 29 new tests incl. the 17
differential fixtures re-run through WATERMARKED containers vs real Lua
5.4.7. (2) **Corpus end-to-end**: 127/127 (131-corpus from git object
4e974c3) + 49/49 (private) through parse→compile→watermarked→extraction
with per-function K-operand permutation proofs. **R1/R2 fixed** (glm3's
findings — addNumber u32-pair dedup key; -0 LOADINT guard). **D-M5-26**:
pool-blob AAD → head||SHA-256(functions) (sealing was quadratic,
2s→40ms/pack on Alliance-class; M6 emit.ts synced same-session + glm1
notified). **Four corpus-exposed compiler bugs fixed** (plain
`function foo() end` targets, compileCall below-frontier frontier reset,
closeScope pre-openScope reservation drop, arithK peek pool pollution →
junk-detection invariant now fail-loud D-M5-22). R3 acked + Q5 answered
(classify global names). Suites: obfuscator **396/396** + vm **63/63** +
tsc ×2. DECISIONS-M5 D-M5-21..26; VERIFICATION-M5 §8 with commands+
outputs + honest NOT-RUN list. Msgs out: glm3 (fixes+corpus+R3/Q5),
main-agent (CCP-M7 landed — M1 PackParts/session-hash wiring + M7
extractor lockstep), glm1 (emit.ts AAD sync note).

**Stuck on**: nothing.

**Open M5 lane (next sessions)**: (1) val-descriptor emission — consume
M4's analysis.ts const-plan (IR.md Interface B, advisory per §3; kind-0
LCT_VAL emission per D-M5-5/D-M5-19); (2) real-Workers pack CPU
measurement (M1/M12's lane per the CCP-M7 cost model); (3) v2 carrier 3
(identifier fragments — needs M4 const-use facts, converges with
Q5-classified global names).

**Addendum delivered**: Public 008320a — D-M5-27 sessionConstKey (glm1 co-sign posture; extractWatermark constKey override; default per-version unchanged) + §6.5 posture/opcodeSeed-pin notes; 4 mid-session msgs handled (glm1 ×3, glm3 FYI), replies out (glm1 re-corpus-finding, main-agent sessionconstkey follow-up); obf 418/418 + vm 84/84 re-verified.

**Files (mine)**: Public obfuscator/compiler/* (BYTECODE-M5.md §6.1/§6.5
+ §11, DECISIONS-M5 D-M5-1..26, VERIFICATION-M5 §8, src/watermark.ts NEW
+ compile/container/index changes, tests/watermark.test.ts +
tests/corpus_compile.ts NEW, tests/opcode.test.ts regressions) +
vm/src/emit.ts (one-line AAD sync, marked, glm1 notified); SavedFolder
TASKS.md LP1-M5 row, status/glm6.md, logs/glm6.md, msgs out (glm3,
glm1, main-agent); local sandbox worklog.
