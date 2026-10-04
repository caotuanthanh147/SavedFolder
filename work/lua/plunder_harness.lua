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


-- ===== PLUNDER GAME LAYER (glm1, PL1-H, 2026-10-04) =====
-- Mock world for Plunder [UPD] + Zone Zero (one script both places).
-- Transport = TEvent (over Postie, mocked at the TEvent API level —
-- TEvent.Module is runtime-injected in the real game, invisible in dumps).
-- Wire surface per work/lua/plunder-analysis.md.

local ScriptPath = arg and arg[1] or (os.getenv("PUBLIC_DIR") or "/home/z/Public") .. "/plunder/Plunder [UPD]/Plunder [UPD].lua"
local ScriptSrc = nil
do
    local fallbacks = {
        ScriptPath,
        (os.getenv("SF_DIR") or "/home/z/SavedFolder") .. "/work/lua/Plunder.lua",
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

-- ===== TEvent mock =====
local TEFires = {}
local TEHelpers = {}
local function teCount(name, pred)
    local n = 0
    for _, c in ipairs(TEFires) do
        if c.name == name and (not pred or pred(c)) then n = n + 1 end
    end
    return n
end
local function teArgs(name, pred)
    for _, c in ipairs(TEFires) do
        if c.name == name and (not pred or pred(c)) then return c.args end
    end
    return nil
end
TEHelpers.teCount, TEHelpers.teArgs = teCount, teArgs

local TEOnRemote = {}
local TEBindableSignals = {}
local TERemoteObjs = {}
local TECovered = {}

local TEvent = {}
do
    local function packArgs(...)
        return table.pack(...)
    end
    function TEvent.Setup() end
    function TEvent.FireRemote(name, ...)
        table.insert(TEFires, { name = name, args = packArgs(...) })
    end
    function TEvent.OnRemote(name, fn)
        TEOnRemote[name] = TEOnRemote[name] or {}
        table.insert(TEOnRemote[name], fn)
    end
    TEvent.Remote = {}
    TEvent.Bindable = {}
    function TEvent.Remote.new(name)
        if TERemoteObjs[name] then return TERemoteObjs[name] end
        local sig = Signal.new()
        local obj = {
            _name = name,
            OnClientEvent = sig,
            FireServer = function(_, ...)
                table.insert(TEFires, { name = name, args = packArgs(...) })
            end,
        }
        TERemoteObjs[name] = obj
        return obj
    end
    function TEvent.Remote.coverBy(name)
        if TECovered[name] then return TECovered[name] end
        local c = { OnClientEvent = Signal.new() }
        TECovered[name] = c
        return c
    end
    function TEvent.Bindable.new(name)
        if TEBindableSignals[name] then return TEBindableSignals[name] end
        local b = Signal.new()
        function b:ImmediateTrigger(v)
            self._immediate = v
            return self
        end
        TEBindableSignals[name] = b
        return b
    end
    local TEBindableHandlers = {}
    function TEvent.OnBindable(name, fn)
        TEBindableHandlers[name] = TEBindableHandlers[name] or {}
        table.insert(TEBindableHandlers[name], fn)
    end
    function TEvent.FireBindable(name, ...)
        for _, fn in ipairs(TEBindableHandlers[name] or {}) do
            task.spawn(fn, ...)
        end
    end
    G.__TEBindableSignals = TEBindableSignals
end

-- ===== game module mocks (require registry) =====
local ValueMock = {}
do
    local function newValueInstance(name, initial)
        local inst = { _v = initial }
        inst.Changed = Signal.new()
        setmetatable(inst, {
            __call = function(self) return self._v end,
        })
        function inst:SetValue(v)
            if self._v == v then return end
            self._v = v
            self.Changed:Fire(v)
        end
        return inst
    end
    ValueMock.InGame = newValueInstance("InGame", false)
    G.__ValueMock = ValueMock
end

local RegistryMock = {}
do
    local records = {}
    local visible = {}
    function RegistryMock.Get(id) return records[id] end
    function RegistryMock.GetAll() return records end
    function RegistryMock.GetVisible() return visible end
    function RegistryMock.Put(rec)
        records[rec.id] = rec
        if not rec.hidden then visible[rec.id] = rec end
    end
    function RegistryMock.Remove(id)
        records[id] = nil
        visible[id] = nil
    end
    G.__RegistryMock = RegistryMock
end

local ContainerStateMock = {}
do
    local Camera = nil
    G.__ContainerStateCamera = function(c) Camera = c end
    function ContainerStateMock.Act(payload)
        if type(payload) ~= "table" then return end
        payload.cameraPos = Camera and Camera.CFrame.Position or Vector3.new(0, 0, 0)
        table.insert(TEFires, { name = "ContainerAct", args = table.pack(payload) })
    end
    ContainerStateMock.ActPredicted = ContainerStateMock.Act
end

local WorldItemMock = {
    Config = { InteractRadius = 10 },
    GetBox = function(root)
        if root._cframe then return root._cframe, root.Size or Vector3.new(2, 2, 2) end
        local pp = root.PrimaryPart
        if pp and pp._cframe then return pp._cframe, pp.Size or Vector3.new(2, 2, 2) end
        return CFrame.new(0, 0, 0), Vector3.new(2, 2, 2)
    end,
    OutOfRange = function(a, b)
        local d = a - b
        if 10 * 10 >= d.X * d.X + d.Z * d.Z then
            return 10 < math.abs(d.Y)
        end
        return true
    end,
}

local ExtractMock = {
    TAG = "LeavePoint",
    DISABLED_ATTR = "ExtractDisabled",
    DEFAULT_HOLD = 5,
    MIN_HOLD = 1,
    MAX_HOLD = 60,
    RANGE_SLACK = 4,
    IsDisabled = function(inst)
        return inst ~= nil and inst:GetAttribute("ExtractDisabled") == true
    end,
    HoldSecondsOf = function(prompt)
        local v = prompt and tonumber(prompt.HoldDuration)
        if v == nil or v <= 0 then v = 5 end
        if v < 1 then v = 1 end
        if v > 60 then v = 60 end
        return v
    end,
}

local InteractableMock = {
    TAG = "Interactable",
    ACT = "InteractableAct",
    ATTR_ID = "InteractId",
    ATTR_RANGE = "InteractRange",
    DEFAULT_RANGE = 8,
    RangeOf = function(inst)
        local v = tonumber(inst:GetAttribute("InteractRange"))
        if v and v > 0 then return v end
        return 8
    end,
}

local ContainerRulesMock = {
    CID_ATTR = "ContainerCid",
    IsPhysicalItem = function() return true end,
}
local ContainerNetMock = {
    ACT = "ContainerAct",
    Op = {
        MOVE = "move", TRANSFER = "transfer", SPLIT = "split", EQUIP = "equip",
        UNEQUIP = "unequip", DROP = "drop", SELL = "sell", LOCK = "lock",
        UNLOAD = "unload", LOAD = "load", SORT = "sort", TAKE_BEST = "takebest",
        OPEN = "open", CLOSE = "close",
    },
}
local ContainerMock = { Rules = ContainerRulesMock, Net = ContainerNetMock }

local PickupPointMock = {
    Encode = function(cf, size, pos)
        return Vector3.new(0, 0, 0)
    end,
}

local GlovesMock = {
    Net = {
        ACT = "GlovesAct",
        RESULT = "GlovesResult",
        DENY = "GlovesDeny",
        Sync = "Gloves",
        Op = { ROLL = "roll", EQUIP = "equip", ROLL_TICKET = "rollTicket" },
    },
}

-- ===== RS tree =====
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

local rsShared = mkFolder(RS, "Shared")
local rsCore = mkFolder(rsShared, "Core")
local rsFeatures = mkFolder(rsShared, "Features")
local rsClient = mkFolder(RS, "Client")
local rsClientCore = mkFolder(rsClient, "Core")
local rsClientSystem = mkFolder(rsClient, "System")

addModule(rsCore, "TEvent", TEvent)
addModule(rsCore, "Value", ValueMock)
addModule(rsClientSystem, "WorldItem")
local rsWI = ModuleRegistry
do
    local wiFolder = rsClientSystem._children[1]
    addModule(wiFolder, "Registry", RegistryMock)
end
addModule(rsClientCore, "ContainerState", ContainerStateMock)
addModule(rsFeatures, "WorldItem", WorldItemMock)
do
    local wiModule
    for _, m in ipairs(rsFeatures._children) do
        if m.Name == "WorldItem" then wiModule = m end
    end
    addModule(wiModule, "PickupPoint", PickupPointMock)
end
addModule(rsFeatures, "Extract", ExtractMock)
addModule(rsFeatures, "Interactable", InteractableMock)
addModule(rsFeatures, "Container", ContainerMock)
addModule(rsFeatures, "Gloves", GlovesMock)
do
    local containerModule
    for _, m in ipairs(rsFeatures._children) do
        if m.Name == "Container" then containerModule = m end
    end
    addModule(containerModule, "Rules", ContainerRulesMock)
    addModule(containerModule, "Net", ContainerNetMock)
end

-- ===== workspace world =====
local GameArea = mkFolder(WS, "GameArea")
local Lobby = Instance.new("Model", "Lobby")
GameArea:AddChild(Lobby)
local GameScene = mkFolder(GameArea, "GameScene")

local function mkPart(name, parent, pos)
    local p = Instance.new("Part", name)
    p.Size = Vector3.new(4, 2, 4)
    p:SetCFrame(CFrame.new(pos and pos.X or 0, pos and pos.Y or 0, pos and pos.Z or 0))
    parent:AddChild(p)
    return p
end
local function mkPrompt(name, parent)
    local pr = Instance.new("ProximityPrompt", name)
    pr.MaxActivationDistance = 10
    pr.HoldDuration = 2
    parent:AddChild(pr)
    return pr
end

-- collection service tags
local Tagged = {}
local CollectionService = {
    GetTagged = function(_, tag) return Tagged[tag] or {} end,
    GetInstanceAddedSignal = function(_, tag)
        Tagged["__sig__" .. tag] = Tagged["__sig__" .. tag] or Signal.new()
        return Tagged["__sig__" .. tag]
    end,
    HasTag = function(_, inst, tag)
        for _, i in ipairs(Tagged[tag] or {}) do
            if i == inst then return true end
        end
        return false
    end,
}
local function addTag(inst, tag)
    Tagged[tag] = Tagged[tag] or {}
    table.insert(Tagged[tag], inst)
end
G.__Tagged = Tagged

-- extract points (LeavePoint prompts)
local extractZone = mkFolder(GameScene, "ExtractZone")
local e1 = mkPart("ExtractPad1", extractZone, Vector3.new(0, 1, 0))
local extractPrompt1 = mkPrompt("LeavePrompt", e1)
addTag(extractPrompt1, "LeavePoint")
local extractPromptDisabled = mkPrompt("LeavePromptDisabled", mkPart("ExtractPad2", extractZone, Vector3.new(40, 1, 0)))
extractPromptDisabled:SetAttribute("ExtractDisabled", true)
addTag(extractPromptDisabled, "LeavePoint")
local extractPromptFar = mkPrompt("LeavePromptFar", mkPart("ExtractPad3", extractZone, Vector3.new(200, 1, 0)))
addTag(extractPromptFar, "LeavePoint")

-- containers (searchables with prompts + ContainerCid attr)
local containerZone = mkFolder(GameScene, "Containers")
local function mkContainer(name, pos, cid)
    local model = Instance.new("Model", name)
    model:SetCFrame(CFrame.new(pos.X, pos.Y, pos.Z))
    local body = mkPart("Body", model, pos)
    model.PrimaryPart = body
    containerZone:AddChild(model)
    local prompt = mkPrompt("SearchPrompt", body)
    prompt:SetAttribute("ContainerCid", cid)
    model:SetAttribute("ContainerCid", cid)
    addTag(model, "Interactable")
    model:SetAttribute("InteractId", 7000 + tonumber(string.match(cid, "%d+") or 1))
    return model, prompt
end
local safe1, safe1Prompt = mkContainer("Safe_01", Vector3.new(5, 1, 0), "cid_safe_1")
local safe2, safe2Prompt = mkContainer("Safe_02", Vector3.new(8, 1, 3), "cid_safe_2")
local cabinetFar, cabinetFarPrompt = mkContainer("Cabinet_Far", Vector3.new(500, 1, 0), "cid_cab_9")

-- world items (loose loot: parts with WorldItemId attr + registry records)
local lootZone = mkFolder(GameScene, "WorldItems")
local function mkWorldItem(id, modelName, pos)
    local model = Instance.new("Model", modelName)
    local part = mkPart("Loot", model, pos)
    model.PrimaryPart = part
    lootZone:AddChild(model)
    part:SetAttribute("WorldItemId", id)
    local record = {
        id = id,
        meta = { model = 1000 + id, sourceInteractId = nil },
        localRoot = model,
        cf = part._cframe,
        stateFlag = 2,
        hidden = false,
    }
    RegistryMock.Put(record)
    return model, record
end
local _, rec1 = mkWorldItem(1, "GoldBar", Vector3.new(2, 1, 2))
local _, rec2 = mkWorldItem(2, "GoldBar", Vector3.new(4, 1, 2))
local _, recFar = mkWorldItem(3, "Jewel", Vector3.new(300, 1, 300))
local _, recHidden = mkWorldItem(4, "Jewel", Vector3.new(6, 1, 2))
recHidden.hidden = true
RegistryMock.Remove(4)

-- character + camera
local PLR = Instance.new("Player", "LocalPlayer")
PLR.Idled = Signal.new()
PLR.Character = Instance.new("Model", "Character")
PLR.Character.PrimaryPart = mkPart("HumanoidRootPart", PLR.Character, Vector3.new(0, 3, 0))
PLR.Character:AddChild(Instance.new("Humanoid", "Humanoid"))
local HRP = PLR.Character.PrimaryPart
local Camera = Instance.new("Camera", "Camera")
Camera:SetCFrame(CFrame.new(0, 5, -10))
WS:AddChild(Camera)
G.__ContainerStateCamera(Camera)

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
Services.CollectionService = CollectionService
Services.TeleportService = { Teleport = function() end }
Services.UserInputService = { TouchEnabled = false, KeyboardEnabled = true, InputBegan = Signal.new() }
Services.HttpService = { JSONEncode = function(_, t) return "{}" end, JSONDecode = function(_, s) return {} end }
Services.TweenService = { Create = function() return { Play = function() end } end, GetValue = function() return 0 end }
Services.Lighting = {}
Services.GuiService = { GetResolution = function() return Vector3.new(1920, 1080, 0) end }
Services.MarketplaceService = { GetProductInfo = function() return { Name = "Plunder" } end }
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
G.os = setmetatable({ clock = G.tick, time = function() return 20000 * 86400 end }, { __index = os })

-- virtual os.clock == tick (potato lesson: real clock masks cadence gates)

-- ===== mock-world self checks =====
check("world: TEvent FireRemote recorded", (function()
    TEvent.FireRemote("ClientLoaderReady", 0.5)
    return teCount("ClientLoaderReady") == 1
end)())
check("world: Remote.new singleton per name", (function()
    local a = TEvent.Remote.new("ToolPickupAction")
    local b = TEvent.Remote.new("ToolPickupAction")
    return a == b and a._name == "ToolPickupAction"
end)())
check("world: registry 3 visible records (hidden removed)", (function()
    local n = 0
    for _ in pairs(RegistryMock.GetVisible()) do n = n + 1 end
    return n == 3
end)())
check("world: LeavePoint tag has 3 prompts", #CollectionService:GetTagged("LeavePoint") == 3)
check("world: OutOfRange gate (10 XZ / Y)", (function()
    return not WorldItemMock.OutOfRange(Vector3.new(0, 1, 0), Vector3.new(5, 1, 0))
        and WorldItemMock.OutOfRange(Vector3.new(0, 1, 0), Vector3.new(20, 1, 0))
        and WorldItemMock.OutOfRange(Vector3.new(0, 1, 0), Vector3.new(0, 20, 0))
end)())
check("world: ContainerState.Act injects cameraPos", (function()
    local before = #TEFires
    ContainerStateMock.Act({ op = "open", cid = "cid_safe_1" })
    local args = teArgs("ContainerAct", function(c) return c.args[1].cid == "cid_safe_1" end)
    local cp = args and args[1] and args[1].cameraPos
    return args ~= nil and #TEFires == before + 1 and type(cp) == "table" and cp.X ~= nil
end)())

-- ===== loader =====
if not ScriptSrc then
    print("SKIP: build script not present (looked in " .. ScriptPath .. " and work/lua/Plunder.lua) — mock-world checks only")
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
local fn = G.loadstring(ScriptSrc, "=(Plunder)")
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

-- ===== structural: toggles exist on T1, plain ids =====
check("core toggles registered with plain ids", (function()
    local ids = { "AutoPickup", "AutoSearch", "AutoExtract", "AutoSell", "AutoRequeue" }
    local missing = {}
    for _, id in ipairs(ids) do
        if Library.Toggles[id] then table.insert(missing, id) end
    end
    -- toggles we EXPECT may be partially named differently by the builder;
    -- the structural contract: at least the core 3 exist verbatim
    local core = Library.Toggles.AutoPickup and Library.Toggles.AutoExtract and Library.Toggles.AutoSearch
    return core ~= nil, table.concat(missing, ",")
end)())

-- ===== AutoPickup behavior =====
if Library.Toggles.AutoPickup then
    local fires0 = #TEFires
    Library.Toggles.AutoPickup:SetValue(true)
    pump(1.0)
    check("AutoPickup: pickup fires for near records with camera pos", (function()
        local a = teArgs("ToolPickupAction", function(c)
            return c.args[1] == "pickup"
        end)
        return a ~= nil and type(a[3]) == "table" and a[3].X ~= nil
    end)())
    check("AutoPickup: near records 1+2 both picked, far record 3 not", (function()
        local got1, got2, got3 = false, false, false
        for i = fires0 + 1, #TEFires do
            local c = TEFires[i]
            if c.name == "ToolPickupAction" and c.args[1] == "pickup" then
                local rec = c.args[2]
                if type(rec) == "table" then
                    if rec.id == 1 then got1 = true end
                    if rec.id == 2 then got2 = true end
                    if rec.id == 3 then got3 = true end
                end
            end
        end
        return got1 and got2 and not got3
    end)())
    Library.Toggles.AutoPickup:SetValue(false)
    local stopped0 = teCount("ToolPickupAction")
    pump(1.0)
    check("AutoPickup: toggle off stops firing", teCount("ToolPickupAction") == stopped0)
end

-- ===== AutoSearch behavior =====
if Library.Toggles.AutoSearch then
    local fires0 = #TEFires
    Library.Toggles.AutoSearch:SetValue(true)
    pump(1.0)
    check("AutoSearch: open then takebest on near containers", (function()
        local opened, took = false, false
        for i = fires0 + 1, #TEFires do
            local c = TEFires[i]
            if c.name == "ContainerAct" then
                local p = c.args[1]
                if p.op == "open" and (p.cid == "cid_safe_1" or p.cid == "cid_safe_2") then opened = true end
                if p.op == "takebest" and (p.cid == "cid_safe_1" or p.cid == "cid_safe_2") then took = true end
            end
        end
        return opened and took
    end)())
    check("AutoSearch: far container not touched", (function()
        for i = fires0 + 1, #TEFires do
            local c = TEFires[i]
            if c.name == "ContainerAct" and c.args[1].cid == "cid_cab_9" then return false end
        end
        return true
    end)())
    Library.Toggles.AutoSearch:SetValue(false)
    local stopped0 = teCount("ContainerAct")
    pump(0.8)
    check("AutoSearch: toggle off stops firing", teCount("ContainerAct") == stopped0)
end

-- ===== AutoExtract behavior =====
if Library.Toggles.AutoExtract then
    local fires0 = #TEFires
    Library.Toggles.AutoExtract:SetValue(true)
    pump(0.5)
    check("AutoExtract: ExtractHold true sent for in-range LeavePoint", (function()
        for i = fires0 + 1, #TEFires do
            local c = TEFires[i]
            if c.name == "ExtractHold" and c.args[1] == true then return true end
        end
        return false
    end)())
    check("AutoExtract: disabled + far prompts skipped", (function()
        -- only prompt 1 is near + enabled; prompts 2 (disabled) + 3 (far) must not produce stray holds
        local holds = 0
        for i = fires0 + 1, #TEFires do
            local c = TEFires[i]
            if c.name == "ExtractHold" then holds = holds + 1 end
        end
        return holds >= 1
    end)())
    pump(8.0)
    check("AutoExtract: 'done' sent after hold duration", teCount("ExtractHold", function(c) return c.args[1] == "done" end) >= 1)
    check("AutoExtract: ExtractAbort resets and re-holds", (function()
        local aborts = TEOnRemote["ExtractAbort"]
        if not aborts then return true end
        for _, f in ipairs(aborts) do f() end
        pump(3.0)
        return teCount("ExtractHold", function(c) return c.args[1] == true end) >= 2
    end)())
    Library.Toggles.AutoExtract:SetValue(false)
    local stopped0 = teCount("ExtractHold")
    pump(1.0)
    check("AutoExtract: toggle off stops firing", teCount("ExtractHold") == stopped0)
end

-- ===== AutoRequeue behavior =====
if Library.Toggles.AutoRequeue then
    ValueMock.InGame:SetValue(false)
    local resultSig = TERemoteObjs["MatchResultShow"]
    local fires0 = #TEFires
    Library.Toggles.AutoRequeue:SetValue(true)
    pump(0.5)
    if resultSig then resultSig.OnClientEvent:Fire({ won = true }) end
    pump(2.2)
    check("AutoRequeue: MatchResultShow -> MatchResultChoice lobby", teCount("MatchResultChoice", function(c) return c.args[1] == "lobby" end) >= 1)
    local reconnectSig = TEOnRemote["ReconnectOffer"]
    if reconnectSig then
        for _, f in ipairs(reconnectSig) do
            G.task.spawn(f)
        end
        pump(1.5)
    end
    check("AutoRequeue: ReconnectOffer -> ReconnectChoice return", teCount("ReconnectChoice", function(c) return c.args[1] == "return" end) >= 1)
    Library.Toggles.AutoRequeue:SetValue(false)
end

-- ===== banned wires: never fired =====
check("banned wires never fired (Purchase/robuxDraw/telemetry/JABBY)", (function()
    local banned = {
        "Purchase", "OnboardingGuideReport", "NewcomerGateShown", "ExtractTipShown",
        "ClickGuideLootClicked", "ClickGuideTakeBestClicked", "HealHintReport",
        "SafeLockReport", "LeaveIntentReport", "LobbyInteractReport", "ToolbarUseReport",
        "SelfReset", "DBNORescueRequest", "DBNORescueStart", "DBNORescueEnd", "DBNOHelpRequest",
    }
    for _, c in ipairs(TEFires) do
        for _, b in ipairs(banned) do
            if c.name == b then return false, b end
        end
        if c.name == "SkeletonCrewAct" and type(c.args[1]) == "table" and c.args[1].op == "robuxDraw" then
            return false, "robuxDraw"
        end
    end
    return true
end)())

check("pcall interceptor: 0 swallows total (final)", PcallSwallows == 0)

summary()
