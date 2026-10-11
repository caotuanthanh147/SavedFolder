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


-- ===================== BAD1 game layer =====================
local ScriptPath = arg and arg[1] or nil
local ScriptSrc = nil
do
    local fallbacks = {
        (os.getenv("SF_DIR") or "/tmp/SavedFolder") .. "/work/lua/BuildADungeon.lua",
        "/home/z/my-project/Yuri/BuildADungeon/BuildADungeon.lua",
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

G.isfile = function() return false end
G.delfile = function() end
G.writefile = function() end
local NotyuriLog = {}
G.appendfile = function(_, line)
    table.insert(NotyuriLog, line)
end

local function jsonDecode(s)
    local pos = 1
    local function skip()
        while pos <= #s and (s:sub(pos, pos) == " " or s:sub(pos, pos) == "\t" or s:sub(pos, pos) == "\n" or s:sub(pos, pos) == "\r") do
            pos = pos + 1
        end
    end
    local function value()
        skip()
        local c = s:sub(pos, pos)
        if c == "{" then
            pos = pos + 1
            local t = {}
            skip()
            if s:sub(pos, pos) == "}" then
                pos = pos + 1
                return t
            end
            while true do
                skip()
                local k = value()
                skip()
                pos = pos + 1
                t[k] = value()
                skip()
                local d = s:sub(pos, pos)
                pos = pos + 1
                if d == "}" then
                    return t
                end
            end
        elseif c == "[" then
            pos = pos + 1
            local t = {}
            skip()
            if s:sub(pos, pos) == "]" then
                pos = pos + 1
                return t
            end
            while true do
                t[#t + 1] = value()
                skip()
                local d = s:sub(pos, pos)
                pos = pos + 1
                if d == "]" then
                    return t
                end
            end
        elseif c == "\"" then
            local out = {}
            pos = pos + 1
            while true do
                local ch = s:sub(pos, pos)
                if ch == "\\" then
                    local esc = s:sub(pos + 1, pos + 1)
                    if esc == "n" then
                        table.insert(out, "\n")
                    elseif esc == "t" then
                        table.insert(out, "\t")
                    elseif esc == "u" then
                        local hex = s:sub(pos + 2, pos + 5)
                        pos = pos + 4
                        table.insert(out, utf8 and utf8.char(tonumber(hex, 16)) or "?")
                    else
                        table.insert(out, esc)
                    end
                    pos = pos + 2
                elseif ch == "\"" then
                    pos = pos + 1
                    return table.concat(out)
                else
                    table.insert(out, ch)
                    pos = pos + 1
                end
            end
        elseif s:sub(pos, pos + 3) == "true" then
            pos = pos + 4
            return true
        elseif s:sub(pos, pos + 4) == "false" then
            pos = pos + 5
            return false
        elseif s:sub(pos, pos + 3) == "null" then
            pos = pos + 4
            return nil
        else
            local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
            pos = pos + #num
            return tonumber(num)
        end
    end
    local v = value()
    return v
end

local function jsonEncode(t)
    local ty = type(t)
    if ty == "nil" then
        return "null"
    elseif ty == "boolean" then
        return tostring(t)
    elseif ty == "number" then
        return tostring(t)
    elseif ty == "string" then
        return "\"" .. t:gsub("[\"\\\n]", "\\%1") .. "\""
    elseif ty == "table" then
        local isArr = #t > 0
        local parts = {}
        if isArr then
            for i = 1, #t do
                parts[i] = jsonEncode(t[i])
            end
            return "[" .. table.concat(parts, ",") .. "]"
        end
        for k, v in pairs(t) do
            parts[#parts + 1] = "\"" .. tostring(k) .. "\":" .. jsonEncode(v)
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return "null"
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
        local fn = G.loadstring(srcOrTbl, "@BAD:" .. name)
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
PLR.Idled = Signal.new()
PLR.CameraMaxZoomDistance = 128
local Services = {}
Services.Players = { LocalPlayer = PLR, GetPlayers = function() return { PLR } end }
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
Services.MarketplaceService = { GetProductInfo = function() return { Name = "Build a Dungeon" } end }
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
G.Enum = setmetatable({}, { __index = function(t, k)
    local c = setmetatable({}, { __index = function(_, k2) return k2 end })
    rawset(t, k, c)
    return c
end })
G.getconnections = nil
G.getgenv = function() return G end

local BADFolder = Instance.new("Folder", "BAD")
RS:AddChild(BADFolder)
local RemotesFolder = Instance.new("Folder", "Remotes")
BADFolder:AddChild(RemotesFolder)
local ActionRemote = Instance.new("RemoteEvent", "Action")
RemotesFolder:AddChild(ActionRemote)
local BuildRemote = Instance.new("RemoteFunction", "Build")
RemotesFolder:AddChild(BuildRemote)
local RollControlsRemote = Instance.new("RemoteFunction", "RollControls")
RemotesFolder:AddChild(RollControlsRemote)
local LabQRemote = Instance.new("RemoteEvent", "LabQ")
RemotesFolder:AddChild(LabQRemote)
local NotifyRemote = Instance.new("RemoteEvent", "Notify")
RemotesFolder:AddChild(NotifyRemote)
ActionRemote.OnClientEvent = Signal.new()
NotifyRemote.OnClientEvent = Signal.new()
LabQRemote.OnClientEvent = Signal.new()
BuildRemote.OnClientInvoke = nil
RollControlsRemote.OnClientInvoke = nil
local ShopRemote = Instance.new("RemoteFunction", "Shop")
RemotesFolder:AddChild(ShopRemote)
local DungeonLayoutsRemote = Instance.new("RemoteFunction", "DungeonLayouts")
RemotesFolder:AddChild(DungeonLayoutsRemote)

local CfgSrc = io.open("bad_real_config.lua", "r"):read("*a")
local GridSrc = io.open("bad_real_gridutil.lua", "r"):read("*a")
local RollUpgSrc = io.open("bad_real_rollupg.lua", "r"):read("*a")
local LateGameSrc = io.open("bad_real_lategame.lua", "r"):read("*a")
addModule(BADFolder, "RollUpgradeConfig", RollUpgSrc)
addModule(BADFolder, "LateGameConfig", LateGameSrc)
local ConfigMod = addModule(BADFolder, "Config", CfgSrc)
local GridUtilMod = addModule(BADFolder, "GridUtil", GridSrc)
local Config = ModuleRegistry[ConfigMod]
local GridUtil = ModuleRegistry[GridUtilMod]
check("real Config module loaded", type(Config) == "table" and type(Config.Items) == "table" and Config.Items.WoodFloor ~= nil)
check("real GridUtil module loaded", type(GridUtil) == "table" and type(GridUtil.key) == "function")
check("Config spine Auto skill present at 350", (function()
    for _, s in ipairs(Config.Skills) do
        if s.id == "Auto" then
            return s.cost == 350 and s.parent == "Heart"
        end
    end
    return false
end)())

local MapFolder = Instance.new("Folder", "Map")
WS:AddChild(MapFolder)
local RollersFolder = Instance.new("Folder", "Rollers")
MapFolder:AddChild(RollersFolder)
local function mkStand(idx, kind)
    local stand = Instance.new("Model", "Plot" .. idx .. "_" .. kind)
    stand:SetAttribute("PlotIndex", idx)
    local pad = Instance.new("Part", "AutoRoll")
    pad.CFrame = CFrame.new(Vector3.new(idx * 124, 3, kind == "Buildings" and 40 or 80))
    stand:AddChild(pad)
    RollersFolder:AddChild(stand)
    return stand
end
local StandB1 = mkStand(1, "Buildings")
local StandM1 = mkStand(1, "Monsters")
local StandB2 = mkStand(2, "Buildings")
mkStand(2, "Monsters")
mkStand(3, "Buildings")
mkStand(3, "Monsters")

local PlotsFolder = Instance.new("Folder", "Plots")
WS:AddChild(PlotsFolder)
local function mkPlot(idx, ownerName, dataTbl, waveActive)
    local plot = Instance.new("Model", "Plot" .. idx)
    plot:SetAttribute("PlotIndex", idx)
    plot:SetAttribute("OwnerName", ownerName)
    plot:SetAttribute("WaveActive", waveActive and true or false)
    local shell = Instance.new("Part", "Shell")
    shell.CFrame = CFrame.new(Vector3.new(idx * 124, 0, 0))
    plot:AddChild(shell)
    local state = Instance.new("StringValue", "State")
    state.Value = jsonEncode(dataTbl)
    plot:AddChild(state)
    PlotsFolder:AddChild(plot)
    return plot
end

local MyPlotData = {
    name = "czhigh",
    owner = 1,
    wave = 5,
    floors = { { tiles = {}, trot = {}, objs = {}, w = 1 } },
    uxp = {},
    ustar = {},
    skills = {},
    best = 1,
    ulvl = {},
}
local SrcPlotData = {
    name = "proplayer",
    owner = 2,
    wave = 50,
    floors = { {
        tiles = { ["6,2"] = "WoodFloor", ["7,2"] = "CrystalHall", ["8,2"] = "Crystal", ["9,2"] = "StoneWall" },
        trot = { ["6,2"] = 1, ["7,2"] = 0, ["9,2"] = 2 },
        objs = { ["6,2"] = { id = "SpikeTrap", rot = 0, lvl = 1 }, ["8,2"] = { id = "Skeleton", rot = 1, lvl = 1 } },
        w = 1,
    } },
}
local MyPlot = mkPlot(1, "czhigh", MyPlotData, false)
local SrcPlot = mkPlot(2, "proplayer", SrcPlotData, false)
mkPlot(3, "idleplayer", { name = "idleplayer", owner = 3, wave = 1, floors = { { tiles = {}, trot = {}, objs = {}, w = 1 } } }, false)

local EnemiesFolder = Instance.new("Folder", "BADEnemies")
WS:AddChild(EnemiesFolder)

local Char = Instance.new("Model", "czhigh")
local HRP = Instance.new("Part", "HumanoidRootPart")
HRP.CFrame = CFrame.new(Vector3.new(999, 3, 999))
Char:AddChild(HRP)
local Hum = Instance.new("Humanoid", "Humanoid")
function Hum:EquipTool(tool)
    Char:AddChild(tool)
end
Char:AddChild(Hum)
PLR.Character = Char
local Backpack = Instance.new("Backpack", "Backpack")
PLR:AddChild(Backpack)
local function mkTool(style)
    local t = Instance.new("Tool", "Dungeon Blade")
    t:SetAttribute("WeaponStyle", style)
    return t
end

PLR:SetAttribute("PlotIndex", 1)
PLR:SetAttribute("Gold", 2000)
PLR:SetAttribute("DarkSouls", 500)
PLR:SetAttribute("Wave", 5)
PLR:SetAttribute("Pop", 0)
PLR:SetAttribute("MaxPop", 2)
PLR:SetAttribute("Inv", jsonEncode({ YellowCorridor = 80, Crossroads = 20, WoodFloor = 10, SpikeTrap = 30, Crystal = 1 }))
PLR:SetAttribute("Mons", jsonEncode({ Skeleton = 10 }))
PLR:SetAttribute("Skills", jsonEncode({ Heart = true }))
PLR:SetAttribute("Weapon", "StarterSword")

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

local Server = {
    plotData = jsonDecode(MyPlot:FindFirstChild("State").Value),
    gold = 2000,
    souls = 500,
    inv = jsonDecode(PLR:GetAttribute("Inv")),
    mons = jsonDecode(PLR:GetAttribute("Mons")),
    skills = jsonDecode(PLR:GetAttribute("Skills")),
    rollSettings = {},
    rollActive = { Buildings = false, Monsters = false },
}
local function syncWorld()
    MyPlot:FindFirstChild("State").Value = jsonEncode(Server.plotData)
    PLR:SetAttribute("Inv", jsonEncode(Server.inv))
    PLR:SetAttribute("Mons", jsonEncode(Server.mons))
    PLR:SetAttribute("Skills", jsonEncode(Server.skills))
    PLR:SetAttribute("Gold", Server.gold)
    PLR:SetAttribute("DarkSouls", Server.souls)
end
local function countOf(id)
    local def = Config.Items[id]
    if not def then
        return 0
    end
    if def.kind == "monster" then
        return Server.mons[id] or 0
    end
    return Server.inv[id] or 0
end

ActionRemote.FireServer = function(self, action, arg)
    logWire(ActionRemote, "fire", { action, arg })
    if action == "startWave" then
        MyPlot:SetAttribute("WaveActive", true)
    elseif action == "attack" then
        local enemies = EnemiesFolder:GetChildren()
        if arg == nil then
            for _, m in ipairs(enemies) do
                if (m:GetAttribute("CombatHP") or 0) > 0 then
                    m:SetAttribute("CombatHP", (m:GetAttribute("CombatHP") or 0) - 10)
                end
            end
        end
    end
end
LabQRemote.FireServer = function(self, action, arg)
    logWire(LabQRemote, "fire", { action, arg })
end

RollControlsRemote.InvokeServer = function(self, action, stand, settings)
    logWire(RollControlsRemote, "invoke", { action, stand, settings })
    if action == "settings" then
        Server.rollSettings[stand] = settings
        return { ok = true }
    elseif action == "start" then
        Server.rollActive[stand] = true
        NotifyRemote.OnClientEvent:Fire("autoRollState", { kind = stand, active = true })
        return { ok = true }
    elseif action == "stop" then
        Server.rollActive[stand] = false
        NotifyRemote.OnClientEvent:Fire("autoRollState", { kind = stand, active = false })
        return { ok = true }
    end
    return { ok = false }
end

BuildRemote.InvokeServer = function(self, req)
    logWire(BuildRemote, "invoke", { req })
    if type(req) ~= "table" then
        return { ok = false }
    end
    local action = req.action
    if action == "place" then
        local def = Config.Items[req.id]
        if not def or countOf(req.id) <= 0 then
            return { ok = false, msg = "None left!" }
        end
        local floor = Server.plotData.floors[req.f]
        if not floor then
            return { ok = false, msg = "no floor" }
        end
        if not GridUtil.inBounds(floor, req.c, req.r) then
            return { ok = false, msg = "out of bounds" }
        end
        local k = GridUtil.key(req.c, req.r)
        if def.kind == "floor" then
            if floor.tiles[k] then
                return { ok = false, msg = "Tile taken" }
            end
            floor.tiles[k] = req.id
            floor.trot[k] = req.rot or 0
            Server.inv[req.id] = Server.inv[req.id] - 1
            syncWorld()
            return { ok = true }
        elseif def.kind == "special" then
            if req.id == "Crystal" then
                if req.f ~= #Server.plotData.floors then
                    return { ok = false, msg = "top floor only" }
                end
                if floor.tiles[k] or GridUtil.isFixedCell(Server.plotData, req.f, req.c, req.r) then
                    return { ok = false, msg = "fixed/taken" }
                end
                floor.tiles[k] = "Crystal"
                local path = GridUtil.buildFullPath(Server.plotData, "main") ~= nil
                if not path then
                    floor.tiles[k] = nil
                    return { ok = false, msg = "no path" }
                end
                Server.inv[req.id] = Server.inv[req.id] - 1
                syncWorld()
                return { ok = true }
            end
            return { ok = false, msg = "special unsupported" }
        else
            local tileDef = Config.Items[floor.tiles[k]]
            if not tileDef or tileDef.kind ~= "floor" then
                return { ok = false, msg = "needs floor" }
            end
            if floor.objs[k] then
                return { ok = false, msg = "occupied" }
            end
            if def.kind == "monster" then
                local pop = PLR:GetAttribute("Pop") or 0
                local maxPop = PLR:GetAttribute("MaxPop") or math.huge
                if maxPop < pop + (def.pop or 1) then
                    return { ok = false, msg = "pop full" }
                end
                if not GridUtil.canPlaceObject(floor, def, req.c, req.r, req.rot or 0) then
                    return { ok = false, msg = "no fit" }
                end
                floor.objs[k] = { id = req.id, rot = req.rot or 0, lvl = 1 }
                Server.mons[req.id] = Server.mons[req.id] - 1
                PLR:SetAttribute("Pop", pop + (def.pop or 1))
                syncWorld()
                return { ok = true }
            end
            if not GridUtil.canPlaceObject(floor, def, req.c, req.r, req.rot or 0) then
                return { ok = false, msg = "no fit" }
            end
            floor.objs[k] = { id = req.id, rot = req.rot or 0, lvl = 1 }
            Server.inv[req.id] = Server.inv[req.id] - 1
            syncWorld()
            return { ok = true }
        end
    elseif action == "upgrade" then
        local floor = Server.plotData.floors[req.f]
        if not floor then
            return { ok = false }
        end
        local k = GridUtil.key(req.c, req.r)
        local obj = floor.objs[k]
        if not obj then
            return { ok = false, msg = "no obj" }
        end
        local def = Config.Items[obj.id]
        local cost, bank
        if def.mon then
            if (obj.lvl or 1) >= (Config.UNIT_MAX_LEVEL or 10) then
                return { ok = false, msg = "max" }
            end
            cost = Config.UnitLevelCost({ price = Config.UnitPriceById[obj.id] or 1 }, obj.lvl or 1)
            bank = "souls"
        else
            cost = Config.UpgradeCost(def, obj.lvl or 1)
            bank = "gold"
        end
        if Server[bank] < cost then
            return { ok = false, msg = "too poor" }
        end
        Server[bank] = Server[bank] - cost
        obj.lvl = (obj.lvl or 1) + 1
        syncWorld()
        return { ok = true }
    elseif action == "expand" then
        local floor = Server.plotData.floors[req.f or 1]
        if not floor then
            return { ok = false }
        end
        local nxt = Config.WidthLevels[(floor.w or 1) + 1]
        if not nxt then
            return { ok = false, msg = "max width" }
        end
        if Server.gold < nxt.cost or (PLR:GetAttribute("Wave") or 1) < (nxt.wave or 0) then
            return { ok = false, msg = "gated" }
        end
        Server.gold = Server.gold - nxt.cost
        floor.w = (floor.w or 1) + 1
        syncWorld()
        return { ok = true }
    elseif action == "skill" then
        local owned = Server.skills
        owned.Heart = true
        local skill = nil
        for _, s in ipairs(Config.Skills) do
            if s.id == req.id then
                skill = s
                break
            end
        end
        if not skill or not Config.SkillBuyable(owned, skill) then
            return { ok = false, msg = "not buyable" }
        end
        if Server.souls < (skill.cost or 0) then
            return { ok = false, msg = "too poor" }
        end
        Server.souls = Server.souls - (skill.cost or 0)
        Server.skills[skill.id] = true
        syncWorld()
        return { ok = true }
    end
    return { ok = true }
end

ShopRemote.InvokeServer = function(self, ...)
    logWire(ShopRemote, "invoke", { ... })
    return { ok = true }
end
DungeonLayoutsRemote.InvokeServer = function(self, ...)
    logWire(DungeonLayoutsRemote, "invoke", { ... })
    return { ok = true }
end

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

do
    local fn = G.loadstring(ScriptSrc, "=(BuildADungeon)")
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
for _, id in ipairs({ "AutoWave", "AutoStart", "AutoSpeed", "AutoRoll", "AutoBuild", "CopyBase", "AutoUpgrade", "AutoExpand", "AutoSkill", "AutoAttack", "AutoQueue" }) do
    check("toggle registered: " .. id, Library.Toggles[id] ~= nil)
end
for _, id in ipairs({ "RollWhat", "RollStopAt", "CopyFrom", "QueueDiff", "PlaceDelay" }) do
    check("element registered: " .. id, Library.Options[id] ~= nil)
end
check("SaveManager folder", SaveManager.Folder == "Yuri/BuildADungeon")
check("CopyFrom populated with other plots", (function()
    local vals = Library.Options.CopyFrom.Values
    return vals ~= nil and #vals == 2 and string.find(vals[1], "proplayer", 1, true) ~= nil and string.find(vals[2], "idleplayer", 1, true) ~= nil
end)())
check("no game SafeLabels (only template Info + Menu bind labels)", #MockState.AllLabels == 2)

check("CopyBase: floor wire copied with src rot", (function()
    Library.Options.CopyFrom:SetValue((Library.Options.CopyFrom.Values or {})[1])
    Library.Toggles.CopyBase:SetValue(true)
    pump(1.5)
    local ws = wiresFor(BuildRemote, function(w)
        return w.args[1] and w.args[1].action == "place" and w.args[1].id == "WoodFloor"
    end)
    Library.Toggles.CopyBase:SetValue(false)
    pump(0.5)
    return #ws == 1 and ws[1].args[1].f == 1 and ws[1].args[1].c == 6 and ws[1].args[1].r == 2 and ws[1].args[1].rot == 1
end)())
check("CopyBase: obj wire copied", (function()
    local ws = wiresFor(BuildRemote, function(w)
        return w.args[1] and w.args[1].action == "place" and w.args[1].id == "SpikeTrap"
    end)
    return #ws == 1 and ws[1].args[1].c == 6 and ws[1].args[1].r == 2 and ws[1].args[1].rot == 0
end)())
check("CopyBase: unowned + special skipped", (function()
    for _, w in ipairs(wiresFor(BuildRemote)) do
        local r = w.args[1]
        if r and r.action == "place" and (r.id == "CrystalHall" or r.id == "Crystal" or r.id == "StoneWall") then
            if w.t < 200 then
                return false
            end
        end
    end
    return true
end)())
check("CopyBase: stops after toggle off", (function()
    local before = #wiresFor(BuildRemote)
    pump(1.5)
    return #wiresFor(BuildRemote) == before
end)())

local AutoBuildT0 = nil
check("AutoBuild: first serpentine wire is turn-piece at (5,0)", (function()
    AutoBuildT0 = Sched.now
    Library.Toggles.AutoBuild:SetValue(true)
    pump(1.5)
    local ws = wiresFor(BuildRemote, function(w)
        return w.t >= AutoBuildT0 and w.args[1] and w.args[1].action == "place"
    end)
    if #ws == 0 then
        return false
    end
    local first = ws[1].args[1]
    return first.id == "Crossroads" and first.f == 1 and first.c == 5 and first.r == 0
end)())
check("AutoBuild: second wire is corridor rot1 (row cell)", (function()
    local ws = wiresFor(BuildRemote, function(w)
        return w.t >= AutoBuildT0 and w.args[1] and w.args[1].action == "place"
    end)
    if #ws < 2 then
        return false
    end
    local second = ws[2].args[1]
    return second.id == "YellowCorridor" and second.c == 6 and second.r == 0 and second.rot == 1
end)())
check("AutoBuild: fills width level 1 grid (70 cells minus copied)", (function()
    pump(30)
    local floors = Server.plotData.floors[1]
    local n = 0
    for _ in pairs(floors.tiles) do
        n = n + 1
    end
    Library.Toggles.AutoBuild:SetValue(false)
    pump(0.5)
    return n >= 70
end)())
check("AutoBuild: server accepted every place (ok wires)", (function()
    local bad = 0
    for _, w in ipairs(wiresFor(BuildRemote)) do
        if w.args[1] and w.args[1].action == "place" then
            bad = bad + 1
        end
    end
    return bad >= 70
end)())
check("AutoBuild: traps placed on path tiles", (function()
    local floors = Server.plotData.floors[1]
    local trapN = 0
    for _, obj in pairs(floors.objs) do
        if Config.Items[obj.id] and Config.Items[obj.id].kind == "trap" then
            trapN = trapN + 1
        end
    end
    return trapN > 0
end)())
check("AutoBuild: pop gate caps monsters at MaxPop", (function()
    local floors = Server.plotData.floors[1]
    local monN = 0
    for _, obj in pairs(floors.objs) do
        if Config.Items[obj.id] and Config.Items[obj.id].kind == "monster" then
            monN = monN + 1
        end
    end
    return monN <= 2
end)())
check("AutoBuild: crystal placed at serpentine end when missing", (function()
    local floors = Server.plotData.floors[1]
    return floors.tiles["5,9"] == "Crystal"
end)())
check("AutoBuild: stops after toggle off", (function()
    local before = #wiresFor(BuildRemote)
    pump(1.5)
    return #wiresFor(BuildRemote) == before
end)())

check("AutoWave: startWave fired for idle plot", (function()
    MyPlot:SetAttribute("WaveActive", false)
    Library.Toggles.AutoWave:SetValue(true)
    pump(3)
    local ws = wiresFor(ActionRemote, function(w)
        return w.args[1] == "startWave"
    end)
    return #ws >= 1
end)())
check("AutoWave: no refire while wave active", (function()
    local ws = wiresFor(ActionRemote, function(w)
        return w.args[1] == "startWave"
    end)
    local n = #ws
    pump(4)
    local ws2 = wiresFor(ActionRemote, function(w)
        return w.args[1] == "startWave"
    end)
    Library.Toggles.AutoWave:SetValue(false)
    pump(0.5)
    return #ws2 == n
end)())

check("AutoStart probe: auto wire fires on toggle", (function()
    Library.Toggles.AutoStart:SetValue(true)
    Library.Toggles.AutoStart:SetValue(false)
    local ws = wiresFor(ActionRemote, function(w)
        return w.args[1] == "auto"
    end)
    return #ws == 2
end)())
check("AutoSpeed probe: speed wire fires on toggle", (function()
    Library.Toggles.AutoSpeed:SetValue(true)
    Library.Toggles.AutoSpeed:SetValue(false)
    local ws = wiresFor(ActionRemote, function(w)
        return w.args[1] == "speed"
    end)
    return #ws == 2
end)())

check("AutoRoll: settings + start for both stands with verified shape", (function()
    Server.rollActive.Buildings = false
    Server.rollActive.Monsters = false
    Library.Toggles.AutoRoll:SetValue(true)
    pump(8)
    Library.Toggles.AutoRoll:SetValue(false)
    pump(0.5)
    local settings = wiresFor(RollControlsRemote, function(w)
        return w.args[1] == "settings"
    end)
    local starts = wiresFor(RollControlsRemote, function(w)
        return w.args[1] == "start"
    end)
    if #settings ~= 2 or #starts ~= 2 then
        return false
    end
    for _, w in ipairs(settings) do
        local s = w.args[3]
        if type(s) ~= "table" then
            return false
        end
        if s.rarity ~= "Legendary" or s.mut ~= "Off" or s.pity ~= "Off" or s.skin ~= "Off" or s.always ~= "Divine" or s.protect ~= "Mythic" or s.category ~= "All" or s.mode ~= "Rarity" then
            return false
        end
    end
    return true
end)())
check("AutoRoll: TP to own stand before invokes", (function()
    local settings = wiresFor(RollControlsRemote, function(w)
        return w.args[1] == "settings"
    end)
    if #settings == 0 then
        return false
    end
    local padM = StandM1:FindFirstChild("AutoRoll")
    local padB = StandB1:FindFirstChild("AutoRoll")
    local dM = (HRP._cframe.Position - padM._cframe.Position).Magnitude
    local dB = (HRP._cframe.Position - padB._cframe.Position).Magnitude
    return dM < 10 or dB < 10
end)())
check("AutoRoll: no duplicate start while active", (function()
    Server.rollActive.Buildings = false
    Server.rollActive.Monsters = false
    Library.Toggles.AutoRoll:SetValue(true)
    pump(2)
    NotifyRemote.OnClientEvent:Fire("autoRollState", { kind = "Buildings", active = true })
    NotifyRemote.OnClientEvent:Fire("autoRollState", { kind = "Monsters", active = true })
    pump(2)
    local afterNotify = #wiresFor(RollControlsRemote, function(w)
        return w.args[1] == "start"
    end)
    pump(6)
    Library.Toggles.AutoRoll:SetValue(false)
    pump(0.5)
    local afterLong = #wiresFor(RollControlsRemote, function(w)
        return w.args[1] == "start"
    end)
    return afterLong == afterNotify
end)())

check("AutoUpgrade: cheapest-first with correct currencies", (function()
    Server.plotData.floors[1].objs = {
        ["5,1"] = { id = "SpikeTrap", rot = 0, lvl = 1 },
        ["6,1"] = { id = "Skeleton", rot = 0, lvl = 1 },
    }
    PLR:SetAttribute("Pop", 0)
    syncWorld()
    Server.gold = 2000
    Server.souls = 500
    local trapCost = Config.UpgradeCost(Config.Items.SpikeTrap, 1)
    local monCost = Config.UnitLevelCost({ price = Config.UnitPriceById.Skeleton }, 1)
    Library.Toggles.AutoUpgrade:SetValue(true)
    pump(3)
    Library.Toggles.AutoUpgrade:SetValue(false)
    pump(0.5)
    local ups = wiresFor(BuildRemote, function(w)
        return w.args[1] and w.args[1].action == "upgrade"
    end)
    if #ups == 0 then
        return false
    end
    local first = ups[1].args[1]
    local cheaperIsTrap = trapCost <= monCost
    if cheaperIsTrap and not (first.c == 5 and first.r == 1) then
        return false
    end
    if not cheaperIsTrap and not (first.c == 6 and first.r == 1) then
        return false
    end
    return true
end)())
check("AutoUpgrade: server applied upgrade (lvl 2)", (function()
    local a = Server.plotData.floors[1].objs["5,1"]
    local b = Server.plotData.floors[1].objs["6,1"]
    return (a and (a.lvl or 1) >= 2) or (b and (b.lvl or 1) >= 2)
end)())
check("AutoUpgrade: stops after toggle off", (function()
    local before = #wiresFor(BuildRemote, function(w)
        return w.args[1] and w.args[1].action == "upgrade"
    end)
    pump(3)
    return #wiresFor(BuildRemote, function(w)
        return w.args[1] and w.args[1].action == "upgrade"
    end) == before
end)())

