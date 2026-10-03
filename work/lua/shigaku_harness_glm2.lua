-- shigaku_harness.lua — REAL-LOAD harness: loads work/lua/Shigaku.lua against a mock
-- Shigaku world (BridgeNet2 bridges, Game_Settings/Muscle/GymWeights modules, PlayerScripts
-- Client.Input/Combat/Data/Gym modules, faithful Gym minigame dynamics from the deobf).
-- Run: lua5.4 work/lua/shigaku_harness.lua
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
        local dd = {}
        for i, d in ipairs(Sched.delayed) do
            if d.at <= Sched.now then
                table.insert(dd, i)
            end
        end
        for i = #dd, 1, -1 do
            local d = table.remove(Sched.delayed, dd[i])
            spawnCo(d.fn, table.unpack(d.args))
        end
    end
end
G.tick = function()
    return Sched.now
end

local mathx = tclone(math)
mathx.clamp = function(v, lo, hi)
    if v < lo then
        return lo
    end
    if v > hi then
        return hi
    end
    return v
end
G.math = mathx
G.os = { clock = function()
    return Sched.now
end, time = function()
    return math.floor(Sched.now)
end, date = os.date }

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
    vmt.__unm = function(a)
        return mk(-a.X, -a.Y, -a.Z)
    end
    vmt.__tostring = function(a)
        return string.format("%.2f, %.2f, %.2f", a.X, a.Y, a.Z)
    end
    Vector3 = { new = mk, zero = mk(0, 0, 0) }
    vmt.__index = function(t, k)
        if k == "Unit" then
            local m = t.Magnitude
            if m > 0.0001 then
                return mk(t.X / m, t.Y / m, t.Z / m)
            end
            return mk(0, 0, 0)
        end
        return nil
    end
end
G.Vector3 = Vector3

local CFrame
do
    local cmt = {}
    local function cf(pos)
        return setmetatable({ Position = pos, X = pos.X, Y = pos.Y, Z = pos.Z }, cmt)
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
                local m = imt[k]
                if m ~= nil then
                    return m
                end
                for _, c in ipairs(rawget(t, "_children")) do
                    if c.Name == k then
                        return c
                    end
                end
                return nil
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
G.string = G.string
if G.string.format == nil then
    G.string.format = string.format
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
        function tab:AddDropdown(idx, info)
            local gb = makeGroupbox(name)
            return gb:AddDropdown(idx, info)
        end
        function tab:AddSlider(idx, info)
            local gb = makeGroupbox(name)
            return gb:AddSlider(idx, info)
        end
        function tab:AddInput(idx, info)
            local gb = makeGroupbox(name)
            return gb:AddInput(idx, info)
        end
        function tab:AddButton(a, b)
            local gb = makeGroupbox(name)
            return gb:AddButton(a, b)
        end
        function tab:AddKeyPicker(idx, info)
            local gb = makeGroupbox(name)
            return gb:AddKeyPicker(idx, info)
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

-- ================= SHIGAKU GAME MOCKS =================

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

-- ---- game module tree: RS.Shared.Modules.Global.Libraries.Game_Settings
local Shared = Instance.new("Folder", "Shared")
RS:AddChild(Shared)
local Modules = Instance.new("Folder", "Modules")
Shared:AddChild(Modules)
local Global = Instance.new("Folder", "Global")
Modules:AddChild(Global)
local Libraries = Instance.new("Folder", "Libraries")
Global:AddChild(Libraries)
local SharedModules = Instance.new("Folder", "Shared")
Modules:AddChild(SharedModules)

local GameSettingsModule = Instance.new("ModuleScript", "Game_Settings")
Libraries:AddChild(GameSettingsModule)
local MuscleModule = Instance.new("ModuleScript", "Muscle")
SharedModules:AddChild(MuscleModule)
local GymWeightsModule = Instance.new("ModuleScript", "GymWeights")
SharedModules:AddChild(GymWeightsModule)
local AppearanceModule = Instance.new("ModuleScript", "Appearance")
SharedModules:AddChild(AppearanceModule)

