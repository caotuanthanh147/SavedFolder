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


-- ===== PST game mocks (glm3, 2026-10-08) =====
local ScriptPath = arg and arg[1] or nil
local ScriptSrc = nil
if ScriptPath then
    local f = io.open(ScriptPath, "r")
    if f then
        ScriptSrc = f:read("*a")
        f:close()
    end
end
if not ScriptSrc then
    for _, p in ipairs({ "/home/z/pst-work/PetStoreTycoon.lua", "/home/z/SavedFolder/work/lua/PetStoreTycoon.lua" }) do
        local f = io.open(p, "r")
        if f then
            ScriptSrc = f:read("*a")
            ScriptPath = p
            f:close()
            break
        end
    end
end

local RS = Instance.new("Folder", "ReplicatedStorage")
local WS = Instance.new("Folder", "Workspace")
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

local PLR = Instance.new("Player", "LocalPlayer")
PLR.Idled = Signal.new()
PLR.UserId = 12345
PLR:SetAttribute("ActivePlotOwnerUserId", 12345)
PLR:SetAttribute("Cash", 5000)
PLR.Character = Instance.new("Model", "Character")
local HRP = Instance.new("Part", "HumanoidRootPart")
HRP:SetCFrame(CFrame.new(0, 3, 0))
PLR.Character.PrimaryPart = HRP
PLR.Character:AddChild(HRP)
PLR.Character:AddChild(Instance.new("Humanoid", "Humanoid"))

local Plots = Instance.new("Folder", "Plots")
WS:AddChild(Plots)
local Plot = Instance.new("Folder", "Plot1")
Plot:SetAttribute("OwnerUserId", 12345)
Plots:AddChild(Plot)

local Shelf = Instance.new("Model", "Shelf")
Shelf:SetAttribute("SlotSize", "Small")
Shelf:SetAttribute("ItemId", "Shelf1")
Plot:AddChild(Shelf)
local SlotGoods = {}
local function mkSlot(idx, price)
    local slot = Instance.new("Model", "Slot")
    slot:SetAttribute("SlotIndex", idx)
    Shelf:AddChild(slot)
    local goods = Instance.new("Part", "Goods")
    goods:SetAttribute("SellPrice", price)
    goods:SetCFrame(CFrame.new(idx * 4, 1, 0))
    slot:AddChild(goods)
    SlotGoods[idx] = goods
    return slot
end
mkSlot(1, 9.99)
mkSlot(2, 20)

local Till = Instance.new("Model", "Checkout")
Till:AddChild(Instance.new("Part", "Foundation"))
Till:AddChild(Instance.new("Part", "ScanMat"))
Plot:AddChild(Till)
local function mkTillItem(idx)
    local it = Instance.new("Part", "Item" .. idx)
    it:SetAttribute("CheckoutTransactionId", "T1")
    it:SetAttribute("CheckoutItemIndex", idx)
    Till:AddChild(it)
    return it
end
mkTillItem(1)
mkTillItem(2)

local Boxes = Instance.new("Folder", "Boxes")
Plot:AddChild(Boxes)

local Enc = Instance.new("Model", "BirdCage")
Enc:SetAttribute("AcceptsType", "Bird")
Enc:SetAttribute("ItemId", "BirdCage1")
Enc:SetAttribute("MaintenanceFeatures", "Food,Play")
Enc:SetAttribute("Need_Food", 20)
local PetsFolder = Instance.new("Folder", "Pets")
Enc:AddChild(PetsFolder)
local Pet1 = Instance.new("Model", "Pet1")
Pet1:SetAttribute("PetKey", "pet-1")
Pet1:SetAttribute("Need_Play", 30)
PetsFolder:AddChild(Pet1)
Plot:AddChild(Enc)

