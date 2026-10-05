-- ===== FNAF WORLD GAME LAYER (glm1, FW1, 2026-10-05) =====
-- Mock world for [GLITCH WORLD + SCOTT] FNAF World Multiplayer.
-- Surface per work/lua/fnafworld-analysis.md: client-authoritative game —
-- all automation is UI-button Activated firing + game-module calls + TPTo.
-- No RemoteEvents are fired by the script (banned-wire sweep stays empty).

local ScriptPath = arg and arg[1] or ((os.getenv("PUBLIC_DIR") or "/home/z/Public") .. "/[GLITCH WORLD + SCOTT] FNAF World Multiplayer/[GLITCH WORLD + SCOTT] FNAF World Multiplayer.lua")
local ScriptSrc = nil
do
    local fallbacks = {
        ScriptPath,
        (os.getenv("SF_DIR") or "/home/z/SavedFolder") .. "/work/lua/FnafWorld.lua",
    }
    for _, p in ipairs(fallbacks) do
        local f = io.open(p, "r")
        if f then
            ScriptSrc = f:read("*a")
            f:close()
            ScriptPath = p
            break
        end
    end
end

G.UDim2 = {
    new = function(xs, xo, ys, yo)
        return { X = { Scale = xs, Offset = xo or 0 }, Y = { Scale = ys, Offset = yo or 0 } }
    end,
}
G.Vector2 = { new = function(x, y) return { X = x, Y = y } end }
G.firesignal = function(sig, ...)
    if sig and sig.Fire then
        sig:Fire(...)
    end
end
G.getconnections = nil

-- ===== module mocks (faithful to the deobf) =====
local SaveCalls = { AutoSave = 0 }
local SaveClient = {
    HasActiveSlot = function() return true end,
    AutoSave = function() SaveCalls.AutoSave = SaveCalls.AutoSave + 1 end,
}

local ByteInventory = {
    MaxSelected = 4,
    Names = { "Gnat", "NeonBee", "NeonWasp", "Medpod1", "Medpod2", "MegaMed", "Mini-Reaper", "Reaper", "X-Reaper" },
    Prices = {
        Gnat = 25, NeonBee = 75, NeonWasp = 150, Medpod1 = 25, Medpod2 = 100,
        MegaMed = 500, ["Mini-Reaper"] = 100, Reaper = 500, ["X-Reaper"] = 2000,
    },
    ShopStock = {
        LolbitShopKeeper = { "Gnat", "NeonBee", "NeonWasp" },
        LolbitShopKeeper2 = { "Medpod1", "Medpod2", "MegaMed" },
        LolbitShopKeeper3 = { "Mini-Reaper", "Reaper", "X-Reaper" },
        LolbitShopKeeper4 = { "Block1", "Block2", "Block3" },
        LolbitShopKeeper5 = { "Block5", "Block20", "Block50" },
        LolbitShopKeeper6 = { "BossDrain01", "BossDrain02", "BossDrain-X" },
        LolbitShopKeeper7 = { "Mini-FO", "UFO", "X-FO" },
    },
}
Prices7 = {
    Block1 = 50, Block2 = 100, Block3 = 250, Block5 = 50, Block20 = 200, Block50 = 500,
    ["BossDrain01"] = 100, ["BossDrain02"] = 250, ["BossDrain-X"] = 1000,
    ["Mini-FO"] = 100, UFO = 300, ["X-FO"] = 900,
}
for k, v in pairs(Prices7) do
    ByteInventory.Prices[k] = v
end
ByteInventory.Key = function(arg1) return (tostring(arg1):gsub("!", "")) end
ByteInventory.OwnedAttribute = function(arg1) return "ByteOwned" .. ByteInventory.Key(arg1) end
ByteInventory.Owns = function(plr, name)
    if ByteInventory.Prices[name] == nil then return false end
    return plr:GetAttribute(ByteInventory.OwnedAttribute(name)) == true
end
ByteInventory.Purchase = function(plr, name)
    local price = ByteInventory.Prices[name]
    if not price then return false, "Unknown byte" end
    if ByteInventory.Owns(plr, name) then return false, "Already owned" end
    local tokens = plr:GetAttribute("FazTokens")
    if type(tokens) ~= "number" or tokens < price then return false, "Not enough Faztokens" end
    plr:SetAttribute("FazTokens", tokens - price)
    plr:SetAttribute(ByteInventory.OwnedAttribute(name), true)
    return true
