# [🌧️] Drop a Fruit — analysis (glm1, DF1)

Game: plot-based fruit tycoon + gacha rolls. Place fruit trees (entities) on your
plot → they drop fruits every `Config.Entity.Drop.Time` (6s) → fruits auto-Collect
into your coin bag after `Config.Coin.Bag.AutoCollectDelay` (15s) OR the player
carries/throws them into the plot HOLE for a coin bonus (`holeLevel` upgrade,
+10%/level via HoleUtil). Roll machine: FREE pulls → result = 1-6 entity slots →
`buy(slot)` pays the entity's Coin cost → entity to backpack → `place`. Rebirth
tiers (Coin target + required entities) → Crystal currency → rebirth upgrade tree
(autoRollMachine unlocks the game's own auto-roll). Weather events (Starfall =
collectible stars). Blitz = instant-drop N fruits per plant, cooldown ability.

Single place. No reference scripts, no Template in zip → ONBOARDING §3 standard
autofarm BOTH HALVES. Networking = TWO layers:

## Layer 1 — Remo containers (littensy/remo@1.5.3)
Client container: `require(RS.Shared.Remotes)` (ModuleScript `ReplicatedStorage.
Shared.Remotes`) → `createRemotes(...)`; call syntax `Remotes.ns.remote:fire(args)`
(lowercase, colon). RFs use `:request(...)` → Promise (none in our feature set).
Remote instances at `RS.Shared.Packages._Index.littensy_remo@1.5.3.remo.container.
<ns>.<event>`. Type-validated client-side (remo `t` checks — wrong payload errors
client-side; extra safety).

## Layer 2 — ReplicaService (Madwork client fork, RS.Shared.Modules.Replica.*)
- `ReplicaController` (RS.Shared.Modules.Replica.ReplicaController): `.RequestData()`,
  `.ReplicaOfClassCreated(class, fn)` (NEW replicas only — misses pre-existing),
  `._replicas` (PUBLIC map id→replica — the catch-up path; scan+filter each tick),
  `.GetReplicaById(id)`. Replica objects: `.Id .ClassToken .Tags .Data .Parent
  .Children` + `:FireServer(action, ...)` = `ReplicaRemoteEvents.Replica_ReplicaSignal:
  FireServer(replica.Id, action, ...)` (L33220-33229; server routes by Id).
- `Observer` (RS.Shared.Modules.Replica.Observer): `listenToChange(replica, "A.B",
  fn)`, `listenToNewKey`, `listenToArrayInsert` → return disconnect fn.

## Replica census (ClassToken → shape)
| Class | Data | Owner marker |
|---|---|---|
| Profile (Config.Player.Profile.ClassToken) | Stats{Coin,Crystal,Rebirth,Playtime}, Inventory{List=id→{Name,Level,Mutation,Placed}, Index{Fruit,Entity,Mutation,Combo}}, Upgrades, RebirthUpgrades, Timeskips, Roll, AutoRoll, Rewards{Daily{Day,LastClaim},Playtime{Start,Claimed},Group{Claimed},Index{Claimed}}, Tutorial{Completed,...}, Time{LastBlitz,...} | Tags.Player == LocalPlayer |
| PlotRoll | Player (Player instance), RollResult{Entities=array[slot]=name, Mutations=map[slot]=mutation, Time} | Data.Player == LocalPlayer |
| Fruit (children of PlotRoll) | Name, Seed, StartPosition, StartTime, State ("Resting"/"Falling"/"Thrown"/"Carried"/"Vacuuming"), Mutation, Scale | Parent.Data.Player == LocalPlayer |
| Entity | Tags.Id; visual replicas of placed trees | not needed (Inventory.List drives features) |
| Coin / CoinBag | coin flight visuals — NO replica fires | — |
| Weather (Config.Weather.ClassToken) | Active (weather name), Next, Stars=map[starId]={Position=Vector3, Collector=UserId?}, Collects=map[UserId]=count | single shared replica |

