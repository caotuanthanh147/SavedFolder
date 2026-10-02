# glm2 status

**Updated**: 2026-10-02 (session 5 — ST-QA1 fix round: ST5/ST6/ST7 re-delivered)

**Doing**: Standing by for glm1's re-QA pass + new games/user orders.

**Progress (session 5 — glm1's ST-QA1 audit fixes)**:
- Read 3 msgs in msgs/glm2/: glm1's audit (all 3 games BROKEN AT LOAD — T1 nil) + glm5 x2 (expansion verified at 5fb30cb, Auto Roll wired, thread closed).
- Re-delivered all 3 games at Public **3a54453** (push ls-remote verified):
  - **T1 load bug fixed**: 16x `TB.Main.Left.Autofarm.T1` → `TB_Tabs.Autofarm.T1`; dropped manual `Toggles.X =` (lib registers by Idx).
  - **§22-7 loops**: `while Toggles.X.Value do pcall(step); notyuri; task.wait(x) end` — work-then-wait, per-step pcall.
  - **L819 boundary**: game section after the antiAFK block; duplicated antiAFK copies deleted. validate: head 819 verbatim / tail 18 / 0 comments.
  - **ST6 wire-semantics correction** (beyond glm1's flags): requestHit takes (swordUid, enemyUid, swingCenter) — old call had enemy name in the sword slot. Now: sword uid via PlayerDataClient:get().equipped, enemy uid via CombatClient:getEnemyModels() keys, center = HRP pos. GetDescendants scan removed (enemies = Parts in workspace.CombatVisuals per makeEnemyModel L32959).
- **Harnesses rebuilt to load the real script**: io.open+loadstring+spawn, assert no ERROR notify + Library.Toggles registration + wire counts/payload tuples + toggle-off stop. ST6 16/16, ST5 11/11, ST7 11/11 — verified against the delivered Public bytes.
- Replied to glm1 (msgs/glm1/glm2-20261002T061459Z.md) with fix list + their qa_load mock gaps (missing Roll/Rebirth folders etc. — my harnesses are game-accurate for their re-pass).

**Stuck on**: nothing.

**Files changed (mine)**: work/lua/{SwordRNGX.lua, OpenSeaForAnimals.lua, EightBallDuels.lua} (rebuilt: head 819 + section + tail 72), work/lua/{swordrngx,opensea,eightball}_harness.lua (real-load versions), work/lua/{swordrngx,opensea,eightball}_section.lua (build inputs), TASKS.md (rows done), status/glm2.md, logs/glm2.md, msgs/glm1/glm2-20261002T061459Z.md.

**Next**: await glm1 re-QA; poll Public for new games; ST3 (Fishing Master) still blocked on user decision per glm1's row.
