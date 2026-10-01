# glm1 log

## 2026-10-01 — bootstrap
- I am glm1, the first session. Bootstrapped this repo: TASKS.md, shared/{PROMPT.md,lessons.md,changelog.md}, logs/, status/, msgs/, work/.
- Main mission: fix user's usethisfileSnack.lua (2,945 lines, in tdref.zip from github.com/caotuanthanh147/Public). Two bugs: (a) macro recording captures 0 actions on Cobalt/cloneref executor — root cause: hook rawequal(self, Remotes.X) never matches cloned refs; fix = port Alliance.lua OrigRemotes pattern. (b) AutoQueue looks for the wrong queuing part.
- Reference files: Alliance.lua (cloneref fix, verified by user), Slop.lua (TD structure canon), error/error.txt (failure evidence).
- Local deliverables also maintained at /home/z/my-project/Yuri/Snack/Snack.lua (TPTo fix already validated by 153-test mock harness).

## 2026-10-01 13:15-14:00 UTC — Snack fix round (T2) + glm2 coordination
- Reread GLM_SCRIPTING_RULES.md fully (discipline), pulled Public: user pushed tdref.zip (Alliance.lua, Slop.lua, usethisfileSnack.lua) + error/error.txt (18:55 run: "hook installed" → "Recording [0]").
- Recovered from context loss: my un-pushed local edits to usethisfileSnack.lua already contained the OrigRemotes port (from Alliance.lua 1231-1261/1450-1548) + wire-format fix (payload=nargs[2]) + AutoQueue rework. Verified EVERY edit against game sources this round:
  - EasyEvents wrapper (lobby deobf 93886): `SendEvent/InvokeServer(name, ...)` → per-name remotes, only varargs on the wire → payload at nargs[2] CONFIRMED (glm2 independently diagnosed the same).
  - Payload shapes from round deobf call sites (4508-4532, 6787, 6846, 6863): PlaceTower{towerKey,slotIndex,x,y,z,rotationY}, Upgrade{tower}, Sell{tower}, SetTowerTarget{tower,mode} CONFIRMED.
  - Join pads: game's own nearestOpenPad (73300-73346): GetTagged("GameJoinPad"), RoundType nil/"Normal", HostUserId==0; dump: Workspace.Functional.Join Pads.Regular Mode.GameJoinPad.Walls.Part+TouchInterest. Old target Lobby.Functional.Zones = generic decoration zones — user's complaint confirmed.
  - Host flow: onPlayClicked → RequestPlay(map,level) → StartButton → requestStartGame → RequestStartGame (50163, 50515, 50192-50193).
- Fixed Upgrade LVL double-count: capture-after-original reads server-bumped level, so LVL = post-read WITHOUT +1 (LVL must equal cfg.Upgrades tier index + replay skip level).
- Rebuilt sandbox tooling (fresh /tmp): compiled lua 5.4.6 from source (no apt root); rebuilt /tmp/snack_debug.lua (full script loaded against mock world).
- Extended harness: cloneref simulation (script RS = proxy, remotes = clones; game-side calls = originals → capture only passes via OrigRemotes), GameJoinPad mock world (open/busy/endless pads), RequestStartGame remote, FindFirstChildOfClass mock (was missing — GetCharacter silently error'd for sessions), real-wire-format test calls, fresh-world-per-phase resets, 4 new assertions.
- Result: Round 83/0, Lobby 52/0, Afk 22/0 = 157/157. Pushed Public 7cd68b0 (repacked tdref.zip). Token: display-redacted in worklog but live in file (glm2's lesson confirmed).
- Team: glm2 alive (delivered SCPINC 055dd8b, diagnosed same nargs bug, waited for green light). Rebased my bootstrap onto theirs (kept their TASKS/lessons structure, merged mine in). Replied msgs/glm2/: green light existed; TWO independent 0-capture bugs (cloneref + wire); division of labor (they keep T3 watch, I take T5 guide).
- Next: T5 guide sections (§20.6 wire-level indexing + cloneref OrigRemotes), local worklog update, mirror harness+script copies.

## 2026-10-01 ~16:05 UTC — session 3 (T6: team infrastructure)

User order (this prompt only): "improve the savedfolder to make your scripting
process faster and smoother — guide for a new glm instance, new shared tool,
search tools on the internet, etc."

- Read up: worklog tail (Snack T2 delivered 7cd68b0, 157/157), SavedFolder at
  05b89d8, glm2 status (T1/T2 done, owns T3 watch + T4).
- Token re-verified live for SavedFolder pushes (grep count, never echoed).
- Built + TESTED on real files (per-tool results in status/glm1.md):
  bootstrap.sh (+lua54.tar.gz 228KB, from the my-project .debs — statically
  linked, portable), deobf_search.py (validated: PlaceTower payload + block
  chain L4509; GameJoinPad L62220; attr/tag censuses), repack_zip.py (real
  tdref.zip replace+add roundtrip [VERIFIED]; found+fixed zipfile ZipInfo
  mutation bug — writestr corrupts source infolist objects, pass copy.copy),
  lua_lint.py (deliberate-bug file caught; Snack template-region Luau usage
  correctly scoped via --from/--to), watch_public.sh (ZIP+/ZIP- simulated).
- Docs: ONBOARDING.md, SEARCH.md (sources web-verified via z-ai web_search
  today: create.roblox.com/docs, luau.org/syntax, lua.org/manual/5.4,
  devforum, dawid-scripts/Fluent), HARNESS_KIT.md; snack_harness.lua committed.
- PROMPT.md pointers (still <60 lines); guide §25 Tooling + sync (536 lines);
  lessons +3; changelog; TASKS T6 done, T7 dogfood opened for glm2; msg to glm2.
- Moved clones to persistent /home/z/{SavedFolder,Public} (survives /tmp wipes;
  poll.sh default path).

Next: idle/watch; glm2 dogfoods (T7); next game zip → standard pipeline (guide
Rule 18 + new §25 tooling front door).
