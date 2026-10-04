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
    vmt.__index = function(v, k)
        if k == "Unit" then
            local m = v.Magnitude
            if m == 0 then
                return mk(0, 0, 0)
            end
            return mk(v.X / m, v.Y / m, v.Z / m)
        end
        return nil
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
    local VecMT = getmetatable(Vector3.zero)
    cmt.__sub = function(a, b)
        if getmetatable(b) == cmt then
            return cf(a.Position - b.Position)
        end
        if getmetatable(b) == VecMT then
            return cf(a.Position - b)
        end
        return a
    end
    cmt.__add = function(a, b)
        if getmetatable(b) == VecMT then
            return cf(a.Position + b)
        end
        if getmetatable(b) == cmt then
            return cf(a.Position + b.Position)
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
    ClickDetector = { "ClickDetector" },
    Attachment = { "Attachment" },
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
    function imt:IsDescendantOf(anc)
        local p = self.Parent
        while p do
            if p == anc then
                return true
            end
            p = p.Parent
        end
        return false
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

-- ===== STEAL A CAR HARNESS — SAC1 (glm3, 2026-10-04) ========================
-- Real-load pattern: io.open + loadstring + task.spawn the delivered script.
-- Mock world per work/lua/stealacar-analysis.md (dump-faithful paths).
-- Run: lua5.4 work/lua/stealacar-harness-glm3.lua [path-to-StealACar.lua]

local ScriptPath = arg and arg[1] or (debug and (function()
    local ok, src = pcall(debug.getinfo, 2, "S")
    if ok and src and src.source then
        return src.source:gsub("@", ""):gsub("[^/\\]+$", "") .. "StealACar.lua"
    end
    return "StealACar.lua"
end)()) or "StealACar.lua"
ScriptPath = ScriptPath or "StealACar.lua"

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
G.delfile = function(p) MockFS[p] = nil end
G.appendfile = function(p, c) MockFS[p] = (MockFS[p] or "") .. c end
G.fireproximityprompt = function(prompt) record({ fn = "FirePP", prompt = prompt }) end
G.fireclickdetector = function(cd) record({ fn = "FireCD", cd = cd }) end
G.firetouchinterest = function(part, root, touch) record({ fn = "FireTI", part = part, root = root, touch = touch }) end

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
humanoid.Health = 100
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
local function addModule(parent, name, tbl)
    local m = Instance.new("ModuleScript", name)
    parent:AddChild(m)
    ModuleRegistry[m] = tbl
    return m
end

local RemotesFolder = Instance.new("Folder", "Remotes")
RS:AddChild(RemotesFolder)
local EventsFolder = Instance.new("Folder", "Events")
local FunctionsFolder = Instance.new("Folder", "Functions")
RemotesFolder:AddChild(EventsFolder)
RemotesFolder:AddChild(FunctionsFolder)

local WireLog = { fires = {}, invokes = {} }
local function makeEvent(name)
    local ev = Instance.new("RemoteEvent", name)
    ev.OnClientEvent = Signal.new()
    function ev:FireServer(...)
        table.insert(WireLog.fires, { name = name, args = { ... } })
    end
    EventsFolder:AddChild(ev)
    return ev
end
local MockState2 = {
    Cash = 30000,
    TrailData = { Equipped = "", Trails = {
        { Id = "Red", Name = "Red", Owned = false },
        { Id = "Galaxy", Name = "Galaxy", Owned = false },
        { Id = "Matrix", Name = "Matrix", Owned = true },
    } },
    IndexClaimable = true,
    GiftClaimed = false,
    DNLAvailable = true,
    LootReady = true,
    RaceReady = true,
    RaceOfferId = 99,
}
local function makeFunction(name, handler)
    local rf = Instance.new("RemoteFunction", name)
    function rf:InvokeServer(...)
        local args = { ... }
        table.insert(WireLog.invokes, { name = name, args = args })
        return handler(args)
    end
    FunctionsFolder:AddChild(rf)
    return rf
end

