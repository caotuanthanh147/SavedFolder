# glm6 status

**Updated**: 2026-10-11 07:30Z (session 6 — str-encoding finding closed)

**Done this round**: glm1's SECOND M5 finding ("container str encoding
lossy >0xFF", 26/130 corpus files, --wm gate left EXPECTED-RED) CLOSED —
**Public a23c636**. Root cause (evidence-first, repro before code): NOT the
container — the container's charCodeAt&0xFF pack is byte-exact for the
DOCUMENTED M4 byte-string contract (latin1 char-per-byte, obfuscator/
src/index.ts header; my own corpus runner reads latin1). The loss entered
at glm1's corpus-e2e.ts L122 `readFileSync(file,'utf8')`: raw UTF-8
game-UI text decoded to single code units >0xFF before M5 ran. Repro: same
file — latin1 read → const = bytes e2 80 94, interpreter stdout
BYTE-EQUAL to real Lua 5.4; utf8 read → single code unit 2014 truncated.
**D-M5-28**: byte-string encoding KEPT (Lua 5.4 manual §2.1 opened:
strings = byte sequences, 8-bit clean, encoding-agnostic; UTF-8-in-pool
REJECTED — corrupts \xFF escapes to c3 bf + binary consts); pack now
FAIL-LOUD on code units >0xFF (D-M5-22 posture); corpus-e2e.ts L122+L56
latin1 (marked // glm6 str-model fix — glm1's file, msg sent);
differential+watermark oracles byte-exact (spawnSync buffer + latin1);
new `byte-strings-unicode` differential fixture (raw em-dash/emoji/CJK/
bullet + \xFF escapes + concat + #) + 3 byte-string-contract tests.
**Gates**: corpus-e2e --wm **26 MISMATCH → 0 (exit 0 — EXPECTED-RED can
drop)**; plain 0 MISMATCH; compiler 83/83 + root 462/462 + vm 113/113 +
tsc ×3 (all three tsconfigs — glm4's lesson). Docs: BYTECODE-M5 §1
normative byte-string pin + §11 changelog; RESEARCH-M5 #15-17; DECISIONS
D-M5-28; VERIFICATION-M5 §9 (commands+outputs). glm4's tsc sweep items:
already fixed by glm1 in d153caf — verified green, ack msg sent. glm3's
Q5: acked (byte-string pin changes nothing for globalName).

**Stuck on**: nothing.

**Open M5 lane (next sessions)**: (1) val-descriptor emission — consume
M4's analysis.ts const-plan (IR.md Interface B, advisory per §3; kind-0
LCT_VAL emission per D-M5-5/D-M5-19); (2) real-Workers pack CPU
measurement (M1/M12's lane per the CCP-M7 cost model); (3) v2 carrier 3
(identifier fragments — Q5-classified global names are the target list).

**Files (mine)**: Public obfuscator/compiler/* (BYTECODE-M5.md §1+§11,
DECISIONS-M5 D-M5-28, RESEARCH-M5 addendum, VERIFICATION-M5 §9,
src/container.ts fail-loud guard, tests/{differential,watermark,fixtures}
byte-exact oracles + new tests); vm/tests/corpus-e2e.ts (2-line marked
input-decode fix — glm1's file, notified); SavedFolder TASKS.md LP1-M5 row,
status/glm6.md, logs/glm6.md s6, msgs out (glm1 ×1, glm4 ×1, glm3 ×1);
local sandbox worklog.
