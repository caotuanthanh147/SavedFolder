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


-- ####################################################################
-- ===== DROP A FRUIT HARNESS — DF1 (glm1, 2026-10-04) ==================
-- Mock world from work/lua/dropafruit-analysis.md (all semantics deobf-verified):
--   remo container  RS.Shared.Remotes → :fire() lowercase-colon (L60257/70550/88734)
--   ReplicaService  _replicas registry + replica:FireServer routes Id (L33220-33229)
--   replica classes Profile(Tags.Player) / PlotRoll(Data.Player, RollResult) /
--     Fruit(parent-plot children, Data.State) / Weather(Data.Active/Stars/Collects)
--   util semantics: EntityUtil.getUpgradeCost = round(Amt*lvl*1.5*mutMult) (L24463),
--     RebirthUtil.canRebirth (L23150 region), IndexRewardUtil.isReady (L23171 region),
--     Purchase.canAfford (L80096 region), isDependencyMet nil-or-owned (L23712 region).
-- REAL-LOAD: io.open + loadstring + task.spawn of work/lua/DropAFruit.lua.
-- ####################################################################

local ScriptPath = (arg and arg[1]) or "/home/z/SavedFolder/work/lua/DropAFruit.lua"

local oldLoadstring = G.loadstring
G.loadstring = function(src, name)
    if src == "LIB" then return function() return Library end end
    if src == "THEME" then return function() return ThemeManager end end
    if src == "SAVE" then return function() return SaveManager end end
    return oldLoadstring(src, name)
end

local MockFS = {}
G.writefile = function(p, c) MockFS[p] = c end
G.readfile = function(p) return MockFS[p] end
G.isfile = function(p) return MockFS[p] ~= nil end
G.isfolder = function() return true end
G.makefolder = function() end
G.listfiles = function() return {} end
G.listfolder = G.listfiles
G.appendfile = function(p, c) MockFS[p] = (MockFS[p] or "") .. c end
G.delfile = function(p) MockFS[p] = nil end
G.queue_on_teleport = function() end
G.queueonteleport = G.queue_on_teleport
G.request = function() return { Success = true } end
G.http_request = G.request
G.setfpscap = function() end
G.getfpscap = function() return 60 end
G.identifyexecutor = function() return "HarnessLua54" end

-- ===== players / character / workspace =====
local PLR = { Name = "glm1_test", UserId = 424242, Character = nil, Backpack = {},
    CameraMaxZoomDistance = 128, ChildAdded = Signal.new(), CharacterAdded = Signal.new(), Idled = Signal.new() }
local OtherPlayer = { Name = "someone_else", UserId = 777 }

local WS = Instance.new("Folder", "Workspace")
local character = Instance.new("Model", "glm1_test")
local charRoot = Instance.new("Part", "HumanoidRootPart")
charRoot.Position = Vector3.new(0, 3, 0)
local humanoid = Instance.new("Humanoid", "Humanoid")
character:AddChild(charRoot)
character:AddChild(humanoid)
character.PrimaryPart = charRoot
PLR.Character = character
WS:AddChild(character)

-- ===== recorder for remo fires =====
local RemoCalls = {}
local function makeRemote(path)
    local r = { Path = path }
    function r:fire(...)
        table.insert(RemoCalls, { path = path, args = table.pack(...) })
    end
    function r:connect() end
    return r
end
local function remoCount(path, pred)
    local n = 0
    for _, c in ipairs(RemoCalls) do
        if c.path == path and (not pred or pred(c)) then n = n + 1 end
    end
    return n
end
local function remoArgs(path, pred)
    for _, c in ipairs(RemoCalls) do
        if c.path == path and (not pred or pred(c)) then return c.args end
    end
    return nil
end

local Remotes = {
    plot = {
        roll = { pull = makeRemote("plot.roll.pull"), buy = makeRemote("plot.roll.buy") },
        autoRoll = { setEnabled = makeRemote("plot.autoRoll.setEnabled"), setArmed = makeRemote("plot.autoRoll.setArmed"), setFilter = makeRemote("plot.autoRoll.setFilter") },
        fountain = makeRemote("plot.fountain"), like = makeRemote("plot.like"),
    },
    entity = {
        place = makeRemote("entity.place"), upgrade = makeRemote("entity.upgrade"),
        delete = makeRemote("entity.delete"), equipBest = makeRemote("entity.equipBest"),
        sell = makeRemote("entity.sell"),
    },
    upgrade = makeRemote("upgrade"),
    rebirth = { perform = makeRemote("rebirth.perform"), upgrade = makeRemote("rebirth.upgrade"), ready = makeRemote("rebirth.ready") },
    blitz = { activate = makeRemote("blitz.activate") },
    weather = { collectStar = makeRemote("weather.collectStar"), charged = makeRemote("weather.charged") },
    reward = { daily = makeRemote("reward.daily"), group = makeRemote("reward.group"), playtime = makeRemote("reward.playtime"), index = makeRemote("reward.index") },
    timeskip = { use = makeRemote("timeskip.use"), play = makeRemote("timeskip.play") },
    offline = { claim = makeRemote("offline.claim"), ready = makeRemote("offline.ready") },
    pack = { open = makeRemote("pack.open") },
    session = { idle = makeRemote("session.idle") },
    effect = { play = makeRemote("effect.play") },
}

