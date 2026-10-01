# Tasks

Claim a task by writing your name in the Owner column and pushing BEFORE you start.
Mark done when finished. Add new tasks at the bottom.

| ID | Task | Owner | Status | Notes |
|---|---|---|---|---|
| T1 | Push SCP Incremental deliverable (`work/lua/SCPIncremental.lua` + repacked zip) to github.com/caotuanthanh147/Public | glm2 | done | Delivered as repacked `[UPD 2] SCP Incremental.zip` at repo root (convention: game zip with script inside). |
| T2 | Snack macro "Recording [0]" bug (error/error.txt in Public repo) — diagnose only; game was declared CLOSED in TASK_SOURCE.md, do not modify until user re-opens | glm2 | in-progress | Read-only diagnosis from tdref.zip refs (Alliance.lua working impl, Slop.lua, usethisfileSnack.lua user-edited build). Findings will go in `work/lua/snack-macro-analysis.md`. |
| T3 | Watch github.com/caotuanthanh147/Public for new game zips; when the user uploads a new game, run the standard pipeline (GLM_SCRIPTING_RULES.md Rule 18: re-read guide + template first) | unclaimed | waiting | IM file delivery is unreliable; the repo is authoritative. |
| T4 | Keep TASK_SOURCE.md "Processed files" table updated after each game completes | glm2 | ongoing | Lives at `work/lua/TASK_SOURCE.md`. |

## Task source & project context

- The Lua scripting project lives in `work/lua/` — read `work/lua/GLM_SCRIPTING_RULES.md` (the 20-section guide, mandatory re-read per game), `work/lua/TASK_SOURCE.md` (game history + workflow), `work/lua/worklog.md` (full session history, token-scrubbed), `work/lua/Template.lua` (canonical 891-line template).
- Game zips arrive in the user's other repo: github.com/caotuanthanh147/Public. Do not push anything there except finished deliverables (repacked game zip with script inside, matching the existing commit style).
