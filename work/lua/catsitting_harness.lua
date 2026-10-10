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
-- 7 Days Cat-Sitting (CS1) real-load harness — game world + checks.
-- World model per work/lua/catsitting-analysis.md: two-place game
-- (GAME house world + LOBBY shop world), prompt-driven chores, workspace
-- attribute oracle (Chore_*/anomaly flags), litter minigame session wires,
-- phone photo wires, lobby shop RemoteFunctions.

local ScriptPath = arg and arg[1]
local ScriptSrc
do
    local paths = {}
    if ScriptPath then
        table.insert(paths, ScriptPath)
    end
    for _, p in ipairs({
        "SevenDaysCatSitting.lua",
        "/home/z/SavedFolder/work/lua/SevenDaysCatSitting.lua",
        "/home/z/Public/cat/7 Days Cat-Sitting/7 Days Cat-Sitting.lua",
        "/home/z/Public/cat/7 Days Cat-Sitting (GAME)/7 Days Cat-Sitting.lua",
    }) do
        table.insert(paths, p)
    end
    for _, p in ipairs(paths) do
        if p then
            local f = io.open(p, "r")
            if f then
                ScriptSrc = f:read("*a")
                f:close()
                ScriptPath = p
                break
            end
        end
    end
end
assert(ScriptSrc, "script under test not found (pass path as arg[1])")

G.os = setmetatable({ clock = function() return Sched.now end, date = function() return "00:00:00" end, time = function() return 0 end }, { __index = os })

-- ===== Instance mock fidelity patch: dot access finds children (real Roblox behavior) =====
do
    local origNew = G.Instance.new
    local origIndex = nil
    G.Instance.new = function(className, name)
        local obj = origNew(className, name)
        local mt = getmetatable(obj)
        if not origIndex then
            origIndex = mt.__index
        end
        mt.__index = function(t, k)
            local v = origIndex(t, k)
            if v ~= nil then
                return v
            end
            for _, c in ipairs(t._children) do
                if c.Name == k then
                    return c
                end
            end
            return nil
        end
        return obj
    end
end

table.clear = table.clear or function(t)
    for k in pairs(t) do
        t[k] = nil
    end
end

-- ===== capture tables (fns defined after the world builder) =====
local PromptFires = {}
local TouchFires = {}
local LitterStartCounter = 0
local LitterPromptRef = nil
local LitterEventMock = nil
G.fireclickdetector = nil
G.firesignal = nil
G.hookmetamethod = nil
G.getconnections = nil
G.cloneref = function(...) return ... end
G.identifyexecutor = function() return "HarnessExecutor" end
G.setfpscap = nil
G.setclipboard = nil
G.writefile = nil
G.isfile = nil
G.appendfile = nil
G.delfile = nil

-- ===== remote mocks =====
local RemoteFires = {}
local RemoteInvokes = {}
local CrateCash = 25
local function mockRemote(name, className)
    local r = Instance.new(className or "RemoteEvent", name)
    r._fires = {}
    function r:FireServer(...)
        local args = table.pack(...)
        table.insert(RemoteFires, { remote = name, args = args })
        table.insert(self._fires, args)
        if name == "LitterCleaning.Event" then
            local action = args[1]
            if action == "Drop" then
                local sid, index = args[2], args[3]
                G.task.delay(0.05, function()
                    local n = 0
                    for _, f in ipairs(self._fires) do
                        if f[1] == "Drop" and f[2] == sid then n = n + 1 end
                    end
                    self.OnClientEvent._serverFire("Collected", sid, { index = index, found = n })
                    if n >= 5 then
                        self.OnClientEvent._serverFire("Win", sid, "cleaned")
                    end
                end)
            end
        end
    end
    function r:InvokeServer(...)
        local args = table.pack(...)
        table.insert(RemoteInvokes, { remote = name, args = args })
        if name == "Shop.GetState" then
            return { cash = CrateCash, owned = { Orange = true }, equipped = "Orange" }
        end
        if name == "Shop.OpenCrate" then
            if CrateCash < 10 then
                return { ok = false, reason = "cash", state = { cash = CrateCash } }
            end
            CrateCash = CrateCash - 10
            return { ok = true, state = { cash = CrateCash }, reel = {} }
        end
        return nil
    end
    r.OnClientEvent = Signal.new()
    r.OnClientEvent._serverFire = function(...)
        local args = table.pack(...)
        for _, conn in ipairs(r.OnClientEvent._handlers) do
            if conn.Connected then
                spawnCo(function()
                    conn._fn(table.unpack(args, 1, args.n))
                end)
            end
        end
    end
    return r
