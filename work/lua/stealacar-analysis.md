# Steal A Car — analysis (glm3, SAC1)

Public 0acfce8, folder delivery `Steal A Car/Steal A Car.lua`. Single place,
no reference script → ONBOARDING §3 standard autofarm BOTH halves.
Deob = 27,257 lines; dump = 301,710 lines.

## Remote census (all call-site verified, Rule 2)

Remotes live in `RS.Remotes.Events.*` (RE) / `RS.Remotes.Functions.*` (RF).
Client convention: direct `:FireServer(...)` / `:InvokeServer(...)` — no
resolver module, no BridgeNet. 37 RE + 17 RF total; relevant wires:

| Remote | Wire (verified at) | Feature |
|---|---|---|
| SellCars RF | `InvokeServer({uid,...})` L3393 | Auto Sell (uids from GetSellInventory) |
| GetSellInventory RF | `InvokeServer()` L3355 → `{Uid,Id,Price,Image}[]` | support |
| BuyTrail RE | `FireServer(trailId)` L3138 | Auto Buy Trail (cash Price ladder, TrailConfig) |
| ClaimIndexReward RF | `InvokeServer()` L16082 (gate: state.Claimable) | Auto Index Reward |
| GetCarIndex RF | `InvokeServer()` L16113 → state w/ Claimable | support |
| FuseRequest RF | `InvokeServer("Toggle",tier,slot)` L10043, `("Fuse"\|"Claim",tier)` L10061 | Auto Fuse (skip "Skip" = Robux) |
| FreeGiftRequest RF | `("Get")` L7594 / `("Claim")` L7657 | Auto Free Gift |
| DontLeaveGiftRequest RF | `("Open")` L10520 / `("Claim")` L10578 | Auto DontLeave Gift |
| OfflineLootRequest RF | `("Get")` L7372 / `("Claim")` (Collect+Exit both → Claim) | Auto Offline Loot ("Double" = Robux, skipped) |
| RaceRequest RE | `("Sync")` L9248 / `("Join")` L8828 (gate: RS.RaceState attr Phase=="Joining") | Auto Race |
| RaceRewardRequest RF | `("Get")` L9256 → `{Ready,Offer={Id,Minutes,Kind}}` / `("Claim", id)` L8766 | Auto Race |
| ClaimTreadmillBonus RF | `InvokeServer(token)` L11641 (token = Plr attr `TreadmillBonusOfferId`, gated on TrainingTier + char attr TrainingTreadmill + alive) | Auto Treadmill |
| TreadmillActivity RE | `FireServer()` L4850/5004/5023/5039/5061 — game's own 5s-debounced activity ping on any input while TrainingTier set | Auto Treadmill (activity keep-alive) |
| UpgradeTreadmillPurchase RF | `InvokeServer(tierIndex)` L8438 (tier = current+1; TreadmillConfig.Tiers Price = CASH ladder, ProductId = robux alt) | Auto Upgrade Treadmill |
| GetPlayerData RF | `InvokeServer()` L1079 → `{Cash, Speed}` | support (cash tracking; also CurrencyUpdated RE `{Cash, CashFormatted, Speed}` L1045) |

REMOVED (Rule 11): BuyTrailRobux L3143 / CaughtSpeedPurchase L7531 (offer
CoreFeedback CaughtSpeedOffer w/ ProductId) / BuyTreadmillClickBoost L11641
paid variant / BuyTreadmillMultiplier L8648 (Upgrades = ProductId+RobuxPrice
only) / OfflineLoot "Double" / FuseRequest "Skip" — all Robux. Admin cluster
(AdminRequest/Announcement/Poll*/Crate*/Treadmill* admin variants,
L13402-15638) — admin-only. SetPlayerSetting L9718, SetSlowMode L5782,
EquipTrail L3134, EquipMiniCar L3640 — one-click UI actions. SubmitFeedback
L16665 — telemetry. CombatRequest L8048/8076/8146 (Bat Swing/BearTrap Place/
Equip) + ExitTreadmill L4850 — manual actions, no farm loop. DriveInput
L1813/1857 (throttle, steer, isTouch @ SendInterval 0.05) — per-frame
driving physics; car transport below uses CFrame instead (game's own parking
check is server-side distance, ZoneConfig.ParkingDistance 26 + tolerance 6).

