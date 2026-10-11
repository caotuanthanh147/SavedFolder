# [LABYRINTH] Build a Dungeon — Analysis (BAD1)

Public 3cc38ff, zip-only. Deobf 81,918 lines + dump 429,120 (client-visible only — NO
server source in dump; wire validation = client call sites per Rule 2). No Template.lua
in zip → canonical 945 stands.

## Game structure

Single place, two modes: `workspace:GetAttribute("LabyrinthMode")` —
- **Home mode** (default): build-a-dungeon tycoon. 6 plots (`workspace.Plots.Plot1..6`,
  attribute `PlotIndex`, StringValue `State` = full layout JSON). Waves of adventurers
  raid your dungeon; your placed units/traps fight; you melee with your weapon
  (Backpack "Dungeon Blade" / Hammer for build mode). Roll stands per plot
  (`workspace.Map.Rollers.PlotN_Buildings/Monsters`).
- **Labyrinth mode**: squad raid of a generated maze (LabGen/LabMaze/ArenaGen), queued
  via LabQ, fought via Lab remote (dash/skill), melee via Action "attack" with the
  target's `LabMonster` attr value.

Client modules: BADClient.{State, Cam, UI, Build, Battle, Floors, Roll, RollPadUI,
LayoutUI, LabyrinthClient, ...} + ReplicatedStorage.BAD.{Config, GridUtil, WeaponKit,
RollOdds, Labyrinth.LabConfig, ...}.

## State model (all client-readable, server-replicated)

- Player attrs: `PlotIndex`, `Gold`, `DarkSouls` (souls), `Wave`, `Best`, `Inv` (JSON
  `{itemId: count}` buildings), `Mons` (JSON `{unitId: count}`), `Pity` (JSON),
  `Hotbar`, `Luck`, `Skills` (JSON owned tree nodes), `Weapon`, `Weapons` (JSON),
  `Units`, `Pop`, `MaxPop`, `FriendBoost`, `Auto`, `Speed`, `AutoUnlocked`,
  `SpeedUnlocked`, `Floors`, `Tutorial`, `Seen`, `MutLuck`.
- Plot entry (State module): `{index, cf, folder, data}` — `data` = decoded State
  StringValue JSON: `{uxp, ustar, owner, wave, floors = [{tiles = {["c,r"] = floorId},
  objs = {["c,r"] = {id, rot, lvl}}, trot = {["c,r"] = rot}, w = widthLevel}], ulvl,
  skills, best, name}`. Plots' `WaveActive` attribute = wave in progress.
- Grid: `GridUtil.key(c,r) = "c,r"`, `cellLocal`, `inBounds(floor, c, r)` per
  `Config.WidthLevels[floor.w]` (level 1: cols 5-11 rows 10 ... level 6: cols 0-16
  rows 16), `DIRS`, `sideWall`, `buildFullPath` (entry→Crystal connectivity),
  `canPlaceObject`, `isFixedCell`. `Config`: CELL=6 COLS=17 ROWS=16 ENTRY_COL=8,
  MAX_FLOORS=3, WidthLevels costs {0,400,900,1800,3500,6000} gold + wave gates
  {0,2,4,6,9,12}, FloorUnlocks {2: 8000@wave8, 3: 30000@wave15}, GAP_COST=7.
- Items (`Config.Items`): 15 `kind=floor` rooms/corridors (WoodFloor open, corridors
  with `edges` walls, CrystalHall etc.), 3 `kind=block` walls, 9 `kind=trap`,
  3 `kind=utility`, 2 `kind=special` (Crystal top-floor-only + Stairs Up),
  19+ `kind=monster` units (cat "Monsters", `mon` stats, `pop`, UnitPriceById).
  Floors live in `floor.tiles`, everything else in `floor.objs` (same cell as their
  floor tile). Traps/monsters sit ON floor tiles (dump-verified: objs and tiles share
  keys). Monsters count from `Mons()`, buildings from `Inv()` (UI.countOf).