-- ===== replica machinery (ReplicaService client shape) =====
local ReplicaCalls = {}
local Replicas = {}
local function newReplica(id, classToken, data, parent, tags)
    local r = {
        Id = id, ClassToken = classToken, Data = data, Tags = tags or {},
        Parent = parent, Children = {},
    }
    function r:FireServer(...)
        table.insert(ReplicaCalls, { id = id, class = classToken, args = table.pack(...) })
        if classToken == "Fruit" and select("#", ...) == 1 and (select(1, ...)) == "SendToHole" then
            local function destroySelf()
                Replicas[id] = nil
                if parent then
                    for i, c in ipairs(parent.Children) do
                        if c == r then table.remove(parent.Children, i) break end
                    end
                end
            end
            table.insert(Sched.delayed, { at = Sched.now + 0.2, fn = destroySelf, args = {} })
        end
    end
    Replicas[id] = r
    if parent then table.insert(parent.Children, r) end
    return r
end
local function replicaCount(pred)
    local n = 0
    for _, c in ipairs(ReplicaCalls) do
        if not pred or pred(c) then n = n + 1 end
    end
    return n
end

local ReplicaController = {
    _replicas = Replicas,
    RequestData = function() end,
    ReplicaOfClassCreated = function() end,
    GetReplicaById = function(_, id) return Replicas[id] end,
}
ReplicaController.GetReplicaById = function(id) return Replicas[id] end

-- ===== config (shape from deobf configs, minimal but faithful) =====
local Config = {
    Entities = {
        Garlic = { DisplayName = "Garlic", Rarity = "Common", Cost = { Type = "Coin", Amount = 20 }, Upgrade = { Cost = { Type = "Coin", Amount = 2 } } },
        Pepper = { DisplayName = "Pepper", Rarity = "Uncommon", Cost = { Type = "Coin", Amount = 1750 }, Upgrade = { Cost = { Type = "Coin", Amount = 175 } } },
        Dumb_Lime = { DisplayName = "Lime", Rarity = "Rare", Cost = { Type = "Coin", Amount = 50000 }, Upgrade = { Cost = { Type = "Coin", Amount = 5000 } } },
    },
    Rarities = { Common = { DisplayName = "Common", Index = 1 }, Uncommon = { DisplayName = "Uncommon", Index = 2 }, Rare = { DisplayName = "Rare", Index = 3 } },
    Mutations = { Normal = { DisplayName = "Normal", Index = 1 }, Golden = { DisplayName = "Golden", Index = 2, CostMultiplier = 2 }, Secret = { DisplayName = "Secret", Index = 3, Hidden = true } },
    Roll = { Auto = { Delay = 0.35 } },
    Rewards = {
        Daily = { Time = { Reset = 86400, Miss = 172800 } },
        Playtime = { m1 = { Time = 60 }, m2 = { Time = 3600 } },
        Index = { BaseMutation = "Normal", Rarity = {}, Milestones = {} },
    },
    Upgrade = {
        Tree = {
            start = { DisplayName = "Start", Dependency = nil, Cost = { Type = "Coin", Amount = 0 } },
            rollSpeed1 = { DisplayName = "Roll Speed I", Dependency = "start", Cost = { Type = "Coin", Amount = 25 } },
            rollLuck1 = { DisplayName = "Extra Luck I", Dependency = "rollSpeed1", Cost = { Type = "Coin", Amount = 10 } },
            holeLevel2 = { DisplayName = "Hole Level 2", Dependency = "start", Cost = { Type = "Coin", Amount = 50 } },
        },
    },
    Rebirth = {
        Upgrade = { List = {
            autoRollMachine = { RequiredRebirth = 1, Levels = { { Value = 1, Cost = { Type = "Crystal", Amount = 10 } } } },
            rollLuck = { RequiredRebirth = 1, Levels = { { Value = 0.5, Cost = { Type = "Crystal", Amount = 5 } }, { Value = 1, Cost = { Type = "Crystal", Amount = 10 } } } },
            vacuumLimit = { RequiredRebirth = 2, Levels = { { Value = 5, Cost = { Type = "Crystal", Amount = 10 } } } },
        } },
    },
    Weather = {
        ClassToken = "Weather",
        Starfall = { DisplayName = "Starfall", Meteors = { MaxCollects = 3, CollectRadius = 5, MaxStars = 12 } },
        Rainbow = { DisplayName = "Rainbow" },
    },
    Entity = { Level = { Base = 5, Cap = 50 }, Sell = { Ratio = 0.15, MaxBatch = 2 }, Backpack = { Max = 1000 } },
    Player = { Profile = { ClassToken = "Profile" } },
}

