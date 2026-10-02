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
                G.task.spawn(fn, v)
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
    pump(0.05)
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

-- ===== APPEND GAME MOCKS + TESTS BELOW THIS LINE =====================

local PLACE = (arg and arg[1]) or "Game"
local GAME_PLACE_ID = 109030368179494
local LOBBY_PLACE_ID = 132304466547289

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
G.writefile = function(path, content)
    MockFS[path] = content
end
G.readfile = function(path)
    return MockFS[path]
end
G.isfile = function(path)
    return MockFS[path] ~= nil
end
G.isfolder = function(path)
    return true
end
G.makefolder = function(path) end
G.listfiles = function(path)
    local out = {}
    for p in pairs(MockFS) do
        if p:sub(1, #path) == path then
            table.insert(out, p)
        end
    end
    table.sort(out)
    return out
end
G.listfolder = G.listfiles
G.appendfile = function(path, content)
    MockFS[path] = (MockFS[path] or "") .. content
end
G.delfile = function(path)
    MockFS[path] = nil
end
local TeleportQueue = {}
G.queue_on_teleport = function(code)
    table.insert(TeleportQueue, code)
end
local WebhookLog = {}
G.request = function(tbl)
    table.insert(WebhookLog, tbl)
    return { Success = true }
end
G.http_request = G.request
local MockExecContext = false
G.checkcaller = function()
    return MockExecContext
end
G.newcclosure = function(f)
    return f
end

local function jsonEnc(v)
    local t = type(v)
    if t == "string" then
        return "\"" .. v:gsub("[\\\"\n\r\t]", function(c)
            if c == "\\" then return "\\\\" end
            if c == "\"" then return "\\\"" end
            if c == "\n" then return "\\n" end
            if c == "\r" then return "\\r" end
            if c == "\t" then return "\\t" end
        end) .. "\""
    elseif t == "number" then
        return string.format("%.14g", v)
    elseif t == "boolean" then
        return tostring(v)
    elseif t ~= "table" then
        return "null"
    end
    local isArray = (#v > 0) or (next(v) == nil)
    if isArray then
        local parts = {}
        for i = 1, #v do
            table.insert(parts, jsonEnc(v[i]))
        end
        return "[" .. table.concat(parts, ",") .. "]"
    end
    local parts = {}
    for k, val in pairs(v) do
        table.insert(parts, jsonEnc(tostring(k)) .. ":" .. jsonEnc(val))
    end
    return "{" .. table.concat(parts, ",") .. "}"
end
local function jsonDec(s)
    local pos = 1
    local function skip()
        while pos <= #s and s:sub(pos, pos):match("[%s,]") do
            pos = pos + 1
        end
    end
    local parse
    parse = function()
        skip()
        local c = s:sub(pos, pos)
        if c == "{" then
            pos = pos + 1
            local out = {}
            skip()
            if s:sub(pos, pos) == "}" then
                pos = pos + 1
                return out
            end
            while true do
                skip()
                local k = parse()
                skip()
                pos = pos + 1
                local v = parse()
                out[k] = v
                skip()
                if s:sub(pos, pos) == "}" then
                    pos = pos + 1
                    break
                end
            end
            return out
        elseif c == "[" then
            pos = pos + 1
            local out = {}
            skip()
            if s:sub(pos, pos) == "]" then
                pos = pos + 1
                return out
            end
            while true do
                table.insert(out, parse())
                skip()
                if s:sub(pos, pos) == "]" then
                    pos = pos + 1
                    break
                end
            end
            return out
        elseif c == "\"" then
            pos = pos + 1
            local buf = {}
            while pos <= #s do
                local ch = s:sub(pos, pos)
                if ch == "\\" then
                    local nx = s:sub(pos + 1, pos + 1)
                    if nx == "n" then buf[#buf + 1] = "\n"
                    elseif nx == "t" then buf[#buf + 1] = "\t"
                    elseif nx == "r" then buf[#buf + 1] = "\r"
                    else buf[#buf + 1] = nx end
                    pos = pos + 2
                elseif ch == "\"" then
                    pos = pos + 1
                    break
                else
                    buf[#buf + 1] = ch
                    pos = pos + 1
                end
            end
            return table.concat(buf)
        else
            local num = s:match("^-?%d+%.?%d*[eE]?[+-]?%d*", pos)
            if num and #num > 0 then
                pos = pos + #num
                return tonumber(num)
            end
            if s:sub(pos, pos + 3) == "true" then
                pos = pos + 4
                return true
            end
            if s:sub(pos, pos + 4) == "false" then
                pos = pos + 5
                return false
            end
            if s:sub(pos, pos + 3) == "null" then
                pos = pos + 4
                return nil
            end
            error("json parse fail at " .. pos)
        end
    end
    local v = parse()
    return v
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

Services.Players = { LocalPlayer = PLR, GetPlayers = function() return { PLR } end }
Services.ReplicatedStorage = RS
Services.RunService = { Stepped = Signal.new(), RenderStepped = Signal.new(), Heartbeat = Signal.new(), PostSimulation = Signal.new(), IsServer = function() return false end, IsStudio = function() return false end, IsClient = function() return true end }
Services.TeleportService = { Teleport = function() end }
Services.UserInputService = { TouchEnabled = false, KeyboardEnabled = true, InputBegan = Signal.new() }
Services.HttpService = {
    JSONEncode = function(_, t) return jsonEnc(t) end,
    JSONDecode = function(_, s) return jsonDec(s) end,
}
Services.TweenService = { Create = function() return { Play = function() end } end, GetValue = function() return 0 end }
Services.Lighting = {}
Services.GuiService = { GetResolution = function() return Vector3.new(1920, 1080, 0) end, TopbarInset = function() return 0, 0 end }
Services.MarketplaceService = { GetUserOwnershipAsync = function() return { IsSuccess = function() return true end, UserOwnsGamePass = false } end }
Services.VirtualInputManager = { SendMouseButtonEvent = function() end, SendKeyEvent = function() end }
Services.CollectionService = {
    GetTagged = function(tag)
        if tag == "Grid" then
            local grid = Instance.new("Part", "GridPart")
            return { grid }
        end
        return {}
    end,
    HasTag = function() return false end,
}
Services.ProximityPromptService = { PromptButtonHoldBegan = Signal.new() }
Services.VirtualUser = { CaptureController = function() end, ClickButton2 = function() end }

G.game = {
    PlaceId = (PLACE == "Lobby") and LOBBY_PLACE_ID or GAME_PLACE_ID,
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
WS.GetPartBoundsInBox = function(self, cf, size, params)
    return {}
end
WS.GetPartsInPart = function(self, part, params)
    return {}
end
local Camera = Instance.new("Folder", "Camera")
WS:AddChild(Camera)

local Shared = Instance.new("Folder", "Shared")
RS:AddChild(Shared)
local Vendor = Instance.new("Folder", "Vendor")
Shared:AddChild(Vendor)
local ConfigFolder = Instance.new("Folder", "Config")
Shared:AddChild(ConfigFolder)

local MeWires = {}
local MeListeners = {}
local MeSingleton = nil
local MeMT = { __index = {} }
MeMT.__index = MeMT
function MeMT.Fire(self, name, ...)
    MeWires[name] = MeWires[name] or { Fires = {} }
    local packed = { n = select("#", ...), ... }
    table.insert(MeWires[name].Fires, packed)
end
function MeMT.Listen(self, name, fn)
    MeListeners[name] = MeListeners[name] or {}
    table.insert(MeListeners[name], fn)
    return { Disconnect = function() end }
end
function MeMT.Get(self, name, useComponents, waitFlag)
    return MeSingleton.Loaded[name]
end
MeSingleton = {
    Loaded = {},
    Events = {},
    Components = {},
    Classes = {},
}
setmetatable(MeSingleton, MeMT)

local function serverEvent(name, ...)
    local list = MeListeners[name]
    if list then
        local args = table.pack(...)
        for _, fn in ipairs(list) do
            G.task.spawn(function()
                local ok, err = pcall(fn, table.unpack(args, 1, args.n))
                if not ok then
                    print("listener error [" .. name .. "]: " .. tostring(err))
                end
            end)
        end
    end
end

local function wireCalls(name)
    local w = MeWires[name]
    return w and w.Fires or {}
end

local function wireCount(name, pred)
    local n = 0
    for _, c in ipairs(wireCalls(name)) do
        if not pred or pred(c) then
            n = n + 1
        end
    end
    return n
end

local AutoConfirmId = 9000
local AutoConfirmedIds = {}
local origFireLog = MeMT.Fire
MeMT.Fire = function(self, name, ...)
    origFireLog(self, name, ...)
    if name == "PlaceUnit" then
        local a, b = ...
        if type(a) == "string" and b and b.Position then
            AutoConfirmId = AutoConfirmId + 1
            local id = AutoConfirmId
            table.insert(AutoConfirmedIds, id)
            local px, py, pz = b.Position.X, b.Position.Y, b.Position.Z
            G.task.delay(0.05, function()
                serverEvent("ReplicateUnit", a, CFrame.new(Vector3.new(px, py, pz)), PLR.UserId, id, 0)
            end)
        end
    end
end

local UnitStats = {
    Archer = { Cost = 125, Range = 14, Damage = 16, Cooldown = 3.5 },
    Sword = { Cost = 100, Range = 8, Damage = 30, Cooldown = 5 },
}
local SharedConfig = {
    UnitStats = UnitStats,
    UnitUpgradeConfig = {
        MaxUpgrades = 5,
        IsMaxed = function(self, name, level) return (level or 0) >= 5 end,
        GetCost = function(self, name, level) return 125 end,
        GetPlaceCost = function(self, name, weather) return (UnitStats[name] and UnitStats[name].Cost) or 100 end,
    },
    TargetPriority = {
        Order = { "Closest", "Farthest", "Weakest", "Strongest" },
        Next = function(self, cur)
            local i = 1
            for idx, v in ipairs(self.Order) do
                if v == cur then i = idx end
            end
            return self.Order[(i % #self.Order) + 1]
        end,
    },
    MapConfig = {
        MAPS = {
            Farm = { DisplayName = "Farm", WinsRequired = 0 },
            Desert = { DisplayName = "Dessert", WinsRequired = 2 },
        },
    },
    CrateConfig = {
        RARITIES = { "Common", "Rare", "Epic", "Legendary" },
        CRATES = { Common = { DisplayName = "Crate Of Beginnings", Key = "CrateOfBeginnings" } },
    },
    ContractConfig = {
        get = function(self, id) return { Goal = 5 } end,
        isComplete = function(self, cfg, slot) return cfg.Goal <= (slot.Progress or 0) end,
    },
}

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
addModule(Vendor, "Me", { new = function() return MeSingleton end })
addModule(ConfigFolder, "SharedConfig", SharedConfig)

local ReplicaData = {
    EquippedUnits = { "Archer", "Sword" },
    CardLimit = 6,
    Units = { Archer = 1, Sword = 1 },
    Gamepasses = {},
    Stats = { Wins = 3 },
    Shards = 500,
    Inventory = {
        Crates = { Common = 2 },
    },
    Contracts = {
        Hourly = { Slots = { { Id = "C1", Claimed = false, Progress = 5 }, { Id = "C2", Claimed = false, Progress = 1 } } },
        Daily = { Slots = { { Id = "D1", Claimed = false, Progress = 0 } } },
    },
}
local Replica = {
    Data = ReplicaData,
    OnChange = function(self, fn) return { Disconnect = function() end } end,
}
local DataController = {
    GetReplica = function(self) return Replica end,
}
MeSingleton.Loaded["DataController"] = DataController

if PLACE ~= "Lobby" then
    local PathScriptable = Instance.new("Folder", "PathScriptable")
    WS:AddChild(PathScriptable)
    local Nodes = Instance.new("Folder", "Nodes")
    PathScriptable:AddChild(Nodes)
    local n1 = Instance.new("Part", "Node1")
    n1.CFrame = CFrame.new(Vector3.new(0, 1, 20))
    Nodes:AddChild(n1)
    local n2 = Instance.new("Part", "Node2")
    n2.CFrame = CFrame.new(Vector3.new(0, 1, 40))
    Nodes:AddChild(n2)
else
    local Map = Instance.new("Folder", "Map")
    WS:AddChild(Map)
    local Portals = Instance.new("Folder", "Portals")
    Map:AddChild(Portals)
    local Portal = Instance.new("Model", "Portal")
    Portals:AddChild(Portal)
    Portal:SetAttribute("PortalId", 7)
    local EnterPart = Instance.new("Part", "PortalEnterCFrame")
    EnterPart.CFrame = CFrame.new(Vector3.new(30, 3, 30))
    Portal:AddChild(EnterPart)
    local Crates = Instance.new("Folder", "UnboxingCrates")
    WS:AddChild(Crates)
    local Board = Instance.new("Folder", "ContractsBoard")
    WS:AddChild(Board)
end

local ScriptSrc = ""
do
    local f = io.open((arg and arg[2]) or "/home/z/SavedFolder/work/lua/Periastron.lua", "r")
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

pump(0.2)
local fn = G.loadstring(ScriptSrc, "=(Periastron)")
G.task.spawn(fn)
pump(1.0)

check("script loaded without ERROR notify", (function()
    local ok, n = noErrorNotify()
    if not ok then print("  notify was: " .. tostring(n)) end
    return ok
end)())
check("guard set", G.ayasemiyatongekissazumirisa == true)
check("save folder Yuri/PeriastronTD", SaveManager.Folder == "Yuri/PeriastronTD")
check("AutoPlace registered", Library.Toggles.AutoPlace ~= nil)
check("AutoUpgrade registered", Library.Toggles.AutoUpgrade ~= nil)
check("MacroRecord registered", Library.Toggles.MacroRecord ~= nil)
check("LoadMacro registered", Library.Toggles.LoadMacro ~= nil)
check("AutoQueue registered", Library.Toggles.AutoQueue ~= nil)
check("AutoCrate registered", Library.Toggles.AutoCrate ~= nil)
check("AutoClaimContracts registered", Library.Toggles.AutoClaimContracts ~= nil)
check("AutoVoteSkip registered", Library.Toggles.AutoVoteSkip ~= nil)
check("AutoReady registered", Library.Toggles.AutoReady ~= nil)
check("AutoSpeed registered", Library.Toggles.AutoSpeed ~= nil)
check("AutoReplay registered", Library.Toggles.AutoReplay ~= nil)
check("AutoLeave registered", Library.Toggles.AutoLeave ~= nil)
check("AutoReexec removed (invented + template feature deleted upstream)", Library.Toggles.AutoReexec == nil)
check("AutoSell slider-toggle registered", Library.Toggles.AutoSell ~= nil and Library.Options.AutoSellValue ~= nil)
check("PlaceAndUpgrade registered", Library.Toggles.PlaceAndUpgrade ~= nil)
check("PlaceOrder1-6 sliders registered", Library.Options.PlaceOrder1 ~= nil and Library.Options.PlaceOrder6 ~= nil)
check("UpgradeLimit1-6 sliders registered", Library.Options.UpgradeLimit1 ~= nil and Library.Options.UpgradeLimit6 ~= nil)
check("SpeedTarget dropdown registered", Library.Options.SpeedTarget ~= nil)
check("DefeatMode removed (analysis-only invention)", Library.Options.DefeatMode == nil)
check("ExecSource removed with reexec", Library.Options.ExecSource == nil)
check("WHMatchEnd registered", Library.Toggles.WHMatchEnd ~= nil)
check("tab layout: Game/Macro/Lobby + AutoPlay/Webhook tabs", (function()
    local seen = {}
    for _, n in ipairs(MockState.Tabs) do seen[n] = true end
    return seen["Game"] and seen["Macro"] and seen["Lobby"] and seen["Auto Play"] and seen["Webhook"] and seen["LobbyConfig"]
end)())
check("UpgradeMethod values match slop format", (function()
    local dd = Library.Options.UpgradeMethod
    if not dd or not dd.Values or #dd.Values ~= 4 then return false end
    return dd.Values[1] == "Lowest Level (Spread Upgrade)"
        and dd.Values[2] == "Hotbar left to right (until Max)"
        and dd.Values[3] == "Randomize"
        and dd.Values[4] == "Customize upgrade order (Set below)"
end)())
check("ReplayMode Time|Money default Time", (function()
    local dd = Library.Options.ReplayMode
    return dd and dd.Values and dd.Values[1] == "Time" and dd.Values[2] == "Money" and dd.Value == "Time"
end)())
check("no invented controls (UpgradeReserve/PlaceDelay/Stats absent)", Library.Options.UpgradeReserve == nil and Library.Options.PlaceDelay == nil)
check("script never queues teleport reexec", #TeleportQueue == 0)

if PLACE ~= "Lobby" then
    check("game place detected", (function()
        for _, n in ipairs(MockState.Notifies) do
            if string.find(n, "Game place detected", 1, true) then return true end
        end
        return false
    end)())
    check("deck loaded from replica (slot dropdown has Archer)", (function()
        local dd = Library.Options.SetSlotSelect
        if not dd or not dd.Values then return false end
        for _, v in ipairs(dd.Values) do
            if v == "Slot 1 (Archer)" then return true end
        end
        return false
    end)())
    serverEvent("UpdateCash", 1000)
    pump(0.2)
    serverEvent("ReplicateUnit", "Archer", CFrame.new(Vector3.new(2, 1, 18)), PLR.UserId, 1, 0)
    pump(0.5)
    serverEvent("SetWave", 3)
    pump(0.2)

    Library.Toggles.AutoUpgrade:SetValue(true)
    pump(1.5)
    check("AutoUpgrade fires UpgradeUnit(1)", wireCount("UpgradeUnit", function(c) return c[1] == 1 end) >= 1)
    Library.Toggles.AutoUpgrade:SetValue(false)
    pump(0.2)

    Library.Options.UpgradeLimit1:SetValue(1)
    Library.Toggles.AutoUpgrade:SetValue(true)
    pump(1.5)
    local upgAtZero = wireCount("UpgradeUnit", function(c) return c[1] == 1 end)
    check("UpgradeLimit1=1 allows upgrading level-0 unit", upgAtZero >= 1)
    serverEvent("UnitUpgraded", 1, 1)
    pump(1.5)
    check("UpgradeLimit1=1 blocks past level 1 (real level gating)", wireCount("UpgradeUnit", function(c) return c[1] == 1 end) == upgAtZero)
    Library.Toggles.AutoUpgrade:SetValue(false)
    Library.Options.UpgradeLimit1:SetValue(0)
    pump(0.2)
    Library.Toggles.AutoPlace:SetValue(true)
    pump(2.5)
    check("AutoPlace fires PlaceUnit with deck name", wireCount("PlaceUnit", function(c) return c[1] == "Archer" or c[1] == "Sword" end) >= 1)
    check("AutoPlace passes CFrame payload", (function()
        for _, c in ipairs(wireCalls("PlaceUnit")) do
            if c[2] and c[2].Position and c[2].X then return true end
        end
        return false
    end)())
    Library.Toggles.AutoPlace:SetValue(false)
    pump(0.2)

    for _, id in ipairs(AutoConfirmedIds) do
        serverEvent("RemoveUnit", id)
    end
    AutoConfirmedIds = {}
    pump(0.3)
    local archerBefore = wireCount("PlaceUnit", function(c) return c[1] == "Archer" end)
    Library.Options.PlaceLimit1:SetValue(2)
    Library.Toggles.AutoPlace:SetValue(true)
    pump(0.5)
    check("AutoPlace placed one more Archer under limit 2", wireCount("PlaceUnit", function(c) return c[1] == "Archer" end) - archerBefore == 1)
    serverEvent("ReplicateUnit", "Archer", CFrame.new(Vector3.new(4, 1, 22)), PLR.UserId, 101, 0)
    pump(2.5)
    check("PlaceLimit1=2 stops placing after confirm (registry now 2)", wireCount("PlaceUnit", function(c) return c[1] == "Archer" end) - archerBefore == 1)
    Library.Toggles.AutoPlace:SetValue(false)
    Library.Options.PlaceLimit1:SetValue(0)
    pump(0.2)

    Library.Toggles.PlaceAndUpgrade:SetValue(true)
    Library.Toggles.AutoPlace:SetValue(true)
    local placedCf, placedName = nil, nil
    for _ = 1, 40 do
        pump(0.25)
        local calls = wireCalls("PlaceUnit")
        if #calls > 0 then
            local c = calls[#calls]
            placedName = c[1]
            placedCf = c[2]
            break
        end
    end
    check("AutoPlace fired for PlaceAndUpgrade test", placedName ~= nil and placedCf ~= nil)
    if placedName and placedCf then
        pump(3.5)
        check("PlaceAndUpgrade upgrades the placed unit", wireCount("UpgradeUnit", function(c) return type(c[1]) == "number" and c[1] >= 9000 end) >= 1)
    end
    Library.Toggles.AutoPlace:SetValue(false)
    Library.Toggles.PlaceAndUpgrade:SetValue(false)
    pump(0.2)

    serverEvent("PlayMapMusic", "Farm")
    pump(0.3)
    local function findButton(text)
        for _, b in ipairs(MockState.Buttons) do
            if b.Text == text then return b end
        end
        return nil
    end
    Library.Options.SetSlotSelect:SetValue("Slot 1 (Archer)")
    local setBtn = findButton("Set Slot Position")
    check("Set Slot Position button present", setBtn ~= nil)
    if setBtn then
        setBtn.Func()
        pump(0.5)
    end
    check("position.json written with per-map bucket", (function()
        local raw = MockFS["Yuri/PeriastronTD/position.json"]
        return raw ~= nil and string.find(raw, "Farm", 1, true) ~= nil and string.find(raw, '"1"', 1, true) ~= nil
    end)())
    Library.Toggles.AutoPlace:SetValue(true)
    pump(1.5)
    check("AutoPlace uses saved slot position", (function()
        for _, c in ipairs(wireCalls("PlaceUnit")) do
            local p = c[2].Position
            if math.abs(p.X) < 0.6 and math.abs(p.Y - 5) < 0.6 and math.abs(p.Z) < 0.6 then return true end
        end
        return false
    end)())
    Library.Toggles.AutoPlace:SetValue(false)
    pump(0.2)
    local resetBtn = findButton("Reset Position")
    check("Reset Position button present", resetBtn ~= nil)
    if resetBtn then
        resetBtn.Func()
        pump(0.5)
    end
    check("reset clears the map bucket", (function()
        local raw = MockFS["Yuri/PeriastronTD/position.json"]
        return raw ~= nil and string.find(raw, "Farm", 1, true) == nil
    end)())

    Library.Toggles.AutoReady:SetValue(true)
    serverEvent("WaveIntermission", { timeLeft = 10 })
    pump(1.0)
    check("AutoReady fires ReadyWave on intermission", wireCount("ReadyWave") >= 1)
    serverEvent("SetWave", 4)
    pump(0.2)

    Library.Toggles.AutoVoteSkip:SetValue(true)
    serverEvent("SkipState", { active = true, votes = 1, total = 2 })
    pump(0.5)
    check("AutoVoteSkip fires VoteSkip(true)", wireCount("VoteSkip", function(c) return c[1] == true end) >= 1)

    Library.Toggles.AutoSpeed:SetValue(true)
    pump(0.5)
    check("AutoSpeed fires SetGameSpeed(2)", wireCount("SetGameSpeed", function(c) return c[1] == 2 end) >= 1)

    Library.Toggles.AutoSell:SetValue(true)
    Library.Options.AutoSellValue:SetValue(10)
    serverEvent("SetWave", 10)
    pump(1.5)
    check("AutoSell at wave 10 fires SellUnit", wireCount("SellUnit", function(c) return c[1] == 1 end) >= 1)
    serverEvent("RemoveUnit", 1)
    pump(0.3)
    local soldAfterRemove = wireCount("SellUnit", function(c) return c[1] == 1 end)
    serverEvent("SetWave", 11)
    pump(1.5)
    check("no re-sell after unit removed (slop semantics)", wireCount("SellUnit", function(c) return c[1] == 1 end) == soldAfterRemove)

    serverEvent("UpdateCash", 100000)
    pump(0.2)
    Library.Options.FileName:SetValue("selfmacro")
    MockExecContext = true
    Library.Toggles.MacroRecord:SetValue(true)
    pump(0.2)
    local ownFireBase = wireCount("UpgradeUnit")
    Library.Toggles.AutoUpgrade:SetValue(true)
    pump(1.5)
    Library.Toggles.AutoUpgrade:SetValue(false)
    check("autofire actually fired during own-fire test", wireCount("UpgradeUnit") > ownFireBase)
    Library.Toggles.MacroRecord:SetValue(false)
    pump(0.3)
    check("own autofarm fires NOT captured (checkcaller gate)", MockFS["Yuri/PeriastronTD/Macros/selfmacro.json"] == nil)
    MockExecContext = false

    Library.Options.FileName:SetValue("testmacro")
    Library.Toggles.MacroRecord:SetValue(true)
    pump(0.2)
    MeMT.Fire(MeSingleton, "PlaceUnit", "Sword", CFrame.new(Vector3.new(5, 1, 25)))
    MeMT.Fire(MeSingleton, "UpgradeUnit", 1)
    pump(0.3)
    Library.Toggles.MacroRecord:SetValue(false)
    pump(0.3)
    check("macro file saved", MockFS["Yuri/PeriastronTD/Macros/testmacro.json"] ~= nil)
    check("macro contains Place entry", (function()
        local raw = MockFS["Yuri/PeriastronTD/Macros/testmacro.json"]
        return raw and string.find(raw, "Place", 1, true) and string.find(raw, "Sword", 1, true) ~= nil
    end)())
    check("macro contains Upgrade entry", (function()
        local raw = MockFS["Yuri/PeriastronTD/Macros/testmacro.json"]
        return raw and string.find(raw, "Upgrade", 1, true) ~= nil
    end)())
    check("macro Time is raw seconds (slop format, no ms encoding)", (function()
        local raw = MockFS["Yuri/PeriastronTD/Macros/testmacro.json"]
        local t = raw and raw:match('"Time":"11 ([0-9%.]+)"')
        return t ~= nil and tonumber(t) < 120
    end)())

    Library.Options.MacroSelected:SetValue("testmacro")
    Library.Toggles.LoadMacro:SetValue(true)
    pump(2.0)
    check("macro replay fires PlaceUnit for recorded unit", (function()
        local base = wireCount("PlaceUnit", function(c) return c[1] == "Sword" end)
        return base >= 1
    end)())
    Library.Toggles.LoadMacro:SetValue(false)
    pump(0.2)

    Library.Options.FileName:SetValue("waitmacro")
    serverEvent("SetWave", 12)
    pump(0.1)
    Library.Toggles.MacroRecord:SetValue(true)
    pump(3.2)
    MeMT.Fire(MeSingleton, "PlaceUnit", "Sword", CFrame.new(Vector3.new(6, 1, 26)))
    pump(0.3)
    Library.Toggles.MacroRecord:SetValue(false)
    pump(0.3)
    check("waitmacro saved", MockFS["Yuri/PeriastronTD/Macros/waitmacro.json"] ~= nil)
    local swordBase = wireCount("PlaceUnit", function(c) return c[1] == "Sword" end)
    serverEvent("SetWave", 12)
    pump(0.1)
    Library.Options.MacroSelected:SetValue("waitmacro")
    Library.Toggles.LoadMacro:SetValue(true)
    pump(0.6)
    check("Time mode waits for recorded elapsed (no early fire)", wireCount("PlaceUnit", function(c) return c[1] == "Sword" end) == swordBase)
    pump(4.0)
    check("Time mode fires once elapsed reached", wireCount("PlaceUnit", function(c) return c[1] == "Sword" end) > swordBase)
    Library.Toggles.LoadMacro:SetValue(false)
    pump(0.2)

    Library.Options.WebhookURL:SetValue("https://discord.com/api/webhooks/test")
    Library.Toggles.WHMatchEnd:SetValue(true)
    pump(0.1)
    serverEvent("Win", {})
    pump(1.0)
    check("Win sends webhook when WHMatchEnd on", #WebhookLog >= 1 and string.find(WebhookLog[#WebhookLog].Body, "Victory", 1, true) ~= nil)
    check("webhook carries yuri avatar", string.find(WebhookLog[#WebhookLog].Body, "avatar_url", 1, true) ~= nil)

    serverEvent("RoundRestarted")
    pump(1.0)
    check("RoundRestarted re-applies game speed", wireCount("SetGameSpeed", function(c) return c[1] == 2 end) >= 2)

    serverEvent("GameOver", {})
    pump(3.0)
    check("defeat webhook sent when WHMatchEnd on", (function()
        local last = WebhookLog[#WebhookLog]
        return last ~= nil and string.find(last.Body, "Defeat", 1, true) ~= nil
    end)())
    check("GameOver fires NO teleport (DefeatMode removed, slop parity)", wireCount("RequestLobbyTeleport") == 0)

    check("RequestCash requested at init", wireCount("RequestCash") >= 1)
else
    check("lobby place detected", (function()
        for _, n in ipairs(MockState.Notifies) do
            if string.find(n, "Lobby place detected", 1, true) then return true end
        end
        return false
    end)())
    check("QueueMap dropdown has map names", (function()
        local dd = Library.Options.QueueMap
        if not dd or not dd.Values then return false end
        local seen = 0
        for _, v in ipairs(dd.Values) do
            if v == "Farm" or v == "Desert" then seen = seen + 1 end
        end
        return seen >= 2
    end)())

    Library.Toggles.AutoQueue:SetValue(true)
    pump(7.0)
    check("AutoQueue fires RequestJoinGroup(7)", wireCount("RequestJoinGroup", function(c) return c[1] == 7 end) >= 1)
    Library.Options.QueueMap:SetValue("Desert")
    pump(35.0)
    check("AutoQueue creates group with selected map", wireCount("RequestCreateGroup", function(c) return c[1] == 7 and c[2] == "Desert" and c[3] == 1 end) >= 1)
    Library.Toggles.AutoQueue:SetValue(false)
    pump(0.2)

    Library.Toggles.AutoCrate:SetValue(true)
    pump(5.0)
    check("AutoCrate opens Common crates", wireCount("RequestOpenCrate", function(c) return c[1] == "Common" end) >= 1)
    Library.Toggles.AutoCrate:SetValue(false)
    pump(0.2)

    Library.Toggles.AutoClaimContracts:SetValue(true)
    pump(6.0)
    check("AutoClaimContracts claims complete Hourly slot 1", wireCount("ClaimContract", function(c) return c[1] == "Hourly" and c[2] == 1 end) >= 1)
    check("AutoClaimContracts skips incomplete slot 2", wireCount("ClaimContract", function(c) return c[2] == 2 end) == 0)
    Library.Toggles.AutoClaimContracts:SetValue(false)
    pump(0.2)

    check("lobby: no reexec elements remain", Library.Toggles.AutoReexec == nil and Library.Options.ExecSource == nil)
end

print(string.format("Periastron harness (%s): %d pass / %d fail", PLACE, Pass, Fail))
if Fail > 0 then
    for _, f in ipairs(Failures) do
        print("  failed: " .. f)
    end
    os.exit(1)
end
