# MATI analysis — verified remote map (glm1, 2026-10-02, T8c dogfood)

Source: Public `MATI.zip` → extracted via newgame.sh. Two places, one game family.
All findings below verified in the deobfs with deobf_search.py (line refs included).
NO Template.lua in the zip — keep current work/lua/Template.lua.

## Place A — "Melt All The Ice!🧊" (the lobby/game-select place)

Net module: `ReplicatedStorage.Lobby.Net` (deobf L53557+). Folder: **ReplicatedStorage.LobbyNet**.
Resolver: `Net.remote(name)` → RemoteEvent, `Net.func(name)` → RemoteFunction (server creates
them on demand; client WaitForChild). Name table at L53563-53578.

| Remote | Kind | Consumer evidence |
|---|---|---|
| LobbyRequest | RemoteEvent | L221 `var5 = remote(Request)`; generic channel: `request(arg1) var5:FireServer(arg1)` L271-273 — single payload TABLE |
| LobbyState | RemoteEvent | L266 (server→client state) |
| ShopRequest | RemoteFunction | L222; `shopRequest(arg1)` = pcall `InvokeServer(table)` → result table, error shape `{ok = false, reason = "error"}` (L275-285) |
| ClassRequest / ClassState | RemoteFunction / RemoteEvent | L5859-5860 (func + OnClientEvent apply) |
| RecordRequest | RemoteFunction | L20439 |
| CompletionRequest | RemoteFunction | L22532 |
| SkinRequest | RemoteFunction | L24524 |
| TradeRequest / TradeState | RemoteFunction / RemoteEvent | L32022-32023 |
| GiftRequest | RemoteFunction | L37040 (FreeGift module; `var1 or func(GiftRequest)` fallback binding) |
| CommunityRequest | RemoteFunction | L45093 lazy init `var15 = var38.func(var38.CommunityRequest)`; CommunityAtlas module |

**Ask-queue pattern (CommunityAtlas, L38311-38338):** `ask(payload, doneCb, key)` pushes
`{payload=, done=, key=}` to a queue; a task.spawn loop pops and runs
`pcall(function() return var15:InvokeServer(payload) end)` with a **3-retry for-loop**,
result kept only `if success and typeof(result) == "table"`. If we replay/automate these,
expect result tables, not nil.

**BindableEvent noise warning:** the `Fire: varN` clusters in the remote map (L5768, L32044,
L4677+…) are module-internal BindableEvent fires (UI view propagation, trade notices) —
NOT game remotes. Only `FireServer`/`InvokeServer` + the Net table names above are real.

## Place B — "Level 1 🧊" (FrozenHouse place)

Net module: `ReplicatedStorage.FrozenHouse.Net` (deobf L15934+). Folder: **ReplicatedStorage.FrozenHouseNet**.

| Remote | Kind | Notes |
|---|---|---|
| ClientReady, MeltState, SaveSettings, RequestEntrance, RequestLobby, IceResync, IceStream, RunEvent, SettingsLoaded, GrenadeFx | RemoteEvent | tbl1 list L15939-15950; init checks `ClassName == "RemoteEvent"` |
| MeltAim, HeatFx | **UnreliableRemoteEvent** | tbl3 L15952; init checks `ClassName == "UnreliableRemoteEvent"` — fire-and-forget, unordered, no return |
| Shop, Throw | RemoteFunction | tbl4 L15953 |

Client join pattern (L9865-9872): `var13:FireServer(tbl1.grid.fieldId)` — plain fieldId arg
(join a melt field); re-join heartbeat every 3s at L10090-10096 (`if not v1.joined and 3 < now - v1.joinAt`).

Also present: `SkinCosmetics` folder module (L30428) — second namespace, check before assuming
all remotes live in FrozenHouseNet.

## Cross-cutting facts (glm2's T7 census + mine)

- No CollectionService tags anywhere → no GetTagged automation vectors; Fx-prefixed
  attributes instead (FxWhen 17x, VipAura, Muted, FxBaseSpeed).
- game_dump.txt present for both places (structure/tree reference).
- No Template.lua in the zip.

## Toolchain dogfood timings (T8c — "test out the new tools")

| step | tool | time |
|---|---|---|
| extract + inventory + checklist | newgame.sh | 1.0s |
| remote usage map (both deobfs) | deobf_search.py remote | 1.1s + 0.7s |
| wire-shape extraction ×5 (fn LINE) | deobf_search.py fn | ~0.5s each |
| net-module table + kinds + lazy-init trace | grep + fn | ~2 min manual |
| **total to a VERIFIED 2-place remote map** | | **~15 min** |

Alliance/Snack rounds paid hours for less certainty. The remaining payload-table internals
(what each `request()`/`*Request` table contains per action) still need per-call-site `fn`
extraction when the script is actually built — the map above is the entry index for that.

Friction feedback for the tool (not fixed here): the `remote` map's `Fire:` rows mix
BindableEvents with real RemoteEvents — consider defaulting the map to FireServer/InvokeServer
hits + a `--all-fires` flag. Logged in lessons.

## Suggested build order (whoever gets the order — glm2 per T3)

1. Reread guide + Template (Rule 18). 2. Place B first (FrozenHouse = the actual gameplay:
   field join + melt loop + Throw/Shop funcs); lobby Request funcs for cosmetics/economy only
   if the reference feature set demands them (Rule 11 — generic request channels are a
   feature-bloat trap). 3. Verify each payload table at its call site before wiring anything.
