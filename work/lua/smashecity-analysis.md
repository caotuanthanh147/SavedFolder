# Smash the City — analysis (STC1)

Source: Public f1ceecd `Smash the City/` — deobf 100,744 lines (Players.LocalPlayer.
PlayerScripts.SmashClient + RS.Smash.* modules) + game_dump.txt 45,873 lines.
Single place. No reference scripts, no Template in folder → canonical Template.lua
**945 lines** (user pushed 4f0e766 3 min before the game upload: GetPosition shared
helper; TweenTo rewritten — yields, returns reached-bool, single-flight cancel via
Connections.ActiveTween, PlatformStand + noclip + velocity-zero in flight).

Genre: camera-based city destruction. Tap to fire weapons (Meteor/Nuke/MoonFall/...)
at a procedural city; broken cells/props earn coins client-side; coins buy
weapons/maps; cities reset/reload. Multiplayer rooms exist (SmashNet) but solo =
host, entire simulation client-side.

## Module map (RS.Smash.*, all requireable)

- `Config` — the master table: SHOP.EARN {cell=1,prop=10,other=5}, SHOP.MILESTONES,
  SHOP.WEAPONS (60 prices, Missile..MoonFall 0..200000), SHOP.MAPS (12),
  COOLDOWNS (weapon→seconds|{t,group,held,action,owner}), CHALLENGES.POOL
  (3/day), DAILY streak table, PASSES, GROUP, MEGA, ROBUX.TIERS, SKIP_COOLDOWN
  {product,robux=25}, MINI_NUKE {product,robux=5,radius=70}, SERVER_NUKE
  {product,robux=99}, CODES {SMASH=5000}, CITY_HALF=440, GROUND_Y=0,
  dev UserId allowlists (INFINITE_COINS/EDITOR.users/WORKSHOP.admins/STREET.users/
  TUTORIAL.always — server-mirrored, client-writes don't replicate).
- `Core.Economy` (str8) — **the whole economy is client-authoritative**: cash in a
  module-local (num1), owned in tbl4 {weapon={},map={}}, passes tbl5; `earn(n,kind)`
  adds locally; `buy(kind,id)` deducts locally + marks owned + flush; `setCash(n)` /
  `unlockAll()` / `wipe()` PUBLIC; `price/canAfford/owns/hasPass/multiplier/
  boostLeft`; RF wrappers claimDaily/claimChallenge/redeemCode/gift; robux wrappers
  buyRobux/buyPass/buyPack/skipCooldown/buyMiniNuke/buyServerNuke; `update(dt)`
  = takeBroken→earn + flush every 10 ticks (called by SmashClient every 0.25s);
  `onChanged(fn)` listeners (cash, delta, kind, info); `setSaveExtra(fn)` → save
  ch/flags builder (set by Challenges); init: Load RF → {cash,tester,infinite,
  canWipe,boostUntil,passes,owned,group,...}; Granted OnClientEvent → wipe/fix/
  reward/pass/cash corrections.
- `Core.Cooldowns` (str7) — PURE client-side: specs copied from Config.COOLDOWNS at
  require time into module-local tbl2 {id→{t,key,held,action,owner}}; state
  {ready,busy,total,by} per player; spec/left/holder/use/release/apply/load/new.
- `Core.Destruction` (str2) — the sim: node tables, `blast(pos,radius,force,opts)`,
  `takeBroken()` {cell,prop,other}, `takeDestroyedIds()`, `getStats()` →
  {total,intact,debris,chunks,active,pressure,destroyed=1-intact/total},
  destroyIds/vaporize/forEach/isFrozen/isCell.
- `Core.Challenges` — day-based 3/3 from CHALLENGES.POOL; client-tracked prog
  (saved via ch={day,prog}); `challenges()` → {list={{i,id,text,kind,goal,prog,
  reward,claimed,done}...}, nextIn}; `daily()`; `claimDaily()`; `claimChallenge(i)`
  → Economy.claimChallenge(i, prog) → ClaimChallenge RF; weaponUsed/broken/earned/
  cityProgress bumpers; tick(dt,coop) day rollover.
- `Core.UI` (str4) — `build({categories, weapons, maps, callbacks})` stores
  **callbacks at MODULE scope** (tbl1 upvalue of every UI fn). SmashClient passes
  tbl11 = {onSelect(id) [owns-checked → select], onReset [loadMap same],
  onNextCity=goNextCity [buy-if-locked → loadMap], onResults("reset"/"next"),
  onGoIn/onGoOut/onEditor/onWorkshop/onServerNuke, canWipe, onRedeemCode,
  getLeaderboard, ...}.
- `Core.Input` (str5) — `start(cameraRig, adapter)` stores the **adapter at module
  scope** (var2 upvalue of start): {pick(x,y), getWeapon(), call(method,pos) →
  use(method,pos), key(KeyCode)}. adapter.call("onTap", worldPos) fires the
  CURRENT weapon through the game's full pipeline (MIN_GAP 0.1s rate limit →
  cooldown gate num4 → call() → weapon.onTap(env,pos,settings) → usedWeapon).