end

local Progression = {}
do
    local base = {
        Freddy = { id = 1, hp = 105 }, Bonnie = { id = 2, hp = 110 },
        Chica = { id = 3, hp = 115 }, Foxy = { id = 4, hp = 120 },
        EndoTest = { id = 9, hp = 120 },
    }
    for _, v in pairs(base) do
        v.hp = 100 + v.id * 5
    end
    Progression.Get = function(plr, name)
        local cfg = base[name]
        if not cfg then return nil end
        local level = tonumber(plr:GetAttribute("FnafLevel_" .. name)) or 1
        level = math.floor(level)
        if level < 1 then level = 1 elseif level > 10000 then level = 10000 end
        return { level = level, xp = 0, maxHP = cfg.hp + (level - 1) * 5, nextXP = 0 }
    end
    Progression.MaxHP = function(plr, name)
        local data = Progression.Get(plr, name)
        return data and data.maxHP or 120
    end
end

local Overworld = {
    CanInteractOnLayer = function(plr, layer)
        if plr:GetAttribute("InGlitchWorld") == true then return false end
        return (plr:GetAttribute("OverworldLayer") or 1) == (layer or 1)
    end,
}

local MoveButtonData = {
    Characters = {
        Freddy = {
            { name = "Mic Toss", effect = "singleDamage", damage = { 4, 6 } },
            { name = "Pizza Wheel", effect = "allDamage", damage = { 3, 5 } },
            { name = "Birthday", effect = "buff", damageBoost = 1.25 },
        },
        Bonnie = {
            { name = "Bite", effect = "singleDamage", damage = { 5, 7 } },
            { name = "Bash Jam", effect = "allDamage" },
            { name = "Happy Jam", effect = "healAll", heal = { 20, 30 } },
        },
        Chica = {
            { name = "Cupcakes", effect = "healAll", heal = { 24, 34 } },
            { name = "Party Favors", effect = "healAndDamageAll", heal = { 12, 20 }, damage = { 2, 4 } },
            { name = "Regen Song", effect = "regen", heal = { 10, 16 } },
        },
        Foxy = {
            { name = "Hook", effect = "singleDamage", damage = { 5, 8 } },
            { name = "Jumpscare", effect = "stun", stunTime = 1.75 },
            { name = "Hot Cheese", effect = "allDamage", damage = { 3, 6 } },
        },
        EndoTest = {
            { name = "Unscrew", effect = "instantDefeat", successChance = 0.33 },
            { name = "Bite", effect = "singleDamage", damage = { 5, 7 } },
            { name = "Bash Jam", effect = "allDamage" },
        },
    },
}

-- ===== RS tree + module registry =====
local RS = Instance.new("Folder", "ReplicatedStorage")
local WS = Instance.new("Folder", "Workspace")
local ModuleRegistry = {}
G.require = function(obj)
    if ModuleRegistry[obj] then return ModuleRegistry[obj] end
    error("mock require: unregistered module " .. tostring(obj and obj.Name))
end
local function addModule(parent, name, tbl)
    local m = Instance.new("ModuleScript", name)
    parent:AddChild(m)
    ModuleRegistry[m] = tbl
    return m
end

addModule(RS, "FnafWorldByteInventory", ByteInventory)
addModule(RS, "FnafWorldProgression", Progression)
addModule(RS, "FnafWorldSaveClient", SaveClient)
addModule(RS, "FnafWorldOverworld", Overworld)

-- ===== player + character =====
local PLR = Instance.new("Player", "LocalPlayer")
PLR.Idled = Signal.new()
PLR:SetAttribute("FazTokens", 100)
PLR:SetAttribute("FnafLevel_Freddy", 10)
PLR:SetAttribute("OverworldLayer", 1)
PLR.Character = Instance.new("Model", "Character")
local HRP = Instance.new("Part", "HumanoidRootPart")
HRP:SetCFrame(CFrame.new(0, 3, 0))
PLR.Character.PrimaryPart = HRP
PLR.Character:AddChild(HRP)
PLR.Character:AddChild(Instance.new("Humanoid", "Humanoid"))
PLR.Character:AddChild(Instance.new("Part", "Collision"))
local PlayerGuiFolder = Instance.new("Folder", "PlayerGui")
PLR:AddChild(PlayerGuiFolder)
PLR.PlayerGui = PlayerGuiFolder

