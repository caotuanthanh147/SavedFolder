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


-- ####################################################################
-- ===== POTATO HARNESS — POT1 (glm1, 2026-10-04) =======================
-- Mock world from work/lua/potato-analysis.md (all semantics deobf-verified):
--   Packet transport (RS.ModifiedPackages.Packet single-RemoteEvent buffer mux; wire table
--   RS.Modules.Resources.Packets, client Fires / OnClientEvent listens)
--   pile state via PotatoPileShared.CreatePile/RemovePotato + PotatoPileSynced/PotatoesPicked/
--   PotatoRemoved/PotatoKeyMoved syncs; kinds via PotatoKindShared.Kinds; peeling session via
--   PeelingStarted/NextPotato/Stopped + crate-top session potato; ToolEquipController singleton
--   (Equip/Use/HasCharge/IsOverheated); store/machine purchases via Price-part ProximityPrompts;
--   ToolUpgradeShared/LobbyUpgradeShared cost trees; ClassShared roll+IsStoppedAt.
-- REAL-LOAD: io.open + loadstring + task.spawn of work/lua/Potato.lua.
-- ####################################################################

local function summary()
    print(string.format("POT1 harness: %d pass / %d fail", Pass, Fail))
    if Fail > 0 then
        for _, f in ipairs(Failures) do
            print("  failed: " .. f)
        end
        os.exit(1)
    end
end

local ScriptPath = (arg and arg[1]) or "/home/z/SavedFolder/work/lua/Potato.lua"

local oldLoadstring = G.loadstring
G.loadstring = function(src, name)
    if src == "LIB" then return function() return Library end end
    if src == "THEME" then return function() return ThemeManager end end
    if src == "SAVE" then return function() return SaveManager end end
    return oldLoadstring(src, name)
end

local MockFS = {}
G.writefile = function(p, c) MockFS[p] = c end
G.readfile = function(p) return MockFS[p] end
G.isfile = function(p) return MockFS[p] ~= nil end
G.isfolder = function() return true end
G.makefolder = function() end
G.listfiles = function() return {} end
G.listfolder = G.listfiles
G.appendfile = function(p, c) MockFS[p] = (MockFS[p] or "") .. c end
G.delfile = function(p) MockFS[p] = nil end
G.queue_on_teleport = function() end
G.queueonteleport = G.queue_on_teleport
G.request = function() return { Success = true } end
G.http_request = G.request
G.setfpscap = function() end
G.getfpscap = function() return 60 end
G.identifyexecutor = function() return "HarnessLua54" end

local PromptFires = {}
G.fireproximityprompt = function(prompt)
    table.insert(PromptFires, prompt)
end
G.fireclickdetector = function() end
G.firetouchinterest = function() end

-- ===== players / character / workspace =====
local PLR = { Name = "glm1_test", UserId = 424242, Character = nil, Backpack = {},
    CameraMaxZoomDistance = 128, ChildAdded = Signal.new(), CharacterAdded = Signal.new(), Idled = Signal.new() }

local WS = Instance.new("Folder", "Workspace")
local character = Instance.new("Model", "glm1_test")
local charRoot = Instance.new("Part", "HumanoidRootPart")
charRoot.Position = Vector3.new(0, 3, 0)
local humanoid = Instance.new("Humanoid", "Humanoid")
character:AddChild(charRoot)
character:AddChild(humanoid)
character.PrimaryPart = charRoot
PLR.Character = character
WS:AddChild(character)

local function makeRecursive(inst)
    local orig = inst.FindFirstChild
    inst.FindFirstChild = function(self, name, recursive)
        local direct = orig(self, name)
        if direct or not recursive then return direct end
        for _, c in ipairs(self:GetDescendants()) do
            if c.Name == name then return c end
        end
        return nil
    end
end
makeRecursive(WS)

-- ===== packet mock =====
local PacketFires = {}
local function packet(name)
    local p = { Name = name, OnClientEvent = Signal.new() }
    function p:Fire(...)
        table.insert(PacketFires, { name = name, args = table.pack(...) })
    end
    return p
end
local Packets = {}
local PacketNames = { "PotatoPick", "ToolSwing", "ToolEquip", "ToolUsing", "ToolUpgradePurchase",
    "PeelingPeelRemoved", "PeelingFinished", "PeelingCancel", "PeelingSync", "QueueCreate",
    "QueueLeave", "ClassRoll", "ClassStopAt", "LobbyUpgradePurchase", "DailyRewardClaim",
    "GroupRewardClaim", "PotatoPileRequest", "PurchaseProduct", "SetGlobalOverride",
    "ResetGlobalOverride", "StatsRequest", "LeaderboardRequest", "RunReportRequest",
    "PotatoPileSynced", "PotatoesPicked", "PotatoRemoved", "PotatoKeyMoved",
    "PeelingStarted", "PeelingNextPotato", "PeelingStopped", "KeyRevealed",
    "Escaped", "EscapeFailed", "QueueJoined", "QueueLeft", "QueueTeleporting",
    "UpdatePlayerState", "PlayerStateCreated" }
for _, n in ipairs(PacketNames) do
    Packets[n] = packet(n)
