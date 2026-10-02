# glm4 status

**Updated**: 2026-10-02 (session 1 — ST8 v2 delivered, §22-7 + glm1 guidance)

**Doing**: ST8 ([🌋] Ride A Pet) DELIVERED. v1 = Public da10db7 (Auto Hatch,
1 toggle). v2 = §22-7 loop refactor (`while Toggles.AutoHatch.Value do
pcall(step) task.wait(0.5) end`) + script synced to work/lua/RideAPet.lua
(glm1 ST-QA1 guidance points 3+4). Gates v2 ALL green: luac OK, lint 0 err,
validate 0 comments / 78-line game section, harness 9/9 (work/lua/rideapet_harness.lua
incl. §22-7 respawn check).

**Wire verified** (Rule 2): `Remotes.Game.Hatch:FireServer({ EggKey = egg:GetAttribute("EggKey") })`
at deobf call site L10832; path L10815 (`RS:WaitForChild("Remotes"):WaitForChild("Game"):WaitForChild("Hatch")`);
EggKey attribute set at L41120; eggs via `CollectionService:GetTagged("Egg")`.

**glm1 ST-QA1 audit context**: glm2's ST5/ST6/ST7 all broken at load
(`TB.Main.Left.Autofarm.T1` nil). My ST8 used `TB_Tabs.Autofarm.T1` (canonical)
from the start — the harness caught the alt form pre-delivery. glm1's 4-point
guidance applied (1+2 already, 3+4 in v2). Replied to glm1 (msgs/glm1/) +
asked for §3 two-halves judgment on ST8 one-off remotes (EggPickup/
ClaimEventReward — hold for explicit user order or expand?).

**Stuck on**: nothing — v2 ready to push.

**Files changed (mine, this session)**:
- `~/Public/[🌋] Ride A Pet/[🌋] Ride A Pet.lua` (v1 da10db7 + v2 pending)
- `work/lua/RideAPet.lua` (clean-name copy, glm1 pt 4)
- `work/lua/rideapet_harness.lua` (9 checks, §22-7, reads work/lua/RideAPet.lua)
- `TASKS.md` (ST8 done v2), `status/glm4.md`, `logs/glm4.md`, `work/lua/TASK_SOURCE.md`
  (ST8 row), `msgs/glm1/glm4-*.md` (reply), `msgs/glm4/` (glm1 msg handled + deleted)

**Next**: push v2 (Public + SavedFolder sync). Then: standing by for next game
OR glm1's §3 judgment on ST8 one-off remotes OR explicit user "more features"
order. The stress round is nearly complete (ST1/ST2/ST4/ST6-8/ST10 done;
ST3 blocked fishing-minigame; ST5/ST6/ST7 being fixed by glm1; ST9 glm3 doing).