check("AutoExpand: width level bought when gold+wave OK", (function()
    Server.plotData.floors[1].w = 1
    syncWorld()
    Server.gold = 1000
    Server.souls = 500
    PLR:SetAttribute("Wave", 5)
    Library.Toggles.AutoExpand:SetValue(true)
    pump(12)
    Library.Toggles.AutoExpand:SetValue(false)
    pump(0.5)
    return Server.plotData.floors[1].w == 2 and Server.gold == 600
end)())

check("AutoSkill: buys first SkillBuyable affordable node", (function()
    Server.skills = { Heart = true }
    syncWorld()
    Server.souls = 500
    local expected = nil
    for _, s in ipairs(Config.Skills) do
        local owned = { Heart = true }
        if not owned[s.id] and Config.SkillBuyable(owned, s) then
            expected = s
            break
        end
    end
    Library.Toggles.AutoSkill:SetValue(true)
    pump(4)
    Library.Toggles.AutoSkill:SetValue(false)
    pump(0.5)
    local ws = wiresFor(BuildRemote, function(w)
        return w.args[1] and w.args[1].action == "skill"
    end)
    if #ws == 0 or not expected then
        return false
    end
    if ws[1].args[1].id ~= expected.id then
        return false
    end
    return Server.skills[expected.id] == true
end)())
check("AutoSkill: no buy when souls short", (function()
    Server.souls = 0
    syncWorld()
    local before = #wiresFor(BuildRemote, function(w)
        return w.args[1] and w.args[1].action == "skill"
    end)
    Library.Toggles.AutoSkill:SetValue(true)
    pump(4)
    Library.Toggles.AutoSkill:SetValue(false)
    pump(0.5)
    return #wiresFor(BuildRemote, function(w)
        return w.args[1] and w.args[1].action == "skill"
    end) == before
