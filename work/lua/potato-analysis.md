# POT1 — Peel THE Potato (two-place) — deobf analysis

Source: `Public/potato/{game,lobby}/Peel THE Potato[Deob].lua` (commit 2481993,
2026-10-04 11:31 +0700). **Both deobfs byte-identical** (MD5 c2f878216d40f65433dbeaab4748ace5,
76,287 lines). Dumps differ only in `ReplicatedStorage.IsReservedServer` attribute
(game=true, lobby=false) + workspace trees. One script serves both places
(features no-op where their world objects are absent — §22.1 one code path).
No reference scripts, no Template in folder → canonical Template.lua (909 lines,
head 836 / game section / tail 18 insertion), standard autofarm ONLY (§3).

## Transport (Rule 2 verified at call sites)

Packet library `RS.ModifiedPackages.Packet` — SINGLE RemoteEvent
`RS.ModifiedPackages.Packet.RemoteEvent` carrying a binary buffer multiplexer
(60 Hz Heartbeat batch, `FireServer(buffer, instances?)` at deobf L49360-49362).
Wire table = `RS.Modules.Resources.Packets` (deobf L44290-44422): every packet
`Packets.X` with typed args. Client sends via `Packets.X:Fire(args)`, listens
via `Packets.X.OnClientEvent:Connect(fn)`. **We never touch the buffer layer —
we require `RS.Modules.Resources.Packets` and fire the packet objects exactly
like the game's own controllers do.**

## Places

- LOBBY (`IsReservedServer=false`): Map.{Env,FloorMeshes,Leaderboards,Shops,
  Zones.MatchmakingZones.1-4}. Queue hub + leaderboards + gamepass shop.
- GAME (reserved server, via QueueCreate→teleport): Map.{Map,PeelingMachines,
  PotRoom,StoreItems,Waterway}, workspace.{PotatoPile,PotatoStacks,
  WaterwayPotatoes,Effects}. Everything gameplay lives here.

## Game loop

Lobby: enter matchmaking zone pad → server QueueJoined → Setup UI →
`QueueCreate:Fire(size(1-4), skipIntro, friendsOnly)` → QueueTeleporting →
reserved server. Game: pick potatoes from the pile into your bag → carry to
`Map.PeelingMachines.PotatoCrate` → PlacePrompt (place on your table) →
Load prompt into your machine (Hand `PeelingMachine` 10 cash / AutoPeeler
`AutoPeelingMachine` 60 cash, bought via their Price prompts) → hand machine:
Crank prompt loop / auto peeler: peels by itself → peeled potatoes collect in
`SellCrate` → SellPrompt → PotatoesSold (cash paid server-side, popup only).
Key potato (pile, chance ramps ≥100 picked) → HasKey → bunker
`Map.Map.InsideBunker.VaultDoor.Model.Model.KeyHole.ProximityPrompt` →
Escaped (win). Hand-peel minigame session (tutorial/manual): server-initiated
`PeelingStarted` → held potato with 6 Peel children → per peel
`PeelingPeelRemoved:Fire(index, pos)` → `PeelingFinished:Fire()` when done.
Store (`Map.StoreItems.{Tools,Storage,Peelers,Robux}`) — physical Price-part
ProximityPrompts (PURCHASE_HOLD_DURATION=1; fireproximityprompt bypasses).

## Wire table (client→server, call-site verified)

