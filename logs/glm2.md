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

---
Task ID: session-3
Agent: glm2
Task: T7 — dogfood the tooling kit from a fresh session (user: "keep improving SavedFolder, parallel to the other glm, watch overlap")

Work Log:
- Pulled first: T6 already done by both instances + unified by glm1 (ONBOARDING.md canonical, bootstrap.sh merged, tool table combined). T7 was open and assigned to me — the fresh-session dogfood. Claimed it in status/glm2.md BEFORE any work (6301161) to stay off the parallel rounds' toes (glm1 claimed T8 mid-session: trim bloat + env-var paths + time-sink + MATI dogfood).
- Cold-started bootstrap.sh from a genuinely empty env (no lua5.4, no ~/Public, no ~/.lua54-env.sh; token only in the local sandbox worklog): 4.2s total — Public cloned to /home/z/Public, portable Lua 5.4.7 from the repo tarball, token wired into both remotes + ls-remote verified, state report + unread msgs + task owners printed.
- Ran one REAL use per tool category: harness_lib.lua smoke 12/12; validate.sh on SCPIncremental.lua (reproduced the session-2 baseline exactly: 783/890/18, 0 comment-only lines); lua_lint.py --from 784 (0 errors, 21 template-region warnings correctly downgraded); newgame.sh on the REAL new game /home/z/Public/MATI.zip (2 sub-games, 2 deobfs + 2 dumps, no Template); repack.sh dry-run on MATI.zip (4→5 members, originals byte-identical, injected MD5 OK); deobf_search.py remote/fn/tags/attrs on the real MATI deobf (var15:InvokeServer(var1.payload) wire, Fx* attrs, no tags); watch_public.sh single cycle.
- 4 frictions found + fixed + re-tested (commit 57de403): (1) newgame.sh `for d in $(find …)` word-split space/emoji paths → while-read; (2) repack.sh --repo default /tmp/Public (stale pre-unification) → /home/z/Public; (3) deobf_search.py FILE-first-only parsing (glm1's own doc phrasing invites CMD-first; I hit the traceback) → arg-order tolerance + usage-restating error; (4) watch_public.sh had no once-mode → --once flag.
- Built shared/tools/selftest.sh — 10-check kit smoke test on tiny fixtures (~5s; auto-sources ~/.lua54-env.sh): 10/10 green. Purpose: run after ANY tool edit; will guard glm1's T8a env-var refactor.
- Docs/process: ONBOARDING.md tool table + time-sinks updated; lessons +2 (space/emoji word-splitting, flexible arg order); changelog row; TASKS.md T7 → done; status/glm2.md final; friction report + MATI intel + acks in msgs/glm1/glm2-20261001T165800Z.md; 3 handled inbox msgs deleted.
- Discovered mid-session: my session-1 SCPINC delivery push NEVER landed on origin (glm1 verified + re-pushed it as 5521079). Adopted the verify-after-push rule (git ls-remote origin after every push) — my pushes this session all confirmed live.
- MATI.zip landed on Public 16:35 UTC (user's dea6ee8). Division per glm1's msg: glm1 does T8c tool-dogfood + mati-analysis.md; the MATI SCRIPT build is mine (T3) when the user orders it.

Stage Summary:
- The T6 tool kit is verified end-to-end from a true cold start: 8/8 categories real-use pass, 4 sharp edges fixed, and a 5-second selftest now guards the whole kit against future edits.
- Process hardened: claim-before-work prevented overlap with both parallel rounds (glm1 T8, session-2 T3); push failures are now caught (ls-remote verify) instead of silently believed.
- Ready state for the next game: MATI.zip intel recorded (wire shape, attrs, no tags); glm1's T8c notes + user order are the remaining triggers for the T3 pipeline.

---
Task ID: session-4-stress-ST6
Agent: glm2
Task: Stress round — ST6 (Sword RNG X): standard autofarm, no reference, ~6-min budget

Work Log:
- Wiped sandbox → re-cloned SavedFolder → bootstrap.sh 4.9s (repos + Lua + token). Read 3 glm1 msgs (stress conventions, MATI claim, T8 ack). Claimed ST6 first (sync e9036b8) before any work.
- deobf_search remote census: 2 server remotes (Combat RemoteEvent + RemoteFunction). fn extraction on fire(L17928) and fetch(L17934): networker wrapper pattern `fire(name,...) → RemoteEvent:FireServer(name,...)`. Remote path from game_dump: ReplicatedStorage.Packages._Index.leifstout_networker@0.3.1.networker._remotes.Combat.RemoteEvent.
- Wire verification: requestHit (L34049) = `fire("requestHit", uid, attackTargetUid, lastSwingCenter)`. Caller L36015 passes (arg1.uid, arg1.attackTargetUid, arg1.lastSwingCenter). Deobf L36263: attackTargetUid=nil (area attack valid). Enemy uid = model Name (getEnemyRig L32541: FindFirstChild(uid) by name). 25 remote folders total; Combat is the farm action.
- Built game section (123 lines): WaitForChild chain for versioned remote path, GetEnemies (workspace:GetDescendants, Model+Humanoid+Health>0, exclude players), Func_AutoAttack (while+task.wait(0.5), GetNearest, FireServer("requestHit", target.Name, nil, hrp.Position)), AutoAttack toggle on Autofarm tab via Thread+SafeLoop. SaveManager "Yuri/SwordRNGX".
- §3 compliance: ONE toggle, ZERO labels/stats/convenience. §17: template helpers only.
- Gates: luac OK, lint 0 errors, validate 783/18/123, harness 8/8 (wire format: arg1="requestHit", arg2=enemyUid, arg3=nil, arg4=Vector3).
- Delivered: Sword RNG X/Sword RNG X.lua (folder convention). Public fe3e703, ls-remote verified.

Stage Summary:
- ST6 done: standard autofarm (Auto Attack) for Sword RNG X, all gates green, delivered to Public (fe3e703, verified). Wire call-site verified per Rule 2. No-reference scope per §3 (autofarm ONLY, no inventions). Ready for next game (ST5/ST7/ST8 open).

---
Task ID: session-4-stress-ST5+ST7
Agent: glm2
Task: Stress round — ST5 (Open Sea For Animals!) + ST7 (8 Ball Duels): standard autofarm, no reference

Work Log:
- ST5 (Open Sea For Animals!): deobf_search + grep on 2.5MB deobf. Game uses Knit (sleitnick/knit). Found CollectEventService.RF.Collect remote. _SpawnPickup (L26012) parents models to workspace.CollectEventPickups folder, named "eventId_id". _CheckProximity (L26072) auto-collects on Heartbeat when HRP within radius. Built TP-based Auto Collect (TPTo nearest pickup, game auto-collects). Gates: luac+lint+validate 783/18/109+harness 6/6. Delivered Public 6f78f7f.
- ST7 (8 Ball Duels): grep on 3.9MB deobf. Game uses Replica remote system + named remotes (Remotes.Pool, Remotes.DailyReward, etc.). Found queue wire at L19796: `FireServer(Pool, "Queue", arg1.Id)` where arg1.Id = venue Id. Verified venue "Brazil" at L44055 (first of 11 venues). Built Auto Queue (Pool:FireServer("Queue", "Brazil") every 10s). PvP pool game → auto-queue is the standard farm equivalent. Gates: luac+lint+validate 783/18+harness 5/5. Delivered Public 424791d.

Stage Summary:
- 3 stress-round games delivered (ST5+ST6+ST7), all gates green, all wires call-site verified, all deliveries push-verified. §3/§17/§2 compliance on all 3. All 10 ST games now claimed across 4 glm instances.

---
Task ID: session-4-expand
Agent: glm2
Task: Expand stress-round scripts with more features (user order: "you add too little features, check other glm upload and improve")

Work Log:
- Compared my 3 delivered scripts (902-924 lines, 1 toggle each) with glm1's (1012-1034 lines, 7+ toggles with framework integration). User's criticism valid.
- Returned to deobfs for wire verification of new features:
  - Sword RNG X: Ascension RemoteFunction `InvokeServer("ascend", nil)` (wire L64602, feature setup L64594), Evolution RF `InvokeServer("evolve", nil)` (L66985/L66977), Shop RF `InvokeServer("restock")` no args (L62454).
  - Open Sea: Knit RFs — InventoryService.SellAll (no args, L28549), AnimalService.CollectOfflineCash (no args, L19087), SpinWheelService.SpinWheel (no args, L24831), DailyRewardService.ClaimReward (day index 1-7, L18513).
  - 8 Ball: DailyReward `FireServer("DailyClaim")` (L14064), SpinWheel `FireServer("SpinWheel")` (L15033).
- Expanded scripts: SwordRNGX.lua 1→4 toggles (Attack+Ascend+Evolve+Restock, 156-line game section), OpenSeaForAnimals.lua 1→5 toggles (Collect+SellAll+CollectCash+SpinWheel+ClaimDaily, 154 lines), EightBallDuels.lua 1→3 toggles (Queue+DailyClaim+SpinWheel, 123 lines).
- Gates re-run all 3: luac OK, lint 0 errors, validate confined to game section, 0 comments. Harnesses: Sword 11/11, Open Sea 6/6, 8 Ball 5/5.
- Re-delivered all 3 as Public 2333df7 (rebased on glm1's FlipAHouse d3127a1, push verified).

Stage Summary:
- 3 scripts expanded from 1 toggle each to 4/5/3 toggles. All new wires call-site verified per Rule 2. All gates green. All deliveries push-verified (2333df7).

---
Task ID: session-4-final-expansion
Agent: glm2
Task: Final feature expansion per glm5's review (under-scoping §3) + user order (too little features)

Work Log:
- glm5's review arrived mid-expansion with deobf-cited unwired features: Sword RNG Roll+Rebirth (L27161/L52082), Open Sea Hatch+Upgrade+Rebirth (L15828/L16272/L18235), 8 Ball OfflineClaim+Codes+EventQuestClaim (L17328/L13796/L21155).
- Round 2 expansion (5fb30cb): Sword RNG X +Auto Roll (Roll RF InvokeServer("roll") no-args, wire L27218) +Auto Rebirth (Rebirth RF InvokeServer("requestRebirth") no-args, L52094) → 6 toggles. Open Sea +Auto Rebirth (RebirthService.RF.Rebirth no-args, L28642) → 6 toggles. 8 Ball +Auto Event Quests (Events RE FireServer("EventQuestClaimAll"), L21269) → 4 toggles.
- Not wired with reasoning (Rule 11 judgment calls, explained to glm5 in msgs/glm5/): Open Sea Hatch (needs per-instance eggId from prompt attrs + IsHatching timing — InstantPP covers the prompt path), Open Sea Upgrade (needs upgradeType from game state), 8 Ball OfflineClaim (Replica-system wire needs replicaId from internal state), 8 Ball Codes (needs code strings from user).
- Gates re-run: luac+lint 0 errors+validate confined (178/165/134-line game sections)+harnesses 11/6/5. Delivered Public 5fb30cb (rebased on other glm's work, push verified).
- Replied to glm5 (msgs/glm5/glm2-20261002T060000Z.md) with the changes + reasoning for unwired features. Deleted their handled msg.

Stage Summary:
- 3 scripts now at glm1/MATI feature parity: 6/6/4 toggles vs 1 each before. The §3 lesson recorded: clause 1 (build the standard autofarm) and clause 2 (nothing else) are two gates — I was only honoring clause 2. Rule 11 bar: wire every remote with genuine automation value.

---
Task ID: ST-QA1-fix (glm2 side)
Agent: glm2
Task: Fix + re-deliver ST5/ST6/ST7 after glm1's ST-QA1 audit (all three broken at load)

Work Log:
- Read glm1's audit msg (T1 nil at load — TB.Main.Left.Autofarm.T1 doesn't exist, TB_Tabs.Autofarm.T1 is the template's own var) + glm5's two msgs (expansion verified, Auto Roll wired, thread closed — no action needed there).
- Fixed all 3 scripts: (a) 16x `TB.Main.Left.Autofarm.T1` → `TB_Tabs.Autofarm.T1`, dropped manual `Toggles.X =` assignment (lib registers by Idx into Library.Toggles); (b) §22-7 loop shape `while Toggles.X.Value do pcall(step); notyuri on err; task.wait(x) end` — work-then-wait, per-step pcall; (c) game section moved after template L819 (antiAFK block stays verbatim in head — my old scripts had a DUPLICATE antiAFK copy in the game section); (d) ST6 GetDescendants scan deleted.
- ST6 deeper find while fixing: old Auto Attack wire args were semantically wrong. sendHit L35984/L36015 + swing-state init L36261 (`uid = k4` from equipped-sword reconcile L36180) prove requestHit(swordUid, attackTargetUid, swingCenter) — sword uid = inventory uid of equipped sword (PlayerDataClient:get().equipped, module at RS.Source.Features.PlayerData.PlayerDataClient, required at L32833), enemy uid = CombatClient registry key (getEnemyModels L34180, registry populated by combatSnapshot L33164). makeEnemyModel L32959: enemy hitboxes are Parts named Enemy_<enemyId> in workspace.CombatVisuals (old scan looked for Models-with-Humanoid = would find nothing). New fire: FireServer("requestHit", swordUid, nearestEnemyUid, hrp.Position). Requires pcall-wrapped so missing modules degrade only Auto Attack.
- Rebuilt all 3 harnesses glm1-style: io.open + loadstring + task.spawn the REAL script; assert no ERROR notify, Library.Toggles registration, wire counts + payload tuples after SetValue(true)+pump, loop stops after SetValue(false); ST6 also retarget-after-enemy-removal + module mocks (G.require registry, PlayerDataClient/CombatClient) + full 6-remote networker tree. 16/16, 11/11, 11/11 — run against the DELIVERED Public bytes.
- Gates on all 3: luac OK, lint 0 errors (game section from 820), validate.sh head 819 verbatim / tail 18 / 0 comments / SaveManager-only tail edit.
- Delivered Public 3a54453 (commit + push + ls-remote verified). Replied to glm1 (msgs/glm1/glm2-20261002T061459Z.md) incl. note that their qa_load mocks for my games have world gaps (swordrngx missing Roll/Rebirth folders; opensea mock = swordrngx world; eightball mock has no RS.Remotes) — my harnesses are the game-accurate ones for their re-pass.
- Deleted processed msgs from msgs/glm2/ (glm1 + glm5 x2).

Stage Summary:
- ST5/ST6/ST7 re-delivered load-clean with real-script-verified harnesses. Feature counts unchanged (6/6/4 toggles). Two durable lessons: (1) harness must load the delivered script — green harnesses that re-implement the logic validate nothing; (2) verifying a wire's CALL SITE shape isn't enough — arg SEMANTICS need their producer traced (sword uid vs enemy uid both "uids" at the same call site). glm1 re-QA pending.

## 2026-10-03 session 6 — Shigaku multi-GLM round (SH1+SH2+merge+deliver)

- 07:35Z session start (sandbox reset again): bootstrap.sh glm3... glm2 with
  token from worklog. Watchers up. Public 71c4793 = [UPDATE] Shigaku.zip
  (uploaded 4 min earlier — single place, 258k-line deobf + 107k dump, no
  reference, no Template in zip).
- Claimed SH1+SH2 with the collab scaffolding (analysis file = coordination
  point). glm1 claimed SH3 harness + SH4 QA (07:42Z); glm3 claimed SH2-b
  roll cluster off my split offer (07:52Z, via glm1's mediation).
- SH1 delivered 07:43Z: shigaku-analysis.md (wire table w/ call-site lines;
  the Input.Fire strategy; module require paths; Rule 11 plan incl. the
  removed one-shots). Zero census disagreements from glm1; glm3 supplement
  +65 bridges, TrashBin wire, Posture client-auth.
- SH2 built: my harness caught (1) module-vs-instance child resolution bug,
  (2) Thread-cancel vs post-loop cleanup (Gym.Stop moved into OnChanged).
  Real-load 32/32 (faithful minigame dynamics: Balance tilt/vel/gust/
  runaway/damping, Stride alternation+idle, Grip drain/regrip/lockout,
  Reps pace band — all from the deobf math).
- glm1's harness + glm3's roll harness both needed the Game_Settings mock
  completion (Gym.Kinds etc.) — patched locally, 30/30 + 42/42 verified,
  patches messaged to owners (their lanes).
- Merged glm3's AutoRoll block verbatim + built InfinitePosture myself
  (glm3 scoped it out). All 3 harnesses green on the merged 1369-line file.
- DELIVERED: Public b8fcef4, [UPDATE] Shigaku.zip + Shigaku/Shigaku.lua
  (SCPINC convention), MD5-verified originals, ls-remote verified.
- Lesson: template-internal pcall errors are invisible to an outer xpcall
  (the eh_success pcall swallows + notifies) — intercept G.pcall in the
  harness to get tracebacks. Also: Instance mocks need dynamic child
  indexing OR scripts should use FindFirstChild chains (the game's own
  pattern is WaitForChild/FindFirstChild anyway).

## 2026-10-03 session 7 — identity mixup (glm1 lane for 25 min), correction, v2

- Woke to user poke. CONSUMED THE WRONG INBOX (msgs/glm1/ not msgs/glm2/) →
  ran as "glm1": re-verified gates + harnesses (53/1), audited v1 delivered
  bytes, found glm3's committed-harness crash (real finding, msg'd —
  mis-signed), pushed SH4 verdict + SH5 claim as "glm1". The real glm1 ran
  in parallel the whole time (2773287 audit, then 6c8ed21 accepting my
  bogus "twin glm1" lane split).
- User: "you are glm2 what are you even doing" → correction round: TASKS
  SH3/SH4/SH5 re-attributed; status/glm1.md restored from a708481 + note;
  msgs/glm1 + msgs/glm3 re-signed (glm3 header fixed; glm1's consumed
  "twin" msg replaced by properly-signed glm2 correction msg 083721Z);
  logs/glm1.md session-11 entry marked MISATTRIBUTED; this entry = the
  real record.
- THE ACTUAL WORK (was my todo all along — glm1's finding was addressed
  TO me): Knocked-skip filter on GetNearest(CombatDummy) — skip exactly
  "Knocked"/"Duo" (analysis §3.1; deobf CombatDummies bind() L4749 refuses
  those two; nil passes = game-faithful, glm1's nil-attr mock world still
  targets). First attempt (strict nil-skip) broke glm1's world (32→30) —
  relaxed to the spec-literal shape.
- MOCK GAP FOUND + FIXED (glm1's canonical, edit-with-msg): Vector3.Unit
  via vmt.__index — v4 lacked it; script `flat.Unit` read nil → `away`
  fallback (0,0,1) → every TP landed 4 studs +Z. My canonical 53/1 was
  masking it (position tolerances passed pre-fix because the player stayed
  at spawn near the Knocked dummy). With Unit: 54/0. Credit in-file
  L178-181, lifted from my own glm2-world harness (which had Unit).
- DEBUG TECHNIQUE (reusable): G.pcall interceptor via coroutine —
  `coroutine.resume(co,...)` + `debug.traceback(co)` on failure pins the
  exact script line even when the template pcall swallows the error. Needs
  G.debug = debug in the env. Caught: GetProductInfo gap + the L870
  Kinds-nil crash in glm3's harness.
- GATES + HARNESSSES (post-fix, all green): luac OK; lint 0 err / 21
  inherited template-region warnings; validate head836/tail18/0 comments;
  canonical 54/0, glm2 32/0, glm3 standalone 42/42 (their merged-context
  run still crashes — their committed mock lacks the Kinds extension,
  msg'd with paste-ready patch).
- Repack + Public v2 push next; re-audit request to glm1 with commit hash.
- V2 DELIVERED: repack via shared/tools/repack_zip.py (3 originals MD5-
  identical to b8fcef4, Shigaku.lua replaced 7f26494f72) → Public
  0c03f2b "Shigaku: fix dummy targeting (skip Knocked/Duo), drop
  duplicate block", ls-remote verified. Delivered bytes re-audited:
  byte-identical to work/lua/Shigaku.lua, canonical 54/0 on the extracted
  zip. Re-audit requested from glm1 (msg w/ hash + Unit note for their
  "targets USABLE dummy" check geometry); glm3 notified (their harness
  fix still their open item).

## Session 8 (2026-10-04 ~04:5xZ) — Potato round: POT1-H harness lane

- Woke to user "next game". Sandbox reset -> bootstrap glm2 (token wired,
  verified). Mandatory reading: ONBOARDING + PROMPT + TASKS + statuses +
  inbox (8 msgs: 7 stale Shigaku-round handled, deleted; glm3's SAC2
  confirmation answered — SCP zip DELETE, scratch removals no-flag).
- Public HEAD 2481993: Steal A Car + Drop a Fruit folders deleted by user
  (both games closed); NEW game = potato/ (Peel THE Potato, two-place:
  game + lobby, 76,287-line deobfs + dumps each, no reference, no
  Template in folder -> canonical + §3 standard autofarm).
- glm1 claimed POT1 full pipeline 04:35Z (c13c1ea). I msg'd them BEFORE
  touching the game: taking POT1-H (independent harness lane, Shigaku
  SH3 / SAC1-H pattern). TASKS row claimed + pushed.
- Direct-tool outage this session (Bash/Read failing in main session);
  subagent shells clean — all work executed via subagents. Watchers:
  restarted via bootstrap session files.
- In flight: potato census (both deobfs) -> potato-harness-glm2.lua.

### Session 8 (cont) — census built + verified

- Two census agents (parallel): potato-census-world-glm2.md (1,508
  lines: dump format pre-order DFS 2-pass; ONLY 3 remotes/place —
  Packet.RemoteEvent + 2 Cmdr; RS 4,089 inst/499 ModuleScripts 100%
  identical game/lobby; zero tags (only Ragdoll L42319); attributes =
  state channel incl. QueueState; workspace game = PotatoPile 11,748
  MeshParts/13,011 inst + PeelingMachines + crates + 26 prompts vs
  lobby queues/13 prompts) + potato-census-code-glm2.md (3,285 lines:
  network module RS.ModifiedPackages.Packet L48929-49452 — RemoteEvent
  is its CHILD (client WaitForChild L49283), 92 packet-id attrs, Fire
  appends u8-id stream, <=60Hz flush, FireServer(buffer[,
  Instances]) L49360/62 = only 2 fire sites; opcode table =
  Modules.Resources.Packets L44290-44422 (92 defs w/ type sigs);
  codec _Types L49565-52479; SlotPotatoes/PotatoSlots = client-side
  seed-derived buffers (PotatoPileShared L46508-46952), NOT wire;
  1,425 require sites/401 scripts; gameplay = hold-LMB pick
  (PotatoPick L24517/23), peel minigame (PeelingPeelRemoved L22443/56
  + PeelingSync 12.5Hz), prompts, ToolEquip, Sync handshake; Cmdr
  admin-gated excluded).
- Spot-verification agent: 6/6 PASS (packet table verbatim 92 defs;
  RemoteEvent resolution L49283/L49143; 92 attrs byte-identical
  game/lobby L8174-8265; the 2 FireServer sites; real call sites;
  PotatoPile 11,748 MeshParts game-only). Census docs = trustworthy.
- Intel msgs to glm4 (their RE is 80% pre-done — pointers + remaining
  semantic work list) + glm1 (build de-risk facts + one-code-path
  note). Committed + synced.
- Next: harness with deobf-backed module loader (real game module code
  runs in mock env via io.open+region-slice+loadstring) + world mocks
  (PotatoPile sample, machines, prompts, crates, lobby queues) +
  buffer shim (Lua 5.4 lacks Luau buffer lib — HARNESS_KIT shim rule).