## Wire table (verified at call sites)

| Remote | Class | Wire | Call site | Purpose |
|---|---|---|---|---|
| Action | RemoteEvent | `:FireServer("startWave")` | 523 | start wave at own plot (HUD button, NOT skill-gated — cb.startWave fires whenever waveActive false) |
| Action | RemoteEvent | `:FireServer("stopWave")` | 534 | stop active wave |
| Action | RemoteEvent | `:FireServer("auto")` | 646 | toggle AUTO next-wave (skill/gamepass AutoUnlocked — server gate unknown, probe) |
| Action | RemoteEvent | `:FireServer("speed")` | 650 | toggle 2x wave speed (SpeedUnlocked — probe) |
| Action | RemoteEvent | `:FireServer("visit", plotIndex)` | 573 | visit another plot |
| Action | RemoteEvent | `:FireServer("watch", plotIndex or nil)` | 490/551/601/619/656/678/1128 | overview/spectate mode |
| Action | RemoteEvent | `:FireServer("home")` | 642 | return home |
| Action | RemoteEvent | `:FireServer("shop")` | 678 | open forge |
| Action | RemoteEvent | `:FireServer("attack", labMonsterValue or nil)` | 81146 | weapon swing (arg = target LabMonster attr in Lab mode, nil at home); client cd per WeaponStyle {dagger .38 katana .45 staff .65 halberd .66 great .7 scythe .7 bow .8} |
| Action | RemoteEvent | `:FireServer("skipOnboarding"/"onboarding*")` | 25305+ | onboarding telemetry — REMOVE |
| Build | RemoteFunction | `:InvokeServer({action="place", id, f, c, r, rot})` | 16206 | place item (server routes by kind → tiles/objs) |
| Build | RemoteFunction | `:InvokeServer({action="move", f, c, r, tc, tr})` | 16161 | move obj to new cell |
| Build | RemoteFunction | `:InvokeServer({action="remove", f, c, r})` | 16185 | pick up |
| Build | RemoteFunction | `:InvokeServer({action="rotate", f, c, r})` | 16360 | rotate obj |
| Build | RemoteFunction | `:InvokeServer({action="upgrade", f, c, r})` | 16369 | upgrade obj (lvl) |
| Build | RemoteFunction | `:InvokeServer({action="expand", f})` | 16423 | buy next WidthLevel (gold+wave gated) |
| Build | RemoteFunction | `:InvokeServer({action="unlockFloor"})` | 16427 | unlock floor 2/3 (gold+wave) |
| Build | RemoteFunction | `:InvokeServer({action="hotbar", slots})` | 16432 | save hotbar |
| Build | RemoteFunction | `:InvokeServer({action="skill", id})` | 6471/11826/14713 | buy skill-tree node with souls |
| Build | RemoteFunction | `:InvokeServer({action="weapon", id})` | 7743 | weapon action (equip) |
| Build | RemoteFunction | `:InvokeServer({action="unitStar"/"unitSell"/"unitSellAll"/"unitLevel", id})` | 8460-9408 | unit management |
| Build | RemoteFunction | `:InvokeServer({action="clearAll"})` | 13553 | wipe own dungeon (confirm flow) |
| RollControls | RemoteFunction | `:InvokeServer("get", stand)` | 31970 | fetch stand settings `{stopAt, mut, pity, skin, always, protect, category, mode, styles, pieces, active}` |
| RollControls | RemoteFunction | `:InvokeServer("settings", stand, settingsTable)` | 31734 | save auto-roll filter; fields `{rarity, mut, pity, skin, always, protect, category, mode, styles, pieces}` (defaults L31133: rarity "Legendary" mut/pity/skin "Off" always "Divine" protect "Mythic" category "All"; mode "Rarity") |
| RollControls | RemoteFunction | `:InvokeServer("start", stand)` / `("stop", stand)` | 31737/31732 | start/stop native auto-roll; stand = "Buildings"/"Monsters" |
| Roll | RemoteEvent | `:FireServer("confirmRoll", id)` | 19955 | keep a confirmed (protect-class) roll |
| Shop | RemoteFunction | `:InvokeServer(action, ...): "daily" "spin" "code" "pass" "meta" "" "title" "pquest" "style" "offline" "use" "revealAck" "revealReady" "indexClaim" "indexClaimAll"` | 26346-43946 | one-shot UI actions — REMOVE (in-game UI 2-clicks), "pass" = robux REMOVE |
| DungeonLayouts | RemoteFunction | `:InvokeServer({action, slot, ...})`: list/save/load/preview/rename/unlock | 36857-37550 | game-native dungeon save slots — UI duplicate REMOVE |
| LabQ | RemoteEvent | `:FireServer("quick"/"solo", {sel = {map, diff}})` | 60620-60624 | queue labyrinth raid (map = "labyrinth", diff = novice/adept/veteran/nightmare/abyssal) |
| LabQ | RemoteEvent | `:FireServer("create", {max, private, sel})`, "start"/"leave"/"unquick"/"join"/"squad"/"kick"/"select"/"close"/"open" | 60628-62071 | squad management |
| LabQ | RemoteEvent | `:FireServer("raidbuy", nodeId)` | 53094 | raid tree upgrade buy |
| LabQ | RemoteEvent | `:FireServer("setCheckpoint", name)` | 53874 | lab checkpoint |
| Lab | RemoteEvent | `:FireServer("hello")` | 51091 | subscribe (client does this itself on init) |
| Lab | RemoteEvent | `:FireServer("leave")` / `("again")` | 47634/47639 | exit/retry raid |
| Lab | RemoteEvent | `:FireServer("dash")` | 50558 | dash |
| Lab | RemoteEvent | `:FireServer("skill", skillId, targetPos)` | 50904 | lab skill (client-computed aim position!) |
| Notify | RemoteEvent | OnClientEvent("rollPad"/"autoRollState"/"openLayouts"/...) | 14516+ | server→client toasts/events |
| Wave | RemoteEvent | OnClientEvent packets | 19038 | server→client wave sim drive |
| Admin/AdminAnnounce/ChatAnnounce/Engagement/ExclusiveWeapon/GroupRewardsRF | — | — | — | admin (REMOVE), announcements (s→c), engagement telemetry (REMOVE), robux shop (REMOVE), group reward claim (UI duplicate REMOVE) |