| Packet | Args (deobf types) | Call site | Feature |
|---|---|---|---|
| PotatoPick | U32 potatoId | L24517/24523 (tryPick) | AutoPick |
| ToolSwing | — | L26926 (ToolCtl.Use) | AutoPick |
| ToolEquip | String toolId | L26961 (Equip) | AutoPick equip |
| ToolUsing | Boolean8 | L26905/26977 | (game holds state; not needed) |
| ToolUpgradePurchase | String toolId, String upgradeId | L27675 | AutoUpgradeTools |
| PeelingPeelRemoved | U8 index, Vector3F24 pos | L22443/22456 (performPeel) | AutoPeel |
| PeelingFinished | — | L22114 | AutoPeel |
| PeelingCancel | — | L22118 | (never auto-fire) |
| PeelingSync | Any cframe | L23078 (0.08s cadence) | AutoPeel |
| QueueCreate | U8 size, Boolean8 skipIntro, Boolean8 friendsOnly | L26130 | AutoQueue |
| QueueLeave | — | L26140 | (manual) |
| ClassRoll | — | L19657 | AutoClassRoll |
| ClassStopAt | String classId | L19381 | (game's own cycle button) |
| ClassSlotSelect | U8 slot | L19351 | (manual) |
| LobbyUpgradePurchase | String upgradeId | L21756 | AutoLobbyUpgrades |
| DailyRewardClaim | — | L20155 | AutoClaimDaily |
| GroupRewardClaim | String task ("Claim"/"Like"/"Group") | L39620/39633 | AutoClaimGroup ("Claim") |
| PotatoPileRequest | — | L24944 | (game fires at start) |

Server→client we track (state mirrors): `PotatoPileSynced(U32 seed, {U32 removed}, U32 keyId)`
→ pile state via PotatoPileShared.CreatePile/RemovePotato/SetKeyPotato;
`PotatoesPicked(F64 userId, {U32 ids}, String toolId)` + `PotatoRemoved(U32 id)`
→ RemovePotato each; `PotatoKeyMoved(U32 keyId)` → SetKeyPotato;
`PeelingStarted(Instance, {U8}, String)` / `PeelingNextPotato({U8}, String)` /
`PeelingStopped` / `KeyRevealed` / `Escaped` → AutoPeel session lifecycle.

## Key shared modules (required, never re-implemented — Rule §2)

- `RS.Modules.Resources.Packets` — wire table
- `RS.Shared.PotatoPileShared` — CreatePile(seed), RemovePotato(state,id),
  SetKeyPotato, GetPotatoInSlot/GetPotatoSlot, ForEachSlot(slot,l,r,q),
  IsExposed/IsVisible(state,id,depth), IsDiamond, IsKeyPotato, GetKind,
  FindTopPotato(state,rng), MARKER_NAME="PotatoPile", PICK_DISTANCE=20
- `RS.Shared.PotatoKindShared` — Kinds {Normal ×1, Golden ×3, Rainbow ×10,
  Diamond ×6, Key ×1} (IsDiamond is a pile-buried special, not the kind list)
- `RS.Shared.ToolUpgradeShared` — pick Tools Hand/Shovel(3)/Sucker(30) +
  Body{WalkSpeed,PotatoWorth,Luck} + Machines AutoPeeler/HandPeeler with
  upgrade trees; GetLevel(upgrades,tool,upgrade) key "Tool_Upgrade";
  GetNextCost(upg,level)=Costs[level+1]; GetPickInterval(upgrades,tool,classId,isTrial);
  GetUpgradeable(id) covers Body+Tools+Machines
- `RS.Shared.PeelToolShared` — minigame peel tools Spoon/Knife(0.01)/SwissKnife(1.5)/
  Peeler(4,InstantPeel)/TriplePeeler(25,InstantPeel,PotatoCount=3), AutoPeelRate per
  tool, Tools[i].Price/ItemName for store gating
- `RS.Shared.CarryUpgradeShared` — Levels Hands(10)/Bucket(50,0.5)/PotatoSack(125,3.5)/
  MechaCapsule(450,20), GetPlayerCapacity(carryLevel,gamepasses,lobbyUpgrades)
- `RS.Shared.LobbyUpgradeShared` — GrabAmount/BagSize/CashBoost/GemBoost
  (Costs 100-4000 **Diamonds**, L21746 gate `Diamonds < cost`)
- `RS.Shared.ClassShared` — Classes Peasant50/Comrade20/Digger15/Mechanic12.5/
  PotatoExpert2.4/Hero0.1, ROLL_COST=40, GetActiveClassId(save,passes),
  IsStoppedAt(currentId, stopAtId) = current.Chance <= stopAt.Chance
- `RS.Shared.DailyRewardShared` — Rewards{100..999} gems, GetToday(),
  GetClaimableDay(day, claimDate, today) → nil|day
- `RS.Shared.PotatoTableShared` — machine/table names: MACHINES_FOLDER_NAME
  "PeelingMachines", INPUT_CRATE_NAME "PotatoCrate", OUTPUT_CRATE_NAME
  "SellCrate", prompts Load/Crank/PlacePrompt/SellPrompt, machine roots
  Cube.042 (auto) / Cube.033 (hand), GetCount reads COUNT_ATTRIBUTE
  "PotatoCount", AUTO_PEELER_COST=60, HAND_PEELER_COST=10
- `RS.Shared.StoreShared` — StoreItems categories Tools/Storage/Peelers/Robux,
  GetItem(map,category,name), Price-part attributes ToolId/PeelToolId/
  CarryLevel/Machine, PROMPT_ATTACHMENT_NAME "PromptAttachment"
- `RS.Shared.KeyShared` — KEYHOLE_NAME "KeyHole", USE_DISTANCE 12
- `RS.Shared.QueueShared` — MATCHMAKING_FOLDER_NAME "MatchmakingZones",
  FindPad(zone)
- `RS.Controllers.ToolEquipController` — live singleton: GetEquippedTool(),
  GetEquippedUpgrades(), GetClassId(), OwnsTool, CanUseTool, IsOnTrial,
  HasCharge(), IsOverheated(), Use() (=ToolSwing:Fire + charge), Equip(id)
  (=ToolEquip:Fire + local UI state), GetPickCooldown
- `RS.Shared.PlayerStateShared` — TryGetPlayerState(plr)/GetSaveDataAsync(plr);
  state: Potatoes, Cash, CarryLevel, Tools{}, PeelTools{}, Upgrades{},
  Gamepasses{}, HasKey, HasAutoPeeler, HasHandPeeler, RunPeels;
  SaveData: Diamonds, Class, ClassSlot2, FreeRolls, StopAtClass,
  GroupRewardClaimed, LikedGame, DailyRewardDay, DailyRewardClaimDate,
  LobbyUpgrades{}, ActiveClassSlot

## Rule 11 keep/remove (named)

KEEP (automation/exploit value): pick/place/load/crank/sell loop, AutoPeel
(bypasses the AutoPeel ROBUX gamepass — the game's own updateAutoPeel L22524
is gated by state.HasAutoPeel; we fire the same session packets), machine +
store + upgrade buys (auto-buy cheapest affordable), class roll loop
(respects the game's own StopAtClass), lobby upgrades (diamonds), daily +
group claims, auto-queue, auto-escape (key→vault prompt).

REMOVE (named): PurchaseProduct/ProductAdmin* (ROBUX), SetGlobalOverride/
ResetGlobalOverride (admin), Cmdr everything (admin, CmdrFunction InvokeServer
L12529), StatsRequest/LeaderboardRequest/RunReportRequest/LobbyGuideRequest
(UI one-shots), TutorialCompleted/TutorialStack (server-driven), SoundPlayed/
NotificationCreated (server→client), class slot select + stop-at (game's own
UI), PeelAll product (ROBUX), IntroCutsceneFinished (fires on real cutscene
end; no skip wire verified), ToolUsing (hold-state mirror, no value).

DROPPED by design (cannot verify table assignment — no server code in dump;
machines fully cover the flow): table hand-peel session starting (PeelingTable
Peel prompt). AutoPeel drives sessions that ARE active (tutorial/manual).

## Build plan (standard autofarm, template §14.3 shape)

TB_Tabs.Autofarm.T1, dividers, plain ids, elements-first then OnChanged,
Thread+SafeLoop wiring, pcall per step, one code path both places:

1. AutoPick + PickKinds multidropdown (AddMultiDropdown) — equip best owned
   pick tool (ToolCtl.Equip, reverse ToolUpgradeShared.Tools first CanUseTool),
   gate ToolCtl.HasCharge()/not IsOverheated(), bag gate
   GetPlayerCapacity <= Potatoes (Key/Diamond-pile potatoes exempt — game's
   own tryPick L24502 rule), target = our pile state exposed ids filtered by
   kind, cadence ToolUpgradeShared.GetPickInterval, fire ToolCtl.Use() +
   PotatoPick:Fire(id)
2. AutoPlace — Potatoes > 0 → TPTo(PotatoCrate area) + FirePP(PlacePrompt)
3. AutoLoad — input crate GetCount > 0 + machine owned → TPTo + FirePP(Load)
4. AutoCrank — hand machine owned + no auto peeler + hand machine count > 0 →
   FirePP(Crank)
5. AutoSell — SellCrate GetCount > 0 → TPTo + FirePP(SellPrompt)
6. AutoPeel — session tracker (SafeConnect PeelingStarted/NextPotato/
   Stopped/KeyRevealed/Escaped), loop: peels of the current potato model at
   1/AutoPeelRate (PotatoCount divisor), PeelingPeelRemoved:Fire(i, peel.Position),
   all removed → PeelingFinished:Fire(); PeelingSync:Fire(model pivot) 0.08s
7. AutoBuyMachines — cash ≥ HAND_PEELER_COST && !HasHandPeeler → FirePP hand
   machine Price prompt; then cash ≥ AUTO_PEELER_COST && !HasAutoPeeler → auto
8. AutoBuyTools — store Tools (Shovel 3, Sucker 30 via ToolUpgradeShared
   Prices) then Storage (CarryUpgradeShared next level Cost) then Peelers
   (PeelToolShared Price order) — cash-gated, one FirePP per buy pass
9. AutoUpgradeTools — cheapest next upgrade across ToolUpgradeShared
   GetUpgradeable set (Body + owned tools + owned machines), cash-gated,
   ToolUpgradePurchase:Fire(toolId, upgradeId)
10. AutoEscape — state.HasKey → TPTo(KeyHole) + FirePP(prompt)
11. AutoQueue (lobby) — TPTo(MatchmakingZones first zone FindPad) →
    QueueCreate:Fire(size, false, false); AutoQueueSize dropdown 1-4
12. AutoClassRoll — not IsStoppedAt(active, StopAtClass) && (FreeRolls > 0 or
    Diamonds ≥ ROLL_COST) → ClassRoll:Fire()
13. AutoLobbyUpgrades — cheapest next across LobbyUpgradeShared.Upgrades,
    Diamonds-gated, LobbyUpgradePurchase:Fire(id)
14. AutoClaimDaily — GetClaimableDay(day, claimDate, GetToday()) →
    DailyRewardClaim:Fire()
15. AutoClaimGroup — not SaveData.GroupRewardClaimed →
    GroupRewardClaim:Fire("Claim")

Gates: luac5.4 -p; lua_lint.py game section (0 comments, no Luau-only globals
outside template region); validate.sh diff = UI-def blocks + game section +
SaveManager folder; REAL-LOAD harness (mock world + delivered bytes).
Delivery: folder mode, `potato/Potato.lua` (both deobfs identical → one
script at potato/ root, DF1 convention of script inside the game folder).
