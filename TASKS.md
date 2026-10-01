# Tasks

Claim a task by writing your name in the Owner column and pushing BEFORE you start.
Mark done when finished. Add new tasks at the bottom.

| ID | Task | Owner | Status | Notes |
|---|---|---|---|---|
| T1 | Push SCP Incremental deliverable (`work/lua/SCPIncremental.lua` + repacked zip) to github.com/caotuanthanh147/Public | glm2 | done | Delivered as repacked `[UPD 2] SCP Incremental.zip` at repo root (convention: game zip with script inside). |
| T2 | Snack macro "Recording [0]" bug — fix usethisfileSnack.lua (game re-opened by user: "Snack is the one we need to fix" + "continue with the fix") | glm1 | done | **Fixed & delivered** (Public commit 7cd68b0, tdref.zip repacked): (a) glm2's diagnosed wire-format fix `payload = nargs[2]`; (b) cloneref fix — OrigRemotes table (fresh `game:GetService` refs) + double-rawequal GetMacroRemoteKind ported from Alliance.lua; (c) AutoQueue join-pad fix — `CS:GetTagged("GameJoinPad")` filtered by RoundType nil/"Normal" + HostUserId==0, TP to nearest Walls part (was teleporting to unrelated `Lobby.Functional.Zones`); (d) `Fire("RequestStartGame")` added after RequestPlay (game's own host flow, deobf 50163); (e) Upgrade macro LVL semantics — post-original read, drop the `+1` (LVL = resulting level = `cfg.Upgrades[LVL]` tier index + replay skip level). Harness: 157/157 (Round 83, Lobby 52, Afk 22) with cloneref simulation (script RS = clone proxy, OrigRemotes = originals). |
| T3 | Watch github.com/caotuanthanh147/Public for new game zips; when the user uploads a new game, run the standard pipeline (GLM_SCRIPTING_RULES.md Rule 18: re-read guide + template first) | glm2 | waiting | IM file delivery is unreliable; the repo is authoritative. glm2 runs a 30s poll (shared/tools/poll.sh). |
| T4 | Keep TASK_SOURCE.md "Processed files" table updated after each game completes | glm2 | ongoing | Lives at `work/lua/TASK_SOURCE.md`. |
| T5 | GLM guide hook-failure sections: §20.6 wire-level payload indexing + new cloneref OrigRemotes section; sync into `work/lua/GLM_SCRIPTING_RULES.md` | glm1 | doing | From the Snack fix round; joint glm1/glm2 diagnosis. |

## Task source & project context

- The Lua scripting project lives in `work/lua/` — read `work/lua/GLM_SCRIPTING_RULES.md` (the guide, mandatory re-read per game), `work/lua/TASK_SOURCE.md` (game history + workflow), `work/lua/worklog.md` (full session history, token-scrubbed), `work/lua/Template.lua` (canonical template).
- Game zips arrive in the user's other repo: github.com/caotuanthanh147/Public. Do not push anything there except finished deliverables (repacked game zip with script inside, matching the existing commit style).
- The user re-opens a closed game by uploading fresh error logs + the reference zips AND saying so in chat — an explicit fix order beats any "looks like a re-open" inference (T2 case: the user said "Snack is the one we need to fix", which was the green light).
