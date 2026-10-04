# Plunder [UPD] + Zone Zero — Analysis (PL1-A, glm1, 2026-10-04)

Public d119454 = `plunder/` two folders: "Plunder [UPD]" + "Zone Zero".
Deobfs 227,920 / 227,825 lines (~95-line version drift), dumps 6.4MB /
11MB. **No reference scripts, no Template in folders → §3 standard
autfarm, canonical work/lua/Template.lua.**

## 1. Identity — one engine, two game places (NOT game/lobby pair)

- BOTH places have `Workspace.GameArea.Lobby` + `GameArea.GameScene`
  (SceneRoot constants: AREA="GameArea", LOBBY="Lobby",
  GAME_SCENE="GameScene", L44169/L180587). Each place is a FULL game:
  lobby + heist scene in one.
- Wire-name sets are **IDENTICAL** (59 named TEvent remotes in both
  deobfs — verified full-set diff). Zone Zero = newer/bigger content
  (dogs: Bulldog/Hound/Husky + PPSh39; 366 EvacuationPoint mentions vs
  Plunder's 46).
- Genre: **extraction heist**. Break in (Glass panes, DoorRuntime),
  loot containers/safes/world items, extract at LeavePoint prompts.
  Chickynoid server-auth movement (custom sim — Humanoid walks do not
  apply; TPTo still works: it sets HRP CFrame, server sim follows).
  PvP weapons (Gun/Grenade/Melee via Chickynoid commands), DBNO +
  rescue, squads, trading, store/vault, gacha (Gloves, SkeletonCrew).
- **Build decision: ONE script in BOTH folders** (Potato/Periastron
  precedent) — identical wire surface, features no-op where world
  objects absent (§22.1).

## 2. Transport — TEvent over Postie (§2: use the game's own module)

- Only REAL RemoteEvents in the dumps: `ReplicatedStorage.PostieSent` /
  `PostieReceived` (+ JABBY_REMOTES dev-tooling, GameAnalytics*,
  FastFlags/ABTests Update — all Rule-11-excluded noise).
- `Shared.Core.TEvent` (L74862) = the wire framework: `require(TEvent)`
  → `.Setup()`, `:FireRemote(name, ...)`, `:OnRemote(name, fn)`,
  `.Remote.new(name)` → object `:FireServer(...)` + `.OnClientEvent`,
  `.Bindable.new(name)` / `:FireBindable`, `.coverBy(name)` (streamed
  sync), `.OnBindable`. TEvent's own body is `require(script.Module)` —
  Module child is RUNTIME-INJECTED (absent from dump+deobf) → the
  Postie packet layer is invisible. **§2 solution (Potato precedent):
  never touch Postie; require the game's TEvent and use its API —
  `require(game:GetService("ReplicatedStorage").Shared.Core.TEvent)`.**
  Do NOT call `Setup()` again (ClientLoader already ran it once;
  double-Setup risk unverified — avoid).
- Postie protocol reference (for harness mocks): client fires
  `PostieSent:FireServer(event, name, id, ...)`-style; TEvent.Remote
  objects multiplex over it by name. Exact field order lives in the
  runtime-injected Module — mock at the TEvent API level instead
  (Remote.new(name) returns object; recorder on FireServer; dispatcher
  for OnClientEvent), exactly how harness_lib mocks Remotes.
- State-sync backbone: `Shared.Core.Value` over `"_value_remote_"`
  (L83008-83060): named ValueInstances, versioned diffs, "All"
  snapshot. Key instance: `Value.InGame` (callable + `.Changed`) =
  in-match gate used by many features (L59934 etc.).
  `require(RS.Shared.Core.Value).InGame()` → in-game bool.
- WorldItem streaming: `Remote.new("WorldItem/Register")` /
  `"WorldItem/Remove"` + `coverBy("WorldItem/Sync")` (SyncClient
  L92913). Registry records: `{id, meta={model=..., sourceInteractId=
  ...}, localRoot, cf, stateFlag, hidden, lastNow, lastSeq}`. Parts in
  workspace carry attribute **`WorldItemId`** (number) mapping to
  registry ids.
- `Registry` singleton (RS.Client.System.WorldItem.Registry, L92749):
  `Get(id)`, `GetAll()`, `GetVisible()` — populated by the game's own
  SyncClient at runtime. **require() it — cached singleton, same table
  the game uses** (Potato ToolEquipController precedent).

## 3. Action-wire census (client→server, call-site verified)

| Wire (TEvent name) | Payload (verbatim from call sites) | Sites | Rule 11 verdict |
|---|---|---|---|
| `ToolPickupAction` | `:FireServer("pickup", record, workspace.CurrentCamera.CFrame.Position, pointOrNil)` — record = Registry record (client always passes the full record; server reads its fields), point = `WorldItem.PickupPoint.Encode(boxCFrame, boxSize, hitPos)` object-space fraction or nil | L93062/93067 (ToolPickup), prediction layer PickExchangePredict L94109 (cosmetic — fires same wire) | **KEEP — AutoPickup** (core automation) |
| `ContainerAct` | `ContainerState.Act(payload)` injects `cameraPos` then `:FireServer(payload)`. Payloads: `{op="open", cid}` (+ optional 2nd arg = search/takeover attr from prompt), `{op="takebest", cid}` (L182067, L183493), `{op="sell", cid, uid, bulk}` (L187543), MOVE `{op, cid, uid, x, y, rot}`, TRANSFER `{op, from, to, uid}`, EQUIP `{op, cid, uid}`, UNEQUIP `{op, slot, uid}`, DROP/LOCK/SORT/LOAD/UNLOAD variants | Act def L170162; open L113685/116135/116514; UI controller region L166k-188k | **KEEP — AutoSearch (open+takebest), AutoSell** (sell panel bulk flag) |
| `ExtractHold` | `FireRemote("ExtractHold", true)` at hold begin → `FireRemote("ExtractHold", false)` on release → `FireRemote("ExtractHold", "done")` on prompt Triggered. Prompts = CollectionService tag **"LeavePoint"** on ProximityPrompts (Extract TAG, L37957); range = `prompt.MaxActivationDistance + 4` slack; disabled check = attr `ExtractDisabled`; hold duration = prompt.HoldDuration clamp 1-60 default 5 | ExtractHandle L141792-141828 | **KEEP — AutoExtract** |
| `InteractableAct` | `:FireServer(interactId, workspace.CurrentCamera.CFrame.Position)` — interactId = instance attr **"InteractId"** (number); range attr "InteractRange" default 8 (server scale 1.5) | L117094-117100 (fireInteract) | **KEEP — AutoInteract** (doors/cabinets/elevators on the loot path; gates loot flow) |
| `ReconnectChoice` | `FireRemote("ReconnectChoice", "return")` / `"abandon"` — DBNO reconnect accept/deny | L191112/191120 | **KEEP-lean — AutoRequeue part** (auto-return on death) |
| `MatchResultChoice` | `:FireServer("lobby")` / `"spectate"` — post-match result choice | L109891, fires L110398/110424 | **KEEP-lean — AutoRequeue part** (return to lobby to re-queue) |
| `MatchAreaLeave` | `:FireServer(zoneId)` — leave a match-area zone | L120441-120446 | keep-lean inside AutoRequeue decision (flag: only if needed for the loop) |
| `GlovesAct` | `{op="roll"}`, `{op="rollTicket", count=n}`, `{op="equip", id=num}` | Net L40976-40982 | **KEEP-lean — AutoRoll** (gacha class; currency-gate at server, Err codes exist) |
| `SkeletonCrewAct` | `{op="draw", count}`, `{op="claim"}`, `{op="refresh", slot}`, `{op="submit", slot}`, ~~`{op="robuxDraw"}`~~ | Net L43737+ | draw/claim/refresh **KEEP-lean** (gacha); **robuxDraw REMOVE** (ROBUX) |
| `StoreAct` | `{op="vault"}`, `{op="testAurora", id}`, `{op="market"}` | Net L41194-41199 | vault **KEEP-lean** (deposit stash = automation); testAurora/market REMOVE (UI one-shot / store browse) |
| `ItemShopAct` | `{op="buy", id}` | Net L37778-37782 | REMOVE (manual player-choice buy; flag for user order if "auto-buy best gear" wanted) |
| `Purchase` | `FireRemote("Purchase", marketRowId)` — Store market products (gamepass/asset) | L191846/193904 | **REMOVE** (ROBUX-class) |
| `ToolEquip` / `ToolThrow` | weapon equip/throw commands (Chickynoid toolbar) | L139125/171885 | REMOVE (manual combat) — unless a future AutoKill order (needs Chickynoid weapon-sim RE, deep) |
| `SelfReset` | no args — game's own character reset (Roblox reset broken under Chickynoid) | literal FireRemote | REMOVE (game UI has the button; one-shot duplicate = Rule 11 clutter). FLAG: if user wants reset-on-stuck, cheap to add. |
| `DBNORescueRequest/Start/End`, `DBNOHelpRequest` | victimUserId social rescue | L130805+ | REMOVE (requires other players, social) |
| `Setting_Change/Setting_Crosshair/Setting_Refresh`, `KeyBind_Change`, `ButtonLayout_Load/Save` | client settings | L~74xxx/124256 | REMOVE (client-side prefs) |
| `FlashlightState`, `EmotePlay`/`EmoteStop`, `ToolPickupAction` non-pickup branches | cosmetic | L59939, L40861-40864 | REMOVE |
| Telemetry: `ClientLoaderReady`, `OnboardingGuideReport`, `NewcomerGateShown`, `ExtractTipShown`, `ClickGuideLootClicked`, `ClickGuideTakeBestClicked`, `HealHintReport`, `SafeLockReport`, `LeaveIntentReport`, `LobbyInteractReport`, `ToolbarUseReport`, `OnboardingGuideReport` | analytics | scattered | **REMOVE** (Pintail-class) |
| `WorldItem/Mark` | player marker ping | Remote.new site | REMOVE |
| `DebugManagerCtrl`, `NetTrafficCtrl`, `DebugTileSync`, JABBY, Cmdr-equivalents | dev tooling | L122121 etc. | **REMOVE** (admin/dev) |

## 4. State events (server→client — logic inputs, not wires to fire)

`MatchStart` (x2), `MatchAreaSync` (zones), `MatchResultShow`,
`ExtractAbort`, `ExtractElevatorDoor`, `Transport` (server TP —
server-driven, do not fire), `TeleportAsync`, `PlayerBodyDeath`,
`ReconnectOffer`, `DBNODummySync`, `DBNOHelpBroadcast`, `EnemyDeath`,
`EnemyCorpseRemoved`, `KillNotice`, `GunHitConfirm`, `GunTuningChanged`,
`BossBar`, `Spectate*` family, `Setting_Refresh`, `BagItemPicked`
(itemId, position, uid — pickup confirm), `ToolPickupAction` OnClientEvent
("deny", uid, reason), coverBy streams `EnemyHP`/`EnemyArmour`/
`SentryLaser`/`WorldItem/Sync`, Container Sync family
(`Bag`/`SafeCase`/`Stash`/`Toolbar`/`ToolbarMap`/`ToolbarRefs`/
`OpenContainer`), `_value_remote_` diffs (Value.InGame!), Container
DENY/OK events (`ContainerDeny`, `ItemShopDeny/Ok`, `StoreDeny`,
`ShopUpgradeDeny`, `SkeletonCrewResult/Deny`, `TradeState`).

## 5. Feature list for the build (PL1 — glm2's call, my recommendation)

Core (high value, fully verified):
1. **AutoPickup** — iterate `Registry.GetVisible()` (or GetAll filtered
   non-hidden), for each record fire ToolPickupAction pickup with the
   record + camera pos + nil point (nil = center — the game's
   FindPreferredItemId encodes a real point, but RequestPickup's arg2
   can be nil per signature; VERIFY in harness which the server
   accepts — prediction layer passes what encode returns, never nil...
   safest = pass nil and watch for deny, or mirror BagPickup's encode).
   Range gate: `WorldItem.OutOfRange(pos, charPos)`.
2. **AutoSearch** — proximity-prompt containers (tag "Interactable" /
   Container prompts) → `ContainerState.Act({op="open", cid=cid})` →
   wait → `{op="takebest", cid=cid}`. cid = container attr
   `Container.Rules.CID_ATTR` (string) on the prompt's parent model.
3. **AutoExtract** — find LeavePoint prompts (CS tag, not
   ExtractDisabled) → TPTo in range → FireRemote("ExtractHold", true)
   → wait HoldDuration → FireRemote("ExtractHold", "done"). On
   ExtractAbort → retry next tick.
4. **AutoSell** — sell panel logic: iterate container contents (Bag
   sync state), `Act({op="sell", cid, uid, bulk=true})` per sellable.
   Border: maybe restrict to SafeCase/Stash to avoid selling equipped
   gear — glm2's call, document choice.
5. **AutoRequeue** — on `Value.InGame()` false + MatchResultShow /
   PlayerBodyDeath / ReconnectOffer → MatchResultChoice "lobby" /
   ReconnectChoice "return" (guard rails: only fire when the
   corresponding UI state is actually active — the game shows the
   choice screen; fire-and-forget without state = server deny spam).

Lean (gacha/stash class — glm2 decides, each needs a currency/state
gate read from the game's own modules):
6. AutoRoll gloves (GlovesAct roll/rollTicket + equip-best?) — lean KEEP
7. AutoVault (StoreAct vault) — lean KEEP
8. SkeletonCrew draw/claim — lean KEEP if ticket-currency gate clean

Removed per Rule 11: everything in the table above marked REMOVE —
NOTHING else. The toggles ARE the UI; no labels, no invented controls.

## 6. Build conventions (fresh template 1df3865!)

- Template = **919 lines** now. User changes: (a) AddSliderToggle
  string-form REMOVED — only Config-table form works; (b) built-in
  **AutoJump** toggle at L706-718 (Player/Server groupbox). Re-read
  Rule 18 done here; glm2 MUST re-read Template.lua before building.
- Insertion point: game section after **L846**
  (`if Toggles.AntiAFK.Value then RunAntiAFK() end`), before
  `local MenuGroup` (L847). Expected validate: head 846 / tail ~18 /
  tail-changed = SaveManager folder line only.
- One script both places: `plunder/Plunder [UPD]/Plunder [UPD].lua` +
  `plunder/Zone Zero/Zone Zero.lua` (folder mode — user converted to
  folders in 0acfce8; script inside game folder; NO repack).
- TEvent require shape: `local TE =
  require(game:GetService("ReplicatedStorage").Shared.Core.TEvent)` —
  then `TE:FireRemote(name, ...)` / `TE.Remote.new(name)`. Requiring
  game singletons: Registry (RS.Client.System.WorldItem.Registry),
  ContainerState (RS.Client.Core.ContainerState), Value
  (RS.Shared.Core.Value) — all require-cached singletons, same tables
  the running game uses (§2, Potato precedent).
- Chickynoid: movement is server-sim. TPTo sets HRP CFrame (server
  reconciles). Anti-cheat posture unknown (no ServerScriptService in
  dumps) — client wire shapes are ground truth, exactly like Potato.

## 7. Open questions (flag, don't guess — §10)

- Exact server-side read of the ToolPickupAction record (which fields
  validated) — invisible; mitigation: pass the game's own record
  verbatim (byte-equal to what the game sends).
- PickupPoint nil-vs-encoded acceptance (5.1 above).
- TEvent double-Setup behavior — avoid calling Setup (game did it).
- Whether "done" alone completes extraction without prior "true"
  (hold-ordering) — mirror the game's exact sequence: true → wait →
  done; safest.

— glm1, PL1-A, 2026-10-04 ~16:05Z. Harness (PL1-H) next: TEvent mock
world + Registry/ContainerState/Value mocks + the 5 core features'
wire tuples.

## 8. Addendum — build decisions (PL1 executed by glm1 after glm2 no-response, 2026-10-04 ~17:00Z)

- glm2 never claimed PL1 (offline since 15:17 +0700, pre-dates the game
  upload); per the TASKS fallback note glm1 built it. glm2 gets first
  review / any wrap lane on return.
- **Dropped from v1 (§10, not verifiable)**: AutoSell — the sell wire
  (`{op="sell", cid, uid, bulk}`, L187543) carries a UI-selection context
  (SellSelectionModels); the sell-panel flow (which cid owns which uid at
  sell time, sell-zone gating) is not traceable from client code alone.
  Needs a user order or server-side intel. AutoVault (StoreAct vault) +
  SkeletonCrew draw/claim: same class, left out.
- **Included**: AutoRoll (GlovesAct Net.Op.ROLL via module) — the
  auto-gacha class (ST6 precedent), currency gate is server-side.
- **Listener-registration risk (documented assumption)**: TEvent.OnRemote
  multi-listener support is unverified (TEvent.Module runtime-injected).
  The build registers ONE OnRemote handler (ReconnectOffer) alongside
  the game's own — if OnRemote is overwrite-style this would break the
  game's handler. Natural framework implementation is Connect-based
  (multi-safe); MatchResultShow uses Remote.new().OnClientEvent (the
  multi-safe pattern) instead. Residual risk flagged; harness models the
  Connect semantics.
- **Listener late-registration fix**: the AutoRequeue listener block
  retries via task.spawn loop (module-wait pattern, §14.2 lazy-wait
  precedent) — TEvent.Module is runtime-injected; one-shot resolution at
  auto-exec time could silently skip listener wiring forever.
- Gates: luac OK / lint 0 err / validate head846-tail18-0comments /
  harness 25/25 on delivered bytes (both Public paths + canonical).
  Delivered Public 4b0000a.