end
local function pktCount(name, pred)
    local n = 0
    for _, c in ipairs(PacketFires) do
        if c.name == name and (not pred or pred(c)) then n = n + 1 end
    end
    return n
end
local function pktArgs(name, pred)
    for _, c in ipairs(PacketFires) do
        if c.name == name and (not pred or pred(c)) then return c.args end
    end
    return nil
end

-- ===== player state mock =====
local State = {
    Potatoes = 0, CarryLevel = 1, Cash = 0, RunPeels = 0,
    HasAutoPeeler = false, HasHandPeeler = false, HasKey = false, HasAutoPeel = false,
    _SaveDataLoaded = true,
    Tools = {}, PeelTools = {}, Upgrades = {}, Gamepasses = {},
    SaveData = {
        Diamonds = 0, Class = "Peasant", ClassSlot2 = "", ActiveClassSlot = 1,
        FreeRolls = 0, Rolls = 0, StopAtClass = "", GroupRewardClaimed = false,
        LikedGame = false, DailyRewardDay = 0, DailyRewardClaimDate = 0,
        LobbyUpgrades = {}, Settings = {},
    },
}
local PlayerStateShared = {}
PlayerStateShared.TryGetPlayerState = function() return State end
PlayerStateShared.GetSaveDataAsync = function() return State.SaveData end

-- ===== tool equip controller mock =====
local ToolCtl = { _equipped = "Hand" }
ToolCtl.GetEquippedTool = function() return ToolCtl._equipped end
ToolCtl.GetEquippedUpgrades = function() return State.Upgrades end
ToolCtl.GetClassId = function() return State.SaveData.Class end
ToolCtl.OwnsTool = function(id)
    if id == "Hand" then return true end
    return State.Tools[id] == true
end
ToolCtl.CanUseTool = function(id) return ToolCtl.OwnsTool(id) end
ToolCtl.IsOnTrial = function() return false end
ToolCtl.HasCharge = function() return true end
ToolCtl.IsOverheated = function() return false end
ToolCtl.Use = function() Packets.ToolSwing:Fire() end
ToolCtl.Equip = function(id)
    ToolCtl._equipped = id
    Packets.ToolEquip:Fire(id)
end

-- ===== shared module mocks (semantics from deobf) =====
local Kinds = {
    NORMAL = 1, KEY = 5,
    Kinds = {
        { Name = "Normal", Chance = 0, Multiplier = 1 },
        { Name = "Golden", Chance = 0.02, Multiplier = 3 },
        { Name = "Diamond", Chance = 0.008, Multiplier = 6 },
        { Name = "Rainbow", Chance = 0.002, Multiplier = 10 },
        { Name = "Key", Chance = 0, Multiplier = 1 },
    },
}

local Pile = {}
Pile.CreatePile = function(seed)
    local slots, ids = {}, {}
    for i = 1, 12 do slots[i] = i; ids[i] = i end
    return { Seed = seed, Slots = slots, Ids = ids, KeyPotatoId = 0 }
end
Pile.SetKeyPotato = function(st, k) st.KeyPotatoId = k end
Pile.RemovePotato = function(st, id)
    local slot = st.Ids[id]
    if not slot then return {} end
    st.Slots[slot] = nil
    st.Ids[id] = nil
    return {}
end
Pile.ForEachSlot = function(fn)
    for slot = 1, 12 do fn(slot) end
end
Pile.GetPotatoInSlot = function(st, slot) return st.Slots[slot] end
Pile.GetPotatoSlot = function(st, id) return st.Ids[id] end
Pile.IsExposed = function(st, id)
    local slot = st.Ids[id]
    return slot ~= nil and slot <= 6
end
Pile.IsKeyPotato = function(st, id) return id == st.KeyPotatoId end
Pile.IsDiamond = function(st, id) return id == 6 end
Pile.GetKind = function(st, id)
    if id == st.KeyPotatoId then return 5 end
    if id == 3 then return 2 end
    if id == 4 then return 4 end
    return 1
end

local ToolsShared = {}
ToolsShared.HAND = "Hand"
ToolsShared.SHOVEL = "Shovel"
ToolsShared.POTATO_SUCKER = "PotatoSucker"
ToolsShared.BODY = "Body"
ToolsShared.WALK_SPEED = "WalkSpeed"
ToolsShared.POTATO_WORTH = "PotatoWorth"
ToolsShared.PICK_SPEED = "PickSpeed"
ToolsShared.HAND_PEELER = "HandPeeler"
ToolsShared.AUTO_PEELER = "AutoPeeler"
ToolsShared.Tools = {
    { Id = "Hand", Name = "Hand", Upgrades = { { Id = "PickSpeed", Costs = { 0.05, 0.4 }, Values = { 1.3, 1.05 } } } },
    { Id = "Shovel", Name = "Shovel", Price = 3, ItemName = "Shovel", Upgrades = { { Id = "PickSpeed", Costs = { 1, 1.8 }, Values = { 1.2, 1.05 } } } },
    { Id = "PotatoSucker", Name = "P0T4T0-3000", Price = 30, ItemName = "P0T4T0-3000", Upgrades = { { Id = "PickAmount", Costs = { 2.1, 3.5 }, Values = { 5, 6 } } } },
}
ToolsShared.Body = { Id = "Body", Name = "General", Upgrades = {
    { Id = "WalkSpeed", Costs = { 0.3, 0.55 }, Values = { 16, 18 } },
    { Id = "PotatoWorth", Costs = { 1, 2.1 }, Values = { 0, 10 } },
} }
ToolsShared.Machines = { { Id = "HandPeeler", Upgrades = { { Id = "Cranks", Costs = { 3, 5 }, Values = { 3, 2 } } } } }
ToolsShared.GetUpgradeable = function(id)
    if id == ToolsShared.BODY then return ToolsShared.Body end
    for _, t in ipairs(ToolsShared.Tools) do
        if t.Id == id then return { Id = t.Id, Name = t.Name, Upgrades = t.Upgrades } end
    end
    for _, m in ipairs(ToolsShared.Machines) do
        if m.Id == id then return { Id = m.Id, Name = m.Id, Upgrades = m.Upgrades } end
    end
    return nil