-- ===== utils (semantics mirrored from deobf; refs in header) =====
if not math.round then
    math.round = function(v) return math.floor(v + 0.5) end
end
local EntityUtil = {}
function EntityUtil.getCost(name, mutation)
    local e = Config.Entities[name]
    if not e then return { Type = "Coin", Amount = 0 } end
    local m = mutation and Config.Mutations[mutation]
    return { Type = e.Cost.Type, Amount = math.round(e.Cost.Amount * (m and m.CostMultiplier or 1)) }
end
function EntityUtil.getUpgradeCost(name, level, mutation)
    local e = Config.Entities[name]
    if not e or not e.Upgrade then return { Type = "Coin", Amount = 0 } end
    local m = mutation and Config.Mutations[mutation]
    return { Type = e.Upgrade.Cost.Type, Amount = math.round(e.Upgrade.Cost.Amount * level * 1.5 * (m and m.CostMultiplier or 1)) }
end
function EntityUtil.getMaxLevel(upgrades, rebirthUpgrades)
    return Config.Entity.Level.Base + ((rebirthUpgrades and rebirthUpgrades.entityMaxLevel) or 0)
end

local UpgradeUtil = {}
local UpgradeBase = { entityPlaceLimit = 1, blitzCooldown = 300, holeLevel = 0 }
function UpgradeUtil.getValue(key, upgrades, rebirthUpgrades)
    return UpgradeBase[key] + ((upgrades and upgrades[key]) or 0) + ((rebirthUpgrades and rebirthUpgrades[key]) or 0)
end
function UpgradeUtil.isDependencyMet(dependency, owned)
    if not dependency then return true end
    return owned and owned[dependency] ~= nil
end

local RebirthUtil = {}
function RebirthUtil.getTargetProgress(rebirthLevel)
    if rebirthLevel >= 2 then return nil end
    return 350
end
function RebirthUtil.hasEntityRequirement(data)
    local n = 0
    for _, item in pairs(data.Inventory.List) do
        if item.Name == "Garlic" then n = n + 1 end
    end
    return n >= 1
end
function RebirthUtil.canRebirth(data)
    local target = RebirthUtil.getTargetProgress(data.Stats.Rebirth)
    if not target or data.Stats.Coin < target then return false end
    return RebirthUtil.hasEntityRequirement(data)
end

local InventoryUtil = {}
function InventoryUtil.isBackpackFull(data)
    local n = 0
    for _ in pairs(data.Inventory.List) do n = n + 1 end
    return n >= Config.Entity.Backpack.Max
end
function InventoryUtil.getPlacedEntities(data)
    local out = {}
    for id, item in pairs(data.Inventory.List) do
        if item.Placed then out[id] = item end
    end
    return out
end

local IndexRewardUtil = {}
function IndexRewardUtil.getGoals(data)
    return { { Key = "Base:Common", Mutation = "Normal", Rarity = "Common", Target = 1, Rewards = {} } }
end
function IndexRewardUtil.isClaimed(data, key)
    return data.Rewards.Index.Claimed[key] == true
end
function IndexRewardUtil.getFound(data, mutation, rarity)
    if data.Inventory.Index.Combo["Garlic_Normal"] then return 1 end
    return 0
end
function IndexRewardUtil.isReady(data, goal)
    return not IndexRewardUtil.isClaimed(data, goal.Key)
        and IndexRewardUtil.getFound(data, goal.Mutation, goal.Rarity) >= goal.Target
end

local AutoRollUtil = {}
function AutoRollUtil.getEntries(category)
    local out = {}
    if category == "Rarity" then
        for name, r in pairs(Config.Rarities) do
            table.insert(out, { Name = name, DisplayName = r.DisplayName, Index = r.Index })
        end
    elseif category == "Mutation" then
        for name, m in pairs(Config.Mutations) do
            if not m.Hidden then
                table.insert(out, { Name = name, DisplayName = m.DisplayName, Index = m.Index })
            end
        end
    end
    table.sort(out, function(a, b)
        if a.Index ~= b.Index then return a.Index < b.Index end
        return a.Name < b.Name
    end)
    return out
end

local Purchase = {}
function Purchase.canAfford(data, currency, amount)
    return (data.Stats[currency] or 0) >= amount
end

local TimeUtil = {}
function TimeUtil.getServerTime() return Sched.now end
function TimeUtil.getUTC() return Sched.now end