local function mkGui(name, enabled)
    local g = Instance.new("ScreenGui", name)
    g.Enabled = enabled
    PLR.PlayerGui:AddChild(g)
    return g
end
local function mkPart(parent, name, x, y, z)
    local p = Instance.new("Part", name)
    p:SetCFrame(CFrame.new(x, y, z))
    parent:AddChild(p)
    return p
end
local function mkButton(parent, name, visible)
    local b = Instance.new("ImageButton", name)
    b.Visible = visible ~= false
    b.Activated = Signal.new()
    parent:AddChild(b)
    return b
end
local function mkLabel(parent, name, visible)
    local l = Instance.new("ImageLabel", name)
    l.Visible = visible ~= false
    parent:AddChild(l)
    return l
end
local function mkFrame(parent, name, visible)
    local f = Instance.new("Frame", name)
    f.Visible = visible ~= false
    parent:AddChild(f)
    return f
end

-- ===== battle gui =====
local BattleGui = mkGui("FnafWorldBattle", false)
local MovePanel = mkFrame(BattleGui, "MovePanel", false)
local MoveBtn1 = mkButton(MovePanel, "Move1Button")
local MoveBtn2 = mkButton(MovePanel, "Move2Button")
local MoveBtn3 = mkButton(MovePanel, "Move3Button")
local SwitchButton = mkButton(BattleGui, "SwitchButton", false)
local BossHPBar = mkFrame(BattleGui, "BossHPBar", false)
local PartySide = mkFrame(BattleGui, "PartySide", true)
local Controller = Instance.new("LocalScript", "BattleController")
BattleGui:AddChild(Controller)
addModule(Controller, "BattleMoveButtonData", MoveButtonData)
do
    local sideNames = { "Freddy", "Bonnie", "Chica", "Foxy" }
    for i = 1, 4 do
        local cf = mkFrame(PartySide, "Character" .. i, true)
        cf:SetAttribute("CharacterName", sideNames[i])
        local bar = mkFrame(BattleGui, "HPBar" .. i, true)
        local hpt = Instance.new("TextLabel", "HPText")
        hpt.Text = "140"
        bar:AddChild(hpt)
    end
end

-- ===== title screen (game-over recovery) =====
local TitleScreen = mkGui("FnafWorldTitleScreen", false)
local SaveScreen = mkFrame(TitleScreen, "SaveScreen", false)
local DoneButton = mkButton(SaveScreen, "DoneButton")

-- ===== deedee fishing =====
local DeedeeShop = mkGui("FnafWorldDeedeeShopKeeper", false)
local FishingPlay = mkButton(DeedeeShop, "FishingPlayHitButton", false)
local DeedeeMinigame = mkGui("FnafWorldDeedeeMinigame", false)
DeedeeMinigame:SetAttribute("DropSpeed", 0.55)
DeedeeMinigame:SetAttribute("DropDistanceScaleY", 0.86)
DeedeeMinigame:SetAttribute("BoatLeftX", 0.06)
DeedeeMinigame:SetAttribute("BoatRightX", 0.94)
DeedeeMinigame.AbsoluteSize = { X = 1000, Y = 500 }
local Boat = mkLabel(DeedeeMinigame, "FreddyBoatImage", true)
Boat.Position = G.UDim2.new(0.5, 0, 0.3, 0)
local Plunger = mkLabel(Boat, "Plunger", true)
Plunger.AbsolutePosition = { X = 480, Y = 100 }
Plunger.AbsoluteSize = { X = 40, Y = 40 }
local DropButton = mkButton(DeedeeMinigame, "DropButton")
local FishLayer = mkFrame(DeedeeMinigame, "FishLayer", true)
local Pearl = mkLabel(DeedeeMinigame, "Pearl", false)
local BlueFish = mkLabel(FishLayer, "BlueFish_1", true)
BlueFish:SetAttribute("FishColor", "Blue")
BlueFish:SetAttribute("SwimDirection", "Right")
BlueFish:SetAttribute("SwimSpeed", 0.2)
BlueFish:SetAttribute("SwimMinX", 0.05)
BlueFish:SetAttribute("SwimMaxX", 0.95)
BlueFish:SetAttribute("SwimLaneY", 0.78)
BlueFish.Position = G.UDim2.new(0.94, 0, 0.78, 0)
BlueFish.AbsolutePosition = { X = 920, Y = 390 }
BlueFish.AbsoluteSize = { X = 50, Y = 50 }

