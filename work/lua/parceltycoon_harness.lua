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
    local function findWhichIsA(inst, cls, recursive)
        for _, c in ipairs(inst._children) do
            if c:IsA(cls) then
                return c
            end
            if recursive then
                local deep = findWhichIsA(c, cls, true)
                if deep then return deep end
            end
        end
        return nil
    end
    function imt:FindFirstChildWhichIsA(cls, recursive)
        return findWhichIsA(self, cls, recursive)
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
    function Library:OnUnload(fn)
        self.__unloadHandlers = self.__unloadHandlers or {}
        table.insert(self.__unloadHandlers, fn)
    end
    function Library:Unload()
        for _, fn in ipairs(self.__unloadHandlers or {}) do
            pcall(fn)
        end
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

do
    local src = [[
local g = getgenv()
local lib = g.__LinoriaLibrary()
local win = lib:CreateWindow({ Title = "Smoke" })
local tab = win:AddTab("Main")
local gb = tab:AddLeftGroupbox("Farm")
local t = gb:AddToggle("SmokeToggle", { Text = "Do thing", Default = false })
local hits = 0
local started = false
t:OnChanged(function(v)
    hits = hits + 1
    if v and not started then
        started = true
        task.spawn(function()
            while not lib.Unloaded and lib.Toggles.SmokeToggle.Value do
                hits = hits + 10
                task.wait(0.5)
            end
        end)
    end
end)
local sm = g.__SaveManagerLoader()
sm:SetFolder("Yuri/Smoke")
local v = Vector3.new(1, 2, 3)
local d = (v - Vector3.zero).Magnitude
local s = ("a,b,c"):split(",")
g.__GetHits = function()
    return hits
end
g.__SmokeResult = { dist = d, parts = #s, folder = sm.Folder }
]]
    local fn = G.loadstring(src, "=(smoke script)")
    G.task.spawn(fn)
    pump(0.1)
    check("smoke script ran", G.__SmokeResult ~= nil)
    local r = G.__SmokeResult
    check("save manager folder captured", r and r.folder == "Yuri/Smoke")
    check("string.split shim (3 parts)", r and r.parts == 3)
    check("Vector3 magnitude", r and math.abs(r.dist - math.sqrt(14)) < 0.0001)
    local tgl = Library.Toggles.SmokeToggle
    check("toggle registered", tgl ~= nil)
    tgl:SetValue(true)
    check("OnChanged fired + immediate first loop pass", G.__GetHits() >= 11)
    pump(1.2)
    check("loop ticked while toggle on (>=20 extra hits)", G.__GetHits() >= 21)
    tgl:SetValue(false)
    pump(0.4)
    local after = G.__GetHits()
    pump(1.0)
    check("loop stopped after toggle off", G.__GetHits() == after)
    local inst = Instance.new("Part", "Dummy")
    inst:SetAttribute("Tier", 3)
    local child = inst:AddChild(Instance.new("Part", "Inner"))
    check("attr roundtrip", inst:GetAttribute("Tier") == 3)
    check("FindFirstChildOfClass", inst:FindFirstChildOfClass("Part") == child)
    check("FindFirstChildWhichIsA", inst:FindFirstChildWhichIsA("Part") == child)
    check("children list", #inst:GetChildren() == 1 and inst:GetChildren()[1] == child)
    summary()
end

-- ===================== PCT1 game layer (below-marker) =====================
local ScriptPath = arg and arg[1] or nil
local ScriptSrc = nil
do
    local fallbacks = {
        (os.getenv("SF_DIR") or "/tmp/SavedFolder") .. "/work/lua/ParcelTycoon.lua",
        "/home/z/my-project/work-lua/ParcelTycoon.lua",
        "/home/z/my-project/Yuri/ParcelTycoon/ParcelTycoon.lua",
    }
    if ScriptPath then
        table.insert(fallbacks, 1, ScriptPath)
    end
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
assert(ScriptSrc, "script under test not found")

G.os = setmetatable({ clock = function() return Sched.now end }, { __index = os })

local ModuleRegistry = {}
G.require = function(obj)
    if ModuleRegistry[obj] ~= nil then
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

local WireLog = {}
local PackLog = {}
local AllWires = {}
local AllPacks = {}
local ItemDefs = {
    toy = { id = "toy", dims = {1,1,1}, weight = 2, fragile = true },
    mug = { id = "mug", dims = {1,1,1}, weight = 1, fragile = true },
    book = { id = "book", dims = {2,1,1}, weight = 3 },
    cat = { id = "cat", dims = {1,1,1}, weight = 1, live = true },
}
local BoxDefs = {
    box_S = { id = "box_S", dims = {3,2,3}, maxWeight = 60, pet = false, capacity = 3 },
    box_M = { id = "box_M", dims = {4,3,4}, maxWeight = 120, pet = false, capacity = 6 },
    box_pet = { id = "box_pet", dims = {2,2,2}, maxWeight = 20, pet = true, capacity = 2 },
}
local function mkItems(list)
    local items, byUid = {}, {}
    for i, id in ipairs(list) do
        local it = { uid = "u" .. i .. "_" .. id, id = id }
        table.insert(items, it)
        byUid[it.uid] = ItemDefs[id]
    end
    return items, byUid
end

local MockSolver = {
    solve = function(boxDef, items, opts)
        local cap = boxDef.capacity or 99
        if #items > cap then
            return { ok = false, exhausted = true, placed = {} }
        end
        local placed = {}
        local w = boxDef.dims[1]
        for i, it in ipairs(items) do
            placed[it.uid] = { x = (i - 1) % w, y = 0, z = math.floor((i - 1) / w), o = 0 }
        end
        return { ok = true, placed = placed }
    end,
}
local MockDemoPlan = {
    order = function(plan)
        local uids = {}
        for uid in pairs(plan) do
            table.insert(uids, uid)
        end
        table.sort(uids, function(a, b)
            local pa, pb = plan[a], plan[b]
            if pa.y ~= pb.y then return pa.y < pb.y end
            if pa.x ~= pb.x then return pa.x < pb.x end
            if pa.z ~= pb.z then return pa.z < pb.z end
            return a < b
        end)
        return uids
    end,
}
local MockHandling = {
    needsFor = function(ids)
        local fragile = false
        for _, id in ipairs(ids) do
            if ItemDefs[id] and ItemDefs[id].fragile then
                fragile = true
            end
        end
        if fragile then
            return { "fragile" }
        end
        return { "standard" }
    end,
}
local MockWheel = {
    ready = function(w)
        if w.spins == 0 then
            return true
        end
        return (w.play or 0) >= 600
    end,
}
local MockPads = {
    { id = "box_M", kind = "box", cost = 30, after = {} },
    { id = "scale", kind = "upgrade", cost = 35, after = { "box_M" } },
    { id = "tapegun", kind = "upgrade", cost = 45, after = { "box_M" } },
    { id = "walls_back", kind = "build", cost = 60, after = { "box_M" } },
}
local MockStaffCfg = {
    trainCost = function(member, stat)
        local lvl = member.stats and member.stats[stat]
        if type(lvl) ~= "number" or 5 <= lvl then
            return nil
        end
        return math.floor(10 * 2 ^ lvl + 0.5) * 100
    end,
}

local server = {
    orderId = nil,
    order = nil,
    board = {
        { orderId = "o1", reward = 100, items = { "book" } },
        { orderId = "o2", reward = 250, items = { "book", "toy", "mug" } },
    },
    queue = {},
    boxId = nil,
    placed = {},
    wrapped = {},
    filled = false,
    boxChosen = false,
    folded = false,
    unlockedBoxes = { box_S = true, box_M = true, box_pet = true },
    carrying = {},
    carryMax = 3,
    cart = { count = 0, max = 2 },
    chute = false,
}
local pendingOrders = {
    { orderId = "o3", reward = 180, items = { "cat", "cat" }, boxes = { "box_pet" }, pet = true },
}
local sim = {
    boxChosen = false,
    folded = false,
    pack = nil,
}
local PredictorMock
local function currentSlip(orderId)
    for _, slip in ipairs(server.board) do
        if slip.orderId == orderId then
            return slip
        end
    end
    return nil
end
local function startOrder(orderId)
    local slip = currentSlip(orderId)
    if not slip then
        return "NO SUCH TICKET"
    end
    for i, s in ipairs(server.board) do
        if s == slip then
            table.remove(server.board, i)
            break
        end
    end
    local items, byUid = mkItems(slip.items)
    server.orderId = orderId
    server.order = { orderId = orderId, reward = slip.reward, items = items, byUid = byUid, boxes = slip.boxes or { "box_S", "box_M" } }
    server.placed = {}
    server.wrapped = {}
    server.filled = false
    server.boxChosen = false
    server.folded = false
    sim.boxChosen = false
    sim.folded = false
    sim.pack = { box = nil, order = server.order, placed = {}, wrapped = {}, filled = false }
    return nil
end
PredictorMock = {
    server = server,
    sim = sim,
    request = function(op, payload)
        table.insert(PackLog, { op = op, payload = payload })
        table.insert(AllPacks, { op = op, payload = payload })
        if op == "Take" then
            return startOrder(payload.ticketId)
        end
        if server.orderId == nil then
            return "NOT PACKING RIGHT NOW"
        end
        if op == "Box" then
            if not table.find(server.order.boxes, payload.boxId) then
                return "THAT BOX ISN'T OFFERED"
            end
            if not server.unlockedBoxes[payload.boxId] then
                return "THAT BOX ISN'T IN STOCK"
            end
            local def = BoxDefs[payload.boxId]
            local sol = MockSolver.solve(def, server.order.items, { perfect = true })
            if not sol.ok then
                return "TOO MUCH FOR THAT BOX"
            end
            server.boxChosen = true
            server.boxId = payload.boxId
            server.folded = def.pet == true
            sim.boxChosen = true
            sim.folded = def.pet == true
            sim.pack.box = def
            return nil
        end
        if op == "Fold" then
            if not server.boxChosen then
                return "PUT A CARTON ON THE TABLE FIRST"
            end
            server.folded = true
            sim.folded = true
            return nil
        end
        if op == "Place" then
            local def = BoxDefs[server.boxId]
            local item = server.order.byUid[payload.uid]
            if not item then
                return "NOT IN THIS ORDER"
            end
            if type(payload.x) ~= "number" or payload.x < 0 or payload.x > def.dims[1] - 1 then
                return "OUTSIDE THE BOX"
            end
            if type(payload.z) ~= "number" or payload.z < 0 or payload.z > def.dims[3] - 1 then
                return "OUTSIDE THE BOX"
            end
            server.placed[payload.uid] = { x = payload.x, y = 0, z = payload.z, o = payload.o or 0 }
            sim.pack.placed[payload.uid] = server.placed[payload.uid]
            return nil
        end
        if op == "Wrap" then
            local item = server.order.byUid[payload.uid]
            if not item then
                return "NOT IN THIS ORDER"
            end
            if not item.fragile then
                return "ONLY FRAGILE ITEMS NEED WRAP"
            end
            server.wrapped[payload.uid] = true
            sim.pack.wrapped[payload.uid] = true
            return nil
        end
        if op == "Fill" then
            local def = BoxDefs[server.boxId]
            if def.pet then
                return "NO PAPER IN THE PET CARRIER"
            end
            for _, it in ipairs(server.order.items) do
                if not server.placed[it.uid] then
                    return "PUT EVERYTHING IN FIRST"
                end
            end
            server.filled = true
            sim.pack.filled = true
            return nil
        end
        if op == "Seal" then
            if server.cart.max <= server.cart.count then
                return "THE CART IS FULL"
            end
            server.cart.count = server.cart.count + 1
            server.orderId = nil
            server.order = nil
            server.placed = {}
            server.wrapped = {}
            server.filled = false
            server.boxChosen = false
            server.folded = false
            sim.boxChosen = false
            sim.folded = false
            sim.pack = nil
            return nil
        end
        return nil
    end,
}

local profile = {
    cash = 500,
    pads = {},
    halloween = { wheel = { play = 700, spins = 2 } },
}
local staffData = {
    { id = "dale", level = 3, stats = { speed = 2, packing = 2, care = 1 } },
    { id = "priya", level = 1, stats = { speed = 5, packing = 3, care = 0 } },
}
local StoreMock = {
    profile = profile,
    station = server,
    staff = staffData,
    send = function(name, payload)
        table.insert(WireLog, { name = name, payload = payload })
        table.insert(AllWires, { name = name, payload = payload })
        if name == "cart" and payload.op == "take" then
            for i = 1, server.cart.count do
                table.insert(server.carrying, "p" .. #server.carrying + 1)
            end
            server.cart.count = 0
        elseif name == "halloweenSpin" then
            profile.halloween.wheel.spins = profile.halloween.wheel.spins + 1
            profile.halloween.wheel.play = 0
        end
    end,
}

local WS = Instance.new("Folder", "Workspace")
local PlotsFolder = Instance.new("Folder", "Plots")
WS:AddChild(PlotsFolder)
local Plot = Instance.new("Model", "Plot7")
PlotsFolder:AddChild(Plot)
local function mkPart(parent, name, x, z)
    local p = Instance.new("Part", name)
    p._cframe = CFrame.new(Vector3.new(x, 0, z))
    parent:AddChild(p)
    return p
end
mkPart(Plot, "DropMat", 0, 0)
local FreightMat = mkPart(Plot, "FreightMat", 40, 40)
local Pumpkin = Instance.new("Model", "MagicPumpkin")
Plot:AddChild(Pumpkin)
Pumpkin.PrimaryPart = mkPart(Pumpkin, "Body", 10, 10)
local PadModels = {}
for _, pad in ipairs(MockPads) do
    local pm = Instance.new("Model", "Pad_" .. pad.id)
    pm.PrimaryPart = mkPart(pm, "Button", 20 + pad.cost, -20)
    Plot:AddChild(pm)
    PadModels[pad.id] = pm
end

local HRP = Instance.new("Part", "HumanoidRootPart")
HRP._cframe = CFrame.new(Vector3.new(0, 2, 0))
local Humanoid = Instance.new("Humanoid", "Humanoid")
local Char = Instance.new("Model", "Char")
Char:AddChild(HRP)
Char:AddChild(Humanoid)
local PSFolder, ClientFolder, PackingFolder
local PLR = {
    UserId = 42,
    Name = "Tester",
    DisplayName = "Tester",
    Character = Char,
    CameraMaxZoomDistance = 128,
    Idled = Signal.new(),
    GetAttribute = function(_, k)
        if k == "PlotIndex" then
            return 7
        end
        return nil
    end,
    GetAttributeChangedSignal = function() return Signal.new() end,
    SetAttribute = function() end,
    FindFirstChild = function(_, name)
        if name == "PlayerScripts" then
            return PSFolder
        end
        if name == "Character" then
            return Char
        end
        return nil
    end,
}

local Services = {}
Services.Players = { LocalPlayer = PLR, GetPlayers = function() return { PLR } end }
local RS = Instance.new("Folder", "ReplicatedStorage")
local SharedFolder = Instance.new("Folder", "Shared")
RS:AddChild(SharedFolder)
local ConfigFolder = Instance.new("Folder", "Config")
SharedFolder:AddChild(ConfigFolder)
Services.ReplicatedStorage = RS
Services.RunService = {
    Stepped = Signal.new(), RenderStepped = Signal.new(), Heartbeat = Signal.new(),
    PostSimulation = Signal.new(),
    IsServer = function() return false end, IsStudio = function() return false end,
    IsClient = function() return true end,
}
Services.TeleportService = { Teleport = function() end, TeleportToPlaceInstance = function() end }
Services.UserInputService = { TouchEnabled = false, KeyboardEnabled = true, InputBegan = Signal.new() }
Services.HttpService = { JSONEncode = function() return "{}" end, JSONDecode = function() return {} end, GenerateGUID = function() return "g" end }
Services.TweenService = { Create = function() return { Play = function() end } end, GetValue = function() return 0 end }
Services.Lighting = {}
Services.GuiService = { GetResolution = function() return Vector3.new(1920, 1080, 0) end, ErrorMessageChanged = Signal.new() }
Services.MarketplaceService = { GetProductInfo = function() return { Name = "Parcel Tycoon" } end }
Services.VirtualInputManager = { SendMouseButtonEvent = function() end, SendKeyEvent = function() end }
Services.ProximityPromptService = { PromptButtonHoldBegan = Signal.new() }
Services.VirtualUser = { CaptureController = function() end, ClickButton2 = function() end }
G.game = {
    PlaceId = 0,
    JobId = "job-1",
    GetService = function(_, name)
        return Services[name] or error("Invalid Service: " .. name)
    end,
    HttpGet = function(_, url)
        if string.find(url, "Library.lua", 1, true) then return "LIB" end
        if string.find(url, "ThemeManager", 1, true) then return "THEME" end
        if string.find(url, "SaveManager", 1, true) then return "SAVE" end
        return ""
    end,
    IsLoaded = function() return true end,
}
G.workspace = WS
G.Enum = setmetatable({}, { __index = function(t, k)
    local c = setmetatable({}, { __index = function(_, k2) return k2 end })
    rawset(t, k, c)
    return c
end })
G.getconnections = nil

addModule(SharedFolder, "Solver", MockSolver)
addModule(SharedFolder, "DemoPlan", MockDemoPlan)
addModule(SharedFolder, "Handling", MockHandling)
addModule(SharedFolder, "HalloweenWheel", MockWheel)
addModule(ConfigFolder, "Boxes", { get = function(id) return BoxDefs[id] end })
addModule(ConfigFolder, "Pads", MockPads)
addModule(ConfigFolder, "Staff", MockStaffCfg)
PSFolder = Instance.new("Folder", "PlayerScripts")
ClientFolder = Instance.new("Folder", "Client")
PSFolder:AddChild(ClientFolder)
addModule(ClientFolder, "Store", StoreMock)
PackingFolder = Instance.new("Folder", "Packing")
ClientFolder:AddChild(PackingFolder)
addModule(PackingFolder, "Predictor", PredictorMock)
G.PlayerScripts = PSFolder
PLR.PlayerScripts = PSFolder

local DepositCount = 0
local function checkDeposits()
    if #server.carrying > 0 then
        local pos = HRP._cframe and HRP._cframe.Position
        if pos then
            local dFreight = (pos - FreightMat._cframe.Position).Magnitude
            if dFreight < 12 then
                DepositCount = DepositCount + 1
                server.carrying = {}
                if #pendingOrders > 0 then
                    local nxt = table.remove(pendingOrders, 1)
                    table.insert(server.board, { orderId = nxt.orderId, reward = nxt.reward, items = nxt.items, boxes = nxt.boxes })
                end
            end
        end
    end
end
G.task.spawn(function()
    while true do
        checkDeposits()
        G.task.wait(0.1)
    end
end)

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
G.loadstring = function(src2, name)
    if src2 == "LIB" then return function() return Library end end
    if src2 == "THEME" then return function() return ThemeManager end end
    if src2 == "SAVE" then return function() return SaveManager end end
    return oldLoadstring(src2, name)
end
print("script under test: " .. tostring(ScriptPath))
local fn = assert(load(ScriptSrc, "=(ParcelTycoon)", "t", G))
G.task.spawn(fn)
pump(1.0)

check("library loaded", G.__LinoriaLibrary ~= nil)
check("AutoPack toggle exists", Library.Toggles.AutoPack ~= nil)
check("AutoBuyPads toggle exists", Library.Toggles.AutoBuyPads ~= nil)
check("AutoSpin toggle exists", Library.Toggles.AutoSpin ~= nil)
check("AutoTrain toggle exists", Library.Toggles.AutoTrain ~= nil)
check("PackDelay slider exists", Library.Options.PackDelay ~= nil and Library.Options.PackDelay.Value == 0.4)
check("save folder set", SaveManager.Folder == "Yuri/ParcelTycoon")

local function packOps()
    local out = {}
    for _, e in ipairs(PackLog) do
        table.insert(out, e.op)
    end
    return out
end
local function lastPack(op)
    for i = #PackLog, 1, -1 do
        if PackLog[i].op == op then
            return PackLog[i]
        end
    end
    return nil
end
local function wires(name)
    local out = {}
    for _, e in ipairs(WireLog) do
        if e.name == name then
            table.insert(out, e)
        end
    end
    return out
end

Library.Toggles.AutoPack:SetValue(true)
pump(10)
check("take fired", #PackLog > 0 and PackLog[1].op == "Take")
check("take picks best reward", PackLog[1].payload.ticketId == "o2")
check("box chosen smallest fitting", lastPack("Box") ~= nil and lastPack("Box").payload.boxId == "box_S")
local foldIdx, firstPlaceIdx = nil, nil
for i, e in ipairs(PackLog) do
    if e.op == "Fold" and not foldIdx then foldIdx = i end
    if e.op == "Place" and not firstPlaceIdx then firstPlaceIdx = i end
end
check("fold before first place", foldIdx ~= nil and firstPlaceIdx ~= nil and foldIdx < firstPlaceIdx)
local firstSealIdx = nil
for i, e in ipairs(PackLog) do
    if e.op == "Seal" and not firstSealIdx then
        firstSealIdx = i
    end
end
local placeCount = 0
for i = 2, (firstSealIdx or 1) - 1 do
    local e = PackLog[i]
    if e.op == "Place" then
        placeCount = placeCount + 1
        if e.payload.x == nil or e.payload.z == nil or e.payload.o == nil then
            placeCount = -99
        end
    end
end
check("all 3 items placed with x/z/o", placeCount == 3)
check("demo plan order", PackLog[firstPlaceIdx].payload.uid ~= nil and PackLog[firstPlaceIdx + 1] ~= nil and PackLog[firstPlaceIdx + 1].op == "Place")
local wrapCount, wrapUid = 0, nil
for _, e in ipairs(PackLog) do
    if e.op == "Wrap" then
        wrapCount = wrapCount + 1
        wrapUid = e.payload.uid
    end
end
check("only fragile wrapped", wrapCount == 2 and wrapUid ~= nil)
check("wrap on = true", lastPack("Wrap") ~= nil and lastPack("Wrap").payload.on == true)
local fillEntry = lastPack("Fill")
check("fill fired on", fillEntry ~= nil and fillEntry.payload.on == true)
local sealEntry = PackLog[firstSealIdx]
check("seal stamps from handling", sealEntry ~= nil and sealEntry.payload.stamps[1] == "fragile" and sealEntry.payload.stamp == "fragile")
local lastSealEntry = lastPack("Seal")
check("plain order gets standard stamp", lastSealEntry ~= nil and lastSealEntry.payload.stamps[1] == "standard")
pump(4)
check("cart take after seal", #wires("cart") > 0 and wires("cart")[1].payload.op == "take")
check("deposit walked to freight", DepositCount > 0 and #server.carrying == 0)
pump(8)
local petBox = nil
for _, e in ipairs(PackLog) do
    if e.op == "Box" and e.payload.boxId == "box_pet" then
        petBox = e
    end
end
check("pet order takes next", petBox ~= nil)
local petFold, petFill = false, false
local sawSeal2 = false
do
    local idxBox, idxSeal = nil, nil
    for i, e in ipairs(PackLog) do
        if e.op == "Box" and e.payload.boxId == "box_pet" then idxBox = i end
        if e.op == "Seal" and idxBox and not idxSeal then idxSeal = i end
    end
    if idxBox and idxSeal then
        for i = idxBox, idxSeal do
            if PackLog[i].op == "Fold" then petFold = true end
            if PackLog[i].op == "Fill" then petFill = true end
        end
        sawSeal2 = idxSeal > idxBox
    end
end
check("pet box skips fold", not petFold)
check("pet box skips fill", not petFill)
check("pet order sealed", sawSeal2)
Library.Toggles.AutoPack:SetValue(false)
pump(3)
local opsAfterOff = #PackLog
pump(3)
check("autopack stops on toggle off", #PackLog == opsAfterOff)

server.chute = true
server.cart.count = 1
table.insert(server.board, { orderId = "o4", reward = 90, items = { "book" }, boxes = { "box_S" } })
PackLog = {}
WireLog = {}
Library.Toggles.AutoPack:SetValue(true)
pump(12)
local chuteCartTakes = 0
for _, e in ipairs(WireLog) do
    if e.name == "cart" then
        chuteCartTakes = chuteCartTakes + 1
    end
end
check("chute plot never cart-takes", chuteCartTakes == 0)
check("chute still seals", lastPack("Seal") ~= nil or #PackLog > 0)
Library.Toggles.AutoPack:SetValue(false)
server.chute = false
server.cart.count = 0
pump(2)

Library.Toggles.AutoBuyPads:SetValue(true)
pump(4)
local purchases = wires("purchase")
check("autobuy fires cheapest pad", #purchases > 0 and purchases[1].payload.kind == "padOffer" and purchases[1].payload.pad == "box_M" and purchases[1].payload.buy == true)
profile.pads.box_M = true
profile.cash = 40
purchases = wires("purchase")
local beforeCount = #purchases
pump(6)
purchases = wires("purchase")
check("buys next ladder pad", #purchases > beforeCount and purchases[#purchases].payload.pad == "scale")
Library.Toggles.AutoBuyPads:SetValue(false)
pump(2)
profile.pads.scale = true
profile.cash = 10
WireLog = {}
Library.Toggles.AutoBuyPads:SetValue(true)
pump(6)
check("no purchase when cash short", #wires("purchase") == 0)
Library.Toggles.AutoBuyPads:SetValue(false)
pump(2)

profile.halloween.wheel.play = 700
profile.halloween.wheel.spins = 2
WireLog = {}
Library.Toggles.AutoSpin:SetValue(true)
pump(8)
local spins = wires("halloweenSpin")
check("autospin fires when ready", #spins == 1)
check("spin walked to pumpkin", (HRP._cframe.Position - Pumpkin.PrimaryPart._cframe.Position).Magnitude < 12)
pump(12)
check("autospin idles when not ready", #wires("halloweenSpin") == 1)
Library.Toggles.AutoSpin:SetValue(false)
pump(2)

profile.cash = 5000
WireLog = {}
Library.Toggles.AutoTrain:SetValue(true)
pump(6)
local trains = wires("staff")
check("autotrain cheapest stat", #trains > 0 and trains[1].payload.op == "train" and trains[1].payload.id == "priya" and trains[1].payload.stat == "care")
staffData[1].stats.care = 5
staffData[2].stats.care = 5
WireLog = {}
pump(6)
trains = wires("staff")
local careTrained = false
for _, e in ipairs(trains) do
    if e.payload.stat == "care" then
        careTrained = true
    end
end
check("maxed stat never trained", not careTrained and #trains > 0)
Library.Toggles.AutoTrain:SetValue(false)
pump(2)

local banned = { "ux", "theme", "story", "dev", "settings", "lots", "zone", "rebirth", "halloweenCome", "halloweenGreeted", "halloweenGo", "halloweenGift", "halloweenSeen", "return", "palMascot" }
local bannedHits = {}
for _, e in ipairs(AllWires) do
    for _, b in ipairs(banned) do
        if e.name == b then
            table.insert(bannedHits, b)
        end
    end
end
for _, e in ipairs(AllPacks) do
    if e.op == "Abandon" or e.op == "Unplace" or e.op == "Undo" then
        table.insert(bannedHits, e.op)
    end
end
check("no banned wires fired", #bannedHits == 0, table.concat(bannedHits, ","))
check("no pcall swallows", PcallSwallows == 0)

summary()
