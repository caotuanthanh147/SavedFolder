# glm3 status

**Updated**: 2026-10-10 18:50Z (M4 s3+s4 delivered + IR.md v0 drafted)

**Doing**: M4 s4 = printer + round-trip differential DELIVERED (Public
44f04bf, canonical a3e8fd6, board 021756d): printer.ts (parens-are-data
D-M4-17) + roundtrip.ts comparator + 28 printer tests (package 248/248
with M5, tsc clean). Corpus round-trip: 49/50 + 127/130, ZERO mismatches
across ~1.63M nodes — §10.3-style differential oracle live. 6 bugs
fixed (headline: Group-injection class). s3 parser was delivered earlier
this session (baf0958) — see logs/glm3/m4-s3-20261010.md. Corpus --parse: private 49/50 (reject = Lua 5.3 bitwise, out of
spec), 131-corpus 127/130 (rejects = broken files), luagrapheg = Lua 5.1
vararg-main reject (out of spec). 3 bugs found+fixed+regression-tested
(lone T? union wrap D-M4-15; dead != branch Equal-vs-Assign;
reservedWordType prototype pollution — toString et al mis-lexed; lesson
logged). DECISIONS D-M4-8..16 reconstructed post-context-loss. glm6 msg'd
(corpus + IR pin unblocked). TASKS row + lessons + this status committed
(6be5751).

**NEXT (s5)**: IR.md v0 DRAFTED + delivered (Public 26fa49d; canonical
12f1e11) — Interface B (analysis side-tables) pending glm6 review (msg'd;
they pushed 7747a0a = active). While awaiting review: §10.3 fuzzer
(generator + round-trip oracle) needs no coordination — START THERE. Then
analysis.ts implementing Interface B once glm6 answers (their review may
adjust the shapes).

**Checkpoint (multi-day big project = LP1 Lua obfuscator)**:
- Lane: LP1-M4 (TASKS row 245). s1 lexer + s2 AST + s3 parser DELIVERED.
  Canonical: ~/SavedFolder/work/lp/m4. Public: obfuscator/ (FLAT package —
  parser src/tests + glm6's compiler/vm share one package.json; run
  `bun test` from obfuscator/ for the merged 220).
- Dependencies RESOLVED by s3: glm6's corpus end-to-end + IR pin. My next
  bottleneck-creating items: printer (M6/glm1 may want source-emitting
  transforms), IR.md.
- **Parallel-instance protocol ACTIVE**: a second glm3 launch was detected
  2026-10-10 16:40-16:42Z editing my tree (21/25 of the same fixes,
  verbatim comment). Lane-split msg in msgs/glm3/. Before ANY write to
  m4 files: re-read msgs/glm3/ + check mtimes vs last read; atomic edit
  failure = other instance won, re-read. Fold, don't revert. Its status:
  silent since 16:42 — possibly context-dead; if it wakes, the TASKS row
  + status now document s3 done (it should see them and yield or take
  review lane).
- Continuous-operation discipline (user, 3 warnings, last: "that's bad"):
  drive pending to empty + poll between items. Current pending: s4 printer
  (next), poll/watch active.
- Force-push risk: user force-pushes Public periodically; canonical in
  SavedFolder is the recovery source (lessons.md pattern). Last known
  user tip behavior: dropped module trees, doc.md + samples survive.

**Last session summary (s3)**: tsc-25-error batch (TS property-narrowing
soundness hole — curType() helper; overloads; parseIf(): IfStat) co-done
with the parallel instance; spec-derived test suite caught 2 parser bugs +
corpus caught 1 lexer bug (prototype pollution — invisible to lex-only
review); DECISIONS log reconstructed D-M4-8..16.

**Watchers**: poll.sh + watch_public.sh — restart best-effort each session
command (sandbox reaps between Bash calls). Msg protocol: consume via rm +
keep .gitkeep; msgs/glm6/ now exists (I created it — glm6 had no inbox
dir before).
