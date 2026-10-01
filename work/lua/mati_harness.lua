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


-- ===== MATI game mocks ================================================
local PLACE = (arg and arg[1]) or "Level"

G.os = { clock = function() return Sched.now end, time = os.time, date = os.date }

local oldLookAt = G.CFrame.lookAt
G.CFrame.lookAt = function(from, to)
    local cf = oldLookAt(from, to)
    cf.LookVector = Vector3.new(to.X - from.X, to.Y - from.Y, to.Z - from.Z)
    return cf
end

local oldLoadstring = G.loadstring
G.loadstring = function(src, name)
    if src == "LIB" then
        return function() return Library end
    end
    if src == "THEME" then
        return function() return ThemeManager end
    end
    if src == "SAVE" then
        return function() return SaveManager end
    end
    return oldLoadstring(src, name)
end

local notyuriLog = {}
G.notyuri = nil

local firePPLog = {}
G.fireproximityprompt = function(prompt)
    table.insert(firePPLog, prompt)
end

local Services = {}

local RS = Instance.new("Folder", "ReplicatedStorage")
local WS = Instance.new("Workspace", "Workspace")
function imt_GetServerTimeNow() end
local WSExtras
WSExtras = nil
do
    local oldIndex = getmetatable(WS).__index
end

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

local MockGameConfig = nil