- `Core.Net` — rooms: sendAct/sendBuild/sendSync/sendStats/spectate/join over
  SmashNet.Net; role host/spectator; canAct/home. Solo: host, everything local.
- `Core.Kit` — VFX/construction toolkit (projectile/trail/missile factories).
- Weapons: `RS.Smash.Weapons.<Category>.<Id>` ModuleScripts, spec shape
  {id,name,category,input="tap",settings={{id,label,min,max,default,step}...},
  onTap(env,pos,settings),onSelect,onDeselect,...}. Nuke: settings Radius 60-170
  def 110; onTap → destruction.blast(pos, Radius, ...) — settings read UNVALIDATED.
  SmashClient builds registry var59[id]→module, state var60[id]→{Radius=110,...}
  (defaults), sorted list var61; select(id) switches (UI setSelected); the game's
  own Nuke trial sets var60.Nuke.Radius programmatically (L2340s).

## Wire table (verified at call sites, Rule 2)

Client→server (all under RS.SmashRemotes / RS.SmashNet):
- `Save:FireServer({cash=math.floor(num1), owned={"kind:id",...}, ch={day,prog},
  flags})` — L47536 flush(); fired every 10 update ticks (~2.5s) when dirty.
  **CLIENT-AUTHORITATIVE STATE PUSH** — cash/owned/challenge state all client-computed.
- `BuyRobux:FireServer(kind,id)` — L47570s — ROBUX product → REMOVE
- `BuyPass:FireServer(passId)` — ROBUX → REMOVE
- `BuyPack:FireServer(packId)` — ROBUX coins → REMOVE
- `SkipCooldown:FireServer(weaponId)` — ROBUX product (25 R$) → REMOVE
- `MiniNuke:FireServer()` / `ServerNuke:FireServer()` — ROBUX (5/99 R$) → REMOVE
- `TestWipe/TestDay:FireServer()` — tester-gated (bool4/bool6 come from Load
  response — server flags, not client-forgeable) → REMOVE
- `Likes`, `Street:FireServer(...)` — social / dev-gated StreetView → REMOVE
- `SmashNet.Net:FireServer({type="act"|"build"|"sync"|"stats"|"join"|"spectate",
  ...})` — room sync; the game fires it itself; our loop needs nothing from it
- `SmashNet.Cursor:FireServer(...)` — room cursor replication (game-fired)

RemoteFunctions: `Load:InvokeServer()` (save state), `ClaimDaily:InvokeServer()`
({ok,coins,state?}), `ClaimChallenge:InvokeServer(i, clientProg)` (client-supplied
prog; server is the payer), `GroupCheck`, `Gift`, `Leaderboard`, `MyRank`,
`RedeemCode(code)`, `UserMaps`, `Workshop`.

Server→client: `Granted:OnClientEvent` (wipe/fix/reward/pass/cash grant corrections)
— the only server authority channel; normal flow trusts the client push.

