# Peel THE Potato — CLIENT CODE CENSUS (glm2)

**Source (single source of truth):** `/home/z/Public/potato/game/Peel THE Potato[Deob].lua` — 76,287 lines of deobfuscated client+shared source (lobby copy byte-identical).
**Provenance rule:** every finding cites deobf line numbers (`Lnnnnn`). All line refs are 1-based into that file.
**Purpose:** map the client code so a mock-world harness can be built around it (network mock, world mock, signal mock, input mock).

The dump is a concatenation of **401 scripts**, each introduced by a `--- <instance path> [LocalScript|ModuleScript|Script]` header (e.g. `--- ReplicatedStorage.Controllers.PeelingController [ModuleScript]` at L22141). Top-level layout:

| Line range | Content |
|---|---|
| L1–L10813 | `Players.LocalPlayer.PlayerScripts.main` + full Roblox **PlayerModule** (camera/control stack) |
| L10814–L16011 | `ReplicatedStorage.CmdrClient` (vendored Cmdr admin lib, 53 scripts) |
| L16012–L16922 | `ReplicatedStorage.Assets.ClassesBackground.Character.Animate` (character animate LocalScript) |
| L16923–L41028 | **`ReplicatedStorage.Controllers.*`** (the game client logic, ~70 controllers) |
| L41189–L44773 | **`ReplicatedStorage.Modules.*`** (incl. `Modules.Buffer` L41324, `Modules.Initializer` L41714, `Modules.Resources.Packets` L44290) |
| L44774–L48928 | **`ReplicatedStorage.Shared.*`** (shared client+server logic, incl. `PotatoPileShared` L46508, `PotatoTableShared` L46954, `PlayerStateShared` L45551) |
| L48929–L52601 | **`ReplicatedStorage.ModifiedPackages.Packet`** — THE network module (+ `_Signal`/`_Task`/`_Types`/… submodules) |
| L52602–L60615 | ModifiedPackages: Promise / Ripple / ExpressivePrompts / Seam (UI+animation libs) |
| L60616–L75372 | ReplicatedStorage.Packages._Index vendored libs (topbarplus, packetprofiler, roact-constant-fork, goodsignal, janitor) |
| L75373–L76287 | `Workspace.Players.<player>.Health/Animate` (per-character scripts) |

Client bootstrap (`Players.LocalPlayer.PlayerScripts.main`, L1–L12):
```lua
L4   local var1 = game:GetService("ReplicatedStorage")
L5   require(var1.Modules.Resources.Folders)
L6   require(var1.Modules.Resources.Assets)
L7   require(var1.Modules.Resources.Packets)
L8   local var2 = require(var1.Modules.Initializer)
L10  var2.InitializeScripts(var1:WaitForChild("Shared"))      -- "Shared" via str1
L12  var2.InitializeScripts(var1:WaitForChild("Controllers")) -- "Controllers" via str1
```
`Initializer` (L41714–L41783) requires **every ModuleScript descendant** of `ReplicatedStorage.Shared` and `ReplicatedStorage.Controllers`, then calls `module.Init()` (L41780) and `module.Start()` (L41782) on each — this is the dynamic require surface a mock DataModel must satisfy.

---

# 1. REQUIRE MAP — 1,425 `require(...)` call sites total

Counted with `rg 'require\('` → 1,425 sites across the 401 scripts. Breakdown by bucket (script path prefix of the *containing* script):

| Bucket | require sites | scripts | harness relevance |
|---|---|---|---|
| A. `Players.LocalPlayer.PlayerScripts.*` (main + PlayerModule) | 118 | 38 | Roblox default stack; harness can stub whole PlayerModule |
| B. `ReplicatedStorage` game code (Controllers/Shared/Modules) | 695 | 158 | **must mock all of these module paths** |
| B1. `ReplicatedStorage.ModifiedPackages.*` | 185 | 44 | Packet/Signal/Promise/Ripple/ExpressivePrompts/Seam — must mock |
| C. `ReplicatedStorage.CmdrClient` | 74 | 53 | admin console; stub if enabled |
| D. `ReplicatedStorage.Packages.*` | 94 | 32 | vendored UI libs (topbarplus, Roact fork, packetprofiler) |
| E. `ReplicatedStorage.Assets` | 0 | — | no code, assets only |
| F. `Workspace.Players.*` | 0 | 2 | — |

Require *styles* the mock must support:
- Absolute via service: `require(var1.Modules.Resources.Packets)` where `var1 = game:GetService("ReplicatedStorage")` (e.g. L24131), or `require(game:GetService("ReplicatedStorage").ModifiedPackages.Signal)` (e.g. L41468).
- Script-relative: `require(script._Types)` (L48932), `require(script.Parent._Task)` (L49458), `require(script.Parent.CharacterController)` (L17076), `require(script:WaitForChild(str1))` (L22, L19946), `require(script:WaitForChild("CommonUtils"):WaitForChild(str1))` (L50).
- Wally-style paths kept by the deobf: `require("@self/Shared/Dispatcher")` (L10818), `require("@self/types")` (L54079), `require("./spring")` (L54099), `require("../types")` (L55343).
- Dynamic (no static site): `Initializer.InitializeScripts` requires all descendants (L41762–L41776); `CmdrController` requires `ReplicatedStorage:WaitForChild("CmdrClient")` (L19946); `PlayerScriptsLoader` requires `script.Parent:WaitForChild(str1)` (L10812, str1="PlayerModule").

Full map (every site, grouped by containing script; `Lnnn: <verbatim require expression>`) follows.

### A. PlayerScripts.main + PlayerModule (Roblox default character/camera stack)

118 require sites in 38 scripts

**Players.LocalPlayer.PlayerScripts.main** (4):
- L5: require(var1.Modules.Resources.Folders)
- L6: require(var1.Modules.Resources.Assets)
- L7: require(var1.Modules.Resources.Packets)
- L8: local var2 = require(var1.Modules.Initializer)

**Players.LocalPlayer.PlayerScripts.PlayerModule** (2):
- L22: var1.cameras = require(script:WaitForChild(str1))
- L24: var1.controls = require(script:WaitForChild(str1))

**Players.LocalPlayer.PlayerScripts.PlayerModule.CameraModule** (14):
- L50: local var2 = require(var1:WaitForChild(str1))
- L52: local var3 = require(var1:WaitForChild(str2))
- L54: local var4 = require(script:WaitForChild(str3))
- L56: str1 = require(script:WaitForChild(str4))
- L58: str2 = require(script:WaitForChild(str5))
- L60: str3 = require(script:WaitForChild(str6))
- L62: str4 = require(script:WaitForChild(str7))
- L64: str5 = require(script:WaitForChild(str8))
- L66: str6 = require(script:WaitForChild(str9))
- L68: str7 = require(script:WaitForChild(str10))
- L70: str8 = require(script:WaitForChild(str11))
- L72: str9 = require(script:WaitForChild(str12))
- L74: str10 = require(script:WaitForChild(str13))
- L76: str11 = require(script:WaitForChild(str14))

**Players.LocalPlayer.PlayerScripts.PlayerModule.CameraModule.ClassicCamera** (4):
- L602: local var1 = require(script.Parent.Parent:WaitForChild("CommonUtils"):WaitForChild(str1)).getUserFlag("UserFixCameraFPError")
- L605: str1 = require(script.Parent:WaitForChild(str2))
- L607: local var2 = require(script.Parent:WaitForChild(str3))
- L608: local var3 = require(script.Parent:WaitForChild(str4))

**Players.LocalPlayer.PlayerScripts.PlayerModule.CameraModule.VRBaseCamera** (4):
- L1118: local var1 = require(script.Parent:WaitForChild(str2))
- L1119: local var2 = require(script.Parent:WaitForChild(str1))
- L1121: str2 = require(script.Parent.Parent:WaitForChild("CommonUtils"):WaitForChild(str3)).getUserFlag("UserVRRemoveLuaEdgeBlur")
- L1123: local var3 = require(script.Parent:WaitForChild(str4))

**Players.LocalPlayer.PlayerScripts.PlayerModule.CameraModule.VRVehicleCamera** (4):
- L1480: local var1 = require(script.Parent:WaitForChild(str1))
- L1482: local var2 = require(script.Parent:WaitForChild(str3))
- L1483: local var3 = require(script.Parent:WaitForChild(str2))
- L1489: local var6 = require(script.Parent:WaitForChild("VehicleCamera"):FindFirstChild(str4))

**Players.LocalPlayer.PlayerScripts.PlayerModule.CameraModule.VRCamera** (6):
- L1746: require(script.Parent:WaitForChild(str1))
- L1748: require(script.Parent:WaitForChild(str2))
- L1750: local var1 = require(script.Parent:WaitForChild(str3))
- L1752: str2 = require(script.Parent.Parent:WaitForChild("CommonUtils"):WaitForChild(str4))
- L1754: str4 = require(script.Parent:WaitForChild(str5))
- L1767: var1.controlModule = require(var2.LocalPlayer:WaitForChild("PlayerScripts").PlayerModule:WaitForChild(str1))

**Players.LocalPlayer.PlayerScripts.PlayerModule.CameraModule.VehicleCamera** (6):
- L2112: local var1 = require(script.Parent:WaitForChild(str1))
- L2114: local var2 = require(script.Parent:WaitForChild(str2))
- L2116: require(script.Parent:WaitForChild(str4))
- L2117: local var3 = require(script.Parent:WaitForChild(str3))
- L2120: str2 = require(script:WaitForChild(str5))
- L2121: str3 = require(script:WaitForChild(str6))

**Players.LocalPlayer.PlayerScripts.PlayerModule.CameraModule.VehicleCamera.VehicleCameraCore** (2):
- L2275: local var1 = require(script.Parent.Parent.CameraUtils)
- L2277: local var3 = require(script.Parent.VehicleCameraConfig)

**Players.LocalPlayer.PlayerScripts.PlayerModule.CameraModule.CameraToggleStateController** (3):
- L2383: local var1 = require(script.Parent:WaitForChild(str1))
- L2385: local var2 = require(script.Parent:WaitForChild(str2))
- L2386: local var3 = require(script.Parent:WaitForChild(str3))

**Players.LocalPlayer.PlayerScripts.PlayerModule.CameraModule.Invisicam** (2):
- L2484: local var1 = require(script.Parent.Parent:WaitForChild("CommonUtils"):WaitForChild(str1)).getUserFlag("UserRaycastUpdateAPI2")
- L2491: local var5 = require(script.Parent:WaitForChild(str2))

**Players.LocalPlayer.PlayerScripts.PlayerModule.CameraModule.VRCameraTeleportDetector.spec** (2):
- L3024: local var1 = require(game:GetService("CorePackages").Packages.Dev.JestGlobals)
- L3025: local var2 = require(script.Parent.VRCameraTeleportDetector)

**Players.LocalPlayer.PlayerScripts.PlayerModule.CameraModule.CameraInput** (1):
- L3111: local var1 = require(script.Parent.Parent:WaitForChild("CommonUtils"):WaitForChild(str1))

**Players.LocalPlayer.PlayerScripts.PlayerModule.CameraModule.Poppercam** (3):
- L3636: local var1 = require(script.Parent.Parent:WaitForChild("CommonUtils"):WaitForChild(str1)).getUserFlag
- L3637: local var2 = require(script.Parent:WaitForChild(str2))
- L3706: str2 = require(script.Parent:WaitForChild(extractRotation))

**Players.LocalPlayer.PlayerScripts.PlayerModule.CameraModule.ZoomController** (1):
- L3744: local var1 = require(script:WaitForChild(str1))

**Players.LocalPlayer.PlayerScripts.PlayerModule.CameraModule.ZoomController.Popper** (3):
- L3837: local var2 = require(var1:WaitForChild(str1))
- L3838: local var3 = require(var1:WaitForChild(str2))
- L3839: local var4 = require(var1:WaitForChild(str3))

**Players.LocalPlayer.PlayerScripts.PlayerModule.CameraModule.TransparencyController** (1):
- L4269: local var2 = require(script.Parent:WaitForChild(str1))

**Players.LocalPlayer.PlayerScripts.PlayerModule.CameraModule.LegacyCamera** (3):
- L4492: require(script.Parent:WaitForChild(str1))
- L4494: local var1 = require(script.Parent:WaitForChild(str2))
- L4496: str1 = require(script.Parent:WaitForChild(str3))

**Players.LocalPlayer.PlayerScripts.PlayerModule.CameraModule.OrbitalCamera** (4):
- L4590: local var1 = require(script.Parent.Parent:WaitForChild("CommonUtils"):WaitForChild(str1)).getUserFlag("UserFixOrbitalCameraAzimuth")
- L4593: local var2 = require(script.Parent:WaitForChild(str3))
- L4594: str1 = require(script.Parent:WaitForChild(str2))
- L4596: str2 = require(script.Parent:WaitForChild(str4))

**Players.LocalPlayer.PlayerScripts.PlayerModule.CameraModule.MouseLockController** (2):
- L4826: local var1 = require(script.Parent.Parent:WaitForChild("CommonUtils"):WaitForChild(str1))
- L4832: local var5 = require(script.Parent:WaitForChild(str2))

**Players.LocalPlayer.PlayerScripts.PlayerModule.CameraModule.BaseCamera** (7):
- L5007: require(var1:WaitForChild(str2))
- L5008: local var2 = require(var1:WaitForChild(str1))
- L5011: local var3 = require(script.Parent:WaitForChild(str3))
- L5013: str1 = require(script.Parent:WaitForChild(str4))
- L5015: str2 = require(script.Parent:WaitForChild(str5))
- L5017: str3 = require(script.Parent:WaitForChild(str6))
- L5018: str4 = require(script.Parent:WaitForChild(str7))

**Players.LocalPlayer.PlayerScripts.PlayerModule.ControlModule** (7):
- L5637: local var1 = require(script:WaitForChild(str1))
- L5639: local var2 = require(script:WaitForChild(str2))
- L5640: local var3 = require(script:WaitForChild(str3))
- L5650: success = require(script:WaitForChild(str4))
- L5652: result = require(script:WaitForChild(str5))
- L5654: local var4 = require(script:WaitForChild(str6))
- L5655: str4 = require(script:WaitForChild(str7))

**Players.LocalPlayer.PlayerScripts.PlayerModule.ControlModule.VRNavigation** (3):
- L6255: local var1 = require(script.Parent.Parent:WaitForChild("CommonUtils"):WaitForChild(str1))
- L6273: var11 = require(var2)
- L6278: local var12 = require(script.Parent:WaitForChild(str2))

**Players.LocalPlayer.PlayerScripts.PlayerModule.ControlModule.Keyboard** (1):
- L6767: local var1 = require(script.Parent:WaitForChild(str1))

**Players.LocalPlayer.PlayerScripts.PlayerModule.ControlModule.ClickToMoveController** (3):
- L6922: local var1 = require(script.Parent.Parent:WaitForChild("CommonUtils"):WaitForChild(str1)).getUserFlag("UserRaycastUpdateAPI2")
- L6931: local var9 = require(script.Parent:WaitForChild(str2))
- L7869: local var21 = require(script.Parent:WaitForChild(str3))

**Players.LocalPlayer.PlayerScripts.PlayerModule.ControlModule.PathDisplay** (1):
- L8396: local var1 = require(script.Parent.Parent:WaitForChild("CommonUtils"):WaitForChild(str1)).getUserFlag("UserRaycastUpdateAPI2")

**Players.LocalPlayer.PlayerScripts.PlayerModule.ControlModule.TouchThumbstick** (3):
- L8533: local var1 = require(script.Parent.Parent:WaitForChild("CommonUtils"):WaitForChild(str1)).getUserFlag("UserAllowAbilityControls")
- L8536: var2 = var1 and require(script.Parent:WaitForChild(str2))
- L8538: str1 = require(script.Parent:WaitForChild(str2))

**Players.LocalPlayer.PlayerScripts.PlayerModule.ControlModule.ClickToMoveDisplay** (1):
- L8903: local var9 = require(script.Parent.Parent:WaitForChild("CommonUtils"):WaitForChild(str1)).getUserFlag("UserRaycastUpdateAPI2")

**Players.LocalPlayer.PlayerScripts.PlayerModule.ControlModule.TouchJump** (5):
- L9335: local var2 = require(var1:WaitForChild(str1))
- L9336: local var3 = require(var1:WaitForChild(str2))
- L9337: str1 = require(var1:WaitForChild(str3)).getUserFlag("UserAllowAbilityControls")
- L9340: str2 = str1 and require(script.Parent:WaitForChild(str4))
- L9342: local var4 = require(script.Parent:WaitForChild(str5))

**Players.LocalPlayer.PlayerScripts.PlayerModule.ControlModule.BaseCharacterController** (1):
- L9554: local var1 = require(script.Parent.Parent:WaitForChild("CommonUtils"):WaitForChild(str1))

**Players.LocalPlayer.PlayerScripts.PlayerModule.ControlModule.Gamepad** (2):
- L9591: local var1 = require(script.Parent.Parent:WaitForChild("CommonUtils"):WaitForChild(str1)).getUserFlag("UserPlayerScriptsSupportTVRemoteKeycodes")
- L9593: str1 = require(script.Parent:WaitForChild(str2))

**Players.LocalPlayer.PlayerScripts.PlayerModule.ControlModule.DynamicThumbstick** (3):
- L9834: local var1 = require(script.Parent.Parent:WaitForChild("CommonUtils"):WaitForChild(str1))
- L9856: success = var2 and require(script.Parent:WaitForChild(str2))
- L9863: local var13 = require(script.Parent:WaitForChild(str3))

**Players.LocalPlayer.PlayerScripts.PlayerModule.ControlModule.AvatarAbilitiesInterface** (1):
- L10392: if require(script.Parent.Parent:WaitForChild("CommonUtils"):WaitForChild(str1)).getUserFlag("UserAllowAbilityControls") then

**Players.LocalPlayer.PlayerScripts.PlayerModule.CommonUtils.CharacterUtil** (1):
- L10467: local tbl1 = { _connectionUtil = require(script.Parent:WaitForChild(str1)).new() }

**Players.LocalPlayer.PlayerScripts.PlayerModule.CommonUtils.CameraWrapper.spec** (3):
- L10626: local var2 = require(var1.Packages.Dev.JestGlobals)
- L10628: local var4 = require(script.Parent.CameraWrapper)
- L10630: local var6 = require(var1.Workspace.Packages.TestUtils).DeferredLuaHelpers.waitForEvents

**Players.LocalPlayer.PlayerScripts.PlayerModule.CommonUtils.CameraWrapper** (1):
- L10653: local var1 = require(script.Parent.ConnectionUtil)

**Players.LocalPlayer.PlayerScripts.PlayerModule.CommonUtils.ConnectionUtil.spec** (3):
- L10730: local var2 = require(var1.Packages.Dev.JestGlobals)
- L10732: local var4 = require(script.Parent.ConnectionUtil)
- L10734: local var6 = require(var1.Workspace.Packages.AppCommonLib).Signal

**Players.LocalPlayer.PlayerScripts.PlayerScriptsLoader** (1):
- L10812: require(script.Parent:WaitForChild(str1))

### B. ReplicatedStorage game code (Controllers / Shared / Modules)

695 require sites in 158 scripts

**ReplicatedStorage.Controllers.AnimationController** (2):
- L16927: require(var1.Modules.Resources.Animations)
- L16929: local var2 = require(var1.Modules.Logger)

**ReplicatedStorage.Controllers.ArmStretchController** (3):
- L17076: local var4 = require(script.Parent.CharacterController)
- L17077: local var5 = require(var1.Modules.Resources.Folders)
- L17078: local var6 = require(var1.Modules.Helper.IS_RESERVED_SERVER)

**ReplicatedStorage.Controllers.ArrowController** (6):
- L17404: require(var1.Shared.ArrowShared)
- L17405: local var2 = require(var1.Modules.Logger)
- L17431: local var4 = require(var1.Modules.Helper.CreateSpring)
- L17434: local var7 = require(var1.Modules.Resources.Assets)
- L17435: local var8 = require(var1.Modules.Lib.MathLib)
- L17436: local var9 = require(var1.Modules.Resources.Packets)

**ReplicatedStorage.Controllers.AudioController** (6):
- L17567: require(var1.Shared.AudioShared)
- L17571: local var3 = require(var1.Modules.Resources.Folders).CreateFolder("SoundCache", var2)
- L17593: local var4 = require(var1.Modules.Resources.Enums)
- L17594: local var5 = require(var1.Modules.Logger)
- L17595: local var6 = require(var1.Modules.Resources.Packets)
- L17596: local var7 = require(var1.Modules.Resources.Sounds)

**ReplicatedStorage.Controllers.AutoPeelerController** (7):
- L17799: local var2 = require(var1.Modules.Resources.Sounds)
- L17800: local var3 = require(var1.Shared.PlayerStateShared)
- L17806: local var9 = require(var1.Shared.PotatoTableShared)
- L17807: local var10 = require(var1.Shared.StoreShared)
- L17909: local var24 = require(var1.Modules.Helper.IS_RESERVED_SERVER)
- L17910: local var25 = require(script.Parent.GuiController)
- L18220: local var27 = require(script.Parent.PotatoTableController)

**ReplicatedStorage.Controllers.BagController** (13):
- L18336: local var3 = require(var1.Shared.CarryUpgradeShared)
- L18337: local var4 = require(var1.Modules.Helper.FlashLabels)
- L18338: local var5 = require(var1.Modules.Helper.FormatCash)
- L18339: local var6 = require(script.Parent.GuiController)
- L18340: local var7 = require(var1.Modules.Helper.IS_RESERVED_SERVER)
- L18341: local var8 = require(var1.Modules.Resources.Packets)
- L18342: local var9 = require(var1.Shared.PlayerStateShared)
- L18343: local var10 = require(var1.Shared.PotatoTableShared)
- L18344: local var11 = require(var1.Shared.SellValueShared)
- L18345: local var12 = require(var1.Modules.Helper.SetCounterValue)
- L18346: local var13 = require(var1.Modules.Helper.ShakeGui)
- L18347: local var14 = require(var1.Modules.Lib.TweenLib)
- L18370: local tbl2 = { KindsChanged = require(var1.ModifiedPackages.Signal).new() }

**ReplicatedStorage.Controllers.BlurController** (1):
- L18547: local var1 = require(game:GetService("ReplicatedStorage").Modules.Lib.TweenLib)

**ReplicatedStorage.Controllers.CameraController** (4):
- L18623: require(var1.Modules.Helper.CreateSpring)(CFrame.identity, { frequency = 1, dampingRatio = 0.9 })
- L18628: local var6 = require(var1.Modules.Helper.IS_RESERVED_SERVER)
- L18629: local var7 = require(var1.Modules.Resources.Packets)
- L18631: local var9 = require(script.Parent.InputControllerV2).Actions.UnlockMouse

**ReplicatedStorage.Controllers.CarryUpgradeController** (4):
- L18806: local var2 = require(var1.Shared.PlayerStateShared)
- L18808: local var4 = require(var1.Shared.CarryUpgradeShared)
- L18810: local var5 = require(var1.Shared.StoreShared)
- L18827: local var6 = require(var1.Modules.Helper.IS_RESERVED_SERVER)

**ReplicatedStorage.Controllers.CashController** (5):
- L18884: local var6 = require(var1.Modules.Helper.FlashLabels)
- L18885: local var7 = require(var1.Shared.PlayerStateShared)
- L18890: local var8 = require(var1.Modules.Helper.FormatCash)
- L18892: local var10 = require(script.Parent.GuiController)
- L18893: local var11 = require(var1.Modules.Helper.IS_RESERVED_SERVER)

**ReplicatedStorage.Controllers.CharacterController** (3):
- L19017: require(var1.Modules.Resources.Types)
- L19018: local var2 = require(var1.ModifiedPackages.Signal)
- L19020: local var4 = require(var1.Modules.Resources.Events)

**ReplicatedStorage.Controllers.CinematicBarsController** (1):
- L19065: local var5 = require(var1.Modules.Resources.Packets)

**ReplicatedStorage.Controllers.ClassController** (15):
- L19112: local var2 = require(var1.Modules.Resources.Gamepasses)
- L19118: local var8 = require(var1.Modules.Resources.Assets)
- L19119: local var9 = require(var1.Shared.ClassShared)
- L19120: local var10 = require(var1.Modules.Helper.DetachScreenGuis)
- L19121: local var11 = require(var1.Shared.GamepassShared)
- L19122: local var12 = require(script.Parent.GuiController)
- L19123: local var13 = require(var1.Modules.Helper.IS_RESERVED_SERVER)
- L19124: local var14 = require(var1.Modules.Helper.LobbyMenus)
- L19125: local var15 = require(var1.Modules.Logger)
- L19126: local var16 = require(var1.Modules.Resources.Packets)
- L19127: local var17 = require(var1.Shared.PlayerStateShared)
- L19128: local var18 = require(script.Parent.ProductController)
- L19129: local var19 = require(var1.Shared.ProductShared)
- L19130: local var20 = require(var1.Modules.Resources.Products)
- L19131: local var21 = require(var1.Modules.Helper.SetCounterValue)

**ReplicatedStorage.Controllers.CmdrController** (2):
- L19946: local var2 = require(var1:WaitForChild(str1))
- L19947: local var3 = require(var1.Modules.Permissions)

**ReplicatedStorage.Controllers.CrosshairController** (3):
- L19963: local var2 = require(script.Parent.DeviceController)
- L19965: local var4 = require(game:GetService("ReplicatedStorage").Modules.Helper.IS_RESERVED_SERVER)
- L19966: local var5 = require(script.Parent.GuiController)

**ReplicatedStorage.Controllers.CutsceneCameraController** (5):
- L19989: require(var1.Shared.CutsceneCameraShared)
- L19992: local var3 = require(var1.Modules.Helper.CreateSpring)(CFrame.identity, { frequency = 1, dampingRatio = 0.9 })
- L19994: local var5 = require(var1.Modules.Lib.MathLib)
- L19996: local var7 = require(var1.Modules.Resources.Globals)
- L19997: local var8 = require(var1.Modules.Resources.Packets)

**ReplicatedStorage.Controllers.DailyRewardController** (7):
- L20109: local var3 = require(var1.Shared.DailyRewardShared)
- L20110: local var4 = require(var1.Shared.PlayerStateShared)
- L20112: local var5 = require(var1.Modules.Helper.LobbyMenus)
- L20132: local var7 = require(script.Parent.BlurController)
- L20133: local var8 = require(script.Parent.GuiController)
- L20134: local var9 = require(var1.Modules.Helper.IS_RESERVED_SERVER)
- L20135: local var10 = require(var1.Modules.Resources.Packets)

**ReplicatedStorage.Controllers.DeviceController** (2):
- L20204: local var3 = require(var1.Modules.Resources.Enums)
- L20206: local tbl1 = { DeviceChanged = require(var1.ModifiedPackages.Signal).new() }

**ReplicatedStorage.Controllers.DiamondController** (5):
- L20260: local var3 = require(var1.Shared.PlayerStateShared)
- L20261: local var4 = require(var1.Modules.Helper.SetCounterValue)
- L20266: local var9 = require(script.Parent.ShopController)
- L20267: local var10 = require(script.Parent.GuiController)
- L20268: local var11 = require(var1.Modules.Helper.IS_RESERVED_SERVER)

**ReplicatedStorage.Controllers.DisableCoreGui** (1):
- L20300: local var2 = require(game:GetService("ReplicatedStorage").Modules.Helper.IS_RESERVED_SERVER)

**ReplicatedStorage.Controllers.FriendBoostController** (5):
- L20313: local var3 = require(var1.Shared.PlayerStateShared)
- L20315: local var5 = require(var1.Shared.FriendBoostShared)
- L20316: local var6 = require(var1.Modules.Helper.SetCounterValue)
- L20320: local var10 = require(var1.Modules.Helper.IS_RESERVED_SERVER)
- L20321: local var11 = require(script.Parent.GuiController)

**ReplicatedStorage.Controllers.GameTimerController** (5):
- L20373: local var4 = require(var1.Shared.PlayerStateShared)
- L20374: local var5 = require(var1.Shared.GameTimerShared)
- L20375: local var6 = require(var1.Modules.Resources.Packets)
- L20385: local var8 = require(script.Parent.GuiController)
- L20386: local var9 = require(var1.Modules.Helper.IS_RESERVED_SERVER)

