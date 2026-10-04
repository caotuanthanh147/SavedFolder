# Potato World Census — game + lobby place instance dumps (glm2)

World-extraction pass for the Roblox harness mock world. Everything below is read from the two
client-side instance dumps; every finding carries dump line numbers as provenance.

**Line-number convention** (both dumps are named `game_dump.txt`, so refs are place-prefixed):
- `game:game_dump.txt:L90` → GAME place dump, pass 1. Pass 2 of the same instance is 27,150 lines later (`L27240`).
- `lobby:game_dump.txt:L26` → LOBBY place dump, pass 1. Pass 2 is 21,126 lines later (`L21152`).
- Both files were dumped as **two passes** (see §0.2); each pass re-lists the same DataModel, so every
  instance appears twice per file. Pass-2 line = pass-1 line + 27,150 (game) / + 21,126 (lobby).

---

## 0) Sources + dump format

### 0.1 Sources

| place | file | lines | passes | instances/pass | top-level services |
|---|---|---|---|---|---|
| GAME (round server) | `/home/z/Public/potato/game/game_dump.txt` | 54,300 | 2 (L1–27150, L27151–54300) | 25,714 | ReplicatedFirst, ReplicatedStorage, Workspace, Players |
| LOBBY (lobby server) | `/home/z/Public/potato/lobby/game_dump.txt` | 42,252 | 2 (L1–21126, L21127–42252) | 18,011 | ReplicatedFirst, ReplicatedStorage, Workspace, Players |

Working copy (TASK 0): `/home/z/my-project/upload/potato/` — full recursive copy of
`/home/z/Public/potato/` (both `game/` and `lobby/` dumps, 10 MB, verified equal size).

### 0.2 Dump format

The dump is a **pre-order (depth-first) walk of the client-visible DataModel**, one instance per line,
properties/attributes on indented lines directly beneath their instance:

```
[ReplicatedFirst] ReplicatedFirst                        <- instance line: [ClassName] Dot.Path (service root, game:game_dump.txt:L1)
[ReplicatedStorage] ReplicatedStorage                    <- service root (game:game_dump.txt:L2)
    Attributes:                                         <- attribute block marker (4-space indent)
        IsReservedServer = true                         <- attribute (8-space indent, Name = LuaValue)
[ModuleScript] ReplicatedStorage.CmdrClient              <- child: parent path + "." + Name (game:game_dump.txt:L5)
[TextBox] ReplicatedStorage.CmdrClient.CmdrInterface.Window.Line
    Text: "TextBox"                                     <- property (4-space indent, Name: LuaValue)
```

Rules observed across all 96,552 lines:

1. **Instance line**: `[ClassName] Full.Dotted.Path` — path is built from service name + child names joined
   with `.`. Names may themselves contain dots (e.g. `ReplicatedStorage.Assets.AutoPeelingMachine.PotatoCounter.Plane.002`,
   game:game_dump.txt:L97), so dot-count is NOT a reliable depth measure; depth was reconstructed from the pre-order walk.
2. **Properties** are only dumped for a handful of classes (full census of property keys in both dumps: `Value:` (1096+),
   `Text:` (828+), `Attributes:` (326+), `ActionText:`/`ObjectText:` (52/36, ProximityPrompt)). **No `Source` property is
   ever dumped (0 hits in both files) — script bodies are NOT available.**
3. **Attributes** print as `    Attributes:` + `        Name = value` lines (game:game_dump.txt:L2-L4, L8173+).
4. **Two passes per file**: pass 2 is a re-walk moments later. GAME passes differ only in countdown text
   (`0:30` → `0:33`, game:game_dump.txt:L27025/L27028 vs L54175/L54178); LOBBY passes differ in queue state
   (`QueueState = "Countdown"` → `"Teleporting"`, `Starting in 1s` → `Teleporting...`, `1/4` → `-/-`, lobby:game_dump.txt:L10258/L10278/L10282/L10298 vs L31384+).
5. **Client-side dump**: no `[Script]`/server scripts anywhere (only `LocalScript` ×5/pass in game, ×15/pass in lobby),
   and only 4 services are walked: **ReplicatedFirst (empty), ReplicatedStorage, Workspace, Players**.
   StarterGui / StarterPlayer / StarterPlayerScripts / StarterPack / SoundService / Lighting / Teams / Chat /
   TextChatService / MaterialService are **not in the dumps** (see §6.6). Runtime equivalents ARE visible:
   StarterGui clones → `Players.<local>.PlayerGui`, StarterPlayerScripts clones → `Players.<local>.PlayerScripts`.
6. **Instance totals per pass**: game 25,714 (ReplicatedStorage 4,089; Workspace ~19,805; Players-tree ~1,820);
   lobby 18,011 (ReplicatedStorage 4,089; Workspace ~13,932; Players-tree ~3,197 incl. 11 players).

---

## 1) Remote inventory (mock-remote registry)

### 1.1 Actual Remote-class instances (complete)

Verified by class-name scan of both files (`^\[(RemoteEvent|RemoteFunction|UnreliableRemoteEvent|BindableEvent|BindableFunction)\]`):

| # | Class | Path | Game place | Lobby place | Notes |
|---|---|---|---|---|---|
| 1 | **RemoteEvent** | `ReplicatedStorage.ModifiedPackages.Packet.RemoteEvent` | L8172 / L35322 | L8172 / L29298 | **THE game protocol remote.** Carries 92 attributes = full event-name→packet-id map (§1.2). Packet framework. |
| 2 | **RemoteEvent** | `ReplicatedStorage.CmdrClient.CmdrEvent` | L90 / L27240 | L26 / L21152 | Cmdr admin console remote (fires command strings). |
| 3 | **RemoteFunction** | `ReplicatedStorage.CmdrClient.CmdrFunction` | L91 / L27241 | L27 / L21153 | Cmdr admin console invoke (autocompletion etc.). |

**Negative results (exhaustive):**
- **No `UnreliableRemoteEvent`** anywhere (0 hits, both files).
- **No `BindableEvent`** anywhere (only `BindableFunction`, §1.4).
- No other RemoteEvent/RemoteFunction instances exist — game networking is 100% funnelled through
  `Packet.RemoteEvent` (1 RemoteEvent) + the 2 Cmdr remotes. All "events" are ids on the single Packet remote.

No folders named `Remotes`, `Network`, `FrameworkEvents`, `Comm(s)`, or `Signals` exist in either place.
The remote-adjacent containers that DO exist:

| Container | Where | Provenance | Role |
|---|---|---|---|
| `ReplicatedStorage.Modules.Resources` (Folder) | RS, both places | game:game_dump.txt:L8035 | Resource declaration modules incl. **`Resources.Events`** (L8116) and **`Resources.Packets`** (L8120) |
| `ReplicatedStorage.ModifiedPackages.Packet` (Folder) | RS, both places | game:game_dump.txt:L8162 | Networking framework: `Packet` (L8163), `Packet._Signal` (L8164), `Packet._Task` (L8165), `Packet._Types` (L8166) + the RemoteEvent (L8172) |
| `ReplicatedStorage.Shared` (Folder) | RS, both places | game:game_dump.txt:L8125 | 36 *Shared modules (shared client/server logic) |
| `ReplicatedStorage.CmdrClient` (ModuleScript) | RS, both places | game:game_dump.txt:L5 | Cmdr console client (owns both Cmdr remotes) |

### 1.2 Packet protocol map — 92 event ids as attributes on `ReplicatedStorage.ModifiedPackages.Packet.RemoteEvent`

The single RemoteEvent instance carries the **entire remote vocabulary as instance attributes**
(game:game_dump.txt:L8173–L8265, i.e. 92 attribute lines under the instance at L8172; identical block at
L35323–L35415; lobby:game_dump.txt:L8173–L8265 / L29299–L29391). **The map is byte-identical between game and
lobby places** (92 attrs, 0 name/value differences) — same protocol id space in both places.

This is the harness mock-remote registry: mock these 92 ids on one RemoteEvent and every client controller
can be driven. Sorted by id:

| id | event name | id | event name | id | event name |
|---|---|---|---|---|---|
| `0` **PlayerStateCreated** | `1` **UpdatePlayerState** | `2` **Sync** |
| `3` **PlayerSynced** | `4` **GlobalOverridesSynced** | `5` **SetGlobalOverride** |
| `6` **ResetGlobalOverride** | `7` **RagdollSetEnabled** | `8` **RagdollOtherPlayerSetEnabled** |
| `9` **SoundPlayed** | `10` **SoundStopped** | `11` **NotificationCreated** |
| `12` **PurchaseProduct** | `13` **ProductAdminPurchasePrompted** | `14` **ProductAdminPurchaseAccept** |
| `15` **PurchaseCelebrated** | `16` **CameraPerspectiveToggled** | `17` **QuestCreated** |
| `18` **QuestTaskSetCompleted** | `19` **QuestRemoved** | `20` **CinematicBarsEnabled** |
| `21` **CinematicBarsDisabled** | `22` **ArrowCreateStatic** | `23` **ArrowRemoveStatic** |
| `24` **ArrowCreateDirection** | `25` **ArrowRemoveDirection** | `26` **CutsceneCameraOrbit** |
| `27` **CutsceneCameraReset** | `28` **QueueJoined** | `29` **QueueLeft** |
| `30` **QueueTeleporting** | `31` **QueueCreate** | `32` **QueueLeave** |
| `33` **PotatoPileSynced** | `34` **PotatoKeyMoved** | `35` **PotatoRemoved** |
| `36` **PotatoPileRequest** | `37` **PotatoPick** | `38` **PotatoesPicked** |
| `39` **BagChanged** | `40` **ToolPurchase** | `41` **ToolEquip** |
| `42` **ToolUsing** | `43` **ToolSwing** | `44` **ToolUpgradePurchase** |
| `45` **ClassRoll** | `46` **ClassStopAt** | `47` **ClassSlotSelect** |
| `48` **ClassRolling** | `49` **ClassRollDenied** | `50` **PotatoTablePlaced** |
| `51` **PotatoesSold** | `52` **PeelPaid** | `53` **MachinePaid** |
| `54` **PeelingStarted** | `55` **PeelingNextPotato** | `56` **PeelingStopped** |
| `57` **PeelingFinished** | `58` **PeelingCancel** | `59` **PeelingSync** |
| `60` **PeelingPeelRemoved** | `61` **PeelingSpectateStarted** | `62` **PeelingSpectateNext** |
| `63` **PeelingSpectateStopped** | `64` **PeelingSpectateSync** | `65` **PeelingSpectatePeel** |
| `66` **PeelRateChanged** | `67` **PeelRateStopped** | `68` **TutorialUpgradesOpened** |
| `69` **TutorialHandSelected** | `70` **TutorialCompleted** | `71` **TutorialStack** |
| `72` **LobbyTutorialFinished** | `73` **GroupRewardClaim** | `74` **GroupRewardLikeResult** |
| `75` **LobbyGuideRequest** | `76` **LobbyGuideSteps** | `77` **IntroCutscenePlay** |
| `78` **IntroCutsceneFinished** | `79` **ItemUnlocked** | `80` **MachineRevealed** |
| `81` **RunReportRequest** | `82` **RunReportShown** | `83` **KeyRevealed** |
| `84` **Escaped** | `85` **EscapeFailed** | `86` **StatsRequest** |
| `87` **StatsShown** | `88` **DailyRewardClaim** | `89` **LeaderboardRequest** |
| `90` **LeaderboardUpdated** | `91` **LobbyUpgradePurchase** |  |

Semantics guessable from names + client controllers (§2.2b): `PlayerStateCreated/0`, `UpdatePlayerState/1`, `Sync/2`,
`PlayerSynced/3` are the sync/bootstrap family; `PotatoPick/37`–`PotatoesSold/51` the potato economy loop;
`PeelingStarted/54`–`PeelRateStopped/67` the peel minigame; `QueueJoined/28`–`QueueLeave/32` lobby matchmaking;
`ToolPurchase/40`–`ToolUpgradePurchase/44` + `ClassRoll/45`–`ClassRollDenied/49` lobby shops; `Escaped/84`/`EscapeFailed/85`
vault-escape win/lose; `StatsRequest/86`/`StatsShown/87`, `DailyRewardClaim/88`, `LeaderboardRequest/89`,
`LeaderboardUpdated/90`, `LobbyUpgradePurchase/91` lobby meta.

### 1.3 Remote-signal framework modules (event plumbing, both places, RS subtree)

```
---- GAME place (pass1 / pass2): ----
[ModuleScript] ReplicatedStorage.CmdrClient.DefaultEventHandlers  L12 / L27162
[ModuleScript] ReplicatedStorage.Modules.Resources.Events  L8116 / L35266
[ModuleScript] ReplicatedStorage.ModifiedPackages.Packet._Signal  L8164 / L35314
[RemoteEvent] ReplicatedStorage.ModifiedPackages.Packet.RemoteEvent  L8172 / L35322
[ModuleScript] ReplicatedStorage.ModifiedPackages.Ripple.utils.signal  L8281 / L35431
[ModuleScript] ReplicatedStorage.ModifiedPackages.Signal  L8283 / L35433
[ModuleScript] ReplicatedStorage.ModifiedPackages.Seam.Modules.UpdateSignals  L8305 / L35455
[ModuleScript] ReplicatedStorage.ModifiedPackages.Seam.Modules.Signal  L8306 / L35456
[ModuleScript] ReplicatedStorage.ModifiedPackages.Seam.Constructors.Connections.OnEvent  L8315 / L35465
[ModuleScript] ReplicatedStorage.ModifiedPackages.Seam.Constructors.Declarations.EventSequence  L8321 / L35471
[ModuleScript] ReplicatedStorage.Packages._Index.1foreverhd_topbarplus@3.4.0.topbarplus.Packages.GoodSignal  L8374 / L35524
[ModuleScript] ReplicatedStorage.Packages._Index.pysephwasntavailable_packetprofiler@2.1.0.Signal  L8379 / L35529
[ModuleScript] ReplicatedStorage.Packages._Index.pysephwasntavailable_remotepacketsizecounter@2.4.1.remotepacketsizecounter  L8400 / L35550
[ModuleScript] ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.SingleEventManager  L8423 / L35573
[ModuleScript] ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.createSignal  L8445 / L35595
[ModuleScript] ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.PropMarkers.Event  L8481 / L35631
[ModuleScript] ReplicatedStorage.Packages._Index.stravant_goodsignal@0.2.1.goodsignal  L8485 / L35635
---- LOBBY place (pass1 / pass2): ----
[ModuleScript] ReplicatedStorage.CmdrClient.DefaultEventHandlers  L12 / L21138
[ModuleScript] ReplicatedStorage.Modules.Resources.Events  L8116 / L29242
[ModuleScript] ReplicatedStorage.ModifiedPackages.Packet._Signal  L8164 / L29290
[RemoteEvent] ReplicatedStorage.ModifiedPackages.Packet.RemoteEvent  L8172 / L29298
[ModuleScript] ReplicatedStorage.ModifiedPackages.Ripple.utils.signal  L8281 / L29407
[ModuleScript] ReplicatedStorage.ModifiedPackages.Signal  L8283 / L29409
[ModuleScript] ReplicatedStorage.ModifiedPackages.Seam.Modules.UpdateSignals  L8305 / L29431
[ModuleScript] ReplicatedStorage.ModifiedPackages.Seam.Modules.Signal  L8306 / L29432
[ModuleScript] ReplicatedStorage.ModifiedPackages.Seam.Constructors.Connections.OnEvent  L8315 / L29441
[ModuleScript] ReplicatedStorage.ModifiedPackages.Seam.Constructors.Declarations.EventSequence  L8321 / L29447
[ModuleScript] ReplicatedStorage.Packages._Index.1foreverhd_topbarplus@3.4.0.topbarplus.Packages.GoodSignal  L8374 / L29500
[ModuleScript] ReplicatedStorage.Packages._Index.pysephwasntavailable_packetprofiler@2.1.0.Signal  L8379 / L29505
[ModuleScript] ReplicatedStorage.Packages._Index.pysephwasntavailable_remotepacketsizecounter@2.4.1.remotepacketsizecounter  L8400 / L29526
[ModuleScript] ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.SingleEventManager  L8423 / L29549
[ModuleScript] ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.createSignal  L8445 / L29571
[ModuleScript] ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.PropMarkers.Event  L8481 / L29607
[ModuleScript] ReplicatedStorage.Packages._Index.stravant_goodsignal@0.2.1.goodsignal  L8485 / L29611
```

Line refs above are game pass1/pass2; the same instances sit at identical pass-1 line numbers in the lobby dump
(except `CmdrClient` descendants — see the §2.5 note on child ordering).

### 1.4 Bindable (client-local) remotes

`BindableFunction` instances = per-character emote hooks (`Animate.PlayEmote`) — one template under the
character-animate asset (`ReplicatedStorage.Assets.ClassesBackground.Character.Animate.PlayEmote`,
game:game_dump.txt:L521, cloned into every character model):

- GAME: template game:game_dump.txt:L521/L27671 + 1 character clone `Workspace.Players.lwtwtnp.Animate.PlayEmote` (L8723/L35873). Total 2.
- LOBBY: template lobby:game_dump.txt:L521/L21647 + 11 character clones, one per player model:
  CherysseAK L10429, Tu4nLogg L10898, Kuimi16 L11469, znskwowiwiwiwu L11989, 3156470584why L12521, cylyaf L13109,
  Max_117M00 L13726, lwtwtnp L14207, Duckchupchip L14732, reaaaaaaaaa02_0 L15286, sru_1128 L15892 (each repeated at +21126).

### 1.5 What the client entry point is (where remotes get consumed)

- `Players.lwtwtnp.PlayerScripts.main` — LocalScript, the single custom bootstrap script (game:game_dump.txt:L25111/L52261;
  lobby:game_dump.txt:L16211/L37337). All 102 Controllers (§2.2b) are required from RS by this tree at runtime.
- Cmdr console GUI is live in PlayerGui: `Players.lwtwtnp.PlayerGui.Cmdr` (game:game_dump.txt:L25163; lobby:game_dump.txt:L16263),
  with prompt `lwtwtnp@Cmdr$` (L25173) — the dumper account had Cmdr access open.

---

## 2) ReplicatedStorage module tree

### 2.1 Top-level structure

`[ReplicatedStorage] ReplicatedStorage` (game:game_dump.txt:L2/L27152; lobby:game_dump.txt:L2/L21128) with
attribute `IsReservedServer = true` (game, L3) vs `false` (lobby, L3) — **the reserved-server flag is the only
ReplicatedStorage-level difference between the two places.**

Direct children (10, identical in both places; game line refs):

