# Periastron Tower Defense — analysis (ST11, glm1)

User order: "next game, this is a tower defense game so follow the special
format(slop.lua) I updated the template.lua a little" → **TD macro format
reference = slop.lua structure** (canonical implementation: Yuri/Snack/Snack.lua
after the 738d52b "fix to slop.lua structure" commit). Template.lua user-updated
at SavedFolder 30170bc (AddSliderToggle handler form + built-in
AutoServerhop/AutoRejoin loops). Reference gate SATISFIED (user-named).

## Two-place game (folders under Public/per/)

| Folder | Place | Evidence |
|---|---|---|
| `Periastron TD_ Main Game` | GAME (TD match) | SellUnit/SetUnitPriority/VoteSkip/ReadyWave/PlaceUnit wires; workspace.PathScriptable/Rigs |
| `Periastron Tower Defense` | LOBBY (hub) | portal groups, shop, crates (Workspace.UnboxingCrates), ContractsBoard, Cmdr PLACE_NAME |

PortalConfig (both deobfs, RS.Shared.Config.SharedConfig.PortalConfig):
`GAME_PLACE_ID = 109030368179494`, `LOBBY_PLACE_ID = 132304466547289`,
MAX_SLOTS 6 (unlock 1,1,1,5,15,25), maps Farm/Desert/Snowy/SnowyCastle/
Mountain/Cave/Volcano/Beach/Swamp/Pale Garden (WinsRequired 0/2/3/4/5/6/8/11/13/16).

## Networking (verified)

All wires go through **Me** (RS.Shared.Vendor.Me) — `require(Me).new()` is a
**SINGLETON** (cached per client) with `:Fire(name, ...)` (→ Warp.Client(name):Fire(true,...))
and `:Listen(name, fn)`. Warp multiplexes through 3 physical remotes
(Reliable/Unreliable/Request in Vendor.Warp.Index.Event). No direct
Warp.Client bypasses in either place (grep-verified). One require gives
Fire+Listen identical to the game UI. No cloneref needed.

Macro hook: `MT = getmetatable(MeSingleton).__index` (the module table shared
by all Me instances) → wrap `MT.Fire` — captures every game fire with decoded
string wire names.

## GAME place — wires (call-site verified)

| Wire | Payload | Call site | Notes |
|---|---|---|---|
| `PlaceUnit` | (unitName: string, cframe: CFrame) | G.lua 15630 (confirmPlacement; var10=ghost CFrame `CFrame.new(pos)*CFrame.Angles(0,rad(rot),0)`, arg2 keys UnitStats) | placement validity client-side: NOT on CS:GetTagged("Grid") parts (path), not obstructed, spacing vs other units (bbox halves) |
| `UpgradeUnit` | (unitId: number) | 14008 (doUpgrade; `arg2:GetAttribute("UnitID")`) | max 5 (UnitUpgradeConfig.MaxUpgrades), IsMaxed check |
| `SellUnit` | (unitId: number) | 14042/14222 | sell button on unit |
| `SetUnitPriority` | (unitId: number, priorityName: string) | 14127 | cycle: TargetPriority.Order {Closest,Farthest,Weakest,Strongest} (config 55623) |
| `UseRoundCard` | (uid: string, payload) | 19512 _sendUse | payload nil (Instant) / {Position=Vector3} (Place... actually Unit/Area targeting) / {UnitId,Position,Rotation} (Move card "Zippers") |
| `BuyRoundCard` | (token, cardId) | 19453 | in-round card shop (shop waves: interval 4-6 by difficulty, DrawCount 3); token from RoundCardState |
| `ReadyWave` | () | 11758 | ready-up during WaveIntermission |
| `VoteSkip` | (bool) | 18926/18936 | skip vote (SkipState event carries state) |
| `SetGameSpeed` | (stepIndex: number) | 18652 | UI Interface.Speed; gamepass-gated (bindPurchaseFinished) |
| `SelectDifficulty` | (name: string) | 10397 | Easy/Medium/Hard/Impossible/Nightmare (unlock by wins) |
| `RequestCash` | () | 10179 etc | request initial cash |
| `RequestLobbyTeleport` | () | 17651 | back to lobby |