**ReplicatedStorage.Controllers.GlobalController** (3):
- L20430: local var2 = require(var1.Modules.Resources.Globals)
- L20431: local var3 = require(var1.Modules.Resources.Packets)
- L20432: local var4 = require(var1.Modules.Lib.TableLib).DeepCopy(var2)

**ReplicatedStorage.Controllers.GuiController** (1):
- L20453: local var2 = require(var1.Modules.Helper.WaitUntilExists)

**ReplicatedStorage.Controllers.HighlightController** (2):
- L20473: local var2 = require(var1.Modules.IdMap).New(tbl1, require(var1.Modules.Resources.Globals).U8)
- L20474: local var3 = require(var1.Modules.Logger)

**ReplicatedStorage.Controllers.HotbarController** (16):
- L20546: local var4 = require(var1.Modules.Helper.CreateGamepadHint)
- L20547: local var5 = require(script.Parent.DeviceController)
- L20548: local var6 = require(script.Parent.GuiController)
- L20549: local var7 = require(var1.Modules.Helper.IS_RESERVED_SERVER)
- L20550: local var8 = require(script.Parent.InputControllerV2)
- L20551: local var9 = require(var1.Shared.KeyShared)
- L20552: local var10 = require(var1.Modules.Resources.Packets)
- L20553: local var11 = require(script.Parent.PeelingController)
- L20554: local var12 = require(var1.Shared.PlayerStateShared)
- L20555: local var13 = require(script.Parent.PotatoPileController)
- L20556: local var14 = require(script.Parent.ProductController)
- L20557: local var15 = require(var1.Modules.Resources.Products)
- L20558: local var16 = require(script.Parent.ToolEquipController)
- L20559: local var17 = require(var1.Shared.ToolUpgradeShared)
- L20560: local var18 = require(var1.Modules.Lib.TweenLib)
- L20561: local var19 = require(var1.Shared.UnlockShared)

**ReplicatedStorage.Controllers.HudController** (3):
- L21024: require(script.Parent.GuiController)
- L21026: require(var1.ModifiedPackages.Signal)
- L21027: require(var1.Modules.Helper.WaitUntilExists)

**ReplicatedStorage.Controllers.InputControllerV2** (1):
- L21033: local var1 = require(game:GetService("ReplicatedStorage").Modules.Resources.Folders)

**ReplicatedStorage.Controllers.InspectController** (5):
- L21203: local var1 = require(game:GetService("ReplicatedStorage").ModifiedPackages.Signal)
- L21207: local var5 = require(script.Parent.CameraController)
- L21208: local var6 = require(script.Parent.DeviceController)
- L21209: local var7 = require(script.Parent.InputControllerV2)
- L21218: local var2 = require((var8.PlayerScripts:WaitForChild("PlayerModule"))):GetControls():GetMoveVector()

**ReplicatedStorage.Controllers.KeyController** (5):
- L21342: local var2 = require(var1.Modules.Helper.IS_RESERVED_SERVER)
- L21343: local var3 = require(var1.Modules.Resources.Packets)
- L21344: local var4 = require(script.Parent.KeyRevealController)
- L21345: local var5 = require(script.Parent.EscapeCinematicController)
- L21347: local var7 = require(script.Parent.GuiController)

**ReplicatedStorage.Controllers.KnifeController** (1):
- L21434: local var8 = require(game:GetService("ReplicatedStorage").Shared.PeelToolShared)

**ReplicatedStorage.Controllers.LeaderboardController** (4):
- L21560: local var2 = require(var1.Shared.LeaderboardShared)
- L21585: local var3 = require(script.Parent.GuiController)
- L21586: local var4 = require(var1.Modules.Helper.IS_RESERVED_SERVER)
- L21587: local var5 = require(var1.Modules.Resources.Packets)

**ReplicatedStorage.Controllers.LobbyUpgradeController** (12):
- L21673: require(var1.Modules.Resources.Products)
- L21675: local var3 = require(script.Parent.BlurController)
- L21676: local var4 = require(script.Parent.GuiController)
- L21677: local var5 = require(var1.Modules.Helper.IS_RESERVED_SERVER)
- L21678: local var6 = require(var1.Modules.Helper.LobbyMenus)
- L21679: local var7 = require(var1.Shared.LobbyUpgradeShared)
- L21680: local var8 = require(script.Parent.NotificationController)
- L21681: local var9 = require(var1.Modules.Resources.Packets)
- L21682: local var10 = require(var1.Shared.PlayerStateShared)
- L21683: local var11 = require(script.Parent.ProductController)
- L21684: local var12 = require(var1.Shared.ProductShared)
- L21685: local var13 = require(script.Parent.ShopController)

**ReplicatedStorage.Controllers.MouseController** (1):
- L21943: local var2 = require(game:GetService("ReplicatedStorage").Modules.Resources.Folders)

**ReplicatedStorage.Controllers.NotificationController** (9):
- L21973: require(var1.Shared.NotificationShared)
- L21975: local var2 = require(var1.Modules.Resources.Globals)
- L21976: local var3 = require(var1.Modules.Resources.Enums)
- L21978: local var5 = require(var1.Modules.Logger)
- L21980: local var7 = require(var1.Modules.Lib.TweenLib)
- L21982: local var9 = require(var1.Modules.IdMap).New(tbl1, var2.U16)
- L21983: local var10 = require(script.Parent.DialogueController)
- L21986: local var12 = require(script.Parent.GuiController)
- L21987: local var13 = require(var1.Modules.Resources.Packets)

**ReplicatedStorage.Controllers.PacketProfilerController** (1):
- L22099: require(var1.Packages.PacketProfiler)

**ReplicatedStorage.Controllers.PeelTableController** (3):
- L22106: local var2 = require(script.Parent.PeelingController)
- L22107: local var3 = require(var1.Modules.Resources.Packets)
- L22108: local var4 = require(var1.Modules.Helper.IS_RESERVED_SERVER)

**ReplicatedStorage.Controllers.PeelingController** (16):
- L22145: local var2 = require(var1.ModifiedPackages.Signal)
- L22149: local var6 = require(script.Parent.AudioController)
- L22150: local var7 = require(var1.Modules.Helper.CreateGamepadHint)
- L22151: local var8 = require(script.Parent.DeviceController)
- L22152: local var9 = require(script.Parent.GuiController)
- L22153: local var10 = require(script.Parent.InputControllerV2)
- L22154: local var11 = require(script.Parent.InspectController)
- L22155: local var12 = require(script.Parent.KnifeController)
- L22156: local var13 = require(var1.Modules.Resources.Packets)
- L22157: local var14 = require(var1.Shared.PeelToolShared)
- L22158: local var15 = require(var1.Shared.PlayerStateShared)
- L22159: local var16 = require(var1.Shared.PotatoKindShared)
- L22160: local var17 = require(var1.Shared.PotatoTableShared)
- L22161: local var18 = require(script.Parent.ProductController)
- L22162: local var19 = require(var1.Modules.Resources.Products)
- L22163: local var20 = require(var1.Modules.Resources.Sounds)

**ReplicatedStorage.Controllers.PeelingSpectateController** (7):
- L23253: local var2 = require(var1.Modules.Resources.Sounds)
- L23254: local var3 = require(var1.Shared.PotatoKindShared)
- L23257: local var6 = require(script.Parent.KnifeController)
- L23276: local var8 = require(var1.Shared.PeelToolShared)
- L23358: local var10 = require(script.Parent.AudioController)
- L23387: local var11 = require(var1.Modules.Helper.IS_RESERVED_SERVER)
- L23388: local var12 = require(var1.Modules.Resources.Packets)

**ReplicatedStorage.Controllers.PlayerController** (1):
- L23565: local var1 = require(game:GetService("ReplicatedStorage").Modules.Resources.Events)

**ReplicatedStorage.Controllers.PopupPromptController** (2):
- L23591: local var4 = require(script.Parent.BlurController)
- L23592: local var5 = require(var1.Modules.Logger)

**ReplicatedStorage.Controllers.PotatoCounterController** (2):
- L23656: local var2 = require(var1.Shared.PotatoTableShared)
- L23657: local var3 = require(var1.Modules.Helper.IS_RESERVED_SERVER)

**ReplicatedStorage.Controllers.PotatoFlyController** (7):
- L23694: local var2 = require(var1.Shared.PotatoKindShared)
- L23695: local var3 = require(var1.Modules.Helper.AttachPotatoKey)
- L23698: local var6 = require(script.Parent.ToolHoldController)
- L23699: local var7 = require(script.Parent.PotatoHoldController)
- L23702: local var9 = require(script.Parent.HandHoldController)
- L23711: local var11 = require(var1.Modules.Resources.Folders)
- L23712: local var12 = require(var1.Modules.Helper.IS_RESERVED_SERVER)

**ReplicatedStorage.Controllers.PotatoHoldController** (11):
- L23851: local var4 = require(var1.Modules.Helper.AttachPotatoKey)
- L23852: local var5 = require(script.Parent.BagController)
- L23853: local var6 = require(var1.Shared.CarryUpgradeShared)
- L23854: local var7 = require(var1.Modules.Resources.Folders)
- L23855: local var8 = require(script.Parent.FreecamController)
- L23856: local var9 = require(script.Parent.HandHoldController)
- L23857: local var10 = require(var1.Modules.Helper.IS_RESERVED_SERVER)
- L23858: local var11 = require(script.Parent.PeelingController)
- L23859: local var12 = require(var1.Shared.PlayerStateShared)
- L23860: local var13 = require(var1.Shared.PotatoHoldShared)
- L23861: local var14 = require(var1.Shared.PotatoKindShared)

**ReplicatedStorage.Controllers.PotatoPileController** (22):
- L24110: local var3 = require(var1.Modules.Resources.Sounds)
- L24111: local var4 = require(var1.Shared.PotatoKindShared)
- L24117: local var5 = require(var1.Shared.PotatoPileShared)
- L24121: local var9 = require(script.Parent.ArmStretchController)
- L24122: local var10 = require(var1.Modules.Helper.AttachPotatoKey)
- L24123: local var11 = require(script.Parent.AudioController)
- L24124: local var12 = require(script.Parent.BagController)
- L24125: local var13 = require(var1.Shared.CarryUpgradeShared)
- L24126: local var14 = require(var1.Modules.Helper.CutsceneState)
- L24127: local var15 = require(script.Parent.DeviceController)
- L24128: local var16 = require(var1.Modules.Resources.Folders)
- L24129: local var17 = require(var1.Modules.Helper.IS_RESERVED_SERVER)
- L24130: local var18 = require(script.Parent.NotificationController)
- L24131: local var19 = require(var1.Modules.Resources.Packets)
- L24132: local var20 = require(script.Parent.PeelingController)
- L24133: local var21 = require(var1.Shared.PlayerStateShared)
- L24134: local var22 = require(script.Parent.PotatoFlyController)
- L24135: local var23 = require(script.Parent.ToolEquipController)
- L24136: local var24 = require(script.Parent.ToolHoldController)
- L24137: local var25 = require(var1.Shared.ToolUpgradeShared)
- L24138: local var26 = require(script.Parent.WooshController)
- L24143: local var30 = require(script.Parent.InputControllerV2).Actions.PickPotato

**ReplicatedStorage.Controllers.PotatoTableController** (12):
- L24955: local var4 = require(var1.Modules.Helper.FlashLabels)
- L24956: local var5 = require(var1.Modules.Resources.Folders)
- L24957: local var6 = require(var1.Modules.Helper.IS_RESERVED_SERVER)
- L24958: local var7 = require(var1.Modules.Resources.Packets)
- L24959: local var8 = require(script.Parent.PeelingController)
- L24960: local var9 = require(script.Parent.PotatoFlyController)
- L24961: local var10 = require(var1.Shared.PotatoKindShared)
- L24962: local var11 = require(var1.Shared.PotatoTableShared)
- L24963: local var12 = require(var1.Shared.TutorialStackShared)
- L24964: local var13 = require(script.Parent.WaterwayController)
- L24965: local var14 = require(script.Parent.WooshController)
- L24966: local tbl1 = { MachineOutput = require(var1.ModifiedPackages.Signal).new() }

**ReplicatedStorage.Controllers.PreloadController** (3):
- L25777: local var4 = require(var1.Modules.Logger)
- L25778: local var5 = require(var1.Modules.Resources.Assets)
- L25779: local var6 = require(var1.Modules.Resources.Folders)

**ReplicatedStorage.Controllers.ProductController** (3):
- L25841: require(var1.Modules.Resources.Products)
- L25842: local var2 = require(var1.Modules.Resources.Packets)
- L25843: local var3 = require(script.Parent.PopupPromptController)

**ReplicatedStorage.Controllers.ProximityPromptController** (4):
- L25865: local var3 = require(script.Parent.DeviceController)
- L25866: local var4 = require(var1.ModifiedPackages.ExpressivePrompts)
- L25867: local var5 = require(script.Parent.GuiController)
- L25868: local var6 = require(var1.Modules.Logger)

**ReplicatedStorage.Controllers.QueueController** (10):
- L25970: local var4 = require(script.Parent.BlurController)
- L25971: local var5 = require(script.Parent.GuiController)
- L25972: local var6 = require(var1.Modules.Helper.LobbyMenus)
- L25973: local var7 = require(var1.Modules.Resources.Packets)
- L25974: local var8 = require(var1.Shared.PlayerStateShared)
- L25975: local var9 = require(var1.Shared.QueueShared)
- L25976: local var10 = require(var1.Modules.Helper.SetSlotSelected)
- L25979: local tbl1 = { SetupVisibleChanged = require(var1.ModifiedPackages.Signal).new() }
- L26081: require((var11.PlayerScripts:WaitForChild("PlayerModule"))):GetControls():Enable()
- L26091: require((var11.PlayerScripts:WaitForChild("PlayerModule"))):GetControls():Disable()

**ReplicatedStorage.Controllers.RagdollController** (3):
- L26201: require(var1.Modules.Resources.Types)
- L26204: local var3 = require(var1.Modules.Resources.Packets)
- L26205: local var4 = require(var1.Modules.RagdollModule)

**ReplicatedStorage.Controllers.ServerTypeController** (2):
- L26286: local var2 = require(var1.Modules.Helper.IS_RESERVED_SERVER)
- L26287: local var3 = require(var1.Modules.Logger)

**ReplicatedStorage.Controllers.ShopController** (11):
- L26301: local var2 = require(var1.Modules.Resources.Products)
- L26304: local var5 = require(script.Parent.BlurController)
- L26305: local var6 = require(var1.Shared.GamepassShared)
- L26306: local var7 = require(var1.Modules.Resources.Gamepasses)
- L26307: local var8 = require(script.Parent.GuiController)
- L26308: local var9 = require(var1.Modules.Helper.IS_RESERVED_SERVER)
- L26309: local var10 = require(var1.Modules.Helper.LobbyMenus)
- L26310: local var11 = require(var1.Modules.Logger)
- L26311: local var12 = require(var1.Shared.PlayerStateShared)
- L26312: local var13 = require(script.Parent.ProductController)
- L26313: local var14 = require(var1.Shared.ProductShared)

**ReplicatedStorage.Controllers.StatsController** (7):
- L26496: local var5 = require(var1.Shared.StatsShared)
- L26499: local var7 = require(var1.Shared.PlayerStateShared)
- L26508: local var9 = require(script.Parent.BlurController)
- L26509: local var10 = require(script.Parent.GuiController)
- L26510: local var11 = require(var1.Modules.Helper.IS_RESERVED_SERVER)
- L26511: local var12 = require(var1.Modules.Helper.LobbyMenus)
- L26512: local var13 = require(var1.Modules.Resources.Packets)

**ReplicatedStorage.Controllers.SyncController** (3):
- L26717: local var2 = require(var1.Modules.Logger)
- L26718: local var3 = require(var1.Modules.Resources.Packets)
- L26720: local tbl1 = { OnSynced = require(var1.ModifiedPackages.Signal).new() }

**ReplicatedStorage.Controllers.ToolEquipController** (5):
- L26757: local var2 = require(var1.ModifiedPackages.Signal)
- L26760: local var5 = require(var1.Shared.ClassShared)
- L26761: local var6 = require(var1.Modules.Resources.Packets)
- L26762: local var7 = require(var1.Shared.PlayerStateShared)
- L26763: local var8 = require(var1.Shared.ToolUpgradeShared)

**ReplicatedStorage.Controllers.ToolHoldController** (8):
- L26991: local var2 = require(var1.Shared.ToolUpgradeShared)
- L26993: local var4 = require(var1.Modules.Resources.Animations)
- L26994: local var5 = require(var1.Modules.Resources.Assets)
- L26995: local var6 = require(var1.Modules.Resources.Folders)
- L26996: local var7 = require(var1.Modules.Helper.IS_RESERVED_SERVER)
- L26997: local var8 = require(var1.Modules.Logger)
- L26998: local var9 = require(script.Parent.PeelingController)
- L26999: local var10 = require(script.Parent.ToolEquipController)

**ReplicatedStorage.Controllers.ToolPickupController** (4):
- L27487: local var2 = require(var1.Shared.StoreShared)
- L27488: local var3 = require(script.Parent.ToolEquipController)
- L27489: local var4 = require(var1.Shared.PlayerStateShared)
- L27492: local var6 = require(var1.Modules.Helper.IS_RESERVED_SERVER)

**ReplicatedStorage.Controllers.ToolUpgradeController** (16):
- L27586: local var2 = require(var1.ModifiedPackages.Signal)
- L27590: local var6 = require(script.Parent.BlurController)
- L27591: local var7 = require(script.Parent.CameraController)
- L27592: local var8 = require(var1.Modules.Helper.CreateGamepadHint)
- L27593: local var9 = require(var1.Modules.Helper.CutsceneState)
- L27594: local var10 = require(var1.Modules.Helper.DetachScreenGuis)
- L27595: local var11 = require(script.Parent.DeviceController)
- L27596: local var12 = require(var1.Modules.Helper.FormatCash)
- L27597: local var13 = require(script.Parent.GuiController)
- L27598: local var14 = require(var1.Modules.Helper.IS_RESERVED_SERVER)
- L27599: local var15 = require(script.Parent.InputControllerV2)
- L27600: local var16 = require(var1.Modules.Resources.Packets)
- L27601: local var17 = require(script.Parent.PeelingController)
- L27602: local var18 = require(var1.Shared.PlayerStateShared)
- L27603: local var19 = require(var1.Modules.Helper.SetSlotSelected)
- L27604: local var20 = require(var1.Shared.ToolUpgradeShared)

**ReplicatedStorage.Controllers.TopbarPlusController** (3):
- L28141: local var4 = require(var1.Packages.TopbarPlus)
- L28151: local var5 = require(script.Parent.DailyRewardController)
- L28152: local var6 = require(var1.Modules.Helper.IS_RESERVED_SERVER)

**ReplicatedStorage.Controllers.TutorialController** (19):
- L28165: local var3 = require(script.Parent.ToolUpgradeController)
- L28166: local var4 = require(var1.Shared.ToolUpgradeShared)
- L28167: local var5 = require(script.Parent.PeelingController)
- L28168: local var6 = require(var1.Shared.PlayerStateShared)
- L28169: local var7 = require(var1.Shared.TutorialShared)
- L28172: local var10 = require(var1.Modules.Helper.CreateGuideBeam)
- L28173: local var11 = require(var1.Modules.Helper.CutsceneState)
- L28174: local var12 = require(script.Parent.DeviceController)
- L28175: local var13 = require(script.Parent.DialogueController)
- L28176: local var14 = require(script.Parent.GuiController)
- L28177: local var15 = require(script.Parent.HighlightController)
- L28178: local var16 = require(var1.Modules.Helper.IS_RESERVED_SERVER)
- L28179: local var17 = require(script.Parent.IntroCutsceneController)
- L28180: local var18 = require(var1.Shared.KeyShared)
- L28181: local var19 = require(var1.Modules.Resources.Packets)
- L28182: local var20 = require(var1.Shared.PotatoTableShared)
- L28183: local var21 = require(var1.Shared.StoreShared)
- L28184: local var22 = require(var1.Shared.TutorialStackShared)
- L28185: local var23 = require(script.Parent.UISpotlightController)

**ReplicatedStorage.Controllers.UISpotlightController** (2):
- L28880: local var6 = require(script.Parent.GuiController)
- L28881: local var7 = require(game:GetService("ReplicatedStorage").Modules.Lib.MathLib)

**ReplicatedStorage.Controllers.WaterwayController** (4):
- L29099: local var4 = require(var1.Modules.Resources.Folders)
- L29100: local var5 = require(var1.Modules.Helper.IS_RESERVED_SERVER)
- L29101: local var6 = require(var1.Shared.PotatoTableShared)
- L29102: local var7 = require(script.Parent.WooshController)

**ReplicatedStorage.Controllers.ToolUseButtonController** (4):
- L29613: local var1 = require(script.Parent.PotatoPileController)
- L29631: local var5 = require(script.Parent.DeviceController)
- L29632: local var6 = require(game:GetService("ReplicatedStorage").Modules.Helper.IS_RESERVED_SERVER)
- L29633: local var7 = require(script.Parent.GuiController)

**ReplicatedStorage.Controllers.PeelRateController** (4):
- L29755: local var3 = require(var1.Modules.Helper.FlashLabels)
- L29787: local var5 = require(var1.Modules.Helper.IS_RESERVED_SERVER)
- L29788: local var6 = require(var1.Modules.Resources.Packets)
- L29820: local var7 = require(var1.Shared.PotatoTableShared)

**ReplicatedStorage.Controllers.HandHoldController** (3):
- L29907: local var5 = require(var1.Shared.PotatoHoldShared)
- L29909: local var6 = require(script.Parent.ArmStretchController)
- L29983: local var10 = require(var1.Modules.Helper.IS_RESERVED_SERVER)

**ReplicatedStorage.Controllers.WooshController** (2):
- L30106: local var1 = require(game:GetService("ReplicatedStorage").Modules.Resources.Sounds)
- L30108: local var2 = require(script.Parent.AudioController)

**ReplicatedStorage.Controllers.LobbySignController** (2):
- L30128: local var2 = require(var1.Modules.Helper.IS_RESERVED_SERVER)
- L30129: local var3 = require(var1.Shared.LeaderboardShared)

**ReplicatedStorage.Controllers.LobbyZoneController** (5):
- L30157: local var2 = require(script.Parent.LobbyUpgradeController)
- L30160: local var5 = require(script.Parent.ClassController)
- L30161: local var6 = require(script.Parent.GroupRewardController)
- L30162: local var7 = require(var1.Shared.GroupRewardShared)
- L30163: local var8 = require(var1.Modules.Helper.IS_RESERVED_SERVER)

**ReplicatedStorage.Controllers.MobileScaleController** (2):
- L30287: local var2 = require(script.Parent.DeviceController)
- L30288: local var3 = require(game:GetService("ReplicatedStorage").Modules.Helper.IS_RESERVED_SERVER)

**ReplicatedStorage.Controllers.ToolVfxController** (2):
- L30512: local var2 = require(var1.Shared.ToolUpgradeShared)
- L30563: local var4 = require(var1.Modules.Helper.IS_RESERVED_SERVER)

**ReplicatedStorage.Controllers.OthersHoldController** (4):
- L30632: local var3 = require(var1.Shared.PotatoKindShared)
- L30633: local var4 = require(var1.Modules.Helper.AttachPotatoKey)
- L30635: local var6 = require(var1.Shared.PotatoHoldShared)
- L30753: local var8 = require(var1.Modules.Helper.IS_RESERVED_SERVER)

**ReplicatedStorage.Controllers.DialogueController** (2):
- L30821: local var2 = require(game:GetService("ReplicatedStorage").Modules.Resources.Sounds)
- L31057: local var7 = require(script.Parent.AudioController)

**ReplicatedStorage.Controllers.SoldController** (12):
- L31504: local var7 = require(var1.Modules.Helper.PotatoKindStyle)
- L31505: local var8 = require(var1.Shared.PotatoKindShared)
- L31535: local var13 = require(script.Parent.PeelEarningsController)
- L31581: local var14 = require(var1.Modules.Helper.FlashLabels)
- L31582: local var15 = require(var1.Modules.Helper.FormatCash)
- L31622: local var16 = require(script.Parent.CashFlyController)
- L31697: local var21 = require(script.Parent.DialogueController)
- L31915: local var23 = require(script.Parent.WaterwayController)
- L31916: local var24 = require(script.Parent.CashController)
- L31937: local var25 = require(var1.Modules.Helper.IS_RESERVED_SERVER)
- L31938: local var26 = require(script.Parent.GuiController)
- L31994: local var27 = require(var1.Modules.Resources.Packets)

**ReplicatedStorage.Controllers.UnlockController** (12):
- L32151: local var7 = require(script.Parent.AudioController)
- L32152: local var8 = require(var1.Modules.Resources.Sounds)
- L32265: local var11 = require(script.Parent.DialogueController)
- L32367: local var12 = require(var1.Shared.UnlockShared)
- L32369: local var13 = require(var1.Shared.PeelToolShared)
- L32370: local var14 = require(var1.Shared.ToolUpgradeShared)
- L32371: local var15 = require(var1.Shared.CarryUpgradeShared)
- L32457: local var16 = require(var1.Shared.StoreShared)
- L32477: local var17 = require(var1.Shared.PotatoTableShared)
- L32531: local var18 = require(var1.Modules.Helper.IS_RESERVED_SERVER)
- L32532: local var19 = require(script.Parent.GuiController)
- L32551: local var21 = require(var1.Modules.Resources.Packets)

**ReplicatedStorage.Controllers.IntroCutsceneController** (15):
- L32591: local var8 = require(script.Parent.AudioController)
- L32592: local var9 = require(var1.Modules.Helper.CutsceneState)
- L32593: local var10 = require(script.Parent.DialogueController)
- L32594: local var11 = require(var1.Modules.Resources.Enums)
- L32595: local var12 = require(var1.Modules.Helper.IS_RESERVED_SERVER)
- L32596: local var13 = require(var1.Modules.Resources.Packets)
- L32597: local var14 = require(var1.Modules.Helper.PlayFocusPull)
- L32598: local var15 = require(var1.Shared.PotatoKindShared)
- L32599: local var16 = require(script.Parent.PotatoPileController)
- L32600: local var17 = require(var1.Modules.Resources.Sounds)
- L32601: local var18 = require(var1.Shared.StoreShared)
- L32602: local tbl1 = { TutorialHoldChanged = require(var1.ModifiedPackages.Signal).new() }
- L33982: local var4 = require(var1.Modules.Helper.KeyShine)
- L34065: local var2 = require(var1.Modules.Helper.KeyShine)
- L34438: local var8 = require((num1:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))):GetControls()

**ReplicatedStorage.Controllers.RadioController** (2):
- L34945: local var2 = require(var1.Modules.Resources.Sounds)
- L35001: local var5 = require(var1.Modules.Helper.IS_RESERVED_SERVER)

**ReplicatedStorage.Controllers.BlizzardController** (5):
- L35051: local var3 = require(var1.Modules.Resources.Sounds)
- L35056: local var7 = require(script.Parent.AudioController)
- L35057: local var8 = require(var1.Modules.Resources.Enums)
- L35061: local var12 = require(script.Parent.IntroCutsceneController)
- L35111: local var13 = require(var1.Modules.Helper.IS_RESERVED_SERVER)

**ReplicatedStorage.Controllers.EscapeCinematicController** (8):
- L35163: local var7 = require(script.Parent.DialogueController)
- L35164: local var8 = require(var1.Shared.KeyShared)
- L35196: local var10 = require(script.Parent.AudioController)
- L35197: local var11 = require(var1.Modules.Resources.Sounds)
- L35361: local var13 = require(var1.Modules.Helper.PlayFocusPull)
- L35399: local var15 = require(var1.Modules.Helper.CutsceneState)
- L35563: local var17 = require(script.Parent.PeelingController)
- L35573: local var3 = require((var2.PlayerScripts:WaitForChild("PlayerModule"))):GetControls()

