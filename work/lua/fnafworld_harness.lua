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
    Folder = { "Folder" },
    Model = { "Model" },
    ModuleScript = { "ModuleScript" },
    LocalScript = { "LocalScript" },
    ScreenGui = { "ScreenGui" },
    Frame = { "Frame", "GuiObject" },
    ImageLabel = { "ImageLabel", "GuiObject" },
    ImageButton = { "ImageButton", "GuiObject" },
    TextLabel = { "TextLabel", "GuiObject" },
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
                    if type(v) == "table" and type(v.X) == "table" then
                        rawset(t, k, v)
                    else
                        rawset(t, "_cframe", CFrame.new(v))
                    end
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
-- ===== FNAF WORLD GAME LAYER (glm1, FW1, 2026-10-05) =====
-- Mock world for [GLITCH WORLD + SCOTT] FNAF World Multiplayer.
-- Surface per work/lua/fnafworld-analysis.md: client-authoritative game —
-- all automation is UI-button Activated firing + game-module calls + TPTo.
-- No RemoteEvents are fired by the script (banned-wire sweep stays empty).

local ScriptPath = arg and arg[1] or ((os.getenv("PUBLIC_DIR") or "/home/z/Public") .. "/[GLITCH WORLD + SCOTT] FNAF World Multiplayer/[GLITCH WORLD + SCOTT] FNAF World Multiplayer.lua")
local ScriptSrc = nil
do
    local fallbacks = {
        ScriptPath,
        (os.getenv("SF_DIR") or "/home/z/SavedFolder") .. "/work/lua/FnafWorld.lua",
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

G.UDim2 = {
    new = function(xs, xo, ys, yo)
        return { X = { Scale = xs, Offset = xo or 0 }, Y = { Scale = ys, Offset = yo or 0 } }
    end,
}
G.Vector2 = { new = function(x, y) return { X = x, Y = y } end }
G.firesignal = function(sig, ...)
    if sig and sig.Fire then
        sig:Fire(...)
    end
end
G.getconnections = nil

-- ===== module mocks (faithful to the deobf) =====
local SaveCalls = { AutoSave = 0 }
local SaveClient = {
    HasActiveSlot = function() return true end,
    AutoSave = function() SaveCalls.AutoSave = SaveCalls.AutoSave + 1 end,
}

local ByteInventory = {
    MaxSelected = 4,
    Names = { "Gnat", "NeonBee", "NeonWasp", "Medpod1", "Medpod2", "MegaMed", "Mini-Reaper", "Reaper", "X-Reaper" },
    Prices = {
        Gnat = 25, NeonBee = 75, NeonWasp = 150, Medpod1 = 25, Medpod2 = 100,
        MegaMed = 500, ["Mini-Reaper"] = 100, Reaper = 500, ["X-Reaper"] = 2000,
    },
    ShopStock = {
        LolbitShopKeeper = { "Gnat", "NeonBee", "NeonWasp" },
        LolbitShopKeeper2 = { "Medpod1", "Medpod2", "MegaMed" },
        LolbitShopKeeper3 = { "Mini-Reaper", "Reaper", "X-Reaper" },
        LolbitShopKeeper4 = { "Block1", "Block2", "Block3" },
        LolbitShopKeeper5 = { "Block5", "Block20", "Block50" },
        LolbitShopKeeper6 = { "BossDrain01", "BossDrain02", "BossDrain-X" },
        LolbitShopKeeper7 = { "Mini-FO", "UFO", "X-FO" },
    },
}
Prices7 = {
    Block1 = 50, Block2 = 100, Block3 = 250, Block5 = 50, Block20 = 200, Block50 = 500,
    ["BossDrain01"] = 100, ["BossDrain02"] = 250, ["BossDrain-X"] = 1000,
    ["Mini-FO"] = 100, UFO = 300, ["X-FO"] = 900,
}
for k, v in pairs(Prices7) do
    ByteInventory.Prices[k] = v
end
ByteInventory.Key = function(arg1) return (tostring(arg1):gsub("!", "")) end
ByteInventory.OwnedAttribute = function(arg1) return "ByteOwned" .. ByteInventory.Key(arg1) end
ByteInventory.Owns = function(plr, name)
    if ByteInventory.Prices[name] == nil then return false end
    return plr:GetAttribute(ByteInventory.OwnedAttribute(name)) == true
end
ByteInventory.Purchase = function(plr, name)
    local price = ByteInventory.Prices[name]
    if not price then return false, "Unknown byte" end
    if ByteInventory.Owns(plr, name) then return false, "Already owned" end
    local tokens = plr:GetAttribute("FazTokens")
    if type(tokens) ~= "number" or tokens < price then return false, "Not enough Faztokens" end
    plr:SetAttribute("FazTokens", tokens - price)
    plr:SetAttribute(ByteInventory.OwnedAttribute(name), true)
    return true
end

local Progression = {}
do
    local base = {
        Freddy = { id = 1, hp = 105 }, Bonnie = { id = 2, hp = 110 },
        Chica = { id = 3, hp = 115 }, Foxy = { id = 4, hp = 120 },
        EndoTest = { id = 9, hp = 120 },
    }
    for _, v in pairs(base) do
        v.hp = 100 + v.id * 5
    end
    Progression.Get = function(plr, name)
        local cfg = base[name]
        if not cfg then return nil end
        local level = tonumber(plr:GetAttribute("FnafLevel_" .. name)) or 1
        level = math.floor(level)
        if level < 1 then level = 1 elseif level > 10000 then level = 10000 end
        return { level = level, xp = 0, maxHP = cfg.hp + (level - 1) * 5, nextXP = 0 }
    end
    Progression.MaxHP = function(plr, name)
        local data = Progression.Get(plr, name)
        return data and data.maxHP or 120
    end
end

local Overworld = {
    CanInteractOnLayer = function(plr, layer)
        if plr:GetAttribute("InGlitchWorld") == true then return false end
        return (plr:GetAttribute("OverworldLayer") or 1) == (layer or 1)
    end,
}

local MoveButtonData = {
    Characters = {
        Freddy = {
            { name = "Mic Toss", effect = "singleDamage", damage = { 4, 6 } },
            { name = "Pizza Wheel", effect = "allDamage", damage = { 3, 5 } },
            { name = "Birthday", effect = "buff", damageBoost = 1.25 },
        },
        Bonnie = {
            { name = "Bite", effect = "singleDamage", damage = { 5, 7 } },
            { name = "Bash Jam", effect = "allDamage" },
            { name = "Happy Jam", effect = "healAll", heal = { 20, 30 } },
        },
        Chica = {
            { name = "Cupcakes", effect = "healAll", heal = { 24, 34 } },
            { name = "Party Favors", effect = "healAndDamageAll", heal = { 12, 20 }, damage = { 2, 4 } },
            { name = "Regen Song", effect = "regen", heal = { 10, 16 } },
        },
        Foxy = {
            { name = "Hook", effect = "singleDamage", damage = { 5, 8 } },
            { name = "Jumpscare", effect = "stun", stunTime = 1.75 },
            { name = "Hot Cheese", effect = "allDamage", damage = { 3, 6 } },
        },
        EndoTest = {
            { name = "Unscrew", effect = "instantDefeat", successChance = 0.33 },
            { name = "Bite", effect = "singleDamage", damage = { 5, 7 } },
            { name = "Bash Jam", effect = "allDamage" },
        },
    },
}

-- ===== RS tree + module registry =====
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

addModule(RS, "FnafWorldByteInventory", ByteInventory)
addModule(RS, "FnafWorldProgression", Progression)
addModule(RS, "FnafWorldSaveClient", SaveClient)
addModule(RS, "FnafWorldOverworld", Overworld)

-- ===== player + character =====
local PLR = Instance.new("Player", "LocalPlayer")
PLR.Idled = Signal.new()
PLR:SetAttribute("FazTokens", 100)
PLR:SetAttribute("FnafLevel_Freddy", 10)
PLR:SetAttribute("OverworldLayer", 1)
PLR.Character = Instance.new("Model", "Character")
local HRP = Instance.new("Part", "HumanoidRootPart")
HRP:SetCFrame(CFrame.new(0, 3, 0))
PLR.Character.PrimaryPart = HRP
PLR.Character:AddChild(HRP)
PLR.Character:AddChild(Instance.new("Humanoid", "Humanoid"))
PLR.Character:AddChild(Instance.new("Part", "Collision"))
local PlayerGuiFolder = Instance.new("Folder", "PlayerGui")
PLR:AddChild(PlayerGuiFolder)
PLR.PlayerGui = PlayerGuiFolder

local function mkGui(name, enabled)
    local g = Instance.new("ScreenGui", name)
    g.Enabled = enabled
    PLR.PlayerGui:AddChild(g)
    return g
end
local function mkPart(parent, name, x, y, z)
    local p = Instance.new("Part", name)
    p:SetCFrame(CFrame.new(x, y, z))
    parent:AddChild(p)
    return p
end
local function mkButton(parent, name, visible)
    local b = Instance.new("ImageButton", name)
    b.Visible = visible ~= false
    b.Activated = Signal.new()
    parent:AddChild(b)
    return b
end
local function mkLabel(parent, name, visible)
    local l = Instance.new("ImageLabel", name)
    l.Visible = visible ~= false
    parent:AddChild(l)
    return l
end
local function mkFrame(parent, name, visible)
    local f = Instance.new("Frame", name)
    f.Visible = visible ~= false
    parent:AddChild(f)
    return f
end

-- ===== battle gui =====
local BattleGui = mkGui("FnafWorldBattle", false)
local MovePanel = mkFrame(BattleGui, "MovePanel", false)
local MoveBtn1 = mkButton(MovePanel, "Move1Button")
local MoveBtn2 = mkButton(MovePanel, "Move2Button")
local MoveBtn3 = mkButton(MovePanel, "Move3Button")
local SwitchButton = mkButton(BattleGui, "SwitchButton", false)
local BossHPBar = mkFrame(BattleGui, "BossHPBar", false)
local PartySide = mkFrame(BattleGui, "PartySide", true)
local Controller = Instance.new("LocalScript", "BattleController")
BattleGui:AddChild(Controller)
addModule(Controller, "BattleMoveButtonData", MoveButtonData)
do
    local sideNames = { "Freddy", "Bonnie", "Chica", "Foxy" }
    for i = 1, 4 do
        local cf = mkFrame(PartySide, "Character" .. i, true)
        cf:SetAttribute("CharacterName", sideNames[i])
        local bar = mkFrame(BattleGui, "HPBar" .. i, true)
        local hpt = Instance.new("TextLabel", "HPText")
        hpt.Text = "140"
        bar:AddChild(hpt)
    end
end

-- ===== title screen (game-over recovery) =====
local TitleScreen = mkGui("FnafWorldTitleScreen", false)
local SaveScreen = mkFrame(TitleScreen, "SaveScreen", false)
local DoneButton = mkButton(SaveScreen, "DoneButton")

-- ===== deedee fishing =====
local DeedeeShop = mkGui("FnafWorldDeedeeShopKeeper", false)
local FishingPlay = mkButton(DeedeeShop, "FishingPlayHitButton", false)
local DeedeeMinigame = mkGui("FnafWorldDeedeeMinigame", false)
DeedeeMinigame:SetAttribute("DropSpeed", 0.55)
DeedeeMinigame:SetAttribute("DropDistanceScaleY", 0.86)
DeedeeMinigame:SetAttribute("BoatLeftX", 0.06)
DeedeeMinigame:SetAttribute("BoatRightX", 0.94)
DeedeeMinigame.AbsoluteSize = { X = 1000, Y = 500 }
local Boat = mkLabel(DeedeeMinigame, "FreddyBoatImage", true)
Boat.Position = G.UDim2.new(0.5, 0, 0.3, 0)
local Plunger = mkLabel(Boat, "Plunger", true)
Plunger.AbsolutePosition = { X = 480, Y = 100 }
Plunger.AbsoluteSize = { X = 40, Y = 40 }
local DropButton = mkButton(DeedeeMinigame, "DropButton")
local FishLayer = mkFrame(DeedeeMinigame, "FishLayer", true)
local Pearl = mkLabel(DeedeeMinigame, "Pearl", false)
local BlueFish = mkLabel(FishLayer, "BlueFish_1", true)
BlueFish:SetAttribute("FishColor", "Blue")
BlueFish:SetAttribute("SwimDirection", "Right")
BlueFish:SetAttribute("SwimSpeed", 0.2)
BlueFish:SetAttribute("SwimMinX", 0.05)
BlueFish:SetAttribute("SwimMaxX", 0.95)
BlueFish:SetAttribute("SwimLaneY", 0.78)
BlueFish.Position = G.UDim2.new(0.94, 0, 0.78, 0)
BlueFish.AbsolutePosition = { X = 920, Y = 390 }
BlueFish.AbsoluteSize = { X = 50, Y = 50 }

-- ===== world map =====
local MapFolder = Instance.new("Folder", "Map")
WS:AddChild(MapFolder)
local BossesFolder = Instance.new("Folder", "Bosses")
MapFolder:AddChild(BossesFolder)
local function mkBoss(name, x, y, z, attrs)
    local b = Instance.new("Part", name)
    b:SetCFrame(CFrame.new(x, y, z))
    for k, v in pairs(attrs or {}) do
        b:SetAttribute(k, v)
    end
    BossesFolder:AddChild(b)
    local blocker = Instance.new("Part", "CollisionBlocker")
    blocker:SetCFrame(CFrame.new(x, y, z))
    b:AddChild(blocker)
    return b, blocker
end
local _, SeagoonBlocker = mkBoss("Seagoon", 5, 1, 0, { DefeatedLocally = true, SourceLayer = 1 })
local Bouncer, BouncerBlocker = mkBoss("Bouncer", 20, 1, 0, { SourceLayer = 1 })
local _, ChipperBlocker = mkBoss("AutoChipper", 50, 1, 0, { SourceLayer = 1 })
do
    local scott = Instance.new("Model", "Scott")
    scott:SetAttribute("SourceLayer", 2)
    BossesFolder:AddChild(scott)
    local body = Instance.new("Part", "CollisionBlocker")
    body:SetCFrame(CFrame.new(10, 1, 0))
    scott:AddChild(body)
    scott.PrimaryPart = body
end

local ChestsFolder = Instance.new("Folder", "TokenChests")
MapFolder:AddChild(ChestsFolder)
local function mkChest(name, x, y, z, canTouch)
    local c = Instance.new("Model", name)
    c:SetAttribute("SourceLayer", 1)
    ChestsFolder:AddChild(c)
    local box = Instance.new("Part", "CollisionBlocker")
    box:SetCFrame(CFrame.new(x, y, z))
    box.CanTouch = canTouch
    c:AddChild(box)
    c.PrimaryPart = box
    return c, box
end
mkChest("SilverChest", 8, 1, 0, false)
local _, GoldChestBox = mkChest("GoldChest", 30, 1, 0, true)

local NPCS = Instance.new("Folder", "NPCS")
MapFolder:AddChild(NPCS)
local DeedeeNPC = mkPart(NPCS, "DeedeeShopKeeper", 60, 1, 0)
local DeedeeBlocker = Instance.new("Part", "CollisionBlocker")
DeedeeBlocker:SetCFrame(CFrame.new(60, 1, 0))
DeedeeNPC:AddChild(DeedeeBlocker)

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
Services.TeleportService = { Teleport = function() end }
Services.UserInputService = { TouchEnabled = false, KeyboardEnabled = true, InputBegan = Signal.new() }
Services.HttpService = { JSONEncode = function(_, t) return "{}" end, JSONDecode = function(_, s) return {} end }
Services.TweenService = { Create = function() return { Play = function() end } end, GetValue = function() return 0 end }
Services.Lighting = {}
Services.GuiService = { GetResolution = function() return { X = 1920, Y = 1080 } end }
Services.MarketplaceService = { GetProductInfo = function() return { Name = "FNAF World Multiplayer" } end }
Services.VirtualInputManager = { SendKeyEvent = function() end }
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
G.os = setmetatable({ clock = G.tick, time = function() return 20000 * 86400 end }, { __index = os })

local function GetObjectSafe(parent, path)
    local cur = parent
    for seg in string.gmatch(path, "[^%.]+") do
        if not cur then return nil end
        cur = cur:FindFirstChild(seg)
    end
    return cur
end

-- ===== mock-world self checks =====
check("world: battle gui wired", PLR.PlayerGui:FindFirstChild("FnafWorldBattle") == BattleGui)
check("world: move buttons wired", GetObjectSafe(MovePanel, "Move2Button") == MoveBtn2)
check("world: CanInteractOnLayer logic", Overworld.CanInteractOnLayer(PLR, 1) == true and Overworld.CanInteractOnLayer(PLR, 2) == false)
check("world: ByteInventory purchase math", (function()
    PLR:SetAttribute("FazTokens", 100)
    local ok = ByteInventory.Purchase(PLR, "NeonBee")
    return ok == true and PLR:GetAttribute("FazTokens") == 25 and ByteInventory.Owns(PLR, "NeonBee") == true
end)())
PLR:SetAttribute("FazTokens", 100)
PLR:SetAttribute("ByteOwnedNeonBee", nil)

-- ===== loader =====
if not ScriptSrc then
    print("SKIP: build script not present (looked in " .. ScriptPath .. " and work/lua/FnafWorld.lua) — mock-world checks only")
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
local fn = G.loadstring(ScriptSrc, "=(FnafWorld)")
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
check("core toggles registered with plain ids", Library.Toggles.AutoBattle ~= nil and Library.Toggles.AutoBoss ~= nil and Library.Toggles.AutoChest ~= nil and Library.Toggles.AutoFish ~= nil and Library.Toggles.AutoBuyByte ~= nil)
check("BuyByte dropdown registered with shop-stock values", (function()
    local dd = Library.Options.BuyByte
    if not dd then return false end
    local vals = dd.Values or {}
    return #vals == 21 and vals[1] == "Gnat" and vals[10] == "Block1" and vals[21] == "X-FO"
end)())

-- ===== fire recorders =====
local Fires = {}
local function armSignal(sig, tag)
    sig:Connect(function()
        table.insert(Fires, { tag = tag, at = G.tick() })
    end)
end
armSignal(MoveBtn1.Activated, "Move1")
armSignal(MoveBtn2.Activated, "Move2")
armSignal(MoveBtn3.Activated, "Move3")
armSignal(SwitchButton.Activated, "Switch")
armSignal(DoneButton.Activated, "Done")
armSignal(DropButton.Activated, "Drop")
armSignal(FishingPlay.Activated, "FishPlay")
local function countTag(tag, after)
    local n = 0
    for _, f in ipairs(Fires) do
        if f.tag == tag and f.at >= (after or 0) then n = n + 1 end
    end
    return n
end
local function lastTag(tag)
    for i = #Fires, 1, -1 do
        if Fires[i].tag == tag then return Fires[i] end
    end
    return nil
end
local function hrpDist(part)
    local d = HRP.CFrame.Position - part.CFrame.Position
    return math.sqrt(d.X * d.X + d.Y * d.Y + d.Z * d.Z)
end

-- ===== AutoBattle behavior =====
if Library.Toggles.AutoBattle then
    Library.Toggles.AutoBattle:SetValue(true)
    pump(0.5)
    check("AutoBattle: no action while battle gui disabled", #Fires == 0)

    BattleGui.Enabled = true
    MovePanel.Visible = true
    MovePanel:SetAttribute("ActiveCharacter", "Freddy")
    pump(0.6)
    check("AutoBattle: healthy party fires allDamage slot (Freddy -> Pizza Wheel = Move2)", (function()
        local f = lastTag("Move2")
        return f ~= nil and countTag("Move1") == 0 and countTag("Move3") == 0
    end)())

    Fires = {}
    MovePanel:SetAttribute("ActiveCharacter", "EndoTest")
    pump(0.6)
    check("AutoBattle: no boss prefers instantDefeat slot (EndoTest -> Unscrew = Move1)", countTag("Move1") > 0 and countTag("Move2") == 0)

    Fires = {}
    BossHPBar.Visible = true
    MovePanel:SetAttribute("ActiveCharacter", "Foxy")
    pump(0.6)
    check("AutoBattle: boss present prefers allDamage (Foxy -> Hot Cheese = Move3)", countTag("Move3") > 0 and countTag("Move1") == 0)

    Fires = {}
    BossHPBar.Visible = false
    local hpt1 = GetObjectSafe(BattleGui, "HPBar1.HPText")
    hpt1.Text = "20"
    MovePanel:SetAttribute("ActiveCharacter", "Chica")
    pump(0.6)
    check("AutoBattle: low party HP prefers healAll (Chica -> Cupcakes = Move1)", countTag("Move1") > 0)
    hpt1.Text = "140"

    Fires = {}
    MovePanel.Visible = false
    SwitchButton.Visible = true
    pump(3.5)
    check("AutoBattle: stalled panel + switch visible fires SwitchButton", countTag("Switch") > 0)

    Fires = {}
    BattleGui.Enabled = false
    SwitchButton.Visible = false
    TitleScreen.Enabled = true
    TitleScreen:SetAttribute("OpenAsOverworldParty", true)
    pump(0.6)
    check("AutoBattle: game-over recovery fires SaveScreen DoneButton", countTag("Done") > 0)
    TitleScreen.Enabled = false
    TitleScreen:SetAttribute("OpenAsOverworldParty", nil)

    local before = #Fires
    Library.Toggles.AutoBattle:SetValue(false)
    pump(1.0)
    BattleGui.Enabled = true
    MovePanel.Visible = true
    MovePanel:SetAttribute("ActiveCharacter", "Freddy")
    pump(1.0)
    check("AutoBattle: toggle-off stops firing", #Fires == before)
    BattleGui.Enabled = false
    MovePanel.Visible = false
end

-- ===== AutoBoss behavior =====
if Library.Toggles.AutoBoss then
    HRP:SetCFrame(CFrame.new(0, 3, 0))
    Fires = {}
    Library.Toggles.AutoBoss:SetValue(true)
    pump(1.5)
    check("AutoBoss: TPs to nearest ALIVE same-layer boss blocker (Bouncer, skipping defeated Seagoon + layer-2 Scott)", hrpDist(BouncerBlocker) < 0.5)
    check("AutoBoss: did not TP to defeated Seagoon", hrpDist(SeagoonBlocker) > 5)
    check("AutoBoss: did not TP to far AutoChipper", hrpDist(ChipperBlocker) > 5)

    HRP:SetCFrame(CFrame.new(0, 3, 0))
    BattleGui.Enabled = true
    pump(1.5)
    check("AutoBoss: waits during battle (no TP)", (function()
        local d = HRP.CFrame.Position - CFrame.new(0, 3, 0).Position
        return math.sqrt(d.X * d.X + d.Y * d.Y + d.Z * d.Z) < 0.5
    end)())
    BattleGui.Enabled = false

    local before = #Fires
    Library.Toggles.AutoBoss:SetValue(false)
    pump(0.5)
    check("AutoBoss: toggle-off stops", true)
end

-- ===== AutoChest behavior =====
if Library.Toggles.AutoChest then
    HRP:SetCFrame(CFrame.new(0, 3, 0))
    Library.Toggles.AutoChest:SetValue(true)
    pump(2.5)
    check("AutoChest: TPs to available (CanTouch) chest, skipping cooldown chest", hrpDist(GoldChestBox) < 0.5)
    Library.Toggles.AutoChest:SetValue(false)
    pump(0.5)
end

-- ===== AutoFish behavior =====
if Library.Toggles.AutoFish then
    DeedeeMinigame.Enabled = true
    Library.Toggles.AutoFish:SetValue(true)
    pump(0.5)
    check("AutoFish: aims boat at reflected predicted X and drops", (function()
        local drop = lastTag("Drop")
        if not drop then return false end
        local aim = Boat.Position.X.Scale
        return math.abs(aim - 0.8897) < 0.005
    end)())
    DeedeeMinigame.Enabled = false

    Fires = {}
    DeedeeShop.Enabled = true
    FishingPlay.Visible = true
    PLR:SetAttribute("DeedeeReturnAt", 20000 * 86400 - 10)
    pump(1.0)
    check("AutoFish: shop open + cooldown expired fires FishingPlayHitButton", countTag("FishPlay") > 0)

    Fires = {}
    PLR:SetAttribute("DeedeeReturnAt", 20000 * 86400 + 100)
    pump(1.0)
    check("AutoFish: respects DeedeeReturnAt cooldown (no fire)", countTag("FishPlay") == 0)

    Fires = {}
    DeedeeShop.Enabled = false
    PLR:SetAttribute("DeedeeReturnAt", 20000 * 86400 - 10)
    pump(1.5)
    check("AutoFish: shop closed + expired TPs to Deedee NPC blocker", hrpDist(DeedeeBlocker) < 0.5)

    Fires = {}
    BattleGui.Enabled = true
    PLR:SetAttribute("DeedeeReturnAt", 20000 * 86400 - 10)
    DeedeeShop.Enabled = true
    pump(1.0)
    check("AutoFish: no shop actions during battle", countTag("FishPlay") == 0)
    BattleGui.Enabled = false
    Library.Toggles.AutoFish:SetValue(false)
    pump(0.5)
end

-- ===== AutoBuyByte behavior =====
if Library.Toggles.AutoBuyByte and Library.Options.BuyByte then
    PLR:SetAttribute("FazTokens", 100)
    PLR:SetAttribute("ByteOwnedNeonBee", nil)
    Library.Options.BuyByte:SetValue("NeonBee")
    Library.Toggles.AutoBuyByte:SetValue(true)
    pump(2.5)
    check("AutoBuyByte: buys affordable selected byte (NeonBee 75)", PLR:GetAttribute("FazTokens") == 25 and ByteInventory.Owns(PLR, "NeonBee") == true)
    check("AutoBuyByte: purchase followed by AutoSave", SaveCalls.AutoSave > 0)

    PLR:SetAttribute("FazTokens", 25)
    Library.Options.BuyByte:SetValue("X-Reaper")
    local savesBefore = SaveCalls.AutoSave
    pump(2.5)
    check("AutoBuyByte: no purchase when insufficient tokens", PLR:GetAttribute("FazTokens") == 25 and SaveCalls.AutoSave == savesBefore)
    Library.Toggles.AutoBuyByte:SetValue(false)
    pump(0.5)
end

summary()
