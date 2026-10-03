# Shigaku analysis (SH1) — [UPDATE] Shigaku, Public 71c4793 (2026-10-03)

Game type: **school-life RP + fist-combat sandbox** (Shigaku = private school). Single
place. Client deobf 258k lines, dump 107k lines. No reference scripts in the zip →
ONBOARDING §3 **standard autofarm only**. No Template.lua in the zip → canonical
`work/lua/Template.lua` (909 lines, game section goes between L836 antiAFK end and
L837 MenuGroup; head 836 verbatim + tail 73).

## 1. Architecture

- **Networking = BridgeNet2** (`ReplicatedStorage.Packages.BridgeNet2`, package
  folder `ReplicatedStorage.ffrostflame_bridgenet2@1.0.0` with `metaRemoteEvent`
  + `dataRemoteEvent`). Every system multiplexes over ONE ClientBridge per name.
  Bridge names are defined in **Game_Settings** (`ReplicatedStorage.Shared.Modules.
  Global.Libraries.Game_Settings`) as `<System>.Bridge` — ~60 bridges total.
  Client resolves: `ReferenceBridge(Game_Settings.X.Bridge)` → `bridge:Fire(payload)`.
  Payloads are plain tables, usually `{ T = "..." }` or `{ Action = "...", ... }`.
- **Data = ReplicaService** (`ReplicatedStorage.RemoteEvents.Replica*`). Client
  reads via the game's own `Client.Data` module: `Data.Get({ "Path" })`,
  `Data.OnSet(path, fn)`, `Data.IsReady()`, `Data.OnReady`. Key paths (census):
  `Style`, `StyleShiny`, `Rerolls`, `Cash`, `Kills`, `Class`, `Steps`,
  `WorkoutSeconds`, `PlaytimeSeconds`, `Slots.Characters[i]` (character fields:
  FirstName/Gender/Height/Hair/HairColor/FacialHair/Ethnicity/Eyes/Mouth/
  Accessories[point]/FightStyle/…), `Slots.Active`, `Slots.Owned`, `Vip`,
  `LaunchBonusClaims`, `LaunchBonusEligible`, `GroupRewardClaimed`, `SpendClaims`,
  `FirstBuys`, `MachineUnlocked`, `HandleCredits`, `Phone.*` (huge subsystem).
- **Input = the game's own action system**: `PlayerScripts.Client.Input` module
  (require-able) with `Input.Bind(id, began, ended)` / `Input.Fire(id, state)` /
  `Input.IsDown(id)`. Firing an action runs the game's own bound handlers with
  full fidelity (combo state, guards, cooldowns, hitboxes). Action ids in
  `PlayerScripts.Client.Input.Actions` (e.g. `Combat.Attack`, `Combat.Block`,
  `Combat.Critical`, `Combat.Equip/Unequip`, `Gym.LeanLeft/Right`, `Gym.Stop`,
  `Move.Sprint`, `Move.Dash`, `World.Carry/Grip`, …).
- **Server authority notes (Combat)**: `Game_Settings.Combat.Authority` = RangeSlack 4,
  FacingDot 0, LineOfSight true, SwingSlack 0.25, PaceSlack 0.75, PingCap 0.35 —
  the server validates hit reports loosely; the Hit wire is client-composed
  (Targets list + direction), classic trust-the-client surface.

## 2. Wire table (every row verified at its call site)

### Combat (bridge `Combat.Sync`, Game_Settings.Combat at L168449)

| Wire | Call site | Payload |
|---|---|---|
| Swing m1 | 6293 | `{ T = "Swing", Kind = "m1", Index = comboIndex, Id = swingId }` — combo 1..StringLength, Id = client incrementing counter |
| Swing crit | 6426 | `{ T = "Swing", Kind = "crit", Index = 1, Id = id }` |
| Hit | 5330 | `{ T = "Hit", Id = swingId, Targets = { userIdOrModel… }, Charge = ChargeTime(), DirX = look.X, DirZ = look.Z }` — Targets: player chars → UserId number; CombatDummy/Npc models → the Model INSTANCE |
| Guard | 6494/6793 | `{ T = "Guard", Up = bool }` |
| Sprint | 6813 | `{ T = "Sprint", Up = bool }` |
| Dash | 6961 | `{ T = "Dash" }` |
| Equip | 6159 | `{ T = "Equip", Up = bool }` |
| Fx | 6966 | `{ T = "Fx", Result = name }` |