local GoodsRoot = Instance.new("Folder", "Goods")
RS:AddChild(GoodsRoot)
local FoodCat = Instance.new("Folder", "Food")
GoodsRoot:AddChild(FoodCat)
local SmallSub = Instance.new("Folder", "Small")
FoodCat:AddChild(SmallSub)
local FishFlakes = Instance.new("Model", "FishFlakes")
FishFlakes:SetAttribute("BoxPrice", 28.17)
FishFlakes:SetAttribute("BoxQuantity", 9)
FishFlakes:SetAttribute("SizeClass", "Small")
SmallSub:AddChild(FishFlakes)
local BirdSeed = Instance.new("Model", "BirdSeedMix")
BirdSeed:SetAttribute("BoxPrice", 65)
BirdSeed:SetAttribute("BoxQuantity", 8)
BirdSeed:SetAttribute("SizeClass", "Small")
SmallSub:AddChild(BirdSeed)
local ToysCat = Instance.new("Folder", "Toys")
GoodsRoot:AddChild(ToysCat)
local MedSub = Instance.new("Folder", "Medium")
ToysCat:AddChild(MedSub)
local MedToy = Instance.new("Model", "Ball")
MedToy:SetAttribute("BoxPrice", 100)
MedToy:SetAttribute("BoxQuantity", 4)
MedToy:SetAttribute("SizeClass", "Medium")
MedSub:AddChild(MedToy)