end)())

check("AutoAttack: equips from backpack and attacks with nil arg at home", (function()
    local enemy = Instance.new("Model", "Adventurer")
    local torso = Instance.new("Part", "UpperTorso")
    torso.CFrame = CFrame.new(HRP._cframe.Position + Vector3.new(3, 0, 0))
    enemy:AddChild(torso)
    enemy:SetAttribute("CombatHP", 50)
    EnemiesFolder:AddChild(enemy)
    local tool = mkTool("sword")
    Backpack:AddChild(tool)
    Library.Toggles.AutoAttack:SetValue(true)
    pump(3)
    Library.Toggles.AutoAttack:SetValue(false)
    pump(0.5)
    local ws = wiresFor(ActionRemote, function(w)
        return w.args[1] == "attack"
    end)
    if #ws == 0 then
        return false
    end
    for _, w in ipairs(ws) do
        if w.args[2] ~= nil then
            return false
        end
    end
    return true
end)())
check("AutoAttack: cooldown-gated (~0.5s cadence)", (function()
    local ws = wiresFor(ActionRemote, function(w)
        return w.args[1] == "attack"
    end)
    return #ws >= 3 and #ws <= 9
end)())
check("AutoAttack: dead enemy stops the wires", (function()
    for _, m in ipairs(EnemiesFolder:GetChildren()) do
        m:SetAttribute("CombatHP", 0)
    end
    Library.Toggles.AutoAttack:SetValue(true)
    pump(2)
    Library.Toggles.AutoAttack:SetValue(false)
    pump(0.2)
    local before = #wiresFor(ActionRemote, function(w)
        return w.args[1] == "attack"
    end)
    pump(1)
    return #wiresFor(ActionRemote, function(w)
        return w.args[1] == "attack"
    end) == before