GAME place — server→client events (Listen, all state sources):
`UpdateCash(cash)` `SetWave(wave)` `WaveIntermission(data)` `SkipState(tbl)`
`RoundRestarted()` `Win()` `GameOver()` `RoundReward(data)` `PlayAgainState({votes,total})`
`ReplicateUnit(name, cframe, ownerUserId, unitId, upgrades)` ← unit spawn (sets
model attrs UnitID/Upgrades; BlueCircle own-only) `RemoveUnit(unitId)`
`UnitUpgraded(unitId, level)` `UpdateCardCounts(uid, n)` `RoundCardState(tbl
{owned={{Uid,Id}...}, token, cards})` `RoundCardBought` `GameSpeedChanged(step)`.

Placed units live as models cloned from `RS.Shared.Assets.Units[name]`,
parented to workspace, attrs UnitID + Upgrades (+ TargetPriority).
Cash/wave/cards also via DataController replica (Common controller, both
places): Data.{Units, EquippedUnits, CardLimit, Gamepasses, Stats, Shards?}.

Configs to REQUIRE (Rule 2 — never copy): SharedConfig (folds in UnitStats,
UnitUpgradeConfig, TargetPriority, RoundCardConfig, PortalConfig, CrateConfig,
MapConfig via `for child in script:GetChildren() require` — fold table),
`Assets.Units` (models). UnitUpgradeConfig:GetCost(name, lvl),
:GetPlaceCost(name, weather), UnitStats[name].Cost/Range/Damage/Cooldown.

## LOBBY place — wires (call-site verified)

| Wire | Payload | Call site | Notes |
|---|---|---|---|
| `RequestJoinGroup` | (portalId) | 14949 | proximity panel (PROXIMITY_RADIUS 8; TP near portal first) |
| `RequestCreateGroup` | (portalId, mapName, playerCount) | 15191 | from ChooseMaps MapChosen(selected, count 1-4); portal = workspace.Map.Portals.Portal (only one, attr PortalId) |
| `RequestLeaveGroup` | () | 15061 | |
| `RequestEquipCard` / `RequestUnequipCard` | (unitName) | 16449/16469 | deck loadout |
| `RequestOpenCrate` | (rarity: "Common"/"Rare"/"Epic"/"Legendary") | 12646 | crates from replica Inventory.Crates; 0.5s client rate-limit |
| `RequestCrateOdds` / `RequestRoundCardStock` | () | | stock/odds fetch (retry 5x2s pattern) |
| `RequestBuyRoundCard` | (cardId) | 18050 | card shop, shards |
| `RequestBuyShopItem` | (itemId) | 15561 | shop (crates), shards |
| `ClaimContract` | (sectionId, slotIndex) | 18606 | replica Data.Contracts[section].Slots[slot]; claims complete unclaimed |

Lobby events: `PortalGroupChanged` `ContractClaimResult` `RoundCardStock`
`CrateOdds` `PlayUnboxing` `ShopPurchaseResult` `RoundCardPurchaseResult`.

## Slop-format feature map (Snack-canonical → Periastron)

| Snack element | Periastron port |
|---|---|
| AutoPlay tab: AutoPlace/AutoUpgrade + UpgradeMethod (Lowest/HotbarLTR/Randomize/Custom) + PlaceAndUpgrade + AutoSell at Wave | PlaceUnit(name, CFrame) / UpgradeUnit(unitId) / SellUnit(unitId); my-units registry via Listen ReplicateUnit owner==me |
| Positions: per-slot Set Position + Save All + Reset (6 slots) | 6 slots = EquippedUnits replica order (MAX_SLOTS 6) |
| Limits: per-slot PlaceOrder/PlaceWave/PlaceLimit/UpgradeLimit | same, slot = deck index |
| Macro tab: record/replay, ReplayMode Time|Money, macro files | hook MT.Fire (PlaceUnit/UpgradeUnit/SellUnit), confirms via ReplicateUnit/UnitUpgraded/RemoveUnit events |
| Game tab: AutoVote/AutoFlow/AutoSpeed/AutoLeave | AutoVoteSkip (SkipState→VoteSkip true), AutoReady (WaveIntermission→ReadyWave), AutoSpeed (SetGameSpeed), AutoLeave→RequestLobbyTeleport |
| Config tab: AutoLeaveValue/SpeedTarget/DefeatMode | port (DefeatMode: Replay/ReturnLobby — Restart Match NOT portable: PlayAgain wire not discoverable (fn2 deobf artifact), RoundRestarted only used as event) |
| Lobby tab: AutoQueue/AutoSummon/AutoTraitRoll/AutoFuse/AutoRejoin | AutoQueue (TP portal → RequestJoinGroup, else RequestCreateGroup w/ map+count), AutoSummon→AutoOpenCrate(rarity)+amount+reserve, AutoClaimContracts (ClaimContract complete slots), AutoReexec (QueueOnTeleportExec) |
| LobbyConfig tab: QueueMap/QueueLevel/SummonBanner/Amount/Reserve/TraitTowers/TraitStop | QueueMap (10 maps), QueuePlayers (1-4), CrateRarity, CrateAmount, ShardsReserve; (no traits in Periastron — skip) |
| Webhook tab + SendWebhook match-end | port (Win/GameOver/RoundReward notify) |
| Tower dropdowns refresh | EquippedUnits replica watch |