end
ToolsShared.GetUpgrade = function(upgrades, id)
    for _, u in ipairs(upgrades) do
        if u.Id == id then return u end
    end
    return nil
end
ToolsShared.GetLevel = function(upgrades, toolId, upgId)
    return (upgrades or {})[toolId .. "_" .. upgId] or 0
end
ToolsShared.GetNextCost = function(upg, level) return upg.Costs[level + 1] end
ToolsShared.GetPickInterval = function() return 0.3 end
ToolsShared.OwnsTool = function(tools, id)
    if id == ToolsShared.HAND then return true end
    if not tools then return false end
    return tools[id] == true
end

local PeelTools = {}
PeelTools.Tools = {
    { Id = "Spoon", Name = "Spoon", AutoPeelRate = 1, InstantPeel = false },
    { Id = "Knife", Name = "Knife", AutoPeelRate = 1.7, InstantPeel = false, Price = 0.01, ItemName = "Knife" },
    { Id = "SwissKnife", Name = "Swiss Knife", AutoPeelRate = 2.5, InstantPeel = false, Price = 1.5, ItemName = "SwissKnife" },
    { Id = "Peeler", Name = "Peeler", AutoPeelRate = 7, InstantPeel = true, Price = 4, ItemName = "Peeler" },
    { Id = "TriplePeeler", Name = "Triple Peeler", AutoPeelRate = 20, InstantPeel = true, PotatoCount = 3, Price = 25, ItemName = "TriplePeeler" },
}
PeelTools.GetTool = function(id)
    for _, t in ipairs(PeelTools.Tools) do
        if t.Id == id then return t end
    end
    return nil
end
PeelTools.GetBestTool = function() return PeelTools.Tools[1] end
PeelTools.IsOutclassed = function() return false end

local Carry = {}
Carry.Levels = {
    { Name = "Hands", Capacity = 10, Cost = 0 },
    { Name = "Bucket", Capacity = 50, Cost = 0.5, ItemName = "Bucket" },
    { Name = "Potato Sack", Capacity = 125, Cost = 3.5, ItemName = "PotatoSack" },
    { Name = "Mecha-Capsule", Capacity = 450, Cost = 20, ItemName = "MechaCapsule" },
}
Carry.GetPlayerCapacity = function(carryLevel, gamepasses, lobbyUpgrades)
    local level = Carry.Levels[carryLevel] or Carry.Levels[1]
    local bag = (lobbyUpgrades or {}).BagSize or 0
    return level.Capacity + bag * 5
end

local Lobby = {}
Lobby.Upgrades = {
    { Id = "GrabAmount", Costs = { 100, 250 } },
    { Id = "BagSize", Costs = { 100, 250 } },
    { Id = "CashBoost", Costs = { 150, 350 } },
    { Id = "GemBoost", Costs = { 200, 500 } },
}
Lobby.GetLevel = function(lu, id) return (lu or {})[id] or 0 end
Lobby.GetNextCost = function(upg, level) return upg.Costs[level + 1] end

local ClassShared = {}
ClassShared.ROLL_COST = 40
ClassShared.Classes = {
    { Id = "Peasant", Chance = 50 },
    { Id = "Comrade", Chance = 20 },
    { Id = "Digger", Chance = 15 },
    { Id = "Mechanic", Chance = 12.5 },
    { Id = "PotatoExpert", Chance = 2.4 },
    { Id = "Hero", Chance = 0.1 },
}
ClassShared.GetActiveClassId = function(save) return save.Class end
ClassShared.IsStoppedAt = function(currentId, stopId)
    local cur, stop = nil, nil
    for _, c in ipairs(ClassShared.Classes) do
        if c.Id == currentId then cur = c.Chance end
        if c.Id == stopId then stop = c.Chance end
    end
    if not cur or not stop then return false end
    return cur <= stop
end

local DailyShared = { Rewards = { 100, 150, 200, 250, 500, 750, 999 } }
DailyShared.GetToday = function() return 20000 end
DailyShared.GetClaimableDay = function(day, claimDate, today)
    if claimDate == today then return nil end
    if today - claimDate > 1 or #DailyShared.Rewards <= day then return 1 end
    return day + 1