local Common = {
    ceilToCents = function(x)
        return math.ceil((tonumber(x) or 0) * 100) / 100
    end,
    formatCurrency = function(x) return "$" .. tostring(x) end,
    formatAmount = function(x) return tostring(x) end,
}
local MockShelfRules = nil
MockShelfRules = {
    SLOT_INDEX_ATTR = "SlotIndex",
    PRICE_ATTR = "SellPrice",
    COST_ATTR = "UnitCost",
    MARKET_MULTIPLIERS = { Small = 1.5, Medium = 1.75, Large = 2 },
    OPTIMAL_RATIO = 1.4,
    isShelf = function(inst)
        local v = inst:GetAttribute("SlotSize")
        return type(v) == "string" and v ~= ""
    end,
    slotSizeOf = function(inst)
        local v = inst:GetAttribute("SlotSize")
        if type(v) == "string" and v ~= "" then
            return v
        end
        return nil
    end,
    sizeClassOf = function(inst)
        local v = inst:GetAttribute("SizeClass")
        if type(v) == "string" and v ~= "" then
            return v
        end
        return "Small"
    end,
    boxQuantityOf = function(inst)
        local v = inst:GetAttribute("BoxQuantity")
        if type(v) == "number" and 1 <= v then
            return math.floor(v)
        end
        return 1
    end,
    boxPriceOf = function(inst)
        local v = inst:GetAttribute("BoxPrice")
        if type(v) ~= "number" or v < 0 then
            return nil
        end
        return v
    end,
    baseUnitPriceOf = function(inst)
        local p = MockShelfRules.boxPriceOf(inst)
        if not p then
            return nil
        end
        return Common.ceilToCents(p / MockShelfRules.boxQuantityOf(inst))
    end,
    marketPriceOf = function(inst)
        local p = MockShelfRules.baseUnitPriceOf(inst)
        if not p then
            return nil
        end
        return math.floor(p * (MockShelfRules.MARKET_MULTIPLIERS[MockShelfRules.sizeClassOf(inst)] or 1.5) * 10 + 1e-06) / 10
    end,
    optimalPriceOf = function(inst)
        local p = MockShelfRules.marketPriceOf(inst)
        if not p then
            return nil
        end
        return math.floor(p * MockShelfRules.OPTIMAL_RATIO * 10 + 1e-06) / 10
    end,
    slotModels = function(shelf)
        local out = {}
        for _, v in ipairs(shelf:GetDescendants()) do
            if v:IsA("Model") and v.Name == "Slot" then
                table.insert(out, v)
            end
        end
        return out
    end,
    goodsPartOf = function(slot)
        local g = slot:FindFirstChild("Goods")
        if g and g:IsA("BasePart") then
            return g
        end
        return nil
    end,
}
local MockMaintenance = nil
MockMaintenance = {
    NEED_ATTRIBUTE_PREFIX = "Need_",
    PET_VISUAL_FOLDER = "Pets",
    Features = {
        Food = { label = "Food", scope = "enclosure", restoreGate = 90 },
        Play = { label = "Play", scope = "animal", restoreGate = 90 },
    },
    get = function(f)
        return MockMaintenance.Features[f]
    end,
    restoreGateFor = function(def)
        return def.restoreGate or 90
    end,
    featuresOf = function(enc)
        local attr = enc:GetAttribute("MaintenanceFeatures")
        local list = {}
        if type(attr) == "string" then
            for f in string.gmatch(attr, "[^,]+") do
                local t = string.match(f, "^%s*(.-)%s*$")
                if t ~= "" and MockMaintenance.Features[t] then
                    table.insert(list, t)
                end
            end
        end
        return list
    end,
    needyPetKeysOf = function(enc, feature)
        local out = {}
        local def = MockMaintenance.get(feature)
        if not def or def.scope ~= "animal" then
            return out
        end
        local pets = enc:FindFirstChild("Pets")
        if not pets then
            return out
        end
        local gate = MockMaintenance.restoreGateFor(def)
        for _, p in ipairs(pets:GetChildren()) do
            local n = p:GetAttribute("Need_" .. feature)
            if type(n) == "number" and n < gate then
                table.insert(out, p.Name)
            end
        end
        table.sort(out)
        return out
    end,
}
local GoodsData = { Shelves = { Shelf1 = { ["1"] = { Good = "FishFlakes", Qty = 3 } } } }
local MockPlayerData = {
    getGoods = function()
        return GoodsData
    end,
    getCash = function()
        return PLR:GetAttribute("Cash")
    end,
}
local MockActivePlot = {
    getHostUserId = function()
        return 12345
    end,
    getPlot = function()
        return Plot
    end,
}
local MockEnclosureRules = {
    isEnclosure = function(inst)
        local v = inst:GetAttribute("AcceptsType")
        return type(v) == "string" and v ~= ""
    end,
}
local MockCheckoutMoney = {
    Denominations = {
        { id = "bill1", cents = 100 },
        { id = "bill5", cents = 500 },
        { id = "bill10", cents = 1000 },
        { id = "bill20", cents = 2000 },
        { id = "bill50", cents = 5000 },
        { id = "bill100", cents = 10000 },
        { id = "coin1", cents = 1 },
        { id = "coin5", cents = 5 },
        { id = "coin10", cents = 10 },
        { id = "coin25", cents = 25 },
        { id = "coin50", cents = 50 },
    },
}
local ModsFolder = Instance.new("Folder", "Modules")
RS:AddChild(ModsFolder)
addModule(ModsFolder, "ActivePlot", MockActivePlot)
addModule(ModsFolder, "PlayerDataClient", MockPlayerData)
addModule(ModsFolder, "ShelfRules", MockShelfRules)
addModule(ModsFolder, "EnclosureRules", MockEnclosureRules)
addModule(ModsFolder, "EnclosureMaintenance", MockMaintenance)
addModule(ModsFolder, "CheckoutMoney", MockCheckoutMoney)

-- ===== remotes tree =====
local RemotesRoot = Instance.new("Folder", "Remotes")
RS:AddChild(RemotesRoot)
local function mkFolder(parent, name)
    local f = Instance.new("Folder", name)
    parent:AddChild(f)
    return f
end
local PlotFolder = mkFolder(RemotesRoot, "Plot")
local GoodsFolder = mkFolder(RemotesRoot, "Goods")
local CheckoutFolder = mkFolder(RemotesRoot, "Checkout")
local MessFolder = mkFolder(RemotesRoot, "Mess")
local EnclFolder = mkFolder(RemotesRoot, "Enclosures")
local CurbsideFolder = mkFolder(RemotesRoot, "Curbside")
local BoxesRFolder = mkFolder(RemotesRoot, "Boxes")
local UIFolder = mkFolder(RemotesRoot, "UI")
local StorageFolder = mkFolder(RemotesRoot, "Storage")
local AdminFolder = mkFolder(RemotesRoot, "Admin")
local AnalyticsFolder = mkFolder(RemotesRoot, "Analytics")

