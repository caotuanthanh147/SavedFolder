# glm4 status

**Updated**: 2026-10-04 (session 2 — Steal A Car delivered, took over stale SAC1)

**Doing**: Steal A Car DELIVERED (Public Steal A Car.lua in folder). Took over
SAC1 from glm3 (claimed 00:57Z, no follow-up in ~10min — no analysis/
delivery/status; reliability issue glm3 logged; msg'd glm3 offering take/
split, no response; §1 end-to-end ownership: a claim with no follow-up isn't
a stake). If glm3 surfaces with a parallel build, merge Shigaku-style.

**Build**: 5 toggles (§3 both halves — all Rule-11-KEEP remotes wired):
- AutoSwing: CombatRequest:FireServer("Swing") (L8076, bat cooldown)
- AutoEquip: CombatRequest:FireServer("Equip","Bat") (L8146)
- AutoPlace: CombatRequest:FireServer("Place", HRP.Position) (L8048)
- AutoSell: GetSellInventory:InvokeServer() → SellCars:InvokeServer(inv) (L3355/3393)
- AutoJoin: RaceRequest:FireServer("Join") (L8828)
EXCLUDED: AdminCrateAction (admin-only), BuyTrailRobux + CaughtSpeedPurchase
(ROBUX), SetSlowMode (chat).

**Gates ALL green**: luac OK, lua_lint 0 err (--from 837, 21 W6 template-region),
validate 0 comments / 109-line game section (head 836 + tail 18 verbatim),
harness 15/15 (work/lua/stealacar_harness.lua — real-load io.open+loadstring+
task.spawn, pcall interceptor, colon-safe service mocks, §22-7 respawn check).

**Applied glm1 ST-QA1 + ST11/12/13 intel**: TB_Tabs.Autofarm.T1 (canonical,
not TB.Main.Left.Autofarm.T1), §22-7 loops (while Toggles.X.Value do pcall(step)
task.wait end), real-load harness (not re-implementation), pcall interceptor
(silent-degradation detector), colon-safe service mocks (function(_,...) —
the GetTagged self-bug class), no template-banned features (§14.2), no
symmetric encode/decode, no AutoReexec/QueueOnTeleportExec, harness_lib
copied fresh (upgraded version). Analysis at work/lua/stealacar-analysis.md.

**Stuck on**: nothing — delivered, gates green.

**Files changed (mine, this session)**:
- `~/Public/Steal A Car/Steal A Car.lua` (DELIVERED)
- `work/lua/StealACar.lua` (clean-name source), `work/lua/stealacar_harness.lua` (15 checks),
  `work/lua/stealacar-analysis.md` (wire table)
- `TASKS.md` (SAC1 glm4 done), `work/lua/TASK_SOURCE.md` (Steal A Car row),
  `status/glm4.md`, `logs/glm4.md`, `msgs/glm3/`+`msgs/glm1/` (I'm-back + stale-claim msgs).

**Next**: standing by. The other open game (Drop a Fruit, DF1) is glm1's.
If glm3 surfaces re Steal A Car, coordinate/merge. If the user uploads a new
game, watch_public.sh will catch it. Applied the §3 two-halves rule from the
start this time (5 toggles, not 1) — the "too little features" lesson.
