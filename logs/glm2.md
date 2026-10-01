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

## 2026-10-01 16:00 UTC — session 2: T6 session-improvement round (user-assigned)

- Sandbox reset at session start: SavedFolder clone + /tmp gone; re-cloned from GitHub (glm1 had joined: T2 Snack fix delivered Public 7cd68b0 with cloneref OrigRemotes + my wire-args diagnosis both applied; T5 guide §20.6+§24 done; message for me in msgs/glm2/).
- Handled glm1's message: work/lua/ credential audit CLEAN (git grep 0, per-member zip scans 0); noted their FindFirstChildOfClass point (SCPINC mock HAS it — but found the related Parent-vs-AddChild silent registration gap); deleted handled message; replied in msgs/glm1/glm2-20261001T155912Z.md.
- User assignment this prompt: improve SavedFolder for faster/smoother scripting + take clean-code violation notes for SCPIncremental.lua (StepRebirth example, "there's more") — notes only, no fixes.
- Web-searched clean-code principles (Lua best practices, function-indirection articles) — guide §21 by glm1 turned out to already codify the rule; my catalog cross-references it.
- BUILT + TESTED: work/lua/clean-code-violations-scpinc.md (13 violations V1-V13 incl. stats labels §23.2 + game prefixes §23.8); shared/GUIDE.md (new-instance quickstart); shared/tools/bootstrap.sh (repos + lua5.4-from-debs restore + state summary — its own reset-recovery was the test), validate.sh (luac + template-diff 783/890/18 verified + style checks incl. double-pcall hint), newgame.sh (extract/inventory/checklist), repack.sh (python3 zipfile core — FOUND+documented the unzip CLI glob-class trap: "[UPD 2]" patterns silently extract nothing → vacuous MD5 passes; MD5-verified replace+add paths), harness_lib.lua (generic prelude lines 8-688 of scpinc_harness + 12/12 smoke checks; gotchas in header: AddChild registration, snapshot-vs-getter, WhichIsA/OfClass gaps).
- TASKS.md T6 added (done); lessons +4 (unzip glob trap, AddChild gap, snapshot-vs-getter, task.spawn immediate-run); changelog updated; restarting poll.sh.

Stage Summary:
- SavedFolder now has a tested toolchain: bootstrap → newgame → (build) → validate → repack --commit, plus a reusable harness prelude — the next game session's bring-up drops from hours to ~1.
- SCPINC clean-code debt fully documented and rule-mapped (user's "take notes" delivered); no fixes applied per order.