| Child | Class | Game L | Content |
|---|---|---|---|
| `ReplicatedStorage.CmdrClient` | ModuleScript | L5 | Cmdr console client: 79 ModuleScripts (CmdrInterface, DefaultEventHandlers, Shared+BuiltInGuards, 45 Commands, 17 Types, + the 2 Cmdr remotes) (§2.2a) |
| `ReplicatedStorage.Assets` | Folder | L92 | 23 model/GUI-template assets (§2.4), 0 ModuleScripts |
| `ReplicatedStorage.Controllers` | Folder | L6672 | **102 client controller ModuleScripts** (§2.2b) |
| `ReplicatedStorage.Gui` | Folder | L6775 | 33 GUI templates (§2.3), 0 ModuleScripts |
| `ReplicatedStorage.Modules` | Folder | L8035 | 76 utility/resource ModuleScripts (§2.2c) |
| `ReplicatedStorage.Shared` | Folder | L8125 | 36 *Shared logic modules (§2.2d) |
| `ReplicatedStorage.ModifiedPackages` | Folder | L8162 | 81 vendored framework modules: Packet, Promise, Ripple, Signal, ExpressivePrompts, Seam (§2.2e) |
| `ReplicatedStorage.Packages` | Folder | L8347 | 125 wally package modules: topbarplus, packetprofiler, roact-constant-fork, goodsignal, remotepacketsizecounter (§2.2f) |
| `ReplicatedStorage.XocoatlSaves` | Folder | L8486 | ColorPresets/`My Palette` folder with `Xocoatl_FolderId` attr (L8488) |
| `ReplicatedStorage.Inputs` | Folder | L8491 | 1 InputContext + 4 InputAction/InputBinding pairs (L8492–L8500) — input-action remapping defs |

RS subtree totals: **4,089 instances, 499 ModuleScripts, 9 Folders** per pass — identical instance sets in
both places (set diff game↔lobby = 0; game:game_dump.txt RS section spans L1–L8543, same span in lobby).

### 2.2 Full ModuleScript list (499)

Grouped by container; line refs = game pass 1 (add 27,150 for game pass 2; identical pass-1 line numbers in the
lobby dump for everything except the `CmdrClient` subtree — see §2.5).

#### 2.2a CmdrClient (79 ModuleScripts + 2 remotes + 2 folders)

```
ReplicatedStorage.CmdrClient  -> L5 / L27155
ReplicatedStorage.CmdrClient.CmdrInterface  -> L6 / L27156
ReplicatedStorage.CmdrClient.CmdrInterface.AutoComplete  -> L7 / L27157
ReplicatedStorage.CmdrClient.CmdrInterface.CreateGui  -> L8 / L27158
ReplicatedStorage.CmdrClient.CmdrInterface.Window  -> L9 / L27159
ReplicatedStorage.CmdrClient.DefaultEventHandlers  -> L12 / L27162
ReplicatedStorage.CmdrClient.Shared.Argument  -> L14 / L27164
ReplicatedStorage.CmdrClient.Shared.Command  -> L15 / L27165
ReplicatedStorage.CmdrClient.Shared.Dispatcher  -> L16 / L27166
ReplicatedStorage.CmdrClient.Shared.Registry  -> L17 / L27167
ReplicatedStorage.CmdrClient.Shared.Util  -> L18 / L27168
ReplicatedStorage.CmdrClient.Shared.BuiltInGuards.HasCharacter  -> L20 / L27170
ReplicatedStorage.CmdrClient.Shared.BuiltInGuards.IsDataStoreAvailable  -> L21 / L27171
ReplicatedStorage.CmdrClient.Shared.BuiltInGuards.MaxArrayLength  -> L22 / L27172
ReplicatedStorage.CmdrClient.Shared.BuiltInGuards.MaxStringLength  -> L23 / L27173
ReplicatedStorage.CmdrClient.Shared.BuiltInGuards.NonEmptyString  -> L24 / L27174
ReplicatedStorage.CmdrClient.Shared.BuiltInGuards.NotEquals  -> L25 / L27175
ReplicatedStorage.CmdrClient.Commands.AddPeeled  -> L27 / L27177
ReplicatedStorage.CmdrClient.Commands.AddUnpeeled  -> L28 / L27178
ReplicatedStorage.CmdrClient.Commands.Ban  -> L29 / L27179
ReplicatedStorage.CmdrClient.Commands.BanByUserId  -> L30 / L27180
ReplicatedStorage.CmdrClient.Commands.Bring  -> L31 / L27181
ReplicatedStorage.CmdrClient.Commands.Fly  -> L32 / L27182
ReplicatedStorage.CmdrClient.Commands.ForceKey  -> L33 / L27183
ReplicatedStorage.CmdrClient.Commands.GivePotatoes  -> L34 / L27184
ReplicatedStorage.CmdrClient.Commands.GiveShinies  -> L35 / L27185
ReplicatedStorage.CmdrClient.Commands.Help  -> L36 / L27186
ReplicatedStorage.CmdrClient.Commands.Kick  -> L37 / L27187
ReplicatedStorage.CmdrClient.Commands.LogGlobalOverrides  -> L38 / L27188
ReplicatedStorage.CmdrClient.Commands.Op  -> L39 / L27189
ReplicatedStorage.CmdrClient.Commands.Peel  -> L40 / L27190
ReplicatedStorage.CmdrClient.Commands.ResetData  -> L41 / L27191
ReplicatedStorage.CmdrClient.Commands.ResetGlobal  -> L42 / L27192
ReplicatedStorage.CmdrClient.Commands.SetCash  -> L43 / L27193
ReplicatedStorage.CmdrClient.Commands.SetGlobal  -> L44 / L27194
ReplicatedStorage.CmdrClient.Commands.Speed  -> L45 / L27195
ReplicatedStorage.CmdrClient.Commands.Teleport  -> L46 / L27196
ReplicatedStorage.CmdrClient.Commands.Unban  -> L47 / L27197
ReplicatedStorage.CmdrClient.Commands.Vanish  -> L48 / L27198
ReplicatedStorage.CmdrClient.Commands.GivePeelTool  -> L49 / L27199
ReplicatedStorage.CmdrClient.Commands.SpawnKey  -> L50 / L27200
ReplicatedStorage.CmdrClient.Commands.Gamepass  -> L51 / L27201
ReplicatedStorage.CmdrClient.Commands.Carry  -> L52 / L27202
ReplicatedStorage.CmdrClient.Commands.Avatar  -> L53 / L27203
ReplicatedStorage.CmdrClient.Commands.Money  -> L54 / L27204
ReplicatedStorage.CmdrClient.Commands.DumpUi  -> L55 / L27205
ReplicatedStorage.CmdrClient.Commands.Dialogue  -> L56 / L27206
ReplicatedStorage.CmdrClient.Commands.Tutorial  -> L57 / L27207
ReplicatedStorage.CmdrClient.Commands.Cutscene  -> L58 / L27208
ReplicatedStorage.CmdrClient.Commands.PileCut  -> L59 / L27209
ReplicatedStorage.CmdrClient.Commands.RunPeels  -> L60 / L27210
ReplicatedStorage.CmdrClient.Commands.UnlockTools  -> L61 / L27211
ReplicatedStorage.CmdrClient.Commands.FillLeaderboard  -> L62 / L27212
ReplicatedStorage.CmdrClient.Commands.ResetTutorial  -> L63 / L27213
ReplicatedStorage.CmdrClient.Commands.FirstPerson  -> L64 / L27214
ReplicatedStorage.CmdrClient.Commands.ThirdPerson  -> L65 / L27215
ReplicatedStorage.CmdrClient.Commands.SetPeelTool  -> L66 / L27216
ReplicatedStorage.CmdrClient.Commands.Sell  -> L67 / L27217
ReplicatedStorage.CmdrClient.Commands.Celebrate  -> L68 / L27218
ReplicatedStorage.CmdrClient.Commands.FakeReport  -> L69 / L27219
ReplicatedStorage.CmdrClient.Commands.Freecam  -> L70 / L27220
ReplicatedStorage.CmdrClient.Commands.Perspective  -> L71 / L27221
ReplicatedStorage.CmdrClient.Types.BrickColor  -> L73 / L27223
ReplicatedStorage.CmdrClient.Types.Color3  -> L74 / L27224
ReplicatedStorage.CmdrClient.Types.Command  -> L75 / L27225
ReplicatedStorage.CmdrClient.Types.Duration  -> L76 / L27226
ReplicatedStorage.CmdrClient.Types.JSON  -> L77 / L27227
ReplicatedStorage.CmdrClient.Types.MathOperator  -> L78 / L27228
ReplicatedStorage.CmdrClient.Types.Player  -> L79 / L27229
ReplicatedStorage.CmdrClient.Types.PlayerId  -> L80 / L27230
ReplicatedStorage.CmdrClient.Types.Primitives  -> L81 / L27231
ReplicatedStorage.CmdrClient.Types.StoredKey  -> L82 / L27232
ReplicatedStorage.CmdrClient.Types.Team  -> L83 / L27233
ReplicatedStorage.CmdrClient.Types.Type  -> L84 / L27234
ReplicatedStorage.CmdrClient.Types.URL  -> L85 / L27235
ReplicatedStorage.CmdrClient.Types.UserInput  -> L86 / L27236
ReplicatedStorage.CmdrClient.Types.Vector  -> L87 / L27237
ReplicatedStorage.CmdrClient.Types.CanUseCommands  -> L88 / L27238
ReplicatedStorage.CmdrClient.Types.CmdrTypeGlobal  -> L89 / L27239
```

#### 2.2b Controllers (102 client controllers)

```
ReplicatedStorage.Controllers.AnimationController  -> L6673 / L33823
ReplicatedStorage.Controllers.ArmStretchController  -> L6674 / L33824
ReplicatedStorage.Controllers.ArrowController  -> L6675 / L33825
ReplicatedStorage.Controllers.AudioController  -> L6676 / L33826
ReplicatedStorage.Controllers.AutoPeelerController  -> L6677 / L33827
ReplicatedStorage.Controllers.BagController  -> L6678 / L33828
ReplicatedStorage.Controllers.BlurController  -> L6679 / L33829
ReplicatedStorage.Controllers.ButtonPressController  -> L6680 / L33830
ReplicatedStorage.Controllers.CameraController  -> L6681 / L33831
ReplicatedStorage.Controllers.CarryUpgradeController  -> L6682 / L33832
ReplicatedStorage.Controllers.CashController  -> L6683 / L33833
ReplicatedStorage.Controllers.CharacterController  -> L6684 / L33834
ReplicatedStorage.Controllers.CinematicBarsController  -> L6685 / L33835
ReplicatedStorage.Controllers.ClassController  -> L6686 / L33836
ReplicatedStorage.Controllers.CmdrController  -> L6687 / L33837
ReplicatedStorage.Controllers.CrosshairController  -> L6688 / L33838
ReplicatedStorage.Controllers.CutsceneCameraController  -> L6689 / L33839
ReplicatedStorage.Controllers.DailyRewardController  -> L6690 / L33840
ReplicatedStorage.Controllers.DeviceController  -> L6691 / L33841
ReplicatedStorage.Controllers.DiamondController  -> L6692 / L33842
ReplicatedStorage.Controllers.DisableCoreGui  -> L6693 / L33843
ReplicatedStorage.Controllers.FriendBoostController  -> L6694 / L33844
ReplicatedStorage.Controllers.GameTimerController  -> L6695 / L33845
ReplicatedStorage.Controllers.GlobalController  -> L6696 / L33846
ReplicatedStorage.Controllers.GuiController  -> L6697 / L33847
ReplicatedStorage.Controllers.HighlightController  -> L6698 / L33848
ReplicatedStorage.Controllers.HotbarController  -> L6699 / L33849
ReplicatedStorage.Controllers.HudController  -> L6700 / L33850
ReplicatedStorage.Controllers.InputControllerV2  -> L6701 / L33851
ReplicatedStorage.Controllers.InspectController  -> L6702 / L33852
ReplicatedStorage.Controllers.KeyController  -> L6703 / L33853
ReplicatedStorage.Controllers.KnifeController  -> L6704 / L33854
ReplicatedStorage.Controllers.LeaderboardController  -> L6705 / L33855
ReplicatedStorage.Controllers.LobbyUpgradeController  -> L6706 / L33856
ReplicatedStorage.Controllers.MouseController  -> L6707 / L33857
ReplicatedStorage.Controllers.NotificationController  -> L6708 / L33858
ReplicatedStorage.Controllers.PacketProfilerController  -> L6709 / L33859
ReplicatedStorage.Controllers.PeelTableController  -> L6710 / L33860
ReplicatedStorage.Controllers.PeelingController  -> L6711 / L33861
ReplicatedStorage.Controllers.PeelingSpectateController  -> L6712 / L33862
ReplicatedStorage.Controllers.PlayerController  -> L6713 / L33863
ReplicatedStorage.Controllers.PopupPromptController  -> L6714 / L33864
ReplicatedStorage.Controllers.PotatoCounterController  -> L6715 / L33865
ReplicatedStorage.Controllers.PotatoFlyController  -> L6716 / L33866
ReplicatedStorage.Controllers.PotatoHoldController  -> L6717 / L33867
ReplicatedStorage.Controllers.PotatoPileController  -> L6718 / L33868
ReplicatedStorage.Controllers.PotatoTableController  -> L6719 / L33869
ReplicatedStorage.Controllers.PreloadController  -> L6720 / L33870
ReplicatedStorage.Controllers.ProductController  -> L6721 / L33871
ReplicatedStorage.Controllers.ProximityPromptController  -> L6722 / L33872
ReplicatedStorage.Controllers.QueueController  -> L6723 / L33873
ReplicatedStorage.Controllers.RagdollController  -> L6724 / L33874
ReplicatedStorage.Controllers.ServerTypeController  -> L6725 / L33875
ReplicatedStorage.Controllers.ShopController  -> L6726 / L33876
ReplicatedStorage.Controllers.StatsController  -> L6727 / L33877
ReplicatedStorage.Controllers.SyncController  -> L6728 / L33878
ReplicatedStorage.Controllers.ToolEquipController  -> L6729 / L33879
ReplicatedStorage.Controllers.ToolHoldController  -> L6730 / L33880
ReplicatedStorage.Controllers.ToolPickupController  -> L6731 / L33881
ReplicatedStorage.Controllers.ToolUpgradeController  -> L6732 / L33882
ReplicatedStorage.Controllers.TopbarPlusController  -> L6733 / L33883
ReplicatedStorage.Controllers.TutorialController  -> L6734 / L33884
ReplicatedStorage.Controllers.UISpotlightController  -> L6735 / L33885
ReplicatedStorage.Controllers.WaterwayController  -> L6736 / L33886
ReplicatedStorage.Controllers.ToolUseButtonController  -> L6737 / L33887
ReplicatedStorage.Controllers.PeelRateController  -> L6738 / L33888
ReplicatedStorage.Controllers.HandHoldController  -> L6739 / L33889
ReplicatedStorage.Controllers.WooshController  -> L6740 / L33890
ReplicatedStorage.Controllers.LobbySignController  -> L6741 / L33891
ReplicatedStorage.Controllers.LobbyZoneController  -> L6742 / L33892
ReplicatedStorage.Controllers.MobileScaleController  -> L6743 / L33893
ReplicatedStorage.Controllers.ToolVfxController  -> L6744 / L33894
ReplicatedStorage.Controllers.OthersHoldController  -> L6745 / L33895
ReplicatedStorage.Controllers.DialogueController  -> L6746 / L33896
ReplicatedStorage.Controllers.SoldController  -> L6747 / L33897
ReplicatedStorage.Controllers.UnlockController  -> L6748 / L33898
ReplicatedStorage.Controllers.IntroCutsceneController  -> L6749 / L33899
ReplicatedStorage.Controllers.RadioController  -> L6750 / L33900
ReplicatedStorage.Controllers.BlizzardController  -> L6751 / L33901
ReplicatedStorage.Controllers.EscapeCinematicController  -> L6752 / L33902
ReplicatedStorage.Controllers.KeyRevealController  -> L6753 / L33903
ReplicatedStorage.Controllers.FreecamController  -> L6754 / L33904
ReplicatedStorage.Controllers.PotWaterController  -> L6755 / L33905
ReplicatedStorage.Controllers.ShineController  -> L6756 / L33906
ReplicatedStorage.Controllers.PeelEarningsController  -> L6757 / L33907
ReplicatedStorage.Controllers.StoreSoldController  -> L6758 / L33908
ReplicatedStorage.Controllers.LobbyTutorialController  -> L6759 / L33909
ReplicatedStorage.Controllers.CashFlyController  -> L6760 / L33910
ReplicatedStorage.Controllers.TablePromptController  -> L6761 / L33911
ReplicatedStorage.Controllers.TableBeaconController  -> L6762 / L33912
ReplicatedStorage.Controllers.ButtonAnimationController  -> L6763 / L33913
ReplicatedStorage.Controllers.MenuAnimationController  -> L6764 / L33914
ReplicatedStorage.Controllers.QuestCardController  -> L6765 / L33915
ReplicatedStorage.Controllers.BagPickupController  -> L6766 / L33916
ReplicatedStorage.Controllers.MobileStrokeController  -> L6767 / L33917
ReplicatedStorage.Controllers.GamepadMenuController  -> L6768 / L33918
ReplicatedStorage.Controllers.GroupRewardController  -> L6769 / L33919
ReplicatedStorage.Controllers.MachineRevealController  -> L6770 / L33920
ReplicatedStorage.Controllers.MachineSoldController  -> L6771 / L33921
ReplicatedStorage.Controllers.PurchaseCelebrationController  -> L6772 / L33922
ReplicatedStorage.Controllers.RunReportController  -> L6773 / L33923
ReplicatedStorage.Controllers.StoreLockController  -> L6774 / L33924
```

#### 2.2c Modules (76 utilities/resources)

