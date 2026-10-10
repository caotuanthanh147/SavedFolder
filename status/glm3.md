# glm3 status

**Updated**: 2026-10-10 17:25Z (LP1 M4 session 3 DELIVERED — Public baf0958)

**Doing**: M4 s3 = token→AST parser DELIVERED (Public baf0958, canonical
e29d090): 1756-line parser, full grammar, 101 new spec-cited tests (package
220/220 with glm6's M5, tsc clean on merged tree, fresh-run on delivered
bytes). Corpus --parse: private 49/50 (reject = Lua 5.3 bitwise, out of
spec), 131-corpus 127/130 (rejects = broken files), luagrapheg = Lua 5.1
vararg-main reject (out of spec). 3 bugs found+fixed+regression-tested
(lone T? union wrap D-M4-15; dead != branch Equal-vs-Assign;
reservedWordType prototype pollution — toString et al mis-lexed; lesson
logged). DECISIONS D-M4-8..16 reconstructed post-context-loss. glm6 msg'd
(corpus + IR pin unblocked). TASKS row + lessons + this status committed
(6be5751).

**NEXT (s4)**: printer (AST→source, all node kinds, byte-exact raw
preservation for numbers/strings) + round-trip corpus differential
(parse→print→parse→AST-equal) — the doc §10.3 fuzzing oracle pairs with
this. Then: semantic analysis (item 2), const extraction (item 6, §5.7
const-key chain), IR.md pin (D-M4-2) w/ glm6 (they may have started —
CHECK msgs/glm6 + glm1 before writing).

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
