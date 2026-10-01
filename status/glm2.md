# glm2 status

**Updated**: 2026-10-01 16:00 UTC (session 2)

**Doing**: finished the user-assigned session-improvement round (T6); restarting the T3 Public-watch poll.

**Progress (session 2)**:
- Handled glm1's message (Snack fix delivered 7cd68b0 — my diagnosis + their cloneref OrigRemotes discovery were TWO independent 0-capture bugs; deleted the handled message). Division of labor confirmed: T3/T4 mine, guide theirs.
- **T6 done** (user: "improve the SavedFolder to make the scripting process faster and smoother"):
  - `work/lua/clean-code-violations-scpinc.md` — the SCPINC clean-code violation notes the user asked for (StepRebirth + 12 more, each mapped to guide §21/§23; includes V12 stats-labels and V13 game-prefixes). NOTES ONLY — user said don't fix.
  - `shared/GUIDE.md` — 10-minute new-instance quickstart (reading order, pipeline, protocol, file map, shortcuts).
  - `shared/tools/` (all tested): `bootstrap.sh` (repos + lua5.4 restore from debs + state summary), `validate.sh` (luac5.4 -p + template-diff + style; verified 783/890/18 on SCPIncremental.lua), `newgame.sh` (extract + inventory + Rule-18 checklist), `repack.sh` (python3-zipfile core, MD5-verified originals; unzip CLI glob trap found + documented), `harness_lib.lua` (generic mock prelude extracted from the SCPINC harness + 12/12 smoke checks).
  - Web research: clean-code sources cited in the notes (Lua best practices, function-indirection articles); rule itself now codified in guide §21 by glm1.
- Credential audit of work/lua/ for glm1: CLEAN (git grep + per-zip-member scan = 0).
- Sandbox was reset at session start (clones + /tmp wiped) — re-cloned everything; lua5.4/luac5.4 restored via bootstrap.sh (its own test).

**Stuck on**: nothing.

**Files changed (mine)**: work/lua/clean-code-violations-scpinc.md, shared/GUIDE.md, shared/tools/{bootstrap,validate,newgame,repack}.sh, shared/tools/harness_lib.lua, shared/tools/poll.sh (autostash), msgs/glm1/glm2-*.md, TASKS.md (T6), shared/lessons.md, shared/changelog.md, status/, logs/.

**Next**: T3 watch Public for the next game zip (poll.sh running); answer any msgs; if a new game lands, standard pipeline starting with bootstrap.sh + newgame.sh + harness_lib.lua.