```
ReplicatedStorage.Modules.AABB  -> L8036 / L35186
ReplicatedStorage.Modules.BehaviorCollection  -> L8037 / L35187
ReplicatedStorage.Modules.Benchmarker  -> L8038 / L35188
ReplicatedStorage.Modules.BiSet  -> L8039 / L35189
ReplicatedStorage.Modules.Buffer  -> L8040 / L35190
ReplicatedStorage.Modules.Cancellable  -> L8041 / L35191
ReplicatedStorage.Modules.DeltaTime  -> L8042 / L35192
ReplicatedStorage.Modules.Framerate  -> L8043 / L35193
ReplicatedStorage.Modules.Gizmos  -> L8044 / L35194
ReplicatedStorage.Modules.IdMap  -> L8045 / L35195
ReplicatedStorage.Modules.Initializer  -> L8046 / L35196
ReplicatedStorage.Modules.Logger  -> L8047 / L35197
ReplicatedStorage.Modules.Maid  -> L8048 / L35198
ReplicatedStorage.Modules.OBB  -> L8049 / L35199
ReplicatedStorage.Modules.Permissions  -> L8050 / L35200
ReplicatedStorage.Modules.Queue  -> L8051 / L35201
ReplicatedStorage.Modules.RagdollModule  -> L8052 / L35202
ReplicatedStorage.Modules.RagdollModule.buildCollisionFilters  -> L8053 / L35203
ReplicatedStorage.Modules.RagdollModule.buildConstraints  -> L8054 / L35204
ReplicatedStorage.Modules.RagdollModule.buildRagdoll  -> L8055 / L35205
ReplicatedStorage.Modules.RagdollModule.getLastWordFromPascalCase  -> L8056 / L35206
ReplicatedStorage.Modules.Rand  -> L8067 / L35217
ReplicatedStorage.Modules.RateLimiter  -> L8068 / L35218
ReplicatedStorage.Modules.Squash  -> L8069 / L35219
ReplicatedStorage.Modules.TweenSequence  -> L8070 / L35220
ReplicatedStorage.Modules.Helper.CreateDebugPart  -> L8072 / L35222
ReplicatedStorage.Modules.Helper.CreateSpring  -> L8073 / L35223
ReplicatedStorage.Modules.Helper.FormatString  -> L8074 / L35224
ReplicatedStorage.Modules.Helper.FormatTime  -> L8075 / L35225
ReplicatedStorage.Modules.Helper.GenerateUuid  -> L8076 / L35226
ReplicatedStorage.Modules.Helper.GetClosestPointOnPart  -> L8077 / L35227
ReplicatedStorage.Modules.Helper.IS_RESERVED_SERVER  -> L8078 / L35228
ReplicatedStorage.Modules.Helper.IS_SERVER  -> L8079 / L35229
ReplicatedStorage.Modules.Helper.IS_STUDIO  -> L8080 / L35230
ReplicatedStorage.Modules.Helper.InstanceList  -> L8081 / L35231
ReplicatedStorage.Modules.Helper.NIL_SYMBOL  -> L8082 / L35232
ReplicatedStorage.Modules.Helper.SetCounterValue  -> L8083 / L35233
ReplicatedStorage.Modules.Helper.SetImageHeadshot  -> L8084 / L35234
ReplicatedStorage.Modules.Helper.SetSlotSelected  -> L8085 / L35235
ReplicatedStorage.Modules.Helper.VerifyFunctionCaller  -> L8086 / L35236
ReplicatedStorage.Modules.Helper.WaitUntilExists  -> L8087 / L35237
ReplicatedStorage.Modules.Helper.Welder  -> L8088 / L35238
ReplicatedStorage.Modules.Helper.FlashLabels  -> L8089 / L35239
ReplicatedStorage.Modules.Helper.FormatCash  -> L8090 / L35240
ReplicatedStorage.Modules.Helper.ShakeGui  -> L8091 / L35241
ReplicatedStorage.Modules.Helper.PlayFocusPull  -> L8092 / L35242
ReplicatedStorage.Modules.Helper.DetachScreenGuis  -> L8093 / L35243
ReplicatedStorage.Modules.Helper.CutsceneState  -> L8094 / L35244
ReplicatedStorage.Modules.Helper.CanAffordCash  -> L8095 / L35245
ReplicatedStorage.Modules.Helper.CreateGuideBeam  -> L8096 / L35246
ReplicatedStorage.Modules.Helper.PotatoKindStyle  -> L8097 / L35247
ReplicatedStorage.Modules.Helper.AttachPotatoKey  -> L8098 / L35248
ReplicatedStorage.Modules.Helper.CreateGamepadHint  -> L8099 / L35249
ReplicatedStorage.Modules.Helper.FormatNumber  -> L8100 / L35250
ReplicatedStorage.Modules.Helper.GetGamepadImage  -> L8101 / L35251
ReplicatedStorage.Modules.Helper.KeyShine  -> L8102 / L35252
ReplicatedStorage.Modules.Helper.LobbyMenus  -> L8103 / L35253
ReplicatedStorage.Modules.Lib.ColorLib  -> L8105 / L35255
ReplicatedStorage.Modules.Lib.MathLib  -> L8106 / L35256
ReplicatedStorage.Modules.Lib.TableLib  -> L8107 / L35257
ReplicatedStorage.Modules.Lib.TweenLib  -> L8108 / L35258
ReplicatedStorage.Modules.Lib.VectorLib  -> L8109 / L35259
ReplicatedStorage.Modules.Resources.Animations  -> L8111 / L35261
ReplicatedStorage.Modules.Resources.Assets  -> L8112 / L35262
ReplicatedStorage.Modules.Resources.Badges  -> L8113 / L35263
ReplicatedStorage.Modules.Resources.CollisionGroups  -> L8114 / L35264
ReplicatedStorage.Modules.Resources.Enums  -> L8115 / L35265
ReplicatedStorage.Modules.Resources.Events  -> L8116 / L35266
ReplicatedStorage.Modules.Resources.Folders  -> L8117 / L35267
ReplicatedStorage.Modules.Resources.Gamepasses  -> L8118 / L35268
ReplicatedStorage.Modules.Resources.Globals  -> L8119 / L35269
ReplicatedStorage.Modules.Resources.Packets  -> L8120 / L35270
ReplicatedStorage.Modules.Resources.Products  -> L8121 / L35271
ReplicatedStorage.Modules.Resources.Resource  -> L8122 / L35272
ReplicatedStorage.Modules.Resources.Sounds  -> L8123 / L35273
ReplicatedStorage.Modules.Resources.Types  -> L8124 / L35274
```

#### 2.2d Shared (36 cross-cutting modules)

```
ReplicatedStorage.Shared.ArrowShared  -> L8126 / L35276
ReplicatedStorage.Shared.AudioShared  -> L8127 / L35277
ReplicatedStorage.Shared.CacheShared  -> L8128 / L35278
ReplicatedStorage.Shared.CarryUpgradeShared  -> L8129 / L35279
ReplicatedStorage.Shared.ClassShared  -> L8130 / L35280
ReplicatedStorage.Shared.CutsceneCameraShared  -> L8131 / L35281
ReplicatedStorage.Shared.DailyRewardShared  -> L8132 / L35282
ReplicatedStorage.Shared.FriendBoostShared  -> L8133 / L35283
ReplicatedStorage.Shared.GameTimerShared  -> L8134 / L35284
ReplicatedStorage.Shared.GamepassShared  -> L8135 / L35285
ReplicatedStorage.Shared.KeyShared  -> L8136 / L35286
ReplicatedStorage.Shared.LeaderboardShared  -> L8137 / L35287
ReplicatedStorage.Shared.LobbyUpgradeShared  -> L8138 / L35288
ReplicatedStorage.Shared.NotificationShared  -> L8139 / L35289
ReplicatedStorage.Shared.PlayerShared  -> L8140 / L35290
ReplicatedStorage.Shared.PlayerStateShared  -> L8141 / L35291
ReplicatedStorage.Shared.PotatoHoldShared  -> L8142 / L35292
ReplicatedStorage.Shared.PotatoKindShared  -> L8143 / L35293
ReplicatedStorage.Shared.PotatoPileShared  -> L8144 / L35294
ReplicatedStorage.Shared.PotatoTableShared  -> L8145 / L35295
ReplicatedStorage.Shared.ProductShared  -> L8146 / L35296
ReplicatedStorage.Shared.SpatialHashShared  -> L8147 / L35297
ReplicatedStorage.Shared.StatsShared  -> L8148 / L35298
ReplicatedStorage.Shared.StoreShared  -> L8149 / L35299
ReplicatedStorage.Shared.TimeShared  -> L8150 / L35300
ReplicatedStorage.Shared.ToolUpgradeShared  -> L8151 / L35301
ReplicatedStorage.Shared.TutorialShared  -> L8152 / L35302
ReplicatedStorage.Shared.PeelToolShared  -> L8153 / L35303
ReplicatedStorage.Shared.UnlockShared  -> L8154 / L35304
ReplicatedStorage.Shared.IntroShared  -> L8155 / L35305
ReplicatedStorage.Shared.QueueShared  -> L8156 / L35306
ReplicatedStorage.Shared.SellValueShared  -> L8157 / L35307
ReplicatedStorage.Shared.GroupRewardShared  -> L8158 / L35308
ReplicatedStorage.Shared.TutorialStackShared  -> L8159 / L35309
ReplicatedStorage.Shared.RunReportShared  -> L8160 / L35310
ReplicatedStorage.Shared.StoreLockShared  -> L8161 / L35311
```

#### 2.2e ModifiedPackages (81 vendored framework modules)

```
ReplicatedStorage.ModifiedPackages.Packet  -> L8163 / L35313
ReplicatedStorage.ModifiedPackages.Packet._Signal  -> L8164 / L35314
ReplicatedStorage.ModifiedPackages.Packet._Task  -> L8165 / L35315
ReplicatedStorage.ModifiedPackages.Packet._Types  -> L8166 / L35316
ReplicatedStorage.ModifiedPackages.Packet._Types._Characters  -> L8167 / L35317
ReplicatedStorage.ModifiedPackages.Packet._Types._Enums  -> L8168 / L35318
ReplicatedStorage.ModifiedPackages.Packet._Types._Static1  -> L8169 / L35319
ReplicatedStorage.ModifiedPackages.Packet._Types._Static2  -> L8170 / L35320
ReplicatedStorage.ModifiedPackages.Packet._Types._Static3  -> L8171 / L35321
ReplicatedStorage.ModifiedPackages.Promise  -> L8266 / L35416
ReplicatedStorage.ModifiedPackages.Promise._Promise  -> L8267 / L35417
ReplicatedStorage.ModifiedPackages.Ripple  -> L8268 / L35418
ReplicatedStorage.ModifiedPackages.Ripple.config  -> L8269 / L35419
ReplicatedStorage.ModifiedPackages.Ripple.easing  -> L8270 / L35420
ReplicatedStorage.ModifiedPackages.Ripple.motion  -> L8271 / L35421
ReplicatedStorage.ModifiedPackages.Ripple.spring  -> L8272 / L35422
ReplicatedStorage.ModifiedPackages.Ripple.tween  -> L8273 / L35423
ReplicatedStorage.ModifiedPackages.Ripple.types  -> L8274 / L35424
ReplicatedStorage.ModifiedPackages.Ripple.utils.intermediate  -> L8276 / L35426
ReplicatedStorage.ModifiedPackages.Ripple.utils.interpolate  -> L8277 / L35427
ReplicatedStorage.ModifiedPackages.Ripple.utils.merge  -> L8278 / L35428
ReplicatedStorage.ModifiedPackages.Ripple.utils.oklab  -> L8279 / L35429
ReplicatedStorage.ModifiedPackages.Ripple.utils.scheduler  -> L8280 / L35430
ReplicatedStorage.ModifiedPackages.Ripple.utils.signal  -> L8281 / L35431
ReplicatedStorage.ModifiedPackages.Ripple.utils.spawn  -> L8282 / L35432
ReplicatedStorage.ModifiedPackages.Signal  -> L8283 / L35433
ReplicatedStorage.ModifiedPackages.ExpressivePrompts  -> L8284 / L35434
ReplicatedStorage.ModifiedPackages.ExpressivePrompts.BuildFrames  -> L8285 / L35435
ReplicatedStorage.ModifiedPackages.ExpressivePrompts.NewInputConnections  -> L8286 / L35436
ReplicatedStorage.ModifiedPackages.ExpressivePrompts.SoundData  -> L8287 / L35437
ReplicatedStorage.ModifiedPackages.ExpressivePrompts.NewInputLabel  -> L8288 / L35438
ReplicatedStorage.ModifiedPackages.ExpressivePrompts.NewInputLabel.Touch  -> L8289 / L35439
ReplicatedStorage.ModifiedPackages.ExpressivePrompts.NewInputLabel.Gamepad  -> L8290 / L35440
ReplicatedStorage.ModifiedPackages.ExpressivePrompts.NewInputLabel.Gamepad.GamepadButtonImage  -> L8291 / L35441
ReplicatedStorage.ModifiedPackages.ExpressivePrompts.NewInputLabel.Keyboard  -> L8292 / L35442
ReplicatedStorage.ModifiedPackages.ExpressivePrompts.NewInputLabel.Keyboard.KeyCodeToTextMapping  -> L8293 / L35443
ReplicatedStorage.ModifiedPackages.ExpressivePrompts.NewInputLabel.Keyboard.KeyboardButtonIconMapping  -> L8294 / L35444
ReplicatedStorage.ModifiedPackages.ExpressivePrompts.NewInputLabel.Keyboard.KeyboardButtonImage  -> L8295 / L35445
ReplicatedStorage.ModifiedPackages.Seam  -> L8296 / L35446
ReplicatedStorage.ModifiedPackages.Seam.Modules.Batch  -> L8298 / L35448
ReplicatedStorage.ModifiedPackages.Seam.Modules.CreateDeepTraceback  -> L8299 / L35449
ReplicatedStorage.ModifiedPackages.Seam.Modules.IsValueChanged  -> L8300 / L35450
ReplicatedStorage.ModifiedPackages.Seam.Modules.StateManager  -> L8301 / L35451
ReplicatedStorage.ModifiedPackages.Seam.Modules.Symbol  -> L8302 / L35452
ReplicatedStorage.ModifiedPackages.Seam.Modules.Trove  -> L8303 / L35453
ReplicatedStorage.ModifiedPackages.Seam.Modules.Types  -> L8304 / L35454
ReplicatedStorage.ModifiedPackages.Seam.Modules.UpdateSignals  -> L8305 / L35455
ReplicatedStorage.ModifiedPackages.Seam.Modules.Signal  -> L8306 / L35456
ReplicatedStorage.ModifiedPackages.Seam.Modules.Signal.Connection  -> L8307 / L35457
ReplicatedStorage.ModifiedPackages.Seam.Modules.ValuePacker  -> L8308 / L35458
ReplicatedStorage.ModifiedPackages.Seam.Modules.ValuePacker.Oklab  -> L8309 / L35459
ReplicatedStorage.ModifiedPackages.Seam.Constructors.Connections.OnAttached  -> L8312 / L35462
ReplicatedStorage.ModifiedPackages.Seam.Constructors.Connections.OnAttributeChanged  -> L8313 / L35463
ReplicatedStorage.ModifiedPackages.Seam.Constructors.Connections.OnChanged  -> L8314 / L35464
ReplicatedStorage.ModifiedPackages.Seam.Constructors.Connections.OnEvent  -> L8315 / L35465
ReplicatedStorage.ModifiedPackages.Seam.Constructors.Declarations.Attribute  -> L8317 / L35467
ReplicatedStorage.ModifiedPackages.Seam.Constructors.Declarations.Children  -> L8318 / L35468
ReplicatedStorage.ModifiedPackages.Seam.Constructors.Declarations.Component  -> L8319 / L35469
ReplicatedStorage.ModifiedPackages.Seam.Constructors.Declarations.Destroyed  -> L8320 / L35470
ReplicatedStorage.ModifiedPackages.Seam.Constructors.Declarations.EventSequence  -> L8321 / L35471
ReplicatedStorage.ModifiedPackages.Seam.Constructors.Declarations.FollowAttribute  -> L8322 / L35472
ReplicatedStorage.ModifiedPackages.Seam.Constructors.Declarations.FollowProperty  -> L8323 / L35473
ReplicatedStorage.ModifiedPackages.Seam.Constructors.Declarations.Lifetime  -> L8324 / L35474
ReplicatedStorage.ModifiedPackages.Seam.Constructors.Declarations.New  -> L8325 / L35475
ReplicatedStorage.ModifiedPackages.Seam.Constructors.Declarations.StyleSheet  -> L8326 / L35476
ReplicatedStorage.ModifiedPackages.Seam.Constructors.Declarations.Tags  -> L8327 / L35477
ReplicatedStorage.ModifiedPackages.Seam.Constructors.Memory.Scope  -> L8329 / L35479
ReplicatedStorage.ModifiedPackages.Seam.Constructors.States.Bezier  -> L8331 / L35481
ReplicatedStorage.ModifiedPackages.Seam.Constructors.States.Computed  -> L8332 / L35482
ReplicatedStorage.ModifiedPackages.Seam.Constructors.States.ForPairs  -> L8333 / L35483
ReplicatedStorage.ModifiedPackages.Seam.Constructors.States.Rendered  -> L8334 / L35484
ReplicatedStorage.ModifiedPackages.Seam.Constructors.States.Resource  -> L8335 / L35485
ReplicatedStorage.ModifiedPackages.Seam.Constructors.States.Value  -> L8336 / L35486
ReplicatedStorage.ModifiedPackages.Seam.Constructors.States.Animation.Spring  -> L8338 / L35488
ReplicatedStorage.ModifiedPackages.Seam.Constructors.States.Animation.Tween  -> L8339 / L35489
ReplicatedStorage.ModifiedPackages.Seam.Constructors.Utilities.GetValue  -> L8341 / L35491
ReplicatedStorage.ModifiedPackages.Seam.Constructors.Utilities.Inspect  -> L8342 / L35492
ReplicatedStorage.ModifiedPackages.Seam.Constructors.Utilities.IsComponent  -> L8343 / L35493
ReplicatedStorage.ModifiedPackages.Seam.Constructors.Utilities.IsState  -> L8344 / L35494
ReplicatedStorage.ModifiedPackages.Seam.Constructors.Utilities.LockValue  -> L8345 / L35495
ReplicatedStorage.ModifiedPackages.Seam.Constructors.Utilities.SetValue  -> L8346 / L35496
```

#### 2.2f Packages (125 wally packages)