**ReplicatedStorage.Controllers.KeyRevealController** (11):
- L35645: local var4 = require(var1.Shared.PotatoKindShared)
- L35647: local var6 = require(var1.Modules.Resources.Assets)
- L35648: local var7 = require(var1.Shared.KeyShared)
- L35650: local var9 = require(var1.Modules.Helper.KeyShine)
- L35656: local var15 = require(script.Parent.PeelingController)
- L35659: local var18 = require(var1.Modules.Helper.CutsceneState)
- L35660: local var19 = require(script.Parent.DialogueController)
- L35783: local var20 = require(script.Parent.AudioController)
- L35784: local var21 = require(var1.Modules.Resources.Sounds)
- L35785: local var22 = require(var1.Modules.Helper.PlayFocusPull)
- L35851: local var8 = require((var3.PlayerScripts:WaitForChild("PlayerModule"))):GetControls()

**ReplicatedStorage.Controllers.PotWaterController** (2):
- L36206: local var2 = require(var1.Shared.PotatoTableShared)
- L36278: local var5 = require(var1.Modules.Helper.IS_RESERVED_SERVER)

**ReplicatedStorage.Controllers.PeelEarningsController** (8):
- L36400: local var5 = require(script.Parent.CashController)
- L36401: local var6 = require(script.Parent.CashFlyController)
- L36402: local var7 = require(var1.Modules.Helper.FormatCash)
- L36403: local var8 = require(var1.Modules.Helper.IS_RESERVED_SERVER)
- L36404: local var9 = require(var1.Modules.Resources.Packets)
- L36405: local var10 = require(script.Parent.PeelingController)
- L36406: local var11 = require(var1.Shared.PotatoKindShared)
- L36407: local var12 = require(var1.Modules.Helper.PotatoKindStyle)

**ReplicatedStorage.Controllers.StoreSoldController** (9):
- L36724: local var2 = require(var1.Shared.StoreShared)
- L36725: local var3 = require(var1.Shared.PlayerStateShared)
- L36727: local var5 = require(var1.Shared.ToolUpgradeShared)
- L36728: local var6 = require(var1.Shared.PeelToolShared)
- L36729: local var7 = require(var1.Shared.CarryUpgradeShared)
- L36730: local var8 = require(var1.Shared.StoreLockShared)
- L36847: local var11 = require(var1.Modules.Helper.IS_RESERVED_SERVER)
- L36871: local var12 = require(var1.Shared.UnlockShared)
- L36872: local var13 = require(var1.Shared.PotatoTableShared)

**ReplicatedStorage.Controllers.LobbyTutorialController** (11):
- L36905: local var3 = require(var1.Shared.QueueShared)
- L36919: local var4 = require(var1.Shared.PlayerStateShared)
- L36920: local var5 = require(var1.Shared.LobbyUpgradeShared)
- L36988: local var10 = require(script.Parent.DialogueController)
- L36989: local var11 = require(var1.Modules.Resources.Packets)
- L36990: local var12 = require(var1.Modules.Helper.IS_STUDIO)
- L36991: local var13 = require(var1.Modules.Resources.Globals)
- L37039: local var15 = require(var1.Modules.Helper.CreateGuideBeam)
- L37040: local var16 = require(script.Parent.GuiController)
- L37041: local var17 = require(var1.Modules.Helper.IS_RESERVED_SERVER)
- L37042: local var18 = require(script.Parent.QueueController)

**ReplicatedStorage.Controllers.CashFlyController** (8):
- L37204: local var2 = require(var1.Modules.Resources.Sounds)
- L37208: local var4 = require(script.Parent.AudioController)
- L37210: local var5 = require(script.Parent.PeelingController)
- L37238: local var8 = require(script.Parent.CashController)
- L37239: local var9 = require(var1.Modules.Helper.FormatCash)
- L37240: local var10 = require(script.Parent.GuiController)
- L37241: local var11 = require(var1.Modules.Helper.IS_RESERVED_SERVER)
- L37242: local var12 = require(var1.Modules.Helper.PotatoKindStyle)

**ReplicatedStorage.Controllers.TablePromptController** (5):
- L37494: local var2 = require(var1.Shared.PlayerStateShared)
- L37497: local var5 = require(var1.Shared.TutorialStackShared)
- L37498: local var6 = require(var1.Shared.PotatoTableShared)
- L37588: local var7 = require(var1.Modules.Helper.IS_RESERVED_SERVER)
- L37589: local var8 = require(script.Parent.PeelingController)

**ReplicatedStorage.Controllers.TableBeaconController** (6):
- L37694: local var2 = require(var1.Shared.PeelToolShared)
- L37695: local var3 = require(var1.Shared.PlayerStateShared)
- L37697: local var5 = require(var1.Shared.PotatoTableShared)
- L37698: local var6 = require(var1.Shared.TutorialStackShared)
- L37699: local var7 = require(var1.Shared.PotatoKindShared)
- L37781: local var12 = require(var1.Modules.Helper.IS_RESERVED_SERVER)

**ReplicatedStorage.Controllers.ButtonAnimationController** (1):
- L37925: local var4 = require(script.Parent.UISpotlightController)

**ReplicatedStorage.Controllers.QuestCardController** (15):
- L38308: local var5 = require(var1.Shared.TutorialShared)
- L38309: local var6 = require(script.Parent.IntroCutsceneController)
- L38310: local var7 = require(var1.Modules.Helper.CutsceneState)
- L38311: local var8 = require(var1.Shared.PlayerStateShared)
- L38425: local var26 = require(var1.Modules.Helper.FormatCash)
- L38480: local var28 = require(script.Parent.AudioController)
- L38481: local var29 = require(var1.Modules.Resources.Sounds)
- L38541: local var33 = require(script.Parent.PeelingController)
- L38590: local var34 = require(script.Parent.CashController)
- L38592: local var36 = require(script.Parent.PotatoPileController)
- L38598: local var41 = require(var1.Shared.PotatoPileShared)
- L38802: local var44 = require(script.Parent.DeviceController)
- L38848: local var45 = require(script.Parent.CashFlyController)
- L38996: local var46 = require(var1.Modules.Helper.IS_RESERVED_SERVER)
- L38997: local var47 = require(script.Parent.GuiController)

**ReplicatedStorage.Controllers.BagPickupController** (4):
- L39143: local var3 = require(var1.Modules.Helper.PotatoKindStyle)
- L39148: local var7 = require(var1.Shared.PotatoKindShared)
- L39180: local var12 = require(script.Parent.BagController)
- L39239: local var13 = require(var1.Modules.Helper.IS_RESERVED_SERVER)

**ReplicatedStorage.Controllers.MobileStrokeController** (1):
- L39339: local var1 = require(script.Parent.DeviceController)

**ReplicatedStorage.Controllers.GamepadMenuController** (1):
- L39375: local var2 = require(script.Parent.DeviceController)

**ReplicatedStorage.Controllers.GroupRewardController** (6):
- L39491: local var4 = require(var1.Shared.GroupRewardShared)
- L39492: local var5 = require(script.Parent.GuiController)
- L39493: local var6 = require(var1.Modules.Helper.IS_RESERVED_SERVER)
- L39494: local var7 = require(var1.Modules.Resources.Packets)
- L39495: local var8 = require(var1.Shared.PlayerStateShared)
- L39496: local var9 = require(script.Parent.PopupPromptController)

**ReplicatedStorage.Controllers.MachineRevealController** (12):
- L39816: local var3 = require(script.Parent.PeelingController)
- L39817: local var4 = require(var1.Modules.Helper.CutsceneState)
- L39821: local var8 = require(script.Parent.CinematicBarsController)
- L39847: local var10 = require(script.Parent.AudioController)
- L39848: local var11 = require(var1.Modules.Resources.Sounds)
- L39849: local var12 = require(script.Parent.StoreLockController)
- L39851: return require((var2.PlayerScripts:WaitForChild("PlayerModule"))):GetControls()
- L39881: local var13 = require(var1.Modules.Helper.DetachScreenGuis)
- L39916: local var14 = require(var1.Modules.Logger)
- L39917: local var15 = require(var1.Shared.PotatoTableShared)
- L39948: local var16 = require(var1.Modules.Helper.IS_RESERVED_SERVER)
- L39949: local var17 = require(var1.Modules.Resources.Packets)

**ReplicatedStorage.Controllers.MachineSoldController** (9):
- L39977: local var2 = require(var1.Shared.PotatoKindShared)
- L39980: local var5 = require(script.Parent.GuiController)
- L39985: local var10 = require(var1.Modules.Helper.PotatoKindStyle)
- L40088: local var17 = require(script.Parent.CashFlyController)
- L40089: local var18 = require(script.Parent.CashController)
- L40090: local var19 = require(var1.Modules.Helper.FormatCash)
- L40091: local var20 = require(var1.Modules.Helper.FlashLabels)
- L40131: local var21 = require(var1.Modules.Helper.IS_RESERVED_SERVER)
- L40132: local var22 = require(var1.Modules.Resources.Packets)

**ReplicatedStorage.Controllers.PurchaseCelebrationController** (7):
- L40254: local var8 = require(var1.Modules.Helper.CutsceneState)
- L40256: local var10 = require(script.Parent.AudioController)
- L40257: local var11 = require(var1.Modules.Resources.Sounds)
- L40341: local var13 = require(var1.Shared.ToolUpgradeShared)
- L40342: local var14 = require(var1.Modules.Helper.IS_RESERVED_SERVER)
- L40343: local var15 = require(script.Parent.ToolEquipController)
- L40455: local var16 = require(var1.Modules.Resources.Packets)

**ReplicatedStorage.Controllers.RunReportController** (11):
- L40499: local var3 = require(var1.Shared.PotatoKindShared)
- L40560: local var11 = require(script.Parent.GuiController)
- L40561: local var12 = require(var1.Shared.LeaderboardShared)
- L40567: local var16 = require(var1.Shared.RunReportShared)
- L40568: local var17 = require(var1.Modules.Resources.Sounds)
- L40570: local var19 = require(script.Parent.DeviceController)
- L40794: local var48 = require(script.Parent.AudioController)
- L40799: local var52 = require(script.Parent.BlurController)
- L40800: local var53 = require(script.Parent.LobbyTutorialController)
- L40912: local var55 = require(var1.Modules.Helper.IS_RESERVED_SERVER)
- L40913: local var56 = require(var1.Modules.Resources.Packets)

**ReplicatedStorage.Controllers.StoreLockController** (6):
- L41032: local var2 = require(var1.Shared.StoreShared)
- L41037: local var7 = require(var1.Shared.StoreLockShared)
- L41070: local var8 = require(var1.Shared.PlayerStateShared)
- L41117: local var10 = require(var1.Modules.Helper.IS_RESERVED_SERVER)
- L41118: local var11 = require(var1.Shared.PotatoTableShared)
- L41119: local var12 = require(var1.Shared.UnlockShared)

**ReplicatedStorage.Modules.BehaviorCollection** (1):
- L41237: tbl1[var2] = require(v1)

**ReplicatedStorage.Modules.Buffer** (1):
- L41329: local var2 = require(script.Parent.Logger)

**ReplicatedStorage.Modules.Cancellable** (1):
- L41468: local var1 = require(game:GetService("ReplicatedStorage").ModifiedPackages.Signal)

**ReplicatedStorage.Modules.Framerate** (1):
- L41504: local var2 = require(script.Parent.Logger)

**ReplicatedStorage.Modules.Gizmos** (2):
- L41533: local var2 = require(var1.Shared.TimeShared)
- L41534: local var3 = require(var1.Modules.Helper.CreateDebugPart)(Vector3.new(0, 0, 0))

**ReplicatedStorage.Modules.IdMap** (1):
- L41683: local var1 = require(game:GetService("ReplicatedStorage").Modules.Logger)

**ReplicatedStorage.Modules.Initializer** (2):
- L41718: local var2 = require(script.Parent.Logger)
- L41769: return require(var1)

**ReplicatedStorage.Modules.Maid** (2):
- L41828: require(game:GetService("ReplicatedStorage").ModifiedPackages.Signal)
- L41829: local var1 = require(script.Parent.Logger)

**ReplicatedStorage.Modules.OBB** (1):
- L41880: require(script.Parent.AABB)

**ReplicatedStorage.Modules.Permissions** (1):
- L42041: local var3 = require(game:GetService("ReplicatedStorage").Modules.Helper.IS_STUDIO)

**ReplicatedStorage.Modules.RagdollModule** (2):
- L42111: require(game:GetService("ReplicatedStorage").Modules.Resources.Types)
- L42112: local var1 = require(script.buildRagdoll)

**ReplicatedStorage.Modules.RagdollModule.buildCollisionFilters** (1):
- L42141: local var1 = require(script.Parent.getLastWordFromPascalCase)

**ReplicatedStorage.Modules.RagdollModule.buildConstraints** (1):
- L42240: local var1 = require(script.Parent.getLastWordFromPascalCase)

**ReplicatedStorage.Modules.RagdollModule.buildRagdoll** (2):
- L42280: local var1 = require(script.Parent.buildCollisionFilters)
- L42281: local var2 = require(script.Parent.buildConstraints)

**ReplicatedStorage.Modules.Squash** (1):
- L42377: local var1 = require(game:GetService("ReplicatedStorage").Modules.Logger)

**ReplicatedStorage.Modules.TweenSequence** (1):
- L42447: local var3 = require(script.Parent.Logger)

**ReplicatedStorage.Modules.Helper.CreateSpring** (1):
- L42717: local var1 = require(game:GetService("ReplicatedStorage").ModifiedPackages.Ripple)

**ReplicatedStorage.Modules.Helper.IS_RESERVED_SERVER** (2):
- L42783: local var2 = require(script.Parent.IS_SERVER)
- L42784: local var3 = require(var1.Modules.Resources.Globals)

**ReplicatedStorage.Modules.Helper.SetCounterValue** (1):
- L42846: local var1 = require(game:GetService("ReplicatedStorage").Modules.Lib.TweenLib)

**ReplicatedStorage.Modules.Helper.SetSlotSelected** (1):
- L42873: local var1 = require(game:GetService("ReplicatedStorage").Modules.Lib.TweenLib)

**ReplicatedStorage.Modules.Helper.VerifyFunctionCaller** (2):
- L42903: local var1 = require(script.Parent.IS_SERVER)
- L42904: local var2 = require(game:GetService("ReplicatedStorage").Modules.Logger)

**ReplicatedStorage.Modules.Helper.WaitUntilExists** (1):
- L42922: local var1 = require(game:GetService("ReplicatedStorage").Modules.Logger)

**ReplicatedStorage.Modules.Helper.CutsceneState** (1):
- L43198: local tbl2 = { Changed = require(game:GetService("ReplicatedStorage").ModifiedPackages.Signal).new() }

**ReplicatedStorage.Modules.Helper.PotatoKindStyle** (1):
- L43258: local var1 = require(game:GetService("ReplicatedStorage").Shared.PotatoKindShared)

**ReplicatedStorage.Modules.Helper.AttachPotatoKey** (2):
- L43350: local var2 = require(var1.Shared.PotatoKindShared)
- L43354: local var7 = require(var1.Modules.Helper.Welder)

**ReplicatedStorage.Modules.Helper.CreateGamepadHint** (1):
- L43396: local var1 = require(script.Parent.GetGamepadImage)

**ReplicatedStorage.Modules.Helper.GetGamepadImage** (1):
- L43433: local var2 = require(game:GetService("ReplicatedStorage").ModifiedPackages.ExpressivePrompts.NewInputLabel.Gamepad.GamepadButtonImage)

**ReplicatedStorage.Modules.Lib.MathLib** (2):
- L43611: local var2 = require(var1.Modules.DeltaTime)
- L43612: local var3 = require(var1.Modules.Logger)

**ReplicatedStorage.Modules.Lib.TableLib** (2):
- L43727: local var2 = require(var1.Modules.Logger)
- L43728: local var3 = require(var1.Modules.Helper.NIL_SYMBOL)

**ReplicatedStorage.Modules.Lib.TweenLib** (1):
- L43941: local var1 = require(game:GetService("ReplicatedStorage").ModifiedPackages.Promise)

**ReplicatedStorage.Modules.Resources.CollisionGroups** (1):
- L44117: local var2 = require(game:GetService("ReplicatedStorage").Modules.Helper.IS_SERVER)

**ReplicatedStorage.Modules.Resources.Events** (1):
- L44181: local var1 = require(game:GetService("ReplicatedStorage").ModifiedPackages.Signal)

**ReplicatedStorage.Modules.Resources.Folders** (1):
- L44191: local var2 = require(var1.Modules.Helper.IS_SERVER)

**ReplicatedStorage.Modules.Resources.Globals** (1):
- L44269: local var1 = require(game:GetService("ReplicatedStorage").Modules.Helper.IS_STUDIO)

**ReplicatedStorage.Modules.Resources.Packets** (8):
- L44294: require(var1.Shared.AudioShared)
- L44295: require(var1.Shared.LeaderboardShared)
- L44296: require(var1.Shared.NotificationShared)
- L44297: require(var1.Shared.RunReportShared)
- L44298: require(var1.Shared.StatsShared)
- L44299: local var2 = require(var1.ModifiedPackages.Packet)
- L44300: local var3 = require(var1.Modules.Helper.IS_SERVER)
- L44301: local var4 = require(var1.Modules.Logger)

**ReplicatedStorage.Modules.Resources.Resource** (4):
- L44454: local var2 = require(var1.Modules.Helper.IS_SERVER)
- L44455: local var3 = require(var1.Modules.Logger)
- L44456: local var4 = require(var1.ModifiedPackages.Signal)
- L44457: local var5 = require(var1.Modules.Lib.TableLib)

**ReplicatedStorage.Modules.Resources.Sounds** (3):
- L44578: local var2 = require(script.Parent.Enums)
- L44579: local var3 = require(var1.Modules.Helper.IS_SERVER)
- L44580: local var4 = require(var1.Modules.Logger)

**ReplicatedStorage.Modules.Resources.Types** (2):
- L44755: require(var1.Modules.Resources.Assets)
- L44756: require(var1.Modules.Helper.NIL_SYMBOL)

**ReplicatedStorage.Shared.CacheShared** (1):
- L44788: local var1 = require(game:GetService("ReplicatedStorage").Modules.Logger)

**ReplicatedStorage.Shared.CarryUpgradeShared** (2):
- L44873: local var2 = require(var1.Modules.Resources.Gamepasses)
- L44874: local var3 = require(var1.Shared.LobbyUpgradeShared)

**ReplicatedStorage.Shared.GamepassShared** (2):
- L45262: local var3 = require(var1.Modules.Resources.Gamepasses)
- L45263: local var4 = require(var1.Modules.Logger)

**ReplicatedStorage.Shared.NotificationShared** (1):
- L45489: require(game:GetService("ReplicatedStorage").Modules.Resources.Enums)

**ReplicatedStorage.Shared.PlayerShared** (2):
- L45495: local var1 = require(script.Parent.CacheShared)
- L45498: local var4 = require(game:GetService("ReplicatedStorage").Modules.Logger)

**ReplicatedStorage.Shared.PlayerStateShared** (9):
- L45555: require(var1.Modules.Helper.NIL_SYMBOL)
- L45558: local var4 = require(var1.Modules.Resources.Enums)
- L45559: local var5 = require(var1.Modules.Helper.IS_SERVER)
- L45560: local var6 = require(var1.Modules.Helper.IS_STUDIO)
- L45561: local var7 = require(var1.Modules.Logger)
- L45562: local var8 = require(var1.Modules.Resources.Packets)
- L45563: local var9 = require(var1.Modules.Lib.TableLib)
- L45564: local var10 = require(var1.Modules.Helper.WaitUntilExists)
- L45565: local tbl1 = { StateChanged = require(var1.ModifiedPackages.Signal).new() }

**ReplicatedStorage.Shared.PotatoHoldShared** (2):
- L45796: local var2 = require(var1.Modules.Resources.Assets)
- L45797: local var3 = require(var1.Shared.PotatoKindShared)

**ReplicatedStorage.Shared.PotatoKindShared** (2):
- L46205: local var2 = require(var1.Modules.Resources.Assets).Assets:WaitForChild("Potatoes")
- L46253: local var4 = require(var1.Shared.PeelToolShared)

**ReplicatedStorage.Shared.PotatoPileShared** (2):
- L46512: local var2 = require(var1.Modules.Resources.Assets)
- L46517: local var7 = require(var1.Shared.PotatoKindShared)

**ReplicatedStorage.Shared.PotatoTableShared** (1):
- L46957: local var1 = require(game:GetService("ReplicatedStorage").Shared.PotatoKindShared)

**ReplicatedStorage.Shared.ProductShared** (2):
- L47160: local var2 = require(var1.Modules.Resources.Products)
- L47161: local var3 = require(var1.Modules.Logger)

**ReplicatedStorage.Shared.SpatialHashShared** (1):
- L47193: local var1 = require(game:GetService("ReplicatedStorage").Modules.Logger)

**ReplicatedStorage.Shared.StatsShared** (1):
- L47272: local var1 = require(game:GetService("ReplicatedStorage").Shared.GameTimerShared)

**ReplicatedStorage.Shared.TimeShared** (4):
- L47600: local var2 = require(var1.ModifiedPackages.Signal)
- L47602: local var4 = require(var1.Modules.DeltaTime)
- L47603: local var5 = require(var1.Modules.Resources.Globals)
- L47604: local var6 = require(var1.Modules.Logger)

**ReplicatedStorage.Shared.ToolUpgradeShared** (2):
- L47661: local var2 = require(var1.Shared.ClassShared)
- L47662: local var3 = require(var1.Modules.Resources.Products)

**ReplicatedStorage.Shared.TutorialShared** (6):
- L48199: require(var1.Shared.PlayerStateShared)
- L48200: local var2 = require(var1.Shared.CarryUpgradeShared)
- L48201: local var3 = require(var1.Shared.PeelToolShared)
- L48202: local var4 = require(var1.Shared.PotatoPileShared)
- L48203: local var5 = require(var1.Shared.PotatoTableShared)
- L48204: local var6 = require(var1.Shared.ToolUpgradeShared)

**ReplicatedStorage.Shared.PeelToolShared** (1):
- L48384: local var1 = require(game:GetService("ReplicatedStorage").Modules.Resources.Assets)

**ReplicatedStorage.Shared.UnlockShared** (1):
- L48570: local var1 = require(game:GetService("ReplicatedStorage").Shared.PotatoTableShared)

**ReplicatedStorage.Shared.SellValueShared** (5):
- L48619: require(var1.Shared.PlayerStateShared)
- L48620: local var2 = require(var1.Shared.ClassShared)
- L48621: local var3 = require(var1.Shared.LobbyUpgradeShared)
- L48622: local var4 = require(var1.Shared.PotatoKindShared)
- L48623: local var5 = require(var1.Shared.ToolUpgradeShared)

**ReplicatedStorage.Shared.TutorialStackShared** (2):
- L48697: local var2 = require(var1.Shared.PotatoTableShared)
- L48699: local tbl2 = { Changed = require(var1.ModifiedPackages.Signal).new() }

**ReplicatedStorage.Shared.RunReportShared** (2):
- L48743: local var2 = require(var1.Modules.Helper.FormatNumber)
- L48744: local var3 = require(var1.Shared.GameTimerShared)

**ReplicatedStorage.Shared.StoreLockShared** (7):
- L48795: require(var1.Shared.PlayerStateShared)
- L48796: local var2 = require(var1.Shared.CarryUpgradeShared)
- L48797: local var3 = require(var1.Shared.PeelToolShared)
- L48798: local var4 = require(var1.Shared.PotatoTableShared)
- L48799: local var5 = require(var1.Shared.StoreShared)
- L48800: local var6 = require(var1.Shared.ToolUpgradeShared)
- L48801: local var7 = require(var1.Shared.UnlockShared)

### B1. ReplicatedStorage.ModifiedPackages (Packet/Signal/Promise/Ripple/ExpressivePrompts/Seam)

185 require sites in 44 scripts

**ReplicatedStorage.ModifiedPackages.Packet** (3):
- L48932: local var1 = require(script._Types)
- L48935: local var4 = require(script._Signal)
- L48936: local var5 = require(script._Task)

**ReplicatedStorage.ModifiedPackages.Packet._Signal** (1):
- L49458: local var1 = require(script.Parent._Task)

**ReplicatedStorage.ModifiedPackages.Packet._Types** (5):
- L49708: local var7 = require(script._Characters)
- L51147: local var10 = require(script._Enums)
- L51187: local var11 = require(script._Static1)
- L51220: local var12 = require(script._Static2)
- L51253: local var13 = require(script._Static3)

**ReplicatedStorage.ModifiedPackages.Promise** (1):
- L52605: return (require(script._Promise))

**ReplicatedStorage.ModifiedPackages.Ripple** (6):
- L54079: require("@self/types")
- L54080: local var1 = require("@self/config")
- L54081: local var2 = require("@self/easing")
- L54082: local var3 = require("@self/motion")
- L54083: local var4 = require("@self/spring")
- L54084: local var5 = require("@self/tween")

**ReplicatedStorage.ModifiedPackages.Ripple.config** (1):
- L54099: require("./spring")

**ReplicatedStorage.ModifiedPackages.Ripple.motion** (5):
- L54372: require("./types")
- L54373: local var1 = require("./utils/scheduler")
- L54374: local var2 = require("./utils/signal")
- L54375: local var3 = require("./spring")
- L54376: local var4 = require("./tween")

**ReplicatedStorage.ModifiedPackages.Ripple.spring** (4):
- L54601: require("./types")
- L54602: local var1 = require("./utils/intermediate")
- L54603: local var2 = require("./utils/scheduler")
- L54604: local var3 = require("./utils/signal")

**ReplicatedStorage.ModifiedPackages.Ripple.tween** (6):
- L54937: require("./types")
- L54938: local var1 = require("./easing")
- L54939: local var2 = require("./utils/interpolate")
- L54940: local var3 = require("./utils/merge")
- L54941: local var4 = require("./utils/scheduler")
- L54942: local var5 = require("./utils/signal")

**ReplicatedStorage.ModifiedPackages.Ripple.utils.intermediate** (2):
- L55137: local var1 = require("./merge")
- L55138: local var2 = require("./oklab")

**ReplicatedStorage.ModifiedPackages.Ripple.utils.interpolate** (2):
- L55343: require("../types")
- L55344: local var1 = require("./oklab")

**ReplicatedStorage.ModifiedPackages.Ripple.utils.signal** (1):
- L55526: local var1 = require("./spawn")

**ReplicatedStorage.ModifiedPackages.ExpressivePrompts** (5):
- L55827: local var6 = if var5 then require(var5.Seam) else require(script.Parent.Seam)
- L55828: local var7 = require(script.NewInputLabel)
- L55829: local var8 = require(script.NewInputConnections)
- L55830: local var9 = require(script.BuildFrames)
- L55831: local var10 = require(script.SoundData)

**ReplicatedStorage.ModifiedPackages.ExpressivePrompts.NewInputConnections** (1):
- L56480: local var2 = require(script.Parent.SoundData)

**ReplicatedStorage.ModifiedPackages.ExpressivePrompts.SoundData** (1):
- L56556: local var3 = if var2 then require(var2.Seam) else require(script.Parent.Parent.Seam)

**ReplicatedStorage.ModifiedPackages.ExpressivePrompts.NewInputLabel** (3):
- L56568: local tbl1 = { [Enum.ProximityPromptInputType.Gamepad] = require(script.Gamepad) }
- L56569: tbl1[Enum.ProximityPromptInputType.Touch] = require(script.Touch)
- L56570: tbl1.Default = require(script.Keyboard)

**ReplicatedStorage.ModifiedPackages.ExpressivePrompts.NewInputLabel.Gamepad** (1):
- L56615: local var2 = require(script.GamepadButtonImage)

**ReplicatedStorage.ModifiedPackages.ExpressivePrompts.NewInputLabel.Keyboard** (3):
- L56660: local var2 = require(script.KeyboardButtonImage)
- L56661: local var3 = require(script.KeyboardButtonIconMapping)
- L56662: local var4 = require(script.KeyCodeToTextMapping)

