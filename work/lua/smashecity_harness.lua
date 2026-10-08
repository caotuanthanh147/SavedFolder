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


-- ####################################################################
-- Smash the City (STC1) real-load harness — game world + checks.
-- World model per work/lua/smashecity-analysis.md: client-authoritative
-- Economy + module-scope adapter (Core.Input.start upvalue) + callbacks
-- (Core.UI.build upvalue) + Cooldowns spec table (spec upvalue).

local ScriptPath = arg and arg[1]
local ScriptSrc = nil
do
    local fallbacks = {
        (os.getenv("SF_DIR") or "/home/z/SavedFolder") .. "/work/lua/SmashTheCity.lua",
        (os.getenv("PUBLIC_DIR") or "/home/z/Public") .. "/Smash the City/Smash the City.lua",
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
assert(ScriptSrc, "script under test not found (pass path as arg[1])")

G.os = setmetatable({ clock = function() return Sched.now end }, { __index = os })

local UpvalueRegistry = {}
G.getupvalues = function(f)
    return UpvalueRegistry[f]
end
G.get_up_values = nil

-- ===== Config mock (real data subset) =====
local ConfigMock = {
    CITY_HALF = 440,
    GROUND_Y = 0,
    SHOP = {
        EARN = { cell = 1, prop = 10, other = 5 },
        DEFAULT_PRICE = 10000,
        WEAPONS = { Missile = 0, Meteor = 12000, Nuke = 150000 },
        MAPS = { Downtown = 0, Coast = 12000 },
    },
    COOLDOWNS = {
        Nuke = 30,
        Meteor = 6,
    },
}

-- ===== Economy mock (real client-authoritative logic) =====
local FlushLog = {}
local EcoListeners = {}
local EcoMock
do
    local cash = 0
    local owned = { weapon = {}, map = {} }
    local passes = {}
    local loadedData = { cash = 0, tester = false, infinite = false, canWipe = false }
    local dirty = false
    local function flush()
        local list = {}
        for kind, ids in pairs(owned) do
            for id in pairs(ids) do
                table.insert(list, kind .. ":" .. id)
            end
        end
        table.insert(FlushLog, { cash = math.floor(cash), owned = list })
        dirty = false
    end
    EcoMock = {
        cash = function() return cash end,
        owns = function(kind, id)
            local price = EcoMock.price(kind, id)
            if price <= 0 then return true end
            return owned[kind] and owned[kind][id] == true
        end,
        price = function(kind, id)
            local source = kind == "map" and ConfigMock.SHOP.MAPS or ConfigMock.SHOP.WEAPONS
            return source[id] or ConfigMock.SHOP.DEFAULT_PRICE
        end,
        canAfford = function(kind, id)
            return EcoMock.price(kind, id) <= cash
        end,
        buy = function(kind, id)
            if EcoMock.owns(kind, id) then return true end
            local price = EcoMock.price(kind, id)
            if cash < price then return false end
            cash = cash - price
            owned[kind][id] = true
            dirty = true
            flush()
            for _, fn in ipairs(EcoListeners) do
                pcall(fn, cash, -price, "buy", { kind = kind, id = id })
            end
            return true
        end,
        earn = function(n)
            if n <= 0 then return end
            cash = cash + n
            dirty = true
            for _, fn in ipairs(EcoListeners) do
                pcall(fn, cash, n, "break", nil)
            end
        end,
        setCash = function(n)
            cash = math.max(math.floor(n), 0)
            dirty = true
            flush()
            for _, fn in ipairs(EcoListeners) do
                pcall(fn, cash, 0, "set", nil)
            end
        end,
        unlockAll = function()
            for id in pairs(ConfigMock.SHOP.WEAPONS) do
                owned.weapon[id] = true
            end
            for id in pairs(ConfigMock.SHOP.MAPS) do
                owned.map[id] = true
            end
            dirty = true
            flush()
        end,
        onChanged = function(fn)
            table.insert(EcoListeners, fn)
        end,
        loaded = function()
            return loadedData
        end,
        markDirty = function()
            dirty = true
        end,
    }
    EcoMock.__owned = owned
    EcoMock.__flushCount = function() return #FlushLog end
end

-- ===== Cooldowns mock (real require-time spec copy) =====
local CooldownsMock
do
    local specs = {}
    for id, v in pairs(ConfigMock.COOLDOWNS) do
        local t = type(v) == "number" and v or v[1]
        specs[id] = { t = t, key = id, held = false, action = false, owner = false }
    end
    CooldownsMock = {
        spec = function(id)
            return specs[id]
        end,
        __specs = specs,
    }
    UpvalueRegistry[CooldownsMock.spec] = { specs }
end

-- ===== Destruction mock (stats under harness control) =====
local StatsState = { total = 1000, intact = 1000, debris = 0, chunks = 0, active = 0, pressure = 0, destroyed = 0 }
local DestructionMock = {
    getStats = function()
        return StatsState
    end,
}

-- ===== Challenges mock =====
local DailyState = { claimed = false, streak = 1, slot = 1 }
local ChallengeList = {
    { i = 1, id = "city75", text = "Destroy 75%", kind = "cityPct", goal = 0.75, prog = 0.8, reward = 1500, claimed = false, done = true },
    { i = 2, id = "cells100", text = "Break 100 cells", kind = "cells", goal = 100, prog = 10, reward = 500, claimed = false, done = false },
    { i = 3, id = "city95", text = "Destroy 95%", kind = "cityPct", goal = 0.95, prog = 1, reward = 2000, claimed = true, done = true },
}
local ClaimDailyCalls = 0
local ClaimChallengeCalls = {}
local ChallengesMock = {
    daily = function()
        return { slot = DailyState.slot, claimed = DailyState.claimed, streak = DailyState.streak, rewards = {}, nextIn = 0 }
    end,
    challenges = function()
        return { list = ChallengeList, nextIn = 0 }
    end,
    claimDaily = function()
        ClaimDailyCalls = ClaimDailyCalls + 1
        DailyState.claimed = true
        return { ok = true, coins = 500 }
    end,
    claimChallenge = function(i)
        table.insert(ClaimChallengeCalls, i)
        ChallengeList[i].claimed = true
        return { ok = true, coins = ChallengeList[i].reward }
    end,
}

-- ===== adapter + callbacks mocks (upvalue surfaces) =====
local AdapterCalls = {}
local AdapterMock = {
    call = function(method, pos)
        table.insert(AdapterCalls, { method = method, pos = pos, at = Sched.now })
    end,
    getWeapon = function() return nil end,
    pick = function(x, y) return Vector3.zero end,
    key = function() end,
}
local OnSelectCalls = {}
local OnResetCalls = {}
local CallbacksMock = {
    onSelect = function(id)
        table.insert(OnSelectCalls, id)
    end,
    onReset = function()
        OnResetCalls[#OnResetCalls + 1] = Sched.now
    end,
    onNextCity = function() end,
    onResults = function() end,
}

-- ===== UI / Input module mocks =====
local UIMock
do
    local stored = nil
    UIMock = {
        build = function(arg)
            stored = arg.callbacks
        end,
        __stored = function() return stored end,
    }
    UpvalueRegistry[UIMock.build] = { CallbacksMock }
end
local InputMock
do
    local stored = nil
    InputMock = {
        start = function(_, adapter)
            stored = adapter
        end,
        __stored = function() return stored end,
    }
    UpvalueRegistry[InputMock.start] = { AdapterMock }
end

-- simulate the game having wired UI/Input already
UIMock.build({ callbacks = CallbacksMock })
InputMock.start(nil, AdapterMock)

-- ===== RS tree + require registry =====
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
local function mkFolder(parent, name)
    local f = Instance.new("Folder", name)
    parent:AddChild(f)
    return f
end

local smashFolder = mkFolder(RS, "Smash")
local coreFolder = mkFolder(smashFolder, "Core")
addModule(smashFolder, "Config", ConfigMock)
addModule(coreFolder, "Economy", EcoMock)
addModule(coreFolder, "Cooldowns", CooldownsMock)
addModule(coreFolder, "Destruction", DestructionMock)
addModule(coreFolder, "Challenges", ChallengesMock)
addModule(coreFolder, "UI", UIMock)
addModule(coreFolder, "Input", InputMock)

-- ===== SmashRemotes banned-wire recorders =====
local RemoteFires = {}
local function addRemote(parent, name)
    local r = Instance.new("RemoteEvent", name)
    parent:AddChild(r)
    r.__fires = {}
    r.FireServer = function(_, ...)
        table.insert(RemoteFires, { name = name, args = { ... } })
    end
    return r
end
local remotesFolder = mkFolder(RS, "SmashRemotes")
local BannedRemotes = { "Save", "BuyRobux", "BuyPass", "BuyPack", "TestWipe", "TestDay", "SkipCooldown", "MiniNuke", "ServerNuke", "Likes", "Street" }
for _, name in ipairs(BannedRemotes) do
    addRemote(remotesFolder, name)
end

-- ===== services / game / player =====
local PLR = {
    UserId = 42,
    Name = "Tester",
    DisplayName = "",
    Character = nil,
    CameraMaxZoomDistance = 128,
    Idled = Signal.new(),
    GetAttribute = function() return nil end,
    GetAttributeChangedSignal = function() return Signal.new() end,
    SetAttribute = function() end,
}
local Services = {}
Services.Players = { LocalPlayer = PLR, GetPlayers = function() return { PLR } end }
Services.ReplicatedStorage = RS
Services.RunService = {
    Stepped = Signal.new(), RenderStepped = Signal.new(), Heartbeat = Signal.new(),
    PostSimulation = Signal.new(),
    IsServer = function() return false end, IsStudio = function() return false end,
    IsClient = function() return true end,
}
Services.TeleportService = { Teleport = function() end, TeleportToPlaceInstance = function() end }
Services.UserInputService = { TouchEnabled = false, KeyboardEnabled = true, InputBegan = Signal.new() }
Services.HttpService = { JSONEncode = function(_, t) return "{}" end, JSONDecode = function(_, s) return {} end, GenerateGUID = function() return "g" end }
Services.TweenService = { Create = function() return { Play = function() end } end, GetValue = function() return 0 end }
Services.Lighting = {}
Services.GuiService = { GetResolution = function() return Vector3.new(1920, 1080, 0) end, ErrorMessageChanged = Signal.new() }
Services.MarketplaceService = { GetProductInfo = function() return { Name = "Smash the City" } end }
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
G.OverlapParams = { new = function() return { FilterType = nil, FilterDescendantsInstances = {} } end }
local enumChildren = setmetatable({}, { __index = function(t, k)
    local c = setmetatable({}, { __index = function(_, k2) return k2 end })
    rawset(t, k, c)
    return c
end })
G.Enum = enumChildren
G.getconnections = nil

-- ===== load the script under test =====
print("script under test: " .. tostring(ScriptPath))

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
local fn = G.loadstring(ScriptSrc, "=(SmashTheCity)")
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
check("core toggles registered with plain ids", Library.Toggles.AutoFire ~= nil
    and Library.Toggles.AutoCityReset ~= nil
    and Library.Toggles.NoCooldown ~= nil
    and Library.Toggles.AutoBuy ~= nil
    and Library.Toggles.AutoClaim ~= nil)
check("core options registered", Library.Options.AutoFireWeapon ~= nil
    and Library.Options.AutoFireDelay ~= nil
    and Library.Options.AutoCityPct ~= nil
    and Library.Options.CheatCashAmount ~= nil)
check("weapon dropdown = Config.SHOP.WEAPONS sorted, default Nuke", (function()
    local d = Library.Options.AutoFireWeapon
    return type(d.Values) == "table"
        and d.Values[1] == "Meteor"
        and d.Values[2] == "Missile"
        and d.Values[3] == "Nuke"
        and d.Value == "Nuke"
end)())
check("cheat buttons registered", (function()
    local addCash, unlockAll = false, false
    for _, b in ipairs(MockState.Buttons) do
        if b.Text == "Add Cash" then addCash = true end
        if b.Text == "Unlock All" then unlockAll = true end
    end
    return addCash and unlockAll
end)())

-- ===== AutoFire: waiting (Nuke unowned) then firing after unlock =====
do
    Library.Toggles.AutoFire:SetValue(true)
    pump(1.0)
    check("AutoFire: no fires while weapon unowned", #AdapterCalls == 0)
    check("AutoFire: waiting notify shown once", (function()
        local n = 0
        for _, msg in ipairs(MockState.Notifies) do
            if string.find(msg, "Waiting for weapon", 1, true) then n = n + 1 end
        end
        return n == 1
    end)())
    local buttons = {}
    for _, b in ipairs(MockState.Buttons) do
        buttons[b.Text] = b
    end
    buttons["Unlock All"].Func()
    check("UnlockAll: all weapons + maps owned", EcoMock.owns("weapon", "Nuke")
        and EcoMock.owns("weapon", "Meteor")
        and EcoMock.owns("map", "Coast"))
    check("UnlockAll: flush recorded with owned list", (function()
        local last = FlushLog[#FlushLog]
        return last ~= nil and #last.owned >= 5
    end)())
    pump(2.0)
    check("AutoFire: fires after unlock (adapter calls)", #AdapterCalls >= 3)
    check("AutoFire: onSelect called with weapon", #OnSelectCalls >= 1 and OnSelectCalls[1] == "Nuke")
    check("AutoFire: tuple shape (onTap, Vector3)", (function()
        local c = AdapterCalls[1]
        return c ~= nil and c.method == "onTap" and type(c.pos) == "table" and c.pos.X ~= nil
    end)())
    check("AutoFire: grid order (-375,-120) then (-250,-120) then (-125,-120)", (function()
        local a = AdapterCalls[1].pos
        local b = AdapterCalls[2].pos
        local c = AdapterCalls[3].pos
        return a.X == -375 and a.Z == -120
            and b.X == -250 and b.Z == -120
            and c.X == -125 and c.Z == -120
    end)())
    check("AutoFire: interval respected (~0.35s between shots)", (function()
        local a = AdapterCalls[2].at - AdapterCalls[1].at
        return a >= 0.3 and a <= 0.5
    end)())
    local fired = #AdapterCalls
    Library.Toggles.AutoFire:SetValue(false)
    pump(1.5)
    check("AutoFire: toggle off stops firing", #AdapterCalls == fired)
end

-- ===== NoCooldown: spec zero + restore + unload restore =====
do
    local specs = CooldownsMock.__specs
    check("NoCooldown initial specs intact", specs.Nuke.t == 30 and specs.Meteor.t == 6)
    Library.Toggles.NoCooldown:SetValue(true)
    check("NoCooldown: all spec t zeroed", specs.Nuke.t == 0 and specs.Meteor.t == 0)
    Library.Toggles.NoCooldown:SetValue(false)
    check("NoCooldown: toggle off restores", specs.Nuke.t == 30 and specs.Meteor.t == 6)
    Library.Toggles.NoCooldown:SetValue(true)
    Library:Unload()
    check("NoCooldown: unload restores", specs.Nuke.t == 30 and specs.Meteor.t == 6)
end

-- ===== AutoCityReset: threshold + window + stall =====
do
    StatsState.destroyed = 0.9
    Library.Toggles.AutoCityReset:SetValue(true)
    pump(2.0)
    check("AutoCityReset: threshold triggers onReset", #OnResetCalls >= 1)
    local resets = #OnResetCalls
    pump(3.0)
    check("AutoCityReset: 5s window holds (no second reset)", #OnResetCalls == resets)
    pump(3.0)
    check("AutoCityReset: window passes, resets again", #OnResetCalls > resets)
    StatsState.destroyed = 0.5
    local resets2 = #OnResetCalls
    EcoMock.earn(5)
    pump(3.0)
    check("AutoCityReset: no reset below threshold while earning", #OnResetCalls == resets2)
    pump(10.5)
    check("AutoCityReset: earn stall (13s no earn) triggers reset", #OnResetCalls > resets2)
    Library.Toggles.AutoCityReset:SetValue(false)
    StatsState.destroyed = 0.95
    local resets3 = #OnResetCalls
    pump(2.0)
    check("AutoCityReset: toggle off stops resetting", #OnResetCalls == resets3)
    StatsState.destroyed = 0
end

-- ===== AutoBuy: cheapest first, affordability gated =====
do
    for k in pairs(EcoMock.__owned.weapon) do
        EcoMock.__owned.weapon[k] = nil
    end
    for k in pairs(EcoMock.__owned.map) do
        EcoMock.__owned.map[k] = nil
    end
    EcoMock.setCash(0)
    local flushes0 = #FlushLog
    Library.Toggles.AutoBuy:SetValue(true)
    pump(6.0)
    check("AutoBuy: nothing bought while broke", not EcoMock.owns("weapon", "Meteor") and not EcoMock.owns("map", "Coast"))
    EcoMock.setCash(20000)
    pump(6.0)
    check("AutoBuy: cheapest weapon bought first (Meteor 12000)", EcoMock.owns("weapon", "Meteor"))
    check("AutoBuy: map not bought (8000 < 12000)", not EcoMock.owns("map", "Coast"))
    check("AutoBuy: free items never re-bought (Missile price 0)", (function()
        for i = flushes0 + 1, #FlushLog do
            for _, entry in ipairs(FlushLog[i].owned) do
                if entry == "weapon:Missile" then return false end
            end
        end
        return true
    end)())
    EcoMock.setCash(12000)
    pump(6.0)
    check("AutoBuy: map bought once affordable", EcoMock.owns("map", "Coast"))
    Library.Toggles.AutoBuy:SetValue(false)
end

-- ===== AutoClaim: daily + done challenges only =====
do
    Library.Toggles.AutoClaim:SetValue(true)
    pump(1.0)
    check("AutoClaim: daily claimed", ClaimDailyCalls == 1)
    check("AutoClaim: only done+unclaimed challenges claimed", (function()
        return #ClaimChallengeCalls == 1 and ClaimChallengeCalls[1] == 1
    end)())
    pump(35.0)
    check("AutoClaim: no repeat claims after state flips", ClaimDailyCalls == 1 and #ClaimChallengeCalls == 1)
    Library.Toggles.AutoClaim:SetValue(false)
end

-- ===== CheatCash =====
do
    local cash0 = EcoMock.cash()
    local buttons = {}
    for _, b in ipairs(MockState.Buttons) do
        buttons[b.Text] = b
    end
    buttons["Add Cash"].Func()
    check("CheatCash: cash + default 1000000", EcoMock.cash() == cash0 + 1000000)
    check("CheatCash: flush carries new cash to the save wire", FlushLog[#FlushLog].cash == EcoMock.cash())
end

-- ===== banned-wire sweep =====
check("banned-wire sweep: zero fires on REMOVE remotes", #RemoteFires == 0)

-- ===== save manager folder =====
check("SaveManager folder Yuri/SmashTheCity", SaveManager.Folder == "Yuri/SmashTheCity")

check("pcall interceptor: 0 silent swallows total", PcallSwallows == 0)

summary()
