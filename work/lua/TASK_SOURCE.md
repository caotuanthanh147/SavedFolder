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
| `snack.zip` (commit d139834) | SNACK Defense! 🍉 [TD] (two-place: lobby + in-round, tdref/Slop.lua + NEW canonical Template.lua 888 lines) — plain "next game" + Rule 17 violation feedback (TowerInc RunLoop/inline nearest) + directory cleanup order | SNACK-1 | `Yuri/Snack/Snack.lua` (2,833 lines, 98/98 checks Round 51/Lobby 42/AFK 5; template re-synced with TweenTo + SafeInvoke skip param; pushed back as commit e91ba44) |

Earlier IM-uploaded zips (pre-repo era, no longer in any repo — listed for completeness): golf.zip, piggy.zip, forest.zip, water.zip, hole.zip, timber.zip, aura.zip, file.zip, golem.zip, leaf.zip, aac.zip, ascension.zip, magnet.zip, dice.zip, farmer.zip, needlehaysack.zip, dummy.zip, sup.zip/1.zip (Superb).

## Repo layout notes

- Game files are plain zips at repo root named `<something>.zip` containing `<name>/[Deobf].lua` + `game_dump.txt` (sometimes split into `lobby/` + `game/` subfolders for two-place games). Newer zips may also contain `Template.lua` — that is the user's CURRENT canonical template; always re-sync `Yuri/Template.lua` from it (Rule 14).
- The repo also contains unrelated personal files (cobalt config, `lesbian/` folder = executor workspace) — ignore those.
- The user DELETES old game zips when moving on (plantinc.zip, cafe.zip, larp.zip, alliance zips all deleted) — a missing file is not an error; the table above is the record.
- Commit history: check `git log --format="%h %ci %s" --name-only` for upload order.
- Push token for delivery commits: saved in the glm guide (`/home/z/my-project/worklog.md`, cafe session entry).

## Open task

- SCPINC-1 complete (Yuri/SCPIncremental/SCPIncremental.lua 100/100 checks). NOT pushed to GitHub: the push token in the oldglm.zip worklog is [REDACTED:github_token] — user must take files from Yuri/SCPIncremental/ or re-supply a token / push themselves.
- Repo also holds error/error.txt (user's Snack macro test: "Recording [0]" — Alliance §20-class hook capture failure) + tdref.zip (reference scripts incl. usethisfileSnack.lua 2026-10-01 18:52). Snack is closed (zip deleted) — do not touch unless the user re-opens it.
| `MATI.zip` (commit 5521079-era upload; delivered as repacked `MATI.zip` c26a275) | Melt All The Ice! (2 places: lobby + Level 1 FrozenHouse) | MATI-1/T9 | `Yuri/MATI/MATI.lua` (harness 28+14 checks; work/lua/mati-analysis.md wire table; products=ROBUX excluded) |

- TowerInc Rule 17 violations (RunLoop instead of SafeLoop, 3x inline nearest instead of GetNearest, missing Shared.Labels init) were NOTED by the user but explicitly NOT fixed ("ignore that game, only fix when I told you to fix it"). Do not touch TowerInc unless the user asks.

## Closed tasks

- **ALLIANCE-4** (macro hook): game abandoned by user. Do not resume Alliance work unless explicitly re-opened. Post-mortem: GLM_SCRIPTING_RULES.md §20.
- **LARP-1/2**: complete (all 35 characters covered).
- **CAFE-1**: croissant cooking fix pushed (commit 85319b8). Game closed.
- All games deleted from the repo by the user are closed; do not resume unless explicitly re-opened (Rule 16).