```
ReplicatedStorage.Packages.PacketProfiler  -> L8348 / L35498
ReplicatedStorage.Packages.TopbarPlus  -> L8349 / L35499
ReplicatedStorage.Packages._Index.1foreverhd_topbarplus@3.4.0.topbarplus  -> L8352 / L35502
ReplicatedStorage.Packages._Index.1foreverhd_topbarplus@3.4.0.topbarplus.Attribute  -> L8353 / L35503
ReplicatedStorage.Packages._Index.1foreverhd_topbarplus@3.4.0.topbarplus.Reference  -> L8354 / L35504
ReplicatedStorage.Packages._Index.1foreverhd_topbarplus@3.4.0.topbarplus.Types  -> L8355 / L35505
ReplicatedStorage.Packages._Index.1foreverhd_topbarplus@3.4.0.topbarplus.Utility  -> L8356 / L35506
ReplicatedStorage.Packages._Index.1foreverhd_topbarplus@3.4.0.topbarplus.VERSION  -> L8357 / L35507
ReplicatedStorage.Packages._Index.1foreverhd_topbarplus@3.4.0.topbarplus.Elements.Caption  -> L8359 / L35509
ReplicatedStorage.Packages._Index.1foreverhd_topbarplus@3.4.0.topbarplus.Elements.Container  -> L8360 / L35510
ReplicatedStorage.Packages._Index.1foreverhd_topbarplus@3.4.0.topbarplus.Elements.Dropdown  -> L8361 / L35511
ReplicatedStorage.Packages._Index.1foreverhd_topbarplus@3.4.0.topbarplus.Elements.Indicator  -> L8362 / L35512
ReplicatedStorage.Packages._Index.1foreverhd_topbarplus@3.4.0.topbarplus.Elements.Menu  -> L8363 / L35513
ReplicatedStorage.Packages._Index.1foreverhd_topbarplus@3.4.0.topbarplus.Elements.Notice  -> L8364 / L35514
ReplicatedStorage.Packages._Index.1foreverhd_topbarplus@3.4.0.topbarplus.Elements.Selection  -> L8365 / L35515
ReplicatedStorage.Packages._Index.1foreverhd_topbarplus@3.4.0.topbarplus.Elements.Widget  -> L8366 / L35516
ReplicatedStorage.Packages._Index.1foreverhd_topbarplus@3.4.0.topbarplus.Features.Gamepad  -> L8368 / L35518
ReplicatedStorage.Packages._Index.1foreverhd_topbarplus@3.4.0.topbarplus.Features.Overflow  -> L8369 / L35519
ReplicatedStorage.Packages._Index.1foreverhd_topbarplus@3.4.0.topbarplus.Features.Themes  -> L8370 / L35520
ReplicatedStorage.Packages._Index.1foreverhd_topbarplus@3.4.0.topbarplus.Features.Themes.Classic  -> L8371 / L35521
ReplicatedStorage.Packages._Index.1foreverhd_topbarplus@3.4.0.topbarplus.Features.Themes.Default  -> L8372 / L35522
ReplicatedStorage.Packages._Index.1foreverhd_topbarplus@3.4.0.topbarplus.Packages.GoodSignal  -> L8374 / L35524
ReplicatedStorage.Packages._Index.1foreverhd_topbarplus@3.4.0.topbarplus.Packages.Janitor  -> L8375 / L35525
ReplicatedStorage.Packages._Index.pysephwasntavailable_packetprofiler@2.1.0.PacketSizeCounter  -> L8377 / L35527
ReplicatedStorage.Packages._Index.pysephwasntavailable_packetprofiler@2.1.0.Roact  -> L8378 / L35528
ReplicatedStorage.Packages._Index.pysephwasntavailable_packetprofiler@2.1.0.Signal  -> L8379 / L35529
ReplicatedStorage.Packages._Index.pysephwasntavailable_packetprofiler@2.1.0.packetprofiler  -> L8380 / L35530
ReplicatedStorage.Packages._Index.pysephwasntavailable_packetprofiler@2.1.0.packetprofiler.Components.ChartResize  -> L8382 / L35532
ReplicatedStorage.Packages._Index.pysephwasntavailable_packetprofiler@2.1.0.packetprofiler.Components.MainPlugin  -> L8383 / L35533
ReplicatedStorage.Packages._Index.pysephwasntavailable_packetprofiler@2.1.0.packetprofiler.Components.PacketChart  -> L8384 / L35534
ReplicatedStorage.Packages._Index.pysephwasntavailable_packetprofiler@2.1.0.packetprofiler.Components.PacketChartItems  -> L8385 / L35535
ReplicatedStorage.Packages._Index.pysephwasntavailable_packetprofiler@2.1.0.packetprofiler.Components.PacketCircleArcs  -> L8386 / L35536
ReplicatedStorage.Packages._Index.pysephwasntavailable_packetprofiler@2.1.0.packetprofiler.Components.PacketFrame  -> L8387 / L35537
ReplicatedStorage.Packages._Index.pysephwasntavailable_packetprofiler@2.1.0.packetprofiler.Components.PacketFrames  -> L8388 / L35538
ReplicatedStorage.Packages._Index.pysephwasntavailable_packetprofiler@2.1.0.packetprofiler.Components.PacketProfiler  -> L8389 / L35539
ReplicatedStorage.Packages._Index.pysephwasntavailable_packetprofiler@2.1.0.packetprofiler.Components.StudioSettings  -> L8390 / L35540
ReplicatedStorage.Packages._Index.pysephwasntavailable_packetprofiler@2.1.0.packetprofiler.Components.StudioTheme  -> L8391 / L35541
ReplicatedStorage.Packages._Index.pysephwasntavailable_packetprofiler@2.1.0.packetprofiler.Components.StudioWidget  -> L8392 / L35542
ReplicatedStorage.Packages._Index.pysephwasntavailable_packetprofiler@2.1.0.packetprofiler.Components.TopbarButton  -> L8393 / L35543
ReplicatedStorage.Packages._Index.pysephwasntavailable_packetprofiler@2.1.0.packetprofiler.Components.TopbarButtonsGroup  -> L8394 / L35544
ReplicatedStorage.Packages._Index.pysephwasntavailable_packetprofiler@2.1.0.packetprofiler.Modules.CircularBuffer  -> L8396 / L35546
ReplicatedStorage.Packages._Index.pysephwasntavailable_packetprofiler@2.1.0.packetprofiler.Modules.Packages  -> L8397 / L35547
ReplicatedStorage.Packages._Index.pysephwasntavailable_packetprofiler@2.1.0.packetprofiler.Modules.TableToSyntaxString  -> L8398 / L35548
ReplicatedStorage.Packages._Index.pysephwasntavailable_remotepacketsizecounter@2.4.1.remotepacketsizecounter  -> L8400 / L35550
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork  -> L8402 / L35552
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.Binding  -> L8403 / L35553
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.Binding.spec  -> L8404 / L35554
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.Component  -> L8405 / L35555
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.ComponentLifecyclePhase  -> L8406 / L35556
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.Config  -> L8407 / L35557
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.Config.spec  -> L8408 / L35558
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.ElementKind  -> L8409 / L35559
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.ElementKind.spec  -> L8410 / L35560
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.ElementUtils  -> L8411 / L35561
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.ElementUtils.spec  -> L8412 / L35562
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.GlobalConfig  -> L8413 / L35563
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.GlobalConfig.spec  -> L8414 / L35564
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.Logging  -> L8415 / L35565
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.None  -> L8416 / L35566
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.NoopRenderer  -> L8417 / L35567
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.Portal  -> L8418 / L35568
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.PureComponent  -> L8419 / L35569
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.PureComponent.spec  -> L8420 / L35570
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.RobloxRenderer  -> L8421 / L35571
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.RobloxRenderer.spec  -> L8422 / L35572
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.SingleEventManager  -> L8423 / L35573
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.SingleEventManager.spec  -> L8424 / L35574
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.Symbol  -> L8425 / L35575
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.Symbol.spec  -> L8426 / L35576
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.Type  -> L8427 / L35577
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.Type.spec  -> L8428 / L35578
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.assertDeepEqual  -> L8429 / L35579
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.assertDeepEqual.spec  -> L8430 / L35580
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.assign  -> L8431 / L35581
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.assign.spec  -> L8432 / L35582
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.createContext  -> L8433 / L35583
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.createContext.spec  -> L8434 / L35584
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.createElement  -> L8435 / L35585
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.createElement.spec  -> L8436 / L35586
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.createFragment  -> L8437 / L35587
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.createFragment.spec  -> L8438 / L35588
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.createReconciler  -> L8439 / L35589
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.createReconciler.spec  -> L8440 / L35590
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.createReconcilerCompat  -> L8441 / L35591
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.createReconcilerCompat.spec  -> L8442 / L35592
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.createRef  -> L8443 / L35593
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.createRef.spec  -> L8444 / L35594
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.createSignal  -> L8445 / L35595
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.createSignal.spec  -> L8446 / L35596
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.createSpy  -> L8447 / L35597
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.createSpy.spec  -> L8448 / L35598
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.forwardRef  -> L8449 / L35599
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.forwardRef.spec  -> L8450 / L35600
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.getDefaultInstanceProperty  -> L8451 / L35601
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.getDefaultInstanceProperty.spec  -> L8452 / L35602
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.init.spec  -> L8453 / L35603
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.internalAssert  -> L8454 / L35604
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.invalidSetStateMessages  -> L8455 / L35605
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.oneChild  -> L8456 / L35606
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.oneChild.spec  -> L8457 / L35607
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.strict  -> L8458 / L35608
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.strict.spec  -> L8459 / L35609
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.Component.spec.context.spec  -> L8461 / L35611
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.Component.spec.defaultProps.spec  -> L8462 / L35612
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.Component.spec.didMount.spec  -> L8463 / L35613
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.Component.spec.didUpdate.spec  -> L8464 / L35614
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.Component.spec.extend.spec  -> L8465 / L35615
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.Component.spec.getDerivedStateFromProps.spec  -> L8466 / L35616
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.Component.spec.getElementTraceback.spec  -> L8467 / L35617
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.Component.spec.init.spec  -> L8468 / L35618
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.Component.spec.legacyContext.spec  -> L8469 / L35619
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.Component.spec.render.spec  -> L8470 / L35620
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.Component.spec.setState.spec  -> L8471 / L35621
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.Component.spec.shouldUpdate.spec  -> L8472 / L35622
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.Component.spec.validateProps.spec  -> L8473 / L35623
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.Component.spec.willUnmount.spec  -> L8474 / L35624
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.Component.spec.willUpdate.spec  -> L8475 / L35625
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.PropMarkers.Change  -> L8477 / L35627
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.PropMarkers.Change.spec  -> L8478 / L35628
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.PropMarkers.Children  -> L8479 / L35629
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.PropMarkers.Constant  -> L8480 / L35630
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.PropMarkers.Event  -> L8481 / L35631
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.PropMarkers.Event.spec  -> L8482 / L35632
ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.PropMarkers.Ref  -> L8483 / L35633
ReplicatedStorage.Packages._Index.stravant_goodsignal@0.2.1.goodsignal  -> L8485 / L35635
```

#### 2.2g Controller→feature cheat sheet

The 102 controllers mirror the Packet protocol (§1.2). Harness-relevant highlights:
potato economy: `PotatoPileController`, `PotatoPickup`→`PotatoFlyController`, `PotatoHoldController`,
`PotatoCounterController`, `PotatoTableController`, `BagController`, `CashController`, `DiamondController`,
`PeelTableController`; peel minigame: `PeelingController`, `PeelingSpectateController`, `PeelRateController`,
`KnifeController`, `AutoPeelerController`; lobby meta: `QueueController`, `ClassController`, `ShopController`,
`LobbyUpgradeController`, `LeaderboardController`, `StatsController`, `DailyRewardController`,
`GroupRewardController`, `ServerTypeController`; escape: `EscapeCinematicController`, `KeyController`,
`KeyRevealController`, `PotWaterController`; systems: `SyncController`, `PlayerController`,
`ProximityPromptController`, `ToolEquipController`/`ToolHoldController`/`ToolPickupController`/
`ToolUpgradeController`/`ToolUseButtonController`, `NotificationController`, `GlobalController`,
`PacketProfilerController`, `CmdrController`, `FreecamController`.

### 2.3 RS.Gui templates (33)

```
ReplicatedStorage.Gui.ExpressivePrompt  [BillboardGui]  L6776 / L33926
ReplicatedStorage.Gui.Bag  [ScreenGui]  L6815 / L33965
ReplicatedStorage.Gui.PopupPrompt  [ScreenGui]  L6831 / L33981
ReplicatedStorage.Gui.CinematicBars  [ScreenGui]  L6878 / L34028
ReplicatedStorage.Gui.Diamonds  [ScreenGui]  L6886 / L34036
ReplicatedStorage.Gui.Spotlight  [ScreenGui]  L6913 / L34063
ReplicatedStorage.Gui.UpgradesButton  [ScreenGui]  L6920 / L34070
ReplicatedStorage.Gui.Queue  [ScreenGui]  L6930 / L34080
ReplicatedStorage.Gui.Classes  [ScreenGui]  L7075 / L34225
ReplicatedStorage.Gui.UnlockPopup  [ScreenGui]  L7249 / L34399
ReplicatedStorage.Gui.Tutorial  [ScreenGui]  L7262 / L34412
ReplicatedStorage.Gui.Escape  [ScreenGui]  L7277 / L34427
ReplicatedStorage.Gui.ProximityPrompt  [BillboardGui]  L7287 / L34437
ReplicatedStorage.Gui.FriendBoost  [ScreenGui]  L7316 / L34466
ReplicatedStorage.Gui.ToolUseButton  [ScreenGui]  L7339 / L34489
ReplicatedStorage.Gui.Crosshair  [ScreenGui]  L7359 / L34509
ReplicatedStorage.Gui.LobbyUpgrades  [ScreenGui]  L7363 / L34513
ReplicatedStorage.Gui.QuestCard  [ScreenGui]  L7436 / L34586
ReplicatedStorage.Gui.SoldPopup  [ScreenGui]  L7500 / L34650
ReplicatedStorage.Gui.Hotbar  [ScreenGui]  L7514 / L34664
ReplicatedStorage.Gui.StatsButton  [ScreenGui]  L7554 / L34704
ReplicatedStorage.Gui.Cash  [ScreenGui]  L7565 / L34715
ReplicatedStorage.Gui.Leaderboard  [SurfaceGui]  L7583 / L34733
ReplicatedStorage.Gui.Timer  [ScreenGui]  L7628 / L34778
ReplicatedStorage.Gui.NameTag  [BillboardGui]  L7639 / L34789
ReplicatedStorage.Gui.ShopButton  [ScreenGui]  L7656 / L34806
ReplicatedStorage.Gui.Stats  [ScreenGui]  L7667 / L34817
ReplicatedStorage.Gui.Notifications  [ScreenGui]  L7720 / L34870
ReplicatedStorage.Gui.DailyRewards  [ScreenGui]  L7735 / L34885
ReplicatedStorage.Gui.LobbyUpgradesButton  [ScreenGui]  L7801 / L34951
ReplicatedStorage.Gui.Shop  [ScreenGui]  L7812 / L34962
ReplicatedStorage.Gui.ToolUpgrades  [ScreenGui]  L7919 / L35069
ReplicatedStorage.Gui.Peeling  [ScreenGui]  L8021 / L35171
```

### 2.4 RS.Assets models/templates (23)

```
ReplicatedStorage.Assets.AutoPeelingMachine  [Model]  L93 / L27243
ReplicatedStorage.Assets.Blackhole  [Model]  L139 / L27289
ReplicatedStorage.Assets.Bucket  [Model]  L152 / L27302
ReplicatedStorage.Assets.Diamond  [Model]  L157 / L27307
ReplicatedStorage.Assets.ClassesBackground  [Folder]  L159 / L27309
ReplicatedStorage.Assets.PeelingMachine  [Model]  L817 / L27967
ReplicatedStorage.Assets.PotatoSack  [Model]  L863 / L28013
ReplicatedStorage.Assets.PotatoSucker  [Model]  L868 / L28018
ReplicatedStorage.Assets.Potatoes  [Folder]  L890 / L28040
ReplicatedStorage.Assets.Key  [Model]  L1184 / L28334
ReplicatedStorage.Assets.Shovel  [Model]  L1186 / L28336
ReplicatedStorage.Assets.ShovelRig  [Model]  L1192 / L28342
ReplicatedStorage.Assets.TutorialArrow  [Model]  L1240 / L28390
ReplicatedStorage.Assets.R15  [Model]  L1244 / L28394
ReplicatedStorage.Assets.ShovelR15  [Model]  L1456 / L28606
ReplicatedStorage.Assets.SuckerR15  [Model]  L1789 / L28939
ReplicatedStorage.Assets.SuckerRig  [Model]  L2098 / L29248
ReplicatedStorage.Assets.CapsuleClosed  [Model]  L2146 / L29296
ReplicatedStorage.Assets.Gui  [Folder]  L2154 / L29304
ReplicatedStorage.Assets.Cutscene  [Folder]  L3061 / L30211
ReplicatedStorage.Assets.CapsuleOpened  [Model]  L6394 / L33544
ReplicatedStorage.Assets.DoguR15  [Model]  L6401 / L33551
ReplicatedStorage.Assets.MinigameTools  [Folder]  L6651 / L33801
```

Notable subtrees: `Assets.Potatoes` = potato kind models (PeeledPotato L1125, UnpeeledPotato L1127,
RainbowUnpeeledPotato L1129, DiamondUnpeeledPotato L1132, GoldenUnpeeledPotato L1135, `KeyPotatoes` folder
L1138 with PeeledKeyPotato/MinigameKeyPotato/TutKeyPotato/SwissKnifeKeyPotato/UnpeeledKeyPotato,
`Minigame` folder L891 with Knife/Spoon/Peeler/SwissKnife variants); `Assets.MinigameTools` (SwissKnife L6659,
TriplePeeler L6665); rig models R15/ShovelR15/SuckerR15/DoguR15/ShovelRig/SuckerRig; `Assets.Cutscene` (L2970);
`Assets.Gui` (L2063); `Assets.ClassesBackground.Character` incl. the Animate LocalScript template (L451).

### 2.5 Game vs lobby RS diff

**Instance sets are 100% identical (4,089/4,089 common, 0 game-only, 0 lobby-only)** — the game and lobby
places ship the same ReplicatedStorage. Only two presentation-level differences:

1. `IsReservedServer` attribute: `true` in game (game:game_dump.txt:L3), `false` in lobby (lobby:game_dump.txt:L3).
   (`Modules.Helper.IS_RESERVED_SERVER` at L8078 reads this — client branches game/lobby behavior on it.)
2. **Child ordering inside `CmdrClient`** (hence different line numbers for that subtree only):
   game order = CmdrInterface → DefaultEventHandlers → Shared → **Commands (L26–L71) → Types (L72–L89) → CmdrEvent L90 → CmdrFunction L91**;
   lobby order = … → Shared → **CmdrEvent L26 → CmdrFunction L27 → Types (L28–L45) → Commands (L46–L91)**.
   Line numbers re-align at `ReplicatedStorage.Assets` (L92) in both files.

---

## 3) CollectionService tags

**No tags are present in either dump.** Evidence (exhaustive searches across both files):

- No serialized `Tags` property or `Tags =` line is printed by the dumper anywhere (the property census in §0.2
  shows only `Value`/`Text`/`ActionText`/`ObjectText`/`Attributes` keys exist).
- Case-insensitive search for `tag` hits exactly one instance **name** in both files:
  `[ModuleScript] ReplicatedStorage.ModifiedPackages.Seam.Constructors.Declarations.Tags` (game:game_dump.txt:L8327/L35477;
  lobby:game_dump.txt:L8327/L29453) — that is a *Seam framework declaration module*, not a CollectionService tag.
- `deobf_search.py tags` → `(none found)` on both dumps (no AddTag/GetTagged/HasTag call sites — consistent with
  the dumps containing no script source at all).
- No `CollectionService` string appears in either file.

Harness implication: tags, if the live game uses any, are applied at runtime by server code and are **not
observable here** — the mock world must rely on names/paths/attributes (attributes ARE richly available, §4),
or assign its own tags. The presence of `Seam.Constructors.Declarations.Tags` (L8327) hints Seam components may
declare tags at runtime, but no tag values are recoverable from these dumps.

---

## 4) Instance attributes

Attribute blocks: 326 per file pair in game (163 distinct instances/pass), 342 in lobby (171/pass).
The 92-attribute protocol map on `Packet.RemoteEvent` is documented in §1.2 and excluded from the tables below.

### 4.1 Game place — attribute-carrying instances (163, pass 1)