**ReplicatedStorage.ModifiedPackages.Seam** (32):
- L56796: require(var2:WaitForChild(str1))
- L56801: local var4 = require(var2:WaitForChild(str2))
- L56804: local var6 = require(var3:WaitForChild(str3))
- L56806: str1 = require(var3:WaitForChild(str4))
- L56808: str2 = require(var5:WaitForChild(str5))
- L56810: str3 = require(var5:WaitForChild(str6))
- L56811: str4 = require(var5:WaitForChild(str7))
- L56813: str5 = require(var5:WaitForChild(str8))
- L56816: str6 = require(var5.Animation:WaitForChild(str9))
- L56819: str7 = require(var5.Animation:WaitForChild(str10))
- L56821: str8 = require(var1:WaitForChild("Memory"):WaitForChild(str11))
- L56823: str9 = require(var7:WaitForChild(str12))
- L56825: str10 = require(var7:WaitForChild(str13))
- L56827: str11 = require(var3:WaitForChild(str14))
- L56829: str12 = require(var7:WaitForChild(str15))
- L56831: str13 = require(var3:WaitForChild(str16))
- L56833: str14 = require(var5:WaitForChild(str17))
- L56836: str15 = require(var3:WaitForChild(str18))
- L56838: str16 = require(var3:WaitForChild(str19))
- L56840: str17 = require(var8:WaitForChild(str20))
- L56842: str18 = require(var3:WaitForChild(str21))
- L56844: str19 = require(var3:WaitForChild(str22))
- L56846: str20 = require(var3:WaitForChild(str23))
- L56848: str21 = require(var8:WaitForChild(str24))
- L56850: str22 = require(var8:WaitForChild(str25))
- L56852: str23 = require(var8:WaitForChild(str26))
- L56854: str24 = require(var8:WaitForChild(str27))
- L56856: str25 = require(var8:WaitForChild(str28))
- L56858: str26 = require(var7:WaitForChild(str29))
- L56860: str27 = require(var3:WaitForChild(str30))
- L56862: str28 = require(var3:WaitForChild(str31))
- L56863: str29 = require(var5:WaitForChild(str32))

**ReplicatedStorage.ModifiedPackages.Seam.Modules.StateManager** (4):
- L57018: local var1 = require(script.Parent.Trove)
- L57019: local var2 = require(script.Parent.IsValueChanged)
- L57020: local var3 = require(script.Parent.CreateDeepTraceback)
- L57021: local var4 = require(script.Parent.UpdateSignals)

**ReplicatedStorage.ModifiedPackages.Seam.Modules.Signal** (1):
- L57405: local var2 = require(script.Connection)

**ReplicatedStorage.ModifiedPackages.Seam.Modules.ValuePacker** (1):
- L57612: local var1 = require(script.Oklab)

**ReplicatedStorage.ModifiedPackages.Seam.Constructors.Declarations.Attribute** (2):
- L57994: require(var1.Types)
- L57995: local var2 = require(var1.Symbol).new("Attribute")

**ReplicatedStorage.ModifiedPackages.Seam.Constructors.Declarations.Children** (2):
- L58083: require(var1.Types)
- L58128: local var2 = require(var1.Symbol).new("Children")

**ReplicatedStorage.ModifiedPackages.Seam.Constructors.Declarations.Component** (2):
- L58169: require(script.Parent.Parent.Memory.Scope)
- L58170: local var1 = require(script.Parent.Parent.Parent.Modules.Symbol)

**ReplicatedStorage.ModifiedPackages.Seam.Constructors.Declarations.Destroyed** (1):
- L58206: local var1 = require(script.Parent.Parent.Parent.Modules.Symbol).new("Destroyed")

**ReplicatedStorage.ModifiedPackages.Seam.Constructors.Declarations.EventSequence** (3):
- L58228: local var2 = require(var1.Trove)
- L58229: local var3 = require(var1.UpdateSignals)
- L58230: local var4 = require(var1.Symbol).new("EventSequence")

**ReplicatedStorage.ModifiedPackages.Seam.Constructors.Declarations.FollowAttribute** (2):
- L58353: require(var1.Types)
- L58354: local var2 = require(var1.Symbol).new("FollowAttribute")

**ReplicatedStorage.ModifiedPackages.Seam.Constructors.Declarations.FollowProperty** (2):
- L58435: require(var1.Types)
- L58436: local var2 = require(var1.Symbol).new("FollowProperty")

**ReplicatedStorage.ModifiedPackages.Seam.Constructors.Declarations.Lifetime** (1):
- L58517: local var2 = require(script.Parent.Parent.Parent.Modules.Symbol).new("Lifetime")

**ReplicatedStorage.ModifiedPackages.Seam.Constructors.Declarations.New** (4):
- L58539: require(script.Parent.Parent.Memory.Scope)
- L58540: local var2 = require(var1.CreateDeepTraceback)
- L58541: local var3 = require(script.Parent.Children)
- L58542: local var4 = require(var1.Symbol).new("New")

**ReplicatedStorage.ModifiedPackages.Seam.Constructors.Declarations.StyleSheet** (1):
- L58612: local var1 = require(script.Parent.Parent.Parent.Modules.Symbol)

**ReplicatedStorage.ModifiedPackages.Seam.Constructors.Declarations.Tags** (1):
- L58866: local var1 = require(script.Parent.Parent.Parent.Modules.Symbol).new("Tags")

**ReplicatedStorage.ModifiedPackages.Seam.Constructors.Memory.Scope** (12):
- L58891: require(var2.Types)
- L58893: require(var3.Computed)
- L58894: require(var3.Rendered)
- L58895: require(var3.Value)
- L58896: require(var3.Animation.Spring)
- L58897: require(var3.Animation.Tween)
- L58898: require(var3.ForPairs)
- L58899: require(var3.Bezier)
- L58900: require(var3.Resource)
- L58901: local var4 = require(var2.Symbol)
- L58903: local var5 = require(var2.CreateDeepTraceback)
- L58905: local var7 = require(var2.Trove)

**ReplicatedStorage.ModifiedPackages.Seam.Constructors.States.Bezier** (7):
- L59060: local var3 = require(var2.Symbol)
- L59061: local var4 = require(var2.ValuePacker)
- L59062: local var5 = require(var2.Trove)
- L59063: local var6 = require(var2.Signal)
- L59064: local var7 = require(script.Parent.Value)
- L59065: local var8 = require(var1.Utilities.GetValue)
- L59066: local var9 = require(script.Parent.Computed)

**ReplicatedStorage.ModifiedPackages.Seam.Constructors.States.Computed** (9):
- L59351: require(var1.Types)
- L59352: require(script.Parent.Value)
- L59353: local var2 = require(var1.Symbol)
- L59354: local var3 = require(var1.Trove)
- L59355: local var4 = require(var1.Signal)
- L59356: local var5 = require(script.Parent.Parent.Utilities.IsState)
- L59357: local var6 = require(script.Parent.Parent.Utilities.GetValue)
- L59358: local var7 = require(var1.Batch)
- L59359: local var8 = require(var1.StateManager)

**ReplicatedStorage.ModifiedPackages.Seam.Constructors.States.ForPairs** (5):
- L59486: require(var1.Types)
- L59487: require(script.Parent.Value)
- L59488: local var2 = require(script.Parent.Computed)
- L59489: local var3 = require(var1.CreateDeepTraceback)
- L59490: local var4 = require(var1.Symbol).new("ForPairs")

**ReplicatedStorage.ModifiedPackages.Seam.Constructors.States.Rendered** (7):
- L59553: require(var1.Types)
- L59554: local var2 = require(var1.Symbol)
- L59555: local var3 = require(var1.Trove)
- L59556: local var4 = require(var1.Signal)
- L59557: local var5 = require(var1.UpdateSignals)
- L59558: local var6 = require(var1.Batch)
- L59559: local var7 = require(var1.StateManager)

**ReplicatedStorage.ModifiedPackages.Seam.Constructors.States.Resource** (6):
- L59641: require(var1.Types)
- L59642: local var2 = require(var1.Symbol)
- L59643: local var3 = require(var1.Trove)
- L59644: local var4 = require(var1.Signal)
- L59645: local var5 = require(var1.Batch)
- L59646: local var6 = require(var1.StateManager)

**ReplicatedStorage.ModifiedPackages.Seam.Constructors.States.Value** (7):
- L59798: require(var1.Types)
- L59799: local var2 = require(var1.Symbol)
- L59800: local var3 = require(var1.Trove)
- L59801: local var4 = require(var1.Signal)
- L59802: local var5 = require(var1.IsValueChanged)
- L59803: local var6 = require(var1.Batch)
- L59804: local var7 = require(var1.StateManager)

**ReplicatedStorage.ModifiedPackages.Seam.Constructors.States.Animation.Spring** (10):
- L60031: require(var2.Types)
- L60032: local var3 = require(var2.Symbol)
- L60033: local var4 = require(var2.ValuePacker)
- L60034: local var5 = require(var1.Utilities.GetValue)
- L60046: local var6 = require(var2.Trove)
- L60047: local var7 = require(var2.Signal)
- L60048: local var8 = require(var2.UpdateSignals)
- L60076: local var9 = require(var2.IsValueChanged)
- L60077: local var10 = require(var2.Batch)
- L60078: local var11 = require(var2.StateManager)

**ReplicatedStorage.ModifiedPackages.Seam.Constructors.States.Animation.Tween** (10):
- L60280: require(var2.Types)
- L60281: local var3 = require(var2.Symbol)
- L60282: local var4 = require(var2.ValuePacker)
- L60284: local var6 = require(var1.Utilities.GetValue)
- L60295: local var7 = require(var2.Trove)
- L60296: local var8 = require(var2.Signal)
- L60297: local var9 = require(var2.UpdateSignals)
- L60312: local var10 = require(var2.IsValueChanged)
- L60313: local var11 = require(var2.Batch)
- L60314: local var12 = require(var2.StateManager)

**ReplicatedStorage.ModifiedPackages.Seam.Constructors.Utilities.GetValue** (1):
- L60458: local var1 = require(script.Parent.IsState)

**ReplicatedStorage.ModifiedPackages.Seam.Constructors.Utilities.LockValue** (1):
- L60574: require(script.Parent.Parent.States.Value)

### C. ReplicatedStorage.CmdrClient (vendored Cmdr admin lib)

74 require sites in 53 scripts

**ReplicatedStorage.CmdrClient** (6):
- L10818: local var1 = require("@self/Shared/Dispatcher")
- L10819: local var2 = require("@self/Shared/Registry")
- L10820: local var3 = require("@self/Shared/Util")
- L10821: local var4 = require("@self/CmdrInterface")
- L10822: local var5 = require("@self/DefaultEventHandlers")
- L10925: require(arg1)(tbl1.Registry)

**ReplicatedStorage.CmdrClient.CmdrInterface** (3):
- L10964: local var1 = require("@self/CreateGui")
- L10965: local var2 = require("@self/AutoComplete")
- L10966: local var3 = require("@self/Window")

**ReplicatedStorage.CmdrClient.Shared.Argument** (1):
- L11943: local var1 = require("./Util")

**ReplicatedStorage.CmdrClient.Shared.Command** (1):
- L12218: local var2 = require("./Argument")

**ReplicatedStorage.CmdrClient.Shared.Dispatcher** (2):
- L12441: local var5 = require("./Util")
- L12442: local var6 = require("./Command")

**ReplicatedStorage.CmdrClient.Shared.Registry** (4):
- L12726: local var2 = require("./Util")
- L12806: require(v1)(arg1)
- L12908: local var1 = require(arg2)
- L12912: var1.Run = require(arg3)

**ReplicatedStorage.CmdrClient.Commands.AddPeeled** (1):
- L13989: Group = require(game:GetService("ReplicatedStorage").Modules.Resources.Enums).PermissionLevel.Admin,

**ReplicatedStorage.CmdrClient.Commands.AddUnpeeled** (1):
- L14010: Group = require(game:GetService("ReplicatedStorage").Modules.Resources.Enums).PermissionLevel.Admin,

**ReplicatedStorage.CmdrClient.Commands.Ban** (1):
- L14030: Group = require(game:GetService("ReplicatedStorage").Modules.Resources.Enums).PermissionLevel.Admin,

**ReplicatedStorage.CmdrClient.Commands.BanByUserId** (1):
- L14046: Group = require(game:GetService("ReplicatedStorage").Modules.Resources.Enums).PermissionLevel.Admin,

**ReplicatedStorage.CmdrClient.Commands.Bring** (1):
- L14062: Group = require(game:GetService("ReplicatedStorage").Modules.Resources.Enums).PermissionLevel.Admin,

**ReplicatedStorage.CmdrClient.Commands.Fly** (3):
- L14072: require(var1.Modules.Resources.Types)
- L14101: local var8 = require(var1.Modules.Resources.Enums)
- L14125: local var12 = require(var6.LocalPlayer.PlayerScripts:WaitForChild("PlayerModule"):WaitForChild(str1))

**ReplicatedStorage.CmdrClient.Commands.ForceKey** (1):
- L14191: Group = require(game:GetService("ReplicatedStorage").Modules.Resources.Enums).PermissionLevel.Admin,

**ReplicatedStorage.CmdrClient.Commands.GivePotatoes** (1):
- L14203: Group = require(game:GetService("ReplicatedStorage").Modules.Resources.Enums).PermissionLevel.Admin,

**ReplicatedStorage.CmdrClient.Commands.GiveShinies** (1):
- L14230: Group = require(game:GetService("ReplicatedStorage").Modules.Resources.Enums).PermissionLevel.Admin,

**ReplicatedStorage.CmdrClient.Commands.Help** (1):
- L14256: Group = require(game:GetService("ReplicatedStorage").Modules.Resources.Enums).PermissionLevel.Admin,

**ReplicatedStorage.CmdrClient.Commands.Kick** (1):
- L14285: Group = require(game:GetService("ReplicatedStorage").Modules.Resources.Enums).PermissionLevel.Admin,

**ReplicatedStorage.CmdrClient.Commands.LogGlobalOverrides** (1):
- L14296: Group = require(game:GetService("ReplicatedStorage").Modules.Resources.Enums).PermissionLevel.Admin,

**ReplicatedStorage.CmdrClient.Commands.Op** (1):
- L14308: Group = require(game:GetService("ReplicatedStorage").Modules.Resources.Enums).PermissionLevel.Admin,

**ReplicatedStorage.CmdrClient.Commands.Peel** (2):
- L14327: Group = require(var1.Modules.Resources.Enums).PermissionLevel.Admin,
- L14332: require(var1.Controllers.PeelingController).StartPeeling()

**ReplicatedStorage.CmdrClient.Commands.ResetData** (1):
- L14343: Group = require(game:GetService("ReplicatedStorage").Modules.Resources.Enums).PermissionLevel.Admin,

**ReplicatedStorage.CmdrClient.Commands.ResetGlobal** (1):
- L14354: Group = require(game:GetService("ReplicatedStorage").Modules.Resources.Enums).PermissionLevel.Admin,

**ReplicatedStorage.CmdrClient.Commands.SetCash** (1):
- L14366: Group = require(game:GetService("ReplicatedStorage").Modules.Resources.Enums).PermissionLevel.Admin,

**ReplicatedStorage.CmdrClient.Commands.SetGlobal** (1):
- L14386: Group = require(game:GetService("ReplicatedStorage").Modules.Resources.Enums).PermissionLevel.Admin,

**ReplicatedStorage.CmdrClient.Commands.Speed** (1):
- L14398: Group = require(game:GetService("ReplicatedStorage").Modules.Resources.Enums).PermissionLevel.Admin,

**ReplicatedStorage.CmdrClient.Commands.Teleport** (1):
- L14418: Group = require(game:GetService("ReplicatedStorage").Modules.Resources.Enums).PermissionLevel.Admin,

**ReplicatedStorage.CmdrClient.Commands.Unban** (1):
- L14429: Group = require(game:GetService("ReplicatedStorage").Modules.Resources.Enums).PermissionLevel.Admin,

**ReplicatedStorage.CmdrClient.Commands.Vanish** (1):
- L14440: Group = require(game:GetService("ReplicatedStorage").Modules.Resources.Enums).PermissionLevel.Admin,

**ReplicatedStorage.CmdrClient.Commands.GivePeelTool** (1):
- L14452: Group = require(game:GetService("ReplicatedStorage").Modules.Resources.Enums).PermissionLevel.Admin,

**ReplicatedStorage.CmdrClient.Commands.SpawnKey** (1):
- L14473: Group = require(game:GetService("ReplicatedStorage").Modules.Resources.Enums).PermissionLevel.Admin,

**ReplicatedStorage.CmdrClient.Commands.Gamepass** (1):
- L14485: Group = require(game:GetService("ReplicatedStorage").Modules.Resources.Enums).PermissionLevel.Admin,

**ReplicatedStorage.CmdrClient.Commands.Carry** (1):
- L14507: Group = require(game:GetService("ReplicatedStorage").Modules.Resources.Enums).PermissionLevel.Admin,

**ReplicatedStorage.CmdrClient.Commands.Avatar** (1):
- L14528: Group = require(game:GetService("ReplicatedStorage").Modules.Resources.Enums).PermissionLevel.Admin,

**ReplicatedStorage.CmdrClient.Commands.Money** (1):
- L14549: Group = require(game:GetService("ReplicatedStorage").Modules.Resources.Enums).PermissionLevel.Admin,

**ReplicatedStorage.CmdrClient.Commands.DumpUi** (1):
- L14572: Group = require(var1.Modules.Resources.Enums).PermissionLevel.Admin,

**ReplicatedStorage.CmdrClient.Commands.Dialogue** (2):
- L14617: Group = require(var1.Modules.Resources.Enums).PermissionLevel.Admin,
- L14652: task.spawn(require(var1.Controllers.DialogueController).Say, getLabel(), { arg2 or "You call *THAT* a plan?" })

**ReplicatedStorage.CmdrClient.Commands.Tutorial** (1):
- L14664: Group = require(game:GetService("ReplicatedStorage").Modules.Resources.Enums).PermissionLevel.Admin,

**ReplicatedStorage.CmdrClient.Commands.Cutscene** (1):
- L14685: Group = require(game:GetService("ReplicatedStorage").Modules.Resources.Enums).PermissionLevel.Admin,

**ReplicatedStorage.CmdrClient.Commands.PileCut** (1):
- L14697: Group = require(game:GetService("ReplicatedStorage").Modules.Resources.Enums).PermissionLevel.Admin,

**ReplicatedStorage.CmdrClient.Commands.RunPeels** (1):
- L14714: Group = require(game:GetService("ReplicatedStorage").Modules.Resources.Enums).PermissionLevel.Admin,

**ReplicatedStorage.CmdrClient.Commands.UnlockTools** (1):
- L14726: Group = require(game:GetService("ReplicatedStorage").Modules.Resources.Enums).PermissionLevel.Admin,

**ReplicatedStorage.CmdrClient.Commands.FillLeaderboard** (3):
- L14742: local var2 = require(var1.Shared.LeaderboardShared)
- L14746: Group = require(var1.Modules.Resources.Enums).PermissionLevel.Admin,
- L14771: local var5 = require(var1.Controllers.LeaderboardController)

**ReplicatedStorage.CmdrClient.Commands.ResetTutorial** (1):
- L14787: Group = require(game:GetService("ReplicatedStorage").Modules.Resources.Enums).PermissionLevel.Admin,

**ReplicatedStorage.CmdrClient.Commands.FirstPerson** (2):
- L14806: Group = require(var1.Modules.Resources.Enums).PermissionLevel.Admin,
- L14811: require(var1.Controllers.CameraController).SetThirdPerson(false)

**ReplicatedStorage.CmdrClient.Commands.ThirdPerson** (2):
- L14824: Group = require(var1.Modules.Resources.Enums).PermissionLevel.Admin,
- L14829: require(var1.Controllers.CameraController).SetThirdPerson(true)

**ReplicatedStorage.CmdrClient.Commands.SetPeelTool** (1):
- L14841: Group = require(game:GetService("ReplicatedStorage").Modules.Resources.Enums).PermissionLevel.Admin,

**ReplicatedStorage.CmdrClient.Commands.Sell** (1):
- L14866: Group = require(game:GetService("ReplicatedStorage").Modules.Resources.Enums).PermissionLevel.Admin,

**ReplicatedStorage.CmdrClient.Commands.Celebrate** (1):
- L14878: Group = require(game:GetService("ReplicatedStorage").Modules.Resources.Enums).PermissionLevel.Admin,

**ReplicatedStorage.CmdrClient.Commands.FakeReport** (2):
- L14891: Group = require(var1.Modules.Resources.Enums).PermissionLevel.Admin,
- L14903: return require(var1.Controllers.RunReportController).Preview(var2)

**ReplicatedStorage.CmdrClient.Commands.Freecam** (1):
- L14914: Group = require(game:GetService("ReplicatedStorage").Modules.Resources.Enums).PermissionLevel.Admin,

**ReplicatedStorage.CmdrClient.Commands.Perspective** (1):
- L14929: local var1 = require(game:GetService("ReplicatedStorage").Modules.Resources.Enums)

**ReplicatedStorage.CmdrClient.Types.CanUseCommands** (2):
- L15980: local var2 = require(var1.Modules.Resources.Enums)
- L15981: local var3 = require(var1.Modules.Permissions)

**ReplicatedStorage.CmdrClient.Types.CmdrTypeGlobal** (1):
- L16000: local var1 = require(game:GetService("ReplicatedStorage").Modules.Resources.Globals)

### D. ReplicatedStorage.Packages (_Index vendored libs: topbarplus, packetprofiler, roact-constant-fork, remotepacketsizecounter, goodsignal, janitor)

353 require sites in 103 scripts

**ReplicatedStorage.Packages.PacketProfiler** (1):
- L60620: return require(var1)

**ReplicatedStorage.Packages.TopbarPlus** (1):
- L60626: return require(var1)

**ReplicatedStorage.Packages._Index.1foreverhd_topbarplus@3.4.0.topbarplus** (17):
- L60631: require(script.Types)
- L60633: local var2 = require(var1.Reference)
- L60642: return (require(var4))
- L60649: local var9 = require(var1.Packages.GoodSignal)
- L60650: local var10 = require(var1.Packages.Janitor)
- L60651: local var11 = require(var1.Utility)
- L60652: local var12 = require(var1.Features.Themes)
- L60653: local var13 = require(var1.Features.Gamepad)
- L60654: local var14 = require(var1.Features.Overflow)
- L60660: tbl1.baseTheme = require(var1.Features.Themes.Default)
- L60666: local var17 = require(var16.Container)(tbl1)
- L60742: require(var1.Attribute)
- L60822: tbl4.widget = var2:add(require(var16.Widget)(var4, var6))
- L61299: local var1 = require(var16.Notice)(arg1, tbl1)
- L61611: local var3 = var1:add(require(var16.Caption)(var2))
- L61669: var2 = require(var16.Dropdown)(arg1)
- L61692: arg1.indicator = arg1.janitor:add(require(var16.Indicator)(var3, var4))

**ReplicatedStorage.Packages._Index.1foreverhd_topbarplus@3.4.0.topbarplus.Attribute** (1):
- L61853: local var1 = require(script.Parent.VERSION)

**ReplicatedStorage.Packages._Index.1foreverhd_topbarplus@3.4.0.topbarplus.Utility** (3):
- L62109: local var2 = require(script.Parent.Packages.Janitor)
- L62138: local var8 = require(arg1.iconModule)
- L62539: local var2 = require(arg1.iconModule).getIconByUID(arg1.parentIconUID)

**ReplicatedStorage.Packages._Index.1foreverhd_topbarplus@3.4.0.topbarplus.Elements.Caption** (1):
- L62885: local var40 = require(arg1.iconModule)

**ReplicatedStorage.Packages._Index.1foreverhd_topbarplus@3.4.0.topbarplus.Elements.Container** (2):
- L62954: local var5 = require(script.Parent.Parent.Packages.GoodSignal).new()
- L62984: arg1.modifyBaseTheme((require(script.Parent.Parent.Features.Themes.Classic)))

**ReplicatedStorage.Packages._Index.1foreverhd_topbarplus@3.4.0.topbarplus.Elements.Dropdown** (2):
- L63149: local var1 = require(script.Parent.Parent.Features.Themes)
- L63262: local var10 = require(arg1.iconModule)

**ReplicatedStorage.Packages._Index.1foreverhd_topbarplus@3.4.0.topbarplus.Elements.Menu** (2):
- L63651: local var2 = require(arg1.iconModule)
- L63664: local var5 = require(script.Parent.Parent.Features.Themes)

**ReplicatedStorage.Packages._Index.1foreverhd_topbarplus@3.4.0.topbarplus.Elements.Notice** (3):
- L63860: local var6 = require(var4.Utility)
- L63894: local var7 = require(var5.Janitor)
- L63895: local var8 = require(var5.GoodSignal)