Response shape of Build/RollControls invokes: `{ok, msg?, silent?}` (Toast on msg, gold/red
by ok) — verified in the game's own request() wrappers (3518, 15355, 30980).

## Economy

- WaveReward(wave) = wave*22+60 gold; WaveSouls(wave) = floor(wave/2)+1.
- Roll stands: Buildings roll costs gold (BuildPrice by rarity: Common 60 ... Secret
  25000), Monsters roll costs souls (UnitPrice by rarity: Common 3 ... Divine 100000).
  cd 0.9 native auto-roll. Pity: Legendary@80 Mythic@160 Secret@300 Divine@2000.
- Upgrades: obj `UpgradeCost(item, lvl) = floor(item.value * 0.9 * lvl)`; unit
  `UnitLevelCost(unit, lvl) = max(1, floor(price * (lvl*0.9+0.8)))` souls;
  UNIT_MAX_LEVEL 10, UNIT_MAX_STARS 5, STAR_COPIES 3.
- Skills: spine ladder 300/1200/4000/12000/35000/90000 souls (Auto@350 fixed,
  Speed node too), ~60 branch nodes, parent-gated, cost in `Config.Skills` entries.
- WidthLevels: expand gold costs 400..6000 + wave gates 2..12. FloorUnlocks 2/3.

## Rule 11 KEEP/REMOVE