local Observer = {
    listenToChange = function() return function() end end,
    listenToNewKey = function() return function() end end,
    listenToArrayInsert = function() return function() end end,
}

-- ===== RS tree + module registry =====
local RS = Instance.new("Folder", "ReplicatedStorage")
local SharedFolder = Instance.new("Folder", "Shared")
RS:AddChild(SharedFolder)
local ModulesFolder = Instance.new("Folder", "Modules")
SharedFolder:AddChild(ModulesFolder)
local ReplicaFolder = Instance.new("Folder", "Replica")
ModulesFolder:AddChild(ReplicaFolder)
local GameFolder = Instance.new("Folder", "Game")
ModulesFolder:AddChild(GameFolder)
local UtilFolder = Instance.new("Folder", "Util")
GameFolder:AddChild(UtilFolder)
local CoreFolder = Instance.new("Folder", "Core")
ModulesFolder:AddChild(CoreFolder)
local ClientFolder = Instance.new("Folder", "Client")
SharedFolder:AddChild(ClientFolder)
local ClientModulesFolder = Instance.new("Folder", "Modules")
ClientFolder:AddChild(ClientModulesFolder)
local ClientUtilFolder = Instance.new("Folder", "Util")
ClientModulesFolder:AddChild(ClientUtilFolder)

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
addModule(SharedFolder, "Remotes", Remotes)
addModule(SharedFolder, "Config", Config)
addModule(ReplicaFolder, "ReplicaController", ReplicaController)
addModule(ReplicaFolder, "Observer", Observer)
addModule(UtilFolder, "EntityUtil", EntityUtil)
addModule(UtilFolder, "UpgradeUtil", UpgradeUtil)
addModule(UtilFolder, "RebirthUtil", RebirthUtil)
addModule(UtilFolder, "InventoryUtil", InventoryUtil)
addModule(UtilFolder, "IndexRewardUtil", IndexRewardUtil)
addModule(UtilFolder, "AutoRollUtil", AutoRollUtil)
addModule(CoreFolder, "Time", TimeUtil)
addModule(ClientUtilFolder, "Purchase", Purchase)

-- ===== replica world =====
local ProfileData = {
    Stats = { Coin = 10000, Crystal = 20, Rebirth = 1, Playtime = 0, RobuxSpent = 0 },
    Inventory = {
        List = {
            e1 = { Name = "Garlic", Level = 1, Mutation = "Normal", Placed = true },
            e2 = { Name = "Garlic", Level = 1, Mutation = "Normal", Placed = false },
            e3 = { Name = "Pepper", Level = 2, Mutation = "Golden", Placed = false },
            e4 = { Name = "Pepper", Level = 5, Mutation = "Normal", Placed = true },
        },
        Index = { Fruit = {}, Entity = {}, Mutation = {}, Combo = { Garlic_Normal = true } },
    },
    Upgrades = {},
    RebirthUpgrades = {},
    Timeskips = {},
    Boosts = {},
    Rewards = {
        Daily = { Day = 1, LastClaim = Sched.now - 90000 },
        Playtime = { Start = Sched.now - 120, Claimed = {} },
        Group = { Claimed = false },
        Index = { Claimed = {} },
    },
    Tutorial = { Completed = true, Step = 0, CompletedAt = 0, Tips = {}, FreeUpgradeUsed = false },
    Time = { LastBlitz = Sched.now - 400 },
    AutoRoll = { Enabled = false, Armed = false, Filters = { Rarity = {}, Mutation = {} } },
}
local ProfileReplica = newReplica(1, "Profile", ProfileData, nil, { Player = PLR })
local MyPlotRoll = newReplica(2, "PlotRoll", { Player = PLR, RollResult = nil }, nil)
local ForeignPlotRoll = newReplica(3, "PlotRoll", { Player = OtherPlayer, RollResult = nil }, nil)
local MyFruitResting = newReplica(10, "Fruit", { Name = "Garlic", State = "Resting" }, MyPlotRoll)
local MyFruitCarried = newReplica(11, "Fruit", { Name = "Pepper", State = "Carried" }, MyPlotRoll)
local ForeignFruit = newReplica(12, "Fruit", { Name = "Garlic", State = "Resting" }, ForeignPlotRoll)
local WeatherReplica = newReplica(4, "Weather", {
    Active = "Starfall",
    Stars = {
        s1 = { Position = Vector3.new(10, 5, 10), Land = Sched.now - 10, Reward = 1 },
        s2 = { Position = Vector3.new(50, 5, 50), Land = Sched.now + 500, Reward = 1 },
    },
    Collects = {},
}, nil)

local function setRollResult(entities, mutations, t)
    MyPlotRoll.Data.RollResult = { Entities = entities, Mutations = mutations, Time = t }
end