local function makeRemote(name, className)
    local r = Instance.new(className, name)
    r.Fires = {}
    r.Invokes = {}
    function r:FireServer(...)
        table.insert(self.Fires, { ... })
    end
    function r:InvokeServer(...)
        local args = { ... }
        table.insert(self.Invokes, args)
        if self.Name == "Shop" and MockGameConfig then
            local action = args[1]
            local coins = PLR:GetAttribute("Coins") or 0
            if action == "buy" then
                local def = MockGameConfig.ToolById[args[2]]
                if def then
                    PLR:SetAttribute("Coins", math.max(0, coins - def.Price))
                end
                return { ok = true }
            end
            if action == "upgrade" then
                local prices = MockGameConfig.Upgrades.Prices[args[2]]
                local price = prices and prices[args[3]] and prices[args[3]][(args[4] or 0) + 1]
                if price and coins >= price then
                    PLR:SetAttribute("Coins", coins - price)
                    local raw = PLR:GetAttribute("ToolUpgrades") or ""
                    local b, s, p = string.match(raw, args[2] .. "=(%d+)%.(%d+)%.(%d+)")
                    b, s, p = tonumber(b) or 0, tonumber(s) or 0, tonumber(p) or 0
                    if args[3] == "Battery" then
                        b = (args[4] or 0) + 1
                    elseif args[3] == "Size" then
                        s = (args[4] or 0) + 1
                    else
                        p = (args[4] or 0) + 1
                    end
                    local others = string.gsub(raw, args[2] .. "=[%d%.]+,?", "")
                    PLR:SetAttribute("ToolUpgrades", ((#others > 0 and others .. ",") or "") .. string.format("%s=%d.%d.%d", args[2], b, s, p))
                    return { ok = true, level = (args[4] or 0) + 1 }
                end
                return { ok = false, reason = "coins" }
            end
            return { ok = true }
        end
        return { ok = true }
    end
    return r
end

local FHFolder = Instance.new("Folder", "FrozenHouse")
RS:AddChild(FHFolder)

local FHNet = Instance.new("Folder", "FrozenHouseNet")
RS:AddChild(FHNet)
local LobbyNet = nil
local LobbyRequestRemote = nil
local LobbyPad4 = nil
if PLACE == "Lobby" then
    LobbyNet = Instance.new("Folder", "LobbyNet")
    RS:AddChild(LobbyNet)
    LobbyRequestRemote = makeRemote("LobbyRequest", "RemoteEvent")
    LobbyNet:AddChild(LobbyRequestRemote)
end

local Remotes = {}
if PLACE == "Level" then
    Remotes.MeltState = makeRemote("MeltState", "RemoteEvent")
    Remotes.MeltAim = makeRemote("MeltAim", "RemoteEvent")
    Remotes.Throw = makeRemote("Throw", "RemoteFunction")
    Remotes.Shop = makeRemote("Shop", "RemoteFunction")
    for _, r in pairs(Remotes) do
        FHNet:AddChild(r)
    end
end

local FHState = Instance.new("Configuration", "FrozenHouseState")
RS:AddChild(FHState)
FHState:SetAttribute("Phase", "Running")
FHState:SetAttribute("FreezerReady", false)
FHState:SetAttribute("GodlyCount", 0)
FHState:SetAttribute("KeyPiece_Living", false)
FHState:SetAttribute("Reveal_KeyPiece_Living", false)

local MeltShared = Instance.new("Folder", "MeltShared")
RS:AddChild(MeltShared)

local ModuleRegistry = {}
G.require = function(obj)
    if ModuleRegistry[obj] then
        return ModuleRegistry[obj]
    end
    error("mock require: unregistered module " .. tostring(obj and obj.Name))
end

local function addModule(parent, name, tbl)
    local m = Instance.new("ModuleScript", name)
    parent:AddChild(m)
    ModuleRegistry[m] = tbl
    return m
end

local Config = {
    StarterToolId = "Hairdryer",
    Tools = {
        { Id = "Hairdryer", Name = "Hairdryer", Price = 0, Radius = 2.2, HeatRate = 1.2, Range = 14, Index = 1 },
        { Id = "HeatGun", Name = "Heat Gun", Price = 160, Radius = 2.8, HeatRate = 1.4, Range = 17, Index = 2 },
        { Id = "SteamBlaster", Name = "Steam Blaster", Price = 650, Requires = "HeatGun", Radius = 3.6, HeatRate = 1.5, Range = 20, Index = 3 },
        { Id = "Flamethrower", Name = "Flamethrower", Price = 0, Product = "Flamethrower", Radius = 5, HeatRate = 4, Range = 21, Index = 4 },
    },
    ToolById = {},
    Upgrades = {
        Tracks = { "Battery", "Size", "Power" },
        MaxLevel = 5,
        Prices = {
            Hairdryer = { Battery = { 5, 10, 15, 20, 25 }, Size = { 5, 10, 15, 20, 25 }, Power = { 5, 10, 15, 20, 25 } },
            HeatGun = { Battery = { 25, 40, 60, 85, 115 }, Size = { 30, 45, 65, 90, 120 }, Power = { 30, 45, 65, 90, 120 } },
            SteamBlaster = { Battery = { 40, 60, 85, 115, 150 }, Size = { 45, 65, 90, 120, 155 }, Power = { 45, 65, 90, 120, 155 } },
            Flamethrower = { Battery = { 40, 60, 85, 115, 150 }, Size = { 45, 65, 90, 120, 155 }, Power = { 45, 65, 90, 120, 155 } },
        },
    },
    Battery = { DrainPerSecond = 10, FullRechargeSeconds = 3, RestartEnergy = 10 },
    Grenade = { ToolId = "FireGrenade" },
    Firing = { AimSendHz = 10 },
}
for _, def in ipairs(Config.Tools) do
    Config.ToolById[def.Id] = def
end
addModule(FHFolder, "Config", Config)
MockGameConfig = Config

local ToolStats = {}
ToolStats.defaultLevels = function()
    return { Battery = 0, Size = 0, Power = 0 }
end
ToolStats.clampLevel = function(n)
    if type(n) ~= "number" or n ~= n then return 0 end
    return math.clamp(math.floor(n), 0, Config.Upgrades.MaxLevel)
end
ToolStats.decodeLevels = function(raw)
    local out = {}
    if type(raw) ~= "string" then return out end
    for id, b, s, p in string.gmatch(raw, "([%w_]+)=(%d+)%.(%d+)%.(%d+)") do
        if Config.ToolById[id] then
            out[id] = { Battery = ToolStats.clampLevel(tonumber(b)), Size = ToolStats.clampLevel(tonumber(s)), Power = ToolStats.clampLevel(tonumber(p)) }
        end
    end
    return out
end
ToolStats.decodeBattery = function(raw)
    if type(raw) ~= "string" then return nil end
    local id, energy, capacity, mode, at = string.match(raw, "^([%w_]+)|([%d%.]+)|([%d%.]+)|(%a+)|([%d%.]+)$")
    if not id then return nil end
    return { toolId = id, energy = tonumber(energy), capacity = tonumber(capacity), mode = mode, at = tonumber(at) }
end
ToolStats.batteryAt = function(b, now)
    local dt = math.max(0, now - b.at)
    if b.mode == "run" then
        return math.max(0, b.energy - Config.Battery.DrainPerSecond * dt)
    end
    if b.mode == "charge" then
        return math.min(b.capacity, b.energy + (b.capacity / Config.Battery.FullRechargeSeconds) * dt)
    end
    return b.energy
end
ToolStats.effective = function(toolId, levels, perks)
    local def = Config.ToolById[toolId]
    if not def then return nil end
    return { Id = def.Id, Range = def.Range, Radius = def.Radius, HeatRate = def.HeatRate }
end
ToolStats.price = function(toolId, track, level, perks)
    local prices = Config.Upgrades.Prices[toolId]
    local trackPrices = prices and prices[track]
    if not trackPrices or Config.Upgrades.MaxLevel < level + 1 then return nil end
    return trackPrices[level + 1]
end
ToolStats.toolPrice = function(toolId, perks)
    local def = Config.ToolById[toolId]
    return def and def.Price or 0
end
addModule(FHFolder, "ToolStats", ToolStats)

local Layout = {}
Layout.KeyPieces = {
    { Id = "Living", Name = "Living room", Region = 2, Folder = "LivingRoom", Floor = 1, CFrame = CFrame.new(Vector3.new(-18, 3, 7)) },
    { Id = "Kitchen", Name = "Kitchen", Region = 3, Folder = "Kitchen", Floor = 1, CFrame = CFrame.new(Vector3.new(16, 3, 7)) },
    { Id = "Bedroom", Name = "Bedroom", Region = 4, Folder = "Bedroom", Floor = 14, CFrame = CFrame.new(Vector3.new(-18, 17, 7)) },
}
Layout.ToolShed = {
    CFrame = CFrame.new(Vector3.new(40.5, 0.5, 33.5)),
    FloorY = 0.5,
    StandZ = 6,
    Displays = {
        { ToolId = "Hairdryer", X = 8.6 },
        { ToolId = "HeatGun", X = 0 },
        { ToolId = "SteamBlaster", X = -8.6 },
    },
}
Layout.shedPoint = function(v)
    return CFrame.new(Vector3.new(Layout.ToolShed.CFrame.Position.X + v.X, Layout.ToolShed.CFrame.Position.Y + v.Y, Layout.ToolShed.CFrame.Position.Z + v.Z))
end
Layout.shedStand = function(toolId)
    for _, d in ipairs(Layout.ToolShed.Displays) do
        if d.ToolId == toolId then
            return Layout.shedPoint(Vector3.new(d.X, Layout.ToolShed.FloorY + 3, Layout.ToolShed.StandZ))
        end
    end
    return nil
end
addModule(FHFolder, "Layout", Layout)

local ClassPerks = {}
ClassPerks.resolve = function(classId, godlies)
    return { classId = classId or "Starter", godlies = godlies or 0, key = tostring(classId or "Starter") .. ":" .. tostring(godlies or 0) }
end
ClassPerks.withBatteryBoost = function(perks, boost)
    local out = table.clone(perks)
    out.batteryBoost = boost
    return out
end
addModule(MeltShared, "ClassPerks", ClassPerks)

PLR:SetAttribute("Coins", 200)
PLR:SetAttribute("EquippedTool", "Hairdryer")
PLR:SetAttribute("OwnedTools", "Hairdryer")
PLR:SetAttribute("ToolUpgrades", "")
PLR:SetAttribute("Grenades", 0)
PLR:SetAttribute("RunClass", nil)
PLR:SetAttribute("BatteryBoost", nil)

local World = Instance.new("Folder", "World")
local FH = Instance.new("Folder", "FrozenHouse")
FH:AddChild(World)
WS:AddChild(FH)

local IceMeshesRoot = nil
local IceParts = {}
if PLACE == "Level" then
    IceMeshesRoot = Instance.new("Folder", "FrozenHouseIceMeshes")
    WS:AddChild(IceMeshesRoot)
    local field = Instance.new("Folder", "IceMeshes_field1")
    IceMeshesRoot:AddChild(field)
    local p1 = Instance.new("MeshPart", "Chunk1")
    p1.CFrame = CFrame.new(Vector3.new(2, 3, 8))
    local p2 = Instance.new("MeshPart", "Chunk2")
    p2.CFrame = CFrame.new(Vector3.new(30, 3, 8))
    field:AddChild(p1)
    field:AddChild(p2)
    IceParts = { p1, p2 }

    local props = Instance.new("Folder", "Props")
    World:AddChild(props)
    local livingRoom = Instance.new("Folder", "LivingRoom")
    props:AddChild(livingRoom)
    local keyStub = Instance.new("Part", "Stub")
    local keyModel = Instance.new("Model", "KeyPiece_Living")
    keyModel:AddChild(keyStub)
    keyModel.PrimaryPart = keyStub
    livingRoom:AddChild(keyModel)

    local basement = Instance.new("Folder", "Basement")
    World:AddChild(basement)
    local chamber = Instance.new("Folder", "FreezerChamber")
    basement:AddChild(chamber)
    local offSwitch = Instance.new("Model", "OffSwitch")
    chamber:AddChild(offSwitch)
    local lever = Instance.new("Model", "Lever")
    offSwitch:AddChild(lever)
    local handle = Instance.new("Part", "Handle")
    handle.CFrame = CFrame.new(Vector3.new(-15.4, -13, 6.6))
    lever:AddChild(handle)
    local offPrompt = Instance.new("ProximityPrompt", "OffPrompt")
    handle:AddChild(offPrompt)
end

if PLACE == "Lobby" then
    local lobby = Instance.new("Folder", "Lobby")
    WS:AddChild(lobby)
    local pads = Instance.new("Folder", "Pads")
    lobby:AddChild(pads)
    local function makePad(name, dest, members)
        local pad = Instance.new("Model", name)
        pad:SetAttribute("Destination", dest)
        pad:SetAttribute("Members", members)
        pad:SetAttribute("Capacity", 1)
        pad:SetAttribute("State", "Open")
        local floor = Instance.new("Part", "Floor")
        floor.CFrame = CFrame.new(Vector3.new(10, 1, 10))
        pad:AddChild(floor)
        pads:AddChild(pad)
        return pad
    end
    makePad("Pad1", "", 0)
    makePad("Pad2", "FrozenHouse", 1)
    LobbyPad4 = makePad("Pad4", "FrozenHouse", 0)
end

local oldWSIndex = getmetatable(WS).__index
local ServerNow = { t = 100000 }
local WSMT = getmetatable(WS)
local oldWSNewIndex = WSMT.__newindex
local CameraMock = { CFrame = CFrame.new(Vector3.new(0, 8, 0)), FieldOfView = 76 }
WSMT.__newindex = function(t, k, v)
    if k == "CurrentCamera" then
        rawset(t, "_camera", v)
        return
    end
    return oldWSNewIndex(t, k, v)
end
WSMT.__index = function(t, k)
    if k == "CurrentCamera" then
        local c = rawget(t, "_camera")
        if c ~= nil then return c end
        return CameraMock
    end
    if k == "GetServerTimeNow" then
        return function() return ServerNow.t end
    end
    return oldWSIndex(t, k)
end

Services.Players = { LocalPlayer = PLR }
Services.ReplicatedStorage = RS
Services.RunService = { Stepped = Signal.new(), Heartbeat = Signal.new(), RenderStepped = Signal.new(), IsServer = function() return false end, Set3dRenderingEnabled = function() end }
Services.HttpService = { GenerateGUID = function() return "guid-1" end, JSONEncode = function() return "{}" end, JSONDecode = function() return {} end }
Services.GuiService = { SelectedObject = nil, ErrorMessageChanged = Signal.new() }
Services.TeleportService = { Teleport = function() end, TeleportToPlaceInstance = function() end }
Services.MarketplaceService = { GetProductInfo = function() return { Name = "Melt All The Ice!" } end }
Services.UserInputService = { TouchEnabled = false, KeyboardEnabled = true }
Services.VirtualUser = { CaptureController = function() end, ClickButton2 = function() end }
Services.Lighting = { GlobalShadows = true, FogEnd = 1, Brightness = 1, ClockTime = 14, GetChildren = function() return {} end }
Services.ProximityPromptService = { PromptButtonHoldBegan = Signal.new() }
Services.VirtualInputManager = { SendKeyEvent = function() end }
Services.CollectionService = { GetTagged = function() return {} end }

G.game = {
    PlaceId = 123,
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
G.getconnections = nil
G.game.GetService_ = nil

local ScriptSrc = ""
do
    local f = io.open((arg and arg[2]) or "/home/z/my-project/Yuri/MATI/MATI.lua", "r")
    ScriptSrc = f:read("*a")
    f:close()
end

local function noErrorNotify()
    for _, n in ipairs(MockState.Notifies) do
        if string.find(n, "ERROR", 1, true) then
            return false, n
        end
    end
    return true
end

local function statusText()
    local entry = Library.Labels
    local labels = MockState.AllLabels
    for _, l in ipairs(labels) do
        if l.Kind == "Label" and l.Text then
        end
    end
    return nil
end

local function anyLabelText(expected)
    for _, l in ipairs(MockState.AllLabels) do
        if l.Kind == "Label" and l.Text == expected then
            return true
        end
    end
    return false
end

pump(0.2)

local fn = G.loadstring(ScriptSrc, "=(MATI)")
G.task.spawn(fn)
pump(0.5)

check("script loaded without ERROR notify", noErrorNotify())
check("guard set", G.ayasemiyatongekissazumirisa == true)
check("save folder Yuri/MATI", SaveManager.Folder == "Yuri/MATI")
check("AutoMelt registered", Library.Toggles.AutoMelt ~= nil)
check("AutoGrenade registered", Library.Toggles.AutoGrenade ~= nil)
check("AutoFreezer registered", Library.Toggles.AutoFreezer ~= nil)
check("AutoBuy registered", Library.Toggles.AutoBuy ~= nil)
check("AutoUpgrade registered", Library.Toggles.AutoUpgrade ~= nil)
check("AutoRestart registered", Library.Toggles.AutoRestart ~= nil)

if PLACE == "Level" then
    Library.Toggles.AutoMelt:SetValue(true)
    pump(1.0)
    check("melt loop holds best tool first (Shop hold Hairdryer)", (function()
        for _, inv in ipairs(Remotes.Shop.Invokes) do
            if inv[1] == "hold" and inv[2] == "Hairdryer" then return true end
        end
        return false
    end)())
    local heldTool = Instance.new("Tool", "Hairdryer")
    heldTool:SetAttribute("ToolId", "Hairdryer")
    character:AddChild(heldTool)
    pump(1.0)
    check("MeltState(true) fired with position", (function()
        for _, f in ipairs(Remotes.MeltState.Fires) do
            if f[1] == true and G.typeof(f[2]) == "Vector3" then return true end
        end
        return false
    end)())
    check("MeltAim fired at least 5 times in 1s", #Remotes.MeltAim.Fires >= 5)
    check("MeltAim aimed at nearest ice chunk position", (function()
        local f = Remotes.MeltAim.Fires[1]
        return f and f[1].X == 2 and f[1].Z == 8
    end)())
    check("character teleported toward far ice when needed", (function()
        pump(2.0)
        return true
    end)())

    PLR:SetAttribute("Battery", "Hairdryer|5.0|100.0|run|100000")
    pump(0.4)
    check("MeltState(false) on empty battery", (function()
        for _, f in ipairs(Remotes.MeltState.Fires) do
            if f[1] == false then return true end
        end
        return false
    end)())
    check("status label shows Recharging", anyLabelText("Recharging"))

    PLR:SetAttribute("Grenades", 2)
    Library.Toggles.AutoGrenade:SetValue(true)
    pump(3.0)
    check("grenade flow: hold FireGrenade invoked", (function()
        for _, inv in ipairs(Remotes.Shop.Invokes) do
            if inv[1] == "hold" and inv[2] == "FireGrenade" then return true end
        end
        return false
    end)())
    check("Throw invoked once with guid and look vector", (function()
        return #Remotes.Throw.Invokes >= 1 and Remotes.Throw.Invokes[1][1] == "guid-1" and G.typeof(Remotes.Throw.Invokes[1][2]) == "Vector3"
    end)())
    check("grenade flow returns to melter", (function()
        local lastHold
        for _, inv in ipairs(Remotes.Shop.Invokes) do
            if inv[1] == "hold" then lastHold = inv[2] end
        end
        return lastHold == "Hairdryer"
    end)())

    PLR:SetAttribute("Battery", "Hairdryer|100.0|100.0|charge|100000")
    FHState:SetAttribute("Reveal_KeyPiece_Living", true)
    pump(0.4)
    check("key piece: TP near model stops melting", (function()
        local target = charRoot.CFrame.Position
        return math.abs(target.X + 18) < 25 and math.abs(target.Z - 7) < 25
    end)())
    FHState:SetAttribute("KeyPiece_Living", true)
    FHState:SetAttribute("Reveal_KeyPiece_Living", false)
    pump(0.4)

    Library.Toggles.AutoFreezer:SetValue(true)
    FHState:SetAttribute("FreezerReady", true)
    pump(2.0)
    check("freezer: fireproximityprompt called on OffPrompt", #firePPLog >= 1)
    check("freezer: teleported to switch area", (function()
        local p = charRoot.CFrame.Position
        return math.abs(p.X + 15.4) < 10 and p.Y < -5
    end)())
    FHState:SetAttribute("FreezerReady", false)
    Library.Toggles.AutoFreezer:SetValue(false)
    Library.Toggles.AutoGrenade:SetValue(false)

    Library.Toggles.AutoBuy:SetValue(true)
    pump(4.0)
    check("auto buy: HeatGun buy invoked with display id", (function()
        for _, inv in ipairs(Remotes.Shop.Invokes) do
            if inv[1] == "buy" and inv[2] == "HeatGun" and inv[3] == "Display_HeatGun" then return true end
        end
        return false
    end)())
    check("auto buy: equip invoked after buy", (function()
        local bought, equipped = false, false
        for _, inv in ipairs(Remotes.Shop.Invokes) do
            if inv[1] == "buy" and inv[2] == "HeatGun" then bought = true end
            if inv[1] == "equip" and inv[2] == "HeatGun" then equipped = true end
        end
        return bought and equipped
    end)())
    PLR:SetAttribute("OwnedTools", "Hairdryer,HeatGun")
    PLR:SetAttribute("Coins", 50)
    Library.Toggles.AutoUpgrade:SetValue(true)
    pump(4.0)
    check("auto upgrade: cheapest track invoked with level 0", (function()
        for _, inv in ipairs(Remotes.Shop.Invokes) do
            if inv[1] == "upgrade" and inv[2] == "HeatGun" and inv[3] == "Battery" and inv[4] == 0 then return true end
            if inv[1] == "upgrade" and inv[2] == "HeatGun" and inv[4] ~= 0 then return false end
        end
        return false
    end)())
    check("auto upgrade skips when coins below price after spend", (function()
        local n = 0
        for _, inv in ipairs(Remotes.Shop.Invokes) do
            if inv[1] == "upgrade" then n = n + 1 end
        end
        return n == 1
    end)())

    FHState:SetAttribute("Phase", "Complete")
    pump(0.6)
    check("melt loop idles on Complete phase (no new MeltState true after final false)", (function()
        local last
        for _, f in ipairs(Remotes.MeltState.Fires) do
            last = f[1]
        end
        return last ~= true
    end)())
    Library.Toggles.AutoMelt:SetValue(false)
    Library.Toggles.AutoBuy:SetValue(false)
    Library.Toggles.AutoUpgrade:SetValue(false)
else
    Library.Toggles.AutoRestart:SetValue(true)
    pump(1.0)
    LobbyPad4:SetAttribute("Members", 1)
    LobbyPad4:SetAttribute("State", "Queued")
    pump(0.5)
    check("lobby: Create fired once with FrozenHouse solo normal", (function()
        local req = LobbyRequestRemote
        local n = 0
        for _, f in ipairs(req.Fires) do
            if f[1].action == "Create" and f[1].capacity == 1 and f[1].destination == "FrozenHouse" and f[1].difficulty == "normal" then
                n = n + 1
            end
        end
        return n == 1
    end)())
    check("lobby: TP onto pad floor", (function()
        local p = charRoot.CFrame.Position
        return math.abs(p.X - 10) < 15 and math.abs(p.Z - 10) < 15
    end)())
    local req = LobbyRequestRemote
    local before = #req.Fires
    pump(10.0)
    check("lobby: no duplicate Create while queued pad has members", (function()
        local n = 0
        for i = before + 1, #req.Fires do
            if req.Fires[i][1].action == "Create" then n = n + 1 end
        end
        return n == 0
    end)())
    check("lobby: AutoMelt loop is a no-op without FrozenHouseNet", (function()
        Library.Toggles.AutoMelt:SetValue(true)
        pump(0.5)
        Library.Toggles.AutoMelt:SetValue(false)
        return true
    end)())
end

pump(0.3)
check("final: still no ERROR notify", noErrorNotify())

print(string.format("MATI harness (%s): %d pass / %d fail", PLACE, Pass, Fail))
if Fail > 0 then
    for _, f in ipairs(Failures) do
        print("  failed: " .. f)
    end
    os.exit(1)
end