local function mkRE(parent, name)
    local r = Instance.new("RemoteEvent", name)
    r.OnClientEvent = Signal.new()
    r.Fires = {}
    function r:FireServer(...)
        local args = table.pack(...)
        table.insert(self.Fires, args)
        if self.Sim then
            self.Sim(table.unpack(args, 1, args.n))
        end
    end
    parent:AddChild(r)
    return r
end
local function mkRF(parent, name)
    local r = Instance.new("RemoteFunction", name)
    r.Invokes = {}
    function r:InvokeServer(...)
        local args = table.pack(...)
        table.insert(self.Invokes, args)
        if self.Sim then
            return self.Sim(table.unpack(args, 1, args.n))
        end
        return nil
    end
    parent:AddChild(r)
    return r
end

local REOrderItem = mkRE(PlotFolder, "OrderItem")
local REStartNextDay = mkRE(PlotFolder, "StartNextDay")
local RESetGoodPrice = mkRE(GoodsFolder, "SetGoodPrice")
local REPlaceGoods = mkRF(GoodsFolder, "PlaceGoods")
local REPickUpBox = mkRE(GoodsFolder, "PickUpBox")
local REBeginShift = mkRF(CheckoutFolder, "BeginShift")
local REScanCurrent = mkRE(CheckoutFolder, "ScanCurrent")
local REAcceptPayment = mkRE(CheckoutFolder, "AcceptPresentedPayment")
local RESubmitCashChange = mkRE(CheckoutFolder, "SubmitCashChange")
local RESubmitCardAmount = mkRE(CheckoutFolder, "SubmitCardAmount")
local REEndShift = mkRE(CheckoutFolder, "EndShift")
local RECleanMess = mkRE(MessFolder, "Clean")
local REBeginCare = mkRF(EnclFolder, "BeginCare")
local RECompleteCare = mkRF(EnclFolder, "CompleteCare")
local RECurbsideAccept = mkRE(CurbsideFolder, "Accept")
local REBoxReport = mkRE(BoxesRFolder, "Report")
local REBoxSpawn = mkRE(BoxesRFolder, "Spawn")
local RECheckoutState = mkRE(UIFolder, "CheckoutState")
local REDaySummary = mkRE(UIFolder, "DaySummary")
local Banned = {}
Banned.PurchaseGood = mkRF(GoodsFolder, "PurchaseGood")
Banned.TakeFromShelf = mkRF(GoodsFolder, "TakeFromShelf")
Banned.TrashBox = mkRE(GoodsFolder, "TrashBox")
Banned.DropBox = mkRE(GoodsFolder, "DropBox")
Banned.StowBox = mkRE(StorageFolder, "StowBox")
Banned.RenameSlot = mkRF(mkFolder(RemotesRoot, "Saves"), "RenameSlot")
Banned.Broadcast = mkRF(AdminFolder, "Broadcast")
Banned.Track = mkRE(AnalyticsFolder, "Track")

-- ===== server sims =====
local BoxSeq = 0
local LastOrder = nil
REOrderItem.Sim = function(payload)
    LastOrder = payload
    BoxSeq = BoxSeq + 1
    local key = "B" .. BoxSeq
    local box = Instance.new("Model", key)
    box:SetAttribute("BoxKey", key)
    Boxes:AddChild(box)
    local part = Instance.new("Part", "Body")
    part:SetCFrame(CFrame.new(2, 0, 2))
    box:AddChild(part)
    REBoxSpawn.OnClientEvent:Fire(key, "Plot1", nil, {}, part._cframe, BoxSeq)
end
REPickUpBox.Sim = function(key)
    for _, b in ipairs(Boxes:GetChildren()) do
        if b:GetAttribute("BoxKey") == key then
            b:SetAttribute("Carrier", 12345)
        end
    end
end
REPlaceGoods.Sim = function(boxKey, shelfKey, slotIndex)
    GoodsData.Shelves[shelfKey] = GoodsData.Shelves[shelfKey] or {}
    GoodsData.Shelves[shelfKey][tostring(slotIndex)] = { Good = LastOrder and LastOrder.item or nil, Qty = 9 }
    return true