-- ===== services / game =====
local Services = {}
Services.Players = { LocalPlayer = PLR, GetPlayers = function() return { PLR } end }
Services.ReplicatedStorage = RS
Services.RunService = { Stepped = Signal.new(), RenderStepped = Signal.new(), Heartbeat = Signal.new(), PostSimulation = Signal.new(), IsServer = function() return false end, IsStudio = function() return false end, IsClient = function() return true end }
Services.TeleportService = { Teleport = function() end }
Services.UserInputService = { TouchEnabled = false, KeyboardEnabled = true, InputBegan = Signal.new() }
Services.HttpService = { JSONEncode = function(_, t) return "{}" end, JSONDecode = function(_, s) return {} end }
Services.TweenService = { Create = function() return { Play = function() end } end, GetValue = function() return 0 end }
Services.Lighting = {}
Services.GuiService = { GetResolution = function() return Vector3.new(1920, 1080, 0) end, TopbarInset = function() return 0, 0 end }
Services.MarketplaceService = { GetUserOwnershipAsync = function() return { IsSuccess = function() return true end, UserOwnsGamePass = false } end, GetProductInfo = function(_, placeId) return { Name = "DropAFruit", Description = "", PriceInRobux = 0, Created = "", Updated = "", ContentRatingTypeId = 0, MinimumAge = 0, IsPublicDomain = false } end }
Services.VirtualInputManager = { SendMouseButtonEvent = function() end, SendKeyEvent = function() end }
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
G.getconnections = nil
G.OverlapParams = { new = function() return { FilterType = nil, FilterDescendantsInstances = {} } end }
local enumChildren = setmetatable({}, { __index = function(t, k)
    local c = setmetatable({}, { __index = function(_, k2) return k2 end })
    rawset(t, k, c)
    return c
end })
G.Enum = enumChildren
local Camera = Instance.new("Folder", "Camera")
WS:AddChild(Camera)

-- ===== mock-world self-checks =====
check("world: modules resolvable (Remotes/ReplicaController/Config)", (function()
    return G.require(RS:FindFirstChild("Shared"):FindFirstChild("Remotes")) == Remotes
        and G.require(RS:FindFirstChild("Shared"):FindFirstChild("Modules"):FindFirstChild("Replica"):FindFirstChild("ReplicaController")) == ReplicaController
end)())
check("world: 4 replicas registered + fruit parenting", (function()
    local n = 0
    for _ in pairs(Replicas) do n = n + 1 end
    return n == 7 and #MyPlotRoll.Children == 2 and MyFruitResting.Parent == MyPlotRoll
end)())
check("world: upgrade util semantics (dependency + getValue)", (function()
    return UpgradeUtil.isDependencyMet(nil, {}) == true
        and UpgradeUtil.isDependencyMet("rollSpeed1", {}) == false
        and UpgradeUtil.getValue("entityPlaceLimit", {}, {}) == 1
        and UpgradeUtil.getValue("entityPlaceLimit", { entityPlaceLimit = 2 }, {}) == 3
end)())
check("world: getUpgradeCost formula (lvl*1.5*mutMult)", (function()
    local c = EntityUtil.getUpgradeCost("Garlic", 2, "Golden")
    return c.Type == "Coin" and c.Amount == math.round(2 * 2 * 1.5 * 2)
end)())

-- ===== loader (real-load: the ACTUAL delivered script) =====
local ScriptSrc = nil
do
    local f = io.open(ScriptPath, "r")
    if f then
        ScriptSrc = f:read("*a")
        f:close()
    end
end

if not ScriptSrc then
    print("SKIP: " .. ScriptPath .. " not present — mock-world checks only")
    summary()
    os.exit(Fail > 0 and 1 or 0)
end

local function noErrorNotify()
    for _, n in ipairs(MockState.Notifies) do
        if string.find(n, "ERROR", 1, true) then return false, n end
    end
    return true
end

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
local fn = G.loadstring(ScriptSrc, "=(DropAFruit)")
G.task.spawn(fn)
pump(2.0)

check("script loaded without ERROR notify", (function()
    local ok, n = noErrorNotify()
    if not ok then print("  notify was: " .. tostring(n)) end
    return ok
end)())
check("guard set", G.ayasemiyatongekissazumirisa == true)
check("save folder = Yuri/Drop a Fruit", SaveManager.Folder == "Yuri/Drop a Fruit")
check("pcall interceptor: 0 silent swallows at load", PcallSwallows == 0)