## ESC — exploit surface beyond remotes (§26 census)

- **§26.1 Attributes**: `NoCooldowns` on LocalPlayer — client-READ cooldown gate
  (cooldownInfo L495: passLeft grace when set; server sets it for pass owners —
  a local SetAttribute emulates the pass locally). NOT wired (weaker than §26.4
  spec-zero; also triggers robux offerSkip prompts). `SmashDebug` LocalPlayer
  attribute — Studio-gated backdoor console dispatcher (L3792: GetAttributeChanged
  → fn32 command → SmashDebugResult) — wiring never connects on live clients, but
  the commands (cheat/unlockall/wipe/redeem/skipoffer/net) prove the APIs. UI attrs
  (Base/Panel/TrackId/...) = cosmetic. RoadX0/RoadX1 = city geometry. Workspace
  BoardCount/RankTest = server-set dev strings. CHECKED.
- **§26.2 Save system**: THE headline. Entire save = client-computed (cash/owned/
  ch/flags) pushed via Save remote every ~2.5s when dirty; server Granted can
  correct but normal flow trusts. The game's OWN Studio console ports prove the
  exploit path: `cheat <n>` → setCash(cash()+n) (default 1e6), `unlockall` →
  unlockAll(), `wipe` → wipe(). All PUBLIC on Core.Economy (requireable).
  → WIRED: CheatCash (input+button, game's own command ported), UnlockAll
  (button), AutoBuy (Economy.buy cheapest-first loop), AutoClaim (ClaimDaily +
  ClaimChallenge RFs via Core.Challenges).
- **§26.3 Mutable client-trusted tables**: Config.SHOP.EARN (earn rates — mutation
  would inflate earn through the game's own pipeline; NOT wired: setCash is the
  game's own cleaner API for the same result). Config.COOLDOWNS (pre-copied into
  Cooldowns at require-time — mutating Config after load is a no-op; mutate the
  module's spec table instead, §26.4). var60 weapon settings (Radius read
  unvalidated by onTap; at-max reachable via the in-game slider = Rule 11 remove;
  beyond-max via hookfunction(weapon.onTap) documented — NOT wired, marginal
  value vs GC/hook complexity).
- **§26.4 Module hooking / no-cooldown**: Core.Cooldowns spec table (single
  upvalue of `Cooldowns.spec`) — zero every `.t` → use() sets ready=now+0 → left()
  = 0 → gate always passes; fully reversible (save originals, restore on off).
  → WIRED: NoCooldown toggle. (Attribute-forge alternative documented above.)
- **§26.5 NaN/inf**: Save payload cash is a bare number — direct
  `Save:FireServer({cash=0/0, owned=...})` = NaN persistence probe (server
  handling unknown, no server code in dump — 0 ServerScriptService hits).
  PROBE-CLASS, documented NOT wired.
- **§26.6 \255**: owned entries are client-built strings "kind:id" — a direct
  Save fire with `"weapon:\255"` in owned = rollback-dupe probe IF the server
  persists verbatim. PROBE-CLASS, documented NOT wired.
- **§26.7 Ownership/replication**: no character/humanoid gameplay (CameraRig
  game — TPTo/TweenTo not needed by any feature); cursor replication is
  room-scoped. CHECKED, no play.

## Access chains (§2 — the game's own modules, no reimplementation)

- Fire: `require(Core.Input).start` upvalues → adapter (shape: .call/.pick/
  .getWeapon/.key functions) → `adapter.call("onTap", worldPos)` — the game's
  full dispatch (rate limit, cooldown gate, weapon handler, usedWeapon, act sync).
- Select: `require(Core.UI).build` upvalues → callbacks (shape: .onSelect/.onReset
  functions) → `callbacks.onSelect(id)` (owns-checked, updates weapon bar).
- Reset city: `callbacks.onReset()` (host-checked; solo always host) → loadMap(same).
- Cooldown specs: `getupvalues(require(Core.Cooldowns).spec)` → the only table
  upvalue = specs {id→{t=...}}.
- Earn/stall tracking: `Economy.onChanged(fn)` (the game's own listener API).
- Progress: `Destruction.getStats().destroyed` (0..1).
- Dropdown values: `pairs(Config.SHOP.WEAPONS)` (Rule 2 — no hand-copied lists).
- All upvalue lookups iterate values + shape-check (upvalues are unnamed in the
  real client — never index by deobf names).

## Feature plan (Rule 11 filtered)

1. **AutoFire** — dropdown (all weapons, default Nuke) + interval slider (def
   0.35s) + grid sweep (X ∈ ±CITY_HALF step 125, Z lanes {-120,-40,40,120},
   Y=GROUND_Y) via adapter.call("onTap", pos); re-select each sweep; stop+notify
   if weapon unowned.
2. **AutoCityReset** — threshold slider (def 0.85): Destruction.getStats()
   .destroyed ≥ threshold → callbacks.onReset(); stall fallback: no earn delta
   for 12s (Economy.onChanged) with destroyed > 0.1 → onReset.
3. **NoCooldown** — spec-zero via getupvalues(Cooldowns.spec); reversible.
4. **AutoBuy** — 5s loop: cheapest unowned weapon then map (Economy.price/owns/
   canAfford/buy — the game's own client-side purchase flow).
5. **AutoClaim** — 30s loop: Challenges.daily() unclaimed → claimDaily();
   challenges() done && !claimed → claimChallenge(i).
6. **CheatCash** — Input (default 1000000, the game's own console default) +
   Button → Economy.setCash(Economy.cash() + n). The game's own cheat command.
7. **UnlockAll** — Button → Economy.unlockAll() (owned={all weapons+all maps},
   dirty → next game flush persists).

REMOVE (Rule 11): all ROBUX wires (BuyRobux/BuyPass/BuyPack/SkipCooldown/
MiniNuke/ServerNuke), Track telemetry, Likes, RedeemCode (UI one-shot),
Leaderboard/MyRank (UI refresh), TestWipe/TestDay (server-gated tester),
GroupCheck/Gift (UI/monetization), UserMaps/Workshop (editor mode), Street
(dev-gated), direct Save/Net fires (the game's own cadence handles persistence;
direct-fire NaN/\255 variants = probe-class, documented above).

## Harness plan (STC1 real-load, SH3 v4 pattern)

Mock world: RS tree (Config verbatim subset + Core modules with real logic where
cheap: Economy real cash/owned/buy math + flush recorder, Cooldowns REAL module
code (specs from mock Config), Destruction getStats scripted, Challenges real
claim gating, UI/Input modules whose build/start store the adapter/callbacks into
upvalue-mockable slots), SmashRemotes recorders, executor env with **getupvalues
mock** (mock functions carry `__mockups`), Linoria template stub, Vector3/CFrame.
Checks: load/structural; NoCooldown on→specs zeroed + off→restored; AutoFire
tuple stream (positions in grid order, interval respected, unowned stop+notify,
owned re-select); AutoCityReset (threshold trigger + stall trigger + reset
cooldown); AutoBuy cheapest-first ordering + affordability gating + no robux
wires; AutoClaim daily + done-challenges only; CheatCash/UnlockAll state +
dirty-flag; banned-wire sweep (zero fires on all REMOVE remotes); toggle-off
stops; pcall interceptor 0 swallows.

## Open risks

- Upvalue reachability depends on executor getupvalues (UNC standard, §12) —
  shape-checked fallback + notify if not found (Support table).
- Server-side validation invisible (no server code in dump) — but the client-
  authoritative design is structural (the client IS the simulation; the game's
  own console cheats through the same APIs).
- Multiplayer rooms: adapter.call no-ops for spectators (canAct) — correct
  behavior, documented.
- Grid lanes are geometric approximations (city band both sides of road Z=18);
  threshold slider + stall fallback make the loop self-correcting.
