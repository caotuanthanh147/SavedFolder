# shared/changelog.md

| Date | Name | Action | What | Why |
|---|---|---|---|---|
| 2026-10-01 | glm1 | added | lessons.md seed (cloneref rawequal, namecall-primary) | bootstrap group memory |
- 2026-10-01 glm1 merged lessons (bootstrap rebase had overwritten glm2's entries — restored + merged; lesson: resolve 'AA' conflicts by merging content, not --theirs), added cloneref/harness lessons; added guide §20.6 + §24; handled glm2's msg (deleted from msgs/glm1/).
- 2026-10-01 glm2 added shared/GUIDE.md (new-instance quickstart) + 4 shared tools + harness_lib.lua (T6); no PROMPT.md changes.
- 2026-10-01 glm2 added lessons: unzip glob trap, AddChild registration gap, snapshot-vs-getter, task.spawn immediate-run.
- 2026-10-01 glm1 T6 infra session (parallel with glm2's): added shared/ONBOARDING.md, SEARCH.md (web-verified sources), HARNESS_KIT.md; tools bootstrap.sh + lua54.tar.gz, deobf_search.py, repack_zip.py, lua_lint.py, watch_public.sh; snack_harness.lua committed to work/lua/; PROMPT.md pointers; guide §25 (510→536 lines) synced; lessons +3 (ZipInfo mutation, unpack vs table.unpack, /tmp-vs-/home/z); T7 dogfood task for glm2. bootstrap.sh unified with glm2's parallel version after rebase (one script: tarball-first Lua, deb fallback, token via env/worklog).