local Packages = Instance.new("Folder", "Packages")
RS:AddChild(Packages)
local BridgeNet2Module = Instance.new("ModuleScript", "BridgeNet2")
Packages:AddChild(BridgeNet2Module)

-- ---- Game_Settings (values from deobf L168432+)
local GymKinds = {
    { Tag = "GymBench", Lift = "Benchpress", Label = "BENCH PRESS", WeightFolder = "BenchWeights", Game = "Balance", CapacityScale = 0.8 },
    { Tag = "GymDeadlift", Lift = "Deadlift", Label = "DEADLIFT", WeightFolder = "DeadliftWeights", Game = "Grip", CapacityScale = 1 },
    { Tag = "GymTreadmill", Lift = "Treadmill", Label = "TREADMILL", Verb = "Run", Game = "Stride", CapacityScale = 1, Speeds = {
        { Id = "walk", Label = "4 MPH", Sub = "WALK", Effort = 0.35 },
        { Id = "jog", Label = "6 MPH", Sub = "JOG", Effort = 0.65 },
        { Id = "run", Label = "8 MPH", Sub = "RUN", Effort = 1 },
        { Id = "sprint", Label = "11 MPH", Sub = "SPRINT", Effort = 1.4 },
    } },
    { Tag = "GymDumbbell", Lift = "Dumbbell", Label = "DUMBBELL", WeightFolder = "DumbbellWeights", Game = "Reps", CapacityScale = 0.25 },
}
ModuleRegistry[GameSettingsModule] = {
    Gym = {
        Bridge = "Gym.Sync",
        Kinds = GymKinds,
        WindedAttribute = "GymWinded",
        Reps = { Enabled = true, Max = 3, BandLow = 1.2, BandHigh = 2, Hold = 0.16, Drift = 0.22, Smooth = 0.5, Start = 1, Warn = 0.45 },
    },
    Zones = {
        Workout = {
            SecondsField = "WorkoutSeconds",
            Tiers = {
                { Name = "Untrained", Seconds = 0, Capacity = 45 },
                { Name = "Minimal", Seconds = 1800, Capacity = 75 },
            },
        },
    },
    Network = {
        CharacterBridge = "Character.Action",
        CharacterRejectBridge = "Character.Reject",
        ClientActions = { "RerollField", "RerollFightStyle" },
    },
}

ModuleRegistry[MuscleModule] = {
    Capacity = function(seconds)
        if (seconds or 0) < 1800 then
            return 45
        end
        return 75
    end,
    Ratio = function(weight, capacity)
        if (weight or 0) <= 0 then
            return 0
        end
        if (capacity or 0) <= 0 then
            return math.huge
        end
        return weight / capacity
    end,
    Band = function(ratio)
        if ratio <= 1 then
            return "Comfortable"
        end
        if ratio <= 1.6 then
            return "Struggle"
        end
        return "Locked"
    end,
}
ModuleRegistry[GymWeightsModule] = {
    List = function(folder)
        local weights = {
            DumbbellWeights = {
                { Name = "5 Dumbbell", Weight = 5 },
                { Name = "15 Dumbbell", Weight = 15 },
                { Name = "50 Dumbbell", Weight = 50 },
            },
        }
        return weights[folder] or {}
    end,
}
ModuleRegistry[AppearanceModule] = {
    holdsRare = function()
        return false
    end,
    styleHoldsRare = function()
        return false
    end,
}

-- ---- BridgeNet2 mock (bridges by name; faithful client-bridge surface)
local Bridges = {}
ModuleRegistry[BridgeNet2Module] = {
    ReferenceBridge = function(name)
        if not Bridges[name] then
            local b = { Name = name, Fires = {}, Handlers = {} }
            function b:Fire(payload)
                table.insert(self.Fires, tclone(payload))
            end
            function b:Connect(fn)
                table.insert(self.Handlers, fn)
                return { Disconnect = function() end }
            end
            function b:InvokeServerAsync(...)
                return { result = true }
            end
            Bridges[name] = b
        end
        return Bridges[name]
    end,
}