makeEvent("CurrencyUpdated")
makeEvent("FuseUpdated")
local BuyTrailEvent = makeEvent("BuyTrail")
local RaceRequestEvent = makeEvent("RaceRequest")
local TreadmillActivityEvent = makeEvent("TreadmillActivity")
makeFunction("SellCars", function() return { Success = true } end)
makeFunction("GetSellInventory", function()
    return { { Uid = "u1", Id = "Vipra", Price = 100 }, { Uid = "u2", Id = "Charger", Price = 50 } }
end)
makeFunction("ClaimIndexReward", function() return { Success = true, State = { Claimable = false } } end)
makeFunction("GetCarIndex", function() return { Claimable = MockState2.IndexClaimable } end)
local FuseRequestRF = makeFunction("FuseRequest", function(args)
    if args[1] == "Claim" then MockState2.FuseClaimed = args[2] end
    return { Success = true }
end)
makeFunction("FreeGiftRequest", function(args)
    if args[1] == "Get" then return { Success = true, Claimed = MockState2.GiftClaimed } end
    if args[1] == "Claim" then MockState2.GiftClaimed = true end
    return { Success = true }
end)
makeFunction("DontLeaveGiftRequest", function(args)
    if args[1] == "Open" then return { Success = true, Available = MockState2.DNLAvailable } end
    if args[1] == "Claim" then MockState2.DNLAvailable = false end
    return { Success = true }
end)
makeFunction("OfflineLootRequest", function(args)
    if args[1] == "Get" then return { Ready = MockState2.LootReady } end
    return { Success = true }
end)
makeFunction("RaceRewardRequest", function(args)
    if args[1] == "Get" then
        if MockState2.RaceReady then
            return { Ready = true, Offer = { Id = MockState2.RaceOfferId, Minutes = 5, Kind = "Cash" } }
        end
        return { Ready = false }
    end
    return { Success = true }
end)
makeFunction("ClaimTreadmillBonus", function(args)
    MockState2.BonusClaimedToken = args[1]
    return { Success = true }
end)
makeFunction("UpgradeTreadmillPurchase", function(args)
    MockState2.TreadmillUpgradeTier = args[1]
    return { Success = true }
end)
makeFunction("GetPlayerData", function() return { Cash = MockState2.Cash, Speed = 20 } end)
makeFunction("GetTrailData", function() return MockState2.TrailData end)

local ConfigsFolder = Instance.new("Folder", "Configs")
RS:AddChild(ConfigsFolder)
addModule(ConfigsFolder, "TrailConfig", {
    Trails = {
        Red = { Name = "Red", Order = 1, Price = 100, SpeedMultiplier = 1.1, MovementMultiplier = 1.02 },
        Galaxy = { Name = "Galaxy", Order = 10, Price = 105000000000000, SpeedMultiplier = 1.75, MovementMultiplier = 1.15 },
        Matrix = { Name = "Matrix", Order = 9, Price = 7000000000000, SpeedMultiplier = 1.6, MovementMultiplier = 1.12 },
    },
})
addModule(ConfigsFolder, "TreadmillConfig", {
    Tiers = {
        { Name = "Starter", Price = 10, SpeedPerSecond = 5 },
        { Name = "Celebrity", Price = 1000, SpeedPerSecond = 20 },
        { Name = "Golden", Price = 20000, SpeedPerSecond = 75 },
        { Name = "Freeze", Price = 2100000, SpeedPerSecond = 250 },
    },
})
addModule(ConfigsFolder, "PlotConfig", {
    MaxLevel = 5,
    UpgradeCosts = { 1000000, 100000000, 10000000000, 140000000000000, [0] = 10000 },
})
addModule(ConfigsFolder, "FuseConfig", {
    Tiers = {
        { Name = "Hybrid", CarId = "Hybrid", Duration = 60, Ingredients = { "RSX", "NissaruR32", "Charger" } },
        { Name = "Cyber", CarId = "Cyber", Duration = 300, Ingredients = { "Nebula", "Corvessa", "SkylanceR" } },
    },
})

local RaceStateFolder = Instance.new("Folder", "RaceState")
RS:AddChild(RaceStateFolder)
RaceStateFolder:SetAttribute("Phase", "Idle")