end

local TableShared = {
    MACHINES_FOLDER_NAME = "PeelingMachines",
    INPUT_CRATE_NAME = "PotatoCrate",
    OUTPUT_CRATE_NAME = "SellCrate",
    CRATE_AREA_NAME = "PotatoArea",
    PLACE_PROMPT_NAME = "PlacePrompt",
    SELL_PROMPT_NAME = "SellPrompt",
    LOAD_PROMPT_NAME = "Load",
    CRANK_PROMPT_NAME = "Crank",
    AUTO_PEELER_MACHINE_NAME = "AutoPeelingMachine",
    AUTO_PEELER_ROOT_NAME = "Cube.042",
    HAND_MACHINE_NAME = "PeelingMachine",
    HAND_MACHINE_ROOT_NAME = "Cube.033",
    AUTO_PEELER_COST = 60,
    HAND_PEELER_COST = 10,
}
TableShared.GetCount = function(inst)
    local v = inst:GetAttribute("PotatoCount")
    if type(v) == "number" then return v end
    return 0
end

local StoreShared = {
    FOLDER_NAME = "StoreItems",
    TOOLS_CATEGORY = "Tools",
    STORAGE_CATEGORY = "Storage",
    PEELERS_CATEGORY = "Peelers",
    PRICE_PART_NAME = "Price",
    PROMPT_ATTACHMENT_NAME = "PromptAttachment",
}

local QueueShared = {
    MATCHMAKING_FOLDER_NAME = "MatchmakingZones",
    FindPad = function(zone)
        local pad = zone:FindFirstChild("Part")
        if pad and pad:IsA("BasePart") then return pad end
        return nil
    end,
}

local KeyShared = { KEYHOLE_NAME = "KeyHole" }
local GroupShared = { CLAIM = "Claim", LIKE = "Like", GROUP = "Group" }

-- ===== RS tree + module registry =====
local RS = Instance.new("Folder", "ReplicatedStorage")
local ModulesFolder = Instance.new("Folder", "Modules")
local ResourcesFolder = Instance.new("Folder", "Resources")
local SharedFolder = Instance.new("Folder", "Shared")
local ControllersFolder = Instance.new("Folder", "Controllers")
RS:AddChild(ModulesFolder)
ModulesFolder:AddChild(ResourcesFolder)
RS:AddChild(SharedFolder)
RS:AddChild(ControllersFolder)

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
addModule(ResourcesFolder, "Packets", Packets)
addModule(SharedFolder, "PotatoPileShared", Pile)
addModule(SharedFolder, "PotatoKindShared", Kinds)
addModule(SharedFolder, "ToolUpgradeShared", ToolsShared)
addModule(SharedFolder, "PeelToolShared", PeelTools)
addModule(SharedFolder, "CarryUpgradeShared", Carry)
addModule(SharedFolder, "LobbyUpgradeShared", Lobby)
addModule(SharedFolder, "ClassShared", ClassShared)
addModule(SharedFolder, "DailyRewardShared", DailyShared)
addModule(SharedFolder, "PotatoTableShared", TableShared)
addModule(SharedFolder, "StoreShared", StoreShared)
addModule(SharedFolder, "QueueShared", QueueShared)
addModule(SharedFolder, "KeyShared", KeyShared)
addModule(SharedFolder, "GroupRewardShared", GroupShared)
addModule(SharedFolder, "PlayerStateShared", PlayerStateShared)
addModule(ControllersFolder, "ToolEquipController", ToolCtl)

-- ===== workspace Map tree =====
local Map = Instance.new("Folder", "Map")
WS:AddChild(Map)
local MachinesFolder = Instance.new("Folder", "PeelingMachines")
Map:AddChild(MachinesFolder)

local function mkPart(name, parent, pos)
    local p = Instance.new("Part", name)
    p.Position = pos or Vector3.new(0, 0, 0)
    p.Size = Vector3.new(4, 2, 4)
    parent:AddChild(p)
    return p
end
local function mkPrompt(name, parent)
    local pr = Instance.new("ProximityPrompt", name)
    pr.MaxActivationDistance = 10
    parent:AddChild(pr)
    return pr
end

local PotatoCrate = Instance.new("Folder", "PotatoCrate")
MachinesFolder:AddChild(PotatoCrate)
local inputArea = mkPart("PotatoArea", PotatoCrate, Vector3.new(0, 1, 0))
local placePrompt = mkPrompt("PlacePrompt", inputArea)
local SellCrate = Instance.new("Folder", "SellCrate")
MachinesFolder:AddChild(SellCrate)
local outputArea = mkPart("PotatoArea", SellCrate, Vector3.new(30, 1, 0))
local sellPrompt = mkPrompt("SellPrompt", outputArea)

local AutoMachine = Instance.new("Folder", "AutoPeelingMachine")
MachinesFolder:AddChild(AutoMachine)
local autoRoot = mkPart("Cube.042", AutoMachine, Vector3.new(10, 1, 0))
local autoLoadPrompt = mkPrompt("Load", autoRoot)
local autoPrice = mkPart("Price", AutoMachine, Vector3.new(10, 3, 0))
local autoHolder = Instance.new("Folder", "PromptAttachment")
autoPrice:AddChild(autoHolder)
local autoBuyPrompt = mkPrompt("ProximityPrompt", autoHolder)

