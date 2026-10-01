# glm2 status

**Updated**: 2026-10-01 17:00 UTC (session 3 — T7 dogfood)

**Doing**: T7 complete. Idle/watching: T3 (Public watch — a new game MATI.zip landed 16:35 UTC; glm1's T8c covers MATI dogfood/analysis, script build stays glm2's if the user orders it).

**Progress (session 3 — user round: "keep improving SavedFolder, parallel to the other glm, watch overlap")**:
- Claimed T7 first (6301161) before any work — zero overlap with the parallel rounds (glm1 T8, session-2 T3 poll).
- Real cold start: bootstrap.sh from a sandbox with NO lua / NO ~/Public / token only in local worklog → **4.2s, everything restored** (repos cloned incl. Public, portable Lua 5.4.7 from repo tarball, token wired + ls-remote verified).
- One real use per category, all PASS: harness_lib 12/12; validate.sh reproduced the SCPINC baseline exactly (783/890/18, 0 comment-only); lua_lint.py 0 errors in game-section range (21 template-region warnings correctly downgraded); newgame.sh on the real MATI.zip; repack.sh dry-run on MATI.zip (originals byte-identical, injected MD5 OK); deobf_search.py remote/fn/tags/attrs on the real MATI deobf; watch_public.sh single cycle.
- 4 frictions found + fixed + re-tested (57de403): newgame.sh word-split dirs on space/emoji paths; repack.sh stale /tmp/Public default → /home/z/Public; deobf_search.py arg-order tolerance (FILE-first and CMD-first both work now); watch_public.sh --once single-cycle mode.
- NEW shared/tools/selftest.sh — 10-check kit smoke test (~5s), 10/10 green; run after ANY tool edit (docs it in ONBOARDING tool table + time-sinks).
- ONBOARDING.md tool table updated (selftest row, arg-tolerance, --once); lessons +2 (space/emoji path word-splitting, flexible arg order for multi-agent CLIs); changelog row; T7 → done; friction report + MATI intel + acks → msgs/glm1/glm2-20261001T165800Z.md; all 3 inbox msgs handled + deleted.
- Adopted glm1's push-verification rule (git ls-remote after every push); session-1 "push succeeded" log claim corrected in logs/glm2.md.
- Verified my 57de403 actually landed on origin (it did — the session-1 push failure class is now checked every time).

**Stuck on**: nothing.

**Files changed (mine, this session)**: shared/tools/{newgame.sh, repack.sh, deobf_search.py, watch_public.sh, selftest.sh (new)}, shared/ONBOARDING.md, shared/lessons.md, shared/changelog.md, TASKS.md (T7 done), status/glm2.md, logs/glm2.md, msgs/glm1/glm2-20261001T165800Z.md, msgs/glm2/ (3 handled msgs deleted).

**Next**: T3/T4 stand by for MATI.zip (wait for glm1's mati-analysis.md + explicit user order before building); answer any msgs; keep the push-verify habit.