local PlotsFolder = Instance.new("Folder", "Plots")
WS:AddChild(PlotsFolder)
local MyPlotModel = Instance.new("Model", "1")
PlotsFolder:AddChild(MyPlotModel)
MyPlotModel:SetAttribute("Owner", 42)
MyPlotModel:SetAttribute("Taken", true)
MyPlotModel:SetAttribute("Level", 1)
MyPlotModel:SetAttribute("UpgradeCost", 1000000)
MyPlotModel:SetAttribute("TreadmillTier", 2)
local SignPart = Instance.new("Part", "Sign")
local SignDetector = Instance.new("ClickDetector", "ClickDetector")
SignPart:AddChild(SignDetector)
local SignHolder = Instance.new("Model", "Sign")
SignHolder:AddChild(SignPart)
MyPlotModel:AddChild(SignHolder)
local ParkingFolder = Instance.new("Folder", "ParkingInteractions")
MyPlotModel:AddChild(ParkingFolder)
local function makeParkingSlot(n, pos)
    local part = Instance.new("Part", tostring(n))
    part.CFrame = CFrame.new(pos)
    part:SetAttribute("PlotSlot", n)
    local attachment = Instance.new("Attachment", "Attachment")
    part:AddChild(attachment)
    local prompt = Instance.new("ProximityPrompt", "ParkingPrompt")
    prompt.MaxActivationDistance = 26
    prompt:SetAttribute("PromptAvailable", true)
    attachment:AddChild(prompt)
    ParkingFolder:AddChild(part)
    return part, prompt
end
local ParkingPart, ParkingPrompt = makeParkingSlot(3, Vector3.new(30, 3, 40))
local ParkingPart2, ParkingPrompt2 = makeParkingSlot(5, Vector3.new(60, 3, 80))

local OtherPlot = Instance.new("Model", "2")
PlotsFolder:AddChild(OtherPlot)
OtherPlot:SetAttribute("Owner", 999)
OtherPlot:SetAttribute("Taken", true)

local StolenCarsFolder = Instance.new("Folder", "LiveStolenCars")
WS:AddChild(StolenCarsFolder)
local function makeCar(name, pos, theftState)
    local car = Instance.new("Model", name)
    car:SetAttribute("TheftState", theftState)
    car:SetAttribute("ZoneSpawn", true)
    local chassis = Instance.new("Part", "Chassis")
    chassis.CFrame = CFrame.new(pos)
    local stealAttachment = Instance.new("Attachment", "StealAttachment")
    chassis:AddChild(stealAttachment)
    local stealPrompt = Instance.new("ProximityPrompt", "StealPrompt")
    stealPrompt.MaxActivationDistance = 12
    stealAttachment:AddChild(stealPrompt)
    local driverSeat = Instance.new("Part", "DriverSeat")
    driverSeat.CFrame = CFrame.new(pos + Vector3.new(0, 2, 0))
    car:AddChild(chassis)
    car:AddChild(driverSeat)
    car.PrimaryPart = chassis
    StolenCarsFolder:AddChild(car)
    return car, chassis, stealPrompt, driverSeat
end
local CarModel, CarChassis, CarStealPrompt, CarDriverSeat = makeCar("Vipra", Vector3.new(200, 3, 100), "Available")
makeCar("Charger", Vector3.new(400, 3, 300), "Stolen")

local SteppedSignal = Signal.new()
SteppedSignal.Wait = function()
    G.task.wait(0.05)
    return nil, 0.1
end
Services.CollectionService = { GetTagged = function() return {} end, HasTag = function() return false end }
Services.Players = { LocalPlayer = PLR, GetPlayers = function() return { PLR } end }
Services.ReplicatedStorage = RS
Services.RunService = { Stepped = SteppedSignal, RenderStepped = Signal.new(), Heartbeat = Signal.new(), IsServer = function() return false end, IsStudio = function() return false end, IsClient = function() return true end }
Services.TeleportService = { Teleport = function() end }
Services.UserInputService = { TouchEnabled = false, KeyboardEnabled = true, InputBegan = Signal.new() }
Services.HttpService = { JSONEncode = function(_, t) return "{}" end, JSONDecode = function(_, s) return {} end }
Services.TweenService = { Create = function() return { Play = function() end } end, GetValue = function() return 0 end }
Services.Lighting = {}
Services.GuiService = { GetResolution = function() return Vector3.new(1920, 1080, 0) end, TopbarInset = function() return 0, 0 end }
Services.MarketplaceService = { GetUserOwnershipAsync = function() return { IsSuccess = function() return true end, UserOwnsGamePass = false } end, GetProductInfo = function() return { Name = "Steal A Car" } end }
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
WS.GetServerTimeNow = function() return Sched.now end
G.getconnections = nil