end

local CheckoutSrv = { Shifts = 0, State = nil }
local function pushCheckout()
    RECheckoutState.OnClientEvent:Fire(CheckoutSrv.State)
end
REBeginShift.Sim = function(till)
    CheckoutSrv.Shifts = CheckoutSrv.Shifts + 1
    if CheckoutSrv.Shifts == 1 then
        CheckoutSrv.State = {
            transactionId = "T1",
            phase = "Scanning",
            itemLines = {},
            scanLines = { { sourceIndex = 1 }, { sourceIndex = 2 } },
            totalCents = 743,
        }
        pushCheckout()
        return { ok = true, state = CheckoutSrv.State }
    end
    return { ok = true }
end
REScanCurrent.Sim = function(itemPart, tid, seq)
    if not CheckoutSrv.State or CheckoutSrv.State.transactionId ~= tid then
        return
    end
    local idx = itemPart:GetAttribute("CheckoutItemIndex")
    table.insert(CheckoutSrv.State.itemLines, { sourceIndex = idx, scanned = true })
    if #CheckoutSrv.State.itemLines >= 2 then
        CheckoutSrv.State.phase = "AwaitingPayment"
    end
    pushCheckout()
end
REAcceptPayment.Sim = function(v)
    if CheckoutSrv.State then
        CheckoutSrv.State.phase = "CashChange"
        CheckoutSrv.State.changeDueCents = 743
        pushCheckout()
    end
end
RESubmitCashChange.Sim = function(counts)
    local sum = 0
    for id, n in pairs(counts) do
        for _, d in ipairs(MockCheckoutMoney.Denominations) do
            if d.id == id then
                sum = sum + d.cents * n
            end
        end
    end
    CheckoutSrv.CashSum = sum
    CheckoutSrv.State = nil
    pushCheckout()
end
RESubmitCardAmount.Sim = function(cents)
    CheckoutSrv.CardSum = cents
end
REEndShift.Sim = function() end

local MessSeq = 0
local function addMess()
    MessSeq = MessSeq + 1
    local m = Instance.new("Model", "Mess" .. MessSeq)
    m:SetAttribute("MessId", "m" .. MessSeq)
    Plot:AddChild(m)
    return m
end
local Messes = { addMess() }
RECleanMess.Sim = function(payload)
    for _, m in ipairs(Messes) do
        if m.Parent and m:GetAttribute("MessId") == payload.messId then
            m:Destroy()
        end
    end
end

REBeginCare.Sim = function(payload)
    return { ok = true, token = "tok-" .. tostring(payload.feature), playable = false }
end
RECompleteCare.Sim = function(payload)
    if payload.feature == "Food" then
        Enc:SetAttribute("Need_Food", 95)
    end
    if payload.feature == "Play" then
        Pet1:SetAttribute("Need_Play", 95)
    end
    return { ok = true }
end
RECurbsideAccept.Sim = function(car)
    car:SetAttribute("CurbsideAcceptedBy", 12345)
end
RESetGoodPrice.Sim = function(goodKey, price)
    local slots = GoodsData.Shelves.Shelf1
    for idx, data in pairs(slots) do
        if data.Good == goodKey then
            SlotGoods[tonumber(idx)]:SetAttribute("SellPrice", price)
        end
    end
end
REStartNextDay.Sim = function() end
REBoxReport.Sim = function(reports) end

local Tagged = { CurbsideCar = {} }
local Car = Instance.new("Model", "Car1")
Car:SetAttribute("OwnerUserId", 12345)
Car:SetAttribute("CurbsideWindow", "w1")
table.insert(Tagged.CurbsideCar, Car)
local Car2 = Instance.new("Model", "Car2")
Car2:SetAttribute("OwnerUserId", 12345)
table.insert(Tagged.CurbsideCar, Car2)

