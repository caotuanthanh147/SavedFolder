# glm2 log (append only)

## 2026-10-01 — session start (bootstrap)

- Cloned https://github.com/caotuanthanh147/SavedFolder — **repo was empty** (no glm1 files, no NOTES.md/TASKS.md/status/glm1.md). I am bootstrapping the shared structure per the user's protocol.
- Took name **glm2** (user designated me glm2, glm1 is the senior session).
- Cloned the task-source repo github.com/caotuanthanh147/Public to /tmp/Public. Current state: `tdref.zip` (Alliance.lua / Slop.lua / usethisfileSnack.lua reference scripts, uploaded 19:08 +0700), `error/error.txt` (Snack macro test: hook installs but `Recording [0]` — zero events captured, updated 19:10 +0700), `lesbian/` (executor workspace, ignore). snack.zip and TowerIncremental.zip deleted by user (games closed).
- Local sandbox state carried over from the previous solo session (this machine): oldglm.zip memory bundle, `Yuri/Template.lua` (891-line canonical), completed SCPINC-1 deliverable `Yuri/SCPIncremental/SCPIncremental.lua` (1,691 lines, 100/100 harness checks) + repacked `[UPD 2] SCP Incremental.zip`, `work-lua/scpinc_harness.lua` mock harness.
- **Token discovery**: the user supplied live git token ghp_…; grep confirms the SAME token was already saved ×2 in the oldglm/local worklog — the previous session's "PUSH NOT POSSIBLE / token redacted" conclusion was wrong (tool output redacts secrets at DISPLAY time only). Recorded as a lesson in shared/lessons.md.
- Imported all Lua project materials into `work/lua/` (rules, task source, template, SCPINC deliverable + harness + repacked zip, tdref.zip references, full scrubbed worklog). Scrubbed the live token from the worklog copy before committing (grep verify = 0 matches).
- Created TASKS.md (T1 SCPINC push, T2 Snack macro diagnosis, T3 watch for next game), shared/PROMPT.md, shared/lessons.md, shared/changelog.md, msgs/ dirs.
- Next: commit + push bootstrap, then push SCPINC deliverable to the Public repo (user: "you can put it to the main public"), then diagnose the Snack macro bug read-only, then message glm1.

## 2026-10-01 13:37 UTC — T1 + T2 done

- T1: pushed `[UPD 2] SCP Incremental.zip` (repacked, originals byte-identical, SCPIncremental.lua inside) to Public as commit 055dd8b. Convention followed (game zip at root, `<game>: add ... automation` message).
- T2: root-caused the Snack `Recording [0]` macro bug — full evidence chain in `work/lua/snack-macro-analysis.md`:
  * Game client: `EasyEvents:InvokeServer("PlaceTower", tbl)` (round deobf line 4510).
  * EasyEvents module (line 87918): `ensureRemote(name):InvokeServer(payload)` — name consumed pre-wire.
  * Hook sees `(self, payload)` → payload at nargs[2]; SnapshotCall reads nargs[3] (Slop port convention) → nil → 0 captured.
  * Fix = one line (nargs[3] → nargs[2]); harness mock also wrong (fired hook with name on wire). Not applied — game closed, awaiting user go-ahead per the "fix only when told" rule.
- Wrote msgs/glm1/glm2-20261001T133535Z.md (intro + findings + offer to help; glm1 has no presence in the repo yet — repo was empty at clone).
- Updated TASKS.md (T2 → diagnosis-done), shared/lessons.md (2 new lessons), shared/changelog.md, status/glm2.md.
- Starting background 30s pull/msg poll.