local function fireCount(name, pred)
    local n = 0
    for _, c in ipairs(WireLog.fires) do
        if c.name == name and (not pred or pred(c)) then
            n = n + 1
        end
    end
    return n
end
local function invokeCount(name, pred)
    local n = 0
    for _, c in ipairs(WireLog.invokes) do
        if c.name == name and (not pred or pred(c)) then
            n = n + 1
        end
    end
    return n
end
local function findInvoke(name)
    for _, c in ipairs(WireLog.invokes) do
        if c.name == name then
            return c
        end
    end
    return nil
end
local function actionCount(fn)
    return countCalls(fn)
end
local function lastNotifyHas(needle)
    for _, n in ipairs(MockState.Notifies) do
        if string.find(n, needle, 1, true) then
            return true
        end
    end
    return false
end

-- ===== mock-world self-checks =====
check("tree: Remotes.Events/Functions resolvable", (function()
    local rem = RS:FindFirstChild("Remotes")
    return rem ~= nil and rem:FindFirstChild("Events") ~= nil and rem:FindFirstChild("Functions") ~= nil
end)())
check("tree: plot + parking + sign resolvable", (function()
    local plots = WS:FindFirstChild("Plots")
    local plot = plots and plots:FindFirstChild("1")
    local parking = plot and plot:FindFirstChild("ParkingInteractions")
    local slot = parking and parking:FindFirstChild("3")
    local attachment = slot and slot:FindFirstChild("Attachment")
    local prompt = attachment and attachment:FindFirstChild("ParkingPrompt")
    local sign = plot and plot:FindFirstChild("Sign")
    local signPart = sign and sign:FindFirstChild("Sign")
    local det = signPart and signPart:FindFirstChildOfClass("ClickDetector")
    return plot ~= nil and prompt ~= nil and det ~= nil and plot:GetAttribute("Owner") == 42
end)())
check("tree: car model + steal prompt + driver seat", (function()
    local cars = WS:FindFirstChild("LiveStolenCars")
    local car = cars and cars:FindFirstChild("Vipra")
    local chassis = car and car:FindFirstChild("Chassis")
    local stealAttachment = chassis and chassis:FindFirstChild("StealAttachment")
    local prompt = stealAttachment and stealAttachment:FindFirstChild("StealPrompt")
    local seat = car and car:FindFirstChild("DriverSeat")
    return car ~= nil and prompt ~= nil and seat ~= nil and car:GetAttribute("TheftState") == "Available"
end)())
check("configs: 4 modules require-able", (function()
    local cfg = RS:FindFirstChild("Configs")
    local ok1 = pcall(function() return G.require(cfg:FindFirstChild("TrailConfig")) end)
    local ok2 = pcall(function() return G.require(cfg:FindFirstChild("TreadmillConfig")) end)
    local ok3 = pcall(function() return G.require(cfg:FindFirstChild("PlotConfig")) end)
    local ok4 = pcall(function() return G.require(cfg:FindFirstChild("FuseConfig")) end)
    return ok1 and ok2 and ok3 and ok4
end)())

local RealOs = os
G.os = { clock = function() return Sched.now end, time = RealOs.time, date = RealOs.date }