end


-- ===== RS tree =====
local RS = Instance.new("Folder", "ReplicatedStorage")
local function rsRemote(name, className)
    local parts = string.split(name, ".")
    local cur = RS
    for i = 1, #parts - 1 do
        local f = cur:FindFirstChild(parts[i])
        if not f then
            f = Instance.new("Folder", parts[i])
            cur:AddChild(f)
        end
        cur = f
    end
    local r = mockRemote(name, className)
    r.Name = parts[#parts]
    cur:AddChild(r)
    return r
end
local R_Pet = rsRemote("Cat.Pet")
local R_Stare = rsRemote("Cat.Stare")
local R_Eat = rsRemote("Meal.Eat")
local R_Laser = rsRemote("Laser.Point")
local R_Photo = rsRemote("Phone.Photo")
local R_Litter = rsRemote("LitterCleaning.Event")
local R_Reply = rsRemote("Phone.Reply")
local R_Skip = rsRemote("Tutorial.Skip")
local R_GetState = rsRemote("Shop.GetState", "RemoteFunction")
local R_OpenCrate = rsRemote("Shop.OpenCrate", "RemoteFunction")
local R_Buy = rsRemote("Shop.Buy", "RemoteFunction")
local R_Equip = rsRemote("Shop.Equip", "RemoteFunction")
local R_EndingsGet = rsRemote("Endings.Get", "RemoteFunction")
local R_EndingLobby = rsRemote("Ending.Lobby")
local R_EndingVote = rsRemote("Ending.Vote")
local R_Objective = rsRemote("Objective.Set")
R_Objective.OnClientEvent = Signal.new()
R_Objective.OnClientEvent._serverFire = function() end

local function GetObjectShim(root, pathStr)
    local cur = root
    for _, seg in ipairs(string.split(pathStr, ".")) do
        if not cur then return nil end
        cur = cur:FindFirstChild(seg)
    end
    return cur
end

-- ===== world builder =====
local WS = Instance.new("Workspace", "Workspace")
for _, name in ipairs({ "Catzilla", "CreepyHead", "FakeDoor", "Grandma", "Misplaced", "Seeker", "SmilingMan", "StalkerInBedroom", "ToiletFace", "VoidOutside", "WindowMonster", "TutorialDone" }) do
    WS:SetAttribute(name, false)
end
for _, name in ipairs({ "Chore_Eat", "Chore_Feed", "Chore_Litter", "Chore_Lock", "Chore_Mail", "Chore_Play" }) do
    WS:SetAttribute(name, false)
end
WS:SetAttribute("PetCount", 0)
WS:SetAttribute("Night", 1)
WS:SetAttribute("CreepyStare", 0)

local function makeNode(parent, className, name)
    local obj = Instance.new(className, name)
    parent:AddChild(obj)
    return obj
end
local function makePart(parent, name, pos)
    local p = makeNode(parent, "Part", name)
    p:SetCFrame(CFrame.new(pos or Vector3.new(0, 0, 0)))
    return p
end
local function makeModel(parent, name)
    return makeNode(parent, "Model", name)
end
local function makeFolder(parent, name)
    return makeNode(parent, "Folder", name)
end
local function chainPrompt(root, pathStr, promptName)
    local cur = root
    for _, seg in ipairs(string.split(pathStr, ".")) do
        local existing = cur:FindFirstChild(seg)
        if existing then
            cur = existing
        else
            cur = makePart(cur, seg)
        end
    end
    local pr = makeNode(cur, "ProximityPrompt", promptName)
    pr.MaxActivationDistance = 999
    return pr
end

local House = makeFolder(WS, "House")
local Important = makeFolder(House, "Important")
local Kitchen = makeFolder(Important, "Kitchen")

local P_CanTake = chainPrompt(Kitchen, "Cabinets.Base_N1.CatFoodCan.CanBody.TakePromptAttachment", "TakePrompt")
local P_Fill = chainPrompt(Kitchen, "FoodBowl.Food Bowl.Cylinder.FillPromptAttachment", "FillPrompt")
local P_DinnerTake = chainPrompt(Kitchen, "Fridge.TVDinner.Tray.TakePromptAttachment", "TakePrompt")
local P_FridgeDoor = chainPrompt(Kitchen, "Fridge.FridgeDoor.Leaf.Panel.OpenClosePromptAttachment", "OpenClosePrompt")
local FridgeDoor = GetObjectShim(Kitchen, "Fridge.FridgeDoor")
FridgeDoor:SetAttribute("Open", false)
local P_Cook = chainPrompt(Kitchen, "Cabinets.Microwave.Carcass.Turntable.CookPromptAttachment", "CookPrompt")
local Microwave = GetObjectShim(Kitchen, "Cabinets.Microwave")
Microwave:SetAttribute("State", "Empty")

local LivingRoom = makeFolder(Important, "LivingRoom")
local P_LaserTake = chainPrompt(LivingRoom, "LaserPointer.Body.TakePromptAttachment", "TakePrompt")
local P_TV = chainPrompt(LivingRoom, "TV.Screen.TogglePromptAttachment", "TogglePrompt")
local TV = GetObjectShim(LivingRoom, "TV")
TV:SetAttribute("On", false)

local Bathroom = makeFolder(Important, "Bathroom")
local P_Flush = chainPrompt(Bathroom, "Toilet.Flush.Lever.FlushPromptAttachment", "FlushPrompt")

local Doors = makeFolder(Important, "Doors")
local P_Lock = chainPrompt(Doors, "Front Door.Leaf.Deadbolt.LockPromptAttachment", "LockPrompt")
local FrontDoor = GetObjectShim(Doors, "Front Door")
FrontDoor:SetAttribute("Locked", false)

local RoomLighting = makeFolder(Important, "RoomLighting")
local Switches = makeFolder(RoomLighting, "Switches")
local SwitchPrompts = {}
for i, name in ipairs({ "BathroomSwitch", "BedroomHallSwitch", "BedroomSwitch", "EntryHallSwitch", "KitchenSwitch", "LaundrySwitch", "LivingRoomSwitch" }) do
    local sw = makeModel(Switches, name)
    sw:SetAttribute("On", i <= 4)
    SwitchPrompts[name] = chainPrompt(sw, "Faceplate.Interaction", "LightSwitchPrompt")
end

local Parts = makeFolder(House, "Parts")
local Bedroom = makeFolder(Parts, "Bedroom")
local P_Sleep = chainPrompt(Bedroom, "Mattress.SleepPromptAttachment", "SleepPrompt")
local Chair = makeModel(Bedroom, "Chair")
makePart(Chair, "Seat", Vector3.new(2, 1, 2))

local Laundry = makeFolder(Parts, "Laundry")
local P_CleanLitter = chainPrompt(Laundry, "LitterBox.LitterInteraction", "CleanLitterPrompt")

local InteriorLayout = makeFolder(Parts, "InteriorLayout")
local Curtains = makeFolder(InteriorLayout, "Curtains")
local BlindsPrompts = {}
for i, name in ipairs({ "01_BathroomBack_Glass", "02_BedroomBack_Glass", "03_East_Glass", "04_Front_Glass", "05_Front_Glass", "06_UtilityBack_Glass", "07_West_Glass", "08_West_Glass" }) do
    local c = makeModel(Curtains, name)
    c:SetAttribute("BlindsClosed", i <= 3)
    BlindsPrompts[name] = chainPrompt(c, "BlindsPromptAnchor", "BlindsPrompt")
end

local Neighborhood = makeFolder(WS, "Neighborhood")
local P_Mailbox = chainPrompt(Neighborhood, "Parts.PetsitFrontYard.Mailbox.Body.MailboxPromptAttachment", "MailboxPrompt")

local Cat = makeModel(WS, "Cat")
local CatRoot = makePart(Cat, "CatRoot", Vector3.new(5, 1, 5))
Cat.PrimaryPart = CatRoot
local CreepyHead = makeModel(Cat, "CreepyCatHead")
local CreepyHeadPart = makePart(CreepyHead, "HeadPart", Vector3.new(5, 1.5, 5))
CreepyHead.PrimaryPart = CreepyHeadPart
LitterPromptRef = P_CleanLitter
LitterEventMock = R_Litter


-- ===== fireproximityprompt / firetouchinterest capture (needs world refs) =====
G.fireproximityprompt = function(prompt)
    table.insert(PromptFires, prompt)
    if prompt == LitterPromptRef and LitterEventMock then
        LitterStartCounter = LitterStartCounter + 1
        local sid = "sid-" .. tostring(LitterStartCounter)
        G.task.delay(0.05, function()
            LitterEventMock.OnClientEvent._serverFire("Start", sid)
        end)
    end
end
G.firetouchinterest = function(part, root, touch)
    table.insert(TouchFires, { part = part, root = root, touch = touch })
end

-- ===== player / character / gui =====
local PLR = {
    UserId = 42,
    Name = "Tester",
    DisplayName = "Tester",
    Character = nil,
    CameraMaxZoomDistance = 128,
    Idled = Signal.new(),
    GetAttribute = function() return nil end,
    GetAttributeChangedSignal = function() return Signal.new() end,
    SetAttribute = function() end,
}
local Backpack = Instance.new("Backpack", "Backpack")
local Char = Instance.new("Model", "Char")
local HRP = Instance.new("Part", "HumanoidRootPart")
HRP:SetCFrame(CFrame.new(Vector3.new(0, 3, 0)))
Char:AddChild(HRP)
local Hum = Instance.new("Humanoid", "Humanoid")
Char:AddChild(Hum)
local equipped = {}
local EquippedLog = {}
function Hum:EquipTool(t)
    equipped[t] = true
    table.insert(EquippedLog, t)
end
function Hum:UnequipTools()
    table.clear(equipped)
end
PLR.Character = Char
PLR.Backpack = Backpack

local PlayerGui = Instance.new("Folder", "PlayerGui")
local LitterGui = Instance.new("ScreenGui", "LitterCleaningGui")
PlayerGui:AddChild(LitterGui)
local LitterPanel = Instance.new("Frame", "Panel")
LitterGui:AddChild(LitterPanel)
local LitterBoard = Instance.new("Frame", "Board")
LitterPanel:AddChild(LitterBoard)
local Bag = Instance.new("Frame", "Bag")
rawset(Bag, "Position", { X = { Scale = 0.6 }, Y = { Scale = 0.55 } })
rawset(Bag, "Size", { X = { Scale = 0.25 }, Y = { Scale = 0.3 } })
LitterBoard:AddChild(Bag)

function PLR:FindFirstChild(n)
    if n == "Backpack" then return Backpack end
    if n == "PlayerGui" then return PlayerGui end
    return nil
end

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
Services.UserInputService = { TouchEnabled = false, KeyboardEnabled = true, InputBegan = Signal.new(), GetLastInputType = function() return { Name = "Keyboard" } end, GetMouseLocation = function() return Vector3.new(0, 0, 0) end }
Services.HttpService = { JSONEncode = function(_, t) return "{}" end, JSONDecode = function(_, s) return {} end, GenerateGUID = function() return "g" end }
Services.TweenService = { Create = function() return { Play = function() end, Completed = { Once = function() end, Wait = function() end } } end, GetValue = function() return 0 end }
Services.Lighting = {}
Services.GuiService = { GetResolution = function() return Vector3.new(1920, 1080, 0) end, ErrorMessageChanged = Signal.new(), SelectedObject = nil }
Services.MarketplaceService = { GetProductInfo = function() return { Name = "7 Days Cat-Sitting" } end }
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

-- ===== load the script under test =====
print("script under test: " .. tostring(ScriptPath))

pump(0.2)
local PcallSwallows = 0
local rawpcall = pcall
G.pcall = function(fn, ...)
    local args = table.pack(...)
    local results = table.pack(xpcall(fn, function(e)
        return tostring(e) .. " @ " .. debug.traceback("", 2)
    end, table.unpack(args, 1, args.n)))
    if not results[1] then
        PcallSwallows = PcallSwallows + 1
        print("  [pcall-caught] " .. tostring(results[2]))
    end
    return table.unpack(results, 1, results.n)
end
local oldLoadstring = G.loadstring
G.loadstring = function(src, name)
    if src == "LIB" then return function() return Library end end
    if src == "THEME" then return function() return ThemeManager end end
    if src == "SAVE" then return function() return SaveManager end end
    return oldLoadstring(src, name)
end
local fn = G.loadstring(ScriptSrc, "=(CatSitting)")
G.task.spawn(fn)
pump(2.0)

local function noErrorNotify()
    for _, n in ipairs(MockState.Notifies) do
        if string.find(n, "ERROR", 1, true) then return false, n end
    end
    return true
end

local function countPrompt(pr)
    local n = 0
    for _, p in ipairs(PromptFires) do
        if p == pr then n = n + 1 end
    end
    return n
end

local function countRemote(name)
    local n = 0
    for _, f in ipairs(RemoteFires) do
        if f.remote == name then n = n + 1 end
    end
    return n
end

local function countInvoke(name)
    local n = 0
    for _, f in ipairs(RemoteInvokes) do
        if f.remote == name then n = n + 1 end
    end
    return n
end

local function remoteArgs(name, i)
    local seen = 0
    for _, f in ipairs(RemoteFires) do
        if f.remote == name then
            seen = seen + 1
            if seen == (i or 1) then
                return f.args
            end
        end
    end
    return nil
end

-- ===== load checks =====
check("script loaded without ERROR notify", (function()
    local ok, n = noErrorNotify()
    if not ok then print("  notify was: " .. tostring(n)) end
    return ok
end)())
check("guard set", G.ayasemiyatongekissazumirisa == true)
check("pcall interceptor: 0 silent swallows at load", PcallSwallows == 0)
check("8 toggles registered with plain ids", Library.Toggles.AutoChores ~= nil
    and Library.Toggles.AutoPet ~= nil
    and Library.Toggles.AutoAnomalies ~= nil
    and Library.Toggles.AutoPhoto ~= nil
    and Library.Toggles.AutoSleep ~= nil
    and Library.Toggles.AutoQueue ~= nil
    and Library.Toggles.AutoOpenCrate ~= nil)
check("no SafeLabel/stats labels in game section", (function()
    local lines = {}
    for line in string.gmatch(ScriptSrc, "[^\n]+") do
        table.insert(lines, line)
    end
    for i = 874, #lines - 18 do
        if string.find(lines[i], "SafeLabel", 1, true) then
            return false
        end
    end
    return true
end)())
check("SaveManager folder Yuri/CatSitting", SaveManager.Folder == "Yuri/CatSitting")

-- ===== AutoChores: full chore pass =====
do
    local hotMeal = Instance.new("Tool", "TVDinnerTool")
    hotMeal:SetAttribute("Meal", true)
    hotMeal:SetAttribute("Hot", true)
    Backpack:AddChild(hotMeal)
    local laserTool = Instance.new("Tool", "LaserTool")
    laserTool:SetAttribute("Laser", true)
    Backpack:AddChild(laserTool)

    Library.Toggles.AutoChores:SetValue(true)
    pump(40.0)

    check("Feed: can take prompt fired", countPrompt(P_CanTake) >= 1)
    check("Feed: fill bowl prompt fired", countPrompt(P_Fill) >= 1)
    check("Eat: TV dinner take prompt fired", countPrompt(P_DinnerTake) >= 1)
    check("Eat: cook prompt fired (put in)", countPrompt(P_Cook) >= 1)
    check("Eat: hot meal equipped", (function()
        for _, t in ipairs(EquippedLog) do
            if t == hotMeal then return true end
        end
        return false
    end)())
    check("Eat: Meal.Eat fired on wire", countRemote("Meal.Eat") >= 1)
    check("Mail: mailbox prompt fired", countPrompt(P_Mailbox) >= 1)
    check("Lock: deadbolt prompt fired (unlocked)", countPrompt(P_Lock) >= 1)
    check("Play: laser pointer take prompt fired", countPrompt(P_LaserTake) >= 1)
    check("Play: laser tool equipped", (function()
        for _, t in ipairs(EquippedLog) do
            if t == laserTool then return true end
        end
        return false
    end)())
    check("Play: Laser.Point fired with Vector3 + true", (function()
        local a = remoteArgs("Laser.Point")
        return a ~= nil and #a >= 1 and a[1] ~= nil and a[1].X ~= nil and a[2] == true
    end)())
    check("Play: laser stop (nil, false) fired", (function()
        local n = 0
        for _, f in ipairs(RemoteFires) do
            if f.remote == "Laser.Point" and f.args[1] == nil and f.args[2] == false then n = n + 1 end
        end
        return n >= 1
    end)())

    for _, name in ipairs({ "Feed", "Eat", "Mail", "Lock", "Play" }) do
        WS:SetAttribute("Chore_" .. name, true)
    end
    local can0, fill0, dinner0, cook0, mail0, lock0, laser0 = countPrompt(P_CanTake), countPrompt(P_Fill), countPrompt(P_DinnerTake), countPrompt(P_Cook), countPrompt(P_Mailbox), countPrompt(P_Lock), countPrompt(P_LaserTake)
    pump(35.0)
    check("Chores: completed chores skipped (no re-fire)", countPrompt(P_CanTake) == can0
        and countPrompt(P_Fill) == fill0
        and countPrompt(P_DinnerTake) == dinner0
        and countPrompt(P_Cook) == cook0
        and countPrompt(P_Mailbox) == mail0
        and countPrompt(P_Lock) == lock0
        and countPrompt(P_LaserTake) == laser0)
end

-- ===== Litter minigame session =====
do
    local before = #RemoteFires
    GrabTotalAtPhaseStart = (function()
        local n = 0
        for _, f in ipairs(RemoteFires) do
            if f.remote == "LitterCleaning.Event" and f.args[1] == "Grab" then n = n + 1 end
        end
        return n
    end)()
    WS:SetAttribute("Chore_Litter", false)
    pump(31.0)
    check("Litter: CleanLitterPrompt fired", countPrompt(P_CleanLitter) >= 1)
    check("Litter: Grab 1..5 sent on Start", (function()
        local grabs = {}
        for _, f in ipairs(RemoteFires) do
            if f.remote == "LitterCleaning.Event" and f.args[1] == "Grab" then
                grabs[f.args[3]] = true
            end
        end
        for i = 1, 5 do
            if not grabs[i] then return false end
        end
        return true
    end)())
    check("Litter: Drop coords inside bag area", (function()
        for _, f in ipairs(RemoteFires) do
            if f.remote == "LitterCleaning.Event" and f.args[1] == "Drop" then
                local x, y = f.args[4], f.args[5]
                if not (x and y and x >= 0.6 and x <= 0.85 and y >= 0.55 and y <= 0.85) then
                    return false
                end
            end
        end
        return true
    end)())
    check("Litter: drive stops after Win (exactly 5 grabs this session)", (function()
        local sessionGrabCount = 0
        for _, f in ipairs(RemoteFires) do
            if f.remote == "LitterCleaning.Event" and f.args[1] == "Grab" then
                sessionGrabCount = sessionGrabCount + 1
            end
        end
        local litterGrabsBeforeSession = GrabTotalAtPhaseStart or 0
        return sessionGrabCount - litterGrabsBeforeSession == 5
    end)())
    WS:SetAttribute("Chore_Litter", true)
    local grabTotal2 = (function()
        local n = 0
        for _, f in ipairs(RemoteFires) do
            if f.remote == "LitterCleaning.Event" and f.args[1] == "Grab" then n = n + 1 end
        end
        return n
    end)()
    pump(35.0)
    check("Litter: no new session when chore done", (function()
        local n = 0
        for _, f in ipairs(RemoteFires) do
            if f.remote == "LitterCleaning.Event" and f.args[1] == "Grab" then n = n + 1 end
        end
        return n == grabTotal2
    end)())
    _ = before
end

-- ===== AutoPet =====
do
    HRP:SetCFrame(CFrame.new(Vector3.new(4, 3, 4)))
    Library.Toggles.AutoPet:SetValue(true)
    pump(1.5)
    check("AutoPet: Pet fired when cat within 40 studs", countRemote("Cat.Pet") >= 1)
    Library.Toggles.AutoPet:SetValue(false)
    pump(0.5)
    local petCount = countRemote("Cat.Pet")
    pump(2.0)
    check("AutoPet: stops when toggled off", countRemote("Cat.Pet") == petCount)
    HRP:SetCFrame(CFrame.new(Vector3.new(500, 3, 500)))
    Library.Toggles.AutoPet:SetValue(true)
    pump(1.5)
    check("AutoPet: no fire when cat out of range", countRemote("Cat.Pet") == petCount)
    Library.Toggles.AutoPet:SetValue(false)
    HRP:SetCFrame(CFrame.new(Vector3.new(0, 3, 0)))
end

-- ===== AutoAnomalies: attribute-transition responders =====
do
    Library.Toggles.AutoAnomalies:SetValue(true)
    pump(0.5)
    WS:SetAttribute("Grandma", true)
    pump(1.0)
    check("Grandma: exactly 4 light prompts fired (On==true only)", (function()
        local n = 0
        for name, pr in pairs(SwitchPrompts) do
            n = n + countPrompt(pr)
        end
        return n == 4
    end)())
    WS:SetAttribute("Grandma", false)

    WS:SetAttribute("VoidOutside", true)
    pump(1.0)
    check("VoidOutside: exactly 5 blinds prompts fired (open only)", (function()
        local n = 0
        for _, pr in pairs(BlindsPrompts) do
            n = n + countPrompt(pr)
        end
        return n == 5
    end)())
    WS:SetAttribute("VoidOutside", false)

    local tv0 = countPrompt(P_TV)
    WS:SetAttribute("Catzilla", true)
    pump(1.0)
    check("Catzilla: TV prompt fired once (On~=true)", countPrompt(P_TV) - tv0 == 1)
    WS:SetAttribute("Catzilla", false)

    local flush0 = countPrompt(P_Flush)
    WS:SetAttribute("ToiletFace", true)
    pump(1.0)
    check("ToiletFace: flush prompt fired", countPrompt(P_Flush) - flush0 >= 1)
    WS:SetAttribute("ToiletFace", false)

    WS:SetAttribute("CreepyHead", true)
    pump(2.0)
    check("CreepyHead: Cat.Stare fired at game cadence", countRemote("Cat.Stare") >= 3)
    local stare0 = countRemote("Cat.Stare")
    WS:SetAttribute("CreepyHead", false)
    pump(1.5)
    check("CreepyHead: stare stops when head clears", countRemote("Cat.Stare") == stare0)
    Library.Toggles.AutoAnomalies:SetValue(false)
end

-- ===== AutoPhoto: SmilingMan + Misplaced =====
do
    Library.Toggles.AutoPhoto:SetValue(true)
    pump(0.5)
    local SmilingMan = Instance.new("Model", "SmilingMan")
    WS:AddChild(SmilingMan)
    local smPart = Instance.new("Part", "SmilingManPart")
    smPart:SetCFrame(CFrame.new(Vector3.new(20, 2, 20)))
    SmilingMan:AddChild(smPart)
    SmilingMan.PrimaryPart = smPart
    WS:SetAttribute("SmilingMan", true)
    pump(2.0)
    check("SmilingMan: Phone.Photo fired with (CFrame, part)", (function()
        local a = remoteArgs("Phone.Photo")
        return a ~= nil and #a >= 2 and a[1] ~= nil and a[1].Position ~= nil and a[2] == smPart
    end)())
    check("SmilingMan: photo eye ~12 studs from target", (function()
        local a = remoteArgs("Phone.Photo")
        local d = (a[1].Position - smPart.Position).Magnitude
        return d > 8 and d < 16
    end)())
    WS:SetAttribute("SmilingMan", false)
    local photo0 = countRemote("Phone.Photo")
    pump(1.5)
    check("SmilingMan: photo loop stops when flag clears", countRemote("Phone.Photo") == photo0)
    SmilingMan:Destroy()

    local photoSweep0 = countRemote("Phone.Photo")
    WS:SetAttribute("Misplaced", true)
    pump(1.5)
    check("Misplaced: furniture sweep fired photos", countRemote("Phone.Photo") > photoSweep0)
    WS:SetAttribute("Misplaced", false)
    pump(1.0)
    local afterClear = countRemote("Phone.Photo")
    pump(12.0)
    check("Misplaced: sweep stops when flag clears", countRemote("Phone.Photo") == afterClear)
    Library.Toggles.AutoPhoto:SetValue(false)
end

-- ===== AutoSleep =====
do
    WS:SetAttribute("Chore_Eat", false)
    Library.Toggles.AutoSleep:SetValue(true)
    pump(11.0)
    check("AutoSleep: no sleep while chores pending", countPrompt(P_Sleep) == 0)
    WS:SetAttribute("Chore_Eat", true)
    WS:SetAttribute("Grandma", true)
    pump(11.0)
    check("AutoSleep: no sleep while anomaly active", countPrompt(P_Sleep) == 0)
    WS:SetAttribute("Grandma", false)
    FridgeDoor:SetAttribute("Open", true)
    pump(11.0)
    check("AutoSleep: fridge closed before sleep", countPrompt(P_FridgeDoor) >= 1)
    check("AutoSleep: sleep prompt fired when ready", countPrompt(P_Sleep) >= 1)
    Library.Toggles.AutoSleep:SetValue(false)
end

-- ===== AutoQueue + AutoOpenCrate (lobby world) =====
do
    local Lobby = Instance.new("Folder", "Lobby")
    WS:AddChild(Lobby)
    local LImportant = Instance.new("Folder", "Important")
    Lobby:AddChild(LImportant)
    local Pod = Instance.new("Model", "TeleportPod")
    LImportant:AddChild(Pod)
    local Zone = Instance.new("Part", "Zone")
    Zone:SetCFrame(CFrame.new(Vector3.new(30, 1, 30)))
    Pod:AddChild(Zone)

    Library.Toggles.AutoQueue:SetValue(true)
    pump(4.0)
    check("AutoQueue: TP to TeleportPod zone", (HRP.Position - Zone.Position).Magnitude < 5)
    check("AutoQueue: FireTI on zone", (function()
        for _, t in ipairs(TouchFires) do
            if t.part == Zone then return true end
        end
        return false
    end)())
    Library.Toggles.AutoQueue:SetValue(false)

    Library.Toggles.AutoOpenCrate:SetValue(true)
    pump(8.0)
    check("AutoOpenCrate: opens until cash < 10 (25 -> 2 opens)", countInvoke("Shop.OpenCrate") == 2)
    check("AutoOpenCrate: GetState consulted", countInvoke("Shop.GetState") >= 1)
    pump(6.0)
    check("AutoOpenCrate: stops when cash exhausted", countInvoke("Shop.OpenCrate") == 2)
    Library.Toggles.AutoOpenCrate:SetValue(false)
    Lobby:Destroy()
end

-- ===== toggle-off chore stop + litter cancel =====
do
    WS:SetAttribute("Chore_Litter", false)
    Library.Toggles.AutoChores:SetValue(true)
    pump(31.0)
    check("Litter session opened on retry pass", (function()
        for _, f in ipairs(RemoteFires) do
            if f.remote == "LitterCleaning.Event" and f.args[1] == "Grab" then return true end
        end
        return false
    end)())
    R_Litter.OnClientEvent._serverFire("Start", "sid-manual")
    pump(0.5)
    Library.Toggles.AutoChores:SetValue(false)
    pump(0.5)
    check("AutoChores off: Cancel sent for open litter session", (function()
        for _, f in ipairs(RemoteFires) do
            if f.remote == "LitterCleaning.Event" and f.args[1] == "Cancel" then return true end
        end
        return false
    end)())
    local can0 = countPrompt(P_CanTake)
    pump(31.0)
    WS:SetAttribute("Chore_Litter", true)
    check("AutoChores: loops stop when toggled off", countPrompt(P_CanTake) == can0)
end

-- ===== banned-wire sweep =====
check("banned-wire sweep: no Phone.Reply fires", countRemote("Phone.Reply") == 0)
check("banned-wire sweep: no Tutorial.Skip fires", countRemote("Tutorial.Skip") == 0)
check("banned-wire sweep: no Ending.* fires", countRemote("Ending.Lobby") == 0 and countRemote("Ending.Vote") == 0)
check("banned-wire sweep: no Shop.Buy/Equip invokes", countInvoke("Shop.Buy") == 0 and countInvoke("Shop.Equip") == 0)
check("banned-wire sweep: no Endings.Get invokes", countInvoke("Endings.Get") == 0)

check("pcall interceptor: 0 silent swallows total", PcallSwallows == 0)

summary()