local Services = {}
Services.Players = { LocalPlayer = PLR, GetPlayers = function() return { PLR } end }
Services.ReplicatedStorage = RS
Services.CollectionService = {
    GetTagged = function(_, tag)
        return Tagged[tag] or {}
    end,
}
Services.RunService = {
    Heartbeat = Signal.new(),
    Stepped = Signal.new(),
    RenderStepped = Signal.new(),
    IsClient = function() return true end,
    IsStudio = function() return false end,
}
Services.TeleportService = { Teleport = function() end }
Services.UserInputService = { TouchEnabled = false, KeyboardEnabled = true, InputBegan = Signal.new() }
Services.HttpService = { JSONEncode = function(_, t) return "{}" end, JSONDecode = function(_, s) return {} end }
Services.TweenService = { Create = function() return { Play = function() end } end, GetValue = function() return 0 end }
Services.Lighting = {}
Services.GuiService = { GetResolution = function() return { X = 1920, Y = 1080 } end }
Services.MarketplaceService = { GetProductInfo = function() return { Name = "Pet Store Tycoon" } end }
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
G.os = setmetatable({ clock = G.tick, time = function() return 20000 * 86400 end }, { __index = os })

-- ===== mock-world self checks =====
check("world: plot resolvable via OwnerUserId", (function()
    for _, p in ipairs(Plots:GetChildren()) do
        if p:GetAttribute("OwnerUserId") == 12345 then
            return p == Plot
        end
    end
    return false
end)())
check("world: shelf rules math (optimal in sane range)", (function()
    local o = MockShelfRules.optimalPriceOf(FishFlakes)
    return type(o) == "number" and o > 5 and o < 8
end)())
check("world: featuresOf iterator yields Food, Play", (function()
    local out = MockMaintenance.featuresOf(Enc)
    return out[1] == "Food" and out[2] == "Play"
end)())
check("world: needyPetKeysOf finds Pet1 (returns names)", MockMaintenance.needyPetKeysOf(Enc, "Play")[1] == "Pet1")

-- ===== loader =====
if not ScriptSrc then
    print("SKIP: build script not present (looked in " .. tostring(ScriptPath) .. ") — mock-world checks only")
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
local fn = G.loadstring(ScriptSrc, "=(PetStoreTycoon)")
G.task.spawn(fn)
pump(3.0)

local function noErrorNotify()
    for _, n in ipairs(MockState.Notifies) do
        if string.find(n, "ERROR", 1, true) then
            return false, n
        end
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
check("save manager folder = Yuri/Pet Store Tycoon", SaveManager.Folder == "Yuri/Pet Store Tycoon")
check("all 7 game toggles registered", Library.Toggles.AutoStock ~= nil and Library.Toggles.AutoCheckout ~= nil and Library.Toggles.AutoClean ~= nil and Library.Toggles.AutoPrice ~= nil and Library.Toggles.AutoPetCare ~= nil and Library.Toggles.AutoCurbside ~= nil and Library.Toggles.AutoNextDay ~= nil)
check("remotes populated at load", RemotesRoot ~= nil and PLR ~= nil)

