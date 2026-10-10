# Task Source Memory (persistent)

## Main source of game tasks

**GitHub repo: https://github.com/caotuanthanh147/Public**

User instruction (recorded 2026-09-25): *"next game, also use this as the main source of task, check for new files and download it https://github.com/caotuanthanh147/Public, save this to your memory"*
User instruction (recorded 2026-09-28): *"use the template in the zip file as your main template from now on, reread the glm guide everytime"*

## Workflow for every "next" / "next game" request

1. `git clone https://github.com/caotuanthanh147/Public /tmp/Public` (or `git pull` if cloned; `/tmp` is wiped on sandbox resets — re-clone, use the saved push token from the glm guide/worklog for auth) and compare the file list / commit log against what has already been processed (see Processed files below).
2. The NEWEST uploaded file (largest commit timestamp) is the next game task. Download it to `/home/z/my-project/upload/` and extract.
3. Run the standard pipeline: Rule 18 re-read (GLM_SCRIPTING_RULES.md + Yuri/Template.lua — re-sync the template from the zip if the zip contains a newer Template.lua) → study deobf + dump → verify every remote signature at client call sites → build `Yuri/<Game>/<Game>.lua` on the template → mock test suite all green → luac5.4 -p + template-diff → repack zip with the script inside → push to GitHub → worklog entry → UPDATE THIS TABLE. (luaparse tooling was removed with the website cleanup 2026-10-01; luac5.4 -p + the runtime mock harness cover validation.)
4. IM-gateway file attachments are UNRELIABLE (5 failed deliveries during the Superb saga). The GitHub repo is the authoritative delivery channel. If the user attaches a file that never arrives, remind them to push it to the repo.

## Processed files (do not reprocess)