```
[ReplicatedStorage] ReplicatedStorage  L2 / L27152  ATTRS: IsReservedServer = true
[Model] ReplicatedStorage.Assets.AutoPeelingMachine  L93 / L27243  ATTRS: RBX_ReimportId = "a24ad0e9-61c3-42f5-b12d-213f44a4e4c8"
[Model] ReplicatedStorage.Assets.Bucket  L152 / L27302  ATTRS: RBX_ReimportId = "57f3138d-d08f-4a37-b200-b52872c0623c"
[Model] ReplicatedStorage.Assets.ClassesBackground.Env.Fences.Model.fence  L295 / L27445  ATTRS: RBX_ReimportId = "27462d01-427b-4a25-9787-c6e42e9941f3"
[Model] ReplicatedStorage.Assets.ClassesBackground.Env.Fences.Model.Model.fence  L313 / L27463  ATTRS: RBX_ReimportId = "27462d01-427b-4a25-9787-c6e42e9941f3"
[Model] ReplicatedStorage.Assets.ClassesBackground.Env.Fences.Model.Model.fence  L322 / L27472  ATTRS: RBX_ReimportId = "27462d01-427b-4a25-9787-c6e42e9941f3"
[Model] ReplicatedStorage.Assets.ClassesBackground.Env.Barriers.Barrier  L382 / L27532  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] ReplicatedStorage.Assets.ClassesBackground.Env.Barriers.Barrier  L391 / L27541  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] ReplicatedStorage.Assets.ClassesBackground.Env.Barriers.Barrier  L400 / L27550  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] ReplicatedStorage.Assets.ClassesBackground.Env.Barriers.Model.Barrier  L410 / L27560  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] ReplicatedStorage.Assets.ClassesBackground.Env.Barriers.Model.Barrier  L419 / L27569  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] ReplicatedStorage.Assets.ClassesBackground.Env.Barriers.Barrier  L428 / L27578  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] ReplicatedStorage.Assets.ClassesBackground.Env.Barriers.Barrier  L437 / L27587  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] ReplicatedStorage.Assets.PeelingMachine  L817 / L27967  ATTRS: RBX_ReimportId = "76147fce-af5d-4a07-874f-a52b5c5e4041"
[Model] ReplicatedStorage.Assets.Potatoes.Minigame.SwissKnife.DiamondUnpeeledPotatoForMinigame  L1088 / L28238  ATTRS: RBX_ReimportId = "aa37281c-b75b-4f2f-be77-b4ab6f195e9b"
[Model] ReplicatedStorage.Assets.Potatoes.Minigame.SwissKnife.GoldenUnpeeledPotatoForMinigame  L1098 / L28248  ATTRS: RBX_ReimportId = "aa37281c-b75b-4f2f-be77-b4ab6f195e9b"
[Model] ReplicatedStorage.Assets.Potatoes.Minigame.SwissKnife.UnpeeledPotatoForMinigame  L1108 / L28258  ATTRS: RBX_ReimportId = "aa37281c-b75b-4f2f-be77-b4ab6f195e9b"
[Model] ReplicatedStorage.Assets.Potatoes.Minigame.SwissKnife.RainbowUnpeeledPotatoForMinigame  L1115 / L28265  ATTRS: RBX_ReimportId = "aa37281c-b75b-4f2f-be77-b4ab6f195e9b"
[Model] ReplicatedStorage.Assets.Potatoes.KeyPotatoes.TutKeyPotato  L1153 / L28303  ATTRS: RBX_ReimportId = "93ee30cb-be91-4c7f-b14b-69f0473b5b76"
[Model] ReplicatedStorage.Assets.Potatoes.KeyPotatoes.SwissKnifeKeyPotato  L1171 / L28321  ATTRS: RBX_ReimportId = "aa37281c-b75b-4f2f-be77-b4ab6f195e9b"
[Model] ReplicatedStorage.Assets.Shovel  L1186 / L28336  ATTRS: RBX_ReimportId = "1a9d668f-a561-4b36-86ba-a10732a5f7f0"
[Model] ReplicatedStorage.Assets.MinigameTools.SwissKnife  L6659 / L33809  ATTRS: RBX_ReimportId = "f1ab1d0a-90c0-4548-82fe-4ed78e91f7e9"
[Model] ReplicatedStorage.Assets.MinigameTools.TriplePeeler  L6665 / L33815  ATTRS: RBX_ReimportId = "538890af-fc8a-45c8-9e35-468a86dcb399"
[Folder] ReplicatedStorage.XocoatlSaves.ColorPresets.My Palette  L8488 / L35638  ATTRS: Xocoatl_FolderId = "{40aff5749eb"
[Model] Workspace.Players.lwtwtnp  L8557 / L35707  ATTRS: HeldContainerName = "Hand", HeldKinds = "1113"
[MeshPart] Workspace.Players.lwtwtnp.BoySpaceHair.Handle  L8972 / L36122  ATTRS: RBXRefinementScale = 1, 1, 1
[Model] Workspace.Map.Map.Barriers.Barrier  L9102 / L36252  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Map.Barriers.Barrier  L9111 / L36261  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Map.Barriers.Barrier  L9120 / L36270  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Map.Barriers.Barrier  L9129 / L36279  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Map.Barriers.Barrier  L9138 / L36288  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Map.Barriers.Barrier  L9147 / L36297  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Map.Barriers.Barrier  L9156 / L36306  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Map.Barriers.Barrier  L9165 / L36315  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Map.Barriers.Barrier  L9174 / L36324  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Map.Barriers.Barrier  L9183 / L36333  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Map.Barriers.Barrier  L9192 / L36342  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Map.Barriers.Model.Barrier  L9202 / L36352  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Map.Barriers.Model.Barrier  L9211 / L36361  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Map.Barriers.Model.Barrier  L9220 / L36370  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Map.Barriers.Model.Barrier  L9230 / L36380  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Map.Barriers.Model.Barrier  L9239 / L36389  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Map.Barriers.Model.Barrier  L9248 / L36398  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Map.Barriers.Model.Model.Barrier  L9259 / L36409  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Map.Barriers.Model.Model.Barrier  L9268 / L36418  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Map.Barriers.Model.Model.Barrier  L9277 / L36427  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Map.Barriers.Model.Model.Barrier  L9286 / L36436  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Map.Barriers.Model.Model.Barrier  L9296 / L36446  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Map.Barriers.Model.Model.Barrier  L9305 / L36455  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Map.Barriers.Model.Model.Barrier  L9314 / L36464  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Map.Barriers.Model.Model.Barrier  L9323 / L36473  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Map.Fences.Model.fence  L9334 / L36484  ATTRS: RBX_ReimportId = "27462d01-427b-4a25-9787-c6e42e9941f3"
[Model] Workspace.Map.Map.Fences.Model.fence  L9344 / L36494  ATTRS: RBX_ReimportId = "27462d01-427b-4a25-9787-c6e42e9941f3"
[Model] Workspace.Map.Map.Fences.Model.fence  L9353 / L36503  ATTRS: RBX_ReimportId = "27462d01-427b-4a25-9787-c6e42e9941f3"
[Model] Workspace.Map.Map.Fences.Model.fence  L9363 / L36513  ATTRS: RBX_ReimportId = "27462d01-427b-4a25-9787-c6e42e9941f3"
[Model] Workspace.Map.Map.Fences.Model.Model.fence  L9374 / L36524  ATTRS: RBX_ReimportId = "27462d01-427b-4a25-9787-c6e42e9941f3"
[Model] Workspace.Map.Map.Fences.Model.Model.fence  L9383 / L36533  ATTRS: RBX_ReimportId = "27462d01-427b-4a25-9787-c6e42e9941f3"
[Model] Workspace.Map.Map.Fences.Model.Model.fence  L9393 / L36543  ATTRS: RBX_ReimportId = "27462d01-427b-4a25-9787-c6e42e9941f3"
[Model] Workspace.Map.Map.Fences.Model.Model.fence  L9402 / L36552  ATTRS: RBX_ReimportId = "27462d01-427b-4a25-9787-c6e42e9941f3"
[Model] Workspace.Map.Map.Fences.fence  L9411 / L36561  ATTRS: RBX_ReimportId = "27462d01-427b-4a25-9787-c6e42e9941f3"
[Model] Workspace.Map.Map.Fences.fence  L9420 / L36570  ATTRS: RBX_ReimportId = "27462d01-427b-4a25-9787-c6e42e9941f3"
[Model] Workspace.Map.Map.Fences.fence  L9429 / L36579  ATTRS: RBX_ReimportId = "27462d01-427b-4a25-9787-c6e42e9941f3"
[Model] Workspace.Map.Map.Fences.Model.fence  L9439 / L36589  ATTRS: RBX_ReimportId = "27462d01-427b-4a25-9787-c6e42e9941f3"
[Model] Workspace.Map.Map.Fences.Model.fence  L9448 / L36598  ATTRS: RBX_ReimportId = "27462d01-427b-4a25-9787-c6e42e9941f3"
[Model] Workspace.Map.Map.Fences.Model.fence  L9458 / L36608  ATTRS: RBX_ReimportId = "27462d01-427b-4a25-9787-c6e42e9941f3"
[Model] Workspace.Map.Map.Fences.Model.fence  L9467 / L36617  ATTRS: RBX_ReimportId = "27462d01-427b-4a25-9787-c6e42e9941f3"
[Model] Workspace.Map.Map.InsideBunker.LightSources.Light  L10109 / L37259  ATTRS: RBX_ReimportId = "99e65354-8409-4439-b64e-4b123cde7ea8"
[Model] Workspace.Map.Map.InsideBunker.LightSources.Light  L10117 / L37267  ATTRS: RBX_ReimportId = "99e65354-8409-4439-b64e-4b123cde7ea8"
[Model] Workspace.Map.Map.InsideBunker.LightSources.Light  L10125 / L37275  ATTRS: RBX_ReimportId = "99e65354-8409-4439-b64e-4b123cde7ea8"
[Model] Workspace.Map.Map.InsideBunker.LightSources.Light  L10133 / L37283  ATTRS: RBX_ReimportId = "99e65354-8409-4439-b64e-4b123cde7ea8"
[Model] Workspace.Map.Map.InsideBunker.LightSources.Light  L10141 / L37291  ATTRS: RBX_ReimportId = "99e65354-8409-4439-b64e-4b123cde7ea8"
[Model] Workspace.Map.Map.InsideBunker.LightSources.Light  L10149 / L37299  ATTRS: RBX_ReimportId = "99e65354-8409-4439-b64e-4b123cde7ea8"
[Model] Workspace.Map.Map.InsideBunker.LightSources.Light  L10157 / L37307  ATTRS: RBX_ReimportId = "99e65354-8409-4439-b64e-4b123cde7ea8"
[Model] Workspace.Map.Map.InsideBunker.LightSources.Light  L10165 / L37315  ATTRS: RBX_ReimportId = "99e65354-8409-4439-b64e-4b123cde7ea8"
[Model] Workspace.Map.PotRoom.Pot  L10778 / L37928  ATTRS: RBX_ReimportId = "a3c9a2fd-7d73-4293-aeda-c5669f06e52d"
[Model] Workspace.Map.PotRoom.PotLight.Light  L10812 / L37962  ATTRS: RBX_ReimportId = "b8bb1913-615f-42e0-b95a-ac86e4163a18"
[Model] Workspace.Map.PotRoom.PotLight.Light  L10824 / L37974  ATTRS: RBX_ReimportId = "b8bb1913-615f-42e0-b95a-ac86e4163a18"
[Model] Workspace.Map.PotRoom.PotLight.Light  L10836 / L37986  ATTRS: RBX_ReimportId = "b8bb1913-615f-42e0-b95a-ac86e4163a18"
[Model] Workspace.Map.PotRoom.PotLight.Light  L10848 / L37998  ATTRS: RBX_ReimportId = "b8bb1913-615f-42e0-b95a-ac86e4163a18"
[Model] Workspace.Map.PotRoom.PotLight.Light  L10860 / L38010  ATTRS: RBX_ReimportId = "b8bb1913-615f-42e0-b95a-ac86e4163a18"
[Model] Workspace.Map.PotRoom.PotLight.Light  L10872 / L38022  ATTRS: RBX_ReimportId = "b8bb1913-615f-42e0-b95a-ac86e4163a18"
[Model] Workspace.Map.PotRoom.PotLight.Light  L10884 / L38034  ATTRS: RBX_ReimportId = "b8bb1913-615f-42e0-b95a-ac86e4163a18"
[Model] Workspace.Map.PotRoom.PotLight.Light  L10896 / L38046  ATTRS: RBX_ReimportId = "b8bb1913-615f-42e0-b95a-ac86e4163a18"
[Model] Workspace.Map.PotRoom.PotLight.Light  L10908 / L38058  ATTRS: RBX_ReimportId = "b8bb1913-615f-42e0-b95a-ac86e4163a18"
[Model] Workspace.Map.PotRoom.PotLight.Light  L10920 / L38070  ATTRS: RBX_ReimportId = "b8bb1913-615f-42e0-b95a-ac86e4163a18"
[Model] Workspace.Map.PotRoom.PotLight.Light  L10932 / L38082  ATTRS: RBX_ReimportId = "b8bb1913-615f-42e0-b95a-ac86e4163a18"
[Model] Workspace.Map.PotRoom.PotLight.Light  L10944 / L38094  ATTRS: RBX_ReimportId = "b8bb1913-615f-42e0-b95a-ac86e4163a18"
[Model] Workspace.Map.PotRoom.PotLight.Light  L10956 / L38106  ATTRS: RBX_ReimportId = "b8bb1913-615f-42e0-b95a-ac86e4163a18"
[Model] Workspace.Map.PotRoom.PotLight.Light  L10968 / L38118  ATTRS: RBX_ReimportId = "b8bb1913-615f-42e0-b95a-ac86e4163a18"
[Model] Workspace.Map.PotRoom.PotLight.Light  L10980 / L38130  ATTRS: RBX_ReimportId = "b8bb1913-615f-42e0-b95a-ac86e4163a18"
[Model] Workspace.Map.PotRoom.PotLight.Light  L10992 / L38142  ATTRS: RBX_ReimportId = "b8bb1913-615f-42e0-b95a-ac86e4163a18"
[Model] Workspace.Map.PotRoom.PotLight.Light  L11004 / L38154  ATTRS: RBX_ReimportId = "b8bb1913-615f-42e0-b95a-ac86e4163a18"
[Model] Workspace.Map.PotRoom.PotLight.Light  L11016 / L38166  ATTRS: RBX_ReimportId = "b8bb1913-615f-42e0-b95a-ac86e4163a18"
[Model] Workspace.Map.PotRoom.PotLight.Light  L11028 / L38178  ATTRS: RBX_ReimportId = "b8bb1913-615f-42e0-b95a-ac86e4163a18"
[Model] Workspace.Map.PotRoom.PotLight.Light  L11040 / L38190  ATTRS: RBX_ReimportId = "b8bb1913-615f-42e0-b95a-ac86e4163a18"
[Model] Workspace.Map.PeelingMachines.AutoPeelingMachine  L11114 / L38264  ATTRS: Machine = "AutoPeelingMachine", RBX_ReimportId = "a24ad0e9-61c3-42f5-b12d-213f44a4e4c8"
[MeshPart] Workspace.Map.PeelingMachines.AutoPeelingMachine.Cube.051  L11147 / L38297  ATTRS: PotatoCount = 0, PotatoKinds = ""
[MeshPart] Workspace.Map.PeelingMachines.AutoPeelingMachine.Cube.042  L11161 / L38311  ATTRS: PotatoCount = 0, PotatoKinds = ""
[Model] Workspace.Map.PeelingMachines.PeelingTable1  L11196 / L38346  ATTRS: RBX_ReimportId = "6a857b03-8056-40f0-aade-71bd427f8ece"
[Model] Workspace.Map.PeelingMachines.PeelingMachine  L11274 / L38424  ATTRS: Machine = "PeelingMachine", RBX_ReimportId = "76147fce-af5d-4a07-874f-a52b5c5e4041"
[MeshPart] Workspace.Map.PeelingMachines.PeelingMachine.Cube.033  L11313 / L38463  ATTRS: PotatoCount = 0, PotatoKinds = ""
[MeshPart] Workspace.Map.PeelingMachines.PeelingMachine.Cube.035  L11321 / L38471  ATTRS: PotatoCount = 0, PotatoKinds = ""
[Model] Workspace.Map.PeelingMachines.PeelingTable2  L11353 / L38503  ATTRS: RBX_ReimportId = "6a857b03-8056-40f0-aade-71bd427f8ece"
[Model] Workspace.Map.PeelingMachines.PeelingTable3  L11431 / L38581  ATTRS: RBX_ReimportId = "6a857b03-8056-40f0-aade-71bd427f8ece"
[Model] Workspace.Map.PeelingMachines.PeelingTable4  L11509 / L38659  ATTRS: RBX_ReimportId = "6a857b03-8056-40f0-aade-71bd427f8ece"
[Model] Workspace.Map.PeelingMachines.SellCrate  L11587 / L38737  ATTRS: RBX_ReimportId = "1adc55d9-2f21-41b3-98fb-c8cd2e3744af"
[Part] Workspace.Map.PeelingMachines.SellCrate.PotatoArea  L11645 / L38795  ATTRS: PotatoCount = 0, PotatoKinds = ""
[Model] Workspace.Map.PeelingMachines.PotatoCrate  L11652 / L38802  ATTRS: RBX_ReimportId = "1adc55d9-2f21-41b3-98fb-c8cd2e3744af"
[Part] Workspace.Map.PeelingMachines.PotatoCrate.PotatoArea  L11702 / L38852  ATTRS: PotatoCount = 0, PotatoKinds = ""
[Model] Workspace.Map.StoreItems.Robux.Blackhole  L11716 / L38866  ATTRS: Gamepass = "Blackhole"
[Model] Workspace.Map.StoreItems.Tools.P0T4T0-3000  L11768 / L38918  ATTRS: ToolId = "PotatoSucker"
[ParticleEmitter] Workspace.Map.StoreItems.Tools.P0T4T0-3000.Model.Plane.001.Little Stars  L11786 / L38936  ATTRS: EmitCount = 20, EmitDelay = 0.5
[Model] Workspace.Map.StoreItems.Tools.Shovel  L11811 / L38961  ATTRS: ToolId = "Shovel"
[Model] Workspace.Map.StoreItems.Tools.Shovel.Shovel  L11814 / L38964  ATTRS: RBX_ReimportId = "1a9d668f-a561-4b36-86ba-a10732a5f7f0"
[Model] Workspace.Map.StoreItems.Storage.MechaCapsule  L11837 / L38987  ATTRS: CarryLevel = 4
[ParticleEmitter] Workspace.Map.StoreItems.Storage.MechaCapsule.CapsuleClosed.Plane.017.Little Stars  L11844 / L38994  ATTRS: EmitCount = 20, EmitDelay = 0.5
[Model] Workspace.Map.StoreItems.Storage.Bucket  L11876 / L39026  ATTRS: CarryLevel = 2
[Model] Workspace.Map.StoreItems.Storage.Bucket.Bucket  L11879 / L39029  ATTRS: RBX_ReimportId = "57f3138d-d08f-4a37-b200-b52872c0623c"
[ParticleEmitter] Workspace.Map.StoreItems.Storage.Bucket.Bucket.Root.Little Stars  L11883 / L39033  ATTRS: EmitCount = 20, EmitDelay = 0.5
[Model] Workspace.Map.StoreItems.Storage.PotatoSack  L11912 / L39062  ATTRS: CarryLevel = 3
[ParticleEmitter] Workspace.Map.StoreItems.Storage.PotatoSack.Closed.Little Stars  L11916 / L39066  ATTRS: EmitCount = 20, EmitDelay = 0.5
[Model] Workspace.Map.StoreItems.Peelers.Peeler  L11946 / L39096  ATTRS: PeelToolId = "Peeler"
[Model] Workspace.Map.StoreItems.Peelers.Peeler.Peeler  L11949 / L39099  ATTRS: RBX_ReimportId = "538890af-fc8a-45c8-9e35-468a86dcb399"
[Model] Workspace.Map.StoreItems.Peelers.Knife  L11977 / L39127  ATTRS: PeelToolId = "Knife"
[Model] Workspace.Map.StoreItems.Peelers.Knife.Knife  L11980 / L39130  ATTRS: RBX_ReimportId = "2440b110-c629-4842-a7a1-8cf0a1fa8ea0"
[Model] Workspace.Map.StoreItems.Peelers.TriplePeeler  L12007 / L39157  ATTRS: PeelToolId = "TriplePeeler"
[Model] Workspace.Map.StoreItems.Peelers.TriplePeeler.Model.Peeler  L12011 / L39161  ATTRS: RBX_ReimportId = "538890af-fc8a-45c8-9e35-468a86dcb399"
[Model] Workspace.Map.StoreItems.Peelers.TriplePeeler.Model.Peeler  L12018 / L39168  ATTRS: RBX_ReimportId = "538890af-fc8a-45c8-9e35-468a86dcb399"
[Model] Workspace.Map.StoreItems.Peelers.TriplePeeler.Model.Peeler  L12025 / L39175  ATTRS: RBX_ReimportId = "538890af-fc8a-45c8-9e35-468a86dcb399"
[Model] Workspace.Map.StoreItems.Peelers.SwissKnife  L12055 / L39205  ATTRS: PeelToolId = "SwissKnife"
[Model] Workspace.Map.StoreItems.Peelers.SwissKnife.SwissKnife  L12058 / L39208  ATTRS: RBX_ReimportId = "f1ab1d0a-90c0-4548-82fe-4ed78e91f7e9"
[ScreenGui] Players.lwtwtnp.PlayerGui.TopbarStandard  L25189 / L52339  ATTRS: StartInset = 8
[ScrollingFrame] Players.lwtwtnp.PlayerGui.TopbarStandard.Holders.Left  L25193 / L52343  ATTRS: IsAHolder = true
[ScrollingFrame] Players.lwtwtnp.PlayerGui.TopbarStandard.Holders.Right  L25197 / L52347  ATTRS: IsAHolder = true
[ScrollingFrame] Players.lwtwtnp.PlayerGui.TopbarCentered.Holders.Center  L25203 / L52353  ATTRS: IsAHolder = true
[UIStroke] Players.lwtwtnp.PlayerGui.Notifications.Notifications.Templates.Info.TextLabel.UIStroke  L25338 / L52488  ATTRS: DesktopThickness = 3
[UIStroke] Players.lwtwtnp.PlayerGui.Notifications.Notifications.Templates.Error.TextLabel.UIStroke  L25343 / L52493  ATTRS: DesktopThickness = 3
[UIStroke] Players.lwtwtnp.PlayerGui.Notifications.Notifications.Templates.Success.TextLabel.UIStroke  L25348 / L52498  ATTRS: DesktopThickness = 3
[ImageButton] Players.lwtwtnp.PlayerGui.Queue.Setup.Content.CreateHolder.Create  L25541 / L52691  ATTRS: HoverScale = 1.025
[UIStroke] Players.lwtwtnp.PlayerGui.Tutorial.Panel.Step.UIStroke  L26749 / L53899  ATTRS: DesktopThickness = 3
[UIStroke] Players.lwtwtnp.PlayerGui.Tutorial.Panel.Objective.UIStroke  L26753 / L53903  ATTRS: DesktopThickness = 4
[UIStroke] Players.lwtwtnp.PlayerGui.Tutorial.Panel.Objective.DialogueLetters.C.UIStroke  L26759 / L53909  ATTRS: DesktopThickness = 4
[UIStroke] Players.lwtwtnp.PlayerGui.Tutorial.Panel.Objective.DialogueLetters.O.UIStroke  L26764 / L53914  ATTRS: DesktopThickness = 4
[UIStroke] Players.lwtwtnp.PlayerGui.Tutorial.Panel.Objective.DialogueLetters.L.UIStroke  L26769 / L53919  ATTRS: DesktopThickness = 4
[UIStroke] Players.lwtwtnp.PlayerGui.Tutorial.Panel.Objective.DialogueLetters.L.UIStroke  L26774 / L53924  ATTRS: DesktopThickness = 4
[UIStroke] Players.lwtwtnp.PlayerGui.Tutorial.Panel.Objective.DialogueLetters.E.UIStroke  L26779 / L53929  ATTRS: DesktopThickness = 4
[UIStroke] Players.lwtwtnp.PlayerGui.Tutorial.Panel.Objective.DialogueLetters.C.UIStroke  L26784 / L53934  ATTRS: DesktopThickness = 4
[UIStroke] Players.lwtwtnp.PlayerGui.Tutorial.Panel.Objective.DialogueLetters.T.UIStroke  L26789 / L53939  ATTRS: DesktopThickness = 4
[UIStroke] Players.lwtwtnp.PlayerGui.Tutorial.Panel.Objective.DialogueLetters.P.UIStroke  L26794 / L53944  ATTRS: DesktopThickness = 4
[UIStroke] Players.lwtwtnp.PlayerGui.Tutorial.Panel.Objective.DialogueLetters.O.UIStroke  L26800 / L53950  ATTRS: DesktopThickness = 4
[UIStroke] Players.lwtwtnp.PlayerGui.Tutorial.Panel.Objective.DialogueLetters.T.UIStroke  L26806 / L53956  ATTRS: DesktopThickness = 4
[UIStroke] Players.lwtwtnp.PlayerGui.Tutorial.Panel.Objective.DialogueLetters.A.UIStroke  L26812 / L53962  ATTRS: DesktopThickness = 4
[UIStroke] Players.lwtwtnp.PlayerGui.Tutorial.Panel.Objective.DialogueLetters.T.UIStroke  L26818 / L53968  ATTRS: DesktopThickness = 4
[UIStroke] Players.lwtwtnp.PlayerGui.Tutorial.Panel.Objective.DialogueLetters.O.UIStroke  L26824 / L53974  ATTRS: DesktopThickness = 4
[UIStroke] Players.lwtwtnp.PlayerGui.Tutorial.Panel.Objective.DialogueLetters.E.UIStroke  L26830 / L53980  ATTRS: DesktopThickness = 4
[UIStroke] Players.lwtwtnp.PlayerGui.Tutorial.Panel.Objective.DialogueLetters.S.UIStroke  L26836 / L53986  ATTRS: DesktopThickness = 4
[UIStroke] Players.lwtwtnp.PlayerGui.Tutorial.Panel.Progress.UIStroke  L26842 / L53992  ATTRS: DesktopThickness = 3
[UIStroke] Players.lwtwtnp.PlayerGui.SoldPopup.Panel.Count.UIStroke  L26872 / L54022  ATTRS: DesktopThickness = 6
[UIStroke] Players.lwtwtnp.PlayerGui.SoldPopup.Panel.Title.UIStroke  L26880 / L54030  ATTRS: DesktopThickness = 3.5999999046325684
[UIStroke] Players.lwtwtnp.PlayerGui.UnlockPopup.Header.UIStroke  L26909 / L54059  ATTRS: DesktopThickness = 4
[UIStroke] Players.lwtwtnp.PlayerGui.UnlockPopup.Title.UIStroke  L26914 / L54064  ATTRS: DesktopThickness = 7
[UIStroke] Players.lwtwtnp.PlayerGui.UnlockPopup.By.UIStroke  L26921 / L54071  ATTRS: DesktopThickness = 4
```