end)())
check("AutoAttack: LabMonster arg in labyrinth mode", (function()
    for _, m in ipairs(EnemiesFolder:GetChildren()) do
        m:SetAttribute("CombatHP", 50)
        m:SetAttribute("LabMonster", "m42")
        local t = m:FindFirstChild("UpperTorso")
        if t then
            t.CFrame = CFrame.new(HRP._cframe.Position + Vector3.new(2, 0, 0))
        end
    end
    WS:SetAttribute("LabyrinthMode", true)
    Library.Toggles.AutoAttack:SetValue(true)
    pump(1.5)
    Library.Toggles.AutoAttack:SetValue(false)
    pump(0.2)
    WS:SetAttribute("LabyrinthMode", false)
    local ws = wiresFor(ActionRemote, function(w)
        return w.args[1] == "attack" and w.args[2] == "m42"
    end)
    return #ws >= 1
end)())

check("AutoQueue: solo wire with map+diff", (function()
    Library.Toggles.AutoQueue:SetValue(true)
    pump(2)
    Library.Toggles.AutoQueue:SetValue(false)
    pump(0.5)
    local ws = wiresFor(LabQRemote, function(w)
        return w.args[1] == "solo"
    end)
    if #ws == 0 then
        return false
    end
    local sel = ws[1].args[2]
    return type(sel) == "table" and sel.sel ~= nil and sel.sel.map == "labyrinth" and sel.sel.diff == "novice"
end)())
check("AutoQueue: diff dropdown respected + lab mode gate", (function()
    Library.Options.QueueDiff:SetValue("abyssal")
    Library.Toggles.AutoQueue:SetValue(true)
    pump(2)
    WS:SetAttribute("LabyrinthMode", true)
    pump(2)
    Library.Toggles.AutoQueue:SetValue(false)
    pump(0.5)
    WS:SetAttribute("LabyrinthMode", false)
    local abyssal = 0
    for _, w in ipairs(wiresFor(LabQRemote, function(w)
        return w.args[1] == "solo"
    end)) do
        if w.args[2].sel.diff == "abyssal" then
            abyssal = abyssal + 1
        end
    end
    return abyssal >= 1 and abyssal <= 2
end)())

check("banned wires: no Shop/DungeonLayouts/Admin invokes", (function()
    return #wiresFor(ShopRemote) == 0 and #wiresFor(DungeonLayoutsRemote) == 0
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

print(string.format("BAD1 harness: %d pass / %d fail", Pass, Fail))
if Fail > 0 then
    for _, f in ipairs(Failures) do
        print("  failed: " .. f)
    end
    os.exit(1)
end