**ReplicatedStorage.Packages._Index.1foreverhd_topbarplus@3.4.0.topbarplus.Elements.Widget** (3):
- L64031: local var5 = require(script.Parent.Menu)(arg1)
- L64062: require(script.Parent.Parent.Features.Gamepad).registerButton(var7)
- L64154: local var21 = require(script.Parent.Parent.Utility).createStagger(0.01, function(_)

**ReplicatedStorage.Packages._Index.1foreverhd_topbarplus@3.4.0.topbarplus.Features.Gamepad** (1):
- L64450: local var8 = require(script.Parent.Parent.Elements.Selection)

**ReplicatedStorage.Packages._Index.1foreverhd_topbarplus@3.4.0.topbarplus.Features.Overflow** (1):
- L64605: local var3 = require(script.Parent.Parent.Utility)

**ReplicatedStorage.Packages._Index.1foreverhd_topbarplus@3.4.0.topbarplus.Features.Themes** (3):
- L64945: local var1 = require(script.Parent.Parent.Utility)
- L64946: local var2 = require(script.Default)
- L65179: arg2 = require(arg2)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_packetprofiler@2.1.0.PacketSizeCounter** (1):
- L65784: return require(var1)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_packetprofiler@2.1.0.Roact** (1):
- L65790: return require(var1)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_packetprofiler@2.1.0.Signal** (1):
- L65796: return require(var1)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_packetprofiler@2.1.0.packetprofiler** (2):
- L65806: local var2 = require(require(script.Modules.Packages).Directory.Roact)
- L65807: var2.mount(var2.createElement((require(script.Components.MainPlugin))), var1.LocalPlayer.PlayerGui, "PacketProfiler")

**ReplicatedStorage.Packages._Index.pysephwasntavailable_packetprofiler@2.1.0.packetprofiler.Components.ChartResize** (2):
- L65813: local var1 = require(script.Parent.Parent.Modules.Packages)
- L65814: local var2 = require(var1.Directory.Roact)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_packetprofiler@2.1.0.packetprofiler.Components.MainPlugin** (5):
- L66015: local var2 = require(var1.Modules.Packages)
- L66016: local var3 = require(var2.Directory.Roact)
- L66018: local var4 = require(var2.Directory.Signal)
- L66114: local var2 = require(var8.PacketProfiler)
- L66120: local var6 = require(var8.PacketChart)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_packetprofiler@2.1.0.packetprofiler.Components.PacketChart** (14):
- L66147: local var3 = require(var2.Packages)
- L66152: local var10 = require(var3.Directory.Roact)
- L66153: local var11 = require(var3.Directory.Signal)
- L66154: local var12 = require(var3.Directory.PacketSizeCounter)
- L66155: local var13 = require(var4.StudioTheme)
- L66156: local var14 = require(var4.PacketCircleArcs)
- L66157: local var15 = require(var4.PacketChartItems)
- L66158: local var16 = require(var4.ChartResize)
- L66159: local var17 = require(var2.TableToSyntaxString)
- L66167: assert(typeof(require(var2)) == "function", "Return of RemoteName.profiler must be a function")
- L66168: var19 = require(arg1)
- L66175: assert(typeof(require(var21)) == "function", "Return of RemoteName.profiler must be a function")
- L66176: var19 = require(var9)
- L66277: local var1 = var3.IsPlugin and require(var4.StudioWidget) or "ScreenGui"

**ReplicatedStorage.Packages._Index.pysephwasntavailable_packetprofiler@2.1.0.packetprofiler.Components.PacketChartItems** (2):
- L66419: local var2 = require(require(var1.Modules.Packages).Directory.Roact)
- L66420: local var3 = require(var1.Components.StudioTheme)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_packetprofiler@2.1.0.packetprofiler.Components.PacketCircleArcs** (2):
- L66625: local var1 = require(script.Parent.Parent.Modules.Packages)
- L66626: local var2 = require(var1.Directory.Roact)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_packetprofiler@2.1.0.packetprofiler.Components.PacketFrame** (1):
- L66801: local var1 = require(require(script.Parent.Parent.Modules.Packages).Directory.Roact)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_packetprofiler@2.1.0.packetprofiler.Components.PacketFrames** (6):
- L66848: local var3 = require(var2.Packages)
- L66850: local var5 = require(var3.Directory.Roact)
- L66853: local var8 = require(var3.Directory.PacketSizeCounter)
- L66854: local var9 = require(var4.StudioTheme)
- L66855: local var10 = require(var2.CircularBuffer)
- L66856: local var11 = require(var4.PacketFrame)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_packetprofiler@2.1.0.packetprofiler.Components.PacketProfiler** (7):
- L67214: local var2 = require(var1.Modules.Packages)
- L67216: local var4 = require(var2.Directory.Roact)
- L67217: local var5 = require(var2.Directory.Signal)
- L67218: local var6 = require(var3.StudioTheme)
- L67219: local var7 = require(var3.PacketFrames)
- L67220: local var8 = require(var3.TopbarButtonsGroup)
- L67221: local var9 = require(var3.TopbarButton)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_packetprofiler@2.1.0.packetprofiler.Components.StudioSettings** (2):
- L67367: local var1 = require(script.Parent.Parent.Modules.Packages)
- L67368: local var3 = require(var1.Directory.Signal)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_packetprofiler@2.1.0.packetprofiler.Components.StudioTheme** (2):
- L67518: local var2 = require(require(var1.Modules.Packages).Directory.Roact)
- L67519: local var3 = require(var1.Components.StudioSettings)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_packetprofiler@2.1.0.packetprofiler.Components.StudioWidget** (1):
- L67548: local var2 = require(require(var1:FindFirstChildOfClass("Script").Modules.Packages).Directory.Roact)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_packetprofiler@2.1.0.packetprofiler.Components.TopbarButton** (1):
- L67591: local var1 = require(require(script.Parent.Parent.Modules.Packages).Directory.Roact)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_packetprofiler@2.1.0.packetprofiler.Components.TopbarButtonsGroup** (1):
- L67613: local var1 = require(require(script.Parent.Parent.Modules.Packages).Directory.Roact)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_packetprofiler@2.1.0.packetprofiler.Modules.TableToSyntaxString** (2):
- L67794: local var2 = require(require(var1.Modules.Packages).Directory.PacketSizeCounter)
- L67795: local var3 = require(var1.Components.StudioSettings)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork** (20):
- L68259: local var1 = require(script.createReconciler)((require(script.RobloxRenderer)))
- L68260: local var2 = require(script.GlobalConfig)
- L68261: local var3 = require(script.Binding)
- L68262: local var4 = require(script.createReconcilerCompat)(var1)
- L68263: local var5 = require(script.strict)
- L68264: local tbl1 = { Component = require(script.Component) }
- L68265: tbl1.createElement = require(script.createElement)
- L68266: tbl1.createFragment = require(script.createFragment)
- L68267: tbl1.oneChild = require(script.oneChild)
- L68268: tbl1.PureComponent = require(script.PureComponent)
- L68269: tbl1.None = require(script.None)
- L68270: tbl1.Portal = require(script.Portal)
- L68271: tbl1.createRef = require(script.createRef)
- L68272: tbl1.forwardRef = require(script.forwardRef)
- L68275: tbl1.createContext = require(script.createContext)
- L68276: tbl1.Change = require(script.PropMarkers.Change)
- L68277: tbl1.Children = require(script.PropMarkers.Children)
- L68278: tbl1.Event = require(script.PropMarkers.Event)
- L68279: tbl1.Constant = require(script.PropMarkers.Constant)
- L68280: tbl1.Ref = require(script.PropMarkers.Ref)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.Binding** (4):
- L68295: local var1 = require(script.Parent.createSignal)
- L68296: local var2 = require(script.Parent.Type)
- L68297: local var3 = require(script.Parent.GlobalConfig).get()
- L68298: local var4 = require(script.Parent.Symbol).named("BindingImpl")

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.Binding.spec** (4):
- L68441: local var1 = require(script.Parent.Binding)
- L68442: local var2 = require(script.Parent.Type)
- L68459: local var3 = require(script.Parent.createSpy)
- L68537: local var4 = require(script.Parent.GlobalConfig)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.Component** (7):
- L68636: local var1 = require(script.Parent.assign)
- L68637: local var2 = require(script.Parent.ComponentLifecyclePhase)
- L68638: local var3 = require(script.Parent.Type)
- L68639: local var4 = require(script.Parent.invalidSetStateMessages)
- L68640: local var5 = require(script.Parent.internalAssert)
- L68641: local var6 = require(script.Parent.GlobalConfig).get()
- L68642: local var7 = require(script.Parent.Symbol).named("InternalData")

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.ComponentLifecyclePhase** (2):
- L69003: local var1 = require(script.Parent.Symbol)
- L69004: local var2 = require(script.Parent.strict)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.Config.spec** (1):
- L69096: local var1 = require(script.Parent.Config)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.ElementKind** (3):
- L69133: local var1 = require(script.Parent.Symbol)
- L69134: local var2 = require(script.Parent.strict)
- L69135: local var3 = require(script.Parent.Portal)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.ElementKind.spec** (3):
- L69167: local var1 = require(script.Parent.ElementKind)
- L69189: local var2 = require(script.Parent.Component)
- L69190: local var3 = require(script.Parent.Portal)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.ElementUtils** (2):
- L69226: local var1 = require(script.Parent.Type)
- L69227: local tbl1 = { UseParentKey = require(script.Parent.Symbol).named("UseParentKey") }

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.ElementUtils.spec** (4):
- L69285: local var1 = require(script.Parent.createElement)
- L69286: local var2 = require(script.Parent.ElementUtils)
- L69287: local var3 = require(script.Parent.Type)
- L69331: local var4 = require(script.Parent.createFragment)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.GlobalConfig** (1):
- L69382: return require(script.Parent.Config).new()

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.GlobalConfig.spec** (1):
- L69388: local var1 = require(script.Parent.GlobalConfig)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.None** (1):
- L69514: return (require(script.Parent.Symbol).named("None"))

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.Portal** (1):
- L69535: return (require(script.Parent.Symbol).named("Portal"))

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.PureComponent** (1):
- L69540: local var1 = require(script.Parent.Component)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.PureComponent.spec** (3):
- L69577: local var1 = require(script.Parent.PureComponent)
- L69582: local var2 = require(script.Parent.createElement)
- L69583: local var3 = require(script.Parent.createReconciler)((require(script.Parent.NoopRenderer)))

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.RobloxRenderer** (10):
- L69630: local var1 = require(script.Parent.Type)
- L69631: local var2 = require(script.Parent.Binding)
- L69632: local var3 = require(script.Parent.getDefaultInstanceProperty)
- L69633: local var4 = require(script.Parent.PropMarkers.Constant)
- L69638: local var5 = require(script.Parent.PropMarkers.Ref)
- L69639: local var6 = require(script.Parent.PropMarkers.Children)
- L69640: local var7 = require(script.Parent.SingleEventManager)
- L69730: local var8 = require(script.Parent.ElementKind)
- L69731: local var9 = require(script.Parent.internalAssert)
- L69732: local var10 = require(script.Parent.GlobalConfig).get()

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.RobloxRenderer.spec** (14):
- L69885: local var1 = require(script.Parent.RobloxRenderer)
- L69886: local var2 = require(script.Parent.createElement)
- L69887: local var3 = require(script.Parent.createReconciler)(var1)
- L69888: local var4 = require(script.Parent.Binding)
- L69889: local var5 = require(script.Parent.createRef)
- L69890: local var6 = require(script.Parent.PropMarkers.Ref)
- L69891: local var7 = require(script.Parent.createSpy)
- L69892: local var8 = require(script.Parent.GlobalConfig)
- L70154: local var9 = require(script.Parent.Portal)
- L70224: local var10 = require(script.Parent.createFragment)
- L70300: local var11 = require(script.Parent.Component)
- L70301: local var12 = require(script.Parent.assertDeepEqual)
- L70302: local var13 = require(script.Parent.PropMarkers.Children)
- L70398: local var15 = require(script.Parent.PropMarkers.Event)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.SingleEventManager** (1):
- L70685: local var1 = require(script.Parent.Logging)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.SingleEventManager.spec** (4):
- L70784: local var1 = require(script.Parent.SingleEventManager)
- L70791: local var2 = require(script.Parent.createSpy)
- L70792: local var3 = require(script.Parent.assertDeepEqual)
- L70793: local var4 = require(script.Parent.Logging)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.Symbol.spec** (1):
- L70994: local var1 = require(script.Parent.Symbol)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.Type** (2):
- L71014: local var1 = require(script.Parent.Symbol)
- L71015: local var2 = require(script.Parent.strict)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.Type.spec** (1):
- L71046: local var1 = require(script.Parent.Type)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.assertDeepEqual.spec** (1):
- L71135: local var1 = require(script.Parent.assertDeepEqual)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.assign** (1):
- L71195: local var1 = require(script.Parent.None)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.assign.spec** (2):
- L71219: local var1 = require(script.Parent.assign)
- L71235: local var2 = require(script.Parent.None)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.createContext** (5):
- L71254: local var1 = require(script.Parent.createSignal)
- L71255: local var2 = require(script.Parent.Component)
- L71256: local var3 = require(script.Parent.createFragment)
- L71257: local var4 = require(script.Parent.PropMarkers.Children)
- L71258: local var5 = require(script.Parent.Symbol)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.createContext.spec** (9):
- L71356: local var1 = require(script.Parent.createReconciler)
- L71357: local var2 = require(script.Parent.createContext)
- L71370: local var3 = require(script.Parent.createSpy)
- L71371: local var4 = require(script.Parent.createElement)
- L71372: local var5 = var1((require(script.Parent.NoopRenderer)))
- L71386: local var6 = require(script.Parent.Component)
- L71387: local var7 = require(script.Parent.createFragment)
- L71388: local var8 = require(script.Parent.PropMarkers.Children)
- L71525: local var10 = var1((require(script.Parent.RobloxRenderer)))

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.createElement** (5):
- L71610: local var1 = require(script.Parent.GlobalConfig).get()
- L71611: local var2 = require(script.Parent.PropMarkers.Children)
- L71612: local var3 = require(script.Parent.Logging)
- L71613: local var4 = require(script.Parent.ElementKind)
- L71614: local var5 = require(script.Parent.Type)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.createElement.spec** (8):
- L71675: local var1 = require(script.Parent.createElement)
- L71676: local var2 = require(script.Parent.Type)
- L71677: local var3 = require(script.Parent.ElementKind)
- L71698: local var4 = require(script.Parent.Component)
- L71708: local var5 = require(script.Parent.Portal)
- L71724: local var6 = require(script.Parent.PropMarkers.Children)
- L71742: local var7 = require(script.Parent.Logging)
- L71757: local var8 = require(script.Parent.GlobalConfig)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.createFragment** (2):
- L71768: local var1 = require(script.Parent.Type)
- L71769: local var2 = require(script.Parent.ElementKind)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.createFragment.spec** (3):
- L71778: local var1 = require(script.Parent.createFragment)
- L71779: local var2 = require(script.Parent.Type)
- L71780: local var3 = require(script.Parent.ElementKind)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.createReconciler** (7):
- L71799: local var1 = require(script.Parent.GlobalConfig).get()
- L71800: local var2 = require(script.Parent.internalAssert)
- L71801: local var3 = require(script.Parent.Type)
- L71802: local var4 = require(script.Parent.ElementUtils)
- L71803: local var5 = require(script.Parent.ElementKind)
- L71804: local var6 = require(script.Parent.PropMarkers.Children)
- L71805: local var7 = require(script.Parent.Symbol).named("InternalData")

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.createReconciler.spec** (8):
- L72208: local var1 = require(script.Parent.createReconciler)
- L72209: local var2 = require(script.Parent.NoopRenderer)
- L72211: local var4 = require(script.Parent.createElement)
- L72279: local var5 = require(script.Parent.createSpy)
- L72280: local var6 = require(script.Parent.assign)
- L72281: local var7 = require(script.Parent.Type)
- L72324: local var8 = require(script.Parent.createFragment)
- L72406: local var9 = require(script.Parent.ElementKind)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.createReconcilerCompat** (1):
- L72441: local var1 = require(script.Parent.Logging)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.createReconcilerCompat.spec** (4):
- L72472: local var1 = require(script.Parent.createReconciler)((require(script.Parent.NoopRenderer)))
- L72473: local var2 = require(script.Parent.Logging)
- L72474: local var3 = require(script.Parent.createReconcilerCompat)(var1)
- L72475: local var4 = require(script.Parent.createElement)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.createRef** (1):
- L72549: local var1 = require(script.Parent.Binding)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.createRef.spec** (3):
- L72581: local var1 = require(script.Parent.createRef)
- L72582: local var2 = require(script.Parent.Type)
- L72590: local var3 = require(script.Parent.Binding)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.createSignal.spec** (2):
- L72675: local var1 = require(script.Parent.createSignal)
- L72676: local var2 = require(script.Parent.createSpy)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.createSpy** (1):
- L72771: local var1 = require(script.Parent.assertDeepEqual)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.createSpy.spec** (1):
- L72831: local var1 = require(script.Parent.createSpy)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.forwardRef** (4):
- L72927: local var1 = require(script.Parent.assign)
- L72928: local var2 = require(script.Parent.None)
- L72929: local var3 = require(script.Parent.PropMarkers.Ref)
- L72930: local var4 = require(script.Parent.GlobalConfig).get()

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.forwardRef.spec** (8):
- L72948: local var1 = require(script.Parent.createElement)
- L72949: local var2 = require(script.Parent.PropMarkers.Ref)
- L72950: local var3 = require(script.Parent.forwardRef)
- L72951: local var4 = require(script.Parent.assign)
- L72952: local var5 = require(script.Parent.createRef)
- L72953: local var6 = require(script.Parent.createReconciler)((require(script.Parent.RobloxRenderer)))
- L73043: local var7 = require(script.Parent.GlobalConfig)
- L73187: local var8 = require(script.Parent.Component)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.getDefaultInstanceProperty** (1):
- L73262: local var1 = require(script.Parent.Symbol).named("Nil")

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.getDefaultInstanceProperty.spec** (1):
- L73301: local var1 = require(script.Parent.getDefaultInstanceProperty)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.init.spec** (1):
- L73332: local var1 = require(script.Parent)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.invalidSetStateMessages** (1):
- L73399: local var1 = require(script.Parent.ComponentLifecyclePhase)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.oneChild.spec** (2):
- L73445: local var1 = require(script.Parent.oneChild)
- L73451: local var2 = require(script.Parent.createElement)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.strict.spec** (1):
- L73495: local var1 = require(script.Parent.strict)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.Component.spec.context.spec** (5):
- L73515: local var1 = require(script.Parent.Parent.Component)
- L73516: local var2 = require(script.Parent.Parent.createElement)
- L73517: local var3 = require(script.Parent.Parent.createReconciler)((require(script.Parent.Parent.NoopRenderer)))
- L73518: local var4 = require(script.Parent.Parent.assertDeepEqual)
- L73581: local var5 = require(script.Parent.Parent.oneChild)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.Component.spec.defaultProps.spec** (5):
- L73710: local var1 = require(script.Parent.Parent.Component)
- L73711: local var2 = require(script.Parent.Parent.createElement)
- L73712: local var3 = require(script.Parent.Parent.createReconciler)((require(script.Parent.Parent.NoopRenderer)))
- L73713: local var4 = require(script.Parent.Parent.assertDeepEqual)
- L73745: local var5 = require(script.Parent.Parent.None)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.Component.spec.didMount.spec** (5):
- L73765: local var1 = require(script.Parent.Parent.Component)
- L73766: local var2 = require(script.Parent.Parent.createSpy)
- L73767: local var3 = require(script.Parent.Parent.createElement)
- L73768: local var4 = require(script.Parent.Parent.createReconciler)((require(script.Parent.Parent.NoopRenderer)))
- L73769: local var5 = require(script.Parent.Parent.Type)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.Component.spec.didUpdate.spec** (6):
- L73789: local var1 = require(script.Parent.Parent.Component)
- L73790: local var2 = require(script.Parent.Parent.createSpy)
- L73791: local var3 = require(script.Parent.Parent.createElement)
- L73792: local var4 = require(script.Parent.Parent.createReconciler)((require(script.Parent.Parent.NoopRenderer)))
- L73793: local var5 = require(script.Parent.Parent.Type)
- L73794: local var6 = require(script.Parent.Parent.assertDeepEqual)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.Component.spec.extend.spec** (2):
- L73847: local var1 = require(script.Parent.Parent.Component)
- L73848: local var2 = require(script.Parent.Parent.Type)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.Component.spec.getDerivedStateFromProps.spec** (6):
- L73875: local var1 = require(script.Parent.Parent.createSpy)
- L73876: local var2 = require(script.Parent.Parent.Component)
- L73877: local var3 = require(script.Parent.Parent.createElement)
- L73878: local var4 = require(script.Parent.Parent.createReconciler)((require(script.Parent.Parent.NoopRenderer)))
- L73879: local var5 = require(script.Parent.Parent.assertDeepEqual)
- L73967: local var6 = require(script.Parent.Parent.createFragment)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.Component.spec.getElementTraceback.spec** (4):
- L74029: local var1 = require(script.Parent.Parent.Component)
- L74030: local var2 = require(script.Parent.Parent.GlobalConfig)
- L74031: local var3 = require(script.Parent.Parent.createElement)
- L74032: local var4 = require(script.Parent.Parent.createReconciler)((require(script.Parent.Parent.NoopRenderer)))

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.Component.spec.init.spec** (6):
- L74077: local var1 = require(script.Parent.Parent.Component)
- L74078: local var2 = require(script.Parent.Parent.createSpy)
- L74079: local var3 = require(script.Parent.Parent.createElement)
- L74080: local var4 = require(script.Parent.Parent.createReconciler)((require(script.Parent.Parent.NoopRenderer)))
- L74081: local var5 = require(script.Parent.Parent.Type)
- L74082: local var6 = require(script.Parent.Parent.assertDeepEqual)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.Component.spec.legacyContext.spec** (4):
- L74106: local var1 = require(script.Parent.Parent.Component)
- L74107: local var2 = require(script.Parent.Parent.createElement)
- L74108: local var3 = require(script.Parent.Parent.createReconciler)((require(script.Parent.Parent.NoopRenderer)))
- L74109: local var4 = require(script.Parent.Parent.assertDeepEqual)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.Component.spec.render.spec** (6):
- L74245: local var1 = require(script.Parent.Parent.Component)
- L74246: local var2 = require(script.Parent.Parent.createElement)
- L74247: local var3 = require(script.Parent.Parent.createReconciler)((require(script.Parent.Parent.NoopRenderer)))
- L74261: local var4 = require(script.Parent.Parent.createSpy)
- L74262: local var5 = require(script.Parent.Parent.Type)
- L74263: local var6 = require(script.Parent.Parent.assertDeepEqual)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.Component.spec.setState.spec** (5):
- L74354: local var1 = require(script.Parent.Parent.Component)
- L74355: local var2 = require(script.Parent.Parent.createElement)
- L74356: local var3 = require(script.Parent.Parent.createReconciler)((require(script.Parent.Parent.NoopRenderer)))
- L74357: local var4 = require(script.Parent.Parent.None)
- L74541: local var5 = require(script.Parent.Parent.createSpy)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.Component.spec.shouldUpdate.spec** (6):
- L74808: local var1 = require(script.Parent.Parent.Component)
- L74809: local var2 = require(script.Parent.Parent.createSpy)
- L74810: local var3 = require(script.Parent.Parent.createElement)
- L74811: local var4 = require(script.Parent.Parent.createReconciler)((require(script.Parent.Parent.NoopRenderer)))
- L74812: local var5 = require(script.Parent.Parent.Type)
- L74813: local var6 = require(script.Parent.Parent.assertDeepEqual)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.Component.spec.validateProps.spec** (5):
- L74916: local var1 = require(script.Parent.Parent.GlobalConfig)
- L74917: local var2 = require(script.Parent.Parent.Component)
- L74918: local var3 = require(script.Parent.Parent.createSpy)
- L74919: local var4 = require(script.Parent.Parent.createElement)
- L74920: local var5 = require(script.Parent.Parent.createReconciler)((require(script.Parent.Parent.NoopRenderer)))

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.Component.spec.willUnmount.spec** (5):
- L75083: local var1 = require(script.Parent.Parent.Component)
- L75084: local var2 = require(script.Parent.Parent.createSpy)
- L75085: local var3 = require(script.Parent.Parent.createElement)
- L75086: local var4 = require(script.Parent.Parent.createReconciler)((require(script.Parent.Parent.NoopRenderer)))
- L75087: local var5 = require(script.Parent.Parent.Type)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.Component.spec.willUpdate.spec** (6):
- L75107: local var1 = require(script.Parent.Parent.Component)
- L75108: local var2 = require(script.Parent.Parent.createSpy)
- L75109: local var3 = require(script.Parent.Parent.createElement)
- L75110: local var4 = require(script.Parent.Parent.createReconciler)((require(script.Parent.Parent.NoopRenderer)))
- L75111: local var5 = require(script.Parent.Parent.Type)
- L75112: local var6 = require(script.Parent.Parent.assertDeepEqual)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.PropMarkers.Change** (1):
- L75163: local var1 = require(script.Parent.Parent.Type)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.PropMarkers.Change.spec** (2):
- L75183: local var1 = require(script.Parent.Parent.Type)
- L75184: local var2 = require(script.Parent.Change)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.PropMarkers.Children** (1):
- L75202: return (require(script.Parent.Parent.Symbol).named("Children"))

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.PropMarkers.Constant** (1):
- L75207: return { SkipBindingUpdate = require(script.Parent.Parent.Symbol).named("SkipBindingUpdate") }

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.PropMarkers.Event** (1):
- L75212: local var1 = require(script.Parent.Parent.Type)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.PropMarkers.Event.spec** (2):
- L75232: local var1 = require(script.Parent.Parent.Type)
- L75233: local var2 = require(script.Parent.Event)

**ReplicatedStorage.Packages._Index.pysephwasntavailable_roact-constant-fork@1.5.0.roact-constant-fork.PropMarkers.Ref** (1):
- L75251: return (require(script.Parent.Parent.Symbol).named("Ref"))
---

# 2. NETWORK MODULE — `ReplicatedStorage.ModifiedPackages.Packet`

## 2.1 Identity & full line ranges

| Module | Deobf lines | Role |
|---|---|---|
| **`ReplicatedStorage.ModifiedPackages.Packet`** | **L48929–L49452** | the network module (wire protocol, Fire/Receive, RemoteEvent owner) |
| `…Packet._Signal` | L49454–L49529 | linked-list Signal used for `OnServerEvent`/`OnClientEvent` |
| `…Packet._Task` | L49531–L49563 | task pool wrapper (Spawn/Defer/Delay) |
| `…Packet._Types` | L49565–L52479 | **the buffer codec** (Reads/Writes per type + dynamic `Any` ids) |
| `…Packet._Types._Characters` | L52481–L52549 | base64-ish char table (used by string packing) |
| `…Packet._Types._Enums` | L52551–L52564 | Enum registry for `EnumItem` dynamic type (AccessoryType, Axis, BodyPart, BodyPartR15, EasingDirection, EasingStyle, KeyCode, Material, NormalId) |
| `…Packet._Types._Static1/2/3` | L52566–L52601 | static value tables (dedup of common literals; only placeholder values visible in deobf) |

The game-side **packet registry** lives in `ReplicatedStorage.Modules.Resources.Packets` (L44290–L44422) — see §2.3.

## 2.2 How the RemoteEvent is resolved

* The RemoteEvent is **a child of the Packet module script itself**: `ReplicatedStorage.ModifiedPackages.Packet.RemoteEvent`.
* **Client side** (L49282–L49283):
```lua
L49282  else            -- (i.e. NOT var7:IsServer())
L49283          var9 = script:WaitForChild("RemoteEvent")
```
* **Server side** creates it (L49142–L49143):
```lua
L49142  if var7:IsServer() then
L49143          var9 = Instance.new("RemoteEvent", script)
```
* **Packet-id registry = attributes on that RemoteEvent instance.** Server assigns each named packet a u8 id and publishes it as an attribute whose **name is the packet name** and whose value is the id (L49120–L49133, in the shared Constructor):
```lua
L49120          if var7:IsServer() then
L49121                  var3.Id = var8
L49122                  var3.OnServerEvent = var4()       -- _Signal
L49123                  var9:SetAttribute(arg2, var8)     -- arg2 = packet NAME -> attr value = numeric id
L49124                  tbl2[var8] = var3
L49125                  local var5 = var8 + 1
L49126                  var8 = var5
L49127          else
L49128                  var3.Id = var9:GetAttribute(arg2)  -- client reads id by packet name
L49129                  var3.OnClientEvent = var4()
L49130                  if var3.Id then
L49131                          tbl2[var3.Id] = var3
L49132                  end
L49133          end
```
  Client also **live-updates** ids when the server sets an attribute later (late-registered packets) (L49335–L49347):
```lua
L49335          var9.AttributeChanged:Connect(function(arg1)
L49336                  local var2 = tbl2[arg1]              -- tbl2[name] -> packet object
L49337                  if var2 then
L49338                          if var2.Id then
L49339                                  tbl2[var2.Id] = nil
L49340                          end
L49342                          var2.Id = var9:GetAttribute(arg1)
L49343                          if var2.Id then
L49344                                  tbl2[var2.Id] = var2
L49345                          end
L49346                  end
L49347          end)
```
  ⇒ **Harness:** the mock RemoteEvent must expose `GetAttribute`/`AttributeChanged` with one attribute per registered packet name (value = its dispatch id), e.g. `PotatoPick = <id>`.

## 2.3 Packet construction & the game packet registry (the "dispatch table")

The module returns `setmetatable(var1.Types, { __call = Constructor })` (L49452) — i.e. **the exported object is the type-name table, callable as `Packet(name, type1, type2, …)`** which returns a memoized packet object (`tbl2[arg2]` lookup, L49113–L49116). Packet object surface:

* Fields: `.Name` (L49119), `.Id` (L49121/L49128), `.Reads` (L49136 — array of read closures), `.Writes` (L49137 — array of write closures), `.ResponseReads`/`.ResponseWrites` (L48952–L48953), `.OnServerEvent` (L49122, server), `.OnClientEvent` (L49129, client), `.ResponseTimeout` (default 10, L48949), `.ResponseTimeoutValue`.
* Methods: `:Response(...)` (L48948–L48955 — declares reply type, makes Fire yield), `:Fire(...)` (L48963–L49000), `:FireClient(player, ...)` (L49004–L49065, server), `:Serialize(...)` (L49068–L49074), `:Deserialize(buffer, instances)` (L49077–L49084).

The **game's packet registry** — every packet the game defines, with exact wire types — is `ReplicatedStorage.Modules.Resources.Packets` (L44290–L44422), verbatim (this IS the opcode table; ids are assigned by server-side registration order, persisted as RemoteEvent attributes):

```lua
L44293  local var1 = game:GetService("ReplicatedStorage")
L44294  require(var1.Shared.AudioShared)          -- side-effect requires (register their own packets)
L44295  require(var1.Shared.LeaderboardShared)
L44296  require(var1.Shared.NotificationShared)
L44297  require(var1.Shared.RunReportShared)
L44298  require(var1.Shared.StatsShared)
L44299  local var2 = require(var1.ModifiedPackages.Packet)
L44302  local tbl1 = { PlayerStateCreated = var2("PlayerStateCreated", var2.Any) }
L44303  tbl1.UpdatePlayerState = var2("UpdatePlayerState", var2.Any, var2.NumberU8)
L44304  tbl1.Sync = var2("Sync")
L44305  tbl1.PlayerSynced = var2("PlayerSynced")
L44306  tbl1.GlobalOverridesSynced = var2("GlobalOverridesSynced", var2.Any)
L44307  tbl1.SetGlobalOverride = var2("SetGlobalOverride", var2.String, var2.Any)
L44308  tbl1.ResetGlobalOverride = var2("ResetGlobalOverride", var2.String)
L44310  tbl1.RagdollSetEnabled = var2("RagdollSetEnabled", var5)              -- var5 = Boolean8
L44312  tbl1.RagdollOtherPlayerSetEnabled = var2("RagdollOtherPlayerSetEnabled", var6, var5)  -- var6 = NumberF64
L44314  tbl1.SoundPlayed = var2("SoundPlayed", var7, var2.Any)                -- var7 = String
L44315  tbl1.SoundStopped = var2("SoundStopped", var7)
L44316  tbl1.NotificationCreated = var2("NotificationCreated", var2.Any)
L44318  tbl1.PurchaseProduct = var2("PurchaseProduct", var8, var2.Any)        -- var8 = String
L44319  tbl1.ProductAdminPurchasePrompted = var2("ProductAdminPurchasePrompted", var8)
L44320  tbl1.ProductAdminPurchaseAccept = var2("ProductAdminPurchaseAccept")
L44321  tbl1.PurchaseCelebrated = var2("PurchaseCelebrated", var8)
L44322  tbl1.CameraPerspectiveToggled = var2("CameraPerspectiveToggled")
L44324  tbl1.QuestCreated = var2("QuestCreated", var9, var2.String, var2.String, { var2.String })
L44325  tbl1.QuestTaskSetCompleted = var2("QuestTaskSetCompleted", var9, var2.NumberU8, var2.Boolean8)
L44326  tbl1.QuestRemoved = var2("QuestRemoved", var9)
L44327  tbl1.CinematicBarsEnabled = var2("CinematicBarsEnabled")
L44328  tbl1.CinematicBarsDisabled = var2("CinematicBarsDisabled")
L44330  tbl1.ArrowCreateStatic = var2("ArrowCreateStatic", var10, { CFrame = var2.Any, Offset = var2.Any, Scale = var2.Any })
L44331  tbl1.ArrowRemoveStatic = var2("ArrowRemoveStatic", var10)
L44332  tbl1.ArrowCreateDirection = var2("ArrowCreateDirection", var10, var2.Vector3F24)
L44333  tbl1.ArrowRemoveDirection = var2("ArrowRemoveDirection", var10)
L44334  tbl1.CutsceneCameraOrbit = var2("CutsceneCameraOrbit", var2.Any)
L44335  tbl1.CutsceneCameraReset = var2("CutsceneCameraReset", var2.Any)
L44336  tbl1.QueueJoined = var2("QueueJoined", var2.Boolean8, var2.String)
L44337  tbl1.QueueLeft = var2("QueueLeft")
L44338  tbl1.QueueTeleporting = var2("QueueTeleporting")
L44339  tbl1.QueueCreate = var2("QueueCreate", var2.NumberU8, var2.Boolean8, var2.Boolean8)
L44340  tbl1.QueueLeave = var2("QueueLeave")
L44342  tbl1.PotatoPileSynced = var2("PotatoPileSynced", var2.NumberU32, { var11 }, var11)   -- var11 = NumberU32
L44343  tbl1.PotatoKeyMoved = var2("PotatoKeyMoved", var11)
L44344  tbl1.PotatoRemoved = var2("PotatoRemoved", var11)
L44345  tbl1.PotatoPileRequest = var2("PotatoPileRequest")
L44346  tbl1.PotatoPick = var2("PotatoPick", var11)
L44348  tbl1.PotatoesPicked = var2("PotatoesPicked", var6, { var11 }, var12)   -- (userId F64, {potatoIds U32}, toolName String)
L44350  tbl1.BagChanged = var2("BagChanged", { var13 })                        -- var13 = NumberU8
L44351  tbl1.ToolPurchase = var2("ToolPurchase", var12)
L44352  tbl1.ToolEquip = var2("ToolEquip", var12)
L44353  tbl1.ToolUsing = var2("ToolUsing", var5)                               -- Boolean8
L44354  tbl1.ToolSwing = var2("ToolSwing")
L44355  tbl1.ToolUpgradePurchase = var2("ToolUpgradePurchase", var12, var2.String)
L44356  tbl1.ClassRoll = var2("ClassRoll")
L44357  tbl1.ClassStopAt = var2("ClassStopAt", var2.String)
L44358  tbl1.ClassSlotSelect = var2("ClassSlotSelect", var2.NumberU8)
L44359  tbl1.ClassRolling = var2("ClassRolling", var2.String)
L44360  tbl1.ClassRollDenied = var2("ClassRollDenied")
L44362  tbl1.PotatoTablePlaced = var2("PotatoTablePlaced", var6, var14)        -- var14 = NumberU16
L44364  tbl1.PotatoesSold = var2("PotatoesSold", var14, var15)                -- var15 = NumberF64
L44365  tbl1.PeelPaid = var2("PeelPaid", var14, var15, var13)
L44366  tbl1.MachinePaid = var2("MachinePaid", var2.Instance, var14, var15, var13)
L44368  tbl1.PeelingStarted = var2("PeelingStarted", var2.Instance, { var13 }, var16)   -- (table Instance, {kinds U8}, toolName String)
L44369  tbl1.PeelingNextPotato = var2("PeelingNextPotato", { var13 }, var16)
L44370  tbl1.PeelingStopped = var2("PeelingStopped")
L44371  tbl1.PeelingFinished = var2("PeelingFinished")
L44372  tbl1.PeelingCancel = var2("PeelingCancel")
L44374  tbl1.PeelingSync = var2("PeelingSync", var17)                         -- var17 = Any (CFrame)
L44377  tbl1.PeelingPeelRemoved = var2("PeelingPeelRemoved", var18, var19)    -- var18 = NumberU8, var19 = Vector3F24
L44379  tbl1.PeelingSpectateStarted = var2("PeelingSpectateStarted", var6, var2.Instance, var13, var20)
L44380  tbl1.PeelingSpectateNext = var2("PeelingSpectateNext", var6, var13, var16)
L44381  tbl1.PeelingSpectateStopped = var2("PeelingSpectateStopped", var6)
L44382  tbl1.PeelingSpectateSync = var2("PeelingSpectateSync", var6, var17)
L44383  tbl1.PeelingSpectatePeel = var2("PeelingSpectatePeel", var6, var18, var19)
L44384  tbl1.PeelRateChanged = var2("PeelRateChanged", var6, var2.Instance, var2.NumberF32)
L44385  tbl1.PeelRateStopped = var2("PeelRateStopped", var6)
L44386  tbl1.TutorialUpgradesOpened = var2("TutorialUpgradesOpened")
L44387  tbl1.TutorialHandSelected = var2("TutorialHandSelected")
L44388  tbl1.TutorialCompleted = var2("TutorialCompleted", var2.NumberU32)
L44390  tbl1.TutorialStack = var2("TutorialStack", var21, var21)              -- var21 = StringLong, StringLong
L44391  tbl1.LobbyTutorialFinished = var2("LobbyTutorialFinished")
L44392  tbl1.GroupRewardClaim = var2("GroupRewardClaim", var2.String)
L44393  tbl1.GroupRewardLikeResult = var2("GroupRewardLikeResult", var2.Boolean8)
L44394  tbl1.LobbyGuideRequest = var2("LobbyGuideRequest")
L44395  tbl1.LobbyGuideSteps = var2("LobbyGuideSteps", var2.Boolean8, var2.Boolean8)
L44396  tbl1.IntroCutscenePlay = var2("IntroCutscenePlay", var2.Any, var2.Boolean8)
L44397  tbl1.IntroCutsceneFinished = var2("IntroCutsceneFinished")
L44398  tbl1.ItemUnlocked = var2("ItemUnlocked", var2.String, var2.String, var2.String)
L44399  tbl1.MachineRevealed = var2("MachineRevealed")
L44400  tbl1.RunReportRequest = var2("RunReportRequest")
L44401  tbl1.RunReportShown = var2("RunReportShown", var2.Any)
L44403  tbl1.KeyRevealed = var2("KeyRevealed", var2.Vector3F24, var6, var22)  -- var22 = NumberF32
L44404  tbl1.Escaped = var2("Escaped")
L44405  tbl1.EscapeFailed = var2("EscapeFailed")
L44406  tbl1.StatsRequest = var2("StatsRequest", var6)
L44407  tbl1.StatsShown = var2("StatsShown", var6, var2.Any)
L44408  tbl1.DailyRewardClaim = var2("DailyRewardClaim")
L44409  tbl1.LeaderboardRequest = var2("LeaderboardRequest")
L44410  tbl1.LeaderboardUpdated = var2("LeaderboardUpdated", var2.String, var2.Any)
L44411  tbl1.LobbyUpgradePurchase = var2("LobbyUpgradePurchase", var2.String)
L44412  if var3 then   -- server-only duplicate-name validation
L44421  table.freeze(tbl1)
L44422  return tbl1
```

⇒ **~90 packets.** Gameplay-critical ones for the harness: `Sync`/`PlayerSynced` (handshake), `PlayerStateCreated`/`UpdatePlayerState` (state), `PotatoPileRequest`/`PotatoPileSynced`/`PotatoPick`/`PotatoesPicked`/`PotatoRemoved`/`PotatoKeyMoved` (pile), `PeelingStarted`/`PeelingNextPotato`/`PeelingStopped`/`PeelingPeelRemoved`/`PeelingSync`/`PeelingCancel`/`PeelingFinished` (peel minigame), `PotatoesSold`/`PeelPaid`/`MachinePaid` (economy), `ToolEquip`/`ToolUsing`/`ToolSwing` (tools), `BagChanged` (bag), `KeyRevealed`/`Escaped`/`EscapeFailed` (win flow).

## 2.4 Send path — Fire + the streaming fire loop

`Packet:Fire(...)` (client, L48963–L49000) appends to a **single global outbound stream** `tbl1` (module-level, L48939–L48940):
```lua
L48939  local tbl1 = { Buffer = buffer.create(128), BufferLength = 128, BufferOffset = 0, InstancesOffset = 0 }
L48940  tbl1.Instances = {}
```
Non-response Fire (L48996–L48999):
```lua
L48996          var12(tbl1)          -- _Types.Import(stream)  (binds module cursor vars)
L48997          var13(arg1.Id)       -- var13 = Writes.NumberU8 : writes packet id
L48998          var15(arg1.Writes, { ... })  -- writes each field via its Writes closure
L48999          tbl1 = var16()       -- var16 = _Types.Export() (returns stream, updates offsets)
```
So the wire stream is `[u8 packetId][field bytes…]` **concatenated for all packets fired since the last flush**; growth auto-doubles the backing buffer (see §2.7 write closures).

**The ONLY `FireServer` call sites in the entire deobf** are in the client flush loop (L49349–L49369), verbatim:
```lua
L49349          local num1 = 0
L49350          local var29 = task.spawn(function()
L49351                  while true do
L49352                          coroutine.yield()
L49353                          if 0 >= tbl1.BufferOffset then
L49354                                  continue
L49355                          end
L49356
L49357                          local var1 = buffer.create(tbl1.BufferOffset)
L49358                          buffer.copy(var1, 0, tbl1.Buffer, 0, tbl1.BufferOffset)
L49359                          if tbl1.InstancesOffset == 0 then
L49360                                  var9:FireServer(var1)                 -- ONE arg: the buffer
L49361                          else
L49362                                  var9:FireServer(var1, tbl1.Instances) -- TWO args: buffer + Instances array
L49363                                  tbl1.InstancesOffset = 0
L49364                                  table.clear(tbl1.Instances)
L49365                          end
L49366
L49367                          tbl1.BufferOffset = 0
L49368                  end
L49369          end)
L49371          var7.Heartbeat:Connect(function(arg1)      -- var7 = RunService
L49372                  local var1 = num1 + arg1
L49373                  num1 = var1
L49374                  if 0.016666666666666666 < num1 then   -- rate-limit: flush at most ~60 Hz
L49375                          var1 = num1 % 0.016666666666666666
L49376                          num1 = var1
L49377                          task.defer(var29)
L49378                  end
L49379          end)
```
⇒ **Argument shapes:** `RemoteEvent:FireServer(buffer)` (no instances packed) or `RemoteEvent:FireServer(buffer, instancesArray)` (when ≥1 `Instance`-typed field was written — instances are replicated by reference in the 2nd arg; see §2.7). The send trigger is *nothing but time*: any `Fire()` just queues bytes; the heartbeat accumulator drains the queue every ≥1/60 s.

## 2.5 Receive path — dispatch loop

Client connects once to the RemoteEvent (L49297–L49333), verbatim (this is the deserializer + dispatcher):
```lua
L49297          var11 = { Index = 0 }                      -- response yield-slot ring buffer
L49298          var9.OnClientEvent:Connect(function(arg1, arg2)
L49299                  local var1 = arg2                   -- arg2 = Instances array (or nil)
L49300                  local tbl1 = { Buffer = arg1, BufferLength = buffer.len(arg1), BufferOffset = 0, InstancesOffset = 0 }
L49301                  tbl1.Instances = var1 or {}
L49302                  var12(tbl1)                         -- Import
L49303                  while true do
L49304                          if var26() ~= false then    -- var26 = _Types.Ended(): stop when stream consumed
L49305                                  break
L49306                          end
L49307
L49308                          local var2 = tbl2[var27()]   -- var27 = Reads.NumberU8 -> read packet ID, look up packet by id
L49309                          if var2.ResponseReads then   -- it's a REPLY to a yielded Fire
L49310                                  tbl1 = var27()       -- read response slot index (u8)
L49311                                  if tbl1 < 128 then
L49312                                          local var6 = var2.Reads
L49313                                          var5:Defer(fn7, var2, tbl1, var20(var6))  -- server->client invoke
L49314                                  else
L49315                                          tbl1 = tbl1 - 128
L49316                                          var1 = var11[tbl1]
L49317                                          if var1 then
L49318                                                  task.cancel(var1.Timeout)
L49319                                                  local var7 = var2.ResponseReads
L49320                                                  task.defer(var1.Yielded, var20(var7))  -- resume yielding Fire()
L49321                                                  var11[tbl1] = nil
L49322                                          else
L49323                                                  local var8 = var2.ResponseReads
L49324                                                  warn("Response thread not found for packet:", var2.Name, "discarding response:", var20(var8))
L49325                                                  continue
L49326                                          end
L49327                                  end
L49328                          else
L49329                                  local var9 = var2.Reads
L49330                                  var2.OnClientEvent:Fire(var20(var9))   -- dispatch to listeners
L49331                          end
L49332                  end
L49333          end)
```
* `var20` = parameter reader (L49089–L49099): calls each `Reads[i]()` closure in order, returns `table.unpack(values)`.
* Dispatch is **id → packet object → packet.OnClientEvent signal**, where handlers were registered game-side via `X.OnClientEvent:Connect(fn)` (full list in §2.10). Not a numeric switch — the "opcode table" is `tbl2[id]`, populated from the RemoteEvent attributes (§2.2).
* Server mirror (for completeness): `var9.OnServerEvent:Connect` L49227–L49232 wraps `fn9` (L49176–L49225) which rate-limits 8000 bytes/player (L49177–L49184), decodes the same way and fires `var4.OnServerEvent:Fire(arg1, ...)` (L49222); server replies use `var13(var3 + 128)` (L49170) and `var13(arg2 + 128)` client-side (L49292) — the +128 flag distinguishes *response* frames from *request* frames.

## 2.6 Response (yield) protocol

* `Packet:Response(...)` (L48948–L48955) sets `ResponseReads/ResponseWrites` and default `ResponseTimeout = 10` (s).
* A Fire on a response-capable packet (L48964–L48993) finds a free slot in the 128-entry ring `var11` (L49297), writes `[u8 id][u8 slot]` (L48985–L48986), stores `{ Yielded = coroutine.running(), Timeout = var5:Delay(...) }` (L48987–L48989), then `coroutine.yield()` (L48993). Receive path resumes it (L49318–L49321); timeouts are handled by `var14` (assignment masked in deobf — see §2.11).
* Max 128 concurrent yielded threads per direction (errors at L48981, L49029).

## 2.7 Buffer packing primitives — `Packet._Types` (the real wire codec)

Module state (module-level cursors, L49568–49575 + L52449–L52479): `var1 = BufferOffset`, `var2 = BufferLength`, `var3 = Buffer`, `var4 = stream table`, `var5 = InstancesOffset`, `var6 = Instances`. Export surface (verbatim, L52449–L52479):
```lua
L52449  return {
L52450          Import = function(arg1)      -- bind stream {Buffer, BufferLength, BufferOffset, Instances, InstancesOffset}
L52451                  var4 = arg1
L52452                  var3 = arg1.Buffer
L52453                  var2 = arg1.BufferLength
L52454                  var1 = arg1.BufferOffset
L52455                  var6 = arg1.Instances
L52456                  var5 = arg1.InstancesOffset
L52457          end,
L52458          Export = function()
L52459                  var4.BufferLength = var2
L52460                  var4.BufferOffset = var1
L52461                  var4.InstancesOffset = var5
L52462                  return var4
L52463          end,
L52464          Truncate = function()          -- finalize: returns (buffer) or (buffer, instances)
L52465                  local var2 = buffer.create(var1)
L52466                  buffer.copy(var2, 0, var3, 0, var1)
L52467                  if var5 == 0 then
L52468                          return var2
L52469                  end
L52470
L52471                  return var2, var6
L52472          end,
L52473          Ended = function()             -- true when cursor >= length
L52474                  return var2 <= var1
L52475          end,
L52476          Types = tbl3,   -- { Any="Any", Nil=…, NumberS8…NumberF64, String, StringLong, StringLongest, Buffer, BufferLong, Instance, Boolean8, NumberRange, BrickColor, Color3, UDim, UDim2, Rect, Vector2S16/F24/F32, Vector3S16/F24/F32, NumberU4, BooleanNumber, Boolean1, CFrameF24U8/F32U8/F32U16, Region3, NumberSequence, ColorSequence } (L49709–L49752)
L52477          Reads = tbl4,
L52478          Writes = tbl5,
L52479  }
```

**Reads (tbl4)** — signatures + lines (all take no args, read at cursor `var1`, advance, return value):
| Type | Wire format | Read fn line |
|---|---|---|
| NumberS8 / S16 / S24 / S32 | readi8 / readi16 / readbits(24)-8388608 / readi32 | L49764 / L49770 / L49776 / L49782 |
| NumberU8 / U16 / U24 / U32 | readu8 / readu16 / readbits(24) / readu32 | L49788 / L49794 / L49800 / L49806 |
| NumberF16 / F24 | custom bit-packed half floats (ReadF16 L49576, ReadF24 L49642) | L49812 / L49815 |
| NumberF32 / F64 | readf32 / readf64 | L49818 / L49824 |
| String | u8 len + bytes | L49830 |
| StringLong | u16 len + bytes | L49839 |
| StringLongest | u32 len + bytes | L49848 |
| Buffer | u8 len + copy | L49857 |
| BufferLong | u16 len + copy | L49867 |
| **Instance** | **no bytes — pops `Instances[var5+1]`** (side table, positional) | L49877–L49881 |
| Boolean8 | u8 == 1 | L49882 |
| NumberRange / BrickColor / Color3 | f32×2 / u16 / u8×3 | L49888 / L49897 / L49903 |
| UDim / UDim2 / Rect | i16÷1000 pairs / ×4 / f32×4 | L49915 / L49925 / L49942 |
| Vector2S16 / Vector2F24 / Vector2F32 | i16×2 / F24×2 / f32×2 | L49957 / L49966 / L49971 |
| Vector3S16 / Vector3F24 / Vector3F32 | i16×3 / F24×3 / f32×3 | L49980 / (≈L49986) / (≈L49992) |
| Any | u8 dynamic type id → dispatch `tbl1[id]()` | L49755–L49760 |

**Writes (tbl5)** — same shapes; each write grows the buffer (double `var2`, copy) before writing (e.g. NumberU8 write L50254–L50270; String L50394–L50414; Boolean8 L50509–L50525). Key entries: Any L50177 (dispatch `tbl2[typeof(v)]`), NumberU8 L50254, NumberU16 L50272, NumberU24 L50290, NumberU32 L50308, NumberF32 L50358, NumberF64 L50376, String L50394, StringLong L50416, StringLongest L50438, Buffer L50460, BufferLong L50482, **Instance L50504–L50507 (no bytes — `var6[var5+1] = instance`, i.e. appends to the Instances side table — this is what triggers the 2-arg FireServer)**, Boolean8 L50509.

**Dynamic `Any` type-id table** (`tbl1[id]` readers at L51286–L52403, writers `tbl2[typeof(v)]` interleaved):
| id | type | id | type |
|---|---|---|---|
| 0 | nil | 15 | NumberRange (f32,f32) |
| 1–4 | −u8, −u16, −u24, −u32 | 16 | BrickColor (u16) |
| 5–8 | u8, u16, u24, u32 | 17 | Color3 (u8,u8,u8) |
| 9 | f32 | 18 | UDim |
| 10 | f64 | 19 | UDim2 |
| 11 | String (u8 len) | 20 | Rect (f32×4) |
| 12 | Buffer (u8 len) | 21 | Vector2 (f32,f32) |
| **13** | **Instance (side table, no bytes)** | 22 | Vector3 (f32×3) |
| 14 | boolean (u8) | 23 | CFrame (u16 angles ×3 + f32 pos ×3, L52099) |
| | | 24 | CFrame quaternion (f32×7, L52162) |
| | | 25 / 26 | NumberSequence / ColorSequence |
| | | 27 | EnumItem (u8 enum index + u16 value, registry = `_Enums` L52551) |
| | | 28 | table — pairs of (typed key, typed value) with type ids, terminated by `0` (read L52388–L52403; write `tbl2.table` L52406–L52447) |

* `Any`-typed numbers pick the smallest fitting int representation (writer `tbl2.number` L51379+, e.g. id 1 with `-value` at L51396–L51401).
* Array types in packet definitions (`{ var2.NumberU8 }`) compile to `u16 count + elements` (compiler `var21` at L49383–L41450: length prefix `var23(#arg1)` = Writes.NumberU16 at L49399, elements at L49401). Table types (`{ CFrame = var2.Any, … }`) compile keys **sorted alphabetically** (L49423) and write only the values (L49445–L49449).

## 2.8 `ReplicatedStorage.Modules.Buffer` (L41324–L41463) — the *other* buffer module

A standalone OO wrapper (`Buffer.New(size)` → object with `_buffer`/`_cursor`, L41330–L41333). **The require map shows no game consumer** (`Modules.Buffer` appears only as its own header, L41324) — the live wire code uses `_Types` (§2.7) and raw `buffer.*` (§2.9). Export surface (all methods take `self`; chained):
| Function | Line | Format |
|---|---|---|
| `New(size)` | L41330 | `buffer.create(size)` |
| `GetBuffer()` | L41335 | |
| `ToBase64()` / `FromBase64()` | L41339 / L41344 | (misnomers — actually JSONEncode/Decode of the buffer, via HttpService L41328) |
| `WriteU8(v)` / `ReadU8()` | L41350 / L41359 | with range Asserts via Logger (L41329) |
| `WriteU16(v)` / `ReadU16()` | L41366 / L41375 | |
| `WriteU32(v)` / `ReadU32()` | L41382 / L41391 | |
| `WriteF32(v)` / `ReadF32()` | L41398 / L41405 | |
| `WriteF64(v)` / `ReadF64()` | L41412 / L41419 | |
| `WriteVec3F32(v)` / `ReadVec3F32()` | L41426 / L41433 | 3× f32 (X,Y,Z) |
| `WriteStringShort(s)` / `ReadStringShort()` | L41437 / L41446 | u8 len + `buffer.writestring` (≤255) |
| `WriteBoolean8(b)` / `ReadBoolean8()` | L41454 / L41459 | u8 0/1 |

## 2.9 Game-specific buffer state: the potato pile (`SlotPotatoes` / `PotatoSlots`)

Owner: **`ReplicatedStorage.Shared.PotatoPileShared`** (L46508–L46952). The pile is **not** sent over the wire as a blob — the server sends `(seed u32, removedIds {u32}, keyPotatoId u32)` via `PotatoPileSynced` (L44342) and the client **reconstructs** two parallel u32 buffers locally:

Pile construction (verbatim, L46919–L46928):
```lua
L46919  tbl2.CreatePile = function(arg1)          -- arg1 = Seed
L46920          local var1 = buffer.create(var13 * 4)     -- SlotPotatoes: SLOT_COUNT × u32
L46921          local var2 = buffer.create(var13 * 4)     -- PotatoSlots: SLOT_COUNT × u32
L46922          for i1 = 1, var13 do
L46923                  buffer.writeu32(var1, (i1 - 1) * 4, i1)   -- slot i -> potato id i (identity)
L46924                  buffer.writeu32(var2, (i1 - 1) * 4, i1)   -- potato id i -> slot i
L46925          end
L46926
L46927          return { Seed = arg1, SlotPotatoes = var1, PotatoSlots = var2, KeyPotatoId = 0 }
L46928  end
```
* `SLOT_COUNT` = `var13` — total slots in the hex-packed pile cone (computed from `Assets.Potatoes.UnpeeledPotato` extents, L46513–46516; sized for 25000 potatoes, L46543–L46565; `MAX_SEED = 536870912`, `PICK_DISTANCE = 20`, `MARKER_NAME = "PotatoPile"` at L46601–L46610).

Accessors (verbatim, L46700–L46720):
```lua
L46700  tbl2.GetPotatoInSlot = function(arg1, arg2)     -- pile, slot -> potatoId|nil
L46701          local var2 = buffer.readu32(arg1.SlotPotatoes, (arg2 - 1) * 4)
L46702          if var2 == 0 then
L46703                  return nil
L46704          end
L46706          return var2
L46707  end
L46709  tbl2.GetPotatoSlot = function(arg1, arg2)       -- pile, potatoId -> slot|nil
L46714          local var2 = buffer.readu32(arg1.PotatoSlots, (arg2 - 1) * 4)
```
Removal + collapse (the writes at ~L46907-46946, verbatim, L46900–46950):
```lua
L46900  local function fillSlot(arg1, arg2, arg3, arg4)   -- gravity: pull a potato from above into emptied slot
L46902          local var3 = getClosestFilled(arg1, arg2, tbl2.GetAbove(var1))
L46903          if not var3 then
L46904                  return
L46905          end
L46906
L46907          buffer.writeu32(arg1.SlotPotatoes, (var3 - 1) * 4, 0)      -- clear old slot
L46908          local var4 = tbl2.GetPotatoInSlot(arg1, var3)
L46909          buffer.writeu32(arg1.SlotPotatoes, (arg2 - 1) * 4, var4)   -- potato lands in new slot
L46910          buffer.writeu32(arg1.PotatoSlots, (var4 - 1) * 4, arg2)   -- reverse map updated
L46911          table.insert(arg4, { PotatoId = var4, From = var3, To = arg2, Delay = arg3 })
L46912          fillSlot(arg1, var3, arg3 + 0.06, arg4)                   -- recurse upward
L46913  end
...
L46939  tbl2.RemovePotato = function(arg1, arg2)          -- pile, potatoId -> animation list
L46940          local var2 = tbl2.GetPotatoSlot(arg1, arg2)
L46941          if not var2 then
L46942                  return nil
L46943          end
L46944
L46945          buffer.writeu32(arg1.SlotPotatoes, (var2 - 1) * 4, 0)
L46946          buffer.writeu32(arg1.PotatoSlots, (arg2 - 1) * 4, 0)
L46947          local tbl1 = {}
L46948          fillSlot(arg1, var2, 0, tbl1)
L46949          return tbl1
L46950  end
```
Other state users: `IsExposedAt` reads SlotPotatoes (L46822); `IsDiamond`/`GetKind`/`GetSlotPosition`/`GetRotation` derive RNG from `Seed` (L46795–L46803, L46727–L46735).

**Callers of these (client):** `Controllers.PotatoPileController` (L24105–L24947): `onPileSynced` (L24588–24645) calls `CreatePile(seed)` (L24599), `RemovePotato` per synced removed id (L24606/L24620), `SetKeyPotato` (L24601); `onPotatoRemoved` → `RemovePotato` (L24697); `onKeyPotatoMoved` → `SetKeyPotato` (L24653); `predictPick`/`tryPick` use `GetPotatoSlot`/`IsExposed`/`GetKind` (L24400–L24423). Pile spawn in world: `workspace:WaitForChild("Map"):WaitForChild("PotatoPile")` (L24933, via `MARKER_NAME`), pile parts under `Folders.CreateFolder("PotatoPile", workspace)` (L24934).

## 2.10 Full client→server send-site list & server→client receive-site list

Every `:Fire(` site in game code (L16012–L48928) — deobf line + call. This list contains **both** client→server packet sends (e.g. `var19.PotatoPick:Fire`, `var3.PeelingCancel:Fire`, `var6.ToolUsing:Fire`) and internal Signal fires (`tbl1.X:Fire` — see §6; internal ones are `tbl1.`/`tbl2.`-prefixed or `:Fire()` with no packet var):

18414:  tbl2.KindsChanged:Fire(tbl1)
19027:  tbl1.OnCharacterAdded:Fire(arg1, arg2)
19029:          tbl1.OnLocalCharacterAdded:Fire(arg2)
19035:          tbl1.OnCharacterRemoved:Fire(arg1, arg2)
19037:                  tbl1.OnLocalCharacterRemoved:Fire(arg2)
19351:          var16.ClassSlotSelect:Fire(var1)
19381:          var16.ClassStopAt:Fire(str1)
19657:  var16.ClassRoll:Fire()
20155:  var10.DailyRewardClaim:Fire()
20231:  tbl1.DeviceChanged:Fire()
21299:  tbl1.InspectBegan:Fire()
21320:  tbl1.InspectEnded:Fire()
21664:  var5.LeaderboardRequest:Fire()
21756:  var9.LobbyUpgradePurchase:Fire(arg1.Id)
22114:  var3.PeelingFinished:Fire()
22118:  var3.PeelingCancel:Fire()
22410:  tbl1.PotatoPeeled:Fire()
22443:                          var13.PeelingPeelRemoved:Fire(var2, arg3)
22456:          var13.PeelingPeelRemoved:Fire(var4, arg3)
22626:  tbl1.PeelingStarting:Fire()
22633:  tbl1.PeelingStarted:Fire()
22925:  tbl1.PeelingEnded:Fire()
23078:                  var13.PeelingSync:Fire(var2:GetPivot())
23568:  var1.OnPlayerAdded:Fire(arg1)
23572:  var1.OnPlayerRemoved:Fire(arg1)
23577:          var1.OnPlayerAdded:Fire(v1)
24517:          var19.PotatoPick:Fire(var10)
24523:          var19.PotatoPick:Fire(var10)
24944:  var19.PotatoPileRequest:Fire()
25728:          tbl1.MachineOutput:Fire(var4)
25751:          tbl1.MachineOutput:Fire(var4)
25846:          var2.PurchaseProduct:Fire(arg1.Name, arg2)
25852:                          var2.ProductAdminPurchaseAccept:Fire()
26057:  tbl1.SetupVisibleChanged:Fire(arg1)
26086:  tbl1.SetupVisibleChanged:Fire(false)
26096:  tbl1.SetupVisibleChanged:Fire(false)
26129:  tbl1.SetupVisibleChanged:Fire(false)
26130:  var7.QueueCreate:Fire(num1, bool1, bool2)
26140:  var7.QueueLeave:Fire()
26566:  var13.StatsRequest:Fire(arg1.UserId)
26725:          tbl1.OnSynced:Fire()
26738:                          var3.Sync:Fire()
26905:  var6.ToolUsing:Fire(var2)
26925:  tbl1.ToolUsed:Fire(var9)
26926:  var6.ToolSwing:Fire()
26961:  var6.ToolEquip:Fire(arg1)
26962:  tbl1.ToolEquipped:Fire(arg1)
26977:  var6.ToolUsing:Fire(var2)
27675:          var16.ToolUpgradePurchase:Fire(arg2, arg3.Id)
27771:  tbl1.SelectionChanged:Fire(arg1)
27888:          tbl1.OpenChanged:Fire(true)
27900:  tbl1.OpenChanged:Fire(false)
28599:          var19.TutorialHandSelected:Fire()
28704:          var19.TutorialUpgradesOpened:Fire()
28712:          var19.TutorialHandSelected:Fire()
34863:  tbl1.TutorialHoldChanged:Fire()
34874:  tbl1.TutorialHoldChanged:Fire()
34883:  var13.IntroCutsceneFinished:Fire()
37127:          var11.LobbyTutorialFinished:Fire()
37150:                  var11.LobbyTutorialFinished:Fire()
37161:          var11.LobbyGuideRequest:Fire()
39620:          var7.GroupRewardClaim:Fire(var4.CLAIM)
39633:          var7.GroupRewardClaim:Fire(var4.LIKE)
41024:          var56.RunReportRequest:Fire()
41471:  arg1.OnCancel:Fire()
43213:          tbl2.Changed:Fire(var3)
44467:          arg1.OnResourcesChanged:Fire()
44500:          arg1.OnResourcesChanged:Fire()
44513:          arg1.OnResourcesChanged:Fire()
45716:  tbl1.StateChanged:Fire(arg1, arg2, var4.StateChange.Set)
45729:  tbl1.StateChanged:Fire(arg1, arg2, var4.StateChange.SetShallow)
45742:  tbl1.StateChanged:Fire(arg1, arg2, var4.StateChange.Increment)
47618:          tbl1.OnFixedStep:Fire(var1)
47621:  tbl1.OnStep:Fire(var1, 1)
47635:                  tbl1.OnStep:Fire(var1, 0)
47645:                  tbl1.OnFixedStep:Fire(var2)
47650:          tbl1.OnStep:Fire(var1, (math.clamp(num1 / var2, 0, 1)))
48703:  tbl2.Changed:Fire(arg1)


Every `OnClientEvent:Connect` / `OnServerEvent:Connect` / raw remote call site in the whole deobf (the receive surface; note `CmdrEvent`/`CmdrFunction` are Cmdr's own, and `var9.OnClientEvent` is the Packet RemoteEvent):

10909:  tbl1._remoteEvent.OnClientEvent:Connect(function(arg1, ...)
12529:          return arg1.Cmdr._remoteFunction:InvokeServer(var1, tbl1)
12540:                  arg1.Cmdr._remoteEvent:FireClient(arg2, arg3, ...)
17534:  var9.ArrowCreateStatic.OnClientEvent:Connect(function(arg1, arg2)
17538:  var9.ArrowRemoveStatic.OnClientEvent:Connect(function(arg1)
17542:  var9.ArrowCreateDirection.OnClientEvent:Connect(function(arg1, arg2)
17546:  var9.ArrowRemoveDirection.OnClientEvent:Connect(function(arg1)
17733:  var6.SoundPlayed.OnClientEvent:Connect(function(arg1, arg2)
17737:  var6.SoundStopped.OnClientEvent:Connect(function(arg1)
18425:  var8.BagChanged.OnClientEvent:Connect(onBagChanged)
18778:  var7.CameraPerspectiveToggled.OnClientEvent:Connect(onPerspectiveToggled)
19097:  var5.CinematicBarsEnabled.OnClientEvent:Connect(function()
19101:  var5.CinematicBarsDisabled.OnClientEvent:Connect(function()
19933:  var16.ClassRolling.OnClientEvent:Connect(onRolling)
19934:  var16.ClassRollDenied.OnClientEvent:Connect(onRollDenied)
20093:  var8.CutsceneCameraOrbit.OnClientEvent:Connect(function(arg1)
20097:  var8.CutsceneCameraReset.OnClientEvent:Connect(function()
20410:          var6.Escaped.OnClientEvent:Connect(onEscaped)
20411:          var6.EscapeFailed.OnClientEvent:Connect(onEscapeFailed)
20434:  var3.GlobalOverridesSynced.OnClientEvent:Connect(function(arg1)
20440:  var3.SetGlobalOverride.OnClientEvent:Connect(function(arg1, arg2)
20444:  var3.ResetGlobalOverride.OnClientEvent:Connect(function(arg1)
20996:  var10.ItemUnlocked.OnClientEvent:Connect(onItemUnlocked)
21355:          var3.KeyRevealed.OnClientEvent:Connect(var4.Play)
21356:          var3.Escaped.OnClientEvent:Connect(function()
21360:          var3.EscapeFailed.OnClientEvent:Connect(function()
21603:  var5.LeaderboardUpdated.OnClientEvent:Connect(tbl3.ShowEntries)
22072:  var13.NotificationCreated.OnClientEvent:Connect(function(arg1)
22126:  var3.PeelingStarted.OnClientEvent:Connect(onPeelingStarted)
22127:  var3.PeelingNextPotato.OnClientEvent:Connect(var2.NextPotato)
22128:  var3.PeelingStopped.OnClientEvent:Connect(var2.StopPeeling)
22129:  var3.KeyRevealed.OnClientEvent:Connect(function()
22133:  var3.Escaped.OnClientEvent:Connect(function()
23544:          var12.PeelingSpectateStarted.OnClientEvent:Connect(onStarted)
23545:          var12.PeelingSpectateNext.OnClientEvent:Connect(onNext)
23546:          var12.PeelingSpectateSync.OnClientEvent:Connect(onSync)
23547:          var12.PeelingSpectatePeel.OnClientEvent:Connect(onPeel)
23548:          var12.PeelingSpectateStopped.OnClientEvent:Connect(onStopped)
24787:  var19.PotatoPileSynced.OnClientEvent:Connect(onPileSynced)
24788:  var19.PotatoKeyMoved.OnClientEvent:Connect(onKeyPotatoMoved)
24789:  var19.PotatoRemoved.OnClientEvent:Connect(onPotatoRemoved)
24790:  var19.PotatoesPicked.OnClientEvent:Connect(onPotatoesPicked)
25645:  var7.PotatoTablePlaced.OnClientEvent:Connect(onTablePlaced)
25646:  var7.TutorialStack.OnClientEvent:Connect(onTutorialStack)
25849:          var2.ProductAdminPurchasePrompted.OnClientEvent:Connect(function(arg1)
26102:  var7.QueueJoined.OnClientEvent:Connect(onQueueJoined)
26103:  var7.QueueLeft.OnClientEvent:Connect(onQueueLeft)
26104:  var7.QueueTeleporting.OnClientEvent:Connect(onQueueTeleporting)
26253:  var3.RagdollSetEnabled.OnClientEvent:Connect(function(arg1)
26265:  var3.RagdollOtherPlayerSetEnabled.OnClientEvent:Connect(function(arg1, arg2)
26608:  var13.StatsShown.OnClientEvent:Connect(onStatsShown)
26722:  var3.PlayerSynced.OnClientEvent:Connect(function()
28806:  var19.TutorialCompleted.OnClientEvent:Connect(onCompleted)
28807:  var19.Escaped.OnClientEvent:Connect(function()
28812:  var19.EscapeFailed.OnClientEvent:Connect(function()
29827:          var6.PeelRateChanged.OnClientEvent:Connect(onPeeled)
32034:  var27.PotatoesSold.OnClientEvent:Connect(onPotatoesSold)
32578:  var21.ItemUnlocked.OnClientEvent:Connect(onItemUnlocked)
34926:  var13.IntroCutscenePlay.OnClientEvent:Connect(function(arg1, arg2)
36715:  var9.PeelPaid.OnClientEvent:Connect(onPeelPaid)
37174:          var11.LobbyGuideSteps.OnClientEvent:Connect(onGuideSteps)
37188:          var11.QueueJoined.OnClientEvent:Connect(onQueueJoined)
39805:  var7.GroupRewardLikeResult.OnClientEvent:Connect(onLikeResult)
39970:  var17.MachineRevealed.OnClientEvent:Connect(onMachineRevealed)
40218:          var22.MachinePaid.OnClientEvent:Connect(onMachinePaid)
40488:  var16.PurchaseCelebrated.OnClientEvent:Connect(onCelebrated)
41015:          var56.RunReportShown.OnClientEvent:Connect(function(arg1)
45698:  var8.PlayerStateCreated:FireClient(arg1, var1)
45718:          var8.UpdatePlayerState:FireClient(arg1, arg2, var4.StateChange.Set)
45731:          var8.UpdatePlayerState:FireClient(arg1, arg2, var4.StateChange.SetShallow)
45744:          var8.UpdatePlayerState:FireClient(arg1, arg2, var4.StateChange.Increment)
45754:  var8.PlayerStateCreated.OnClientEvent:Connect(function(arg1)
45758:  var8.UpdatePlayerState.OnClientEvent:Connect(function(arg1, arg2)
49222:                          var4.OnServerEvent:Fire(arg1, var20(var14))
49227:  var9.OnServerEvent:Connect(function(arg1, ...)
49267:                                  var9:FireClient(k1, var5)
49269:                                  var9:FireClient(k1, var5, v1.Instances)
49298:  var9.OnClientEvent:Connect(function(arg1, arg2)
49330:                          var2.OnClientEvent:Fire(var20(var9))
49360:                          var9:FireServer(var1)
49362:                          var9:FireServer(var1, tbl1.Instances)


---

# 3. COLLECTIONSERVICE — complete census (7 sites; gameplay uses NO tags)

| Line | Script | Call | Tag |
|---|---|---|---|
| L6928 | PlayerModule ControlModule/ClickToMove | `GetService("CollectionService")` (service handle only) | — |
| L8309 | same (ClickToMove character-follow) | `var7:GetTagged(var14)` — var14 is a runtime parameter (custom tag string, not a literal) | dynamic |
| L8314 / L8318 | same | `GetInstanceAddedSignal(var14)` / `GetInstanceRemovedSignal(var14)` | dynamic |
| L42319 | `Modules.RagdollModule.buildRagdoll` | `game:GetService("CollectionService"):AddTag(arg1, "Ragdoll")` | **"Ragdoll"** |
| L58613 / L58624 | `ModifiedPackages.Seam…StyleSheet` | service handle / `var2:HasTag(var6, arg2:sub(num2))` — CSS-like `#tag` selector matching | dynamic |
| L58870 | `ModifiedPackages.Seam…Declarations.Tags` | `arg2:AddTag(v1)` — Seam style declarations add tags to instances | dynamic |

⇒ **No gameplay tags exist** (no `GetTagged("Slot")` etc. — the pile/machines/crates are located by *names and attributes*, see §5). A harness CollectionService mock only needs `AddTag` (Ragdoll, on server path anyway) and generic GetTagged/HasTag stubs for the PlayerModule/Seam paths.


---

# 4. ATTRIBUTES — complete census (130 call sites)

Name constants defined in shared modules (these are the *gameplay* attributes; resolve via the constant, not the literal):
| Constant | Value | Defined | Used at |
|---|---|---|---|
| `CONTAINER_ATTRIBUTE` | `"ContainerName"` | L45829 (PotatoHoldShared) | L29932 |
| `HELD_CONTAINER_ATTRIBUTE` | `"HeldContainerName"` | L45830 | L30710, L30718(sync) |
| `HELD_KINDS_ATTRIBUTE` | `"HeldKinds"` | L45831 | L30711 (OthersHoldController sync of other players' held potatoes) |
| `CRANKS_ATTRIBUTE` | `"Cranks"` | L46983 (PotatoTableShared) | L18322 (ArmStretchController listens on `Root`) |
| `KINDS_ATTRIBUTE` | `"PotatoKinds"` | L46991 | L47112 (SetKinds), L47117, L47131, L47149 |
| `COUNT_ATTRIBUTE` | `"PotatoCount"` | L46992 | L47113, L47126 |
| `IN_USE_ATTRIBUTE` | `"InUse"` | L46997 | L37503, L37625 (TablePromptController on `PeelPrompt`), L37871, L37890, L37892 |
| `SOURCE_ATTRIBUTE` | `"SourceTable"` | L46998 | L47052 (FindSourceTop) |
| `SOLD_ATTRIBUTE` | `"PotatoesSold"` | L47000 | L23677, L23682, L23683 (PotatoCounterController on `Map.PotatoCounter`) |
| `TOOL_ID_ATTRIBUTE` | `"ToolId"` | L47347 (StoreShared) | L27500, L27525, L27544, L36796, L48896 |
| `GAMEPASS_ATTRIBUTE` | `"Gamepass"` | L47348 | L27501, L27530, L27549, L36804 |
| `PEEL_TOOL_ATTRIBUTE` | `"PeelToolId"` | L47349 | L36809, L48903 |
| `CARRY_LEVEL_ATTRIBUTE` | `"CarryLevel"` | L47350 | L36816, L48910 |
| `MACHINE_ATTRIBUTE` | `"Machine"` | L47351 | L36826, L36785, L48917 |
| `STATE_ATTRIBUTE` | `"QueueState"` | L48598 (QueueShared) | L36961 |
| (packet id registry) | *packet names* | — | L49123, L49128, L49342 (Packet module, see §2.2) |
| (reserved server) | `"IsReservedServer"` | — | L42795–L42803 (Helper.IS_RESERVED_SERVER, on the TeleportService-ish var; loops until set) |
| (UI misc) | `"HoverScale"` | — | L26148 Set / L38043 Get |
| (UI misc) | `"UprightLength"` | — | L37731 Set / L37775 Get |
| (UI misc) | `"DesktopThickness"` | — | L39330 Get / L39333 Set |
| (UI misc) | `"Using"` | — | L30580 (ToolVfxController, tool-using fade on character part) |
| (UI misc) | `"FreecamAccess"` | — | L36088, L36102, L36109, L36197 (FreecamController, on Player) |

Everything else (≈90 sites, L57908–L65013) is **TopbarPlus / Seam UI-framework attribute plumbing** (`Collective`, `WidgetUID`, `CaptionText`, `MaxIcons`, `TargetWidth`, `BorderSize`, `ClipToJoinedParent`, `MaxWidth`, `MenuCanvasWidth`, `CorrespondingIconUID`, `RotationSpeed`, `ForceUpdate`, `IgnoreVisibilityUpdater`, `IsAHolder`, `IsAClippedClone`, `HasAClippedClone`, `TrackCloneSize`, `AdditionalOffsetX`, `StartInset`, `MinimumWidth/Height`, `DesiredWidth`, `MenuWidth`) — irrelevant to gameplay; stub with generic get/set/changed-signal.

Complete raw list (line + call) follows:

18322:  var15.Root:GetAttributeChangedSignal(var9.CRANKS_ATTRIBUTE):Connect(onCranked)
23677:  local var9 = tostring(var4:GetAttribute(var2.SOLD_ATTRIBUTE) or 0)
23682:  var4:GetAttributeChangedSignal(var2.SOLD_ATTRIBUTE):Connect(function()
23683:          local var1 = tostring(var4:GetAttribute(var2.SOLD_ATTRIBUTE) or 0)
26148:  var2:SetAttribute("HoverScale", 1.025)
27500:  if arg1:GetAttribute("ToolId") == nil then
27501:          bool1 = arg1:GetAttribute("Gamepass") ~= nil
27525:          local var10 = k1:GetAttribute("ToolId")
27530:                  local var13 = k1:GetAttribute("Gamepass")
27544:          local var2 = k1:GetAttribute("ToolId")
27549:                  local var8 = k1:GetAttribute("Gamepass")
29932:  local var2 = arg2:GetAttribute(var5.CONTAINER_ATTRIBUTE)
30580:                  local var8 = k1:GetAttribute("Using") == true
30710:  local var5 = arg1:GetAttribute(var6.HELD_CONTAINER_ATTRIBUTE)
30711:  local var7 = arg1:GetAttribute(var6.HELD_KINDS_ATTRIBUTE)
36088:  if not (var2:GetAttribute("FreecamAccess") == true) then
36102:  if var2:GetAttribute("FreecamAccess") == true then
36109:  if var2:GetAttribute("FreecamAccess") == true then
36197:          var2:GetAttributeChangedSignal("FreecamAccess"):Connect(onAccessChanged)
36785:          var4(var5, if arg1.Item.Model:GetAttribute(var2.MACHINE_ATTRIBUTE) then var2.UNLOCKED_TEXT else var2.SOLD_TEXT)
36796:  local var12 = arg1:GetAttribute(var2.TOOL_ID_ATTRIBUTE)
36804:  local var17 = arg1:GetAttribute(var2.GAMEPASS_ATTRIBUTE)
36809:  local var21 = arg1:GetAttribute(var2.PEEL_TOOL_ATTRIBUTE)
36816:  local var25 = arg1:GetAttribute(var2.CARRY_LEVEL_ATTRIBUTE)
36826:  local var29 = arg1:GetAttribute(var2.MACHINE_ATTRIBUTE)
36961:          if v1:GetAttribute(var3.STATE_ATTRIBUTE) ~= var3.EMPTY_STATE then
37503:  local var8 = arg1.PeelPrompt:GetAttribute(var6.IN_USE_ATTRIBUTE) == true
37625:  tbl2.PeelPrompt:GetAttributeChangedSignal(var6.IN_USE_ATTRIBUTE):Connect(function()
37731:  var1:SetAttribute("UprightLength", var10)
37775:  arg1.Rest = CFrame.new(var2.Position + Vector3.new(0, 1, 0) * var2.Size.Y / 2 + Vector3.new(0, 1, 0) * (var1:GetAttribute("UprightLength") / 2 + 0.35)) * var2.CFrame.Rotation
37871:          local var3 = not (var1.PeelPrompt:GetAttribute(var5.IN_USE_ATTRIBUTE) == true)
37890:  tbl2.PeelPrompt:GetAttributeChangedSignal(var5.IN_USE_ATTRIBUTE):Connect(refresh)
37892:  var7 = not (tbl2.PeelPrompt:GetAttribute(var5.IN_USE_ATTRIBUTE) == true)
38043:          HoverScale = arg1:GetAttribute("HoverScale") or 1.06,
39330:  local var1 = arg1:GetAttribute("DesktopThickness")
39333:          arg1:SetAttribute("DesktopThickness", var1)
42795:          var1:SetAttribute("IsReservedServer", var5)
42799:  while var1:GetAttribute("IsReservedServer") == nil do
42800:          var1:GetAttributeChangedSignal("IsReservedServer"):Wait()
42803:  return (var1:GetAttribute("IsReservedServer"))
47052:  local var1 = arg2:GetAttribute(tbl1.SOURCE_ATTRIBUTE)
47112:  arg1:SetAttribute(tbl1.KINDS_ATTRIBUTE, tbl1.EncodeKinds(var1, var2))
47113:  arg1:SetAttribute(tbl1.COUNT_ATTRIBUTE, #arg2)
47117:  arg1:GetAttributeChangedSignal(tbl1.KINDS_ATTRIBUTE):Connect(arg2)
47118:  arg1:GetAttributeChangedSignal(tbl1.COUNT_ATTRIBUTE):Connect(arg2)
47126:  local var1 = arg1:GetAttribute(tbl1.COUNT_ATTRIBUTE)
47131:  local var3 = arg1:GetAttribute(tbl1.KINDS_ATTRIBUTE)
47149:  local var1 = arg1:GetAttribute(tbl1.KINDS_ATTRIBUTE)
48896:  local var4 = arg2:GetAttribute(var5.TOOL_ID_ATTRIBUTE)
48903:  local var11 = arg2:GetAttribute(var5.PEEL_TOOL_ATTRIBUTE)
48910:  local var17 = arg2:GetAttribute(var5.CARRY_LEVEL_ATTRIBUTE)
48917:  local var23 = arg2:GetAttribute(var5.MACHINE_ATTRIBUTE)
49123:          var9:SetAttribute(arg2, var8)
49128:          var3.Id = var9:GetAttribute(arg2)
49342:                  var2.Id = var9:GetAttribute(arg1)
57908:                          var1 = arg2:GetAttributeChangedSignal(arg2):Connect(arg3)
58033:                                          arg2:SetAttribute(arg2, arg3.Value)
58055:                                  arg2:SetAttribute(arg2, arg3.Value)
58059:                          arg2:SetAttribute(arg2, arg3)
58389:                  var3 = arg2:GetAttributeChangedSignal(arg2):Connect(function()
58390:                          if arg2:GetAttribute(arg2) ~= arg3.Value then
58391:                                  arg3.Value = arg2:GetAttribute(arg2)
58394:                          arg3.Value = arg2:GetAttribute(arg2)
61122:                  local var2 = arg2:GetAttribute("Collective")
61148:                  local var3 = v1:GetAttribute("WidgetUID")
61185:          if k1:GetAttribute("Collective") ~= arg2 then
61612:  var3:SetAttribute("CaptionText", arg2)
62120:  var4:SetAttribute("IsAClippedClone", true)
62133:  arg2:SetAttribute("HasAClippedClone", true)
62160:  local var11 = arg2:GetAttribute("IgnoreVisibilityUpdater")
62179:  local var15 = arg2:GetAttribute("AdditionalOffsetX") or 0
62185:                  if arg2:GetAttribute("ClipToJoinedParent") then
62258:          if arg2:GetAttribute("ClipToJoinedParent") then
62348:                                  if arg2:GetAttribute("ClipToJoinedParent") then
62428:          var1:add(var4:GetAttributeChangedSignal("ForceUpdate"):Connect(var6))
62455:  if arg2:GetAttribute("TrackCloneSize") then
62760:          local var1 = var3:GetAttribute("CaptionText") or ""
62780:  var3:GetAttributeChangedSignal("CaptionText"):Connect(updateHotkey)
62839:          local var26 = var3:GetAttribute("CaptionText") or ""
62866:          local var35 = var3:GetAttribute("CaptionText") or ""
62899:                  var17:SetAttribute("ForceUpdate", true)
62903:          local var4 = var3:GetAttribute("CaptionText") or ""
63034:          var6:SetAttribute("StartInset", num3)
63091:  var12:SetAttribute("IsAHolder", true)
63280:          local var2 = var4:GetAttribute("MaxIcons")
63394:          local var3 = var4:GetAttribute("MaxIcons")
63436:                  local var12 = var8:GetAttribute("WidgetUID")
63496:  var16:add(var4:GetAttributeChangedSignal("MaxIcons"):Connect(var18))
63498:  var16:add(var4:GetAttributeChangedSignal("MaxIcons"):Connect(var18))
63748:          var1:GetAttributeChangedSignal("MenuCanvasWidth"):Connect(function()
63750:                  var1.CanvasSize = UDim2.new(0, var1:GetAttribute("MenuCanvasWidth"), var2.Scale, var2.Offset)
63754:                  local var4 = var1:GetAttribute("MaxIcons")
63761:                          if not v1:GetAttribute("WidgetUID") then
63786:                  var1:SetAttribute("MenuWidth", num1)
63801:          var4:add(var1:GetAttributeChangedSignal("MaxIcons"):Connect(var12))
63803:          var4:add(var1:GetAttributeChangedSignal("MaxWidth"):Connect(var12))
63933:  var1:SetAttribute("ClipToJoinedParent", true)
63962:  var5:SetAttribute("Collective", "IconCorners")
63967:  var2:GetAttributeChangedSignal("RotationSpeed"):Connect(function()
63968:          num1 = var2:GetAttribute("RotationSpeed")
63988:  var1:SetAttribute("WidgetUID", arg1.UID)
64028:  var4:SetAttribute("Collective", "IconCorners")
64053:  var7:SetAttribute("CorrespondingIconUID", arg1.UID)
64146:  var17:SetAttribute("Collective", nil)
64203:                          local var24 = v1:GetAttribute("TargetWidth")
64207:                  local var25 = var1:GetAttribute("MinimumWidth")
64210:                  local var27 = var1:GetAttribute("MinimumHeight")
64211:                  local var28 = var1:GetAttribute("BorderSize")
64228:                                  local var30 = v2:GetAttribute("TargetWidth")
64234:                                  local var34 = var33:GetAttribute("TargetWidth")
64245:                  local var37 = var1:GetAttribute("DesiredWidth")
64251:                  local var38 = var5:GetAttribute("MenuWidth")
64256:                          local var42 = var5:GetAttribute("MaxWidth")
64261:                          var5:SetAttribute("MenuCanvasWidth", var29)
64268:                  local var44 = var43:GetAttribute("TargetWidth")
64271:                  var43 = var45:GetAttribute("TargetWidth")
64288:                  var1:SetAttribute("TargetWidth", var45.X.Offset)
64334:                  local var2 = var1:GetAttribute("BorderSize")
64378:                  local var2 = var1:GetAttribute("BorderSize")
64457:                  var6 = var6 and var2:GetAttribute("CorrespondingIconUID")
64468:                                          var19:SetAttribute("IgnoreVisibilityUpdater", true)
64519:                          var9 = var9 and var8:GetAttribute("CorrespondingIconUID")
64619:                  if not v2:GetAttribute("IsAHolder") then
64665:  local var2 = var1:GetAttribute("TargetWidth")
64894:          if var23 and (var30 and var23:GetAttribute("MaxWidth")) ~= var26 then
64895:                  var23:SetAttribute("MaxWidth", var26)
64968:                  result = arg1:GetAttribute(arg2)
64974:          if not arg1:GetAttribute("IsAClippedClone") then
64986:          if not arg1:GetAttribute("HasAClippedClone") then
65013:          local var5 = v1:GetAttribute("Collective")


---

# 5. WORLD ACCESSES — game-structure location chains

Root: **`workspace:WaitForChild("Map")`** (36 sites; e.g. L18265, L18860, L21628, L23663, L24933, L25713, L27566, L28790, L29576, L29834, L30135, L30261, L32535, L35003, L35115, L36337, L36878, L37685, L37905, L39955, L41166) or `workspace:FindFirstChild("Map")` (L22199, L22638, L22840, L26003, L33340, L33458, L33663, L33743, L33771, L33817, L33979, L33984, L35219, L36907, L36939).

Structure constants (owner: `Shared.PotatoTableShared` L46954–L47002 unless noted):
* **The pile:** `Map.PotatoPile` (MARKER_NAME, L46602/L24933) — a BasePart; pile pivot via `GetPileCFrame` (L46915–46917).
* **Machines folder:** `Map.PeelingMachines` (MACHINES_FOLDER_NAME, L46959; `GetMachines` L47007). Children:
  - `PeelingTable%d*` (PEELING_TABLE_NAME + digits; IsPeelingTable regex L47017–47019, enumerated via `ForEachPeelingTable` L47072–47094 using ChildAdded)
  - each table has `TabelTop` (sic, TABLE_TOP_NAME L46961), `PotatoCrate` (INPUT_CRATE_NAME L46964) and `SellCrate` (OUTPUT_CRATE_NAME L46965), each crate has `PotatoArea` (CRATE_AREA_NAME L46966) with **ProximityPrompts `PlacePrompt` / `SellPrompt`** (L46993–46994; found at L37593–37594), `Counter` (CRATE_COUNTER_NAME L46967, read L25654–25655)
  - table-top counters `UnPeeledPotatoCounterTable` / `PeeledPotatoCounterTable` (L46973–46974, watched L25703–25704), `PeelStand` (L46975), `StationLabel` BillboardGuis (L37532)
  - the peel station prompt: `TabelTop.PeelPrompt` (attachment, PEEL_PROMPT_ATTACHMENT_NAME L46995) → child **ProximityPrompt `Peel`** with attribute `InUse` (L46996–46997; found L37623)
  - `AutoPeelingMachine` (AUTO_PEELER_MACHINE_NAME L46969) with top `Cube.051` (L46971), counter `PotatoCounter` (L46972), light `Light` (L46976), `Path` (MACHINE_PATH_NAME L46982)
  - `PeelingMachine` (HAND_MACHINE_NAME L46977) with top `Cube.035` (L46979), root `Cube.033`, handle `Circle.017`, knob `gs` (L46978–46981); `CrankPromptPart.Crank` prompt (L46988–46989; found L18321)
  - `AutoPeelerByHand` (HAND_PEELER_NAME L46990) with `Load` prompt (LOAD_PROMPT_NAME L46987; found L18049) and purchase `ProximityPrompt` (L18050)
* **Store items:** `Map.StoreItems.{Tools,Storage,Robux,Peelers}` (StoreShared FOLDER_NAME L47329 + categories L47330–47333; `GetCategory` L47363) — item Models with `ToolId`/`Gamepass`/`PeelToolId`/`CarryLevel`/`Machine` attributes, a `Price` part (L47337) with `PromptAttachment.ProximityPrompt` (L47345, L27513–27518, purchase prompts L18850).
* **Waterway (sell ride):** `Map.Waterway` (L29577) with paths `MainPath`, `MachinesChannel.{Auto,HandCrank,SaleDrop}` (WaterwayController L29083–29091, createPath calls L29579–29583), `MainPath.SellLine` part (L29602).
* **PotRoom:** `Map.PotRoom` (L29587, L36337) with `Pot.Circle.051` (L36337) and `PotPath` (L29089).
* **Zones:** `Map.Zones` (L30261) — zone children matched by name in LobbyZoneController (ChildAdded L30263).
* **Shops:** `Map.Shops` (L30135, LobbySignController — descendant scan).
* **Global counter:** `Map.PotatoCounter` with attribute `PotatoesSold` (COUNTER_NAME L46999; PotatoCounterController L23663–23683).
* Folders created/expected by `Modules.Resources.Folders` (L44187–44247): `workspace.Hidden` (Camera, L44197–44199), `workspace.Players` (L44215), `workspace.Preload` (L44225), `workspace.Effects` (L44235), `ReplicatedStorage.Inputs` (client-only, L44240–44243) + `CreateFolder(name, parent)` helper (L44200). Controllers create more at runtime: `PotatoPile` (L24934), `PotatoStacks` (L25714), `WaterwayPotatoes` (L29609), `LoosePeels` (PeelingController L22304–22307), `SoundCache` (L17571).
* **Assets tree** (read at require time — must exist before `main` runs): `ReplicatedStorage.Assets` (Resources.Assets L44098–44102) → `Assets.Potatoes.{UnpeeledPotato, PeeledPotato, GoldenUnpeeledPotato, DiamondUnpeeledPotato, RainbowUnpeeledPotato, KeyPotatoes.*, Minigame.*, Diamond}` (L46206, L46256–46295, L46513, L46518) and `Assets.Potatoes.Minigame.<Tool>Potato` (minigame models, PeelToolShared PotatoFolderName L48390+).
* **GUI templates:** `ReplicatedStorage.Gui` (GuiController L20464) containing ScreenGuis cloned by controllers: `Bag`, `Cash`, `Diamonds`, `Peeling`, `Classes`, `Hotbar`, `Escape`, `Leaderboard`, `Crosshair`, `DailyRewards`, `FriendBoost`, `Timer`, `Shop`, `LobbyUpgrades`, `Queue`, `ExpressivePrompt` (e.g. L18264, L18430, L18990, L19864, L20176, L20275, L20359, L20949, L21369, L21627, L23135, L24135…; template names at L26453–26460, L23135, L25948).
* Potato kinds (PotatoKindShared L46201–46507): NORMAL=1 (L46246), Golden (chance .02, L46254), Diamond (.008), Rainbow, KEY=5 (L46246).

Raw `workspace:` site list:

18265:  local var1 = workspace:WaitForChild("Map")
18860:  local var1 = workspace:WaitForChild("Map")
21628:  local var7 = workspace:WaitForChild("Map"):WaitForChild(var2.FOLDER_NAME)
22199:  local var2 = workspace:FindFirstChild("Map")
22638:          local var2 = workspace:FindFirstChild("Map")
22840:  local var26 = workspace:FindFirstChild("Map")
23663:  local var4 = workspace:WaitForChild("Map"):WaitForChild(var2.COUNTER_NAME, 10)
24933:  var34 = var5.GetPileCFrame((workspace:WaitForChild("Map"):WaitForChild(var5.MARKER_NAME)))
25713:  var19 = workspace:WaitForChild("Map")
26003:  local var2 = workspace:FindFirstChild("Map")
27566:  local var1 = workspace:WaitForChild("Map")
28790:  var28 = workspace:WaitForChild("Map")
29576:  local var1 = workspace:WaitForChild("Map")
29834:          var7.ForEachPeelingTable(workspace:WaitForChild("Map"), function(arg1)
30135:  for k1, v1 in workspace:WaitForChild("Map"):WaitForChild("Shops"):GetDescendants() do
30261:  local var1 = workspace:WaitForChild("Map"):WaitForChild("Zones")
32535:  local var1 = workspace:WaitForChild("Map")
33340:  local var1 = workspace:FindFirstChild("Map")
33458:  local var1 = workspace:FindFirstChild("Map")
33663:  local var2 = workspace:FindFirstChild("Map")
33743:  local var25 = workspace:FindFirstChild("Map")
33771:  local var35 = workspace:FindFirstChild("Map")
33817:  local var1 = workspace:FindFirstChild("Map")
33979:  local var2 = workspace:FindFirstChild("Map")
33984:  local var6 = workspace:FindFirstChild("Map")
35003:  local var1 = workspace:WaitForChild("Map")
35115:  local var1 = workspace:WaitForChild("Map")
35219:  local var1 = workspace:FindFirstChild("Map")
36337:  local var1 = workspace:WaitForChild("Map"):WaitForChild("PotRoom"):WaitForChild("Pot"):WaitForChild("Circle.051")
36878:  local var1 = workspace:WaitForChild("Map")
36907:  local var1 = workspace:FindFirstChild("Map")
36939:  local var1 = workspace:FindFirstChild("Map")
37685:  local var1 = workspace:WaitForChild("Map")
37905:  var11 = workspace:WaitForChild("Map")
39955:  local var1 = var15.GetMachine(workspace:WaitForChild("Map"), var15.HAND_MACHINE_NAME)
41166:          local var1 = workspace:WaitForChild("Map")


---

# 6. INTERNAL SIGNALS — `ModifiedPackages.Signal` (L55578–L55813)

Implementation: GoodSignal-style linked-list signal. **Export surface (L55813):** `return { new = tbl3.new, wrap = tbl3.wrap }` — usage `require(...Signal).new()`.
* `.new()` L55778–55780; `.wrap(rbxEvent)` L55782–55789.
* Methods: `Connect(fn)` L55791 (returns connection with `.Connected`, `Disconnect` L55589–55609, `Reconnect` L55611–55626), `Once` L55792, `Wait` L55793, **`Fire(...)` L55794** (masked body — deferred dispatch via BindableEvent-derived connect fns, L55638–55645), `DisconnectAll` L55795, `Destroy` L55801.
* A second, simpler signal (`Packet._Signal`, L49454–L49529) is used *only* inside the network module for `OnServerEvent`/`OnClientEvent` (Connect L49462, Once L49473, Wait L49484, Fire L49495 — dispatches via `_Task:Defer` L49503).

Game signal registry (creation sites; these are what the harness world must fire to drive client loops):
| Signal | Owner script | Created | Fired | Listened (examples) |
|---|---|---|---|---|
| `KindsChanged` | BagController | L18370 | L18414 | bag UI refresh |
| `OnCharacterAdded/Removed`, `OnLocalCharacterAdded/Removed` | CharacterController | L19021–L19024 | L19027–19037 | character spawn logic |
| `DeviceChanged` | DeviceController | L20206 | L20231 | L23211, L23243, L26860s |
| `InspectBegan/InspectEnded` | InspectController | L21210–21211 | L21299, L21320 | camera inspect |
| **`PotatoPeeled`** | PeelingController | L22164 | **L22410** (in `finishPotato`, L22398) | HotbarController, SellValue etc. |
| `PeelingStarting/PeelingStarted/PeelingEnded` | PeelingController | L22165–L22167 | L22626, L22633, L22925 | TablePromptController L37639/L37662, PotatoPileController L24853 |
| `MachineOutput` | PotatoTableController | L24966 | L25728, L25751 (machine tops produce) | machine flow |
| `SetupVisibleChanged` | QueueController | L25979 | L26057, L26086, L26096, L26129 | queue GUI |
| `OnSynced` | SyncController | L26720 | L26725 (on `PlayerSynced` packet) | post-sync init |
| `ToolEquipped` / `ToolUsed` | ToolEquipController | L26764–L26765 | L26962 / L26925 | tool visuals |
| `OpenChanged` / `SelectionChanged` | ToolUpgradeController | L27605–27606 | L27888, L27900 / L27771 | upgrades GUI |
| `TutorialHoldChanged` | TutorialController | L32602 | L34863, L34874 | tutorial hand |
| `Changed` | Helper.CutsceneState | L43198 | L43213 | cutscene |
| `OnPlayerAdded/OnPlayerRemoved/OnItemPurchased` | Resources.Events | L44182–L44184 | L23568, L23572, L23577 | PlayerController L23562–23584 |
| `OnResourcesChanged` | Resources.Resource | L44560 | L44467, L44500, L44513 | resource preload |
| **`StateChanged`** | **PlayerStateShared** | **L45565** | **L45716, L45729, L45742** (Set/SetShallow/Increment) | L24110s, L27579, L37638, L23212, L26780… — the master client-state signal |
| `OnFixedStep` / `OnStep` | TimeShared | L47605–47606 | L47618–47650 | tick consumers |
| `Changed` | TutorialStackShared | L48699 | L48703 | stack watchers (L37598, L37599) |
| `OnCancel` | Modules.Cancellable | L41475 | L41471 | cancellation |

**Client state propagation model:** server pushes `PlayerStateCreated` (full template, L45666–45617) and `UpdatePlayerState` (patch + `StateChange` enum 1=Set, 2=SetShallow, 3=Increment — Enums L44149) → `PlayerStateShared` applies (L45754–45775) → fires `StateChanged` → every controller re-reads `TryGetPlayerState(LocalPlayer)` (L45624). ⇒ The harness server mock drives the entire client by sending these two packets.

---

# 7. PLAYER INPUT / TOOLS — the automation surface

## 7.1 Input system — `InputControllerV2` (L21030–L21198)

Uses Roblox's (new) `InputContext` / `InputAction` / `InputBinding` instances — parents them into `ReplicatedStorage.Inputs` (Folders.Inputs, L21039). Contexts (priority): `Inventory` 1000 (L21034–21040), `Interactions` 2000 (L21041–21047), `Inspect` 3000 sink (L21048–21054). **Actions table (`…InputControllerV2.Actions`, L21069–L21196):**
| Action | Key bindings | Line |
|---|---|---|
| UseItem | MouseLeftButton | L21069 |
| UseItemMobile | TouchPosition | L21075 |
| HotbarSlot1–4 | One, Two, Three, Four | L21081–L21103 |
| HotbarPrevious/Next | ButtonL1 / ButtonR1 | L21105–L21115 |
| InteractWithPlayer, Fish | MouseLeftButton, TouchPosition | L21117–L21127 |
| UnlockMouse | LeftAlt | L21129 |
| ToggleToolUpgrades | Tab, ButtonY | L21135 |
| CloseMenu | ButtonB | L21141 |
| **PickPotato** | **MouseLeftButton, TouchPosition, ButtonR2** | **L21147** |
| InspectDrag | MouseRightButton | L21157 |
| **InspectClick** (peel click) | **MouseLeftButton, TouchPosition, ButtonR2** | **L21163** |
| PeelLeave | ButtonB | L21173 |
| PeelAuto | ButtonY | L21179 |
| PeelAll | ButtonX | L21185 |
| InspectRotate | Thumbstick2 (Direction2D) | L21191 |

Each action object exposes `Pressed`/`Released` signals (consumed e.g. L24941–24942, L23091–23095). The harness must mock these three Instance classes with `.Pressed`/`.Released`.

## 7.2 Picking potatoes (hold-click)

`PotatoPileController` (L24105–24947):
* Hold LMB → `Actions.PickPotato.Pressed` → `onPickPressed` (L24886) → `SetUsing(true)` + `tryPick(mousePos)`.
* `tryPick` (L24451–24526): cooldown check via `ToolUpgradeShared.GetPickInterval` (L24459), overheat (`IsOverheated` L24460), charge (`HasCharge` L24470), bag capacity from PlayerState (L24505), raycast 20 studs into the pile folder (L24479; `RaycastParams` include-list `PotatoPile` folder L24935) or nearest-potato scan `getPotatoNearCursor` (L24365–24414, requires `IsExposed`); then **`var19.PotatoPick:Fire(var10)`** (L24517; delayed by tool impact delay L24522–24525) and local prediction `predictPick` (L24416–24449, 0.12 s hide, 1.5 s revert).
* Held state repeats via `Heartbeat → updateHeldPick → tryPick(getAimLocation())` (L24940, L24874–24884); aim = `UserInputService:GetMouseLocation()` (L24528–24534) or screen center on mobile/console.
* Touch: `UserInputService.TouchTap` → `onTouchTap` (L24905–24926, L24943).
* Hover highlight via `Highlight` adornee (L24851–24872); `SetUseHeld(bool)` external API (L24536–24546).

## 7.3 Peeling minigame (the core loop)

`PeelingController` (L22141–23247):
* Server starts it: packets `PeelingStarted(table Instance, {kinds u8}, toolName string)` → `onPeelingStarted` (connected L22126) → `StartPeeling` (L22621–22634: sets `IsPeeling`, fires PeelingStarting/Started, `NextPotato`); `PeelingNextPotato({kinds}, toolName)` → `NextPotato` (L22725–22880: spawns potato model `Assets.Potatoes.Minigame.<tool>` clone in workspace, positions at `Map.PeelingMachines.PotatoCrate.PotatoArea` or hand fallback, `tbl6 = getPeels(model)` — child BaseParts named **"Peel"**, L22221–22236); `PeelingStopped` → `StopPeeling` (L22906–23021).
* While peeling, every RenderStepped: `updateHeldPeeling` (L23073–23088) → (a) **`PeelingSync:Fire(potato:GetPivot())`** every ≥0.08 s (L23076–23079) — sends the potato's CFrame (`Any`-typed); (b) `updateAutoPeel` (L22524–22583, if AutoPeel product owned); (c) if mouse held, `tryPeel` (L22484–22521): raycast from mouse into the potato model, hit part must be named **"Peel"**, then `performPeel` (L22435–22467): knife strike anim, sound, **`var13.PeelingPeelRemoved:Fire(peelIndex u8, hitPosition Vector3F24)`** (L22443 instant-peel / L22456 normal — `peelIndex = table.find(tbl6, peelPart)`), local peel physics release (L22291–22317), `finishPotato` when no peels left → fires internal `PotatoPeeled` (L22410).
* Leave: `PeelLeave` action (ButtonB, L23093) or GUI `Cancel` button `Activated` (L23143) → `StopPeeling` → **`PeelingCancel:Fire()`** (L22118 — connected via `var3.PeelingCancel` in a wrapper at L22100–22120); completion **`PeelingFinished:Fire()`** at L22114.
* GUI: `Peeling` ScreenGui from `ReplicatedStorage.Gui` (L23135), `AUTO PEEL` / `PEEL ALL` buttons (L23146–23172), gamepad hints (L23191–23206).

## 7.4 Tools & hotbar

* Pick tools (ToolUpgradeShared L47657+): `Hand` (L47664), `Shovel`, `PotatoSucker` (L47666) + upgrade ids (PickSpeed, PickAmount, Charge, Cooling, HoldPick…). Peel tools (PeelToolShared L48381+): `Spoon`, `Knife`, `SwissKnife`, `Peeler`, `TriplePeeler` (L48388–48392) with `AutoPeelRate`, `InstantPeel`.
* Equip flow: HotbarController slot click/keys → `SelectSlot` (L20646–20679) → **`ToolEquipController.Equip(toolId)`** (L26947–26963) → **packet `ToolEquip:Fire(toolId string)`** (L26961) + internal `ToolEquipped:Fire` (L26962). Trial tools prompt a purchase (L20665–20670).
* Using: `SetUsing(bool)` (L26897–26906) → **packet `ToolUsing:Fire(active bool)`** (L26905, also L26977 from charge loop); each pick/swing → `Use()` (L26923–26927) → internal `ToolUsed` + **packet `ToolSwing:Fire()`** (L26926). Heat/charge simulated client-side (L26909–26945).
* Purchase: `ToolPurchase:Fire(toolName)` sites (ToolPickupController prompts) and `ToolUpgradePurchase:Fire(tool, upgradeId)` L27675.

## 7.5 ProximityPrompts (world interaction)

World prompts (harness must provide these instances for FirePP-style automation):
* `Map.PeelingMachines.AutoPeelerByHand…Load` prompt (L46987, read L18049) + purchase prompt (L18050).
* `CrankPromptPart.Crank` (L46988, read L18321 — cranking the hand peeler; `Cranks` attribute on machine root listened at L18322).
* `PotatoCrate.PotatoArea.PlacePrompt` and `SellCrate.PotatoArea.SellPrompt` (L46993–46994, read L37593–37594, enabled-state driven by player state + crate counts L37549–37586).
* `TabelTop.PeelPrompt.Peel` (L46995–46996, read L37623) — entering the peel minigame; **`InUse` attribute** gates it (L37503, L37625, L37871, L37890–37892).
* Store purchase prompts: `<item>.Price.PromptAttachment.ProximityPrompt` (StoreShared L47345; L18850, L27513–27518) — enabled by ownership (ToolPickupController L27523–27558).
* StatsController creates its own prompt client-side (L26584–26591, `Triggered` connect at L26591).
* Prompt UI is reskinned by `ProximityPromptController` (L25860–25962) via `ModifiedPackages.ExpressivePrompts` (template `PlayerGui.ExpressivePromptsGui`, L25957; uppercase ActionText enforcement L25931–25944).

**What a player physically does:** hold/click LMB over a potato in the pile (or tap on touch) to pick; walk to a peeling table and trigger the `Peel` ProximityPrompt; click LMB repeatedly on the "Peel" parts to peel (or buy AUTO PEEL / Peel All); place potatoes on the table via `PlacePrompt`, sell via `SellPrompt`; crank the hand machine / load the auto peeler; equip tools via hotbar 1–4; leave with ButtonB/LEAVE. All of these reduce to the packet sends in §2.10 — the automation surface is exactly: `PotatoPick`, `PeelingPeelRemoved`, `PeelingSync`, `PeelingCancel`, `PeelingFinished`, `ToolEquip`, `ToolUsing`, `ToolSwing`, `ToolPurchase`, `ToolUpgradePurchase`, `PotatoPileRequest`, `Sync`, plus purchase/queue/misc packets.

---

# 8. CMDR — the admin remote (single direct `:InvokeServer`)

* Library: `ReplicatedStorage.CmdrClient` (L10814–L16010, 53 scripts). Client guard `assert(IsClient())` L10817.
* Remotes (children of the CmdrClient script): **`CmdrEvent`** (RemoteEvent, `script:WaitForChild("CmdrEvent")` L10851) and **`CmdrFunction`** (RemoteFunction, L10852). Activation key **F2** (L10853).
* **The only `:InvokeServer` in the entire deobf** — `Shared/Dispatcher.Send` (L12525–12530), verbatim:
```lua
L12525          Send = function(arg1, arg2, arg3)
L12526                  assert(var4, "[Cmdr] [Dispatcher::Send] can only be called from the client.")
L12527                  local var1 = arg2
L12528                  local tbl1 = { Data = arg3 }
L12529                  return arg1.Cmdr._remoteFunction:InvokeServer(var1, tbl1)   -- (commandText, {Data=...})
L12530          end,
```
* Commands available (ReplicatedStorage.CmdrClient.Commands.*, L13983–L14895): AddPeeled, AddUnpeeled, Ban, BanByUserId, Bring, Fly, ForceKey, GivePotatoes, GiveShinies, Help, Kick, LogGlobalOverrides, Op, Peel, ResetData, ResetGlobal, SetCash, SetGlobal, Speed, Teleport, Unban, Vanish, GivePeelTool, SpawnKey, Gamepass, Carry, Avatar, Money, DumpUi, Dialogue, Tutorial, Cutscene, PileCut, RunPeels, UnlockTools, FillLeaderboard, ResetTutorial, FirstPerson, ThirdPerson, SetPeelTool, Sell, Celebrate, FakeReport, Freecam, Perspective.
* Gated by `Modules.Permissions` (L42035–42072): admin user ids `{1719875357, 15673743, 1706888615, 89261119}` (L42039), Studio always admin (L42044, L42058). `CmdrController` (L19941–19957) enables the client console only for admins (L19950–19956).
* Cmdr's own remote event traffic: client `OnClientEvent` at L10909; server-side FireClient wrapper L12540.
* ⇒ Per Rule 11 (likely excluded from harness automation): the Cmdr RemoteFunction is the only non-Packet remote; a mock needs `CmdrClient.CmdrEvent`/`CmdrFunction` children to exist if the module is required (it is, at L19946), but the admin path can stay inert for a non-admin LocalPlayer.

---

# 9. HARNESS MUST-MOCK CHECKLIST (summary)

1. **DataModel:** `ReplicatedStorage.{Modules,Shared,Controllers,ModifiedPackages,Assets,Gui,Packages,_Index,CmdrClient,Inputs}`, `workspace.{Map,Players,Preload,Effects,Hidden}`, `Map` subtree of §5 (esp. `PotatoPile`, `PeelingMachines.*`, `StoreItems.*`, `Waterway`, `PotRoom`, `Zones`, `Shops`, `PotatoCounter`), `LocalPlayer.PlayerGui.ExpressivePromptsGui`, current `workspace.CurrentCamera`.
2. **Packet network:** one `RemoteEvent` child of the Packet module with per-packet-name **attributes holding dispatch ids**; FireServer(buffer[, instances]) once per ~1/60 s; OnClientEvent(buffer[, instances]) decodes `[u8 id][fields…]` frames; Instances side-table passed as the second remote argument; implement the ~90-packet registry of §2.3 with `_Types` codec of §2.7 (or hand-pack the few packets the harness actually drives).
3. **Server-driven flow:** respond to `Sync` with `PlayerSynced`; send `PlayerStateCreated` + `UpdatePlayerState` patches (drives everything via `StateChanged`); `PotatoPileSynced(seed, removed, keyId)` on `PotatoPileRequest`; `PeelingStarted/Next/Stopped` around the peel loop; confirm picks with `PotatoesPicked`.
4. **Signals:** `ModifiedPackages.Signal` `{new, wrap}` with Connect/Once/Wait/Fire; `Resources.Events` singleton signals; PlayerStateShared.StateChanged is the hub.
5. **Input:** mock `InputContext/InputAction/InputBinding` classes with Pressed/Released; `UserInputService` (GetMouseLocation, TouchTap, DeviceChanged…); ProximityPrompts with Enabled + `InUse` attributes.
6. **Roblox globals:** `buffer` library (create/len/copy/readu8…/writeu8…/readbits/writebits/readstring/writestring), `task`, `Random`, `TweenService`, `RunService` (Heartbeat/RenderStepped/PostSimulation + IsServer=false), `workspace:Raycast/BulkMoveTo`, `Instance.new` for the classes the client creates (Highlight, ParticleEmitter, ProximityPrompt, Camera, Folder, UI…).

*Deobf artifact note:* the dump occasionally drops a loop body or an alias assignment while preserving line structure (e.g. Packet module locals `var10` (type compiler = the `var21` function at L49383), `var14` (response-timeout handler), `var8` (server id counter init) are declared at L48943/L48945/L48960 and used at L49121–49126/L48988/L49135 but their assignments are not visible; `Signal.Fire` body at L55763–55776 and `Signal.DisconnectAll/Destroy` at L55795–55811 have empty/masked loops). Semantics above were reconstructed from call sites; a faithful port should re-derive these three aliases as: `var10 = var21`, `var14 = function(ring, index, timeoutValue) … resume/cancel …`, `var8` = next server packet id (starts at 1 on the server).
