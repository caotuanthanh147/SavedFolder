# glm1 status

**Updated**: 2026-10-01 ~16:05 UTC (session 3 — T6 infrastructure)

**Doing**: nothing (T6 delivered; watching for user/glm2).

**Done this round (T6 — updated after merge with glm2's parallel T6): — user order: improve SavedFolder for faster/smoother scripting)**:
- Tools (all tested on real files): `shared/tools/bootstrap.sh` + `lua54.tar.gz` (portable Lua 5.4.7, cold env ~10s, survives /tmp wipes), `deobf_search.py` (remote map / `fn` block+payload extraction / find / strings / tags / attrs — validated on both Snack deobfs: PlaceTower payload L4509-4521, GameJoinPad L62220, attr census), `repack_zip.py` (delivery repack, per-entry MD5 verify; found+fixed a real zipfile ZipInfo-mutation bug), `lua_lint.py` (mechanical rule scan with `--from/--to` game-section range), `watch_public.sh` (ZIP+/ZIP- detection tested — automates T3 watching).
- Docs: `shared/ONBOARDING.md` (new-instance 10-minute cold start), `shared/SEARCH.md` (when/how to search; sources web-verified today), `shared/HARNESS_KIT.md` + `work/lua/snack_harness.lua` committed (157-check canonical kit).
- PROMPT.md pointers; guide §25 Tooling added + synced (510→536 lines); lessons +3 (ZipInfo mutation, unpack vs table.unpack, /tmp-vs-/home/z); changelog; TASKS T6 done + T7 (dogfood) opened for glm2.
- Repos moved to persistent paths: /home/z/SavedFolder + /home/z/Public (poll.sh default).

**Stuck on**: nothing.

**Files changed (mine, this repo)**: shared/{ONBOARDING.md,SEARCH.md,HARNESS_KIT.md,PROMPT.md,lessons.md,changelog.md}, shared/tools/* (bootstrap.sh, lua54.tar.gz, deobf_search.py, repack_zip.py, lua_lint.py, watch_public.sh), work/lua/{GLM_SCRIPTING_RULES.md,snack_harness.lua}, TASKS.md, status/, logs/, msgs/glm2/.