| Repo file | Game | Task ID | Artifact |
|---|---|---|---|
| `1.zip` (commit f26d0f7) | Superb Upgrade Tree [UPDATE] | SUPERB-1 | `Yuri/Superb/Superb.lua` (71/71 checks) |
| `alliance.zip` (commit f817c68) | [⌛TODAY] Alliance Tower Defense! ⚔️ | ALLIANCE-1 | `Yuri/Alliance/Alliance.lua` (81/81 checks) |
| `alliance#.zip` (commit 2bd83f1) | Alliance TD — reference scripts (Slop TD complete port) | ALLIANCE-2 | `Yuri/Alliance/Alliance.lua` updated (107/107 checks) |
| `alliancenew.zip` (commit 8ab3465) | Alliance TD — user's macro-hook bug build | ALLIANCE-3 | Fixed IN THE ZIP: `upload/alliancenew.zip` (17/17 hook tests) |
| `allainceaaa.zip` (commit d350b97) | Alliance TD — next-game test log | ALLIANCE-4 | CLOSED — game abandoned; lessons → GLM rules §20 |
| `larp.zip` (commit eb53c46) | Larp Your Character! | LARP-1 | `Yuri/Larp/Larp.lua` (1349 lines, 71/71 checks) |
| `kickuma.zip` | Kick an Uma | KICKUMA-1/2 | `Yuri/KickUma/KickUma.lua` (AutoPlace replace-loop fixed) |
| `jj.zip` | A Bizarre Town (UPDATE 1.1) | BIZARRETOWN-1 | `Yuri/BizarreTown/BizarreTown.lua` (1634 lines; Skip Dialogue feature) |
| `dummy.zip` | (TD reference game) | DUMMY-1/2 | `Yuri/Dummy/Dummy.lua` (2448 lines; macro record/replay ported + race fixes) |
| `tycoon.zip` | Tycoon RNG: Refinery | REFINERY-1 | `Yuri/Refinery/Refinery.lua` |
| `veil.zip` | [🎉] The Veil | VEIL-1/2 | `Yuri/Veil/Veil.lua` (+ backup.zip registered as studyref #2) |
| `pop.zip` | Pop Bubbles! 🎯 | POP-1 | `Yuri/Pop/Pop.lua` |
| `seed.zip` | Steal A Seed! | SEED-1 | `Yuri/Seed/Seed.lua` |
| `zombies.zip` | [🧑🏻‍💻] Build and Kill Zombies | ZOMBIES-1 | `Yuri/Zombies/Zombies.lua` (Build tab per user genre note) |
| `slop.zip` | [AFK] Slop Tower Defense! 💔 | SLOP-1 | `Yuri/Slop/Slop.lua` (TD macro record/replay) |
| `larp.zip` (2nd upload, user edit inside) | Larp Your Character! — MinigameHits expansion | LARP-2 | `upload/larp.zip` Larp.lua covering all 35 characters (verified success calls) |
| `alliance#.zip` (fishing update) | Alliance TD — lobby fishing update | fishing-1 | `Yuri/Alliance/Alliance.lua` +569 lines fishing suite (AutoFish/AutoSell/AutoCraft/teleports) |
| `plantinc.zip` (commit d27741b; later deleted by user) | [UPD] Plant Incremental | PLANTINC-1/2 | `Yuri/PlantInc/PlantInc.lua` (2025 lines; NOTE: shipped with `--` comments = Rule 3 violation, left as-is since game closed) |
| `cafe.zip` (commit cc09905; later deleted by user) | Emma's Cafe — croissant cooking bug fix in user's own Cafe.lua build | CAFE-1 | `Yuri/Cafe/Cafe.lua` fixed + PUSHED commit 85319b8 (26/26 oven tests) |
| `genshin.zip` (commit f5f530c) | [🌟 UPD 3] Hoyoverse Gacha Simulator + NEW canonical Template.lua (853 lines) | GENSHIN-1 | `Yuri/Gacha/Gacha.lua` (1,648 lines, 37/37 checks; template re-synced; pushed back as commit ce4fa17) |
| `camera.zip` (commit e0c8e9e) | Cameraman Tower Defense (two-place: lobby + match) — Slop.lua complete ref + task "next game, it's a tower defense game, the ref is the complete version of slop.lua so read it" | CAMERA-1 | `Yuri/Camera/Camera.lua` (3,343 lines, 103/103 checks; pushed back as commit 5a0fe70) |
| `"[UPD 2] SCP Incremental.zip"` (IM upload 2026-10-01, NOT in repo) | [UPD 2] SCP Incremental | SCPINC-1 | `Yuri/SCPIncremental/SCPIncremental.lua` (1,691 lines, 100/100 checks; repacked zip in Yuri/SCPIncremental/; NOT pushed — token redacted) |
| `"[⭐UPD2] Tower Incremental.zip"` (commit 47d9709) | [⭐UPD2] Tower Incremental (StairClimb) — plain "next game" | TOWERINC-1 | `Yuri/TowerInc/TowerInc.lua` (1,553 lines, 95/95 checks; pushed back as commit 0a89b0d) |
| `[UPDATE] Shigaku.zip` (commit 71c4793) | [UPDATE] Shigaku (school-life RP + fist-combat sandbox; BridgeNet2 + ReplicaService) — plain "next game" + user multi-GLM single-game experiment ("I'll launch you with other glm to see how you guys work on one game") | SHIGAKU-1 | **v2 FINAL = Public 0c03f2b** (user order via glm3: glm1 final verdict + wrap): `work/lua/Shigaku.lua` 1,355 lines = AutoAttack (game's own Input actions, Knocked/Duo filterFn per deobf bind L4749) + AutoGym (Gym.Sync Start + universal minigame tap loop) + InfinitePosture (client-auth Posture.Sync) + AutoRoll (glm3 cluster). Gates: luac / lint 0 / validate head836-tail18-0comments; originals MD5-identical. Harnesses on DELIVERED bytes: glm1 canonical 54/0 + glm2 32/0 + glm3 fork 42/42. Round: SH1-SH5 done (glm2 analysis+build+deliveries, glm3 cluster+post-merge fixes+harness fix, glm1 harness+audit+verdict, identity mixup corrected); 3 findings fixed across 2 delivery iterations |
| `[GLITCH WORLD + SCOTT] FNAF World Multiplayer/` (commit 8744ca1) | [GLITCH WORLD + SCOTT] FNAF World Multiplayer — plain "next game" (Impossible Animals uploaded 29735e5 + deleted 8744ca1 same day, never claimed, closed unprocessed) | FW1 | `Public 18b39a0` (FnafWorld.lua in game folder, MD5 47cd6e8d; harness 43/43; analysis work/lua/fnafworld-analysis.md) |
| `snack.zip` (commit d139834) | SNACK Defense! 🍉 [TD] (two-place: lobby + in-round, tdref/Slop.lua + NEW canonical Template.lua 888 lines) — plain "next game" + Rule 17 violation feedback (TowerInc RunLoop/inline nearest) + directory cleanup order | SNACK-1 | `Yuri/Snack/Snack.lua` (2,833 lines, 98/98 checks Round 51/Lobby 42/AFK 5; template re-synced with TweenTo + SafeInvoke skip param; pushed back as commit e91ba44) |
| `MATI.zip` (commit 5521079-era upload; delivered as repacked `MATI.zip` c26a275, re-delivered c2cf4a8) | Melt All The Ice! (2 places: lobby + Level 1 FrozenHouse) | MATI-1/T9/T10 | `Yuri/MATI/MATI.lua` (harness 27+14 checks after T10; work/lua/mati-analysis.md wire table; products=ROBUX excluded). T10 2026-10-02: user-flagged invented "Status" label removed + re-delivered — the reference set is the spec, no-reference games get standard autofarm ONLY. |

| `[🌋] Ride A Pet/` (folder, Public 6aaefd6) | [🌋] Ride A Pet (pet game) | ST8 | `[🌋] Ride A Pet/[🌋] Ride A Pet.lua` (Auto Hatch via `Remotes.Game.Hatch:FireServer({EggKey})`; eggs via CollectionService:GetTagged("Egg"); standard autofarm no reference; harness 9/9; delivered Public da10db7) |

| `Steal A Car/` (folder, Public 0acfce8) | Steal A Car (no reference) | SAC1 | `Steal A Car/Steal A Car.lua` (5 toggles: AutoSwing/AutoEquip/AutoPlace/AutoSell/AutoJoin via CombatRequest/SellCars/RaceRequest; §3 both halves; harness 15/15; delivered Public by glm4) |

Earlier IM-uploaded zips (pre-repo era, no longer in any repo — listed for completeness): golf.zip, piggy.zip, forest.zip, water.zip, hole.zip, timber.zip, aura.zip, file.zip, golem.zip, leaf.zip, aac.zip, ascension.zip, magnet.zip, dice.zip, farmer.zip, needlehaysack.zip, dummy.zip, sup.zip/1.zip (Superb).

| `potato/` (commit 2481993, folder mode) | Peel THE Potato (two-place: game/ reserved server + lobby/ queue hub; deobfs byte-identical) — plain "next game" | POT1 | `work/lua/Potato.lua` (15 toggles, harness 45/45; delivered Public 4fcbc2d into BOTH subfolders; Packet-mux transport, analysis at work/lua/potato-analysis.md) |

## Repo layout notes

- Game files are plain zips at repo root named `<something>.zip` containing `<name>/[Deobf].lua` + `game_dump.txt` (sometimes split into `lobby/` + `game/` subfolders for two-place games). Newer zips may also contain `Template.lua` — that is the user's CURRENT canonical template; always re-sync `Yuri/Template.lua` from it (Rule 14).
- The repo also contains unrelated personal files (cobalt config, `lesbian/` folder = executor workspace) — ignore those.
- The user DELETES old game zips when moving on (plantinc.zip, cafe.zip, larp.zip, alliance zips all deleted) — a missing file is not an error; the table above is the record.
- Commit history: check `git log --format="%h %ci %s" --name-only` for upload order.
- Push token for delivery commits: saved in the glm guide (`/home/z/my-project/worklog.md`, cafe session entry).

## Open task

- FW1 delivered (FNAF World Multiplayer, Public 18b39a0, harness 43/43). glm4 FW1-H deobf-backed cross-validation pending. Awaiting user feedback/testing or next game upload.
- (previous) POT1/PL1 complete — see Processed files table.

- SCPINC-1 complete (Yuri/SCPIncremental/SCPIncremental.lua 100/100 checks). NOT pushed to GitHub: the push token in the oldglm.zip worklog is [REDACTED:github_token] — user must take files from Yuri/SCPIncremental/ or re-supply a token / push themselves.
- Repo also holds error/error.txt (user's Snack macro test: "Recording [0]" — Alliance §20-class hook capture failure) + tdref.zip (reference scripts incl. usethisfileSnack.lua 2026-10-01 18:52). Snack is closed (zip deleted) — do not touch unless the user re-opens it.
- MATI still OPEN (zip at Public root as of 2026-10-02).

- TowerInc Rule 17 violations (RunLoop instead of SafeLoop, 3x inline nearest instead of GetNearest, missing Shared.Labels init) were NOTED by the user but explicitly NOT fixed ("ignore that game, only fix when I told you to fix it"). Do not touch TowerInc unless the user asks.

## Closed tasks

- **ALLIANCE-4** (macro hook): game abandoned by user. Do not resume Alliance work unless explicitly re-opened. Post-mortem: GLM_SCRIPTING_RULES.md §20.
- **LARP-1/2**: complete (all 35 characters covered).
- **CAFE-1**: croissant cooking fix pushed (commit 85319b8). Game closed.
- All games deleted from the repo by the user are closed; do not resume unless explicitly re-opened (Rule 16).

| `[🌧️] Drop a Fruit/` (folder, Public 261a0b6→8ed03f0) | [🌧️] Drop a Fruit (fruit tycoon + gacha rolls) | DF1 | `[🌧️] Drop a Fruit/[🌧️] Drop a Fruit.lua` (11 toggles + 3 filters; two-layer networking: remo containers `Remotes.ns.event:fire()` + ReplicaService actions `replica:FireServer(action)` routed by Id via Replica_ReplicaSignal; work/lua/dropafruit-analysis.md + dropafruit_harness.lua 58/58). Delivered Public 8ed03f0. |
| `plunder/` (folder, Public d119454→4b0000a) | Plunder [UPD] + Zone Zero (two-place extraction heist, Chickynoid, one engine) | PL1 | `plunder/Plunder [UPD]/Plunder [UPD].lua` + `plunder/Zone Zero/Zone Zero.lua` (both MD5 fad6b893; 5 toggles — AutoPickup/AutoSearch/AutoExtract/AutoRoll/AutoRequeue; TEvent-over-Postie wire layer via the game's own modules: Registry/ContainerState/Value/PickupPoint/Gloves; work/lua/plunder-analysis.md + plunder_harness.lua 25/25; user updated Template.lua 1df3865 → 919-line head, AddSliderToggle table-form only, AutoJump built-in). Delivered Public 4b0000a. |

| 7 Days Cat-Sitting (cat/, Public 261c46e -> glm1 1d5c1b0) | Two-place anomaly-survival chore game (GAME house + LOBBY shop + videotranscript.txt). 26 remotes, 48 prompts, workspace-attr oracle. glm1 CS1: SevenDaysCatSitting.lua (7 features, inline resolution per user directive, 56/56 x3) DELIVERED both folders. main-agent CS1-B parallel: CatSitting.lua (7 features, 43/43+10/10) DELIVERED d82c55a. FW1 both-land — user picks. Analyses: catsitting-analysis.md + catsitting-analysis-b.md. |