local HandMachine = Instance.new("Folder", "PeelingMachine")
MachinesFolder:AddChild(HandMachine)
makeRecursive(HandMachine)
local handRoot = mkPart("Cube.033", HandMachine, Vector3.new(20, 1, 0))
local handLoadPrompt = mkPrompt("Load", handRoot)
local crankPart = mkPart("CrankPromptPart", HandMachine, Vector3.new(20, 2, 2))
local crankPrompt = mkPrompt("Crank", crankPart)
local handPrice = mkPart("Price", HandMachine, Vector3.new(20, 3, 0))
local handHolder = Instance.new("Folder", "PromptAttachment")
handPrice:AddChild(handHolder)
local handBuyPrompt = mkPrompt("ProximityPrompt", handHolder)

local StoreItems = Instance.new("Folder", "StoreItems")
Map:AddChild(StoreItems)
local function mkStoreItem(category, itemName)
    local cat = StoreItems:FindFirstChild(category)
    if not cat then
        cat = Instance.new("Folder", category)
        StoreItems:AddChild(cat)
    end
    local item = Instance.new("Folder", itemName)
    cat:AddChild(item)
    local price = mkPart("Price", item, Vector3.new(0, 2, 0))
    local holder = Instance.new("Folder", "PromptAttachment")
    price:AddChild(holder)
    return mkPrompt("ProximityPrompt", holder)
end
local shovelPrompt = mkStoreItem("Tools", "Shovel")
local suckerPrompt = mkStoreItem("Tools", "P0T4T0-3000")
local bucketPrompt = mkStoreItem("Storage", "Bucket")
local knifePrompt = mkStoreItem("Peelers", "Knife")

local Zones = Instance.new("Folder", "Zones")
Map:AddChild(Zones)
local MatchZones = Instance.new("Folder", "MatchmakingZones")
Zones:AddChild(MatchZones)
local Zone1 = Instance.new("Folder", "1")
MatchZones:AddChild(Zone1)
local zonePad = mkPart("Part", Zone1, Vector3.new(50, 0, 50))

local keyholePart = mkPart("KeyHole", WS, Vector3.new(100, 2, 100))
local keyPrompt = mkPrompt("ProximityPrompt", keyholePart)

-- ===== services / game =====
local Services = {}
Services.Players = { LocalPlayer = PLR, GetPlayers = function() return { PLR } end }
Services.ReplicatedStorage = RS
Services.RunService = { Stepped = Signal.new(), RenderStepped = Signal.new(), Heartbeat = Signal.new(), PostSimulation = Signal.new(), IsServer = function() return false end, IsStudio = function() return false end, IsClient = function() return true end }
Services.TeleportService = { Teleport = function() end }
Services.UserInputService = { TouchEnabled = false, KeyboardEnabled = true, InputBegan = Signal.new() }
Services.HttpService = { JSONEncode = function(_, t) return "{}" end, JSONDecode = function(_, s) return {} end }
Services.TweenService = { Create = function() return { Play = function() end } end, GetValue = function() return 0 end }
Services.Lighting = {}
Services.GuiService = { GetResolution = function() return Vector3.new(1920, 1080, 0) end }
Services.MarketplaceService = { GetProductInfo = function() return { Name = "Peel THE Potato" } end }
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
local Camera = Instance.new("Folder", "Camera")
WS:AddChild(Camera)
G.getconnections = nil

-- ===== session potato helper =====
local function makeSessionPotato(kindSuffix)
    local potato = Instance.new("Model", "SessionPotato" .. (kindSuffix or ""))
    local anchor = inputArea.CFrame * CFrame.new(0, inputArea.Size.Y / 2 + 1, 0)
    potato:PivotTo(anchor)
    for i = 1, 6 do
        local peel = mkPart("Peel", potato, anchor.Position + Vector3.new(0.1 * i, 0.2, 0))
        potato:AddChild(peel)
    end
    WS:AddChild(potato)
    return potato
end

-- ===== mock-world self-checks =====
check("world: 16 modules registered", (function()
    local names = { "Packets", "PotatoPileShared", "PotatoKindShared", "ToolUpgradeShared", "PeelToolShared", "CarryUpgradeShared", "LobbyUpgradeShared", "ClassShared", "DailyRewardShared", "PotatoTableShared", "StoreShared", "QueueShared", "KeyShared", "GroupRewardShared", "PlayerStateShared", "ToolEquipController" }
    local seen = 0
    for _, m in pairs(ModuleRegistry) do seen = seen + 1 end
    return seen == 16 + 0 and #names == 16
end)())
check("world: pile exposed semantics (1-6 exposed, 7-12 buried)", (function()
    local st = Pile.CreatePile(7)
    return Pile.IsExposed(st, 1) and Pile.IsExposed(st, 6) and not Pile.IsExposed(st, 7) and not Pile.IsExposed(st, 12)
end)())
check("world: kind mapping (3=Golden 4=Rainbow 6=diamondSpecial)", (function()
    local st = Pile.CreatePile(7)
    return Kinds.Kinds[Pile.GetKind(st, 3)].Name == "Golden"
        and Kinds.Kinds[Pile.GetKind(st, 4)].Name == "Rainbow"
        and Pile.IsDiamond(st, 6)
end)())