### 4.2 Lobby place — attribute-carrying instances (171, pass 1)

```
[ReplicatedStorage] ReplicatedStorage  L2 / L21128  ATTRS: IsReservedServer = false
[Model] ReplicatedStorage.Assets.AutoPeelingMachine  L93 / L21219  ATTRS: RBX_ReimportId = "a24ad0e9-61c3-42f5-b12d-213f44a4e4c8"
[Model] ReplicatedStorage.Assets.Bucket  L152 / L21278  ATTRS: RBX_ReimportId = "57f3138d-d08f-4a37-b200-b52872c0623c"
[Model] ReplicatedStorage.Assets.ClassesBackground.Env.Fences.Model.fence  L295 / L21421  ATTRS: RBX_ReimportId = "27462d01-427b-4a25-9787-c6e42e9941f3"
[Model] ReplicatedStorage.Assets.ClassesBackground.Env.Fences.Model.Model.fence  L313 / L21439  ATTRS: RBX_ReimportId = "27462d01-427b-4a25-9787-c6e42e9941f3"
[Model] ReplicatedStorage.Assets.ClassesBackground.Env.Fences.Model.Model.fence  L322 / L21448  ATTRS: RBX_ReimportId = "27462d01-427b-4a25-9787-c6e42e9941f3"
[Model] ReplicatedStorage.Assets.ClassesBackground.Env.Barriers.Barrier  L382 / L21508  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] ReplicatedStorage.Assets.ClassesBackground.Env.Barriers.Barrier  L391 / L21517  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] ReplicatedStorage.Assets.ClassesBackground.Env.Barriers.Barrier  L400 / L21526  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] ReplicatedStorage.Assets.ClassesBackground.Env.Barriers.Model.Barrier  L410 / L21536  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] ReplicatedStorage.Assets.ClassesBackground.Env.Barriers.Model.Barrier  L419 / L21545  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] ReplicatedStorage.Assets.ClassesBackground.Env.Barriers.Barrier  L428 / L21554  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] ReplicatedStorage.Assets.ClassesBackground.Env.Barriers.Barrier  L437 / L21563  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] ReplicatedStorage.Assets.PeelingMachine  L817 / L21943  ATTRS: RBX_ReimportId = "76147fce-af5d-4a07-874f-a52b5c5e4041"
[Model] ReplicatedStorage.Assets.Potatoes.Minigame.SwissKnife.DiamondUnpeeledPotatoForMinigame  L1088 / L22214  ATTRS: RBX_ReimportId = "aa37281c-b75b-4f2f-be77-b4ab6f195e9b"
[Model] ReplicatedStorage.Assets.Potatoes.Minigame.SwissKnife.GoldenUnpeeledPotatoForMinigame  L1098 / L22224  ATTRS: RBX_ReimportId = "aa37281c-b75b-4f2f-be77-b4ab6f195e9b"
[Model] ReplicatedStorage.Assets.Potatoes.Minigame.SwissKnife.UnpeeledPotatoForMinigame  L1108 / L22234  ATTRS: RBX_ReimportId = "aa37281c-b75b-4f2f-be77-b4ab6f195e9b"
[Model] ReplicatedStorage.Assets.Potatoes.Minigame.SwissKnife.RainbowUnpeeledPotatoForMinigame  L1115 / L22241  ATTRS: RBX_ReimportId = "aa37281c-b75b-4f2f-be77-b4ab6f195e9b"
[Model] ReplicatedStorage.Assets.Potatoes.KeyPotatoes.TutKeyPotato  L1153 / L22279  ATTRS: RBX_ReimportId = "93ee30cb-be91-4c7f-b14b-69f0473b5b76"
[Model] ReplicatedStorage.Assets.Potatoes.KeyPotatoes.SwissKnifeKeyPotato  L1171 / L22297  ATTRS: RBX_ReimportId = "aa37281c-b75b-4f2f-be77-b4ab6f195e9b"
[Model] ReplicatedStorage.Assets.Shovel  L1186 / L22312  ATTRS: RBX_ReimportId = "1a9d668f-a561-4b36-86ba-a10732a5f7f0"
[Model] ReplicatedStorage.Assets.MinigameTools.SwissKnife  L6659 / L27785  ATTRS: RBX_ReimportId = "f1ab1d0a-90c0-4548-82fe-4ed78e91f7e9"
[Model] ReplicatedStorage.Assets.MinigameTools.TriplePeeler  L6665 / L27791  ATTRS: RBX_ReimportId = "538890af-fc8a-45c8-9e35-468a86dcb399"
[Folder] ReplicatedStorage.XocoatlSaves.ColorPresets.My Palette  L8488 / L29614  ATTRS: Xocoatl_FolderId = "{40aff5749eb"
[Model] Workspace.Map.Env.Fences.Model.Model.fence  L9100 / L30226  ATTRS: RBX_ReimportId = "27462d01-427b-4a25-9787-c6e42e9941f3"
[Model] Workspace.Map.Env.Fences.Model.Model.fence  L9110 / L30236  ATTRS: RBX_ReimportId = "27462d01-427b-4a25-9787-c6e42e9941f3"
[Model] Workspace.Map.Env.Fences.Model.Model.fence  L9120 / L30246  ATTRS: RBX_ReimportId = "27462d01-427b-4a25-9787-c6e42e9941f3"
[Model] Workspace.Map.Env.Fences.Model.Model.fence  L9130 / L30256  ATTRS: RBX_ReimportId = "27462d01-427b-4a25-9787-c6e42e9941f3"
[Model] Workspace.Map.Env.Fences.Model.fence  L9140 / L30266  ATTRS: RBX_ReimportId = "27462d01-427b-4a25-9787-c6e42e9941f3"
[Model] Workspace.Map.Env.Fences.Model.Model.fence  L9151 / L30277  ATTRS: RBX_ReimportId = "27462d01-427b-4a25-9787-c6e42e9941f3"
[Model] Workspace.Map.Env.Fences.Model.Model.fence  L9161 / L30287  ATTRS: RBX_ReimportId = "27462d01-427b-4a25-9787-c6e42e9941f3"
[Model] Workspace.Map.Env.Fences.Model.Model.fence  L9171 / L30297  ATTRS: RBX_ReimportId = "27462d01-427b-4a25-9787-c6e42e9941f3"
[Model] Workspace.Map.Env.Fences.Model.Model.fence  L9181 / L30307  ATTRS: RBX_ReimportId = "27462d01-427b-4a25-9787-c6e42e9941f3"
[Model] Workspace.Map.Env.Fences.Model.Model.fence  L9192 / L30318  ATTRS: RBX_ReimportId = "27462d01-427b-4a25-9787-c6e42e9941f3"
[Model] Workspace.Map.Env.Fences.Model.Model.fence  L9201 / L30327  ATTRS: RBX_ReimportId = "27462d01-427b-4a25-9787-c6e42e9941f3"
[Model] Workspace.Map.Env.Fences.Model.Model.fence  L9210 / L30336  ATTRS: RBX_ReimportId = "27462d01-427b-4a25-9787-c6e42e9941f3"
[Model] Workspace.Map.Env.Fences.Model.Model.fence  L9219 / L30345  ATTRS: RBX_ReimportId = "27462d01-427b-4a25-9787-c6e42e9941f3"
[Model] Workspace.Map.Env.Fences.Model.Model.fence  L9228 / L30354  ATTRS: RBX_ReimportId = "27462d01-427b-4a25-9787-c6e42e9941f3"
[Model] Workspace.Map.Env.Fences.Model.Model.fence  L9237 / L30363  ATTRS: RBX_ReimportId = "27462d01-427b-4a25-9787-c6e42e9941f3"
[Model] Workspace.Map.Env.Fences.Model.Model.fence  L9246 / L30372  ATTRS: RBX_ReimportId = "27462d01-427b-4a25-9787-c6e42e9941f3"
[Model] Workspace.Map.Env.Fences.Model.Model.fence  L9255 / L30381  ATTRS: RBX_ReimportId = "27462d01-427b-4a25-9787-c6e42e9941f3"
[Model] Workspace.Map.Env.Fences.Model.Model.fence  L9265 / L30391  ATTRS: RBX_ReimportId = "27462d01-427b-4a25-9787-c6e42e9941f3"
[Model] Workspace.Map.Env.Fences.Model.Model.fence  L9275 / L30401  ATTRS: RBX_ReimportId = "27462d01-427b-4a25-9787-c6e42e9941f3"
[Model] Workspace.Map.Env.Fences.Model.Model.fence  L9285 / L30411  ATTRS: RBX_ReimportId = "27462d01-427b-4a25-9787-c6e42e9941f3"
[Model] Workspace.Map.Env.Fences.Model.fence  L9295 / L30421  ATTRS: RBX_ReimportId = "27462d01-427b-4a25-9787-c6e42e9941f3"
[Model] Workspace.Map.Env.Fences.Model.Model.fence  L9306 / L30432  ATTRS: RBX_ReimportId = "27462d01-427b-4a25-9787-c6e42e9941f3"
[Model] Workspace.Map.Env.Fences.Model.Model.fence  L9315 / L30441  ATTRS: RBX_ReimportId = "27462d01-427b-4a25-9787-c6e42e9941f3"
[Model] Workspace.Map.Env.Fences.Model.Model.fence  L9325 / L30451  ATTRS: RBX_ReimportId = "27462d01-427b-4a25-9787-c6e42e9941f3"
[Model] Workspace.Map.Env.Fences.Model.Model.fence  L9335 / L30461  ATTRS: RBX_ReimportId = "27462d01-427b-4a25-9787-c6e42e9941f3"
[Model] Workspace.Map.Env.Fences.Model.Model.fence  L9345 / L30471  ATTRS: RBX_ReimportId = "27462d01-427b-4a25-9787-c6e42e9941f3"
[Model] Workspace.Map.Env.Fences.Model.fence  L9355 / L30481  ATTRS: RBX_ReimportId = "27462d01-427b-4a25-9787-c6e42e9941f3"
[Model] Workspace.Map.Env.Fences.Model.fence  L9365 / L30491  ATTRS: RBX_ReimportId = "27462d01-427b-4a25-9787-c6e42e9941f3"
[Model] Workspace.Map.Env.Barriers.Barrier  L9414 / L30540  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Env.Barriers.Barrier  L9423 / L30549  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Env.Barriers.Barrier  L9432 / L30558  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Env.Barriers.Barrier  L9441 / L30567  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Env.Barriers.Barrier  L9450 / L30576  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Env.Barriers.Barrier  L9459 / L30585  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Env.Barriers.Barrier  L9468 / L30594  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Env.Barriers.Barrier  L9477 / L30603  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Env.Barriers.Barrier  L9486 / L30612  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Env.Barriers.Model.Barrier  L9496 / L30622  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Env.Barriers.Model.Barrier  L9505 / L30631  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Env.Barriers.Model.Barrier  L9514 / L30640  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Env.Barriers.Model.Barrier  L9523 / L30649  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Env.Barriers.Model.Barrier  L9533 / L30659  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Env.Barriers.Model.Barrier  L9542 / L30668  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Env.Barriers.Model.Barrier  L9551 / L30677  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Env.Barriers.Model.Barrier  L9561 / L30687  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Env.Barriers.Model.Barrier  L9570 / L30696  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Env.Barriers.Barrier  L9579 / L30705  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Env.Barriers.Barrier  L9588 / L30714  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Env.Barriers.Model.Barrier  L9598 / L30724  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Env.Barriers.Model.Barrier  L9607 / L30733  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Env.Barriers.Barrier  L9616 / L30742  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Env.Barriers.Barrier  L9625 / L30751  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Env.Barriers.Barrier  L9634 / L30760  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Env.Barriers.Model.Barrier  L9644 / L30770  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Env.Barriers.Model.Barrier  L9653 / L30779  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Env.Barriers.Model.Barrier  L9662 / L30788  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Env.Barriers.Model.Barrier  L9671 / L30797  ATTRS: RBX_ReimportId = "65e9af14-d06a-4345-8be4-7ccf254cf4a1"
[Model] Workspace.Map.Zones.MatchmakingZones.4  L10232 / L31358  ATTRS: QueueState = "Empty"
[Model] Workspace.Map.Zones.MatchmakingZones.3  L10256 / L31382  ATTRS: QueueState = "Countdown"
[Model] Workspace.Map.Zones.MatchmakingZones.1  L10280 / L31406  ATTRS: QueueState = "Countdown"
[Model] Workspace.Map.Zones.MatchmakingZones.2  L10304 / L31430  ATTRS: QueueState = "Empty"
[Model] Workspace.Map.Zones.GroupGiftZone.Gift  L10333 / L31459  ATTRS: RBX_ReimportId = "7ae156f3-ca87-418c-b68b-35a566be1322"
[MeshPart] Workspace.Players.CherysseAK.MediHood.Handle  L10433 / L31559  ATTRS: RBXRefinementScale = 1, 1, 1
[MeshPart] Workspace.Players.Tu4nLogg.Pal Hair.Handle  L11057 / L32183  ATTRS: RBXRefinementScale = 1, 1, 1
[MeshPart] Workspace.Players.Kuimi16.LavanderHair.Handle  L11498 / L32624  ATTRS: RBXRefinementScale = 1, 1, 1
[MeshPart] Workspace.Players.Kuimi16.RobloxVisor2019.Handle  L11510 / L32636  ATTRS: RBXRefinementScale = 1, 1, 1
[MeshPart] Workspace.Players.znskwowiwiwiwu.Accessory (propellerhat).Handle  L12083 / L33209  ATTRS: RBXRefinementScale = 1, 1, 1
[MeshPart] Workspace.Players.znskwowiwiwiwu.Accessory (default).Handle  L12095 / L33221  ATTRS: RBXRefinementScale = 1, 1, 1
[MeshPart] Workspace.Players.znskwowiwiwiwu.Accessory (Duck float).Handle  L12107 / L33233  ATTRS: RBXRefinementScale = 1, 1, 1
[MeshPart] Workspace.Players.3156470584why.Accessory (Anime Wolf Cut Hair).Handle  L12526 / L33652  ATTRS: RBXRefinementScale = 1, 1, 1
[MeshPart] Workspace.Players.3156470584why.3.0 Kawaii Tooth Choker.Handle  L12569 / L33695  ATTRS: RBXRefinementScale = 1, 1, 1
[MeshPart] Workspace.Players.3156470584why.Accessory (New).Handle  L12581 / L33707  ATTRS: RBXRefinementScale = 1, 1, 1
[MeshPart] Workspace.Players.3156470584why.Accessory (Chibi Doll Bikini Skirt - Blue).Handle  L12593 / L33719  ATTRS: RBXRefinementScale = 1, 1, 1
[MeshPart] Workspace.Players.3156470584why.Accessory (Launched_Employees).Handle  L12605 / L33731  ATTRS: RBXRefinementScale = 1, 1, 1
[MeshPart] Workspace.Players.3156470584why.Accessory (MeshPartAccessory).Handle  L12618 / L33744  ATTRS: RBXRefinementScale = 1, 1, 1
[MeshPart] Workspace.Players.3156470584why.Accessory (Anime Girl Hairstyle).Handle  L12630 / L33756  ATTRS: RBXRefinementScale = 1, 1, 1
[MeshPart] Workspace.Players.cylyaf.Accessory (Sakura Braided Windy Ponytail White&Pink).Handle  L13218 / L34344  ATTRS: RBXRefinementScale = 1, 1, 1
[MeshPart] Workspace.Players.lwtwtnp.BoySpaceHair.Handle  L14473 / L35599  ATTRS: RBXRefinementScale = 1, 1, 1
[MeshPart] Workspace.Players.Duckchupchip.VarietyShades02.Handle  L14998 / L36124  ATTRS: RBXRefinementScale = 1, 1, 1
[MeshPart] Workspace.Players.Duckchupchip.light_fae.Handle  L15008 / L36134  ATTRS: RBXRefinementScale = 1, 1, 1
[MeshPart] Workspace.Players.reaaaaaaaaa02_0.HairAccessory.Handle  L15560 / L36686  ATTRS: RBXRefinementScale = 1, 1, 1
[MeshPart] Workspace.Players.sru_1128.RobloxVisor2019.Handle  L16071 / L37197  ATTRS: RBXRefinementScale = 1, 1, 1
[MeshPart] Workspace.Players.sru_1128.light_fae.Handle  L16081 / L37207  ATTRS: RBXRefinementScale = 1, 1, 1
[MeshPart] Workspace.Players.sru_1128.LongStraightHair.Handle  L16094 / L37220  ATTRS: RBXRefinementScale = 1, 1, 1
[ScreenGui] Players.lwtwtnp.PlayerGui.TopbarStandard  L16289 / L37415  ATTRS: StartInset = 8
[ScrollingFrame] Players.lwtwtnp.PlayerGui.TopbarStandard.Holders.Left  L16293 / L37419  ATTRS: IsAHolder = true
[Frame] Players.lwtwtnp.PlayerGui.TopbarStandard.Holders.Left.Widget  L16297 / L37423  ATTRS: BorderSize = 4, DesiredWidth = 44, MinimumHeight = 44, MinimumWidth = 44, TargetWidth = 66, WidgetUID = "5ICYbws}"
[UICorner] Players.lwtwtnp.PlayerGui.TopbarStandard.Holders.Left.Widget.IconButton.UICorner  L16306 / L37432  ATTRS: Collective = "IconCorners"
[ScrollingFrame] Players.lwtwtnp.PlayerGui.TopbarStandard.Holders.Left.Widget.IconButton.Menu  L16309 / L37435  ATTRS: MaxIcons = 4
[UICorner] Players.lwtwtnp.PlayerGui.TopbarStandard.Holders.Left.Widget.IconButton.Menu.IconSpot.UICorner  L16315 / L37441  ATTRS: Collective = "IconCorners"
[UICorner] Players.lwtwtnp.PlayerGui.TopbarStandard.Holders.Left.Widget.IconButton.Menu.IconSpot.IconOverlay.OverlayUICorner  L16319 / L37445  ATTRS: Collective = "IconCorners"
[TextButton] Players.lwtwtnp.PlayerGui.TopbarStandard.Holders.Left.Widget.IconButton.Menu.IconSpot.ClickRegion  L16322 / L37448  ATTRS: CorrespondingIconUID = "5ICYbws}"
[UICorner] Players.lwtwtnp.PlayerGui.TopbarStandard.Holders.Left.Widget.IconButton.Menu.IconSpot.ClickRegion.UICorner  L16325 / L37451  ATTRS: Collective = "IconCorners"
[Frame] Players.lwtwtnp.PlayerGui.TopbarStandard.Holders.Left.Widget  L16343 / L37469  ATTRS: BorderSize = 4, DesiredWidth = 44, MinimumHeight = 44, MinimumWidth = 44, TargetWidth = 44, WidgetUID = "Al{3~k{~"
[UICorner] Players.lwtwtnp.PlayerGui.TopbarStandard.Holders.Left.Widget.IconButton.UICorner  L16352 / L37478  ATTRS: Collective = "IconCorners"
[ScrollingFrame] Players.lwtwtnp.PlayerGui.TopbarStandard.Holders.Left.Widget.IconButton.Menu  L16355 / L37481  ATTRS: MaxIcons = 4
[UICorner] Players.lwtwtnp.PlayerGui.TopbarStandard.Holders.Left.Widget.IconButton.Menu.IconSpot.UICorner  L16361 / L37487  ATTRS: Collective = "IconCorners"
[UICorner] Players.lwtwtnp.PlayerGui.TopbarStandard.Holders.Left.Widget.IconButton.Menu.IconSpot.IconOverlay.OverlayUICorner  L16365 / L37491  ATTRS: Collective = "IconCorners"
[TextButton] Players.lwtwtnp.PlayerGui.TopbarStandard.Holders.Left.Widget.IconButton.Menu.IconSpot.ClickRegion  L16368 / L37494  ATTRS: CorrespondingIconUID = "Al{3~k{~"
[UICorner] Players.lwtwtnp.PlayerGui.TopbarStandard.Holders.Left.Widget.IconButton.Menu.IconSpot.ClickRegion.UICorner  L16371 / L37497  ATTRS: Collective = "IconCorners"
[Frame] Players.lwtwtnp.PlayerGui.TopbarStandard.Holders.Left.OverflowLeft  L16388 / L37514  ATTRS: BorderSize = 4, DesiredWidth = 44, MinimumHeight = 44, MinimumWidth = 44, TargetWidth = 55, WidgetUID = "hFO]~aMo"
[UICorner] Players.lwtwtnp.PlayerGui.TopbarStandard.Holders.Left.OverflowLeft.IconButton.UICorner  L16397 / L37523  ATTRS: Collective = "IconCorners"
[ScrollingFrame] Players.lwtwtnp.PlayerGui.TopbarStandard.Holders.Left.OverflowLeft.IconButton.Menu  L16400 / L37526  ATTRS: MaxIcons = 4, MaxWidth = 486
[UICorner] Players.lwtwtnp.PlayerGui.TopbarStandard.Holders.Left.OverflowLeft.IconButton.Menu.IconSpot.UICorner  L16407 / L37533  ATTRS: Collective = "IconCorners"
[UICorner] Players.lwtwtnp.PlayerGui.TopbarStandard.Holders.Left.OverflowLeft.IconButton.Menu.IconSpot.IconOverlay.OverlayUICorner  L16411 / L37537  ATTRS: Collective = "IconCorners"
[TextButton] Players.lwtwtnp.PlayerGui.TopbarStandard.Holders.Left.OverflowLeft.IconButton.Menu.IconSpot.ClickRegion  L16414 / L37540  ATTRS: CorrespondingIconUID = "hFO]~aMo"
[UICorner] Players.lwtwtnp.PlayerGui.TopbarStandard.Holders.Left.OverflowLeft.IconButton.Menu.IconSpot.ClickRegion.UICorner  L16417 / L37543  ATTRS: Collective = "IconCorners"
[ScrollingFrame] Players.lwtwtnp.PlayerGui.TopbarStandard.Holders.Right  L16438 / L37564  ATTRS: IsAHolder = true
[ScrollingFrame] Players.lwtwtnp.PlayerGui.TopbarCentered.Holders.Center  L16444 / L37570  ATTRS: IsAHolder = true
[UIStroke] Players.lwtwtnp.PlayerGui.Notifications.Notifications.Templates.Info.TextLabel.UIStroke  L19497 / L40623  ATTRS: DesktopThickness = 3
[UIStroke] Players.lwtwtnp.PlayerGui.Notifications.Notifications.Templates.Error.TextLabel.UIStroke  L19502 / L40628  ATTRS: DesktopThickness = 3
[UIStroke] Players.lwtwtnp.PlayerGui.Notifications.Notifications.Templates.Success.TextLabel.UIStroke  L19507 / L40633  ATTRS: DesktopThickness = 3
[ImageButton] Players.lwtwtnp.PlayerGui.Queue.Setup.Content.CreateHolder.Create  L19741 / L40867  ATTRS: HoverScale = 1.025
[UIStroke] Players.lwtwtnp.PlayerGui.Tutorial.Panel.Step.UIStroke  L20153 / L41279  ATTRS: DesktopThickness = 3
[UIStroke] Players.lwtwtnp.PlayerGui.Tutorial.Panel.Objective.UIStroke  L20157 / L41283  ATTRS: DesktopThickness = 4
[UIStroke] Players.lwtwtnp.PlayerGui.Tutorial.Panel.Objective.DialogueLetters.S.UIStroke  L20163 / L41289  ATTRS: DesktopThickness = 4
[UIStroke] Players.lwtwtnp.PlayerGui.Tutorial.Panel.Objective.DialogueLetters.T.UIStroke  L20168 / L41294  ATTRS: DesktopThickness = 4
[UIStroke] Players.lwtwtnp.PlayerGui.Tutorial.Panel.Objective.DialogueLetters.E.UIStroke  L20173 / L41299  ATTRS: DesktopThickness = 4
[UIStroke] Players.lwtwtnp.PlayerGui.Tutorial.Panel.Objective.DialogueLetters.P.UIStroke  L20178 / L41304  ATTRS: DesktopThickness = 4
[UIStroke] Players.lwtwtnp.PlayerGui.Tutorial.Panel.Objective.DialogueLetters.O.UIStroke  L20183 / L41309  ATTRS: DesktopThickness = 4
[UIStroke] Players.lwtwtnp.PlayerGui.Tutorial.Panel.Objective.DialogueLetters.N.UIStroke  L20188 / L41314  ATTRS: DesktopThickness = 4
[UIStroke] Players.lwtwtnp.PlayerGui.Tutorial.Panel.Objective.DialogueLetters.A.UIStroke  L20193 / L41319  ATTRS: DesktopThickness = 4
[UIStroke] Players.lwtwtnp.PlayerGui.Tutorial.Panel.Objective.DialogueLetters.N.UIStroke  L20198 / L41324  ATTRS: DesktopThickness = 4
[UIStroke] Players.lwtwtnp.PlayerGui.Tutorial.Panel.Objective.DialogueLetters.E.UIStroke  L20203 / L41329  ATTRS: DesktopThickness = 4
[UIStroke] Players.lwtwtnp.PlayerGui.Tutorial.Panel.Objective.DialogueLetters.M.UIStroke  L20209 / L41335  ATTRS: DesktopThickness = 4
[UIStroke] Players.lwtwtnp.PlayerGui.Tutorial.Panel.Objective.DialogueLetters.P.UIStroke  L20215 / L41341  ATTRS: DesktopThickness = 4
[UIStroke] Players.lwtwtnp.PlayerGui.Tutorial.Panel.Objective.DialogueLetters.T.UIStroke  L20221 / L41347  ATTRS: DesktopThickness = 4
[UIStroke] Players.lwtwtnp.PlayerGui.Tutorial.Panel.Objective.DialogueLetters.Y.UIStroke  L20227 / L41353  ATTRS: DesktopThickness = 4
[UIStroke] Players.lwtwtnp.PlayerGui.Tutorial.Panel.Objective.DialogueLetters.Q.UIStroke  L20233 / L41359  ATTRS: DesktopThickness = 4
[UIStroke] Players.lwtwtnp.PlayerGui.Tutorial.Panel.Objective.DialogueLetters.U.UIStroke  L20239 / L41365  ATTRS: DesktopThickness = 4
[UIStroke] Players.lwtwtnp.PlayerGui.Tutorial.Panel.Objective.DialogueLetters.E.UIStroke  L20245 / L41371  ATTRS: DesktopThickness = 4
[UIStroke] Players.lwtwtnp.PlayerGui.Tutorial.Panel.Objective.DialogueLetters.U.UIStroke  L20251 / L41377  ATTRS: DesktopThickness = 4
[UIStroke] Players.lwtwtnp.PlayerGui.Tutorial.Panel.Objective.DialogueLetters.E.UIStroke  L20257 / L41383  ATTRS: DesktopThickness = 4
[UIStroke] Players.lwtwtnp.PlayerGui.Tutorial.Panel.Objective.DialogueLetters.T.UIStroke  L20263 / L41389  ATTRS: DesktopThickness = 4
[UIStroke] Players.lwtwtnp.PlayerGui.Tutorial.Panel.Objective.DialogueLetters.O.UIStroke  L20268 / L41394  ATTRS: DesktopThickness = 4
[UIStroke] Players.lwtwtnp.PlayerGui.Tutorial.Panel.Objective.DialogueLetters.S.UIStroke  L20273 / L41399  ATTRS: DesktopThickness = 4
[UIStroke] Players.lwtwtnp.PlayerGui.Tutorial.Panel.Objective.DialogueLetters.T.UIStroke  L20278 / L41404  ATTRS: DesktopThickness = 4
[UIStroke] Players.lwtwtnp.PlayerGui.Tutorial.Panel.Objective.DialogueLetters.A.UIStroke  L20283 / L41409  ATTRS: DesktopThickness = 4
[UIStroke] Players.lwtwtnp.PlayerGui.Tutorial.Panel.Objective.DialogueLetters.R.UIStroke  L20288 / L41414  ATTRS: DesktopThickness = 4
[UIStroke] Players.lwtwtnp.PlayerGui.Tutorial.Panel.Objective.DialogueLetters.T.UIStroke  L20293 / L41419  ATTRS: DesktopThickness = 4
[UIStroke] Players.lwtwtnp.PlayerGui.Tutorial.Panel.Objective.DialogueLetters.A.UIStroke  L20298 / L41424  ATTRS: DesktopThickness = 4
[UIStroke] Players.lwtwtnp.PlayerGui.Tutorial.Panel.Objective.DialogueLetters.G.UIStroke  L20303 / L41429  ATTRS: DesktopThickness = 4
[UIStroke] Players.lwtwtnp.PlayerGui.Tutorial.Panel.Objective.DialogueLetters.A.UIStroke  L20308 / L41434  ATTRS: DesktopThickness = 4
[UIStroke] Players.lwtwtnp.PlayerGui.Tutorial.Panel.Objective.DialogueLetters.M.UIStroke  L20313 / L41439  ATTRS: DesktopThickness = 4
[UIStroke] Players.lwtwtnp.PlayerGui.Tutorial.Panel.Objective.DialogueLetters.E.UIStroke  L20318 / L41444  ATTRS: DesktopThickness = 4
[UIStroke] Players.lwtwtnp.PlayerGui.Tutorial.Panel.Progress.UIStroke  L20323 / L41449  ATTRS: DesktopThickness = 3
```