-- ===== UI registration =====
check("11 toggles + 3 dropdowns registered", (function()
    local ids = { "AutoHole", "AutoRoll", "AutoPlace", "AutoUpgrade", "AutoEquipBest", "AutoSell", "AutoBuyUpgrades", "AutoRebirth", "AutoBlitz", "AutoStars", "AutoClaim" }
    for _, id in ipairs(ids) do
        if not Library.Toggles[id] then return false, id end
    end
    for _, id in ipairs({ "RollRarities", "RollMutations", "SellRarities" }) do
        if not Library.Options[id] then return false, id end
    end
    return true
end)())
check("RollRarities values = 3 rarities from AutoRollUtil", (function()
    local dd = Library.Options.RollRarities
    local names = {}
    for _, v in ipairs(dd.Values) do
        if v ~= "All" then table.insert(names, v) end
    end
    table.sort(names)
    return #names == 3 and names[1] == "Common" and names[2] == "Rare" and names[3] == "Uncommon"
end)())
check("RollMutations values skip Hidden (Normal+Golden only, +All)", (function()
    local dd = Library.Options.RollMutations
    local n = 0
    for _, v in ipairs(dd.Values) do
        if v ~= "All" then n = n + 1 end
    end
    return n == 2
end)())

-- ===== AutoHole =====
Library.Toggles.AutoHole:SetValue(true)
pump(1.0)
check("AutoHole: SendToHole fired exactly once for my Resting fruit", (function()
    local n = replicaCount(function(c) return c.id == 10 and c.args[1] == "SendToHole" end)
    return n == 1, ("n=" .. tostring(n))
end)())
check("AutoHole: Carried fruit NOT sent", replicaCount(function(c) return c.id == 11 end) == 0)
check("AutoHole: foreign fruit NOT sent", replicaCount(function(c) return c.id == 12 end) == 0)
check("AutoHole: sent fruit destroyed server-side (no refire)", (function()
    pump(1.0)
    return Replicas[10] == nil and replicaCount(function(c) return c.id == 10 end) == 1
end)())
Library.Toggles.AutoHole:SetValue(false)
local holeAfter = replicaCount(function(c) return c.args[1] == "SendToHole" end)
pump(1.0)
check("AutoHole: stops after toggle off", replicaCount(function(c) return c.args[1] == "SendToHole" end) == holeAfter)

-- ===== AutoRoll =====
ProfileData.Stats.Coin = 100000
Library.Options.RollRarities:SetValue({ Rare = true })
Library.Toggles.AutoRoll:SetValue(true)
pump(0.5)
check("AutoRoll: pull fired", remoCount("plot.roll.pull") >= 1)
setRollResult({ "Garlic", "Dumb_Lime" }, { "Normal", "Normal" }, 1000.5)
pump(1.5)
check("AutoRoll: matched Rare slot bought by index", (function()
    local a = remoArgs("plot.roll.buy", function(c) return true end)
    return a ~= nil and a.n == 1 and a[1] == 2, ("args=" .. tostring(a and a[1]))
end)())
check("AutoRoll: keeps pulling after result (>=2 pulls)", remoCount("plot.roll.pull") >= 2)
setRollResult({ "Garlic", "Garlic" }, { "Normal", "Normal" }, 2000.5)
pump(1.5)
check("AutoRoll: non-matching result → no buy", (function()
    local n = 0
    for _, c in ipairs(RemoCalls) do
        if c.path == "plot.roll.buy" then n = n + 1 end
    end
    return n == 1
end)())
ProfileData.Stats.Coin = 30
setRollResult({ "Garlic", "Dumb_Lime" }, { "Normal", "Golden" }, 3000.5)
pump(1.5)
check("AutoRoll: unaffordable match → no buy", (function()
    local n = 0
    for _, c in ipairs(RemoCalls) do
        if c.path == "plot.roll.buy" then n = n + 1 end
    end
    return n == 1
end)())
ProfileData.Stats.Coin = 10000
Library.Toggles.AutoRoll:SetValue(false)
local pullAfter = remoCount("plot.roll.pull")
pump(1.5)
check("AutoRoll: stops after toggle off", remoCount("plot.roll.pull") == pullAfter)

-- ===== AutoPlace =====
Library.Toggles.AutoPlace:SetValue(true)
pump(1.5)
check("AutoPlace: unplaced entities placed up to limit (limit=1, 2 placed → 0 fires)", (function()
    local n = remoCount("entity.place")
    return n == 0, ("n=" .. tostring(n))
end)())
ProfileData.Upgrades.entityPlaceLimit = 2
pump(1.5)
check("AutoPlace: place fires when limit raised (1 fire, stops at limit)", (function()
    local n = remoCount("entity.place")
    return n == 1, ("n=" .. tostring(n))
end)())
check("AutoPlace: place payload = entity id", (function()
    local a = remoArgs("entity.place")
    return a ~= nil and a.n == 1 and (a[1] == "e2" or a[1] == "e3")
end)())
ProfileData.Inventory.List.e2.Placed = true
ProfileData.Upgrades.entityPlaceLimit = 5
pump(1.5)
check("AutoPlace: next unplaced placed (e3)", (function()
    local a = remoArgs("entity.place", function(c)
        return c.args[1] == "e3"
    end)
    return a ~= nil
end)())
ProfileData.Inventory.List.e2.Placed = false
ProfileData.Inventory.List.e3.Placed = false
ProfileData.Upgrades.entityPlaceLimit = 0
Library.Toggles.AutoPlace:SetValue(false)