-- ---- PlayerScripts.Client tree
local PlayerScripts = Instance.new("Folder", "PlayerScripts")
PLR:AddChild(PlayerScripts)
local ClientScript = Instance.new("LocalScript", "Client")
PlayerScripts:AddChild(ClientScript)
local InputModule = Instance.new("ModuleScript", "Input")
ClientScript:AddChild(InputModule)
local CombatModule = Instance.new("ModuleScript", "Combat")
ClientScript:AddChild(CombatModule)
local DataModule = Instance.new("ModuleScript", "Data")
ClientScript:AddChild(DataModule)
local GymModule = Instance.new("ModuleScript", "Gym")
ClientScript:AddChild(GymModule)

-- Input mock with REAL dispatch semantics (Bind/Fire spawn handlers)
local InputActions = {}
local InputFires = {}
ModuleRegistry[InputModule] = {
    Bind = function(id, began, ended)
        if not InputActions[id] then
            InputActions[id] = {}
        end
        table.insert(InputActions[id], { Began = began, Ended = ended })
        return function() end
    end,
    Fire = function(id, state)
        table.insert(InputFires, { id = id, state = state })
        local list = InputActions[id]
        if list then
            for _, entry in ipairs(tclone(list)) do
                local fn = state and entry.Began or entry.Ended
                if fn then
                    G.task.spawn(fn)
                end
            end
        end
    end,
    IsDown = function(id)
        return false
    end,
    Get = function(id)
        return { Id = id, Key = nil, Pad = nil, Mouse = nil }
    end,
    Cap = function(id)
        return "?"
    end,
}
local CombatState = { active = false }
ModuleRegistry[CombatModule] = {
    IsActive = function()
        return CombatState.active
    end,
}
local DataStore = { WorkoutSeconds = 0 }
ModuleRegistry[DataModule] = {
    Get = function(path)
        return DataStore[path[1]]
    end,
    IsReady = function()
        return true
    end,
}

-- ---- Gym minigame mocks (faithful dynamics from deobf L103818/L104489/L104589/L104737)
local GymState = { game = nil }
local BalanceGame = { active = false, tilt = 0, vel = 0, gust = 0, gustAt = 0, lastFail = 0 }
local StrideGame = { active = false, level = 0, lastSide = 0, lastStepAt = 0 }
local GripGame = { active = false, left = 1, right = 1, leftLock = 0, rightLock = 0 }
local RepsGame = { active = false, level = 0, pace = 1.6, lastTapAt = 0 }

local GymCfg = ModuleRegistry[GameSettingsModule].Gym

local function startGame(name)
    GymState.game = name
    if name == "Balance" then
        BalanceGame.active = true
        BalanceGame.tilt = 0
        BalanceGame.vel = 0
        BalanceGame.gust = 0.6
        BalanceGame.gustAt = Sched.now
    elseif name == "Stride" then
        StrideGame.active = true
        StrideGame.level = 1
        StrideGame.lastSide = 0
        StrideGame.lastStepAt = Sched.now
    elseif name == "Grip" then
        GripGame.active = true
        GripGame.left = 1
        GripGame.right = 1
        GripGame.leftLock = 0
        GripGame.rightLock = 0
    elseif name == "Reps" then
        RepsGame.active = true
        RepsGame.level = 1
        RepsGame.pace = (GymCfg.Reps.BandLow + GymCfg.Reps.BandHigh) / 2
        RepsGame.lastTapAt = Sched.now
    end
end
local function stopGame()
    GymState.game = nil
    BalanceGame.active = false
    StrideGame.active = false
    GripGame.active = false
    RepsGame.active = false
end

ModuleRegistry[GymModule] = {
    IsLifting = function()
        return GymState.game ~= nil
    end,
}

