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

-- ===== SHIGAKU HARNESS — SH3 (glm1, 2026-10-03) ============================
-- Mock world from the independent census (deobf 258k + dump 107k lines) —
-- cross-checked against SH1's shigaku-analysis.md (glm2, b4cae09); all paths
-- re-verified in dump/deobf: Game_Settings/Appearance/Muscle/GymWeights under
-- RS.Shared.Modules.*, Client.Input/Client.Data under PlayerScripts.Client,
-- ReferenceBridge (deobf L2197/L3682/L5105), CombatDummy/Gym* tags, Files.
-- Assets.Models weight tree. Census: 32 RemoteEvent, 0 RemoteFunction.
-- SH2 wire checks (Input.Fire tuples, Gym.Sync/Character.Action bridge tuples,
-- Data reads, toggle-off stop) activate automatically when work/lua/Shigaku.lua
-- lands (live loader below). Single place — no lobby/game split.

local ScriptPath = (arg and arg[1]) or "/home/z/SavedFolder/work/lua/Shigaku.lua"

G.os = { clock = function() return Sched.now end, time = os.time, date = os.date }

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

local MockFS = {}
G.writefile = function(p, c) MockFS[p] = c end
G.readfile = function(p) return MockFS[p] end
G.isfile = function(p) return MockFS[p] ~= nil end
G.isfolder = function(p) return true end
G.makefolder = function(p) end
G.listfiles = function(p)
    local out = {}
    for k in pairs(MockFS) do
        if k:sub(1, #p) == p then
            table.insert(out, k)
        end
    end
    table.sort(out)
    return out
end
G.listfolder = G.listfiles
G.appendfile = function(p, c) MockFS[p] = (MockFS[p] or "") .. c end
G.delfile = function(p) MockFS[p] = nil end
local TeleportQueue = {}
G.queue_on_teleport = function(code) table.insert(TeleportQueue, code) end
G.queueonteleport = G.queue_on_teleport
local WebhookLog = {}
G.request = function(t)
    table.insert(WebhookLog, t)
    return { Success = true }
end
G.http_request = G.request
local MockExecContext = false
G.checkcaller = function() return MockExecContext end
G.iscaller = G.checkcaller
G.newcclosure = function(f) return f end

-- ===== world tree (dump-faithful paths) =====
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

local PlayerScripts = Instance.new("Folder", "PlayerScripts")
PLR:AddChild(PlayerScripts)
local ClientDir = Instance.new("Folder", "Client")
PlayerScripts:AddChild(ClientDir)

local Packages = Instance.new("Folder", "Packages")
RS:AddChild(Packages)
local IndexFolder = Instance.new("Folder", "_Index")
Packages:AddChild(IndexFolder)
local BNIndex = Instance.new("Folder", "ffrostflame_bridgenet2@1.0.0")
IndexFolder:AddChild(BNIndex)
local BNClient = Instance.new("Folder", "bridgenet2")
BNIndex:AddChild(BNClient)
local BNClientDir = Instance.new("Folder", "Client")
BNClient:AddChild(BNClientDir)

local BNRoot = Instance.new("Folder", "ffrostflame_bridgenet2@1.0.0")
RS:AddChild(BNRoot)
local BNIds = Instance.new("Folder", "identifierStorage")
BNRoot:AddChild(BNIds)
local BNMeta = Instance.new("RemoteEvent", "metaRemoteEvent")
BNRoot:AddChild(BNMeta)
local BNData = Instance.new("RemoteEvent", "dataRemoteEvent")
BNRoot:AddChild(BNData)

local RemoteEvents = Instance.new("Folder", "RemoteEvents")
RS:AddChild(RemoteEvents)
local ReplicaNames = {
    "ReplicaRequestData", "ReplicaSet", "ReplicaSetValues", "ReplicaTableInsert",
    "ReplicaTableRemove", "ReplicaWrite", "ReplicaSignal", "ReplicaParent",
    "ReplicaCreate", "ReplicaBind", "ReplicaDestroy",
}
for _, name in ipairs(ReplicaNames) do
    RemoteEvents:AddChild(Instance.new("RemoteEvent", name))
end
RemoteEvents:AddChild(Instance.new("RemoteEvent", "ReplicaSignalUnreliable"))

local Archery = Instance.new("Folder", "Archery")
RS:AddChild(Archery)
Archery:AddChild(Instance.new("RemoteEvent", "Pose"))

local SharedFolder = Instance.new("Folder", "Shared")
RS:AddChild(SharedFolder)
local ModulesFolder = Instance.new("Folder", "Modules")
SharedFolder:AddChild(ModulesFolder)
local GlobalFolder = Instance.new("Folder", "Global")
ModulesFolder:AddChild(GlobalFolder)
local LibrariesFolder = Instance.new("Folder", "Libraries")
GlobalFolder:AddChild(LibrariesFolder)
local SharedModsFolder = Instance.new("Folder", "Shared")
ModulesFolder:AddChild(SharedModsFolder)

local FilesFolder = Instance.new("Folder", "Files")
RS:AddChild(FilesFolder)
local AssetsFolder = Instance.new("Folder", "Assets")
FilesFolder:AddChild(AssetsFolder)
local ModelsFolder = Instance.new("Folder", "Models")
AssetsFolder:AddChild(ModelsFolder)
local WeightFolder = Instance.new("Folder", "Dumbbells")
ModelsFolder:AddChild(WeightFolder)
local function addWeightModel(name, weight)
    local w = Instance.new("Model", name)
    w:SetAttribute("Weight", weight)
    WeightFolder:AddChild(w)
    return w
end
addWeightModel("DB_25", 25)
addWeightModel("DB_45", 45)
addWeightModel("DB_70", 70)

-- ===== mock game data (ReplicaService via the game's Client.Data) =====
local MockCharData = {
    FirstName = "Test",
    Gender = "Male",
    Height = 170,
    Hair = "Spiky",
    HairColor = "Black",
    FacialHair = "None",
    Ethnicity = "A",
    Eyes = "Brown",
    Mouth = "Default",
    FightStyle = "Basic",
    Accessories = {},
}
local MockData = {
    Style = "Basic",
    StyleShiny = false,
    Rerolls = 10,
    Cash = 1000,
    Kills = 0,
    Class = "None",
    Steps = 0,
    WorkoutSeconds = 120,
    Workouts = 3,
    PlaytimeSeconds = 500,
    Vip = false,
    MachineUnlocked = true,
    Slots = {
        Active = 1,
        Owned = 2,
        Characters = { MockCharData, MockCharData },
    },
}

-- ===== game module mocks (require-able, Rule 2 surface only) =====
local Game_Settings = {
    Combat = {
        Bridge = "Combat.Sync",
        Authority = { RangeSlack = 4, FacingDot = 0, LineOfSight = true, SwingSlack = 0.25, PaceSlack = 0.75, PingCap = 0.35 },
        Styles = {
            Basic = { HitRange = 7, HitAngle = 0.65, AttackDebounce = 0.35, StringLength = 4, Rarity = "Common" },
            Karate = { HitRange = 6.5, HitAngle = 0.6, AttackDebounce = 0.31, StringLength = 4, Rarity = "Uncommon" },
            ["Fist of Flowing Water"] = { HitRange = 7, HitAngle = 0.65, AttackDebounce = 0.33, StringLength = 5, Rarity = "Epic" },
        },
        DefaultStyle = "Basic",
    },
    Network = {
        CharacterBridge = "Character.Action",
        CharacterRejectBridge = "Character.Reject",
    },
    Gym = {
        Bridge = "Gym.Sync",
        Reps = { Max = 3, BandLow = 1.2, BandHigh = 2.0, Smooth = 0.5, Hold = 0.16, Drift = 0.22 },
    },
}
local Appearance = {
    holdsRare = function(charTable, field)
        return type(charTable) == "table" and charTable[field] == "RARE"
    end,
    styleHoldsRare = function(styleName, styleShinyBool)
        return styleShinyBool == true or styleName == "Fist of Flowing Water"
    end,
    StyleRarity = { Basic = "Common", Karate = "Uncommon", ["Fist of Flowing Water"] = "Epic" },
}
local Muscle = {}
Muscle.Capacity = function(workoutSeconds)
    if workoutSeconds >= 200 then return 245 end
    if workoutSeconds >= 100 then return 120 end
    return 45
end
Muscle.Assess = function(weight, seconds)
    local cap = Muscle.Capacity(seconds)
    if weight > cap then return "Locked" end
    if weight >= cap * 0.6 then return "Struggle" end
    return "Comfortable"
end
local GymWeights = {}
GymWeights.List = function(folderName)
    local out = {}
    for _, m in ipairs(WeightFolder:GetChildren()) do
        table.insert(out, { Name = m.Name, Weight = m:GetAttribute("Weight") or 0, Template = m })
    end
    table.sort(out, function(a, b) return a.Weight < b.Weight end)
    return out
end
GymWeights.Find = function(name)
    for _, row in ipairs(GymWeights.List()) do
        if row.Name == name then return row end
    end
    return nil
end

-- ===== Client.Posture mock (glm3 notes §3 — client-authoritative stamina) =====
local PostureValue = 100
local Posture = {
    Get = function() return PostureValue end,
    GetMax = function() return 100 end,
    Add = function(n) PostureValue = math.min(100, PostureValue + n) end,
    Reduce = function(n) PostureValue = math.max(0, PostureValue - n) end,
    Sync = function(n) PostureValue = n end,
}

-- ===== Client.Input mock (the game's own action system — WIRE SURFACE) =====
local InputFires = {}
local InputBinds = {}
local Input = {
    Bind = function(id, began, ended)
        InputBinds[id] = { began = began, ended = ended }
    end,
    Fire = function(id, state)
        table.insert(InputFires, { id = id, state = state })
    end,
    IsDown = function(id) return false end,
}
local function inputCount(id, state)
    local n = 0
    for _, f in ipairs(InputFires) do
        if f.id == id and (state == nil or f.state == state) then
            n = n + 1
        end
    end
    return n
end

-- ===== Client.Data mock (ReplicaService surface) =====
local DataSetHandlers = {}
local Data = {
    IsReady = function() return true end,
    OnReady = function(fn)
        G.task.spawn(fn)
        return { Disconnect = function() end }
    end,
    Get = function(path)
        local cur = MockData
        for _, k in ipairs(path) do
            if type(cur) ~= "table" then return nil end
            cur = cur[k]
        end
        return cur
    end,
    OnSet = function(path, fn)
        local key = table.concat(path, ".")
        DataSetHandlers[key] = DataSetHandlers[key] or {}
        table.insert(DataSetHandlers[key], fn)
        return { Disconnect = function() end }
    end,
}
local function dataSet(path, value)
    local cur = MockData
    for i = 1, #path - 1 do
        cur = cur[path[i]]
    end
    cur[path[#path]] = value
    local list = DataSetHandlers[table.concat(path, ".")]
    if list then
        for _, fn in ipairs(list) do
            G.task.spawn(function() pcall(fn, value) end)
        end
    end
end

-- ===== BridgeNet2 client mock =====
-- Game resolves bridges via ReferenceBridge(Game_Settings.X.Bridge) — deobf
-- L2197/L2205/L3682/L5105. Reference kept as alias (real lib has both).
local BridgeFires = {}
local BridgeListeners = {}
local BridgeCache = {}
local BridgeNet2Client = {}
local function makeBridge(name)
    if BridgeCache[name] then
        return BridgeCache[name]
    end
    local bridge = {}
    local mt = {}
    mt.__index = function(_, k)
        if k == "Fire" or k == "FireServer" then
            return function(_, ...)
                BridgeFires[name] = BridgeFires[name] or {}
                table.insert(BridgeFires[name], table.pack(...))
            end
        elseif k == "Connect" or k == "ConnectTo" or k == "OnClientEvent" then
            return function(_, fn)
                BridgeListeners[name] = BridgeListeners[name] or {}
                table.insert(BridgeListeners[name], fn)
                return { Disconnect = function() end }
            end
        end
        return nil
    end
    mt.__tostring = function() return "ClientBridge(" .. name .. ")" end
    setmetatable(bridge, mt)
    BridgeCache[name] = bridge
    return bridge
end
BridgeNet2Client.ReferenceBridge = makeBridge
BridgeNet2Client.Reference = makeBridge
BridgeNet2Client.Server = { Bridge = function() error("server-only") end }
function BridgeNet2Client.initBridge() return BridgeNet2Client end

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
addModule(Packages, "BridgeNet2", BridgeNet2Client)
addModule(BNClient, "bridgenet2", BridgeNet2Client)
addModule(BNClientDir, "ClientBridge", BridgeNet2Client)
addModule(Packages, "ReplicaClient", { new = function() error("ReplicaClient mock pending SH2 pattern") end })
addModule(Packages, "Faye", {})
addModule(Packages, "ProfileStore", {})
addModule(Packages, "ReplicaServer", {})
addModule(Packages, "ReplicaShared", {})
addModule(Packages, "crunchyroll", {})
addModule(Packages, "TextPlus", {})
addModule(Packages, "SmoothShiftLock", {})
addModule(Packages, "TopbarPlus", {})
addModule(LibrariesFolder, "Game_Settings", Game_Settings)
addModule(SharedModsFolder, "Appearance", Appearance)
addModule(SharedModsFolder, "Muscle", Muscle)
addModule(SharedModsFolder, "GymWeights", GymWeights)
addModule(ClientDir, "Input", Input)
addModule(ClientDir, "Data", Data)
addModule(ClientDir, "Posture", Posture)

local function serverBridge(name, ...)
    local list = BridgeListeners[name]
    if list then
        local args = table.pack(...)
        for _, fn in ipairs(list) do
            G.task.spawn(function()
                local ok, err = pcall(fn, table.unpack(args, 1, args.n))
                if not ok then
                    print("bridge listener error [" .. name .. "]: " .. tostring(err))
                end
            end)
        end
    end
end

local function bridgeCalls(name)
    return BridgeFires[name] or {}
end

local function bridgeCount(name, pred)
    local n = 0
    for _, c in ipairs(bridgeCalls(name)) do
        if not pred or pred(c) then
            n = n + 1
        end
    end
    return n
end

-- ===== workspace: gym station + combat dummies (tagged) =====
local GymStation = Instance.new("Model", "DumbbellStation1")
local LiftPoint = Instance.new("Part", "LiftPoint")
LiftPoint.CFrame = CFrame.new(Vector3.new(20, 3, 10))
GymStation:AddChild(LiftPoint)
GymStation.PrimaryPart = LiftPoint
WS:AddChild(GymStation)

local function makeDummy(name, behavior, pos)
    local d = Instance.new("Model", name)
    local root = Instance.new("Part", "HumanoidRootPart")
    root.CFrame = CFrame.new(Vector3.new(pos[1], pos[2], pos[3]))
    d:AddChild(root)
    d:AddChild(Instance.new("Humanoid", "Humanoid"))
    d.PrimaryPart = root
    d:SetAttribute("DummyBehavior", behavior)
    WS:AddChild(d)
    return d
end
local DummyUsable = makeDummy("CombatDummy1", "Regular", { 5, 5, 5 })
local DummyKnocked = makeDummy("CombatDummy2", "Knocked", { 2, 5, 2 })

local Tagged = {
    CombatDummy = { DummyUsable, DummyKnocked },
    GymDumbbell = { GymStation },
    GymBench = {},
    GymDeadlift = {},
    GymTreadmill = {},
}
local TagSignals = {}
Services.CollectionService = {
    GetTagged = function(tag) return Tagged[tag] or {} end,
    HasTag = function(inst, tag)
        for _, m in ipairs(Tagged[tag] or {}) do
            if m == inst then return true end
        end
        return false
    end,
    GetInstanceAddedSignal = function(tag)
        if not TagSignals[tag] then TagSignals[tag] = Signal.new() end
        return TagSignals[tag]
    end,
    GetInstanceRemovedSignal = function(tag)
        if not TagSignals["-" .. tag] then TagSignals["-" .. tag] = Signal.new() end
        return TagSignals["-" .. tag]
    end,
}

-- ===== services / game =====
Services.Players = { LocalPlayer = PLR, GetPlayers = function() return { PLR } end }
Services.ReplicatedStorage = RS
Services.RunService = { Stepped = Signal.new(), RenderStepped = Signal.new(), Heartbeat = Signal.new(), PostSimulation = Signal.new(), IsServer = function() return false end, IsStudio = function() return false end, IsClient = function() return true end }
Services.TeleportService = { Teleport = function() end }
Services.UserInputService = { TouchEnabled = false, KeyboardEnabled = true, InputBegan = Signal.new() }
Services.HttpService = { JSONEncode = function(_, t) return "{}" end, JSONDecode = function(_, s) return {} end }
Services.TweenService = { Create = function() return { Play = function() end } end, GetValue = function() return 0 end }
Services.Lighting = {}
Services.GuiService = { GetResolution = function() return Vector3.new(1920, 1080, 0) end, TopbarInset = function() return 0, 0 end }
Services.MarketplaceService = { GetUserOwnershipAsync = function() return { IsSuccess = function() return true end, UserOwnsGamePass = false } end }
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

-- ===== mock-world self-checks (skeleton + module surface) =====
check("tree: BridgeNet2 packages path resolvable", (function()
    local pk = RS:FindFirstChild("Packages")
    local idx = pk and pk:FindFirstChild("_Index")
    local bni = idx and idx:FindFirstChild("ffrostflame_bridgenet2@1.0.0")
    local bn = bni and bni:FindFirstChild("bridgenet2")
    return bn ~= nil
end)())
check("tree: BridgeNet2 transport remotes present", (function()
    local root = RS:FindFirstChild("ffrostflame_bridgenet2@1.0.0")
    return root and root:FindFirstChild("metaRemoteEvent") and root:FindFirstChild("dataRemoteEvent") ~= nil
end)())
check("tree: 12 Replica remotes present", (function()
    local re = RS:FindFirstChild("RemoteEvents")
    if not re then return false end
    local n = 0
    for _, name in ipairs(ReplicaNames) do
        if re:FindFirstChild(name) then n = n + 1 end
    end
    return n == 11 and re:FindFirstChild("ReplicaSignalUnreliable") ~= nil
end)())
check("tree: Game_Settings module path (Shared.Modules.Global.Libraries)", (function()
    local m = RS:FindFirstChild("Shared"):FindFirstChild("Modules"):FindFirstChild("Global")
        :FindFirstChild("Libraries"):FindFirstChild("Game_Settings")
    local ok, res = pcall(function() return G.require(m) end)
    return ok and res == Game_Settings
end)())
check("tree: Appearance/Muscle/GymWeights module paths", (function()
    local sm = RS:FindFirstChild("Shared"):FindFirstChild("Modules"):FindFirstChild("Shared")
    local ok1 = pcall(function() return G.require(sm:FindFirstChild("Appearance")) end)
    local ok2 = pcall(function() return G.require(sm:FindFirstChild("Muscle")) end)
    local ok3 = pcall(function() return G.require(sm:FindFirstChild("GymWeights")) end)
    return ok1 and ok2 and ok3
end)())
check("tree: Client.Input/Client.Data under PlayerScripts", (function()
    local ps = PLR:FindFirstChild("PlayerScripts")
    local c = ps and ps:FindFirstChild("Client")
    local ok1 = pcall(function() return G.require(c:FindFirstChild("Input")) end)
    local ok2 = pcall(function() return G.require(c:FindFirstChild("Data")) end)
    return ok1 and ok2
end)())
check("bridgenet2 mock: ReferenceBridge caches per name", (function()
    local a = BridgeNet2Client.ReferenceBridge("Combat.Sync")
    local b = BridgeNet2Client.ReferenceBridge("Combat.Sync")
    return a == b and BridgeNet2Client.ReferenceBridge("Gym.Sync") ~= a
end)())
check("bridgenet2 mock: Fire records wire tuples", (function()
    local br = BridgeNet2Client.ReferenceBridge("TestBridge")
    br:Fire({ T = "Start", Station = GymStation, Weight = "DB_45" })
    local calls = bridgeCalls("TestBridge")
    return #calls == 1 and calls[1][1].T == "Start" and calls[1][1].Station == GymStation and calls[1][1].Weight == "DB_45"
end)())
check("bridgenet2 mock: server dispatch reaches Connect", (function()
    local got = nil
    local br = BridgeNet2Client.ReferenceBridge("TestBridge")
    br:Connect(function(payload) got = payload end)
    serverBridge("TestBridge", { T = "Begin", User = PLR.UserId })
    pump(0.05)
    return got ~= nil and got.T == "Begin"
end)())
check("input mock: Fire records tuples; Bind visible", (function()
    Input.Bind("Combat.Attack", function() end, function() end)
    Input.Fire("Combat.Attack", true)
    Input.Fire("Combat.Attack", false)
    Input.Fire("Gym.LeanLeft", true)
    return inputCount("Combat.Attack", true) == 1 and inputCount("Combat.Attack", false) == 1
        and inputCount("Gym.LeanLeft", true) == 1 and InputBinds["Combat.Attack"] ~= nil
end)())
check("data mock: Get navigates array paths; OnSet dispatches", (function()
    local seen = nil
    Data.OnSet({ "Rerolls" }, function(v) seen = v end)
    dataSet({ "Rerolls" }, 7)
    pump(0.05)
    return Data.Get({ "Style" }) == "Basic"
        and Data.Get({ "Slots", "Active" }) == 1
        and Data.Get({ "Rerolls" }) == 7
        and seen == 7
end)())
check("gym mock: GymWeights.List sorted rows + Muscle.Assess bands", (function()
    local rows = GymWeights.List("Dumbbells")
    return #rows == 3 and rows[1].Weight == 25 and rows[3].Weight == 70
        and Muscle.Assess(45, 120) == "Comfortable"
        and Muscle.Assess(120, 120) == "Struggle"
        and Muscle.Assess(200, 120) == "Locked"
end)())
check("posture mock: Sync sets value directly (glm3 §3 surface)", (function()
    Posture.Reduce(40)
    if Posture.Get() ~= 60 then return false end
    Posture.Sync(Posture.GetMax())
    return Posture.Get() == 100
end)())
check("world: tagged dummies + station resolvable", (function()
    local tagged = Services.CollectionService.GetTagged("CombatDummy")
    return #tagged == 2 and tagged[1]:GetAttribute("DummyBehavior") == "Regular"
        and tagged[2]:GetAttribute("DummyBehavior") == "Knocked"
        and GymStation.PrimaryPart ~= nil
end)())

-- ===== loader (live — picks up SH2's draft when it lands) =====
local ScriptSrc = nil
do
    local f = io.open(ScriptPath, "r")
    if f then
        ScriptSrc = f:read("*a")
        f:close()
    end
end

if not ScriptSrc then
    print("SKIP: " .. ScriptPath .. " not present yet (SH2 draft pending) — mock-world checks only")
else
    local function noErrorNotify()
        for _, n in ipairs(MockState.Notifies) do
            if string.find(n, "ERROR", 1, true) then
                return false, n
            end
        end
        return true
    end
    pump(0.2)
    local fn = G.loadstring(ScriptSrc, "=(Shigaku)")
    G.task.spawn(fn)
    pump(1.0)
    check("script loaded without ERROR notify", (function()
        local ok, n = noErrorNotify()
        if not ok then print("  notify was: " .. tostring(n)) end
        return ok
    end)())
    check("guard set", G.ayasemiyatongekissazumirisa == true)
    check("no queueonteleport (template feature deleted upstream)", #TeleportQueue == 0)
    check("save folder set", SaveManager.Folder ~= nil and SaveManager.Folder ~= "")
    -- SH2 draft checks land here when the draft exists:
    --   + toggle registry (AutoAttack/AutoGym/AutoRoll as delivered)
    --   + Input.Fire tuples (attack paced from Game_Settings, equip first,
    --     LeanLeft taps in Reps midband)
    --   + Gym.Sync tuples (Start Station+Weight, Stop on toggle-off)
    --   + Character.Action tuples (RerollField Args=slot,field,confirm shape)
    --   + rarity stop (holdsRare true → loop stops, no more fires)
    --   + Data reads use array paths
end

print(string.format("Shigaku harness: %d pass / %d fail", Pass, Fail))
if Fail > 0 then
    for _, f in ipairs(Failures) do
        print("  failed: " .. f)
    end
    os.exit(1)
end