### 4.3 Attribute-name census (excluding the 92 protocol ids)

```
GAME (163 instances, pass 1):
  19 non-protocol attr names:
  RBX_ReimportId: 107
  DesktopThickness: 26
  PotatoCount: 6
  PotatoKinds: 6
  EmitCount: 4
  EmitDelay: 4
  PeelToolId: 4
  CarryLevel: 3
  IsAHolder: 3
  Machine: 2
  ToolId: 2
  IsReservedServer: 1
  Xocoatl_FolderId: 1
  HeldContainerName: 1
  HeldKinds: 1
  RBXRefinementScale: 1
  Gamepass: 1
  StartInset: 1
  HoverScale: 1

LOBBY:
  19 non-protocol attr names:
  RBX_ReimportId: 80
  DesktopThickness: 36
  RBXRefinementScale: 22
  Collective: 12
  QueueState: 4
  IsAHolder: 3
  BorderSize: 3
  DesiredWidth: 3
  MinimumHeight: 3
  MinimumWidth: 3
  TargetWidth: 3
  WidgetUID: 3
  MaxIcons: 3
  CorrespondingIconUID: 3
  IsReservedServer: 1
  Xocoatl_FolderId: 1
  StartInset: 1
  MaxWidth: 1
  HoverScale: 1
```

Semantics of the gameplay attributes (game place, all on Workspace.Map instances):

- `Machine` (`"AutoPeelingMachine"`/`"PeelingMachine"`, L11114/L11274) — machine type id on machine models.
- `PotatoCount` + `PotatoKinds` (on machine `Cube.NN`/`PotatoArea` parts, L11147/L11161/L11313/L11321/L11645/L11702) —
  server-synced per-slot potato contents; kinds is a concatenated digit string (player attr `HeldKinds = "1113"`, L8557).
