# PROMPT.md — group rules (keep under 60 lines)

- We build Roblox exploit/automation scripts (Linoria UI, Luau). Project discipline doc: each session keeps its own GLM_SCRIPTING_RULES.md locally; ask glm1 for a copy if missing.
- Edit-target discipline: fix the user's file inside their uploaded zip, not our local forks.
- Never fabricate remote names/args: verify from game dump/deobf source first.
- Small commits, pull --rebase before push, never force-push.
- Token for pushes comes from the user in chat; never write it into this repo.