-- ===== AutoClean =====
Library.Toggles.AutoClean:SetValue(true)
pump(3)
check("AutoClean: fired for m1", (function()
    for _, a in ipairs(RECleanMess.Fires) do
        if a[1] and a[1].messId == "m1" then
            return true
        end
    end
    return false
end)())
local m2 = addMess()
table.insert(Messes, m2)
pump(3)
check("AutoClean: fired for m2", (function()
    for _, a in ipairs(RECleanMess.Fires) do
        if a[1] and a[1].messId == "m2" then
            return true
        end
    end
    return false
end)())
local cleanCount = #RECleanMess.Fires
Library.Toggles.AutoClean:SetValue(false)
local m4 = addMess()
table.insert(Messes, m4)
pump(4)
check("AutoClean: stopped after toggle off", #RECleanMess.Fires == cleanCount)

-- ===== AutoPetCare =====
Library.Toggles.AutoPetCare:SetValue(true)
pump(10)
check("AutoPetCare: BeginCare Food (enclosure scope, petKey nil)", (function()
    for _, a in ipairs(REBeginCare.Invokes) do
        if a[1] and a[1].itemKey == "BirdCage1" and a[1].feature == "Food" and a[1].petKey == nil then
            return true
        end
    end
    return false
end)())
check("AutoPetCare: BeginCare Play with pet-1", (function()
    for _, a in ipairs(REBeginCare.Invokes) do
        if a[1] and a[1].feature == "Play" and a[1].petKey == "pet-1" then
            return true
        end
    end
    return false
end)())
check("AutoPetCare: CompleteCare Food with token", (function()
    for _, a in ipairs(RECompleteCare.Invokes) do
        if a[1] and a[1].feature == "Food" and a[1].token == "tok-Food" and a[1].quiet == true then
            return true
        end
    end
    return false
end)())
check("AutoPetCare: CompleteCare Play with token", (function()
    for _, a in ipairs(RECompleteCare.Invokes) do
        if a[1] and a[1].feature == "Play" and a[1].token == "tok-Play" and a[1].petKey == "pet-1" then
            return true
        end
    end
    return false
end)())
check("AutoPetCare: needs recovered (no re-fire)", #REBeginCare.Invokes == 2 and #RECompleteCare.Invokes == 2)
Library.Toggles.AutoPetCare:SetValue(false)

-- ===== AutoCurbside =====
Library.Toggles.AutoCurbside:SetValue(true)
pump(4)
check("AutoCurbside: accepted car with window", Car:GetAttribute("CurbsideAcceptedBy") == 12345)
check("AutoCurbside: did NOT accept windowless car", Car2:GetAttribute("CurbsideAcceptedBy") == nil)
Library.Toggles.AutoCurbside:SetValue(false)

-- ===== AutoNextDay =====
Library.Toggles.AutoNextDay:SetValue(true)
REDaySummary.OnClientEvent:Fire()
pump(2.5)
check("AutoNextDay: fired after DaySummary", #REStartNextDay.Fires >= 1)
Library.Toggles.AutoNextDay:SetValue(false)
local ndCount = #REStartNextDay.Fires
REDaySummary.OnClientEvent:Fire()
pump(2.5)
check("AutoNextDay: stopped after toggle off", #REStartNextDay.Fires == ndCount)

-- ===== AutoStock =====
Library.Toggles.AutoStock:SetValue(true)
pump(16)
check("AutoStock: 2 OrderItem fires (refill + fresh)", #REOrderItem.Fires == 2)
check("AutoStock: first order = FishFlakes refill tuple", (function()
    local a = REOrderItem.Fires[1]
    return a and a[1].category == "Food" and a[1].subCategory == "Small" and a[1].item == "FishFlakes"
end)())
check("AutoStock: second order = BirdSeedMix (rotation, unused good)", (function()
    local a = REOrderItem.Fires[2]
    return a and a[1].item == "BirdSeedMix"
end)())
check("AutoStock: 2 PickUpBox fires with box keys", (function()
    return #REPickUpBox.Fires == 2 and REPickUpBox.Fires[1][1] == "B1" and REPickUpBox.Fires[2][1] == "B2"
end)())
check("AutoStock: 2 PlaceGoods invokes with full tuples", (function()
    local a, b = REPlaceGoods.Invokes[1], REPlaceGoods.Invokes[2]
    return a and a[1] == "B1" and a[2] == "Shelf1" and a[3] == 1 and b and b[1] == "B2" and b[2] == "Shelf1" and b[3] == 2
end)())
check("AutoStock: ESC wiring — Boxes.Report fired with valid gen", (function()
    for _, a in ipairs(REBoxReport.Fires) do
        local reps = a[1]
        if type(reps) == "table" and reps[1] and reps[1].k == "B1" and reps[1].g == 1 and reps[1].c then
            return true
        end
    end
    return false
end)())
check("AutoStock: replica data updated (both slots full)", (function()
    local s = GoodsData.Shelves.Shelf1
    return s["1"] and s["1"].Qty == 9 and s["1"].Good == "FishFlakes" and s["2"] and s["2"].Qty == 9 and s["2"].Good == "BirdSeedMix"
end)())
local stockOrders = #REOrderItem.Fires
pump(8)
check("AutoStock: no over-ordering when full", #REOrderItem.Fires == stockOrders)
Library.Toggles.AutoStock:SetValue(false)

-- ===== AutoPrice =====
Library.Toggles.AutoPrice:SetValue(true)
pump(6)
check("AutoPrice: SetGoodPrice fired for both goods at optimal", (function()
    local optFF = MockShelfRules.optimalPriceOf(FishFlakes)
    local optBS = MockShelfRules.optimalPriceOf(BirdSeed)
    local gotFF, gotBS = false, false
    for _, a in ipairs(RESetGoodPrice.Fires) do
        if a[1] == "FishFlakes" and math.abs(a[2] - optFF) < 1e-9 then
            gotFF = true
        end
        if a[1] == "BirdSeedMix" and math.abs(a[2] - optBS) < 1e-9 then
            gotBS = true
        end
    end
    return gotFF and gotBS
end)())
check("AutoPrice: prices differ from pre-set (sanity)", (function()
    local optFF = MockShelfRules.optimalPriceOf(FishFlakes)
    return math.abs(optFF - 9.99) > 0.05
end)())
Library.Toggles.AutoPrice:SetValue(false)

-- ===== AutoCheckout =====
Library.Toggles.AutoCheckout:SetValue(true)
pump(6)
check("AutoCheckout: BeginShift invoked with till", (function()
    local a = REBeginShift.Invokes[1]
    return a and a[1] == Till
end)())
check("AutoCheckout: both items scanned with tid + seq", (function()
    local n = 0
    for _, a in ipairs(REScanCurrent.Fires) do
        if a[2] == "T1" and type(a[3]) == "number" then
            n = n + 1
        end
    end
    return n == 2
end)())
check("AutoCheckout: scan args are the till item instances", (function()
    for _, a in ipairs(REScanCurrent.Fires) do
        if a[1] == nil or a[1].Parent ~= Till then
            return false
        end
    end
    return #REScanCurrent.Fires == 2
end)())
check("AutoCheckout: payment accepted", (function()
    for _, a in ipairs(REAcceptPayment.Fires) do
        if a[1] == true then
            return true
        end
    end
    return false
end)())
check("AutoCheckout: cash change counts sum to changeDue (743)", CheckoutSrv.CashSum == 743)
check("AutoCheckout: counts payload is a denom map", (function()
    for _, a in ipairs(RESubmitCashChange.Fires) do
        if type(a[1]) == "table" then
            for k, v in pairs(a[1]) do
                if type(k) ~= "string" or type(v) ~= "number" then
                    return false
                end
            end
            return true
        end
    end
    return false
end)())
pump(24)
check("AutoCheckout: idle EndShift after 25s virtual", #REEndShift.Fires >= 1)
local endShifts = #REEndShift.Fires
local begins = #REBeginShift.Invokes
Library.Toggles.AutoCheckout:SetValue(false)
pump(0.5)
check("AutoCheckout: toggle-off ends active shift", #REEndShift.Fires == endShifts + 1)
check("AutoCheckout: re-begin happened during idle cycle", begins >= 2)

-- ===== banned-wire sweep =====
check("banned sweep: no PurchaseGood/TakeFromShelf/TrashBox/DropBox/StowBox/RenameSlot/Broadcast/Track fires", (function()
    return #Banned.PurchaseGood.Invokes == 0 and #Banned.TakeFromShelf.Invokes == 0
        and #Banned.TrashBox.Fires == 0 and #Banned.DropBox.Fires == 0 and #Banned.StowBox.Fires == 0
        and #Banned.RenameSlot.Invokes == 0 and #Banned.Broadcast.Invokes == 0 and #Banned.Track.Fires == 0
end)())
check("pcall interceptor: 0 silent swallows total", PcallSwallows == 0)

print(string.format("PST harness: %d pass / %d fail", Pass, Fail))
if Fail > 0 then
    for _, f in ipairs(Failures) do
        print("  failed: " .. f)
    end
    os.exit(1)
end