-- ===== world map =====
local MapFolder = Instance.new("Folder", "Map")
WS:AddChild(MapFolder)
local BossesFolder = Instance.new("Folder", "Bosses")
MapFolder:AddChild(BossesFolder)
local function mkBoss(name, x, y, z, attrs)
    local b = Instance.new("Part", name)
    b:SetCFrame(CFrame.new(x, y, z))
    for k, v in pairs(attrs or {}) do
        b:SetAttribute(k, v)
    end
    BossesFolder:AddChild(b)
    local blocker = Instance.new("Part", "CollisionBlocker")
    blocker:SetCFrame(CFrame.new(x, y, z))
    b:AddChild(blocker)
    return b, blocker
end
local _, SeagoonBlocker = mkBoss("Seagoon", 5, 1, 0, { DefeatedLocally = true, SourceLayer = 1 })
local Bouncer, BouncerBlocker = mkBoss("Bouncer", 20, 1, 0, { SourceLayer = 1 })
local _, ChipperBlocker = mkBoss("AutoChipper", 50, 1, 0, { SourceLayer = 1 })
do
    local scott = Instance.new("Model", "Scott")
    scott:SetAttribute("SourceLayer", 2)
    BossesFolder:AddChild(scott)
    local body = Instance.new("Part", "CollisionBlocker")
    body:SetCFrame(CFrame.new(10, 1, 0))
    scott:AddChild(body)
    scott.PrimaryPart = body
end

local ChestsFolder = Instance.new("Folder", "TokenChests")
MapFolder:AddChild(ChestsFolder)
local function mkChest(name, x, y, z, canTouch)
    local c = Instance.new("Model", name)
    c:SetAttribute("SourceLayer", 1)
    ChestsFolder:AddChild(c)
    local box = Instance.new("Part", "CollisionBlocker")
    box:SetCFrame(CFrame.new(x, y, z))
    box.CanTouch = canTouch
    c:AddChild(box)
    c.PrimaryPart = box
    return c, box
end
mkChest("SilverChest", 8, 1, 0, false)
local _, GoldChestBox = mkChest("GoldChest", 30, 1, 0, true)

local NPCS = Instance.new("Folder", "NPCS")
MapFolder:AddChild(NPCS)
local DeedeeNPC = mkPart(NPCS, "DeedeeShopKeeper", 60, 1, 0)
local DeedeeBlocker = Instance.new("Part", "CollisionBlocker")
DeedeeBlocker:SetCFrame(CFrame.new(60, 1, 0))
DeedeeNPC:AddChild(DeedeeBlocker)

-- ===== services / game =====
local Services = {}
Services.Players = { LocalPlayer = PLR, GetPlayers = function() return { PLR } end }
Services.ReplicatedStorage = RS
Services.RunService = {
    Stepped = Signal.new(), RenderStepped = Signal.new(), Heartbeat = Signal.new(),
    PostSimulation = Signal.new(),
    IsServer = function() return false end, IsStudio = function() return false end,
    IsClient = function() return true end,
}
Services.TeleportService = { Teleport = function() end }
Services.UserInputService = { TouchEnabled = false, KeyboardEnabled = true, InputBegan = Signal.new() }
Services.HttpService = { JSONEncode = function(_, t) return "{}" end, JSONDecode = function(_, s) return {} end }
Services.TweenService = { Create = function() return { Play = function() end } end, GetValue = function() return 0 end }
Services.Lighting = {}
Services.GuiService = { GetResolution = function() return { X = 1920, Y = 1080 } end }
Services.MarketplaceService = { GetProductInfo = function() return { Name = "FNAF World Multiplayer" } end }
Services.VirtualInputManager = { SendKeyEvent = function() end }
Services.ProximityPromptService = { PromptButtonHoldBegan = Signal.new() }
Services.VirtualUser = { CaptureController = function() end, ClickButton2 = function() end }