KEEP (automation/exploit value):
- AutoWave (startWave loop — the core grind; native AUTO needs a 350-soul skill or
  gamepass, our loop is free)
- AutoRoll Buildings + Monsters with stopAt rarity filter (drives the game's own
  native auto-roll via RollControls settings+start; TP to own stand first)
- AutoBuild (place owned floors serpentine path entry→crystal, traps on path, monsters
  on path, pop-gated — the build-a core; Zombies genre precedent)
- CopyBase (read ANY plot's State layout JSON → place same layout from own inventory —
  the copy-base genre vector; all layouts replicate to every client)
- AutoUpgrade (upgrade placed objs cheapest-first while currency allows)
- AutoExpand (expand width levels + unlockFloor when affordable+wave-gated)
- AutoSkill (buy affordable skill nodes parent-first, souls)
- AutoAttack (melee adventurers during waves with the game's own per-style cooldown;
  in Lab mode targets LabMonster-flagged enemies)
- AutoQueue (LabQ quick with map/diff dropdowns + AutoLeave after run — the raid loop)
- Speed/Auto toggles (probe wires — the game's own HUD buttons, unlock-gated UI-side;
  if the server trusts the wire they're free 2x/auto)

REMOVE (named): all Shop one-shots (daily/spin/code/title/style/offline/use/index/
pquest/reveal handshake), pass/robux products, DungeonLayouts slot UI (in-game window),
GroupRewards claim, Admin remotes, Engagement, ExclusiveWeapon, onboarding telemetry,
ChatAnnounce, unitSell/SellAll (manual inventory decision — no loop value), hotbar
(one-shot UI state), visit/watch/home (one-shot camera moves, UI has buttons),
confirmRoll (arrives only with protect-class meta rolls, native auto-roll already
respects the filter), clearAll (destructive).

## ESC — exploit surface beyond remotes

- **Attributes (26.1)**: player attrs (Gold/Inv/Mons/Auto/Speed...) are server-written,
  client reads only — local SetAttribute = display-only forgery, no server reader
  found at call sites → NOT wired. Tool attrs Combo/Heavy/Swing set by SwordClient on
  the client-owned tool: readers = Anim module animation picker only (23564+: visual
  Attack(heavy)) — server never reads them → NOT wired (checked). BADEnemies
  CombatHP/CombatMaxHP = client-side wave sim display (Battle 17110/18898) → NOT
  wired. Lab monsters: CombatHP=1/CombatMaxHP=1 set client-side (48074) — display
  dummies; the "attack" arg passes the LabMonster attr VALUE (server-assigned id from
  the Lab OnClientEvent spawn packet) — forging it targets nothing server-side we can
  verify → documented probe, not wired.
- **Save/persistence (26.2)**: no DataStore calls in client dump (server-only). The
  client-supplied persistent strings: layout `rename` name field. \255 class: no
  verified verbatim persistence visible client-side → probe documented, NOT wired
  (would be own-data corruption only).
- **Mutable client-trusted tables (26.3)**: Config/GridUtil/RollOdds are shared
  modules but every economy decision (roll results, costs, upgrades) is server-side;
  client mutations only affect local display → NOT wired.
- **Module hooking / no-cooldown (26.4)**: attack cooldown table (SwordClient str1)
  is client-side; server may rate-limit — attack automation uses the game's own
  per-style cooldowns (no faster than legit play). Roll cd 0.9 enforced by native
  auto-roll server loop → no bypass needed.
- **Numeric injection (26.5)**: Build invoke tables all string ids + integer grid
  coords; no numeric arithmetic surface verified on any wire → negative.
- **\255 / rollback (26.6)**: rename string probe documented above; NOT wired.
- **Ownership/replication (26.7)**: character CFrame = TPTo/TweenTo (standard); no
  server reader of owned-part attributes found → covered by movement helpers only.
- **Probes wired as toggles**: Action "auto"/"speed" (gamepass/skill-gated UI, server
  gate unverifiable from client dump — the wire itself is the game's own toggle
  button). Honest labeling: if server checks unlock, toggles no-op.

## Genre notes (user directive: build-a-stuff game — check build tab / copy base)

- Zombies precedent (ZOMBIES-1): AutoPlace + parts multiselect + delay/rotation +
  build save/load. BAD1 equivalents: AutoBuild (systematic fill), CopyBase (steal any
  layout), and the game's OWN save slots exist (DungeonLayouts — UI duplicate, not
  re-implemented). Copy base implementation: pick a source plot (dropdown of
  Plot1..6 by owner name), decode its State JSON, place its floors then objs at the
  same cells from own inventory (skip unowned/blocked), same rotations.