Hitbox targets: `PlayerScripts.Client.Hitbox` `Query(hrp, {Range, Angle})` —
`GetPartBoundsInRadius(hrp.Position, sqrt(range²+16))` → models with Humanoid that
are other players OR tagged `CombatDummy`/`Npc` (Hitbox module L18315, targetOf
L18342). Range/Angle per style from `Game_Settings.Combat.Styles[style]`
(HitRange 6.5-7, HitAngle 0.6-0.65, AttackDebounce 0.31-0.38, StringLength 4).
Style resolution (CombatTag L18195 GetStyle): character attribute `FightStyle` →
Data `Style` → `DefaultStyle` "Basic".

### Character rolls (bridge `Character.Action`, Game_Settings.Network L170753)

Wire: `{ Action = name, Args = table.pack(...) }` (Character module L2200).
ClientActions list (L170760): Attend, Create, Delete, SetActive, SetName,
SetGender, SetAccessoryAdjust, ClearAccessoryAdjust, SetAccessoryVanity, SetHair,
RerollField, RedeemHairColor, RedeemAccessory, RedeemEyeColor, RerollFightStyle.

| Action | Call site | Args |
|---|---|---|
| RerollField | 34589 via fireRoll 34570 | `(activeSlotIndex, fieldName, confirmRareBool)` — slot = `Slots.Active` via Character.GetActiveIndex(); field = "Height"/"Hair"/"HairColor"/"FacialHair"/"Ethnicity"/"Eyes"/"Mouth"/"Ringtone"/…; confirm bool = true only when overriding the rare-loss warning |
| RerollFightStyle | 34585 | `(confirmRareBool)` |
| SetHair | (Character module generated fn) | see Stats menu usage |

Roll currency: Data `Rerolls` (Character.GetRerolls L2135). Cost = `rollCost`
(Stats L32720, Reroll.PickCosts per field, 0 if unnamed). Rare check =
`Shared.Modules.Shared.Appearance` (require-able): `Appearance.holdsRare(charTable,
field)`, `Appearance.styleHoldsRare(styleName, styleShinyBool)` (StyleRarity →
Rarity Weights order, shiny always rare) — Stats L32308-32317.
Fight styles: `Game_Settings.Combat.Styles` = Basic (Common), Karate (Uncommon),
Boxing (Uncommon), "Fist of Flowing Water" (Epic), "Tae Kwon Do" (Epic), plus
weapon styles (Bat, …) with `Weapon` table. StyleCycle at L168794.
`Character.Reject` bridge delivers `{Action, Reason}` rejections (L35917 gate:
reroll actions debounced client-side).

### Gym (bridge `Gym.Sync`, Game_Settings.Gym L170607)

| Wire | Call site | Payload |
|---|---|---|
| Start | 103732 | `{ T = "Start", Station = stationInstance, Weight = weightModelName }` — station = tagged model (CollectionService: GymBench/GymDeadlift/GymTreadmill/GymDumbbell), Weight = the weight Model's NAME (weightRows L103365: `Id = v1.Name` from GymWeights.List) |
| Fail | 102733 | `{ T = "Fail" }` (dropped the lift) |
| Stop | 102762 | `{ T = "Stop" }` (exit) |
| Server→client Begin | 103190 (listener) | `{ T = "Begin", User, Station, Anim, Ratio, Rate }` → game starts the local minigame |
| Server→client End | 103224 | `{ T = "End", User }` |

Weights: `Shared.Modules.Shared.GymWeights.List(folderName)` → `{Name, Weight,
Template}` from `ReplicatedStorage.Files.Assets.Models.<WeightFolder>` (model
Weight attribute). Capacity/band: `Shared.Modules.Shared.Muscle` —
`Muscle.Capacity(workoutSeconds)` (Zones.Workout tiers L170555: Untrained 45 LB →
Relentless 245 LB), `Muscle.Assess(weight, seconds)` → "Comfortable"/"Struggle"/
"Locked". Progress field = `Workouts` (count), seconds field = `WorkoutSeconds`.
Kinds: Bench(Balance→Health), Deadlift(Grip→Health), Treadmill(Stride→Stamina,
speeds walk/jog/run/sprint), Dumbbell(Reps→Damage).
Minigame taps go through INPUT actions: `Gym.LeanLeft`/`Gym.LeanRight` → `side(±1)`
(L102812-102820) → routes to Balance.Nudge / Grip.Regroup / Stride.Press /
Reps.Tap (Reps only listens to LeanLeft, L102809). Reps band = 1.2-2.0 taps/s
(L170731: Max 3, BandLow 1.2, BandHigh 2, Smooth 0.5, Hold 0.16, Drift 0.22) —
midband ≈ 0.625 s interval keeps InBand true, level rises, session survives.

### One-shots & QoL (mostly Rule 11 REMOVE)