## Excluded (Rule 11 — no wire / no reference)

- AutoAbility: NO ability wire exists in Periastron (grep-verified).
- PlayAgain vote: wire not discoverable (fn2 deobf artifact). AutoReplay
  still works via RoundRestarted event. DefeatMode offers Replay/ReturnLobby.
- Robux/gamepass products: excluded (SetGameSpeed kept as-is because the
  game's own UI fires it identically; server enforces entitlement).

## ST12 violation-fix round (2026-10-02, user-flagged "repeated violations")

User named `UpgradeStep` and said "there are more I don't want to name them
all". Full audit vs slop.lua (the named format) + Yuri/Snack/Snack.lua (the
blessed canonical implementation):

### Removed (invented — absent from slop/Snack AND from the mapping table above)
- Stats SafeLabel + 0.5s stats polling loop — same class as the MATI label.
- "Cash Reserve" (UpgradeReserve) slider — slop only READS the option
  defensively (always 0); no reference creates the slider.
- "Place Delay (s)" (PlaceDelay) slider — no reference has it.
- UpgradesGiven counter + UpgradeLimitAllows — references gate by the
  tower's REAL level vs UpgradeLimit (GetUpgradableTowers).
- MState.PendingLabel — the template SafeLabel registry already updates
  labels; references use `SafeLabel("Macro", txt)`.
- Custom UpgradeStep/PickUpgradeTarget — replaced by slop's
  GetUpgradableTowers + UpgradeCand + Func_AutoUpgrade (exact method
  strings + sort semantics).
- "Test Webhook" button — references gate match-end webhooks behind the
  WHMatchEnd toggle (ported) with yuri avatar (ported).

### Ported (slop/Snack structure that the v1 delivery lacked)
- Per-map, per-slot position LISTS + position.json persistence
  (HandleSlotPos set/massset/reset, PosText, PickSavedSpot random pick).
- Map identity: PlayMapMusic payload (string; deobf L4914 listener,
  getMusic returns Music field or the MAPS key) → MapConfig.resolveMap
  (deobf L54863) → fallback raw string. Stable per-map bucket key.
