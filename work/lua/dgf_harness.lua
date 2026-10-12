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
                for _, c in ipairs(rawget(t, "_children")) do
                    if c.Name == k then
                        return c
                    end
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
    function Library:SetNotifySide(n) end
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
            local rawSetValue = el.SetValue
            function el:SetValue(v)
                rawSetValue(self, v)
                if info.Callback then
                    info.Callback(v)
                end
            end
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

-- ===================== DGF1 game layer =====================
local ScriptPath = arg and arg[1] or nil
local ScriptSrc = nil
do
    local fallbacks = {
        (os.getenv("SF_DIR") or "/tmp/SavedFolder") .. "/work/lua/DontGetFired.lua",
        "/home/z/my-project/Yuri/DontGetFired/DontGetFired.lua",
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

G.math.round = function(x)
    return (x >= 0) and math.floor(x + 0.5) or math.ceil(x - 0.5)
end

G.os = setmetatable({ clock = function() return Sched.now end, date = function() return "00:00:00" end, time = function() return 0 end }, { __index = os })

do
    local vmt = getmetatable(Vector3.new(0, 0, 0))
    vmt.__div = function(a, b)
        if type(b) == "number" then
            return Vector3.new(a.X / b, a.Y / b, a.Z / b)
        end
        return Vector3.new(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
    end
    vmt.__index = function(t, k)
        if k == "Unit" then
            local m = t.Magnitude
            if m == 0 then
                return Vector3.new(0, 0, 0)
            end
            return Vector3.new(t.X / m, t.Y / m, t.Z / m)
        end
        if k == "Lerp" then
            return function(self, other, alpha)
                return Vector3.new(self.X + (other.X - self.X) * alpha, self.Y + (other.Y - self.Y) * alpha, self.Z + (other.Z - self.Z) * alpha)
            end
        end
        return nil
    end
    local cmt = getmetatable(CFrame.new(Vector3.new(0, 0, 0)))
    cmt.__index = function(t, k)
        if k == "LookVector" then
            return Vector3.new(0, 0, -1)
        end
        return nil
    end
end

G.Random = { new = function(seed)
    local s = (tonumber(seed) or 1) % 2147483647
    if s <= 0 then
        s = s + 2147483646
    end
    local function nextU()
        s = (s * 16807) % 2147483647
        return s / 2147483647
    end
    return {
        NextNumber = function(_, a, b)
            return a + nextU() * (b - a)
        end,
        NextInteger = function(_, a, b)
            return a + math.floor(nextU() * (b - a + 1))
        end,
    }
end }

local VFS = {}
local function vfsPath(path)
    return string.match(path, "^(.*)/([^/]+)$")
end
G.isfolder = function(path)
    return VFS[path] ~= nil
end
G.listfiles = function(path)
    local out = {}
    local folder = VFS[path]
    if folder then
        for name in pairs(folder) do
            out[#out + 1] = path .. "/" .. name
        end
    end
    table.sort(out)
    return out
end
G.makefolder = function(path)
    VFS[path] = VFS[path] or {}
end
G.writefile = function(path, content)
    local dir, name = vfsPath(path)
    if dir then
        VFS[dir] = VFS[dir] or {}
        VFS[dir][name] = content
    end
end
G.readfile = function(path)
    local dir, name = vfsPath(path)
    return dir and VFS[dir] and VFS[dir][name] or nil
end
G.isfile = function(path)
    local dir, name = vfsPath(path)
    return dir ~= nil and VFS[dir] ~= nil and VFS[dir][name] ~= nil
end
G.delfile = function() end
local NotyuriLog = {}
G.appendfile = function(_, line)
    table.insert(NotyuriLog, line)
end

local PcallSwallows = 0
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

local ModuleRegistry = {}
G.require = function(obj)
    if ModuleRegistry[obj] ~= nil then
        return ModuleRegistry[obj]
    end
    error("mock require: unregistered module " .. tostring(obj and obj.Name))
end
local function addModule(parent, name, srcOrTbl)
    local m = Instance.new("ModuleScript", name)
    parent:AddChild(m)
    if type(srcOrTbl) == "string" then
        local fn = G.loadstring(srcOrTbl, "@DGF:" .. name)
        G.script = m
        local ok, result = pcall(fn)
        G.script = nil
        if not ok then
            error("real module " .. name .. " failed to load: " .. tostring(result))
        end
        ModuleRegistry[m] = result
    else
        ModuleRegistry[m] = srcOrTbl
    end
    return m
end

local PLR = Instance.new("Player", "czhigh")
PLR.UserId = 1
PLR.Idled = Signal.new()
PLR.CameraMaxZoomDistance = 128
local Char = Instance.new("Model", "czhigh")
local HRP = Instance.new("Part", "HumanoidRootPart")
HRP:SetCFrame(CFrame.new(Vector3.new(0, 3, 0)))
Char:AddChild(HRP)
local Head = Instance.new("Part", "Head")
Head:SetCFrame(CFrame.new(Vector3.new(0, 5, 0)))
Char:AddChild(Head)
local Hum = Instance.new("Humanoid", "Humanoid")
Char:AddChild(Hum)
local Backpack = Instance.new("Backpack", "Backpack")
Hum.EquipTool = function(_, tool)
    for i = #Char._children, 1, -1 do
        local c = Char._children[i]
        if c ~= tool and c.ClassName == "Tool" then
            table.remove(Char._children, i)
            Backpack:AddChild(c)
        end
    end
    local old = tool.Parent
    if old then
        for i, c in ipairs(old._children) do
            if c == tool then
                table.remove(old._children, i)
                break
            end
        end
    end
    Char:AddChild(tool)
    tool.Parent = Char
end
PLR.Character = Char
PLR:AddChild(Backpack)
local PaperTool = Instance.new("Tool", "MeetingPaper")
PaperTool:SetAttribute("MeetingPaper", true)
Backpack:AddChild(PaperTool)
local SquishyTool = Instance.new("Tool", "ButterSquishy")
SquishyTool:SetAttribute("MeetingRelaxItem", "ButterSquishy")
Backpack:AddChild(SquishyTool)

local function mkPlayer(name, userId, team, seat, dist)
    local p = Instance.new("Player", name)
    p.UserId = userId
    local c = Instance.new("Model", name)
    local h = Instance.new("Part", "Head")
    h:SetCFrame(CFrame.new(Vector3.new(0, 5, -dist)))
    c:AddChild(h)
    local r = Instance.new("Part", "HumanoidRootPart")
    r:SetCFrame(CFrame.new(Vector3.new(0, 3, -dist)))
    c:AddChild(r)
    p.Character = c
    if seat then
        p:SetAttribute("SeatName", seat)
    end
    if team then
        p:SetAttribute("WarTeam", team)
    end
    p:SetAttribute("MeetingJoined", true)
    return p
end

local PlayerList = { PLR }
local AllyRed = mkPlayer("allyred", 2, "Red", "A1", 12)
local EnemyBlue = mkPlayer("enemyblue", 3, "Blue", "B2", 20)
local EnemyRedFar = mkPlayer("enemyredfar", 4, "Red", "C3", 50)
local NoSeat = mkPlayer("noseat", 5, "Red", nil, 8)
for _, p in ipairs({ AllyRed, EnemyBlue, EnemyRedFar, NoSeat }) do
    table.insert(PlayerList, p)
end

local Services = {}
Services.Players = { LocalPlayer = PLR, GetPlayers = function() return PlayerList end }
local RS = Instance.new("Folder", "ReplicatedStorage")
Services.ReplicatedStorage = RS
Services.RunService = {
    Stepped = Signal.new(), RenderStepped = Signal.new(), Heartbeat = Signal.new(),
    PostSimulation = Signal.new(),
    IsServer = function() return false end, IsStudio = function() return false end,
    IsClient = function() return true end,
}
Services.TeleportService = { Teleport = function() end, TeleportToPlaceInstance = function() end }
Services.UserInputService = { TouchEnabled = false, KeyboardEnabled = true, InputBegan = Signal.new() }
Services.HttpService = {
    JSONEncode = function(_, t) return jsonEncode(t) end,
    JSONDecode = function(_, s) return jsonDecode(s) end,
    GenerateGUID = function() return "g" end,
}
Services.TweenService = { Create = function() return { Play = function() end } end, GetValue = function() return 0 end }
Services.Lighting = {}
Services.GuiService = { GetResolution = function() return Vector3.new(1920, 1080, 0) end, ErrorMessageChanged = Signal.new() }
Services.MarketplaceService = { GetProductInfo = function() return { Name = "Don't Get Fired At Work!" } end }
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

local WS = Instance.new("Folder", "Workspace")
G.workspace = WS
WS.GetServerTimeNow = function()
    return Sched.now
end
G.Enum = setmetatable({}, { __index = function(t, k)
    local c = setmetatable({}, { __index = function(_, k2) return k2 end })
    rawset(t, k, c)
    return c
end })
G.getconnections = nil
G.getgenv = function() return G end

local Meeting = Instance.new("Folder", "Meeting")
RS:AddChild(Meeting)
local RemotesFolder = Instance.new("Folder", "Remotes")
Meeting:AddChild(RemotesFolder)
local function mkRE(name)
    local r = Instance.new("RemoteEvent", name)
    RemotesFolder:AddChild(r)
    r.OnClientEvent = Signal.new()
    return r
end
local StateUpdatedRE = mkRE("StateUpdated")
local SubmitEmailRE = mkRE("SubmitEmail")
local SetLaptopViewRE = mkRE("SetLaptopView")
local JoinMeetingRE = mkRE("JoinMeeting")
local DismissScamRE = mkRE("DismissScam")
local SmackLaptopRE = mkRE("SmackLaptop")
local InterruptActionRE = mkRE("InterruptAction")
local UseRelaxItemRE = mkRE("UseRelaxItem")
local ThrowPaperRE = mkRE("ThrowPaper")
local OfficeEventRE = mkRE("OfficeEvent")
local OfficeEventActionRE = mkRE("OfficeEventAction")
local BossQuizRE = mkRE("BossQuiz")
local BossQuizAnswerRE = mkRE("BossQuizAnswer")
local HackActionRE = mkRE("HackAction")
local HackUpdateRE = mkRE("HackUpdate")
local BuyUpgradeRE = mkRE("BuyUpgrade")
local ClaimPlaytimeRE = mkRE("ClaimPlaytime")
local AlienActionRE = mkRE("AlienAction")
local HwActionRE = mkRE("HwAction")
local VerityActionRE = mkRE("VerityAction")
local VerityCueRE = mkRE("VerityCue")
local LaptopFightActionRE = mkRE("LaptopFightAction")
local LaptopFightCueRE = mkRE("LaptopFightCue")
local GetStateRF = Instance.new("RemoteFunction", "GetState")
RemotesFolder:AddChild(GetStateRF)

local CareerSrc = io.open("dgf_real/CareerConfig.lua", "r"):read("*a")
local AlienSrc = io.open("dgf_real/AlienConfig.lua", "r"):read("*a")
local HackRhythmSrc = io.open("dgf_real/HackRhythm.lua", "r"):read("*a")
local HwSrc = io.open("dgf_real/HalloweenConfig.lua", "r"):read("*a")
local LaptopSrc = io.open("dgf_real/LaptopFightConfig.lua", "r"):read("*a")
local VeritySrc = io.open("dgf_real/VerityConfig.lua", "r"):read("*a")
local VerityPathSrc = io.open("dgf_real/VerityPath.lua", "r"):read("*a")
local CareerMod = addModule(Meeting, "CareerConfig", CareerSrc)
local AlienMod = addModule(Meeting, "AlienConfig", AlienSrc)
local HackRhythmMod = addModule(Meeting, "HackRhythm", HackRhythmSrc)
local HwMod = addModule(Meeting, "HalloweenConfig", HwSrc)
local LaptopMod = addModule(Meeting, "LaptopFightConfig", LaptopSrc)
local VerityMod = addModule(Meeting, "VerityConfig", VeritySrc)
local VerityPathMod = addModule(Meeting, "VerityPath", VerityPathSrc)
local CareerConfig = ModuleRegistry[CareerMod]
local AlienConfig = ModuleRegistry[AlienMod]
local HackRhythm = ModuleRegistry[HackRhythmMod]
local LaptopFightConfig = ModuleRegistry[LaptopMod]
local VerityPath = ModuleRegistry[VerityPathMod]
check("real CareerConfig loaded", type(CareerConfig) == "table" and #CareerConfig.Playtime == 5 and CareerConfig.PaperUpgrades[1].Price == 300)
check("real AlienConfig loaded", type(AlienConfig) == "table" and AlienConfig.FireInterval == 0.085 and AlienConfig.DodgeSeconds == 2.4)
check("real HackRhythm loaded + chart gen", (function()
    local c = HackRhythm.Chart(G.Random.new(7), 1)
    return type(c) == "table" and #c.notes >= 3 and c.notes[1].d ~= nil and c.perfect == 0.09
end)())
check("real VerityPath loaded", type(VerityPath) == "table" and type(VerityPath.new) == "function")

local Boss = Instance.new("Model", "Boss")
local BossPart = Instance.new("Part", "HumanoidRootPart")
BossPart:SetCFrame(CFrame.new(Vector3.new(30, 3, 0)))
Boss:AddChild(BossPart)
WS:AddChild(Boss)

local RedDummy = Instance.new("Model", "DummyRed")
local RedDummyHead = Instance.new("Part", "Head")
RedDummyHead:SetCFrame(CFrame.new(Vector3.new(0, 5, -10)))
RedDummy:AddChild(RedDummyHead)
RedDummy:SetAttribute("MeetingDummy", true)
RedDummy:SetAttribute("WarTeam", "Red")
WS:AddChild(RedDummy)
local BlueDummy = Instance.new("Model", "DummyBlue")
local BlueDummyHead = Instance.new("Part", "Head")
BlueDummyHead:SetCFrame(CFrame.new(Vector3.new(0, 5, -6)))
BlueDummy:AddChild(BlueDummyHead)
BlueDummy:SetAttribute("MeetingDummy", true)
BlueDummy:SetAttribute("WarTeam", "Blue")
WS:AddChild(BlueDummy)

local LFDummies = Instance.new("Folder", "LaptopFightDummies")
WS:AddChild(LFDummies)
local function mkLFDummy(name, x, y, z, dist)
    local m = Instance.new("Model", name)
    local r = Instance.new("Part", "HumanoidRootPart")
    r:SetCFrame(CFrame.new(Vector3.new(x, y, z)))
    m:AddChild(r)
    if dist then
        m:SetAttribute("Dist", dist)
    end
    LFDummies:AddChild(m)
    return m
end

local WireLog = {}
local function logWire(remote, kind, args)
    table.insert(WireLog, { remote = remote, kind = kind, args = args, t = Sched.now })
end
local function wiresFor(remote, pred)
    local out = {}
    for _, w in ipairs(WireLog) do
        if w.remote == remote and (not pred or pred(w)) then
            out[#out + 1] = w
        end
    end
    return out
end

local Emails = {
    { Token = "t1", Kind = "Normal", From = "Karen", Subject = "Monthly report", Text = "Hi! Please APPROVE the monthly report. Thanks!" },
    { Token = "t2", Kind = "Normal", From = "FREE PRIZES", Subject = "YOU WON", Text = "CONGRATS!!! Click APPROVE to claim it NOW!!!", IsScam = true },
    { Token = "t3", Kind = "Normal", From = "Dave", Subject = "Printer", Text = "The printer is broken again. Please forward this to IT." },
    { Token = "t4", Kind = "WRITE", From = "The Boss", Subject = "Meeting notes", Text = "Reply to this email and tell me you're on it!" },
    { Token = "t5", Kind = "Normal", From = "Maria", Subject = "Informe", Text = "Por favor apruebe el informe mensual." },
    { Token = "t6", Kind = "Normal", From = "Sam", Subject = "Lunch", Text = "Lunch at the usual place tomorrow?" },
}
local function serverAnswer(E)
    if E.IsScam then
        return "DELETE"
    end
    if E.Kind == "WRITE" then
        return "WRITE"
    end
    for Word in string.gmatch(string.lower(E.Text or ""), "[%a\128-\255]+") do
        if Word:sub(1, 6) == "approv" or Word:sub(1, 5) == "aprob" or Word:sub(1, 6) == "aprueb" or Word:sub(1, 4) == "apru" then
            return "APPROVE"
        end
        if Word:sub(1, 7) == "forward" or Word:sub(1, 5) == "reenv" then
            return "FORWARD"
        end
    end
    return nil
end

local State = {
    Ready = true,
    LaptopView = false,
    Email = nil,
    Recovering = false,
    LaptopBroken = false,
    SmacksLeft = 0,
    Pressure = 0,
    ScamAds = {},
    Interrupt = nil,
    AnswerResult = nil,
    WorkProgress = 0,
}
local function pushState()
    StateUpdatedRE.OnClientEvent:Fire(State)
end

GetStateRF.InvokeServer = function()
    logWire(GetStateRF, "invoke", {})
    return State
end
JoinMeetingRE.FireServer = function()
    logWire(JoinMeetingRE, "fire", {})
    PLR:SetAttribute("MeetingJoined", true)
end
SetLaptopViewRE.FireServer = function(_, on)
    logWire(SetLaptopViewRE, "fire", { on })
    State.LaptopView = on and true or false
end
SubmitEmailRE.FireServer = function(_, token, choice)
    logWire(SubmitEmailRE, "fire", { token, choice })
    local E = nil
    for _, e in ipairs(Emails) do
        if e.Token == token then
            E = e
            break
        end
    end
    if E then
        local right = serverAnswer(E)
        State.AnswerResult = { Id = (State.AnswerResult and State.AnswerResult.Id or 0) + 1, Correct = choice == right, Right = right, Choice = choice }
    end
end
DismissScamRE.FireServer = function(_, id)
    logWire(DismissScamRE, "fire", { id })
    local out = {}
    for _, ad in ipairs(State.ScamAds) do
        if ad.Id ~= id then
            table.insert(out, ad)
        end
    end
    State.ScamAds = out
end
SmackLaptopRE.FireServer = function()
    logWire(SmackLaptopRE, "fire", {})
    if State.LaptopBroken and State.SmacksLeft > 0 then
        State.SmacksLeft = State.SmacksLeft - 1
        if State.SmacksLeft == 0 then
            State.LaptopBroken = false
        end
    end
end
InterruptActionRE.FireServer = function(_, id, act)
    logWire(InterruptActionRE, "fire", { id, act })
    if act == "decline" or act == "done" then
        State.Interrupt = nil
    end
end
UseRelaxItemRE.FireServer = function(_, tool)
    logWire(UseRelaxItemRE, "fire", { tool })
    State.Pressure = math.max(0, (State.Pressure or 0) - 8)
end
ThrowPaperRE.FireServer = function(_, target)
    logWire(ThrowPaperRE, "fire", { target })
end
OfficeEventActionRE.FireServer = function(_, kind, id)
    logWire(OfficeEventActionRE, "fire", { kind, id })
end
BossQuizAnswerRE.FireServer = function(_, id, idx)
    logWire(BossQuizAnswerRE, "fire", { id, idx })
end
HackActionRE.FireServer = function(_, ...)
    logWire(HackActionRE, "fire", { ... })
end
BuyUpgradeRE.FireServer = function(_, kind)
    logWire(BuyUpgradeRE, "fire", { kind })
    local bobux = PLR:GetAttribute("Bobux") or 0
    if kind == "Paper" then
        PLR:SetAttribute("PaperLevel", (PLR:GetAttribute("PaperLevel") or 0) + 1)
        PLR:SetAttribute("Bobux", bobux - CareerConfig.PaperUpgrades[(PLR:GetAttribute("PaperLevel") or 1)].Price)
    elseif kind == "Phone" then
        PLR:SetAttribute("PhoneLevel", (PLR:GetAttribute("PhoneLevel") or 0) + 1)
        PLR:SetAttribute("Bobux", bobux - CareerConfig.PhoneUpgrades[(PLR:GetAttribute("PhoneLevel") or 1)].Price)
    end
end
ClaimPlaytimeRE.FireServer = function(_, idx)
    logWire(ClaimPlaytimeRE, "fire", { idx })
    PLR:SetAttribute("PlaytimeClaimed", (PLR:GetAttribute("PlaytimeClaimed") or 0) + 2 ^ (idx - 1))
end
AlienActionRE.FireServer = function(_, act)
    logWire(AlienActionRE, "fire", { act })
end
HwActionRE.FireServer = function(_, act)
    logWire(HwActionRE, "fire", { act })
end
VerityActionRE.FireServer = function(_, kind, origin, dir)
    logWire(VerityActionRE, "fire", { kind, origin, dir })
end
LaptopFightActionRE.FireServer = function(_, kind, hits)
    logWire(LaptopFightActionRE, "fire", { kind, hits })
end

local oldLoadstring = G.loadstring
G.loadstring = function(src2, name)
    if src2 == "LIB" then return function() return Library end end
    if src2 == "THEME" then return function() return ThemeManager end end
    if src2 == "SAVE" then return function() return SaveManager end end
    return oldLoadstring(src2, name)
end

do
    local fn = G.loadstring(ScriptSrc, "=(DontGetFired)")
    G.task.spawn(fn)
    pump(0.5)
end

check("real load: no ERROR notify", (function()
    for _, n in ipairs(MockState.Notifies) do
        if string.find(n, "ERROR", 1, true) then
            return false
        end
    end
    return true
end)())
for _, id in ipairs({ "AutoJoin", "AutoWork", "AutoSmack", "AutoAds", "AutoInterrupt", "AutoEvents", "AutoQuiz", "AutoHack", "AutoPaper", "AutoRelax", "AutoClaim", "AutoUpgrade", "AutoAlien", "AutoHalloween", "AutoVerity", "AutoLaptopFight" }) do
    check("toggle registered: " .. id, Library.Toggles[id] ~= nil)
end
check("slider registered: RelaxAt", Library.Options.RelaxAt ~= nil and Library.Options.RelaxAt.Value == 60)
check("SaveManager folder", SaveManager.Folder == "Yuri/DontGetFired")
check("GetState invoked at load", #wiresFor(GetStateRF) >= 1)

-- ===== AutoJoin =====
do
    local t0 = Sched.now
    Meeting:SetAttribute("RoundPhase", "Countdown")
    Meeting:SetAttribute("CountdownEndsAt", Sched.now + 20)
    Library.Toggles.AutoJoin:SetValue(true)
    pump(3)
    local ws = wiresFor(JoinMeetingRE, function(w) return w.t >= t0 end)
    check("AutoJoin fires JoinMeeting in Countdown", #ws >= 1)
    check("AutoJoin stops once joined", (function()
        pump(3)
        return #wiresFor(JoinMeetingRE, function(w) return w.t >= t0 end) == #ws
    end)())
    Library.Toggles.AutoJoin:SetValue(false)
    pump(0.5)
end

-- ===== AutoWork =====
do
    PLR:SetAttribute("MeetingJoined", true)
    Library.Toggles.AutoWork:SetValue(true)
    local results = { t1 = "APPROVE", t2 = "DELETE", t3 = "FORWARD", t4 = "WRITE", t5 = "APPROVE" }
    for _, E in ipairs(Emails) do
        State.Email = E
        State.LaptopView = false
        State.Ready = true
        local t0 = Sched.now
        pump(1.6)
        local ws = wiresFor(SubmitEmailRE, function(w) return w.t >= t0 end)
        local expect = results[E.Token]
        if expect then
            check("AutoWork " .. E.Token .. " -> " .. expect, #ws >= 1 and ws[#ws].args[1] == E.Token and ws[#ws].args[2] == expect)
        else
            check("AutoWork " .. E.Token .. " unrecognized -> skipped", #ws == 0)
        end
    end
    check("AutoWork opens laptop view before submitting", (function()
        local opened = false
        for _, w in ipairs(WireLog) do
            if w.remote == SetLaptopViewRE and w.t < (wiresFor(SubmitEmailRE)[1] and wiresFor(SubmitEmailRE)[1].t or math.huge) then
                opened = true
            end
        end
        return opened
    end)())
    check("AutoWork unrecognized notify shown", (function()
        for _, n in ipairs(MockState.Notifies) do
            if string.find(n, "Unrecognized email", 1, true) then
                return true
            end
        end
        return false
    end)())
    check("AutoWork closes view when inbox empty", (function()
        State.Email = nil
        pump(1.5)
        local closed = false
        for _, w in ipairs(wiresFor(SetLaptopViewRE)) do
            if w.args[1] == false then
                closed = true
            end
        end
        return closed
    end)())
    check("AutoWork 0.8s submit rate", (function()
        local ws = wiresFor(SubmitEmailRE)
        if #ws < 2 then
            return false
        end
        local last = nil
        for _, w in ipairs(ws) do
            if last and w.t - last < 0.79 then
                return false
            end
            last = w.t
        end
        return true
    end)())
    check("AutoWork wrong answer notify", (function()
        State.Email = Emails[1]
        State.AnswerResult = { Id = 99, Correct = false, Right = "APPROVE" }
        pump(0.6)
        for _, n in ipairs(MockState.Notifies) do
            if string.find(n, "expected APPROVE", 1, true) then
                return true
            end
        end
        return false
    end)())
    check("AutoWork blocked during LaptopFight event", (function()
        State.Email = Emails[1]
        Meeting:SetAttribute("OfficeEvent", "LaptopFight")
        local t0 = Sched.now
        pump(1.2)
        Meeting:SetAttribute("OfficeEvent", nil)
        return #wiresFor(SubmitEmailRE, function(w) return w.t >= t0 end) == 0
    end)())
    Library.Toggles.AutoWork:SetValue(false)
    pump(0.5)
end

-- ===== AutoSmack =====
do
    Library.Toggles.AutoSmack:SetValue(true)
    State.LaptopBroken = true
    State.SmacksLeft = 3
    pump(1.5)
    check("AutoSmack fires until SmacksLeft=0", #wiresFor(SmackLaptopRE) == 3)
    check("AutoSmack clears LaptopBroken at 0", State.LaptopBroken == false and State.SmacksLeft == 0)
    check("AutoSmack rate >= 0.25s", (function()
        local ws = wiresFor(SmackLaptopRE)
        local last = nil
        for _, w in ipairs(ws) do
            if last and w.t - last < 0.24 then
                return false
            end
            last = w.t
        end
        return true
    end)())
    Library.Toggles.AutoSmack:SetValue(false)
    pump(0.3)
    State.LaptopBroken = true
    State.SmacksLeft = 5
    pump(0.5)
    check("AutoSmack stops after toggle off", #wiresFor(SmackLaptopRE) == 3)
    State.LaptopBroken = false
    State.SmacksLeft = 0
end

-- ===== AutoAds =====
do
    Library.Toggles.AutoAds:SetValue(true)
    State.ScamAds = { { Id = "ad1" }, { Id = "ad2" }, { Id = "ad1" } }
    pump(1.5)
    local a1 = #wiresFor(DismissScamRE, function(w) return w.args[1] == "ad1" end)
    local a2 = #wiresFor(DismissScamRE, function(w) return w.args[1] == "ad2" end)
    check("AutoAds dismisses each ad id once", a1 == 1 and a2 == 1)
    Library.Toggles.AutoAds:SetValue(false)
    pump(0.3)
end

-- ===== AutoInterrupt =====
do
    Library.Toggles.AutoInterrupt:SetValue(true)
    State.Interrupt = { Id = "call1", Kind = "Call" }
    pump(0.6)
    local declines = wiresFor(InterruptActionRE, function(w) return w.args[2] == "decline" end)
    check("AutoInterrupt declines Call once", #declines == 1 and declines[1].args[1] == "call1")
    State.Interrupt = { Id = "upd1", Kind = "Update" }
    pump(1.0)
    local clicks = wiresFor(InterruptActionRE, function(w) return w.args[2] == "click" and w.args[1] == "upd1" end)
    check("AutoInterrupt spams Update clicks", #clicks >= 5)
    check("AutoInterrupt no decline on Update", #wiresFor(InterruptActionRE, function(w) return w.args[2] == "decline" and w.args[1] == "upd1" end) == 0)
    State.Interrupt = nil
    Library.Toggles.AutoInterrupt:SetValue(false)
    pump(0.3)
end

-- ===== AutoEvents (RollCall / Printer / Dance) =====
do
    Library.Toggles.AutoEvents:SetValue(true)
    OfficeEventRE.OnClientEvent:Fire("RollCallAsk", { Id = "rc1", EndsAt = Sched.now + 3 })
    pump(0.3)
    check("AutoEvents answers RollCall here once", (function()
        local ws = wiresFor(OfficeEventActionRE, function(w) return w.args[1] == "here" and w.args[2] == "rc1" end)
        return #ws == 1
    end)())
    OfficeEventRE.OnClientEvent:Fire("PrinterKick", { Id = "pk1", StartsAt = Sched.now, EndsAt = Sched.now + 2, Need = 6 })
    pump(1.0)
    check("AutoEvents kicks printer Need times in window", (function()
        local ws = wiresFor(OfficeEventActionRE, function(w) return w.args[1] == "kick" and w.args[2] == "pk1" end)
        return #ws == 6
    end)())
    OfficeEventRE.OnClientEvent:Fire("DanceStart", { Id = "dn1", StartsAt = Sched.now + 0.2, EndsAt = Sched.now + 4, Need = 3 })
    OfficeEventRE.OnClientEvent:Fire("DancePicked", { Victim = "czhigh", Boss = "boss", UserId = 1 })
    pump(1.5)
    check("AutoEvents dances when picked", (function()
        local ws = wiresFor(OfficeEventActionRE, function(w) return w.args[1] == "dance" and w.args[2] == "dn1" end)
        return #ws == 3
    end)())
    OfficeEventRE.OnClientEvent:Fire("DanceStart", { Id = "dn2", StartsAt = Sched.now + 0.2, EndsAt = Sched.now + 4, Need = 3 })
    OfficeEventRE.OnClientEvent:Fire("DancePicked", { Victim = "other", Boss = "boss", UserId = 42 })
    pump(1.5)
    check("AutoEvents no dance when other picked", #wiresFor(OfficeEventActionRE, function(w) return w.args[1] == "dance" and w.args[2] == "dn2" end) == 0)
    OfficeEventRE.OnClientEvent:Fire("EventEnd", {})
    Library.Toggles.AutoEvents:SetValue(false)
    pump(0.3)
end

-- ===== AutoQuiz =====
do
    Library.Toggles.AutoQuiz:SetValue(true)
    BossQuizRE.OnClientEvent:Fire({ Id = "q1", Question = "Who is the best boss ever?", Options = { "My mom", "You, sir!", "The janitor" }, EndsAt = Sched.now + 8, ReadyAt = Sched.now + 0.5 })
    local readyAt = Sched.now + 0.5
    pump(2.5)
    local ws = wiresFor(BossQuizAnswerRE, function(w) return w.args[1] == "q1" end)
    check("AutoQuiz answers compliment option", #ws == 1 and ws[1].args[2] == 2)
    check("AutoQuiz waits for ReadyAt", ws[1] ~= nil and ws[1].t >= readyAt + 0.7)
    BossQuizRE.OnClientEvent:Fire({ Id = "q2", Question = "Who makes the best coffee?", Options = { "Starbucks", "The vending machine", "The intern" }, EndsAt = Sched.now + 8, ReadyAt = Sched.now })
    pump(2.5)
    check("AutoQuiz skips non-compliment question", #wiresFor(BossQuizAnswerRE, function(w) return w.args[1] == "q2" end) == 0)
    BossQuizRE.OnClientEvent:Fire({ Id = "q3", Question = "¿Soy la persona más lista aquí?", Options = { "Mi mamá", "¡Obviamente, señor!", "Eh... ¿no?" }, EndsAt = Sched.now + 8, ReadyAt = Sched.now })
    pump(2.5)
    local ws3 = wiresFor(BossQuizAnswerRE, function(w) return w.args[1] == "q3" end)
    check("AutoQuiz answers Spanish compliment", #ws3 == 1 and ws3[1].args[2] == 2)
    Library.Toggles.AutoQuiz:SetValue(false)
    pump(0.3)
end

-- ===== AutoHack =====
do
    Boss:SetAttribute("BossState", "LEAVING")
    PLR:SetAttribute("HackReadyAt", Sched.now - 5)
    State.LaptopView = false
    State.Email = nil
    Meeting:SetAttribute("RoundEndsAt", Sched.now + 300)
    Meeting:SetAttribute("DayOff", false)
    Library.Toggles.AutoHack:SetValue(true)
    local t0 = Sched.now
    pump(4)
    check("AutoHack opens view then starts", (function()
        local view = wiresFor(SetLaptopViewRE, function(w) return w.t >= t0 and w.args[1] == true end)
        local starts = wiresFor(HackActionRE, function(w) return w.t >= t0 and w.args[1] == "start" end)
        return #view >= 1 and #starts >= 1
    end)())
    Meeting:SetAttribute("RoundEndsAt", Sched.now + 400)
    local Chart = HackRhythm.Chart(G.Random.new(99), 1)
    local RoundStart = Sched.now + 0.5
    HackUpdateRE.OnClientEvent:Fire({ Id = "h1", State = "active", Local = false, Round = 1, RoundStart = RoundStart, RoundEnd = RoundStart + 8, Chart = Chart })
    pump(6)
    check("AutoHack no re-start while hack active (HackUntil gate)", (function()
        local tA = Sched.now
        pump(1.5)
        return #wiresFor(HackActionRE, function(w) return w.t >= tA and w.args[1] == "start" end) == 0
    end)())
    local taps = wiresFor(HackActionRE, function(w) return w.args[1] == "tap" end)
    check("AutoHack taps every chart note", (function()
        if #taps ~= #Chart.notes then
            return false
        end
        for i, w in ipairs(taps) do
            local note = Chart.notes[i]
            if w.args[2] ~= "h1" or w.args[3] ~= 1 or w.args[4] ~= note.d then
                return false
            end
            if math.abs(w.args[5] - (RoundStart + note.t)) > 1e-9 then
                return false
            end
        end
        return true
    end)())
    check("AutoHack lateLocked skips start", (function()
        Meeting:SetAttribute("RoundEndsAt", Sched.now + 40)
        local t1 = Sched.now
        pump(2.5)
        local starts = #wiresFor(HackActionRE, function(w) return w.t >= t1 and w.args[1] == "start" end)
        Meeting:SetAttribute("RoundEndsAt", Sched.now + 300)
        pump(1.2)
        local starts2 = #wiresFor(HackActionRE, function(w) return w.t >= t1 and w.args[1] == "start" end)
        Meeting:SetAttribute("RoundEndsAt", Sched.now + 300)
        return starts < starts2
    end)())
    check("AutoHack boss-behind blocks", (function()
        local t2 = Sched.now
        Boss:SetAttribute("BossState", "BEHIND_PLAYER")
        Boss:SetAttribute("WatchedUserId", 1)
        pump(1.2)
        local n = #wiresFor(HackActionRE, function(w) return w.t >= t2 and w.args[1] == "start" end)
        Boss:SetAttribute("BossState", "PATROLLING")
        Boss:SetAttribute("WatchedUserId", nil)
        return n == 0
    end)())
    Library.Toggles.AutoHack:SetValue(false)
    pump(0.3)
end

-- ===== AutoPaper =====
do
    Library.Toggles.AutoPaper:SetValue(true)
    PLR:SetAttribute("SeatName", "S1")
    PLR:SetAttribute("WarTeam", "Blue")
    Meeting:SetAttribute("OfficeEvent", "PaperFight")
    Meeting:SetAttribute("PaperFightStartsAt", Sched.now - 1)
    Meeting:SetAttribute("PaperFightEndsAt", Sched.now + 10)
    local t0 = Sched.now
    pump(1.5)
    check("AutoPaper war: throws at nearest enemy (AllyRed at 12 < EnemyRedFar 50, RedDummy 10)", (function()
        local ws = wiresFor(ThrowPaperRE, function(w) return w.t >= t0 end)
        if #ws == 0 then
            return false
        end
        local target = ws[1].args[1]
        return target == AllyRed or target == RedDummy
    end)())
    check("AutoPaper war: never targets own team / unseated", (function()
        for _, w in ipairs(wiresFor(ThrowPaperRE, function(w) return w.t >= t0 end)) do
            if w.args[1] == EnemyBlue or w.args[1] == BlueDummy or w.args[1] == NoSeat then
                return false
            end
        end
        return true
    end)())
    Meeting:SetAttribute("OfficeEvent", nil)
    Meeting:SetAttribute("PaperFightEndsAt", nil)
    Meeting:SetAttribute("RoundPhase", "Countdown")
    Meeting:SetAttribute("CountdownEndsAt", Sched.now + 30)
    pump(1.2)
    check("AutoPaper countdown window throws (FFA, closest = NoSeat 8 then RedDummy 10)", (function()
        local ws = wiresFor(ThrowPaperRE)
        return #ws >= 2
    end)())
    Meeting:SetAttribute("RoundPhase", "Active")
    Meeting:SetAttribute("CountdownEndsAt", nil)
    local t2 = Sched.now
    pump(1.2)
    check("AutoPaper idle round: no throws (cooldown class left manual)", #wiresFor(ThrowPaperRE, function(w) return w.t >= t2 end) == 0)
    check("AutoPaper equips the paper tool from backpack", Char:FindFirstChild("MeetingPaper") ~= nil)
    Library.Toggles.AutoPaper:SetValue(false)
    pump(0.3)
    PLR:SetAttribute("SeatName", nil)
    PLR:SetAttribute("WarTeam", nil)
end

-- ===== AutoRelax =====
do
    Boss:SetAttribute("BossState", "LEAVING")
    State.Pressure = 75
    Library.Toggles.AutoRelax:SetValue(true)
    pump(1.5)
    check("AutoRelax equips squishy + uses it", (function()
        local uses = wiresFor(UseRelaxItemRE)
        return #uses >= 1 and uses[1].args[1] == SquishyTool and Char:FindFirstChild("ButterSquishy") ~= nil
    end)())
    check("AutoRelax 7s cooldown between squeezes", (function()
        local uses = wiresFor(UseRelaxItemRE)
        local last = nil
        for _, w in ipairs(uses) do
            if last and w.t - last < 6.9 then
                return false
            end
            last = w.t
        end
        return true
    end)())
    check("AutoRelax boss-behind blocks", (function()
        local t0 = Sched.now
        Boss:SetAttribute("BossState", "BEHIND_PLAYER")
        Boss:SetAttribute("WatchedUserId", 1)
        State.Pressure = 90
        pump(1.5)
        local n = #wiresFor(UseRelaxItemRE, function(w) return w.t >= t0 end)
        Boss:SetAttribute("BossState", "PATROLLING")
        Boss:SetAttribute("WatchedUserId", nil)
        return n == 0
    end)())
    Library.Toggles.AutoRelax:SetValue(false)
    pump(0.3)
    State.Pressure = 0
end

-- ===== AutoClaim =====
do
    PLR:SetAttribute("EconomyReady", true)
    PLR:SetAttribute("PlaytimeStart", Sched.now - 400)
    PLR:SetAttribute("PlaytimeClaimed", 0)
    Library.Toggles.AutoClaim:SetValue(true)
    pump(6)
    local c1 = #wiresFor(ClaimPlaytimeRE, function(w) return w.args[1] == 1 end)
    local c2 = #wiresFor(ClaimPlaytimeRE, function(w) return w.args[1] == 2 end)
    local c3 = #wiresFor(ClaimPlaytimeRE, function(w) return w.args[1] == 3 end)
    check("AutoClaim claims tier 1 (2min) and tier 2 (5min) once each", c1 == 1 and c2 == 1)
    check("AutoClaim skips unearned tier 3 (15min)", c3 == 0)
    pump(6)
    check("AutoClaim no double-claim", #wiresFor(ClaimPlaytimeRE) == 2)
    Library.Toggles.AutoClaim:SetValue(false)
    pump(0.3)
    PLR:SetAttribute("PlaytimeStart", nil)
    PLR:SetAttribute("PlaytimeClaimed", nil)
    PLR:SetAttribute("EconomyReady", nil)
end

-- ===== AutoUpgrade =====
do
    PLR:SetAttribute("Rank", 3)
    PLR:SetAttribute("Exp", 500)
    PLR:SetAttribute("Bobux", 400)
    PLR:SetAttribute("PaperLevel", 0)
    PLR:SetAttribute("PhoneLevel", 0)
    Library.Toggles.AutoUpgrade:SetValue(true)
    pump(6)
    check("AutoUpgrade buys cheapest next (Phone 200 before Paper 300)", (function()
        local ws = wiresFor(BuyUpgradeRE)
        return #ws == 1 and ws[1].args[1] == "Phone"
    end)())
    PLR:SetAttribute("Bobux", 350)
    pump(6)
    check("AutoUpgrade ladder advances to Paper", (function()
        local ws = wiresFor(BuyUpgradeRE, function(w) return w.args[1] == "Paper" end)
        return #ws == 1
    end)())
    PLR:SetAttribute("Bobux", 5000)
    PLR:SetAttribute("Rank", 1)
    PLR:SetAttribute("PaperLevel", 2)
    PLR:SetAttribute("PhoneLevel", 1)
    local t0 = Sched.now
    pump(6)
    check("AutoUpgrade respects Rank gate (Rank 1 < tier Rank 2)", (function()
        for _, w in ipairs(wiresFor(BuyUpgradeRE)) do
            if w.t >= t0 then
                return false
            end
        end
        return true
    end)())
    Library.Toggles.AutoUpgrade:SetValue(false)
    pump(0.3)
    PLR:SetAttribute("Rank", nil)
    PLR:SetAttribute("Bobux", nil)
    PLR:SetAttribute("PaperLevel", nil)
    PLR:SetAttribute("PhoneLevel", nil)
end

-- ===== AutoAlien =====
do
    Library.Toggles.AutoAlien:SetValue(true)
    Meeting:SetAttribute("AlienPhase", "Fight")
    local t0 = Sched.now
    pump(1.0)
    local fires = wiresFor(AlienActionRE, function(w) return w.args[1] == "fire" and w.t >= t0 end)
    check("AutoAlien fires at FireInterval cadence (>=9/s)", #fires >= 9)
    check("AutoAlien respects FireInterval spacing", (function()
        local last = nil
        for _, w in ipairs(fires) do
            if last and w.t - last < 0.084 then
                return false
            end
            last = w.t
        end
        return true
    end)())
    Meeting:SetAttribute("AlienDodgeAt", Sched.now)
    local t1 = Sched.now
    pump(0.5)
    check("AutoAlien no fire while dodging", #wiresFor(AlienActionRE, function(w) return w.args[1] == "fire" and w.t >= t1 end) == 0)
    Meeting:SetAttribute("AlienDodgeAt", nil)
    Meeting:SetAttribute("AlienZappedUntil", Sched.now + 5)
    pump(0.5)
    check("AutoAlien no fire while zapped", #wiresFor(AlienActionRE, function(w) return w.args[1] == "fire" and w.t >= t1 end) == 0)
    Meeting:SetAttribute("AlienZappedUntil", nil)
    Meeting:SetAttribute("AlienWarnId", "w1")
    pump(0.3)
    Meeting:SetAttribute("AlienWarnId", "w1")
    pump(0.3)
    local shields = wiresFor(AlienActionRE, function(w) return w.args[1] == "shield" end)
    check("AutoAlien shields once per warn id", #shields == 1)
    Library.Toggles.AutoAlien:SetValue(false)
    pump(0.3)
    local t2 = Sched.now
    Meeting:SetAttribute("AlienWarnId", "w2")
    pump(0.5)
    check("AutoAlien stops after toggle off", #wiresFor(AlienActionRE, function(w) return w.t >= t2 end) == 0)
    Meeting:SetAttribute("AlienPhase", nil)
    Meeting:SetAttribute("AlienWarnId", nil)
end

-- ===== AutoHalloween =====
do
    Library.Toggles.AutoHalloween:SetValue(true)
    Meeting:SetAttribute("HwPhase", "Fight")
    local t0 = Sched.now
    pump(1.0)
    check("AutoHalloween fires in Fight phase", #wiresFor(HwActionRE, function(w) return w.args[1] == "fire" and w.t >= t0 end) >= 9)
    Meeting:SetAttribute("HwPhase", "Climax")
    Meeting:SetAttribute("HwQteKind", "Mash")
    Meeting:SetAttribute("HwQteAt", Sched.now - 0.01)
    Meeting:SetAttribute("HwQteEnd", Sched.now + 2)
    Meeting:SetAttribute("HwQteId", "qte1")
    local t1 = Sched.now
    pump(0.6)
    check("AutoHalloween Climax Mash fires inside QTE window", #wiresFor(HwActionRE, function(w) return w.args[1] == "fire" and w.t >= t1 end) >= 5)
    Meeting:SetAttribute("HwQteEnd", Sched.now - 1)
    local t2 = Sched.now
    pump(0.5)
    check("AutoHalloween no fire outside QTE window", #wiresFor(HwActionRE, function(w) return w.args[1] == "fire" and w.t >= t2 end) == 0)
    Meeting:SetAttribute("HwQteKind", "Dodge")
    Meeting:SetAttribute("HwQteAt", Sched.now - 0.01)
    Meeting:SetAttribute("HwQteEnd", Sched.now + 2)
    Meeting:SetAttribute("HwQteId", "qte2")
    pump(0.3)
    Meeting:SetAttribute("HwQteId", "qte2")
    pump(0.3)
    check("AutoHalloween Climax Dodge shields once per QteId", (function()
        local ws = wiresFor(HwActionRE, function(w) return w.args[1] == "shield" and w.t >= t2 end)
        return #ws == 1
    end)())
    Meeting:SetAttribute("HwQteKind", nil)
    Meeting:SetAttribute("HwPhase", "Fight")
    local tWarn = Sched.now
    Meeting:SetAttribute("HwWarnId", "hw1")
    pump(0.3)
    Meeting:SetAttribute("HwWarnId", "hw1")
    pump(0.3)
    check("AutoHalloween shields once per warn id", #wiresFor(HwActionRE, function(w) return w.args[1] == "shield" and w.t >= tWarn end) == 1)
    Library.Toggles.AutoHalloween:SetValue(false)
    pump(0.3)
    Meeting:SetAttribute("HwPhase", nil)
    Meeting:SetAttribute("HwWarnId", nil)
end

-- ===== AutoVerity =====
do
    Library.Toggles.AutoVerity:SetValue(true)
    PLR:SetAttribute("MeetingJoined", true)
    PLR:SetAttribute("ReturnToMenu", false)
    local Seed, StartAt = 4242, Sched.now
    local Min, Max = Vector3.new(-12, 2, -12), Vector3.new(12, 9, 12)
    local Hover = Vector3.new(0, 5, 0)
    VerityCueRE.OnClientEvent:Fire("Fight", { Seed = Seed, StartAt = StartAt, Hover = Hover, Min = Min, Max = Max })
    pump(1.5)
    local throws = wiresFor(VerityActionRE, function(w) return w.args[1] == "throw" end)
    check("AutoVerity throws at ThrowRate", (function()
        local last = nil
        for _, w in ipairs(throws) do
            if last and w.t - last < 0.27 then
                return false
            end
            last = w.t
        end
        return #throws >= 2
    end)())
    check("AutoVerity aim = game's own lead against the REAL path", (function()
        if #throws == 0 then
            return false
        end
        local w = throws[#throws]
        local twin = VerityPath.new(Seed, StartAt, Hover, Min, Max)
        local origin = Vector3.new(Head.CFrame.Position.X, Head.CFrame.Position.Y + 0.2, Head.CFrame.Position.Z)
        if math.abs(w.args[2].X - origin.X) > 1e-6 or math.abs(w.args[2].Y - origin.Y) > 1e-6 or math.abs(w.args[2].Z - origin.Z) > 1e-6 then
            return false
        end
        local T = w.t
        local cur = twin:Pos(T)
        local eta = (cur - origin).Magnitude / 75
        local aim = twin:Pos(T + eta) + Vector3.new(0, eta * eta * 6, 0)
        local dir = (aim - origin).Unit
        return math.abs(dir.X - w.args[3].X) < 1e-4 and math.abs(dir.Y - w.args[3].Y) < 1e-4 and math.abs(dir.Z - w.args[3].Z) < 1e-4
    end)())
    VerityCueRE.OnClientEvent:Fire("End", nil)
    pump(0.5)
    check("AutoVerity stops after End cue", (function()
        local n = #throws
        pump(1)
        return #wiresFor(VerityActionRE, function(w) return w.args[1] == "throw" end) == n
    end)())
    Library.Toggles.AutoVerity:SetValue(false)
    pump(0.3)
end

-- ===== AutoLaptopFight =====
do
    Library.Toggles.AutoLaptopFight:SetValue(true)
    local FightLaptop = Instance.new("Tool", "FightLaptop")
    FightLaptop:SetAttribute("LaptopFight", true)
    Char:AddChild(FightLaptop)
    mkLFDummy("D1", 0, 3, -4)
    mkLFDummy("D2", 0, 3, -2)
    mkLFDummy("D3", 2, 3, -3)
    mkLFDummy("D4", 0, 3, -2.1)
    mkLFDummy("DFar", 0, 3, 30)
    EnemyBlue:SetAttribute("LaptopFighter", true)
    LaptopFightCueRE.OnClientEvent:Fire("Fight", { EndsAt = Sched.now + 8 })
    pump(2.5)
    local swings = wiresFor(LaptopFightActionRE, function(w) return w.args[1] == "swing" end)
    local hits = wiresFor(LaptopFightActionRE, function(w) return w.args[1] == "hit" end)
    check("AutoLaptopFight swings at SwingCooldown", (function()
        if #swings < 2 then
            return false
        end
        local last = nil
        for _, w in ipairs(swings) do
            if last and w.t - last < 0.54 then
                return false
            end
            last = w.t
        end
        return true
    end)())
    check("AutoLaptopFight hit list <=4 nearest models", (function()
        if #hits == 0 then
            return false
        end
        local list = hits[#hits].args[2]
        if type(list) ~= "table" or #list > 4 then
            return false
        end
        local farFound = false
        for _, m in ipairs(list) do
            if m.Name == "DFar" then
                farFound = true
            end
        end
        return #list == 4 and not farFound
    end)())
    check("AutoLaptopFight sorted by distance (D2/D4 closest first region)", (function()
        local list = hits[#hits].args[2]
        local d = {}
        for i, m in ipairs(list) do
            local part = m:FindFirstChild("HumanoidRootPart")
            d[i] = part and part.CFrame.Position.Z or 0
        end
        for i = 2, #d do
            if d[i - 1] > d[i] + 1e-9 and math.abs(d[i - 1]) > math.abs(d[i]) then
                return false
            end
        end
        return true
    end)())
    LaptopFightCueRE.OnClientEvent:Fire("End", nil)
    pump(0.5)
    Library.Toggles.AutoLaptopFight:SetValue(false)
    pump(0.3)
    EnemyBlue:SetAttribute("LaptopFighter", nil)
end

-- ===== globals =====
check("banned wires: none beyond the 24 resolved remotes", (function()
    local allowed = { [JoinMeetingRE] = true, [GetStateRF] = true, [StateUpdatedRE] = true, [SubmitEmailRE] = true, [SetLaptopViewRE] = true, [DismissScamRE] = true, [SmackLaptopRE] = true, [InterruptActionRE] = true, [UseRelaxItemRE] = true, [ThrowPaperRE] = true, [OfficeEventRE] = true, [OfficeEventActionRE] = true, [BossQuizRE] = true, [BossQuizAnswerRE] = true, [HackActionRE] = true, [HackUpdateRE] = true, [BuyUpgradeRE] = true, [ClaimPlaytimeRE] = true, [AlienActionRE] = true, [HwActionRE] = true, [VerityActionRE] = true, [VerityCueRE] = true, [LaptopFightActionRE] = true, [LaptopFightCueRE] = true }
    for _, w in ipairs(WireLog) do
        if not allowed[w.remote] then
            return false
        end
    end
    return true
end)())
check("no pcall swallows", PcallSwallows == 0)
check("no loop error logs", (function()
    for _, l in ipairs(NotyuriLog) do
        if string.find(l, "Auto", 1, true) then
            return false
        end
    end
    return true
end)())

print(string.format("DGF1 harness: %d pass / %d fail", Pass, Fail))
if Fail > 0 then
    for _, f in ipairs(Failures) do
        print("  failed: " .. f)
    end
    os.exit(1)
end