## Feature plan (bad-section)

Toggles on TB_Tabs.Autofarm.T1 (Slop §22 shape, INLINE steps — no Step functions
per the user's PCT1 feedback):
1. AutoWave — startWave when own plot idle (waveActive false, data present).
2. AutoRoll — dropdown RollWhat {Buildings, Monsters, Both} + stopAt rarity dropdown
   (Common..Divine from Config.Rarities); TP to own stand, settings+start each.
3. AutoBuild — serpentine: floors along path (owned, any floor kind), Crystal at end
   (top floor), then traps on path tiles, then monsters on free path tiles (pop
   gate). Skips during waveActive. PlaceDelay slider.
4. CopyBase — plot dropdown (by owner name), button-style toggle: place matched
   pieces at matched cells, floors first then objs, skip unowned.
5. AutoUpgrade — cheapest-first upgrade of placed objs (trap value ladder; units
   soul ladder), currency-gated.
6. AutoExpand — WidthLevels expand when gold ≥ cost & wave gate OK; unlockFloor 2/3.
7. AutoSkill — affordable parent-first skill buys (souls).
8. AutoAttack — BADEnemies in range (13 studs game's own default) at per-style cd;
   Lab mode: LabMonster targets.
9. AutoQueue — LabQ quick {map, diff} dropdowns; AutoLeave after run.
10. AutoSpeed (probe) + AutoStart (probe) toggles — Action speed/auto.

All loops: `while Toggles.X.Value do local ok, err = pcall(function() ...inline... end)
if not ok then notyuri(...) end task.wait(n) end` via Thread + OnChanged.

## Harness note (deobf artifact repair)

The deobf's `GridUtil.trace` dropped the `tbl3 = var1` back-assignment
(line 68111 region: `while tbl3 do table.insert... local var1 = ... end` with
no reassignment = infinite loop). Repaired in the harness module extract
(bad_grid_raw.lua, 1-line re-insertion, documented) — same class as POT1's
deobf-mask repairs. The delivered SCRIPT does not ship this code (it requires
the game's own live module), so the artifact is harness-only.

## Delivery

- Script: Yuri/BuildADungeon/BuildADungeon.lua (1,552 lines = template head 873
  verbatim + 606-line game section + tail, SaveManager folder edit only).
- 11 toggles + RollWhat/RollStopAt/CopyFrom/QueueDiff dropdowns + PlaceDelay
  slider on TB_Tabs.Autofarm.T1, dividers between clusters, inline
  pcall(function() ... end) steps (NO named Step functions — the user's PCT1
  feedback applied).
- Gates: luac5.4 -p OK / lua_lint 0 errors game section (16 inherited
  template-region warnings) / head-tail verbatim / 0 comments.
- REAL-LOAD harness bad_harness.lua: the REAL Config + GridUtil modules
  (Luau-transformed via the POT1 transformer, math.round/table.clone shims,
  trace repair) run against the delivered bytes; semantic mock server
  (place/upgrade/expand/skill rules via the game's own GridUtil functions,
  inventory mutation + attr sync feedback). 57/57 x4 deterministic.