local BalanceMod = {
    Active = function()
        return BalanceGame.active
    end,
    Tilt = function()
        return BalanceGame.tilt
    end,
    Nudge = function(side)
        BalanceGame.vel = BalanceGame.vel + side * 0.7
    end,
}
local StrideMod = {
    Active = function()
        return StrideGame.active
    end,
    Step = function(side)
        if not StrideGame.active then
            return false
        end
        StrideGame.lastStepAt = Sched.now
        if side ~= StrideGame.lastSide then
            StrideGame.lastSide = side
            StrideGame.level = math.min(1, StrideGame.level + 0.06)
            return true
        end
        StrideGame.level = math.max(0, StrideGame.level - 0.34)
        if StrideGame.level <= 0 then
            stopGame()
        end
        return false
    end,
}
local GripMod = {
    Active = function()
        return GripGame.active
    end,
    Hand = function(side)
        if side < 0 then
            return math.clamp(GripGame.left, 0, 1)
        end
        return math.clamp(GripGame.right, 0, 1)
    end,
    Locked = function(side)
        if side < 0 then
            return Sched.now < GripGame.leftLock
        end
        return Sched.now < GripGame.rightLock
    end,
    Window = function()
        return 0.5
    end,
    Regrip = function(side)
        if not GripGame.active then
            return false
        end
        local good = false
        local hand = side < 0 and GripGame.left or GripGame.right
        local lock = side < 0 and GripGame.leftLock or GripGame.rightLock
        if lock <= Sched.now and hand <= 0.5 then
            good = true
        end
        if side < 0 then
            GripGame.left = good and 1 or math.max(0, GripGame.left - 0.12)
            GripGame.leftLock = Sched.now + 0.9
        else
            GripGame.right = good and 1 or math.max(0, GripGame.right - 0.12)
            GripGame.rightLock = Sched.now + 0.9
        end
        return good
    end,
}
local RepsMod = {
    Active = function()
        return RepsGame.active
    end,
    Tap = function()
        if not RepsGame.active then
            return false
        end
        local now = Sched.now
        local dt = now - RepsGame.lastTapAt
        RepsGame.lastTapAt = now
        local inst = 0.001 < dt and math.min(1 / dt, GymCfg.Reps.Max) or GymCfg.Reps.Max
        RepsGame.pace = RepsGame.pace + (inst - RepsGame.pace) * GymCfg.Reps.Smooth
        local eff = math.min(RepsGame.pace, 0.001 < dt and 1 / dt or GymCfg.Reps.Max)
        return GymCfg.Reps.BandLow <= eff and eff <= GymCfg.Reps.BandHigh
    end,
}
local GymModuleChildren = { Balance = BalanceMod, Stride = StrideMod, Grip = GripMod, Reps = RepsMod }
ModuleRegistry[InputModule].GymChildren = GymModuleChildren
local BalanceChild = Instance.new("ModuleScript", "Balance")
GymModule:AddChild(BalanceChild)
ModuleRegistry[BalanceChild] = BalanceMod
local StrideChild = Instance.new("ModuleScript", "Stride")
GymModule:AddChild(StrideChild)
ModuleRegistry[StrideChild] = StrideMod
local GripChild = Instance.new("ModuleScript", "Grip")
GymModule:AddChild(GripChild)
ModuleRegistry[GripChild] = GripMod
local RepsChild = Instance.new("ModuleScript", "Reps")
GymModule:AddChild(RepsChild)
ModuleRegistry[RepsChild] = RepsMod

-- game-side Gym module: Bind LeanLeft/LeanRight routing (side() from deobf L102790) + bridge Begin
ModuleRegistry[InputModule].Fire = function(id, state)
    table.insert(InputFires, { id = id, state = state })
    local list = InputActions[id]
    if list then
        for _, entry in ipairs(tclone(list)) do
            local fn = state and entry.Began or entry.Ended
            if fn then
                G.task.spawn(fn)
            end
        end
    end
end
ModuleRegistry[InputModule].Bind("Gym.LeanLeft", function()
    local side = -1
    if BalanceMod.Active() then
        BalanceMod.Nudge(side)
    elseif StrideMod.Active() then
        StrideMod.Step(side)
    elseif GripMod.Active() then
        GripMod.Regrip(side)
    elseif RepsMod.Active() then
        RepsMod.Tap()
    end
end)
ModuleRegistry[InputModule].Bind("Gym.LeanRight", function()
    local side = 1
    if BalanceMod.Active() then
        BalanceMod.Nudge(side)
    elseif StrideMod.Active() then
        StrideMod.Step(side)
    elseif GripMod.Active() then
        GripMod.Regrip(side)
    end
end)