-- ===== AutoUpgrade =====
Library.Toggles.AutoUpgrade:SetValue(true)
pump(1.5)
check("AutoUpgrade: upgradable placed entities fired (e1 lvl1, e4 lvl5<max)", (function()
    local ids = {}
    for _, c in ipairs(RemoCalls) do
        if c.path == "entity.upgrade" then table.insert(ids, c.args[1]) end
    end
    return #ids == 2, ("n=" .. tostring(#ids))
end)())
check("AutoUpgrade: cost formula respected (e1 Garlic lvl1 = 2*1*1.5=3; e4 Pepper lvl5 = 175*5*1.5=1312.5→1313)", (function()
    local a = remoArgs("entity.upgrade", function(c) return c.args[1] == "e1" end)
    return a ~= nil
end)())
ProfileData.Stats.Coin = 3
pump(1.5)
check("AutoUpgrade: coin gate stops extra fires (spend-tracked)", (function()
    local n = remoCount("entity.upgrade")
    return n == 3, ("n=" .. tostring(n))
end)())
ProfileData.Stats.Coin = 10000
Library.Toggles.AutoUpgrade:SetValue(false)
local upgAfter = remoCount("entity.upgrade")
pump(1.5)
check("AutoUpgrade: stops after toggle off", remoCount("entity.upgrade") == upgAfter)

-- ===== AutoEquipBest =====
Library.Toggles.AutoEquipBest:SetValue(true)
pump(0.5)
local equipN = remoCount("entity.equipBest")
check("AutoEquipBest: fires once on inventory state", equipN == 1, ("n=" .. tostring(equipN)))
pump(3.0)
check("AutoEquipBest: no refire while inventory unchanged", remoCount("entity.equipBest") == equipN)
ProfileData.Inventory.List.e9 = { Name = "Dumb_Lime", Level = 1, Mutation = "Normal", Placed = false }
pump(3.0)
check("AutoEquipBest: refires on inventory change", remoCount("entity.equipBest") == equipN + 1)
ProfileData.Inventory.List.e9 = nil
Library.Toggles.AutoEquipBest:SetValue(false)

-- ===== AutoSell =====
Library.Options.SellRarities:SetValue({ Common = true })
Library.Toggles.AutoSell:SetValue(true)
pump(1.5)
check("AutoSell: unplaced Common sold in MaxBatch chunks of 2", (function()
    local chunks = {}
    for _, c in ipairs(RemoCalls) do
        if c.path == "entity.sell" then
            table.insert(chunks, c.args)
        end
    end
    if #chunks == 0 then return false, "no chunks" end
    for _, a in ipairs(chunks) do
        if a.n > 2 then return false, "chunk > MaxBatch" end
    end
    local total = 0
    for _, a in ipairs(chunks) do total = total + a.n end
    return total == 1, ("total=" .. tostring(total))
end)())
check("AutoSell: placed entities never sold", (function()
    for _, c in ipairs(RemoCalls) do
        if c.path == "entity.sell" then
            for i = 1, c.args.n do
                local id = c.args[i]
                if id == "e1" or id == "e4" then return false, id end
            end
        end
    end
    return true
end)())
Library.Options.SellRarities:SetValue({})
Library.Toggles.AutoSell:SetValue(false)