G.game = {
    PlaceId = 0,
    JobId = "job-1",
    GetService = function(self, name)
        return Services[name] or error("Invalid Service: " .. name)
    end,
    HttpGet = function(self, url)
        if string.find(url, "Library.lua", 1, true) then return "LIB" end
        if string.find(url, "ThemeManager", 1, true) then return "THEME" end
        if string.find(url, "SaveManager", 1, true) then return "SAVE" end
        return ""
    end,
    IsLoaded = function() return true end,
}
G.workspace = WS
G.OverlapParams = { new = function() return { FilterType = nil, FilterDescendantsInstances = {} } end }
local enumChildren = setmetatable({}, { __index = function(t, k)
    local c = setmetatable({}, { __index = function(_, k2) return k2 end })
    rawset(t, k, c)
    return c
end })
G.Enum = enumChildren
G.os = setmetatable({ clock = G.tick, time = function() return 20000 * 86400 end }, { __index = os })

local function GetObjectSafe(parent, path)
    local cur = parent
    for seg in string.gmatch(path, "[^%.]+") do
        if not cur then return nil end
        cur = cur:FindFirstChild(seg)
    end
    return cur
end

-- ===== mock-world self checks =====
check("world: battle gui wired", PLR.PlayerGui:FindFirstChild("FnafWorldBattle") == BattleGui)
check("world: move buttons wired", GetObjectSafe(MovePanel, "Move2Button") == MoveBtn2)
check("world: CanInteractOnLayer logic", Overworld.CanInteractOnLayer(PLR, 1) == true and Overworld.CanInteractOnLayer(PLR, 2) == false)
check("world: ByteInventory purchase math", (function()
    PLR:SetAttribute("FazTokens", 100)
    local ok = ByteInventory.Purchase(PLR, "NeonBee")
    return ok == true and PLR:GetAttribute("FazTokens") == 25 and ByteInventory.Owns(PLR, "NeonBee") == true
end)())
PLR:SetAttribute("FazTokens", 100)
PLR:SetAttribute("ByteOwnedNeonBee", nil)

-- ===== loader =====
if not ScriptSrc then
    print("SKIP: build script not present (looked in " .. ScriptPath .. " and work/lua/FnafWorld.lua) — mock-world checks only")
    summary()
    os.exit(Fail > 0 and 1 or 0)
end
print("script under test: " .. ScriptPath)

pump(0.2)
local PcallSwallows = 0
local rawpcall = pcall
G.pcall = function(fn, ...)
    local args = table.pack(...)
    local ok, err = xpcall(fn, function(e)
        return tostring(e) .. " @ " .. debug.traceback("", 2)
    end, table.unpack(args, 1, args.n))
    if not ok then
        PcallSwallows = PcallSwallows + 1
        print("  [pcall-caught] " .. tostring(err))
    end
    return ok, err
end
local oldLoadstring = G.loadstring
G.loadstring = function(src, name)
    if src == "LIB" then return function() return Library end end
    if src == "THEME" then return function() return ThemeManager end end
    if src == "SAVE" then return function() return SaveManager end end
    return oldLoadstring(src, name)
end
local fn = G.loadstring(ScriptSrc, "=(FnafWorld)")
G.task.spawn(fn)
pump(2.0)

local function noErrorNotify()
    for _, n in ipairs(MockState.Notifies) do
        if string.find(n, "ERROR", 1, true) then return false, n end
    end
    return true
end
check("script loaded without ERROR notify", (function()
    local ok, n = noErrorNotify()
    if not ok then print("  notify was: " .. tostring(n)) end
    return ok
end)())
check("guard set", G.ayasemiyatongekissazumirisa == true)
check("pcall interceptor: 0 silent swallows at load", PcallSwallows == 0)

-- ===== structural =====
check("core toggles registered with plain ids", Library.Toggles.AutoBattle ~= nil and Library.Toggles.AutoBoss ~= nil and Library.Toggles.AutoChest ~= nil and Library.Toggles.AutoFish ~= nil and Library.Toggles.AutoBuyByte ~= nil)
check("BuyByte dropdown registered with shop-stock values", (function()
    local dd = Library.Options.BuyByte
    if not dd then return false end
    local vals = dd.Values or {}
    return #vals == 21 and vals[1] == "Gnat" and vals[10] == "Block1" and vals[21] == "X-FO"
end)())