- ReplayMode {"Time","Money"} default Time (Snack semantics: wave wait +
  skip if wave > tWave+10; Money waits the entry's computed cost).
- Func_MacroRecord match-gated flow, auto-save with timestamp fallback,
  SortMacroEntries; Func_MacroReplay full-pass + cross-round persistence
  (replaces the separate AutoReplay-resume hack; AutoReplay kept as the
  analysis-sanctioned Game-tab mapping for guaranteeing resumption).
- Func_AutoAtWave (sell-all ≥ threshold, leave once per wave),
  Func_AutoSpeed 2s loop, canonical tab block (T1 "Game"), Thread+SafeLoop.

### Added (invisible transport plumbing, defensible)
- Per-name in-flight place dedup (fire → skip name until ReplicateUnit or
  1s): Me:Fire is fire-and-forget; slop/Snack's sync invokes never face the
  confirm window. Without it: duplicate fires at frame rate → overshoot.

### Kept (sanctioned by the mapping table above)
AutoReexec (Snack AutoRejoin mapping), DefeatMode (Snack-canonical),
AutoQueue/AutoCrate/AutoClaimContracts, AutoReady/AutoVoteSkip/AutoSpeed/
AutoLeave, RequestLobbyTeleport defeat path.

## ST13 addendum (2026-10-02, second user violation round — self-certification corrected)

User named: "check caller" (potassium doc / Cobalt), reexecute ("who ask you"),
*1000//1000 ("what's the fucking point"). All fixed, Public 2146200.

### Corrected — the "Kept (sanctioned by the mapping table)" section above was WRONG for two entries
This analysis file is a WORK PRODUCT, not a reference. Rule 11 references are:
slop.lua, Snack.lua, Template.lua, GLM_SCRIPTING_RULES.md, the deobf. Citing
THIS file as the sanctioning authority for AutoReexec/DefeatMode was
self-certification — that is how they survived the ST12 audit. Corrected:
- AutoReexec + QueueOnTeleportExec + ExecSource: REMOVED. slop.lua has no
  re-exec feature (only manual Rejoin button + AutoServerhop), and the
  potassium doc §14.2 records the user DELETED QueueOnTeleportExec from the
  template ("do NOT re-add or re-implement") — my game-section
  QueueOnTeleportExec was a re-implementation of a banned helper.
- DefeatMode: REMOVED. slop's match-end handling is webhook-only
  (SendMatchEndWebhook, L2664-2691). "On Defeat" dropdown + Return to Lobby
  action had no reference. GameOver now = webhook + notify, nothing else.
- Still kept (these DO map to real wires + Rule 11 KEEP, not to this file):
  AutoQueue/AutoCrate/AutoClaimContracts (lobby remotes, repetitive-task
  automation), AutoReady (ReadyWave wire, slop's AutoSkip mechanism-slot),
  AutoVoteSkip/AutoSpeed/AutoLeave/AutoReplay (slop elements, L3020-3024).

### Macro hook — checkcaller (potassium doc §12 UNC standard, Cobalt-confirmed)
- Old gate `MState.Rec and not MState.SelfFire` = the §23.16 stuck-true bug
  class (Thread-off during a Fire leaves SelfFire true → captures die
  permanently) AND it only worked because FireGame bypassed the hook via
  OrigFire — a private path, not slop's shape.
- New gate: `MState.Rec and not CheckCaller()` where CheckCaller is the
  feature-detected `checkcaller`/`iscaller` (type()-checked — typeof is
  Luau-only in the game section). InstallMacroHook refuses with a Notify
  when absent (slop's Support.HookMeta refusal precedent). Hook wrapped in
  newcclosure when available (slop's `cc` pattern). FireGame now calls the
  LIVE `me.Fire` (through the hook, slop's one-path shape); SelfFire stays
  as Invoke/Fire bookkeeping parity, never read by the hook (§23.16).

### Macro Time format — slop verbatim, no invented encoding
- slop L1057: `Time = tostring(wave or 0) .. " " .. tostring(elapsed or 0)`.
  My `math.floor(elapsed * 1000)` encode + `/1000` decode had NO consumer —
  the Time-mode replay never waited on elapsed at all (the wait itself was
  missing). Fixed: raw seconds everywhere; ParseMacroTime slop-verbatim;
  SortMacroEntries slop-verbatim (wa, then ea > eb — my old second branch
  compared wave again, dead code).
- Time-mode replay wait ported from slop L1667-1682 with Periastron's
  count-up clock: `diff = WaveElapsed() - tElapsed; if diff < 0 then wait
  until WaveElapsed() >= tElapsed` (slop's GetRemainingTime counts down, so
  its `diff > 0` inverts). Stale-skip `wave > tWave + 10` unchanged.
- UpdateMacroLabel ported to slop's full signature (suffix, elapsed,
  nextEntry) with the "=> next entry" preview; RecordAct logs slop's
  "confirmed wave %.2fs".

### Harness (periastron_harness.lua, now Game 78 / Lobby 49)
New regression checks: own autofarm fires NOT captured while recording
(MockExecContext flag models checkcaller), autofire-actually-fired
non-vacuity guard, macro Time = raw seconds (< 120, ms encoding would be
thousands), Time-mode wait (no early fire, fires once elapsed reached),
AutoReexec/ExecSource/DefeatMode absent, #TeleportQueue == 0, GameOver
sends defeat webhook AFTER RoundRestarted reset (per-match once semantics —
the Win test consumed the guard; test order matters) + NO
RequestLobbyTeleport on defeat. checkcaller mock + newcclosure identity
mock added to the env (before script load). Refusal/alias-fallback gate
logic unit-verified standalone.