-- pre-create the Gym.Sync bridge and connect the game-side Begin/End listener
local gymBridge = ModuleRegistry[BridgeNet2Module].ReferenceBridge("Gym.Sync")
gymBridge:Connect(function(msg)
    if type(msg) ~= "table" then
        return
    end
    if msg.User ~= 42 then
        return
    end
    if msg.T == "Begin" then
        local station = msg.Station
        local kind = nil
        for _, k in ipairs(GymKinds) do
            if station and station.Name == k.Tag then
                kind = k
            end
        end
        if kind then
            startGame(kind.Game)
        end
    elseif msg.T == "End" then
        stopGame()
    end
end)

-- Heartbeat driver: faithful minigame physics each 0.05s pump step
local Heartbeat = {}
G.task.spawn(function()
    while true do
        G.task.wait(0.05)
        local dt = 0.05
        if BalanceGame.active then
            if Sched.now >= BalanceGame.gustAt then
                BalanceGame.gust = (math.random() * 2 - 1) * 0.8
                BalanceGame.gustAt = Sched.now + 0.5 + math.random() * 0.9
            end
            BalanceGame.vel = BalanceGame.vel + BalanceGame.gust * dt
            BalanceGame.vel = BalanceGame.vel + BalanceGame.tilt * 0.9 * dt
            BalanceGame.vel = BalanceGame.vel - BalanceGame.vel * math.min(2 * dt, 1)
            BalanceGame.tilt = BalanceGame.tilt + BalanceGame.vel * dt
            if math.abs(BalanceGame.tilt) >= 1 then
                stopGame()
            end
        end
        if StrideGame.active then
            if Sched.now - StrideGame.lastStepAt > 2.5 then
                stopGame()
            end
        end
        if GripGame.active then
            GripGame.left = math.max(0, GripGame.left - 0.18 * dt)
            GripGame.right = math.max(0, GripGame.right - 0.18 * dt)
            if GripGame.left <= 0 or GripGame.right <= 0 then
                stopGame()
            end
        end
        if RepsGame.active then
            local dtTap = Sched.now - RepsGame.lastTapAt
            local eff = math.min(RepsGame.pace, 0.001 < dtTap and 1 / dtTap or GymCfg.Reps.Max)
            local inBand = GymCfg.Reps.BandLow <= eff and eff <= GymCfg.Reps.BandHigh
            if inBand then
                RepsGame.level = math.min(1, RepsGame.level + 0.16 * dt)
            else
                RepsGame.level = math.max(0, RepsGame.level - 0.22 * dt)
                if RepsGame.level <= 0 then
                    stopGame()
                end
            end
        end
    end
end)

-- ---- world: dummies + gym station
local dummy = Instance.new("Model", "BlockingDummy")
local dummyRoot = Instance.new("Part", "HumanoidRootPart")
dummyRoot.CFrame = CFrame.new(Vector3.new(20, 5, 0))
dummy:AddChild(dummyRoot)
local dummyHum = Instance.new("Humanoid", "Humanoid")
dummy:AddChild(dummyHum)
dummy.PrimaryPart = dummyRoot
WS:AddChild(dummy)

local station = Instance.new("Model", "GymDumbbell")
local stationPart = Instance.new("Part", "Station")
stationPart.CFrame = CFrame.new(Vector3.new(30, 5, 30))
station:AddChild(stationPart)
station.PrimaryPart = stationPart
WS:AddChild(station)

local Tagged = {
    CombatDummy = { dummy },
    GymDumbbell = { station },
}