## Wire table (all call-site verified in the deobf)
| Feature | Wire (payload) | Call site | Client gate (game's own) |
|---|---|---|---|
| Auto Send to Hole | `fruitReplica:FireServer("SendToHole")` (no args) | L76839 Fruit.Prototype.SendToHole | fires on hole touch; dedup 0.5s; grabbable states Resting/Falling/Thrown (L82099 isGrabbable) |
| Auto Roll pull | `Remotes.plot.roll.pull:fire()` | L70550 RollStore | not rolling / not pending |
| Auto Roll buy | `Remotes.plot.roll.buy:fire(slotIndex 1-6)` (numberConstrained) | L88734 | RollResult exists, entity known, `Purchase.tryAfford`, not backpack-full (InventoryUtil.isBackpackFull, Max=1000) |
| Auto Place | `Remotes.entity.place:fire(entityId)` | L61448 Backpack UI | unplaced inventory entity; server enforces `entityPlaceLimit` (UpgradeUtil.getValue, levels {2..8,[0]=1}) |
| Auto Upgrade trees | `Remotes.entity.upgrade:fire(entityId)` | — (remote def L21735 remote(string)) | level < `EntityUtil.getMaxLevel(Upgrades, RebirthUpgrades)` (Base 5→Cap 50), cost `EntityUtil.getUpgradeCost(name, level, mutation)` = round(Upgrade.Cost.Amount × level × CostGrowth(1.5) × mutationCostMult) |
| Auto Equip Best | `Remotes.entity.equipBest:fire()` | L61037 Backpack UI | — |
| Auto Sell | `Remotes.entity.sell:fire({entityId, ...})` array, batches of `Config.Entity.Sell.MaxBatch` (200) | L61966 sellSelection (table.move chunks) | game's UI sells the manual selection; ratio 0.15 |
| Auto Buy Upgrades (Coin tree) | `Remotes.upgrade:fire(upgradeId)` | L65651 upgrade tree UI | node not owned (`Upgrades[id] == nil`), dependency met (`UpgradeUtil.isDependencyMet(id, Upgrades)`), `tryAfford(Coin)`; ALL 98 nodes cost Coin; TutorialUpgradeLock during tutorial → skip while `Tutorial.Completed ~= true` |
| Auto Rebirth Upgrades (Crystal) | `Remotes.rebirth.upgrade:fire(id)` | L63796 | level < #Levels, `Stats.Rebirth >= RequiredRebirth`, cost Levels[level+1].Cost (Crystal) |
| Auto Rebirth | `Remotes.rebirth.perform:fire()` | L64007 | `RebirthUtil.getTargetProgress(Stats.Rebirth)` (Coin target or nil=maxed) + tryAfford Coin + `RebirthUtil.hasEntityRequirement(data)` |
| Auto Blitz | `Remotes.blitz.activate:fire()` | L89353 Blitz tool | cooldown: `Time.getServerTime() - (Time.LastBlitz or 0) >= UpgradeUtil.getValue("blitzCooldown", ...)` (300→180s); effect = instant drop blitzAmount (10-30) fruits per plant |
| Auto Collect Stars | `Remotes.weather.collectStar:fire(starId)` | L75336 WeatherStar | player within CollectRadius (horizontal) + ±10 Y; 0.3s debounce; `Collects[userId] < Config.Weather.Meteors.MaxCollects`; star.Collector == nil. TP to star.Position then fire (mirrors game flow) |
| Auto Claim Daily | `Remotes.reward.daily:fire()` | L62550 | `ClaimableDay` UI state ← Daily.Day/LastClaim vs `Config.Rewards.Daily.Time.Reset` (86400); fire once per detected reset |
| Auto Claim Group | `Remotes.reward.group:fire()` | L87766 | `Rewards.Group.Claimed ~= true` (server verifies membership) |
| Auto Claim Playtime | `Remotes.reward.playtime:fire(milestoneKey)` | L62173 | not `Playtime.Claimed[tostring(k)]` and `getUTC() - Playtime.Start >= milestone.Time` (milestones = Config.Rewards.Playtime map) |
| Auto Claim Index | `Remotes.reward.index:fire(goalKey)` | L63283 | IndexRewardUtil.getGoals(data) → {Key, Mutation, Rarity, Target}; `getFound(data, Mutation, Rarity) >= Target` and not isClaimed |

## REMOVED per Rule 11 (named so nobody re-wires them)
- code.redeem (RF, one-click UI), timeskip.use/play (consumable one-click; player
  may hoard), pack.open (one-click per gifted pack), offline.claim (once per
  login, UI locks until claimed — one click), plot.fountain (NO client call site —
  Cmdr-admin alias only), boost.requestServerLuck (data-sync fired by game UI
  itself), session.idle / effect.play / settings.set / tutorial.* / updateLog.seen
  / leaderboard.update / marketplace.* / notification / chat.system / rsvp.* /
  Store.* (telemetry/UI/purchase), Cmdr (admin), Replica data-sync events, Fruit
  Fell/SetCarried/SyncPosition/Throw/SetVacuumed (transport actions — SendToHole
  is the value action; carrying is the manual chore we SKIP, not automate).
- The game's own autoRoll remote cluster (plot.autoRoll.*): needs autoRollMachine
  rebirth unlock; our own pull/buy loop provides the same automation from game
  start with plain wires (same shape the game's auto uses: Config.Roll.Auto.Delay
  0.35s between result and next pull).

## Canonical module requires (Rule 2 — never reimplement)
`RS.Shared.Remotes` (remo container) · `RS.Shared.Modules.Replica.ReplicaController`
(_replicas scan) · `.Observer` (listenToChange) · `RS.Shared.Config` {Entities,
Rarities, Mutations, Roll, Rewards, Upgrade.Tree, Rebirth, Weather, Player.Profile}
· `RS.Shared.Modules.Game.Util.{EntityUtil, UpgradeUtil, RebirthUtil,
IndexRewardUtil, AutoRollUtil}` (AutoRollUtil.getEntries("Rarity"/"Mutation") =
sorted dropdown values, skips Hidden mutations) · `RS.Shared.Client.Modules.Util.
Purchase` (canAfford(data, type, amount)) · `RS.Shared.Modules.Core.Time`
(getServerTime/getUTC) · InventoryUtil (isBackpackFull / getPlacedEntities —
RS.Shared.Modules.Game.Util.InventoryUtil).

## Key numeric facts
Drop.Time 6s · Coin.Bag AutoCollectDelay 15s (game auto-collects) · Backpack.Max
1000 · Sell.MaxBatch 200 / Ratio 0.15 · Entity.Level Base 5 Cap 50 · rollSlot
1-6 · Pity: Mythic from 200 pulls (+0.01/pull, max 3) · Roll.Luck BaseLuck 1 ·
holeLevel +10% coin/level · Offline 1800-28800s @0.35x · Rebirth tiers
350/50k/1M/15M/200M/3B/25B/300B Coin.