-- ===== loader (real-load: the ACTUAL delivered script) =====
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
    summary()
    os.exit(Fail > 0 and 1 or 0)
end

local function noErrorNotify()
    for _, n in ipairs(MockState.Notifies) do
        if string.find(n, "ERROR", 1, true) then return false, n end
    end
    return true
end

G.os = setmetatable({ clock = G.tick, time = function() return 20000 * 86400 end }, { __index = os })

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
local fn = G.loadstring(ScriptSrc, "=(Potato)")
G.task.spawn(fn)
pump(2.0)

check("script loaded without ERROR notify", (function()
    local ok, n = noErrorNotify()
    if not ok then print("  notify was: " .. tostring(n)) end
    return ok
end)())
check("guard set", G.ayasemiyatongekissazumirisa == true)
check("save folder = Yuri/Potato", SaveManager.Folder == "Yuri/Potato")
check("pcall interceptor: 0 silent swallows at load", PcallSwallows == 0)

-- ===== UI registration =====
check("15 toggles registered", (function()
    local ids = { "AutoPick", "AutoPlace", "AutoLoad", "AutoCrank", "AutoSell", "AutoBuyMachines", "AutoBuyTools", "AutoUpgradeTools", "AutoPeel", "AutoEscape", "AutoQueue", "AutoClassRoll", "AutoLobbyUpgrades", "AutoClaimDaily", "AutoClaimGroup" }
    for _, id in ipairs(ids) do
        if not Library.Toggles[id] then return false, id end
    end
    return true
end)())
check("PickKinds + QueueSize options registered", Library.Options.PickKinds ~= nil and Library.Options.QueueSize ~= nil)
check("PickKinds populated from PotatoKindShared (5 kinds)", (function()
    local dd = Library.Options.PickKinds
    local want = { All = true, Normal = true, Golden = true, Diamond = true, Rainbow = true, Key = true }
    for _, v in ipairs(dd.Values) do
        if not want[v] then return false, v end
        want[v] = nil
    end
    return next(want) == nil
end)())
Library.Options.PickKinds.Value = { All = true }

-- ===== pile sync + AutoPick =====
Library.Toggles.AutoPick:SetValue(true)
pump(1.0)
check("AutoPick: no picks before PotatoPileSynced", pktCount("PotatoPick") == 0)
Packets.PotatoPileSynced.OnClientEvent:Fire(7, {}, 0)
pump(1.2)
check("AutoPick: pile sync enables picking (first exposed id)", (function()
    local a = pktArgs("PotatoPick")
    return a ~= nil and a.n == 1 and a[1] == 1
end)())
check("AutoPick: ToolSwing fired (Use)", pktCount("ToolSwing") >= 1)
Packets.PotatoRemoved.OnClientEvent:Fire(1)
pump(0.8)
check("AutoPick: pile removal shifts target to id 2", (function()
    local a = pktArgs("PotatoPick", function(c) return c.args[1] == 2 end)
    return a ~= nil
end)())
Library.Options.PickKinds:SetValue({ Golden = true })
local pickIdx0 = #PacketFires
pump(0.8)
check("AutoPick: Golden filter picks id 3 only", (function()
    local golden3, wrong = false, 0
    for i = pickIdx0 + 1, #PacketFires do
        local c = PacketFires[i]
        if c.name == "PotatoPick" then
            if c.args[1] == 3 then golden3 = true
            elseif c.args[1] == 2 or c.args[1] == 4 or c.args[1] == 5 then wrong = wrong + 1 end
        end
    end
    return golden3 and wrong == 0
end)())
Library.Options.PickKinds:SetValue({ All = true })
State.Potatoes = 10
pump(0.8)
check("AutoPick: bag full stops normal picks, diamond exempt still picked", (function()
    local diamond = pktCount("PotatoPick", function(c) return c.args[1] == 6 end)
    local normal = pktCount("PotatoPick", function(c) return c.args[1] == 4 or c.args[1] == 5 end)
    return diamond >= 1 and normal == 0
end)())
State.Potatoes = 0
Library.Toggles.AutoPick:SetValue(false)
pump(0.8)
local pickCountAfterOff = pktCount("PotatoPick")
pump(1.2)
check("AutoPick: stops after toggle off", pktCount("PotatoPick") == pickCountAfterOff)

-- ===== AutoPlace =====
State.Potatoes = 5
Library.Toggles.AutoPlace:SetValue(true)
pump(1.5)
check("AutoPlace: PlacePrompt fired when bag has potatoes", (function()
    for _, p in ipairs(PromptFires) do
        if p == placePrompt then return true end
    end
    return false
end)())
State.Potatoes = 0
Library.Toggles.AutoPlace:SetValue(false)

