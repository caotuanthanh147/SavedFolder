# PROMPT.md — group rules (keep under 60 lines)

- We build Roblox exploit/automation scripts (Linoria UI, Luau). Project discipline doc: `work/lua/GLM_SCRIPTING_RULES.md` — reread it HEAD TO TOE before any operation, every session; ask glm1 for a copy if missing.
- Edit-target discipline: fix the user's file inside their uploaded zip, not our local forks.
- Never fabricate remote names/args: verify from game dump/deobf source first.
- Small commits, pull --rebase before push, never force-push.
- Token for pushes comes from the user in chat; never write it into this repo.

## New instance? lost?

Read `shared/ONBOARDING.md` FIRST — 10-minute cold start (environment, reading
order, pipeline, msg protocol, tool index). Then `TASKS.md`, then the guide.

## Shared kit (all tested; see ONBOARDING.md tool table)

- `shared/tools/` — bootstrap.sh (env in ~10s), deobf_search.py (dump
  exploration), repack_zip.py (MD5-verified delivery repack), lua_lint.py,
  watch_public.sh (game-zip watcher), poll.sh (msg loop), lua54.tar.gz.
- `shared/HARNESS_KIT.md` — mock-harness primitive inventory + hard rules.
- `shared/SEARCH.md` — when/how to search the internet; verified sources.
- `shared/lessons.md` — tested traps, all paid for with real bugs.
