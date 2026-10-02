-- harness_lib.lua — GENERIC mock-harness prelude for Roblox script testing under real Lua 5.4.
-- Extracted from the SCPINC harness (game-independent layer) by glm2 2026-10-01.
-- USAGE: cp shared/tools/harness_lib.lua work-lua/<game>_harness.lua, then append game mocks
-- + checks BELOW the marker line. Run: lua5.4 work-lua/<game>_harness.lua.
-- Provides: virtual-clock scheduler (task.wait/delay/spawn/defer/cancel + pump(t)), Instance mock
-- (LIST children, attrs, signals, FindFirstChild[WhichIsA|OfClass], GetPivot, CFrame), Vector3,
-- CFrame.lookAt, Signal, Linoria Library/ThemeManager/SaveManager mocks (Toggles/Options registries,
-- OnChanged/SetValue semantics), mock loadstring with env G, record/countCalls/findCall test helpers,
-- Luau shims (table.clone/find/create/freeze, math.clamp, string.split on the string metatable).
-- The built-in smoke checks at the bottom verify the prelude; keep them until your game checks exist.
-- GOTCHAS (bit previous sessions): (1) register children with parent:AddChild(child) — plain
-- `child.Parent = parent` does NOT populate _children, so FindFirstChild*/GetChildren silently
-- see nothing; (2) values captured into a result table are snapshots — expose getters when a
-- check must observe later mutation; (3) grep the Instance mock for any *WhichIsA/OfClass gap
-- before debugging silent pcall failures in the script-under-test.

local Pass, Fail = 0, 0
local Failures = {}
local function check(name, cond)
    if cond then
        Pass = Pass + 1
    else
        Fail = Fail + 1
        table.insert(Failures, name)
        print("FAIL: " .. name)
    end
end

local G = {}

local function tclone(t)
    local out = {}
    for k, v in pairs(t) do
        out[k] = v
    end
    return out
end
if not table.clone then
    table.clone = tclone
end
if not table.create then
    table.create = function(n, v)
        local out = {}
        for i = 1, n do
            out[i] = v
        end
        return out
    end
end
if not table.freeze then
    table.freeze = function(t)
        return t
    end
end
if not table.find then
    table.find = function(t, v)
        for i, x in ipairs(t) do
            if x == v then
                return i
            end
        end
        return nil
    end
end

G.getgenv = function()
    return G
end

local Sched = { now = 100000, waiting = {}, delayed = {}, cancelled = {} }
local function spawnCo(fn, ...)
    local co = coroutine.create(fn)
    local ok, res = coroutine.resume(co, ...)
    if not ok then
        error(res)
    end
    if coroutine.status(co) ~= "dead" and type(res) == "number" then
        Sched.waiting[co] = res
    end
    return co
end
G.task = {
    spawn = function(fn, ...)
        return spawnCo(fn, ...)
    end,
    wait = function(n)
        local wake = Sched.now + (tonumber(n) or 1 / 30)
        return coroutine.yield(wake)
    end,
    delay = function(n, fn, ...)
        table.insert(Sched.delayed, { at = Sched.now + (tonumber(n) or 0), fn = fn, args = { ... } })
    end,
    defer = function(fn, ...)
        table.insert(Sched.delayed, { at = Sched.now, fn = fn, args = { ... } })
    end,
    cancel = function(co)
        Sched.cancelled[co] = true
        Sched.waiting[co] = nil
    end,
}
local function pump(seconds)
    local target = Sched.now + seconds
    while Sched.now < target do
        Sched.now = math.min(Sched.now + 0.05, target)
        local due = {}
        for co, wake in pairs(Sched.waiting) do
            if wake <= Sched.now and not Sched.cancelled[co] then
                table.insert(due, co)
            end
        end
        table.sort(due, function(a, b)
            return tostring(a) < tostring(b)
        end)
        for _, co in ipairs(due) do
            Sched.waiting[co] = nil
            if not Sched.cancelled[co] then
                local ok, res = coroutine.resume(co)
                if not ok then
                    error(res)
                end
                if coroutine.status(co) ~= "dead" and type(res) == "number" then
                    Sched.waiting[co] = res
                end
            end
        end
        local i = 1
        while i <= #Sched.delayed do
            local d = Sched.delayed[i]
            if d.at <= Sched.now then
                table.remove(Sched.delayed, i)
                local fn = d.fn
                local args = d.args
                spawnCo(function()
                    fn(table.unpack(args))
                end)
            else
                i = i + 1
            end
        end
    end