- `Codes.Action` `{Action="Redeem", Code=str}` (L31221) — manual code entry; REMOVE.
- `Spending.Action` `{Action="Claim", Tier=k}` (L34169) — spend-tier claim buttons; REMOVE.
- `Servers.Action` `{Action="List"}` / `{Action="Join", JobId}` (L30377/30203) — server browser; REMOVE.
- `Vending.Action` `{Action="Buy", Drink=id}` (L49976) — one-shot buy; REMOVE (needs Cash anyway).
- `GroupReward.Action`, `LaunchBonus.Action` — one-time claims; REMOVE.
- Hygiene (Hygiene.Sweat bridge, sweat/stink/shower cosmetics, L169694) — cosmetic
  state, shower = walk under prompt; REMOVE (no automation value).
- Sports (Basketball/Volleyball/Archery/Soccer/Rhythm matches) — stateful
  multiplayer matches, low automation value, out of standard-autofarm scope.

## 3. Feature plan for SH2 (Rule 11 filter applied)

Standard autofarm = the game's core grind loops. This game's core progression:
**fight-style unlocks/rolls + combat practice + gym training**.

1. **Auto Attack** — CombatDummies via the game's own input actions. Loop:
   nearest `CombatDummy`-tagged model (skip Knocked/Duo behavior) → TP near +
   face → ensure equipped (`Combat.IsActive` via Data Style/attribute check +
   `Input.Fire("Combat.Equip", true)`) → `Input.Fire("Combat.Attack", true)` paced
   by the style's `AttackDebounce` (require Game_Settings, never hardcode).
   The game's own guarded attack fn handles combo/anim/hitbox/wire — maximum
   fidelity, zero invented logic. Optional crit every `CritCooldown` (5s).
2. **Auto Gym** — Dumbbell (Reps) station: nearest GymDumbbell tag → TP to
   LiftPoint/station → fire `Gym.Sync Start` with Station=instance + Weight =
   best non-Locked weight (Muscle.Assess over GymWeights.List, heaviest
   Comfortable, else heaviest Struggle) → on server Begin (Connect the bridge),
   tap `Gym.LeanLeft` every 1.6/2 s → 0.625s (midband, from settings) → session
   runs until toggle off → `{T="Stop"}`. (Treadmill/Stride variant possible later
   via alternating LeanLeft/Right; Reps is the simplest + trains Damage.)
3. **Auto Roll** — character field rerolls with rarity stop: choose field from
   the rollable set (incl. FightStyle), loop while `Rerolls` > rollCost AND not
   `Appearance.holdsRare(active, field)` (FightStyle: `styleHoldsRare`) →
   `Character.Action Fire {Action="RerollField"/"RerollFightStyle", Args=...}`;
   stop + notify on rare/shiny. Confirm arg true ONLY when current is rare
   (re-roll-over-rare requires it — matches the game's own rareWarning flow).

Excluded per Rule 11: codes/spend-claims/vending/group rewards (in-game UI
one-shots), sports matches, hygiene, phone/gang/social. No stats labels
(Rule 23.2 — reference-less), no game-prefix ids (Rule 23.8), toggles only.

## 4. Module require paths (Rule 2 — require, never copy)

- `game.ReplicatedStorage.Shared.Modules.Global.Libraries.Game_Settings` (styles,
  gym kinds, combat tuning, network actions, phone/settings)
- `game.ReplicatedStorage.Shared.Modules.Shared.Appearance` (holdsRare,
  styleHoldsRare, StyleRarity, roll helpers)
- `game.ReplicatedStorage.Shared.Modules.Shared.Muscle` (Capacity/Assess/Tier)
- `game.ReplicatedStorage.Shared.Modules.Shared.GymWeights` (List/Find)
- `game:GetService("Players").LocalPlayer.PlayerScripts.Client.Input` (Bind/Fire)
- Bridge refs: `require(RS.Packages.BridgeNet2).ReferenceBridge(name)` — same as
  the game's own client code. Gym.Sync Connect for server Begin/End.

## 5. Gotchas

- BridgeNet2 Fire is method-call (`:Fire`) — dot-call hits fatalAssert.
- `Input.Fire` spawns ALL bound handlers (task.spawn) — don't spam faster than
  the game's own debounce; pace from settings.
- The Hit wire's Targets mixes UserId (players) and Model instances (dummies) —
  but Auto Attack via Input.Fire never composes this wire ourselves; the game does.
- Gym Start requires actually being at the station (server Begin echoes Station;
  presume proximity validation — TP to the station's `LiftPoint`/part first).
- Data.Get paths are ARRAYS (`{ "Style" }`), not strings.
- ReplicaService data may not be ready at exec time — use the game's Data module
  (IsReady/OnReady) or read lazily inside loops.
- CombatDummies to skip: DummyBehavior "Knocked"/"Duo" (CombatDummies module
  L4710); usable: Regular/Blocking/Parry/Attacker/Grapple.