Services.Players = { LocalPlayer = PLR, GetPlayerFromCharacter = function() return nil end }
Services.ReplicatedStorage = RS
Services.RunService = { Stepped = Signal.new(), Heartbeat = Signal.new(), RenderStepped = Signal.new(), IsServer = function() return false end, IsClient = function() return true end, Set3dRenderingEnabled = function() end }
Services.HttpService = { GenerateGUID = function() return "g1" end, JSONEncode = function() return "{}" end, JSONDecode = function() return {} end }
Services.GuiService = { SelectedObject = nil, ErrorMessageChanged = Signal.new() }
Services.TeleportService = { Teleport = function() end, TeleportToPlaceInstance = function() end }
Services.MarketplaceService = { GetProductInfo = function() return { Name = "Shigaku" } end }
Services.UserInputService = { TouchEnabled = false, KeyboardEnabled = true }
Services.VirtualUser = { CaptureController = function() end, ClickButton2 = function() end }
Services.Lighting = { GlobalShadows = true, FogEnd = 1, Brightness = 1, ClockTime = 14, GetChildren = function() return {} end }
Services.ProximityPromptService = { PromptButtonHoldBegan = Signal.new() }
Services.VirtualInputManager = { SendKeyEvent = function() end }
Services.CollectionService = { GetTagged = function(_, tag) return Tagged[tag] or {} end }
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

local oldLoadstring = G.loadstring
G.loadstring = function(src, name)
    if src == "LIB" then return function() return Library end end
    if src == "THEME" then return function() return ThemeManager end end
    if src == "SAVE" then return function() return SaveManager end end
    return oldLoadstring(src, name)
end

-- ================= LOAD THE REAL SCRIPT =================
local ScriptPath = (arg and arg[1]) or "Shigaku.lua"
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
local fn = G.loadstring(ScriptSrc, "=(Shigaku)")
local okRun, errRun
G.task.spawn(function()
    okRun, errRun = pcall(fn)
end)
pump(1.0)
check("script loads without runtime error", okRun == true)
if not okRun then
    print("SCRIPT RUN ERROR: " .. tostring(errRun))
end
local errNotified = false
for _, n in ipairs(MockState.Notifies) do
    if string.find(n, "ERROR", 1, true) then
        errNotified = true
    end