- `ToolId` (`"PotatoSucker"`/`"Shovel"`), `PeelToolId` (`"Peeler"`/`"Knife"`/`"TriplePeeler"`/`"SwissKnife"`),
  `CarryLevel` (2/3/4 on Bucket/PotatoSack/MechaCapsule), `Gamepass` (`"Blackhole"`) — shop item ids.
- `EmitCount`/`EmitDelay` (ParticleEmitters, e.g. L11786) — cosmetic particle config.
- `HeldContainerName`/`HeldKinds` on the player model (L8557) — held-potato state.
- `QueueState` (lobby matchmaking zone models `Zones.MatchmakingZones.1–4`, lobby:game_dump.txt:L10280/L10256/L10304/L10232) —
  `"Empty"`/`"Countdown"`/`"Teleporting"` — the lobby queue state machine the harness must emulate.
- topbarplus widget attrs (`WidgetUID`, `Collective`, `MaxIcons`, `BorderSize`, …) — GUI framework internals, ignore.
- `RBX_ReimportId` / `RBXRefinementScale` — Roblox 3D-import metadata, ignore.

---

## 5) Workspace trees

### 5.1 GAME place — top level (13 children)

```
[Camera]      Workspace.Camera            L8545/L35695   (children: AudioListener L8546 + Wire L8547, FlyingPotatoes L8548 (empty),
                                            HeldPotatoes L8549 (4 MeshPart "Root" L8550-L8553), HeldTool L8555 (empty))
[Folder]      Workspace.Players           L8556/L35706   (1 character model: lwtwtnp L8557)
[Folder]      Workspace.Preload           L9061          (empty)
[Folder]      Workspace.Effects           L9062          (empty)
[Folder]      Workspace.Map               L9063/L36213   (the round map, §5.3)
[Terrain]     Workspace.Terrain           L12087         (Attachment L12088 + Beam L12090)
[Camera]      Workspace.Hidden            L12091         (hidden camera, no children)
[Folder]      Workspace.StretchArms       L12092         (empty — arm-stretch ragdoll FX target)
[Folder]      Workspace.SpectatedPeeling  L12093         (empty — spectate peel minigame container)
[Folder]      Workspace.PotatoStacks      L12094         (empty)
[Folder]      Workspace.WaterwayPotatoes  L12095         (empty — waterway conveyor potatoes)
[Folder]      Workspace.OthersHeldPotatoes L12096        (empty)
[Folder]      Workspace.PotatoPile        L12097/L39247  (THE pile: Highlight L12098 + 11,748 MeshPart "Root"
                                            L12099–L25107, 1,261 with SurfaceAppearance; 13,011 instances total)
```

### 5.2 LOBBY place — top level (7 children)

```
[Camera]        Workspace.Camera     L8545/L29671   (only AudioListener L8546 + Wire L8547 — no held-potato folders in lobby)
[Folder]        Workspace.Preload    L8548          (empty)
[Folder]        Workspace.Effects    L8549          (empty)
[Folder]        Workspace.Map        L8550/L29676   (lobby map, §5.4)
[Folder]        Workspace.Players    L10356         (11 character models: CherysseAK L10357, Tu4nLogg L10876,
                                                 Kuimi16 L11397, znskwowiwiwiwu L11917, 3156470584why L12449,
                                                 cylyaf L13037, Max_117M00 L13547, lwtwtnp L14044, Duckchupchip L14562,
                                                 reaaaaaaaaa02_0 L15123, sru_1128 L15651)
[Terrain]       Workspace.Terrain    L16203         (Attachment L16204 + Beam L16206)
[Camera]        Workspace.Hidden     L16207
```

### 5.3 GAME `Workspace.Map` subtree (round map)

```
Workspace.Map  (Folder, L9063)
├─ Waterway            (Folder L9064: MainPath L9065, MachinesChannel L9069)   — potato waterway conveyor
├─ CutsceneLocations   (Folder L9077: CameraLocationBunker L9078, SplatZone L9079)
├─ RadioTable          (Model L9080, incl. Radio.AudioEmitter L9091)
├─ InvisibleBarriers   (Folder L9092: many Parts)
├─ Map                 (Folder L9100 — the bunker environment:
│     Barriers L9101, Fences L9332, Crates L9476, OutsideBunker L9523, FloorMeshes L9653, Outside L9662
│     (Rocks L9663, Snow L9721, Trees L9754, PotatoZone L10083), InsideBunker L10107 (LightSources L10108,
│     GroundHay L10173, Pipes L10236, BunkerWalls L10302, VaultDoor L10615 incl. KeyHole UNLOCK prompt L10621,
│     Store L10642, Model L10653, Title L10749), Flyers L10761, Baseplate L10774, SnowVFX L10775)
├─ PotRoom             (Folder L10777: Pot L10778, Conveyor L10786, PotLight L10811, PotPipes L11052, PotPath L11103)
├─ PeelingMachines     (Folder L11113 — see table below)
├─ PotatoPile          (Part L11709 — pile trigger zone)
├─ SpawnPoint          (Part L11710)
├─ Speaker             (MeshPart L11711, AudioEmitter L11712)
├─ InsideBunker        (Part L11713 — bunker bounds)
└─ StoreItems          (Folder L11714 — see table below; all pass-2 lines = +27,150)
```

**PeelingMachines (game) — the machine/sell/peel stations:**

| Instance | Provenance | Attributes / prompts |
|---|---|---|
| `AutoPeelingMachine` | L11114 | `Machine="AutoPeelingMachine"`; LOAD prompt on `Cube.042.Load` L11165; LOCKED price prompt L11193; engine `AudioPlayer` L11168 |
| `PeelingMachine` (hand peeler) | L11274 | `Machine="PeelingMachine"`; LOAD prompt `Cube.033.Load` L11317; CRANK prompt L11350 (`Hand Peeler (0/3)`); LOCKED L11346 |
| `PeelingTable1–4` | L11196 / L11353 / L11431 / L11509 | PEEL prompt `TabelTop.PeelPrompt.Peel` (L11262, L11419, L11497, L11575) |
| `SellCrate` | L11587 | SELL prompt `PotatoArea.SellPrompt` L11649; `PotatoCount`/`PotatoKinds` attrs on `PotatoArea` L11645 |
| `PotatoCrate` | L11652 | PLACE prompt `PotatoArea.PlacePrompt` L11706 |

**StoreItems (game) — the shop floor:**

| Path | Provenance | Attrs |
|---|---|---|
| `StoreItems.Robux.Blackhole` | L11716 | `Gamepass="Blackhole"`; BUY PERMANENT R$99 / BUY ONE ROUND R$19 prompts L11761/L11764 |
| `StoreItems.Tools.P0T4T0-3000` | L11768 | `ToolId="PotatoSucker"`; LOCKED L11808 |
| `StoreItems.Tools.Shovel` | L11811 | `ToolId="Shovel"`; BUY $3.00 L11833 |
| `StoreItems.Storage.MechaCapsule` | L11837 | `CarryLevel=4`; LOCKED L11873 |
| `StoreItems.Storage.Bucket` | L11876 | `CarryLevel=2`; PURCHASE BUCKET $0.50 L11909 |
| `StoreItems.Storage.PotatoSack` | L11912 | `CarryLevel=3`; LOCKED L11942 |
| `StoreItems.Peelers.Peeler` | L11946 | `PeelToolId="Peeler"`; LOCKED L11974 |
| `StoreItems.Peelers.Knife` | L11977 | `PeelToolId="Knife"`; BUY $0.01 L12004 |
| `StoreItems.Peelers.TriplePeeler` | L12007 | `PeelToolId="TriplePeeler"`; LOCKED L12052 |
| `StoreItems.Peelers.SwissKnife` | L12055 | `PeelToolId="SwissKnife"`; LOCKED L12084 |

### 5.4 LOBBY `Workspace.Map` subtree

```
Workspace.Map  (Folder, L8550)
├─ FloorMeshes        (Folder L8551)
├─ Leaderboards       (Folder L8560: TotalWins L8561, PotatoesCollected L8586, TimeRecord L8716 — SurfaceGui boards)
├─ Shops              (Folder L8757: UpgradesShop L8758 (Model L8759, Title L8760), ClassesShop L8796)
├─ InvisibleBarriers  (Folder L8834)
├─ Env                (Folder L8842: Extras L8843, Fences L9097, Crates L9374, Barriers L9413, Outside L9680)
├─ Zones              (Folder L10216: ShopZone L10217, ClassesZone L10224,
│                       MatchmakingZones L10231 → 4 L10232, 3 L10256, 1 L10280, 2 L10304 (each QueueState attr),
│                       GroupGiftZone L10328 incl. Gift L10333)
└─ SpawnLocation      (SpawnLocation L10355; all lobby pass-2 lines = +21,126)
```

### 5.5 Game-only vs lobby-only (Workspace)

| | game only | lobby only |
|---|---|---|
| top level | `StretchArms`, `SpectatedPeeling`, `PotatoStacks`, `WaterwayPotatoes`, `OthersHeldPotatoes`, `PotatoPile` (13,011 inst) | *(none — lobby top level ⊂ game top level)* |
| Map children | `Waterway`, `CutsceneLocations`, `RadioTable`, `PotRoom`, `PeelingMachines`, `PotatoPile`, `SpawnPoint`, `Speaker`, `InsideBunker`, inner `Map` | `FloorMeshes`, `Leaderboards`, `Shops`, `Env`, `Zones`, `SpawnLocation` |
| Camera | `FlyingPotatoes`, `HeldPotatoes`, `HeldTool` folders | *(none)* |
| players | 1 character (lwtwtnp) | 11 characters |

**Potato-themed inventory (the mock-world fixtures):** game `Workspace.PotatoPile` = giant pile (11,748 potato
MeshParts + Highlight, L12097–L25107); the other 5 game-only top folders (`StretchArms`, `SpectatedPeeling`,
`PotatoStacks`, `WaterwayPotatoes`, `OthersHeldPotatoes`) are empty at dump time — *runtime containers*
the server fills; lobby has zero potato-world fixtures — its gameplay surface is queues (`Zones.MatchmakingZones`),
shops, leaderboards. Potato kind models live in RS (§2.4) and are cloned at runtime (the dumper was holding
`HeldKinds="1113"` = 3 kind-1 potatoes + 1 kind-3, game:game_dump.txt:L8557, visible as 4 Root MeshParts in
`Workspace.Camera.HeldPotatoes` L8550–L8553).

---

## 6) Other services / client-facing containers

### 6.1 Services captured

Only 4 services were walked by the dumper (each file, both passes): `ReplicatedFirst` (game:game_dump.txt:L1/L27151 — **empty**),
`ReplicatedStorage` (L2), `Workspace` (L8544), `Players` (L25108 game; L16208 lobby).
**NOT captured anywhere: StarterGui, StarterPlayer, StarterPlayerScripts, StarterPack, SoundService, Lighting, Teams,
Chat, TextChatService, MaterialService, CoreGui, StarterCharacterService** — 0 hits for those service root lines in both files.
Their runtime content is nonetheless visible under the local player:

### 6.2 Players service

| | GAME | LOBBY |
|---|---|---|
| local player | `Players.lwtwtnp` (L25109/L52259) | `Players.lwtwtnp` (L16209/L37335) |
| other players | — | 10 more `[Player]` entries (L21097–L21124): Kuimi16, cylyaf, Tu4anLogg, znskwowiwiwiwu, 3156470584why, Max_117M00, CherysseAK, Duckchupchip, reaaaaaaaaa02_0, sru_1128 — each only `Backpack` + `StarterGear` (both empty) |
| local children | `PlayerScripts` (L25110, 102 instances), `PlayerGui` (L25162, 35 ScreenGuis), `StarterGear` (L27149, empty), `Backpack` (L27150, empty) | `PlayerScripts` (L16210, 102 instances), `PlayerGui` (L16262, 28 ScreenGuis), `StarterGear` (L21095, empty), `Backpack` (L21096, empty) |

No `leaderstats` folder exists in either dump (0 hits) — stats surface through the Packet protocol (`StatsRequest/86`,
`StatsShown/87`) and the `Stats` ScreenGui, not classic leaderstats values.

### 6.3 PlayerScripts (client script inventory — identical in both places, 102 instances/pass)

```
[LocalScript]   Players.lwtwtnp.PlayerScripts.main                     game L25111 / lobby L16211  <- custom bootstrap
[LocalScript]   Players.lwtwtnp.PlayerScripts.RbxCharacterSounds       game L25112 / lobby L16212  (+AtomicBinding module)
[ModuleScript]  Players.lwtwtnp.PlayerScripts.PlayerModule             game L25114 / lobby L16214  (default Roblox camera/controls,
                                                                           ~97 modules: CameraModule, ControlModule, etc.)
[LocalScript]   Players.lwtwtnp.PlayerScripts.PlayerScriptsLoader      game L25161 / lobby L16261
```

Tree-diff of `PlayerScripts` game vs lobby: **identical** (102/102 instances, sorted-path diff empty).
These four scripts are the only LocalScripts belonging to the local player; the 102 client controllers in
`ReplicatedStorage.Controllers` (§2.2b) are required by `main` at runtime.

### 6.4 PlayerGui (runtime GUI inventory, per place)

GAME — 35 top-level GUIs (game:game_dump.txt:L25162–L27135): Cmdr, TopbarCenteredClipped, TopbarStandardClipped,
TopbarStandard, TopbarCentered, Hotbar, Escape, Notifications, PacketChart, Peeling, ExpressivePromptsGui, Queue,
Teleporting, Stats, ToolUpgrades, UpgradesButton, Tutorial, ToolUseButton, SoldPopup, SoldMini, UnlockPopup,
PeelEarnings, CashFlyers, QuestCard, BagPickups, MachineSold, PurchaseCelebration, Timer, FriendBoost, Diamonds,
Crosshair, Cash, Bag, TouchGui.

LOBBY — 28 top-level GUIs (lobby:game_dump.txt:L16262–L21082): Cmdr, TopbarCenteredClipped, TopbarStandardClipped,
TopbarStandard, TopbarCentered, TotalWinsLeaderboard (SurfaceGui), PotatoesCollectedLeaderboard (SurfaceGui),
TimeRecordLeaderboard (SurfaceGui), LobbyUpgrades, LobbyUpgradesButton, Notifications, PacketChart, Peeling,
ExpressivePromptsGui, Queue, Teleporting, Shop, ShopButton, Stats, StatsButton, Tutorial, GroupRewards,
PurchaseCelebration, Diamonds, DailyRewards, Classes, TouchGui.

Game-only GUIs: Hotbar, Escape, ToolUpgrades, UpgradesButton, ToolUseButton, SoldPopup, SoldMini, UnlockPopup,
PeelEarnings, CashFlyers, QuestCard, BagPickups, MachineSold, Timer, FriendBoost, Crosshair, Cash, Bag.
Lobby-only GUIs: TotalWinsLeaderboard, PotatoesCollectedLeaderboard, TimeRecordLeaderboard, LobbyUpgrades,
LobbyUpgradesButton, Shop, ShopButton, StatsButton, GroupRewards, DailyRewards, Classes.
(Shared: Cmdr, topbar×4, Notifications, PacketChart, Peeling, ExpressivePromptsGui, Queue, Teleporting, Stats, Tutorial, PurchaseCelebration, Diamonds, TouchGui.)

### 6.5 Sounds / audio (client-observable)

- GAME: 9 Sound instances/pass, all Roblox character sounds under `Workspace.Players.lwtwtnp.HumanoidRootPart`
  (Climbing/Died/GettingUp/Swimming/Jumping/Landing/Splash/FreeFalling/Running, game:game_dump.txt:L8570–L8578).
  Audio3D: `Camera.AudioListener`+Wire (L8546/L8547), `Map.RadioTable.Radio.AudioEmitter` (L9091),
  `Map.PeelingMachines.AutoPeelingMachine.Cube.042.EngineAutomatic` AudioPlayer+Wire (L11168/L11169) +
  `AudioEmitter` (L11170), `Map.Speaker.AudioEmitter` (L11712).
- LOBBY: 99 Sound instances/pass = the same 9 character sounds × 11 players (e.g. CherysseAK L10555–L10563);
  only `Camera.AudioListener`+Wire as fixed audio (L8546/L8547).
- `SoundService` itself is not in the dumps; `Modules.Resources.Sounds` (RS, L8123) is the sound catalogue module.

### 6.6 Everything else the client touches (from the dumps)

- **Cmdr admin console**: `PlayerGui.Cmdr` (§6.4) + 45 admin command definitions in `ReplicatedStorage.CmdrClient.Commands`
  (§2.2a: AddPeeled, AddUnpeeled, Ban, BanByUserId, Bring, Fly, ForceKey, GivePotatoes, GiveShinies, Help, Kick,
  LogGlobalOverrides, Op, Peel, ResetData, ResetGlobal, SetCash, SetGlobal, Speed, Teleport, Unban, Vanish, GivePeelTool,
  SpawnKey, Gamepass, Carry, Avatar, Money, DumpUi, Dialogue, Tutorial, Cutscene, PileCut, RunPeels, UnlockTools,
  FillLeaderboard, ResetTutorial, FirstPerson, ThirdPerson, SetPeelTool, Sell, Celebrate, FakeReport, Freecam, Perspective).
- **Input remapping**: `ReplicatedStorage.Inputs.InputContext` + 4 InputActions (L8492–L8500).
- **ProximityPrompts** (client interactables — full census): game 26/pass = 3 RS template prompts
  (RS.Assets AutoPeelingMachine L116 + PeelingMachine L840/L843) + 23 workspace prompts (machine LOAD/CRANK/PEEL/SELL/PLACE +
  shop BUY/LOCKED + vault UNLOCK, §5.3 tables); lobby 13/pass = the same 3 RS template prompts + 10 per-player
  `HumanoidRootPart.StatsPrompt` "VIEW STATS" (one for every player except the local lwtwtnp, e.g. lobby:game_dump.txt:L10564).
- **Character rigs**: `Workspace.Players.<name>` models carry Roblox Animate LocalScripts, RagdollConstraints,
  HumanoidDescription, FaceControls etc. — characters are fully client-replicated (needed for the mock world avatars).

---

## Quick stats (for the final report)

- Remote-class instances: **3 per place** (Packet.RemoteEvent + CmdrEvent + CmdrFunction); **92 protocol event ids**;
  0 UnreliableRemoteEvent / BindableEvent; 2–12 BindableFunctions.
- ReplicatedStorage: **4,089 instances / 499 ModuleScripts / 33 Gui templates / 23 asset models** — identical in both places.
- Tags: **0 found**. Attributes: 163 (game) / 171 (lobby) attribute-carrying instances incl. the 92-id protocol map.
- Workspace: game 13 top-level (incl. 13,011-instance PotatoPile) vs lobby 7; game has machines/sell/store/vault/pile,
  lobby has queues/shops/leaderboards/zones.
- Client bootstrap: `Players.lwtwtnp.PlayerScripts.main`; PlayerGui 35 (game) vs 28 (lobby) ScreenGuis; Backpacks empty.