-- ===== AutoLoad =====
State.HasAutoPeeler = true
inputArea:SetAttribute("PotatoCount", 3)
Library.Toggles.AutoLoad:SetValue(true)
pump(1.5)
check("AutoLoad: auto machine Load prompt fired (input count > 0)", (function()
    for _, p in ipairs(PromptFires) do
        if p == autoLoadPrompt then return true end
    end
    return false
end)())
inputArea:SetAttribute("PotatoCount", 0)
Library.Toggles.AutoLoad:SetValue(false)

-- ===== AutoCrank =====
State.HasAutoPeeler = false
State.HasHandPeeler = true
handRoot:SetAttribute("PotatoCount", 4)
Library.Toggles.AutoCrank:SetValue(true)
pump(1.2)
check("AutoCrank: Crank prompt fired (hand machine has potatoes)", (function()
    for _, p in ipairs(PromptFires) do
        if p == crankPrompt then return true end
    end
    return false
end)())
handRoot:SetAttribute("PotatoCount", 0)
Library.Toggles.AutoCrank:SetValue(false)

-- ===== AutoSell =====
outputArea:SetAttribute("PotatoCount", 2)
Library.Toggles.AutoSell:SetValue(true)
pump(1.5)
check("AutoSell: SellPrompt fired (output count > 0)", (function()
    for _, p in ipairs(PromptFires) do
        if p == sellPrompt then return true end
    end
    return false
end)())
outputArea:SetAttribute("PotatoCount", 0)
Library.Toggles.AutoSell:SetValue(false)

-- ===== AutoBuyMachines =====
State.HasHandPeeler = false
State.HasAutoPeeler = false
State.Cash = 12
Library.Toggles.AutoBuyMachines:SetValue(true)
pump(1.5)
check("AutoBuyMachines: hand machine (10) bought first, auto (60) not", (function()
    local hand, auto = false, false
    for _, p in ipairs(PromptFires) do
        if p == handBuyPrompt then hand = true end
        if p == autoBuyPrompt then auto = true end
    end
    return hand and not auto
end)())
State.HasHandPeeler = true
State.Cash = 65
pump(1.5)
check("AutoBuyMachines: auto peeler bought when cash 65", (function()
    for _, p in ipairs(PromptFires) do
        if p == autoBuyPrompt then return true end
    end
    return false
end)())
State.Cash = 0
Library.Toggles.AutoBuyMachines:SetValue(false)

-- ===== AutoBuyTools =====
State.Cash = 3.5
Library.Toggles.AutoBuyTools:SetValue(true)
pump(1.5)
check("AutoBuyTools: Shovel (3) store prompt fired, Sucker (30) not", (function()
    local shovel, sucker, bucket = false, false, false
    for _, p in ipairs(PromptFires) do
        if p == shovelPrompt then shovel = true end
        if p == suckerPrompt then sucker = true end
        if p == bucketPrompt then bucket = true end
    end
    return shovel and not sucker and not bucket
end)())
State.Tools.Shovel = true
State.Cash = 0.5
pump(1.5)
check("AutoBuyTools: next Bucket storage (0.5) after Shovel owned", (function()
    for _, p in ipairs(PromptFires) do
        if p == bucketPrompt then return true end
    end
    return false
end)())
State.Cash = 0
State.Tools.Shovel = nil
Library.Toggles.AutoBuyTools:SetValue(false)

-- ===== AutoUpgradeTools =====
State.Cash = 0.5
Library.Toggles.AutoUpgradeTools:SetValue(true)
pump(1.5)
check("AutoUpgradeTools: cheapest next (Hand PickSpeed 0.05) fired", (function()
    local a = pktArgs("ToolUpgradePurchase")
    return a ~= nil and a.n == 2 and a[1] == "Hand" and a[2] == "PickSpeed"
end)())
State.Upgrades["Hand_PickSpeed"] = 2
State.Cash = 0.5
pump(1.2)
check("AutoUpgradeTools: maxed Hand falls through to Body WalkSpeed (0.3)", (function()
    local a = pktArgs("ToolUpgradePurchase", function(c) return c.args[1] == "Body" end)
    return a ~= nil and a[2] == "WalkSpeed"
end)())
Library.Toggles.AutoUpgradeTools:SetValue(false)
State.Upgrades["Hand_PickSpeed"] = nil
State.Cash = 0

-- ===== AutoPeel =====
local potato1 = makeSessionPotato("A")
Library.Toggles.AutoPeel:SetValue(true)
pump(1.6)
check("AutoPeel: PeelingPeelRemoved fired per peel index (1-6)", (function()
    for i = 1, 6 do
        local a = pktArgs("PeelingPeelRemoved", function(c) return c.args[1] == i end)
        if a == nil then return false, i end
        if type(a[2]) ~= "table" or a[2].X == nil then return false, "pos" end
    end
    return true
end)())
check("AutoPeel: PeelingFinished fired after all 6", pktCount("PeelingFinished") >= 1)
check("AutoPeel: PeelingSync periodic fired", pktCount("PeelingSync") >= 5)
local removedBefore = pktCount("PeelingPeelRemoved")
local finishedBefore = pktCount("PeelingFinished")
Packets.PeelingStarted.OnClientEvent:Fire(nil, {}, "Peeler")
pump(0.6)
check("AutoPeel: InstantPeel tool fires all 6 + Finished in one cycle", (function()
    return pktCount("PeelingPeelRemoved") - removedBefore >= 6 and pktCount("PeelingFinished") - finishedBefore >= 1
end)())
Packets.PeelingStopped.OnClientEvent:Fire()
pump(0.4)
local peelFiresStopped = pktCount("PeelingPeelRemoved")
pump(1.0)
check("AutoPeel: session stopped halts peels", pktCount("PeelingPeelRemoved") == peelFiresStopped)
Library.Toggles.AutoPeel:SetValue(false)
potato1:Destroy()