end
check("no ERROR notify at load", not errNotified)
check("AutoAttack toggle registered", Library.Toggles.AutoAttack ~= nil)
check("AutoGym toggle registered", Library.Toggles.AutoGym ~= nil)
check("GymKind dropdown registered", Library.Options.GymKind ~= nil)
check("GymKind populated from Game_Settings (4 kinds)", Library.Options.GymKind ~= nil and #Library.Options.GymKind.Values == 4)
check("SaveManager folder per game", SaveManager.Folder == "Yuri/Shigaku")
check("gym bridge resolved by settings name", gymBridge.Name == "Gym.Sync")

-- ================= AUTO ATTACK =================
local function countInput(id, state)
    local n = 0
    for _, f in ipairs(InputFires) do
        if f.id == id and (state == nil or f.state == state) then
            n = n + 1
        end
    end
    return n
end

Library.Toggles.AutoAttack:SetValue(true)
pump(0.8)
check("AutoAttack fires Combat.Equip when not equipped", countInput("Combat.Equip", true) >= 1)
CombatState.active = true
pump(1.0)
check("AutoAttack fires Combat.Attack once equipped", countInput("Combat.Attack", true) >= 3)
check("AutoAttack sends release (attack fire with nil state)", countInput("Combat.Attack", nil) >= 3)
check("AutoAttack fires Combat.Critical", countInput("Combat.Critical", true) >= 3)
local dpos = dummyRoot.CFrame.Position
local hpos = charRoot.CFrame.Position
check("player repositioned near dummy (<= 5.5 studs)", math.abs(hpos.X - dpos.X) <= 5.5 and math.abs(hpos.Z - dpos.Z) <= 5.5)
check("player stands at 4 studs offset on approach axis", math.abs(math.abs(hpos.X - dpos.X) - 4) < 1.2)

local attackCount = countInput("Combat.Attack", true)
Library.Toggles.AutoAttack:SetValue(false)
pump(1.0)
check("AutoAttack stops firing after toggle off", countInput("Combat.Attack", true) == attackCount)

-- ================= AUTO GYM: session start =================
Options_GymKind = Library.Options.GymKind
Options_GymKind:SetValue("DUMBBELL")
Library.Toggles.AutoGym:SetValue(true)
pump(0.5)
check("Gym.Sync Start fired", #gymBridge.Fires >= 1)
local startMsg = gymBridge.Fires[1]
check("Start wire: T literal", startMsg and startMsg.T == "Start")
check("Start wire: Station is the tagged station instance", startMsg and startMsg.Station == station)
check("Start wire: Weight is heaviest non-Locked model name", startMsg and startMsg.Weight == "15 Dumbbell")
local spos = stationPart.CFrame.Position
local gpos = charRoot.CFrame.Position
check("player teleported to station before Start", math.abs(gpos.X - spos.X) < 1 and math.abs(gpos.Z - spos.Z) < 1)

-- server answers Begin on the bridge (game's own module flow)
for _, h in ipairs(gymBridge.Handlers) do
    h({ T = "Begin", User = 42, Station = station, Ratio = 0.3, Rate = 1 })
end
pump(0.5)
check("minigame started from server Begin (Reps active)", RepsGame.active)

-- ================= AUTO GYM: Reps strategy keeps the game alive =================
pump(6.0)
check("Reps minigame still alive after 6s of script taps", RepsGame.active)
check("Reps taps were delivered (LeanLeft fires while Reps active)", countInput("Gym.LeanLeft", true) >= 8)
check("Reps level held above zero (in-band pace)", RepsGame.level > 0.2)

-- toggle off mid-session: Stop fired + loop ends
local leanBefore = countInput("Gym.LeanLeft", true)
Library.Toggles.AutoGym:SetValue(false)
pump(0.5)
check("Gym.Stop fired on toggle off", countInput("Gym.Stop", true) >= 1)
check("tap loop stopped after toggle off", countInput("Gym.LeanLeft", true) == leanBefore)

-- ================= AUTO GYM: Balance strategy =================
Library.Toggles.AutoGym:SetValue(true)
pump(0.3)
for _, h in ipairs(gymBridge.Handlers) do
    h({ T = "Begin", User = 42, Station = station, Ratio = 0.3, Rate = 1 })
end
stopGame()
startGame("Balance")
pump(3.0)
check("Balance minigame survives 3s with script counter-nudges", BalanceGame.active)
check("Balance tilt kept below fail threshold", math.abs(BalanceGame.tilt) < 1)
Library.Toggles.AutoGym:SetValue(false)
pump(0.3)

-- ================= AUTO GYM: Stride strategy =================
Library.Toggles.AutoGym:SetValue(true)
pump(0.3)
stopGame()
startGame("Stride")
pump(2.5)
check("Stride minigame survives 2.5s (alternating taps, no idle fail)", StrideGame.active)
local lefts, rights = 0, 0
for _, f in ipairs(InputFires) do
    if f.id == "Gym.LeanLeft" and f.state then
        lefts = lefts + 1
    elseif f.id == "Gym.LeanRight" and f.state then
        rights = rights + 1
    end
end
check("Stride alternated both sides", lefts > 0 and rights > 0)
Library.Toggles.AutoGym:SetValue(false)
pump(0.3)

-- ================= AUTO GYM: Grip strategy =================
Library.Toggles.AutoGym:SetValue(true)
pump(0.3)
stopGame()
startGame("Grip")
pump(4.0)
check("Grip minigame survives 4s (regrip taps as hands drain)", GripGame.active)
check("both grip hands kept above zero", GripGame.left > 0 and GripGame.right > 0)
Library.Toggles.AutoGym:SetValue(false)
pump(0.3)

-- ================= SUMMARY =================
print(string.format("shigaku harness: %d pass / %d fail", Pass, Fail))
if Fail > 0 then
    for _, f in ipairs(Failures) do
        print("  failed: " .. f)
    end
    os.exit(1)
end