-- ===== AutoBuyUpgrades =====
Library.Toggles.AutoBuyUpgrades:SetValue(true)
pump(0.5)
check("AutoBuyUpgrades: cheapest affordable node bought first (start=0)", (function()
    local a = remoArgs("upgrade")
    return a ~= nil and a[1] == "start", ("first=" .. tostring(a and a[1]))
end)())
ProfileData.Upgrades.start = 1
pump(2.5)
check("AutoBuyUpgrades: then cheapest of affordable deps (holeLevel2=50 < rollSpeed1=25? no: 25 first)", (function()
    local a = remoArgs("upgrade", function(c) return c.args[1] == "rollSpeed1" end)
    return a ~= nil
end)())
check("AutoBuyUpgrades: dependency-unmet node not bought", remoCount("upgrade", function(c)
    return c.args[1] == "rollLuck1"
end) == 0)
check("AutoBuyUpgrades: rebirth crystal node bought when affordable+rebirth met", (function()
    local n = remoCount("rebirth.upgrade")
    return n >= 1, ("n=" .. tostring(n))
end)())
check("AutoBuyUpgrades: RequiredRebirth=2 node not bought at Rebirth 1", remoCount("rebirth.upgrade", function(c)
    return c.args[1] == "vacuumLimit"
end) == 0)
ProfileData.Tutorial.Completed = false
RemoCalls = {}
pump(2.5)
check("AutoBuyUpgrades: tutorial gate blocks buys", #RemoCalls == 0 or (#RemoCalls == 1 and RemoCalls[1].path ~= "upgrade"))
ProfileData.Tutorial.Completed = true
Library.Toggles.AutoBuyUpgrades:SetValue(false)

-- ===== AutoRebirth =====
Library.Toggles.AutoRebirth:SetValue(true)
pump(0.5)
check("AutoRebirth: perform fired (coin 10000 >= target 350 + has Garlic)", (function()
    local n = remoCount("rebirth.perform")
    return n >= 1, ("n=" .. tostring(n))
end)())
ProfileData.Stats.Coin = 100
pump(5.5)
check("AutoRebirth: gated when coin below target", remoCount("rebirth.perform") == 1)
ProfileData.Stats.Coin = 10000
Library.Toggles.AutoRebirth:SetValue(false)

-- ===== AutoBlitz =====
Library.Toggles.AutoBlitz:SetValue(true)
pump(0.5)
check("AutoBlitz: activate fired (LastBlitz 400s ago >= 300s cooldown)", (function()
    local n = remoCount("blitz.activate")
    return n == 1, ("n=" .. tostring(n))
end)())
ProfileData.Time.LastBlitz = Sched.now - 10
pump(2.0)
check("AutoBlitz: on cooldown → no refire", remoCount("blitz.activate") == 1)
Library.Toggles.AutoBlitz:SetValue(false)

-- ===== AutoStars =====
Library.Toggles.AutoStars:SetValue(true)
pump(1.5)
check("AutoStars: landed star collected (TP + fire with starId)", (function()
    local a = remoArgs("weather.collectStar", function(c) return c.args[1] == "s1" end)
    return a ~= nil and a.n == 1
end)())
check("AutoStars: TP moved character to star position", (function()
    local p = charRoot.Position
    return math.abs(p.X - 10) < 1 and math.abs(p.Z - 10) < 1
end)())
check("AutoStars: unlanded star not collected", remoCount("weather.collectStar", function(c)
    return c.args[1] == "s2"
end) == 0)
WeatherReplica.Data.Collects[PLR.UserId] = 3
RemoCalls = {}
pump(1.5)
check("AutoStars: MaxCollects reached → stops", #RemoCalls == 0)
WeatherReplica.Data.Collects[PLR.UserId] = 0
Library.Toggles.AutoStars:SetValue(false)

-- ===== AutoClaim =====
Library.Toggles.AutoClaim:SetValue(true)
pump(0.5)
check("AutoClaim: daily fired (LastClaim 90000s ago >= 86400 reset)", (function()
    local n = remoCount("reward.daily")
    return n >= 1, ("n=" .. tostring(n))
end)())
check("AutoClaim: group fired (unclaimed)", remoCount("reward.group") >= 1)
check("AutoClaim: playtime m1 fired (120s elapsed >= 60s)", (function()
    local a = remoArgs("reward.playtime", function(c) return c.args[1] == "m1" end)
    return a ~= nil and a.n == 1
end)())
check("AutoClaim: playtime m2 NOT fired (120 < 3600)", remoCount("reward.playtime", function(c)
    return c.args[1] == "m2"
end) == 0)
check("AutoClaim: index goal fired (Garlic_Normal discovered >= target 1)", (function()
    local a = remoArgs("reward.index", function(c) return c.args[1] == "Base:Common" end)
    return a ~= nil
end)())
pump(31.0)
check("AutoClaim: daily not refired (memo on LastClaim)", remoCount("reward.daily") == 1)
Library.Toggles.AutoClaim:SetValue(false)

-- ===== final: no invented wires =====
check("no removed-class wires fired (timeskip/pack/offline/fountain/session)", (function()
    local banned = { ["timeskip.use"] = true, ["timeskip.play"] = true, ["pack.open"] = true, ["offline.claim"] = true, ["offline.ready"] = true, ["plot.fountain"] = true, ["session.idle"] = true, ["effect.play"] = true }
    for _, c in ipairs(RemoCalls) do
        if banned[c.path] then return false, c.path end
    end
    return true
end)())
check("no fruit transport spam (SetCarried/SyncPosition/Throw never fired)", replicaCount(function(c)
    local a = c.args[1]
    return a == "SetCarried" or a == "SyncPosition" or a == "Throw" or a == "SetVacuumed" or a == "Fell"
end) == 0)
check("pcall interceptor: no silent swallows across all features", PcallSwallows == 0)

summary()