-- ===== AutoEscape =====
State.HasKey = true
Library.Toggles.AutoEscape:SetValue(true)
pump(1.5)
check("AutoEscape: KeyHole prompt fired when HasKey", (function()
    for _, p in ipairs(PromptFires) do
        if p == keyPrompt then return true end
    end
    return false
end)())
State.HasKey = false
Library.Toggles.AutoEscape:SetValue(false)

-- ===== AutoQueue =====
Library.Toggles.AutoQueue:SetValue(true)
pump(2.5)
check("AutoQueue: QueueCreate fired (1, false, false) after zone pad TP", (function()
    local a = pktArgs("QueueCreate")
    return a ~= nil and a.n == 3 and a[1] == 1 and a[2] == false and a[3] == false
end)())
check("AutoQueue: HRP teleported to zone pad", (function()
    local d = (charRoot.Position - zonePad.Position).Magnitude
    return d < 5
end)())
Packets.QueueJoined.OnClientEvent:Fire(true, "1")
pump(2.0)
local createCount = pktCount("QueueCreate")
check("AutoQueue: no create spam while joined", createCount <= 2)
Packets.QueueLeft.OnClientEvent:Fire()
Library.Toggles.AutoQueue:SetValue(false)

-- ===== AutoClassRoll =====
State.SaveData.Diamonds = 50
State.SaveData.StopAtClass = ""
State.SaveData.Class = "Peasant"
Library.Toggles.AutoClassRoll:SetValue(true)
pump(1.0)
check("AutoClassRoll: ClassRoll fired (diamonds 50 >= 40)", pktCount("ClassRoll") >= 1)
State.SaveData.Class = "PotatoExpert"
State.SaveData.StopAtClass = "PotatoExpert"
pump(2.0)
check("AutoClassRoll: stopped at class target (IsStoppedAt)", (function()
    local rolls = pktCount("ClassRoll")
    pump(2.0)
    return pktCount("ClassRoll") == rolls
end)())
Library.Toggles.AutoClassRoll:SetValue(false)
State.SaveData.StopAtClass = ""
State.SaveData.Diamonds = 0

-- ===== AutoLobbyUpgrades =====
State.SaveData.Diamonds = 150
Library.Toggles.AutoLobbyUpgrades:SetValue(true)
pump(1.5)
check("AutoLobbyUpgrades: cheapest (GrabAmount 100) fired", (function()
    local a = pktArgs("LobbyUpgradePurchase")
    return a ~= nil and a.n == 1 and a[1] == "GrabAmount"
end)())
State.SaveData.Diamonds = 0
Library.Toggles.AutoLobbyUpgrades:SetValue(false)

-- ===== AutoClaimDaily =====
Library.Toggles.AutoClaimDaily:SetValue(true)
pump(1.0)
check("AutoClaimDaily: claim fired when claimable", pktCount("DailyRewardClaim") == 1)
State.SaveData.DailyRewardDay = 1
State.SaveData.DailyRewardClaimDate = DailyShared.GetToday()
pump(31.0)
check("AutoClaimDaily: no refire after server confirmed claim", pktCount("DailyRewardClaim") == 1)
State.SaveData.DailyRewardClaimDate = DailyShared.GetToday()
pump(1.0)
Library.Toggles.AutoClaimDaily:SetValue(false)

-- ===== AutoClaimGroup =====
Library.Toggles.AutoClaimGroup:SetValue(true)
pump(1.0)
check("AutoClaimGroup: Claim fired once with game enum", (function()
    return pktCount("GroupRewardClaim") == 1 and pktArgs("GroupRewardClaim")[1] == "Claim"
end)())
State.SaveData.GroupRewardClaimed = true
pump(31.0)
check("AutoClaimGroup: no refire after claimed", pktCount("GroupRewardClaim") == 1)
Library.Toggles.AutoClaimGroup:SetValue(false)

-- ===== final: no invented wires =====
check("no removed-class wires fired (ROBUX/admin/UI one-shots)", (function()
    local banned = { "PurchaseProduct", "SetGlobalOverride", "ResetGlobalOverride", "StatsRequest", "LeaderboardRequest", "RunReportRequest", "PeelingCancel", "QueueLeave", "ClassStopAt" }
    for _, c in ipairs(PacketFires) do
        for _, b in ipairs(banned) do
            if c.name == b then return false, c.name end
        end
    end
    return true
end)())
check("pcall interceptor: no silent swallows across all features", PcallSwallows == 0)

summary()
