# FNAF World Multiplayer — Analysis (FW1)

Public 8744ca1. Single place. Deobf 88,747 lines + 144,225-line dump.
No reference scripts, no Template in folder → canonical Template.lua (919 lines,
1df3865 version). Standard autofarm ONLY (ONBOARDING §3). Genre: FNAF World
fangame RPG — turn-based battles, bytes (party helpers), chips, FazTokens
economy, DeeDee fishing minigame, multiplayer challenger gacha.

## 1. Remote census (11 RemoteEvents + 5 RemoteFunctions, all in RS.FnafWorldRemotes + RS root)

| Remote | Kind | Verdict |
|---|---|---|
| ChallengerRoll | RF | KEEP (game flow: "Roll"/"Announce"/"Complete"/"Fail" — invoked BY the game's own controllers; we never call it directly) |
| SaveData | RF | game-only (FnafWorldSaveClient.AutoSave wraps it; we mirror AutoSave after purchases like the game's own buyByte does) |
| FlipsideExitRequest / OverworldLayerRequest | RF | REMOVE (UI-driven layer travel one-shots) |
| GetServerAnnouncement / ServerAnnouncement | RF/RE | REMOVE (announcements display) |
| SetSupporterBenefits | RE | REMOVE (supporter toggle) |
| ChallengerAnnouncement | RE | REMOVE (chat display) |
| OpeningCutsceneSeen | RE | REMOVE (one-shot) |
| WorldAccessCorrection | RE | REMOVE (server correction listener) |
| NuzlockeReviveCredit | RE | REMOVE (nuzlocke flow) |
| SetPlayerSession | RE | REMOVE (session bookkeeping) |
| ShopkeeperStateEvent | RE | game-only (shop open/close sync, fired by the game's own shop controllers on touch) |
| SetOldFreddyAppearance | RE | REMOVE (cosmetic) |
| SharedChestReward | RE | REMOVE display (chest rewards are LOCAL, see §4) |
| DeedeeFishingStateEvent | RE | game-only (boat position sync for other players, fired by the minigame render loop) |

**The wire surface is nearly irrelevant: the whole game is client-authoritative.**
Tokens/bytes/chips/XP/battle outcomes all live in client state (player
attributes + local tables) and are persisted via SaveData. No wire forging
needed — automation drives the game's own UI/module code paths.

## 2. Battle system (BattleController = PlayerGui.FnafWorldBattle, L22345-34976)

- Battles are 100% client-side. Victory applies XP/tokens locally, AutoSaves.
- **Start triggers** (exhaustively verified — no random/wild encounter starter exists in this build):
  1. Boss touch/proximity: `workspace.Map.Bosses.*` (10 boss Parts + Scott Model),
     each with CollisionBlocker. AutoChipperOverworldController: Touched +
     0.05s Heartbeat GetPartBoundsInBox(box + 0.2, {char.Collision}) →
     `FnafWorldBattle.OpenBattle:Fire(boss)` (BindableEvent on the gui).
  2. Challenger battles: server ChallengerRoll "Roll" (auto-invoked by the game
     after regular victories/runs — no client starter we can call; ForceChallenger
     bindable is dev-gated CanUseStudioTools = Studio + UserId 1048500292).
- **Move flow**: MovePanel (children Move1-3Button ImageButtons + attrs
  ActiveSlot/ActiveTeam/ActiveCharacter) → button Activated → `attack(slot)`
  with ALL guards inside (panel matches character, charge consumed, session
  current). Auto-targeting inside FnafWorldMoveFormulas (no target UI).
  Move data: `PlayerGui.FnafWorldBattle.BattleController.BattleMoveButtonData`
  module → `.Characters[charName] = { {name, effect, damage/heal/...}, ×3 }`,
  effects: singleDamage / allDamage / buff / healAll / healAndDamageAll / regen /
  stun / instantDefeat (Unscrew 33% regular, 1.67% boss).
- **Party HP**: HPBar1-4 frames (children of the battle gui, index-aligned with
  PartySide.Character1-4 frames' CharacterName attrs) → HPText (floor HP) +
  RedBar. MaxHP: `RS.FnafWorldProgression.Get(plr, char).maxHP` (= base hp by id
  + (level-1)*5; levels via FnafLevel_<char> attributes).
- **Team switch**: SwitchButton (Visible = other team has living members) →
  Activated → switchActiveBattleTeam. Not auto — AutoBattle must fire it when
  the panel stalls.
- **Victory**: non-boss non-challenger → auto-chains ChallengerRoll "victory"
  after 0.35s (server 20% BaseRollChance × ChallengerConfig.Zones weights).
  Challenger victory → "Complete" → character UNLOCK (gacha reward).
- **Game over** (party wiped): playGameOverSequence → ALL bosses reset
  (DefeatedLocally=false) → TP back to FazbearHills → openPartyScreenAfterGameOver
  (FnafWorldTitleScreen with attribute OpenAsOverworldParty=true) → SaveScreen
  DoneButton (Activated via ConnectBack = plain Activated:Connect) → AutoSave +
  closeOverworldPartyScreen. Existing party retained → recovery = fire DoneButton.
- NoEncounters attr blocks boss touches (auto-set true in GlitchWorld layer 2).

## 3. Bosses (workspace.Map.Bosses)

AutoChipper, Bouncer, Seagoon, Bubba, ChippersRevenge, Overclock, Porkpatch,
Security, Snowcone, Supergoon (Parts) + Scott (Model). All have CollisionBlocker
+ BattleEnemyType/ExpansionBoss attrs + DefeatedLocally. Reset on game over and
on save load. `RS.FnafWorldOverworld.CanInteractOnLayer(plr, boss.SourceLayer)`
gates interaction. AutoChipperBattleCooldownUntil (10s) after game over only.

## 4. Token chests (SharedTokenChestRewards, L274-1263)

`workspace.Map.TokenChests.SilverChest` models (Building + CollisionBlocker).
Claim is 100% LOCAL: chest available → box.CanTouch=true (showModelLocal) →
character in box bounds (+3,5,3) → tryClaimChest → +10 tokens (gold 50, 10%
chance), 300s per-chest local cooldown, AutoSaved. TP into the box triggers
Touched → claim. Slot system cycles availability (3 slots).

## 5. Shops (all LOCAL purchases — FazTokens attribute arithmetic)

- **Lolbit** (LolbitShopKeeper1-7 NPCs): bytes. `RS.FnafWorldByteInventory`
  module: Names/Prices (Gnat 25 … X-Reaper 2000), ShopStock per keeper,
  `Purchase(plr, name)` = local check-deduct-own + the shop UI then AutoSaves.
  Shop opens on NPC CollisionBlocker touch (openShop → ShopkeeperStateEvent
  :FireServer(true) + gui enabled).
- **Mendo** (defense upgrades 250/1500/9000): one-shot ladder → §11 REMOVE.
- **DeeDee fishing** (DeedeeShopKeeper NPC): FnafWorldDeedeeMinigame.
  Round = 10 tokens (local deduct) → 60s round, boat (FreddyBoatImage, Line +
  Plunger are CHILDREN → plunger X tracks boat) moves L/R via input only;
  DropButton → drop() → animateDrop (DropSpeed 0.55s to DropDistanceScaleY
  0.86), catch = plunger rect (44% width inset X) vs fish rect overlap each
  RenderStepped. Fish = FishLayer children matching `Fish_%d+$`, fully
  deterministic attrs: SwimDirection/SwimSpeed/SwimMinX(0.05)/SwimMaxX(0.95)/
  SwimLaneY. Pearl identical (Pearl* attrs, PearlLaneY 0.9146, speed re-rolled
  0.047-0.131/s at bounces). Rewards LOCAL: Orange 1 / Green 2 / Purple 5 /
  Blue 10 / Pink 20 / Yellow 50 / Pearl 100 → awardFazTokens (local SetAttribute).
  getCatchTarget prioritizes Pearl then first-overlapping fish. ONE drop per
  round (catch or miss both end it). After a round: DeedeeReturnAt attr =
  os.time()+120 (shop hidden 120s, openShop early-returns) — documented as a
  possible client-attr bypass, NOT shipped (faithful version first).

## 6. Feature verdicts (Rule 11)

| Feature | Verdict | Implementation |
|---|---|---|
| AutoBattle | KEEP | fire Move1-3Button.Activated when MovePanel.Visible; smart slot pick from BattleMoveButtonData effects (heal when lowest living member < 40%, else instantDefeat (no boss) > allDamage > singleDamage > healAndDamageAll); fire SwitchButton.Activated when it's Visible and panel hidden (stall); fire SaveScreen DoneButton.Activated when TitleScreen open with OpenAsOverworldParty (game-over recovery). Gates all inside the game's own attack(). |
| AutoBoss | KEEP | while idle (battle gui not Enabled): pick nearest alive boss (DefeatedLocally ~= true, CanInteractOnLayer ok, CollisionBlocker exists) → TPTo(CollisionBlocker) → proximity poll starts battle (game's own 0.05s Heartbeat check). |
| AutoChest | KEEP | TP into available chest boxes (box.CanTouch) → Touched → local claim. |
| AutoFish | KEEP | TP to DeedeeShopKeeper → shop auto-opens → fire FishingPlayHitButton.Activated (child of FnafWorldDeedeeShopKeeper) → during round: pick target (Pearl > Yellow > Pink > Blue > Purple > Green > Orange), predict X (deterministic swim attrs), set FreddyBoatImage.Position X, fire DropButton.Activated when aligned → round ends → wait out DeedeeReturnAt (120s) → re-touch NPC. |
| AutoBuyByte | KEEP | dropdown (all ByteInventory.Names) + loop: if not Owned and FazTokens >= Price → ByteInventory.Purchase(plr, name) + FnafWorldSaveClient.AutoSave (exactly the game's own buyByte flow). |
| Mendo upgrades / flipside travel / shop menus / announcements / cutscene / cosmetics | REMOVE | one-shots, UI duplicates, §11. |

## 7. Conventions for the build

- Template 919: head 1-846 verbatim, game section after AntiAFK wiring (before
  MenuGroup), tail verbatim. validate = head846/tail73... (per PL1 actual:
  head846 + section + tail; validate.sh reports head/tail lines).
- Elements directly on TB_Tabs.Autofarm.T1, plain ids, elements-first, Thread +
  SafeLoop wiring, pcall per step, 0 comments, no invented labels.
- GUI/button firing = fire_event helper (firesignal → getconnections Fire),
  §12.2.1 ordering. No hooks needed in this game (no macro system — §16: plain
  "next game" = no genre carryover).
- Module access via GetSafeModule on the real instances (cloneref'd Services
  fine — no rawequal gates anywhere in this game).

## 8. Open questions / risks

- Challenger battles interrupt AutoBoss farming mid-TP (EncounterPending) —
  AutoBattle handles them (battle gui enables, moves fire; victory → Complete
  → unlock). AutoBoss waits while battle gui Enabled.
- regular-battle chain (victory → ChallengerRoll) has no client starter in
  this build — boss touches are the only farm entry; documented, not worked
  around (ForceChallenger is dev-gated).
- Boat X writes persist (render loop only moves on input) — verified
  FishAnimator/DeedeeMinigameController read loops.
- Fish catch tolerance: aim = predicted fish X mid-drop; fish move ≤0.06 scale
  over the 0.55s drop; tolerance 0.03 scale (plunger catch rect 44% width +
  fish width ≈ 0.04-0.06 half-width band).
- DeedeeReturnAt 120s bypass (client attr) documented, not shipped.