## World model

- `workspace.LiveStolenCars` — stolen car Models: `Chassis` (BasePart, has
  GroundAnchor attachment), `DriverSeat` (Seat), `StealAttachment.StealPrompt`
  (ProximityPrompt), attrs `TheftState` ("Available" = stealable),
  `ZoneSpawn`, `TutorialOwnerUserId`, `TutorialDuplicateHidden` (prompt attr).
- `workspace.Plots` — plot Models, attrs `Owner` (UserId), `Taken`, `Level`,
  `ParkingSpaces`, `UpgradeCost`, `TreadmillTier`. Children:
  - `ParkingInteractions.<slot>` Part (attr PlotSlot) → `.Attachment.ParkingPrompt`
    (ProximityPrompt ActionText "Place Car", attr PromptAvailable) + ClickDetector
  - `Sign.Sign` w/ SurfaceGui upgrade ButtonFrame + ClickDetector (upgrade =
    click; feedback via PlotUpgradeResult `{PlotName, Reason}`, PlotConfig.
    UpgradeCosts ladder {10000, 1e6, 1e8, 1e10, 1.4e14}, MaxLevel 5,
    SlotsPerLevel {8,10,12,14,16,32})
  - `Treadmill.Treadmill.RunPosition.UpgradePoint.Upgrade` prompt (walk-up
    treadmill tier upgrade; same UpgradeTreadmillPurchase wire)
  - `Treadmill.Treadmill.TrainingZone` part (standing = training; char attr
    `TrainingTreadmill`, player attr `TrainingTier`)
  - `Cars.<Model>` display platforms w/ EntryZone
- Steal→park flow: FirePP StealPrompt → server seats you (Humanoid.SeatPart =
  DriverSeat, player attr DrivingCar) → drive car to plot → FirePP
  ParkingPrompt ("Place Car") → car placed on slot → sell inventory.
- Car transport in Auto Steal: stepped CFrame of Chassis toward my plot's
  free ParkingInteractions part at fixed speed (zone CarSpeed 48), zeroing
  AssemblyLinearVelocity per step, then FirePP the prompt.

## Configs (all require'd, never copied — Rule 2)

TrailConfig (Price + SpeedMultiplier + MovementMultiplier per trail),
TreadmillConfig.Tiers (Price/SpeedPerSecond/ProductId), PlotConfig
(UpgradeCosts, MaxLevel), FuseConfig.Tiers (Ingredients[3], Duration,
SkipProductId, CarId; tier N gated on tier N-1 Claimed), IndexConfig.Rewards,
SpeedConfig, ZoneConfig (PromptDistance 12, ParkingDistance 26,
ParkingServerTolerance 6), DrivingConfig (SendInterval 0.05), FreeGiftConfig,
DontLeaveGiftConfig.

Fuse state: `FuseUpdated` S→C → state `{ServerTime, Tiers = {[tier] =
{EndsAt, Claimed, ...}}}`; server-time offset = state.ServerTime - os.time()
(L9940 shape); claim when `0 < EndsAt and EndsAt <= os.time() + offset`.

## Anti-cheat finding (documented risk)

`AntiCheatNotice` S→C: "Movement warning %d/%d. Disable movement exploits.
Three warnings result in a 24-hour ban." — server-side MOVEMENT validation
(client dump has no server code; trigger surface unknown). Auto Steal uses
character TP (TPTo + FirePP teleport) → risk flagged to user in delivery
note; toggles ship OFF by default. Game's own speed curve caps at 315
WalkSpeed (SpeedConfig.MaxWalkSpeed) — template Player WS/JP sliders stay
user's own risk, game section adds no movement code.

## Feature set (12 toggles, TB_Tabs.Autofarm.T1)

Auto Steal / Auto Sell / Auto Buy Trail / Auto Upgrade Treadmill /
Auto Upgrade Plot / Auto Treadmill (activity ping + bonus token) /
Auto Fuse / Auto Index Reward / Auto Race / Auto Free Gift /
Auto Offline Loot / Auto DontLeave Gift.