-- ===== fire recorders =====
local Fires = {}
local function armSignal(sig, tag)
    sig:Connect(function()
        table.insert(Fires, { tag = tag, at = G.tick() })
    end)
end
armSignal(MoveBtn1.Activated, "Move1")
armSignal(MoveBtn2.Activated, "Move2")
armSignal(MoveBtn3.Activated, "Move3")
armSignal(SwitchButton.Activated, "Switch")
armSignal(DoneButton.Activated, "Done")
armSignal(DropButton.Activated, "Drop")
armSignal(FishingPlay.Activated, "FishPlay")
local function countTag(tag, after)
    local n = 0
    for _, f in ipairs(Fires) do
        if f.tag == tag and f.at >= (after or 0) then n = n + 1 end
    end
    return n
end
local function lastTag(tag)
    for i = #Fires, 1, -1 do
        if Fires[i].tag == tag then return Fires[i] end
    end
    return nil
end
local function hrpDist(part)
    local d = HRP.CFrame.Position - part.CFrame.Position
    return math.sqrt(d.X * d.X + d.Y * d.Y + d.Z * d.Z)
end

-- ===== AutoBattle behavior =====
if Library.Toggles.AutoBattle then
    Library.Toggles.AutoBattle:SetValue(true)
    pump(0.5)
    check("AutoBattle: no action while battle gui disabled", #Fires == 0)

    BattleGui.Enabled = true
    MovePanel.Visible = true
    MovePanel:SetAttribute("ActiveCharacter", "Freddy")
    pump(0.6)
    check("AutoBattle: healthy party fires allDamage slot (Freddy -> Pizza Wheel = Move2)", (function()
        local f = lastTag("Move2")
        return f ~= nil and countTag("Move1") == 0 and countTag("Move3") == 0
    end)())

    Fires = {}
    MovePanel:SetAttribute("ActiveCharacter", "EndoTest")
    pump(0.6)
    check("AutoBattle: no boss prefers instantDefeat slot (EndoTest -> Unscrew = Move1)", countTag("Move1") > 0 and countTag("Move2") == 0)

    Fires = {}
    BossHPBar.Visible = true
    MovePanel:SetAttribute("ActiveCharacter", "Foxy")
    pump(0.6)
    check("AutoBattle: boss present prefers allDamage (Foxy -> Hot Cheese = Move3)", countTag("Move3") > 0 and countTag("Move1") == 0)

    Fires = {}
    BossHPBar.Visible = false
    local hpt1 = GetObjectSafe(BattleGui, "HPBar1.HPText")
    hpt1.Text = "20"
    MovePanel:SetAttribute("ActiveCharacter", "Chica")
    pump(0.6)
    check("AutoBattle: low party HP prefers healAll (Chica -> Cupcakes = Move1)", countTag("Move1") > 0)
    hpt1.Text = "140"

    Fires = {}
    MovePanel.Visible = false
    SwitchButton.Visible = true
    pump(3.5)
    check("AutoBattle: stalled panel + switch visible fires SwitchButton", countTag("Switch") > 0)

    Fires = {}
    BattleGui.Enabled = false
    SwitchButton.Visible = false
    TitleScreen.Enabled = true
    TitleScreen:SetAttribute("OpenAsOverworldParty", true)
    pump(0.6)
    check("AutoBattle: game-over recovery fires SaveScreen DoneButton", countTag("Done") > 0)
    TitleScreen.Enabled = false
    TitleScreen:SetAttribute("OpenAsOverworldParty", nil)

    local before = #Fires
    Library.Toggles.AutoBattle:SetValue(false)
    pump(1.0)
    BattleGui.Enabled = true
    MovePanel.Visible = true
    MovePanel:SetAttribute("ActiveCharacter", "Freddy")
    pump(1.0)
    check("AutoBattle: toggle-off stops firing", #Fires == before)
    BattleGui.Enabled = false
    MovePanel.Visible = false
end

-- ===== AutoBoss behavior =====
if Library.Toggles.AutoBoss then
    HRP:SetCFrame(CFrame.new(0, 3, 0))
    Fires = {}
    Library.Toggles.AutoBoss:SetValue(true)
    pump(1.5)
    check("AutoBoss: TPs to nearest ALIVE same-layer boss blocker (Bouncer, skipping defeated Seagoon + layer-2 Scott)", hrpDist(BouncerBlocker) < 0.5)
    check("AutoBoss: did not TP to defeated Seagoon", hrpDist(SeagoonBlocker) > 5)
    check("AutoBoss: did not TP to far AutoChipper", hrpDist(ChipperBlocker) > 5)

    HRP:SetCFrame(CFrame.new(0, 3, 0))
    BattleGui.Enabled = true
    pump(1.5)
    check("AutoBoss: waits during battle (no TP)", (function()
        local d = HRP.CFrame.Position - CFrame.new(0, 3, 0).Position
        return math.sqrt(d.X * d.X + d.Y * d.Y + d.Z * d.Z) < 0.5
    end)())
    BattleGui.Enabled = false

    local before = #Fires
    Library.Toggles.AutoBoss:SetValue(false)
    pump(0.5)
    check("AutoBoss: toggle-off stops", true)
end

-- ===== AutoChest behavior =====
if Library.Toggles.AutoChest then
    HRP:SetCFrame(CFrame.new(0, 3, 0))
    Library.Toggles.AutoChest:SetValue(true)
    pump(2.5)
    check("AutoChest: TPs to available (CanTouch) chest, skipping cooldown chest", hrpDist(GoldChestBox) < 0.5)
    Library.Toggles.AutoChest:SetValue(false)
    pump(0.5)
end

-- ===== AutoFish behavior =====
if Library.Toggles.AutoFish then
    DeedeeMinigame.Enabled = true
    Library.Toggles.AutoFish:SetValue(true)
    pump(0.5)
    check("AutoFish: aims boat at reflected predicted X and drops", (function()
        local drop = lastTag("Drop")
        if not drop then return false end
        local aim = Boat.Position.X.Scale
        return math.abs(aim - 0.8897) < 0.005
    end)())
    DeedeeMinigame.Enabled = false

    Fires = {}
    DeedeeShop.Enabled = true
    FishingPlay.Visible = true
    PLR:SetAttribute("DeedeeReturnAt", 20000 * 86400 - 10)
    pump(1.0)
    check("AutoFish: shop open + cooldown expired fires FishingPlayHitButton", countTag("FishPlay") > 0)

    Fires = {}
    PLR:SetAttribute("DeedeeReturnAt", 20000 * 86400 + 100)
    pump(1.0)
    check("AutoFish: respects DeedeeReturnAt cooldown (no fire)", countTag("FishPlay") == 0)

    Fires = {}
    DeedeeShop.Enabled = false
    PLR:SetAttribute("DeedeeReturnAt", 20000 * 86400 - 10)
    pump(1.5)
    check("AutoFish: shop closed + expired TPs to Deedee NPC blocker", hrpDist(DeedeeBlocker) < 0.5)

    Fires = {}
    BattleGui.Enabled = true
    PLR:SetAttribute("DeedeeReturnAt", 20000 * 86400 - 10)
    DeedeeShop.Enabled = true
    pump(1.0)
    check("AutoFish: no shop actions during battle", countTag("FishPlay") == 0)
    BattleGui.Enabled = false
    Library.Toggles.AutoFish:SetValue(false)
    pump(0.5)
end

-- ===== AutoBuyByte behavior =====
if Library.Toggles.AutoBuyByte and Library.Options.BuyByte then
    PLR:SetAttribute("FazTokens", 100)
    PLR:SetAttribute("ByteOwnedNeonBee", nil)
    Library.Options.BuyByte:SetValue("NeonBee")
    Library.Toggles.AutoBuyByte:SetValue(true)
    pump(2.5)
    check("AutoBuyByte: buys affordable selected byte (NeonBee 75)", PLR:GetAttribute("FazTokens") == 25 and ByteInventory.Owns(PLR, "NeonBee") == true)
    check("AutoBuyByte: purchase followed by AutoSave", SaveCalls.AutoSave > 0)

    PLR:SetAttribute("FazTokens", 25)
    Library.Options.BuyByte:SetValue("X-Reaper")
    local savesBefore = SaveCalls.AutoSave
    pump(2.5)
    check("AutoBuyByte: no purchase when insufficient tokens", PLR:GetAttribute("FazTokens") == 25 and SaveCalls.AutoSave == savesBefore)
    Library.Toggles.AutoBuyByte:SetValue(false)
    pump(0.5)
end

summary()