-- ===== loader (real-load) =====
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
else
    local function noErrorNotify()
        for _, n in ipairs(MockState.Notifies) do
            if string.find(n, "ERROR", 1, true) or string.find(n, "Error in", 1, true) then
                return false, n
            end
        end
        return true
    end
    pump(0.2)
    local fn = G.loadstring(ScriptSrc, "=(StealACar)")
    G.task.spawn(fn)
    pump(1.0)
    check("script loaded without ERROR notify", (function()
        local ok, n = noErrorNotify()
        if not ok then print("  notify was: " .. tostring(n)) end
        return ok
    end)())
    check("guard set", G.ayasemiyatongekissazumirisa == true)
    check("save folder set", SaveManager.Folder == "Yuri/Steal A Car")
    local ToggleIds = { "AutoSteal", "AutoSell", "AutoBuyTrail", "AutoUpgradeTreadmill", "AutoUpgradePlot", "AutoTreadmill", "AutoFuse", "AutoIndexReward", "AutoRace", "AutoFreeGift", "AutoOfflineLoot", "AutoDontLeaveGift" }
    local registered = 0
    for _, id in ipairs(ToggleIds) do
        if Library.Toggles[id] then
            registered = registered + 1
        end
    end
    check("12 toggles registered", registered == 12)
    check("no error notifies after idle", (function()
        pump(1.0)
        local ok, n = noErrorNotify()
        if not ok then print("  notify was: " .. tostring(n)) end
        return ok
    end)())

    local function clearWires()
        WireLog.fires = {}
        WireLog.invokes = {}
    end
    local function setCash(v)
        MockState2.Cash = v
        local ev = EventsFolder:FindFirstChild("CurrencyUpdated")
        if ev then
            ev.OnClientEvent:Fire({ Cash = v, CashFormatted = tostring(v) })
        end
    end

    -- AutoSell
    Library.Toggles.AutoSell:SetValue(true)
    pump(3.0)
    check("autosell: GetSellInventory invoked", invokeCount("GetSellInventory") >= 1)
    check("autosell: SellCars invoked with exact uid array", (function()
        local c = findInvoke("SellCars")
        if not c then return false end
        local a = c.args[1]
        return type(a) == "table" and #a == 2 and a[1] == "u1" and a[2] == "u2"
    end)())
    clearWires()
    Library.Toggles.AutoSell:SetValue(false)
    pump(3.0)
    check("autosell: toggle off stops invokes", invokeCount("GetSellInventory") == 0)

    -- AutoBuyTrail
    MockState2.Cash = 200000000000000
    Library.Toggles.AutoBuyTrail:SetValue(true)
    pump(6.0)
    check("autobuytrail: fires best affordable (Galaxy 1.75x @ 1.05e14)", (function()
        local n = 0
        for _, c in ipairs(WireLog.fires) do
            if c.name == "BuyTrail" and c.args[1] == "Galaxy" then
                n = n + 1
            end
        end
        return n >= 1
    end)())
    clearWires()
    setCash(50)
    pump(6.0)
    check("autobuytrail: poor cash buys nothing", fireCount("BuyTrail") == 0)
    Library.Toggles.AutoBuyTrail:SetValue(false)

    -- AutoUpgradeTreadmill
    setCash(30000)
    Library.Toggles.AutoUpgradeTreadmill:SetValue(true)
    pump(6.0)
    check("autoupgradetreadmill: invokes next tier (3) when cash >= price", (function()
        local c = findInvoke("UpgradeTreadmillPurchase")
        return c ~= nil and c.args[1] == 3
    end)())
    clearWires()
    setCash(100)
    pump(6.0)
    check("autoupgradetreadmill: poor cash no invoke", invokeCount("UpgradeTreadmillPurchase") == 0)
    Library.Toggles.AutoUpgradeTreadmill:SetValue(false)

    -- AutoUpgradePlot
    setCash(2000000)
    Library.Toggles.AutoUpgradePlot:SetValue(true)
    pump(6.0)
    check("autoupgradeplot: FireCD on sign detector when affordable", (function()
        local n = 0
        for _, c in ipairs(Calls) do
            if c.fn == "FireCD" and c.cd == SignDetector then
                n = n + 1
            end
        end
        return n >= 1
    end)())
    clearWires()
    Calls = {}
    MyPlotModel:SetAttribute("Level", 5)
    setCash(999999999)
    pump(6.0)
    check("autoupgradeplot: max level no fire", (function()
        local n = 0
        for _, c in ipairs(Calls) do
            if c.fn == "FireCD" then
                n = n + 1
            end
        end
        return n == 0
    end)())
    MyPlotModel:SetAttribute("Level", 1)
    Library.Toggles.AutoUpgradePlot:SetValue(false)

    -- AutoTreadmill
    PLR:SetAttribute("TrainingTier", 2)
    character:SetAttribute("TrainingTreadmill", true)
    PLR:SetAttribute("TreadmillBonusOfferId", "token-abc")
    PLR:SetAttribute("TreadmillBonusOfferUntil", Sched.now + 100)
    Library.Toggles.AutoTreadmill:SetValue(true)
    pump(2.0)
    check("autotreadmill: activity ping fired (game's own 5s wire)", fireCount("TreadmillActivity") >= 1)
    check("autotreadmill: bonus token claimed", (function()
        local c = findInvoke("ClaimTreadmillBonus")
        return c ~= nil and c.args[1] == "token-abc"
    end)())
    clearWires()
    pump(6.0)
    check("autotreadmill: same token not re-claimed", invokeCount("ClaimTreadmillBonus") == 0)
    PLR:SetAttribute("TreadmillBonusOfferId", nil)
    PLR:SetAttribute("TrainingTier", nil)
    character:SetAttribute("TrainingTreadmill", nil)
    Library.Toggles.AutoTreadmill:SetValue(false)

    -- AutoFuse
    local evFuse = EventsFolder:FindFirstChild("FuseUpdated")
    evFuse.OnClientEvent:Fire({ ServerTime = os.time(), Tiers = { [1] = { EndsAt = os.time() - 10 } } })
    pump(0.5)
    Library.Toggles.AutoFuse:SetValue(true)
    pump(6.0)
    check("autofuse: Claim fired for finished tier 1", (function()
        for _, c in ipairs(WireLog.invokes) do
            if c.name == "FuseRequest" and c.args[1] == "Claim" and c.args[2] == 1 then
                return true
            end
        end
        return false
    end)())
    evFuse.OnClientEvent:Fire({ ServerTime = os.time(), Tiers = { [1] = { EndsAt = os.time() - 10, Claimed = true } } })
    clearWires()
    pump(6.0)
    check("autofuse: tier 2 toggles x3 + Fuse fired (tier 1 claimed)", (function()
        local toggles, fuse = 0, false
        for _, c in ipairs(WireLog.invokes) do
            if c.name == "FuseRequest" and c.args[1] == "Toggle" and c.args[2] == 2 then
                toggles = toggles + 1
            end
            if c.name == "FuseRequest" and c.args[1] == "Fuse" and c.args[2] == 2 then
                fuse = true
            end
        end
        return toggles == 3 and fuse
    end)())
    clearWires()
    pump(6.0)
    check("autofuse: 30s backoff (no refire within one cycle)", (function()
        local n = 0
        for _, c in ipairs(WireLog.invokes) do
            if c.name == "FuseRequest" and (c.args[1] == "Fuse" or c.args[1] == "Toggle") then
                n = n + 1
            end
        end
        return n == 0
    end)())
    Library.Toggles.AutoFuse:SetValue(false)

    -- AutoIndexReward
    MockState2.IndexClaimable = true
    Library.Toggles.AutoIndexReward:SetValue(true)
    pump(11.0)
    check("autoindexreward: claim fired when Claimable", invokeCount("ClaimIndexReward") >= 1)
    MockState2.IndexClaimable = false
    clearWires()
    pump(11.0)
    check("autoindexreward: no claim when not Claimable", invokeCount("ClaimIndexReward") == 0)
    Library.Toggles.AutoIndexReward:SetValue(false)

    -- AutoRace
    RaceStateFolder:SetAttribute("Phase", "Joining")
    Library.Toggles.AutoRace:SetValue(true)
    pump(3.0)
    check("autorace: Join fired during Joining phase", fireCount("RaceRequest", function(c) return c.args[1] == "Join" end) >= 1)
    check("autorace: reward Claim fired with offer id", (function()
        for _, c in ipairs(WireLog.invokes) do
            if c.name == "RaceRewardRequest" and c.args[1] == "Claim" and c.args[2] == 99 then
                return true
            end
        end
        return false
    end)())
    clearWires()
    RaceStateFolder:SetAttribute("Phase", "Idle")
    MockState2.RaceReady = false
    pump(3.0)
    check("autorace: no Join when phase Idle", fireCount("RaceRequest") == 0)
    Library.Toggles.AutoRace:SetValue(false)

    -- AutoFreeGift
    MockState2.GiftClaimed = false
    Library.Toggles.AutoFreeGift:SetValue(true)
    pump(61.0)
    check("autofreegift: Claim fired when not claimed", (function()
        for _, c in ipairs(WireLog.invokes) do
            if c.name == "FreeGiftRequest" and c.args[1] == "Claim" then
                return true
            end
        end
        return false
    end)())
    clearWires()
    pump(61.0)
    check("autofreegift: no re-claim once claimed", (function()
        for _, c in ipairs(WireLog.invokes) do
            if c.name == "FreeGiftRequest" and c.args[1] == "Claim" then
                return false
            end
        end
        return true
    end)())
    Library.Toggles.AutoFreeGift:SetValue(false)

    -- AutoOfflineLoot
    MockState2.LootReady = true
    Library.Toggles.AutoOfflineLoot:SetValue(true)
    pump(61.0)
    check("autoofflineloot: Claim fired when Ready", (function()
        for _, c in ipairs(WireLog.invokes) do
            if c.name == "OfflineLootRequest" and c.args[1] == "Claim" then
                return true
            end
        end
        return false
    end)())
    Library.Toggles.AutoOfflineLoot:SetValue(false)

    -- AutoDontLeaveGift
    MockState2.DNLAvailable = true
    Library.Toggles.AutoDontLeaveGift:SetValue(true)
    pump(61.0)
    check("autodontleavegift: Open then Claim fired", (function()
        local opened, claimed = false, false
        for _, c in ipairs(WireLog.invokes) do
            if c.name == "DontLeaveGiftRequest" and c.args[1] == "Open" then
                opened = true
            end
            if c.name == "DontLeaveGiftRequest" and c.args[1] == "Claim" then
                claimed = true
            end
        end
        return opened and claimed
    end)())
    Library.Toggles.AutoDontLeaveGift:SetValue(false)

    -- AutoSteal (not seated): walk to car, steal prompt, seat touch
    Library.Toggles.AutoSteal:SetValue(true)
    pump(8.0)
    check("autosteal: StealPrompt fired on nearest available car", (function()
        for _, c in ipairs(Calls) do
            if c.fn == "FirePP" and c.prompt == CarStealPrompt then
                return true
            end
        end
        return false
    end)())
    check("autosteal: DriverSeat touch fired for seating", (function()
        for _, c in ipairs(Calls) do
            if c.fn == "FireTI" and c.part == CarDriverSeat then
                return true
            end
        end
        return false
    end)())
    check("autosteal: character walked toward car (TweenTo moved HRP)", (function()
        local d0 = (Vector3.new(0, 5, 0) - CarChassis.Position).Magnitude
        local d1 = (charRoot.CFrame.Position - CarChassis.Position).Magnitude
        return d1 < d0 - 50
    end)())

    -- AutoSteal (seated): transport toward parking, then FirePP parking
    humanoid.SeatPart = CarDriverSeat
    CarModel:SetAttribute("TheftState", "Stolen")
    CarChassis.CFrame = CFrame.new(Vector3.new(120, 3, 100))
    pump(8.0)
    check("autosteal: chassis transported to nearest parking slot (within 22)", (function()
        local d5 = (CarChassis.CFrame.Position - ParkingPart2.Position).Magnitude
        local d3 = (CarChassis.CFrame.Position - ParkingPart.Position).Magnitude
        return math.min(d5, d3) <= 22
    end)())
    check("autosteal: ParkingPrompt fired on arrival (either slot)", (function()
        for _, c in ipairs(Calls) do
            if c.fn == "FirePP" and (c.prompt == ParkingPrompt or c.prompt == ParkingPrompt2) then
                return true
            end
        end
        return false
    end)())
    Library.Toggles.AutoSteal:SetValue(false)
    humanoid.SeatPart = nil
    clearWires()
    Calls = {}
    pump(2.0)
    check("autosteal: toggle off stops all wires", fireCount("TreadmillActivity") == 0 and invokeCount("GetSellInventory") == 0 and actionCount(function() return false end) == 0)

    check("final: no error notifies across whole run", (function()
        local ok, n = noErrorNotify()
        if not ok then print("  notify was: " .. tostring(n)) end
        return ok
    end)())
end

print(string.format("Steal A Car harness: %d pass / %d fail", Pass, Fail))
if Fail > 0 then
    for _, f in ipairs(Failures) do
        print("  failed: " .. f)
    end
    os.exit(1)
end