end
G.tick = function()
    return Sched.now
end

G.math = tclone(math)
G.math.clamp = function(v, lo, hi)
    if v < lo then
        return lo
    end
    if v > hi then
        return hi
    end
    return v
end

local Vector3
do
    local vmt = {}
    local function mk(x, y, z)
        return setmetatable({ X = x, Y = y, Z = z, Magnitude = math.sqrt(x * x + y * y + z * z) }, vmt)
    end
    vmt.__sub = function(a, b)
        return mk(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
    end
    vmt.__add = function(a, b)
        return mk(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
    end
    vmt.__mul = function(a, b)
        if type(a) == "number" then
            return mk(a * b.X, a * b.Y, a * b.Z)
        end
        return mk(a.X * b, a.Y * b, a.Z * b)
    end
    vmt.__tostring = function(a)
        return string.format("%.2f, %.2f, %.2f", a.X, a.Y, a.Z)
    end
    Vector3 = { new = mk, zero = mk(0, 0, 0) }
end
G.Vector3 = Vector3

local CFrame
do
    local cmt = {}
    local function cf(pos)
        return setmetatable({ Position = pos }, cmt)
    end
    cmt.__mul = function(a, b)
        if getmetatable(b) == cmt then
            return cf(a.Position + b.Position)
        end
        return a
    end
    cmt.__sub = function(a, b)
        if getmetatable(b) == cmt then
            return cf(a.Position - b.Position)
        end
        return a
    end
    CFrame = {
        new = function(a, b, c)
            if type(a) == "table" then
                return cf(Vector3.new(a.X, a.Y, a.Z))
            end
            return cf(Vector3.new(a or 0, b or 0, c or 0))
        end,
        lookAt = function(from, to)
            return cf(Vector3.new(from.X, from.Y, from.Z))
        end,
        Angles = function()
            return cf(Vector3.new(0, 0, 0))
        end,
    }
end
G.CFrame = CFrame
G.Color3 = {
    new = function()
        return { r = 1, g = 1, b = 1 }
    end,
    fromRGB = function()
        return { r = 1, g = 1, b = 1 }
    end,
}

local Signal
do
    Signal = {}
    Signal.__index = Signal
    function Signal.new()
        return setmetatable({ _handlers = {} }, Signal)
    end
    function Signal:Connect(fn)
        local conn = { Connected = true, _fn = fn }
        function conn:Disconnect()
            self.Connected = false
        end
        table.insert(self._handlers, conn)
        return conn
    end
    Signal.Once = Signal.Connect
    function Signal:Wait()
        G.task.wait(0.05)
        return 0.03
    end
    function Signal:Fire(...)
        local args = { ... }
        for _, conn in ipairs(self._handlers) do
            if conn.Connected then
                spawnCo(function()
                    conn._fn(table.unpack(args))
                end)
            end
        end
    end
end

local InstanceClassMap = {
    Part = { "Part", "BasePart" },
    SpawnLocation = { "SpawnLocation", "BasePart" },
    MeshPart = { "MeshPart", "BasePart" },
    UnionOperation = { "UnionOperation", "BasePart" },
    Model = { "Model" },
    Folder = { "Folder" },
    Tool = { "Tool" },
    ModuleScript = { "ModuleScript" },
    LocalScript = { "LocalScript" },
    Script = { "Script" },
    RemoteEvent = { "RemoteEvent" },
    RemoteFunction = { "RemoteFunction" },
    Workspace = { "Workspace" },
    Player = { "Player" },
    Backpack = { "Backpack" },
    Humanoid = { "Humanoid" },
    Camera = { "Camera" },
    ProximityPrompt = { "ProximityPrompt" },
    Configuration = { "Configuration" },
}
local Instance
do
    local imt = {}
    Instance = { _all = {} }
    function Instance.new(className, name)
        local obj = {
            ClassName = className,
            Name = name or className,
            _children = {},
            _attrs = {},
            _signals = {},
            Parent = nil,
        }
        setmetatable(obj, {
            __index = function(t, k)
                if k == "CFrame" and rawget(t, "_cframe") then
                    return rawget(t, "_cframe")
                end
                if k == "Position" and rawget(t, "_cframe") then
                    return rawget(t, "_cframe").Position
                end
                return imt[k]
            end,
            __newindex = function(t, k, v)
                if k == "CFrame" then
                    rawset(t, "_cframe", v)
                elseif k == "Position" then
                    rawset(t, "_cframe", CFrame.new(v))
                else
                    rawset(t, k, v)
                end
            end,
        })
        table.insert(Instance._all, obj)
        return obj
    end
    function imt:IsA(cls)
        local set = InstanceClassMap[self.ClassName]
        return set ~= nil and table.find(set, cls) ~= nil
    end
    function imt:FindFirstChild(name)
        for _, c in ipairs(self._children) do
            if c.Name == name then
                return c
            end
        end
        return nil
    end
    function imt:FindFirstChildWhichIsA(cls)
        for _, c in ipairs(self._children) do
            if c:IsA(cls) then
                return c
            end
        end
        return nil
    end
    function imt:FindFirstChildOfClass(cls)
        for _, c in ipairs(self._children) do
            if c.ClassName == cls then
                return c
            end
        end
        return nil
    end
    function imt:FindFirstAncestorWhichIsA(cls)
        local p = self.Parent
        while p do
            if p:IsA(cls) then
                return p
            end
            p = p.Parent
        end
        return nil
    end
    function imt:WaitForChild(name, t)
        local c = self:FindFirstChild(name)
        if not c then
            warn("WaitForChild timeout: " .. tostring(name))
        end
        return c
    end
    function imt:GetChildren()
        return table.clone(self._children)
    end
    function imt:GetDescendants()
        local out = {}
        local function walk(parent)
            for _, c in ipairs(parent._children) do
                table.insert(out, c)
                walk(c)
            end
        end
        walk(self)
        return out
    end
    function imt:GetAttribute(k)
        return self._attrs[k]
    end
    function imt:SetAttribute(k, v)
        self._attrs[k] = v
        local sig = self._signals["attr:" .. k]
        if sig then
            sig:Fire()
        end
    end
    function imt:GetAttributeChangedSignal(k)
        if not self._signals["attr:" .. k] then
            self._signals["attr:" .. k] = Signal.new()
        end
        return self._signals["attr:" .. k]
    end
    function imt:GetPropertyChangedSignal(k)
        if not self._signals["prop:" .. k] then
            self._signals["prop:" .. k] = Signal.new()
        end
        return self._signals["prop:" .. k]
    end
    function imt:GetPivot()
        if rawget(self, "_cframe") then
            return rawget(self, "_cframe")
        end
        if self.PrimaryPart then
            return self.PrimaryPart._cframe
        end
        local part = self:FindFirstChildWhichIsA("BasePart")
        return part and part._cframe or CFrame.new(0, 0, 0)
    end
    function imt:PivotTo(cf)
        rawset(self, "_cframe", cf)
    end
    function imt:Destroy()
        if self.Parent then
            local siblings = self.Parent._children
            for i, c in ipairs(siblings) do
                if c == self then
                    table.remove(siblings, i)
                    break
                end
            end
        end
        self.Parent = nil
    end
    function imt:AddChild(child)
        child.Parent = self
        table.insert(self._children, child)
        return child
    end
    function imt:SetCFrame(cf)
        rawset(self, "_cframe", cf)
    end
end
G.Instance = Instance

G.string = tclone(string)
local function strsplit(s, sep)
    local out = {}
    local pattern = "([^" .. sep .. "]+)"
    for part in string.gmatch(s, pattern) do
        table.insert(out, part)
    end
    return out
end
G.string.split = strsplit
local smt = getmetatable("")
if smt and smt.__index then
    smt.__index.split = strsplit
end
G.table = table
G.coroutine = coroutine
G.unpack = table.unpack or unpack
G.os = os
G.warn = warn
G.print = print
G.tostring = tostring
G.tonumber = tonumber
G.type = type
G.pcall = pcall
G.xpcall = xpcall
G.assert = assert
G.error = error
G.select = select
G.ipairs = ipairs
G.pairs = pairs
G.next = next
G.setmetatable = setmetatable
G.getmetatable = getmetatable
G.rawset = rawset
G.rawequal = rawequal
G.typeof = function(v)
    local t = type(v)
    if t == "table" then
        if rawget(v, "ClassName") then
            return "Instance"
        end
        if v.X and v.Y and v.Z then
            return "Vector3"
        end
        if v.Position then
            return "CFrame"
        end
    end
    if t == "thread" then
        return "thread"
    end
    return t
end

local MockState = { Notifies = {}, AllLabels = {}, Buttons = {}, Windows = 0, Tabs = {} }
local Library
do
    local function newElement(idx, kind, info)
        local el = {
            Idx = idx,
            Kind = kind,
            Value = nil,
            _handlers = {},
            _visible = true,
        }
        function el:OnChanged(fn)
            table.insert(self._handlers, fn)
            return self
        end
        function el:SetValue(v)
            self.Value = v
            for _, fn in ipairs(self._handlers) do
                fn(v)
            end
        end
        function el:SetValues(list)
            self.Values = table.clone(list)
        end
        function el:SetVisible(v)
            self._visible = v
        end
        function el:SetText(t)
            self.Text = t
        end
        return el
    end
    Library = {
        Toggles = {},
        Options = {},
        Labels = {},
        Unloaded = false,
        KeybindFrame = { Visible = false },
        NotifySide = "Left",
        ShowToggleFrameInKeybinds = true,
        ShowCustomCursor = true,
    }
    function Library:Notify(msg, t)
        table.insert(MockState.Notifies, tostring(msg))
    end
    function Library:SetDPIScale(n) end
    function Library:Unload()
        self.Unloaded = true
    end
    function Library:SetWatermark() end
    local function makeGroupbox(name)
        local gb = { Name = name }
        function gb:AddToggle(idx, info)
            info = info or {}
            local el = newElement(idx, "Toggle", info)
            el.Value = info.Default or false
            el.Text = info.Text
            Library.Toggles[idx] = el
            return el
        end
        function gb:AddDropdown(idx, info)
            info = info or {}
            local el = newElement(idx, "Dropdown", info)
            el.Values = table.clone(info.Values or {})
            if info.Multi then
                el.Value = table.clone(info.Default or {})
            else
                el.Value = info.Default
            end
            el.Multi = info.Multi
            el.Text = info.Text
            Library.Options[idx] = el
            return el
        end
        function gb:AddSlider(idx, info)
            info = info or {}
            local el = newElement(idx, "Slider", info)
            el.Value = info.Default or info.Min or 0
            el.Text = info.Text
            Library.Options[idx] = el
            return el
        end
        function gb:AddButton(a, b)
            local info = type(a) == "table" and a or { Text = a, Func = b }
            table.insert(MockState.Buttons, info)
            return { Func = info.Func }
        end
        function gb:AddLabel(text, wrap)
            local el = { Text = tostring(text), Kind = "Label" }
            function el:SetText(t)
                self.Text = t
            end
            function el:AddKeyPicker(idx, info)
                local el2 = newElement(idx, "KeyPicker", info or {})
                el2.Value = (info and info.Default) or "None"
                Library.Options[idx] = el2
                return el2
            end
            table.insert(MockState.AllLabels, el)
            return el
        end
        function gb:AddDivider() end
        function gb:AddKeyPicker(idx, info)
            local el = newElement(idx, "KeyPicker", info or {})
            el.Value = (info and info.Default) or "None"
            Library.Options[idx] = el
            return el
        end
        function gb:AddInput(idx, info)
            local el = newElement(idx, "Input", info or {})
            el.Value = (info and info.Default) or ""
            Library.Options[idx] = el
            return el
        end
        return gb
    end
    local makeTabInner
    local function boxmaker()
        local box = {}
        function box:AddTab(n)
            return makeTabInner(n)
        end
        return box
    end
    makeTabInner = function(name)
        local tab = { Name = name }
        table.insert(MockState.Tabs, name)
        function tab:AddLeftGroupbox(n)
            return makeGroupbox(n)
        end
        function tab:AddRightGroupbox(n)
            return makeGroupbox(n)
        end
        function tab:AddGroupbox(n)
            return makeGroupbox(n)
        end
        function tab:AddLeftTabbox()
            return boxmaker()
        end
        function tab:AddRightTabbox()
            return boxmaker()
        end
        function tab:AddTabbox()
            return boxmaker()
        end
        function tab:AddToggle(idx, info)
            local gb = makeGroupbox(name)
            return gb:AddToggle(idx, info)
        end
        function tab:AddDivider() end
        function tab:AddLabel(text, wrap)
            local gb = makeGroupbox(name)
            return gb:AddLabel(text, wrap)
        end
        return tab
    end
    function Library:CreateWindow(info)
        MockState.Windows = MockState.Windows + 1
        local win = {}
        function win:AddTab(n)
            return makeTabInner(n)
        end
        function win:SetWindowTitle() end
        function win:AddDialog() end
        return win
    end
    local function makeTab(name)
        return makeTabInner(name)
    end
end
local ThemeManager = {}
function ThemeManager:SetLibrary() end
function ThemeManager:SetFolder() end
function ThemeManager:ApplyToTab() end
local SaveManager = {}
function SaveManager:SetLibrary() end
function SaveManager:IgnoreThemeSettings() end
function SaveManager:SetFolder(f)
    SaveManager.Folder = f
end
function SaveManager:BuildConfigSection() end
function SaveManager:LoadAutoloadConfig() end
function SaveManager:SetLoadingOrder() end
G.__LinoriaLibrary = function()
    return Library
end
G.__ThemeManagerLoader = function()
    return ThemeManager
end
G.__SaveManagerLoader = function()
    return SaveManager
end

G.loadstring = function(src, name)
    local f, err = load(src, name or "=(loadstring)", "t", G)
    if not f then
        error("mock loadstring: " .. tostring(err))
    end
    return f
end

local Calls = {}
local function record(entry)
    table.insert(Calls, entry)
end
local function countCalls(fn, pred)
    local n = 0
    for _, c in ipairs(Calls) do
        if c.fn == fn then
            if not pred or pred(c) then
                n = n + 1
            end
        end
    end
    return n
end
local function findCall(fn, pred)
    for _, c in ipairs(Calls) do
        if c.fn == fn and (not pred or pred(c)) then
            return c
        end
    end
    return nil
end

-- ####################################################################
-- ===== APPEND GAME MOCKS + TESTS BELOW THIS LINE =====================
-- (game tree: workspace parts, RS modules, remotes/mock server, ClientState-style state machines)
-- Then replace the smoke block below with your game checks (keep a summary() call at the end).
-- ####################################################################

local function summary()
    print(string.format("harness_lib smoke: %d pass / %d fail", Pass, Fail))
    if Fail > 0 then
        for _, f in ipairs(Failures) do
            print("  failed: " .. f)
        end
        os.exit(1)
    end
end

local Services = {}
local RS = Instance.new("Folder", "ReplicatedStorage")
local WS = Instance.new("Workspace", "Workspace")
local PLR = Instance.new("Player", "Tester")
PLR.UserId = 42
PLR.Idled = Signal.new()
local charRoot = Instance.new("Part", "HumanoidRootPart")
charRoot.CFrame = CFrame.new(Vector3.new(0, 5, 0))
local humanoid = Instance.new("Humanoid", "Humanoid")
local character = Instance.new("Model", "Char")
character:AddChild(charRoot)
character:AddChild(humanoid)
character.PrimaryPart = charRoot
PLR.Character = character

local ModuleRegistry = {}
G.require = function(obj)
    if ModuleRegistry[obj] then
        return ModuleRegistry[obj]
    end
    error("mock require: unregistered module " .. tostring(obj and obj.Name))
end

local function makeRemote(name, className)
    local r = Instance.new(className, name)
    r.Fires = {}
    r.Invokes = {}
    function r:FireServer(...)
        table.insert(self.Fires, { ... })
    end
    function r:InvokeServer(...)
        table.insert(self.Invokes, { ... })
        return { ok = true }
    end
    return r
end

local Packages = Instance.new("Folder", "Packages")
RS:AddChild(Packages)
local Index = Instance.new("Folder", "_Index")
Packages:AddChild(Index)
local nw = Instance.new("Folder", "leifstout_networker@0.3.1")
Index:AddChild(nw)
local netw = Instance.new("Folder", "networker")
nw:AddChild(netw)
local rem = Instance.new("Folder", "_remotes")
netw:AddChild(rem)
local CombatEvent = nil
local RFs = {}
for _, spec in ipairs({ "Ascension", "Evolution", "Shop", "Roll", "Rebirth" }) do
    local folder = Instance.new("Folder", spec)
    rem:AddChild(folder)
    local r = makeRemote("RemoteFunction", "RemoteFunction")
    folder:AddChild(r)
    RFs[spec] = r
end
do
    local folder = Instance.new("Folder", "Combat")
    rem:AddChild(folder)
    CombatEvent = makeRemote("RemoteEvent", "RemoteEvent")
    folder:AddChild(CombatEvent)
end

local SourceRoot = Instance.new("Folder", "Source")
RS:AddChild(SourceRoot)
local Features = Instance.new("Folder", "Features")
SourceRoot:AddChild(Features)
local CombatFolder = Instance.new("Folder", "Combat")
Features:AddChild(CombatFolder)
local PlayerDataFolder = Instance.new("Folder", "PlayerData")
Features:AddChild(PlayerDataFolder)
local CombatClientModule = Instance.new("ModuleScript", "CombatClient")
CombatFolder:AddChild(CombatClientModule)
local PlayerDataClientModule = Instance.new("ModuleScript", "PlayerDataClient")
PlayerDataFolder:AddChild(PlayerDataClientModule)

local CombatVisuals = Instance.new("Folder", "CombatVisuals")
WS:AddChild(CombatVisuals)
local function addEnemy(uid, x)
    local p = Instance.new("Part", "Enemy_" .. uid)
    p.CFrame = CFrame.new(Vector3.new(x, 5, 0))
    CombatVisuals:AddChild(p)
    return p
end
local enemyA = addEnemy("e-42", 5)
local enemyB = addEnemy("e-77", 50)
local EnemyRegistry = {
    ["e-42"] = { model = enemyA },
    ["e-77"] = { model = enemyB },
}
ModuleRegistry[CombatClientModule] = {
    getEnemyModels = function(self)
        return EnemyRegistry
    end,
}
ModuleRegistry[PlayerDataClientModule] = {
    get = function(self)
        return { equipped = { [1] = "sword-uid-1" }, inventory = { ["sword-uid-1"] = { id = "b" } } }
    end,
}

local oldLoadstring = G.loadstring
G.loadstring = function(src, name)
    if src == "LIB" then return function() return Library end end
    if src == "THEME" then return function() return ThemeManager end end
    if src == "SAVE" then return function() return SaveManager end end
    return oldLoadstring(src, name)
end

Services.Players = { LocalPlayer = PLR, GetPlayerFromCharacter = function() return nil end }
Services.ReplicatedStorage = RS
Services.RunService = { Stepped = Signal.new(), Heartbeat = Signal.new(), RenderStepped = Signal.new(), IsServer = function() return false end, IsClient = function() return true end, Set3dRenderingEnabled = function() end }
Services.HttpService = { GenerateGUID = function() return "g1" end, JSONEncode = function() return "{}" end, JSONDecode = function() return {} end }
Services.GuiService = { SelectedObject = nil, ErrorMessageChanged = Signal.new() }
Services.TeleportService = { Teleport = function() end, TeleportToPlaceInstance = function() end }
Services.MarketplaceService = { GetProductInfo = function() return { Name = "Sword RNG X" } end }
Services.UserInputService = { TouchEnabled = false, KeyboardEnabled = true }
Services.VirtualUser = { CaptureController = function() end, ClickButton2 = function() end }
Services.Lighting = { GlobalShadows = true, FogEnd = 1, Brightness = 1, ClockTime = 14, GetChildren = function() return {} end }
Services.ProximityPromptService = { PromptButtonHoldBegan = Signal.new() }
Services.VirtualInputManager = { SendKeyEvent = function() end }
Services.CollectionService = { GetTagged = function() return {} end }
Services.TweenService = { Create = function() return { Play = function() end } end, GetValue = function() return 0 end }

G.game = {
    PlaceId = 123, JobId = "j",
    GetService = function(self, name) return Services[name] or error("Invalid Service: " .. tostring(name)) end,
    HttpGet = function(self, url)
        if string.find(url, "Library.lua", 1, true) then return "LIB" end
        if string.find(url, "ThemeManager", 1, true) then return "THEME" end
        if string.find(url, "SaveManager", 1, true) then return "SAVE" end
        return ""
    end,
    IsLoaded = function() return true end,
}
G.workspace = WS
G.getconnections = nil

local ScriptPath = (arg and arg[1]) or "SwordRNGX.lua"
local ScriptSrc = ""
do
    local f = io.open(ScriptPath, "r")
    if not f then
        print("FAIL: cannot open script " .. tostring(ScriptPath))
        os.exit(1)
    end
    ScriptSrc = f:read("*a")
    f:close()
end

pump(0.2)
local fn = G.loadstring(ScriptSrc, "=(SwordRNGX)")
local okRun, errRun
G.task.spawn(function()
    okRun, errRun = pcall(fn)
end)
pump(0.8)
check("script loads without runtime error", okRun == true)
if not okRun then
    print("SCRIPT RUN ERROR: " .. tostring(errRun))
end
local errNotified = false
for _, n in ipairs(MockState.Notifies) do
    if string.find(n, "ERROR", 1, true) then errNotified = true end
end
check("no ERROR notify at load", not errNotified)
check("all 6 toggles registered via TB_Tabs.Autofarm.T1", Library.Toggles.AutoAttack ~= nil and Library.Toggles.AutoRoll ~= nil and Library.Toggles.AutoRebirth ~= nil and Library.Toggles.AutoAscend ~= nil and Library.Toggles.AutoEvolve ~= nil and Library.Toggles.AutoRestock ~= nil)
check("SaveManager folder per game", SaveManager.Folder == "Yuri/SwordRNGX")

Library.Toggles.AutoAttack:SetValue(true)
pump(1.6)
local fires = #CombatEvent.Fires
check("AutoAttack fires requestHit while on", fires >= 2)
local tuple = CombatEvent.Fires[1]
check("requestHit wire: cmd literal", tuple and tuple[1] == "requestHit")
check("requestHit wire: sword uid from PlayerDataClient equipped", tuple and tuple[2] == "sword-uid-1")
check("requestHit wire: nearest enemy uid from CombatClient registry", tuple and tuple[3] == "e-42")
check("requestHit wire: swing center = HRP position", tuple and tuple[4] and tuple[4].X == 0 and tuple[4].Y == 5 and tuple[4].Z == 0)
local midFires = #CombatEvent.Fires
Library.Toggles.AutoAttack:SetValue(false)
pump(2.0)
check("AutoAttack loop stops after toggle off (Toggles.X.Value guard)", #CombatEvent.Fires == midFires)

EnemyRegistry["e-42"] = nil
enemyA.Parent = nil
Library.Toggles.AutoAttack:SetValue(true)
pump(1.1)
local tuple2 = CombatEvent.Fires[#CombatEvent.Fires]
check("requestHit retargets to remaining enemy (or nil target AOE)", tuple2 and (tuple2[3] == "e-77" or tuple2[3] == nil))
Library.Toggles.AutoAttack:SetValue(false)
pump(0.3)

Library.Toggles.AutoRoll:SetValue(true)
pump(2.5)
check("AutoRoll invokes Roll RF 'roll'", #RFs.Roll.Invokes >= 2 and RFs.Roll.Invokes[1][1] == "roll")
Library.Toggles.AutoRoll:SetValue(false)
pump(0.3)

Library.Toggles.AutoRebirth:SetValue(true)
pump(31)
check("AutoRebirth invokes Rebirth RF 'requestRebirth' (work-then-wait)", #RFs.Rebirth.Invokes >= 2 and RFs.Rebirth.Invokes[1][1] == "requestRebirth")
Library.Toggles.AutoRebirth:SetValue(false)

Library.Toggles.AutoAscend:SetValue(true)
pump(31)
check("AutoAscend invokes Ascension RF 'ascend'", #RFs.Ascension.Invokes >= 2 and RFs.Ascension.Invokes[1][1] == "ascend")
Library.Toggles.AutoAscend:SetValue(false)

Library.Toggles.AutoEvolve:SetValue(true)
pump(31)
check("AutoEvolve invokes Evolution RF 'evolve'", #RFs.Evolution.Invokes >= 2 and RFs.Evolution.Invokes[1][1] == "evolve")
Library.Toggles.AutoEvolve:SetValue(false)

Library.Toggles.AutoRestock:SetValue(true)
pump(61)
check("AutoRestock invokes Shop RF 'restock'", #RFs.Shop.Invokes >= 2 and RFs.Shop.Invokes[1][1] == "restock")
Library.Toggles.AutoRestock:SetValue(false)

for _, n in ipairs(MockState.Notifies) do
    if string.find(n, "ERROR", 1, true) then
        print("ERROR NOTIFY: " .. n)
    end
end

print(string.format("SwordRNGX load harness: %d pass / %d fail", Pass, Fail))
if Fail > 0 then
    for _, f in ipairs(Failures) do
        print("  failed: " .. f)
    end
    os.exit(1)
end
