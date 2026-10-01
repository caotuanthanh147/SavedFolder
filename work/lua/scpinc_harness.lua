local SCP_SRC = nil
do
    local f = io.open("/home/z/my-project/Yuri/SCPIncremental/SCPIncremental.lua", "r")
    SCP_SRC = f:read("*a")
    f:close()
end

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
        return setmetatable({ Position = pos }, cmt)
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

local BigNum
do
    local SUFFIX = { "", "K", "M", "B", "T", "Qa", "Qn", "Sx", "Sp", "Oc", "No", "Dc", "Ud", "Dd", "Td", "Qad", "Qnd", "Sxd", "Spd", "Ocd", "Nod", "Vg", "Uvg", "Dvg", "Tvg", "Qavg", "Qnvg", "Sxvg", "Spvg", "Ocvg", "Novg", "Tg", "Utg", "Dtg", "Ttg", "Qatg", "Qntg", "Sxtg", "Sptg", "Octg", "Notg", "Qag" }
    local mt = {}
    local function val(v)
        if type(v) == "table" then
            return v.v
        end
        return tonumber(v) or 0
    end
    local function wrap(x)
        return setmetatable({ v = x }, mt)
    end
    mt.__add = function(a, b)
        return wrap(val(a) + val(b))
    end
    mt.__sub = function(a, b)
        return wrap(val(a) - val(b))
    end
    mt.__mul = function(a, b)
        return wrap(val(a) * val(b))
    end
    mt.__div = function(a, b)
        return wrap(val(a) / val(b))
    end
    mt.__lt = function(a, b)
        return val(a) < val(b)
    end
    mt.__le = function(a, b)
        return val(a) <= val(b)
    end
    mt.__tostring = function(a)
        return tostring(val(a))
    end
    BigNum = { _mt = mt }
    function BigNum.new(x)
        if type(x) == "table" then
            return x
        end
        local n = tonumber(x)
        if n == nil and type(x) == "string" then
            local num, suf = string.match(x, "^([%d%.]+)(.*)$")
            if num and suf ~= "" then
                for i, s in ipairs(SUFFIX) do
                    if s == suf then
                        n = tonumber(num) * (1000 ^ (i - 1))
                        break
                    end
                end
            end
        end
        return wrap(tonumber(n) or 0)
    end
    BigNum.zero = wrap(0)
    BigNum.one = wrap(1)
    BigNum.isZero = function(x)
        return val(x) == 0
    end
    BigNum.toNumber = function(x)
        return val(x)
    end
    BigNum.gte = function(a, b)
        return val(a) >= val(b)
    end
    BigNum.gt = function(a, b)
        return val(a) > val(b)
    end
    BigNum.lt = function(a, b)
        return val(a) < val(b)
    end
    BigNum.lte = function(a, b)
        return val(a) <= val(b)
    end
    BigNum.add = function(a, b)
        return wrap(val(a) + val(b))
    end
    BigNum.sub = function(a, b)
        return wrap(val(a) - val(b))
    end
    BigNum.mul = function(a, b)
        return wrap(val(a) * val(b))
    end
    BigNum.div = function(a, b)
        return wrap(val(a) / val(b))
    end
    BigNum.pow = function(a, b)
        return wrap(val(a) ^ val(b))
    end
    BigNum.abs = function(a)
        return wrap(math.abs(val(a)))
    end
    BigNum.max = function(a, b)
        return wrap(math.max(val(a), val(b)))
    end
    BigNum.min = function(a, b)
        return wrap(math.min(val(a), val(b)))
    end
    BigNum.log10 = function(a)
        return wrap(math.log10(val(a)))
    end
    BigNum.isBigNum = function(x)
        return type(x) == "table" and getmetatable(x) == mt
    end
    BigNum.encode = function(x)
        return tostring(val(x))
    end
    BigNum.decode = function(x)
        return BigNum.new(x)
    end
    function BigNum.format(x, opts)
        local v = val(x)
        if v ~= v then
            return "NaN"
        end
        local i = 1
        local scale = 1
        while math.abs(v) >= 1000 * scale and i < #SUFFIX do
            scale = scale * 1000
            i = i + 1
        end
        if i > 1 then
            return string.format("%.1f%s", v / scale, SUFFIX[i])
        end
        if v == math.floor(v) then
            return string.format("%d", v)
        end
        return string.format("%.2f", v)
    end
end
G.__MockBigNum = BigNum

local Actions = {
    BuyUpgrade = "BuyUpgrade",
    BuyGun = "BuyGun",
    SelectLizardLevel = "SelectLizardLevel",
    BuyMaxUpgrade = "BuyMaxUpgrade",
    UnlockWall = "UnlockWall",
    ClaimKill = "ClaimKill",
    ClaimP13Food = "ClaimP13Food",
    Rebirth = "Rebirth",
    Prestige = "Prestige",
    RollRune = "RollRune",
    Convert = "Convert",
    ClaimHeart = "ClaimHeart",
    RollRank = "RollRank",
    GunFired = "GunFired",
    GetTicketPrice = "GetTicketPrice",
    BuyWithTickets = "BuyWithTickets",
    EquipRank = "EquipRank",
    SetSetting = "SetSetting",
    UsePotion = "UsePotion",
    RedeemCode = "RedeemCode",
    ClaimGroupReward = "ClaimGroupReward",
    ClaimGems = "ClaimGems",
    ShopFunnelStep = "ShopFunnelStep",
    RequestChestDrops = "RequestChestDrops",
    RequestIdleRejoin = "RequestIdleRejoin",
    WarehouseSnapshot = "WarehouseSnapshot",
    LizardSnapshot = "LizardSnapshot",
    ZombieSnapshot = "ZombieSnapshot",
}
local Net = {
    Actions = Actions,
    PacketKind = { Snapshot = "Snapshot", Delta = "Delta" },
    get = function(name)
        return nil
    end,
}
G.__MockNet = Net

local GameState = {
    ready = true,
    currencies = {
        Peanuts = 90000,
        Rebirth = 0,
        Tears = 0,
        Pills = 0,
        Love = 0,
        Zombies = 0,
        Bones = 0,
        Bullets = 0,
        Tix = 0,
        Souls = 0,
        Goo = 0,
        Gems = 0,
    },
    upgrades = {},
    walls = {
        Wall_Containment = true,
        Wall_Rebirth = true,
        Wall_Gems = true,
    },
    prestige = 3,
    gunTier = 1,
    keycards = 0,
    tickets = 15,
    gemClaim = { lastClaimAt = 90000, streakStep = 0 },
    potions = { StatBoost = 2 },
    ranks = { DClass = true },
    equippedRank = "DClass",
}

local CfgWalls = {
    List = {
        { Id = "Wall_Containment", Name = "Containment Wing", Order = 1, ModelName = "ContainmentWall", UnlockedByDefault = true },
        { Id = "Wall_Rebirth", Name = "Rebirth", Order = 2, ModelName = "RebirthWall", UnlockedByDefault = true },
        { Id = "Wall_Love", Name = "Love", Order = 6, ModelName = "LoveWall", UnlockedByDefault = false },
        { Id = "Wall_Bones", Name = "Bone Upgrades", Order = 8, ModelName = "BoneWall", UnlockedByDefault = false },
        { Id = "Wall_Gems", Name = "Gem Upgrades", Order = 13, ModelName = "GemUpgrades", UnlockedByDefault = true },
    },
    ById = {},
}
for _, w in ipairs(CfgWalls.List) do
    CfgWalls.ById[w.Id] = w
end

local CfgCurrencies = {
    List = {
        { Id = "Peanuts", Name = "Peanuts", Order = 1 },
        { Id = "Rebirth", Name = "Rebirth Points", Order = 2 },
        { Id = "Tears", Name = "Tears", Order = 3 },
        { Id = "Pills", Name = "Pills", Order = 4 },
        { Id = "Love", Name = "Love", Order = 5 },
        { Id = "Zombies", Name = "Zombies", Order = 6 },
        { Id = "Bones", Name = "Bones", Order = 7 },
        { Id = "Bullets", Name = "Bullets", Order = 8 },
        { Id = "Tix", Name = "Tix", Order = 9 },
        { Id = "Souls", Name = "Souls", Order = 10 },
        { Id = "Goo", Name = "Goo", Order = 11 },
        { Id = "Gems", Name = "Gems", Order = 12 },
    },
    ById = {},
}
for _, c in ipairs(CfgCurrencies.List) do
    CfgCurrencies.ById[c.Id] = c
end

local UpgDefs = {
    { Id = "T1_EarnMore", Wall = "Wall_Containment", Name = "Earn More", Order = 1, Currency = "Peanuts", MaxLevel = 5, Cost = { Curve = "Geometric", Base = 10, Growth = 1.5 } },
    { Id = "T1_Speed", Wall = "Wall_Containment", Name = "Breach Speed", Order = 2, Currency = "Peanuts", MaxLevel = 3, Cost = { Curve = "Geometric", Base = 100, Growth = 2 } },
    { Id = "R_Multi", Wall = "Wall_Rebirth", Name = "Rebirth Multiplier", Order = 1, Currency = "Rebirth", MaxLevel = 10, Cost = { Curve = "Geometric", Base = 50, Growth = 1.2 }, Requires = { Upgrades = { { Id = "T1_EarnMore", Level = 2 } } } },
    { Id = "L_A", Wall = "Wall_Love", Name = "Love Boost", Order = 1, Currency = "Love", MaxLevel = 2, Cost = { Curve = "Geometric", Base = 6000, Growth = 2 } },
    { Id = "B_Dmg", Wall = "Wall_Bones", Name = "Bone Damage", Order = 1, Currency = "Bones", MaxLevel = 4, Cost = { Curve = "Geometric", Base = 500, Growth = 1.5 }, Requires = { Walls = { "Wall_Love" } } },
    { Id = "T1_PrestigeGated", Wall = "Wall_Containment", Name = "Prestige Gate", Order = 3, Currency = "Peanuts", MaxLevel = 2, Cost = { Curve = "Geometric", Base = 10, Growth = 1 }, Requires = { Prestige = 9 } },
}
local CfgUpgrades = { ById = {}, List = {}, ByWall = {} }
for _, w in ipairs(CfgWalls.List) do
    CfgUpgrades.ByWall[w.Id] = {}
end
for _, u in ipairs(UpgDefs) do
    CfgUpgrades.ById[u.Id] = u
    table.insert(CfgUpgrades.List, u)
    table.insert(CfgUpgrades.ByWall[u.Wall], u)
end
table.sort(CfgUpgrades.List, function(a, b)
    if a.Wall ~= b.Wall then
        return a.Wall < b.Wall
    end
    return a.Order < b.Order
end)
for _, wlist in pairs(CfgUpgrades.ByWall) do
    table.sort(wlist, function(a, b)
        return a.Order < b.Order
    end)
end
CfgUpgrades.get = function(id)
    return CfgUpgrades.ById[id]
end
CfgUpgrades.forWall = function(id)
    return CfgUpgrades.ByWall[id] or {}
end
local function costAt(cost, lvl)
    return cost.Base * cost.Growth ^ lvl
end

local CfgPrestiges = {
    List = {
        { Level = 1, Name = "Prestige 1", Cost = "1000000" },
        { Level = 2, Name = "Prestige 2", Cost = "1e9" },
        { Level = 3, Name = "Prestige 3", Cost = "1.5e22" },
        { Level = 4, Name = "Prestige 4", Cost = "5e9" },
    },
    ById = {},
}
for _, p in ipairs(CfgPrestiges.List) do
    CfgPrestiges.ById[p.Level] = p
end
CfgPrestiges.next = function(cur)
    return CfgPrestiges.ById[cur + 1]
end
CfgPrestiges.current = function(cur)
    return CfgPrestiges.ById[cur]
end

local CfgGuns = {
    List = {
        { Tier = 1, Model = "1", Name = "Sidearm", Price = "0", Damage = 1, Bones = 1, FireRate = 1 },
        { Tier = 2, Model = "2", Name = "Snubnose", Price = "500", Damage = 1.35, Bones = 1.15, FireRate = 1 },
        { Tier = 3, Model = "3", Name = "Machine Pistol", Price = "2500", Damage = 1.56, Bones = 1.3, FireRate = 1 },
    },
    ByTier = {},
    BASE_SHOTS_PER_SECOND = 4,
}
for _, g in ipairs(CfgGuns.List) do
    CfgGuns.ByTier[g.Tier] = g
end
CfgGuns.get = function(t)
    return CfgGuns.ByTier[t]
end

local CfgRanks = {
    ROLL_COST = 1,
    REQUIRED_PRESTIGE = 3,
    KeycardProducts = {
        [3712298906] = 10,
        [3712298920] = 50,
    },
    TicketProducts = { [3712600857] = 10 },
    PermanentProducts = {},
    List = {
        { Id = "DClass", Name = "D-Class", OneIn = 3, AllStats = 1.2 },
        { Id = "O5", Name = "O5", OneIn = 3000, AllStats = 2.8 },
    },
    ById = {},
}
do
    for i, r in ipairs(CfgRanks.List) do
        r.Order = i
        CfgRanks.ById[r.Id] = r
    end
end
CfgRanks.best = function(owned)
    local best
    for k in pairs(owned or {}) do
        local def = CfgRanks.ById[k]
        if def then
            if not best or (best.Order or 0) < (def.Order or 0) then
                best = def
            end
        end
    end
    return best
end

local CfgConverts = {
    List = {
        { Id = "TearsToPills", From = "Tears", To = "Pills", Requirement = "5000", Gain = "1", Wall = "Wall_Convert" },
        { Id = "BonesToBullets", From = "Bones", To = "Bullets", Requirement = "40000", Gain = "1", Wall = "Wall_Bullets" },
    },
    ById = {},
}
for _, c in ipairs(CfgConverts.List) do
    CfgConverts.ById[c.Id] = c
end

local CfgPotions = {
    List = {
        { Id = "StatBoost", Name = "2x Stat Boost", ExpiryAttribute = "PotionStatBoostExpiresAt" },
        { Id = "RuneLuck", Name = "2x Rune Luck", ExpiryAttribute = "PotionRuneLuckExpiresAt" },
    },
    ById = {},
}
for _, p in ipairs(CfgPotions.List) do
    CfgPotions.ById[p.Id] = p
end

local CfgGemClaims = {
    BaseReward = 30,
    ClaimCooldown = 28800,
    StreakDuration = 86400,
    Multipliers = { 1, 10, 20, 35, 45, 50 },
}
CfgGemClaims.isReady = function(lastAt, now)
    if lastAt > 0 then
        return lastAt + CfgGemClaims.ClaimCooldown <= now
    end
    return true
end

local CfgRuneStations = {
    List = {
        { Id = "Basic", Name = "Basic Runes", Pool = "Basic", Currency = "Tears", Cost = 50, Wall = "Wall_ShyGuy", Interval = 1 },
        { Id = "Love", Name = "Love Runes", Pool = "Love", Currency = "Love", Cost = 6000, Wall = "Wall_Love", Interval = 1.5 },
        { Id = "Zombie", Name = "Zombie Runes", Pool = "Zombie", Currency = "Zombies", Cost = 25000, Wall = "Wall_Zombies", Interval = 1.5 },
    },
    ById = {},
}
for _, s in ipairs(CfgRuneStations.List) do
    CfgRuneStations.ById[s.Id] = s
end
CfgRuneStations.get = function(id)
    return CfgRuneStations.ById[id]
end

G.__CfgWalls = CfgWalls
G.__CfgCurrencies = CfgCurrencies
G.__CfgUpgrades = CfgUpgrades
G.__CfgPrestiges = CfgPrestiges
G.__CfgGuns = CfgGuns
G.__CfgRanks = CfgRanks
G.__CfgConverts = CfgConverts
G.__CfgPotions = CfgPotions
G.__CfgGemClaims = CfgGemClaims
G.__CfgRuneStations = CfgRuneStations
G.__CfgReleaseGates = {
    Prestige11ContentEnabled = true,
    Prestige13ContentEnabled = false,
    Prestige13Available = false,
}

local TicketPrices = {
    [3712298906] = 10,
    [3712298920] = 50,
}

local PlayerObj
local MyLizard
local MockCS
do
    local S = GameState
    MockCS = {}
    function MockCS.isReady()
        return S.ready
    end
    function MockCS.getCurrency(id)
        return BigNum.new(S.currencies[id] or 0)
    end
    function MockCS.getLevel(id)
        return S.upgrades[id] or 0
    end
    function MockCS.isWallUnlocked(id)
        return S.walls[id] == true
    end
    function MockCS.getPrestige()
        return S.prestige
    end
    function MockCS.getGunTier()
        return S.gunTier
    end
    function MockCS.getKeycards()
        return S.keycards
    end
    function MockCS.getTickets()
        return S.tickets
    end
    function MockCS.getGemClaim()
        return S.gemClaim.lastClaimAt or 0, S.gemClaim.streakStep or 0
    end
    function MockCS.getRanks()
        return S.ranks
    end
    function MockCS.getEquippedRank()
        return S.equippedRank
    end
    function MockCS.getPotions()
        return S.potions
    end
    function MockCS.canRebirth()
        local peanuts = tonumber(S.currencies.Peanuts or 0) or 0
        local preview = math.floor(math.sqrt(peanuts / 100000) * 5)
        return preview >= 5
    end
    function MockCS.rebirth()
        record({ fn = "rebirth" })
        S.currencies.Peanuts = 0
    end
    function MockCS.prestige()
        record({ fn = "prestige" })
        S.prestige = S.prestige + 1
        S.currencies.Peanuts = 0
    end
    function MockCS.convert(id)
        record({ fn = "convert", id = id })
        local def = CfgConverts.ById[id]
        if def then
            S.currencies[def.From] = 0
        end
    end
    function MockCS.canAfford(id)
        local u = CfgUpgrades.ById[id]
        if not u then
            return false
        end
        if u.MaxLevel <= (S.upgrades[id] or 0) then
            return false
        end
        local cur = tonumber(S.currencies[u.Currency] or 0) or 0
        return cur >= costAt(u.Cost, S.upgrades[id] or 0)
    end
    function MockCS.buyMax(id)
        record({ fn = "buyMax", id = id })
        local u = CfgUpgrades.ById[id]
        if not u then
            return
        end
        local lvl = S.upgrades[id] or 0
        local cur = tonumber(S.currencies[u.Currency] or 0) or 0
        local bought = 0
        while lvl + bought < u.MaxLevel and cur >= costAt(u.Cost, lvl + bought) do
            cur = cur - costAt(u.Cost, lvl + bought)
            bought = bought + 1
        end
        S.upgrades[id] = lvl + bought
        S.currencies[u.Currency] = cur
    end
    function MockCS.rollRank(count)
        record({ fn = "rollRank", count = count })
        S.keycards = math.max(0, S.keycards - count)
    end
    function MockCS.equipRank(id)
        record({ fn = "equipRank", id = id })
        S.equippedRank = id
    end
    function MockCS.claimGems()
        record({ fn = "claimGems" })
        S.gemClaim.lastClaimAt = Sched.now
    end
    function MockCS.usePotion(id, amount)
        record({ fn = "usePotion", id = id, amount = amount })
        S.potions[id] = math.max(0, (S.potions[id] or 0) - (amount or 1))
        local def = CfgPotions.ById[id]
        if def and PlayerObj then
            PlayerObj:SetAttribute(def.ExpiryAttribute, Sched.now + 900)
        end
    end
    function MockCS.request(action, payload, cb)
        record({ fn = "request", action = action, payload = payload })
        if action == Actions.GetTicketPrice then
            local pid = payload and payload.productId
            local price = TicketPrices[pid]
            if cb then
                spawnCo(function()
                    cb(true, nil, { price = price })
                end)
            end
        elseif action == Actions.BuyWithTickets then
            local pid = payload and payload.productId
            if TicketPrices[pid] and S.tickets >= TicketPrices[pid] then
                S.tickets = S.tickets - TicketPrices[pid]
                if cb then
                    spawnCo(function()
                        cb(true, nil, {})
                    end)
                end
            else
                if cb then
                    spawnCo(function()
                        cb(false, "INSUFFICIENT_FUNDS", nil)
                    end)
                end
            end
        elseif action == Actions.BuyGun then
            local nextGun = CfgGuns.ByTier[S.gunTier + 1]
            if nextGun then
                local price = tonumber(nextGun.Price) or 0
                if (tonumber(S.currencies.Bones or 0) or 0) >= price then
                    S.currencies.Bones = (tonumber(S.currencies.Bones or 0) or 0) - price
                    S.gunTier = S.gunTier + 1
                end
            end
            if cb then
                spawnCo(function()
                    cb(true, nil, {})
                end)
            end
        elseif action == Actions.SelectLizardLevel then
            if MyLizard and payload and type(payload.tier) == "number" then
                MyLizard:SetAttribute("Tier", payload.tier)
            end
            if cb then
                spawnCo(function()
                    cb(true, nil, {})
                end)
            end
        else
            if cb then
                spawnCo(function()
                    cb(true, nil, {})
                end)
            end
        end
    end
    function MockCS.buy(id, count, cb)
        record({ fn = "buy", id = id, count = count })
        if cb then
            spawnCo(function()
                cb(true, nil, {})
            end)
        end
    end
end
G.__MockClientState = MockCS

local ModuleCache = {}
G.require = function(obj)
    if ModuleCache[obj] ~= nil then
        return ModuleCache[obj]
    end
    local f, err = load(obj.Source, "@" .. tostring(obj.Name), "t", G)
    if not f then
        error("mock require failed: " .. tostring(err))
    end
    local res = f()
    ModuleCache[obj] = res
    return res
end

local Workspace
do
    Workspace = Instance.new("Workspace", "Workspace")
    function Workspace:GetServerTimeNow()
        return Sched.now
    end
    Workspace.CurrentCamera = Instance.new("Camera", "Camera")
    Workspace.Gravity = 196
    local function addPart(name, pos)
        local p = Instance.new("Part", name)
        p:SetCFrame(CFrame.new(pos[1], pos[2], pos[3]))
        p.Size = Vector3.new(4, 1, 4)
        p.Anchored = true
        return p
    end
    local function addModel(name, pos)
        local m = Instance.new("Model", name)
        local part = Instance.new("Part", "Root")
        part:SetCFrame(CFrame.new(pos[1], pos[2], pos[3]))
        m:AddChild(part)
        m.PrimaryPart = part
        return m
    end
    local function place(inst)
        Workspace:AddChild(inst)
        return inst
    end
    place(addPart("SpawnLocation", { 0, 1, 0 }))
    place(addPart("tearpad", { 10, 1, 20 }))
    place(addPart("slimewalkzone", { -30, 1, 40 }))
    place(addPart("shootinghere", { 100, 1, 200 }))
    place(addModel("changelevels", { 90, 1, 180 }))
    place(addModel("gunupgradewall", { 80, 1, 160 }))
    place(addModel("prrestigewall", { 70, 1, 140 }))
    place(addModel("xzombieroll", { 60, 1, 120 }))
    place(addModel("zombiesell", { 50, 1, 100 }))
    place(addPart("milestonewall", { 40, 1, 80 }))
    place(addModel("bonus wall", { 30, 1, 60 }))
    place(addModel("convert wall", { 20, 1, 40 }))
    place(addModel("convert walltobullets", { 25, 1, 45 }))
    local rankZone = place(Instance.new("Folder", "RankZone"))
    rankZone:AddChild(addPart("Hitbox", { 5, 1, 5 }))
    local dailies = place(Instance.new("Folder", "Dailies"))
    dailies:AddChild(addModel("ClaimBoard", { -5, 1, -5 }))
    local locations = place(Instance.new("Folder", "Locations"))
    local stations = {
        { model = "RuneRoll1", sid = "Basic", pos = { 1, 1, 1 } },
        { model = "RuneRoll2", sid = "Love", pos = { 2, 1, 2 } },
        { model = "zombierunes", sid = "Zombie", pos = { 3, 1, 3 } },
    }
    for _, st in ipairs(stations) do
        local m = Instance.new("Model", st.model)
        local part = Instance.new("Part", "Root")
        part:SetCFrame(CFrame.new(st.pos[1], st.pos[2], st.pos[3]))
        m:AddChild(part)
        m.PrimaryPart = part
        m:SetAttribute("StationId", st.sid)
        locations:AddChild(m)
    end
    local lizardScene = place(Instance.new("Folder", "LizardScene"))
    MyLizard = Instance.new("Model", "Lizard_42")
    do
        local lizardPart = Instance.new("Part", "Root")
        lizardPart:SetCFrame(CFrame.new(120, 1, 210))
        MyLizard:AddChild(lizardPart)
        MyLizard.PrimaryPart = lizardPart
        MyLizard:SetAttribute("OwnerUserId", 42)
        MyLizard:SetAttribute("Tier", 2)
        MyLizard:SetAttribute("Highest", 5)
    end
    lizardScene:AddChild(MyLizard)
    local otherLizard = Instance.new("Model", "Lizard_7")
    do
        local otherPart = Instance.new("Part", "Root")
        otherPart:SetCFrame(CFrame.new(1, 1, 1))
        otherLizard:AddChild(otherPart)
        otherLizard.PrimaryPart = otherPart
        otherLizard:SetAttribute("OwnerUserId", 7)
    end
    lizardScene:AddChild(otherLizard)
    local zombieLocal = place(Instance.new("Folder", "ZombieLocal"))
    for i = 1, 2 do
        local zm = Instance.new("Model", "Zombie" .. i)
        local zp = Instance.new("Part", "Root")
        zp:SetCFrame(CFrame.new(110 + i, 1, 205))
        zm:AddChild(zp)
        zm.PrimaryPart = zp
        zombieLocal:AddChild(zm)
    end
end
G.workspace = Workspace

local RS
do
    RS = Instance.new("Folder", "ReplicatedStorage")
    local shared = Instance.new("Folder", "Shared")
    local netMod = Instance.new("ModuleScript", "Net")
    netMod.Source = "return __MockNet"
    shared:AddChild(netMod)
    local bigMod = Instance.new("ModuleScript", "BigNum")
    bigMod.Source = "return __MockBigNum"
    shared:AddChild(bigMod)
    RS:AddChild(shared)
    local config = Instance.new("Folder", "Config")
    local function addCfg(name, global)
        local m = Instance.new("ModuleScript", name)
        m.Source = "return " .. global
        config:AddChild(m)
        return m
    end
    addCfg("Upgrades", "__CfgUpgrades")
    addCfg("Walls", "__CfgWalls")
    addCfg("Currencies", "__CfgCurrencies")
    addCfg("Prestiges", "__CfgPrestiges")
    addCfg("Guns", "__CfgGuns")
    addCfg("Ranks", "__CfgRanks")
    addCfg("Converts", "__CfgConverts")
    addCfg("Potions", "__CfgPotions")
    addCfg("GemClaims", "__CfgGemClaims")
    addCfg("RuneStations", "__CfgRuneStations")
    addCfg("ReleaseGates", "__CfgReleaseGates")
    RS:AddChild(config)
    local remotes = Instance.new("Folder", "Remotes")
    for _, rn in ipairs({ "Request", "Response", "Sync" }) do
        local r = Instance.new("RemoteEvent", rn)
        r.OnClientEvent = Signal.new()
        remotes:AddChild(r)
    end
    RS:AddChild(remotes)
end

local GunActivations = 0
local Character
local function buildCharacter()
    local char = Instance.new("Model", "Char")
    local hrp = Instance.new("Part", "HumanoidRootPart")
    hrp:SetCFrame(CFrame.new(0, 5, 0))
    hrp.Size = Vector3.new(2, 2, 1)
    char:AddChild(hrp)
    char.HumanoidRootPart = hrp
    local hum = Instance.new("Humanoid", "Humanoid")
    hum.Health = 100
    hum.WalkSpeed = 16
    hum.JumpPower = 50
    hum.MoveDirection = Vector3.new(0, 0, 0)
    function hum:EquipTool(tool)
        if tool.Parent and tool.Parent._children then
            for i, c in ipairs(tool.Parent._children) do
                if c == tool then
                    table.remove(tool.Parent._children, i)
                    break
                end
            end
        end
        table.insert(self.Parent._children, tool)
        tool.Parent = self.Parent
    end
    char:AddChild(hum)
    char.PrimaryPart = hrp
    return char
end

PlayerObj = Instance.new("Player", "TestPlayer")
PlayerObj.UserId = 42
do
    local ps = Instance.new("Folder", "PlayerScripts")
    local client = Instance.new("LocalScript", "Client")
    local cs = Instance.new("ModuleScript", "ClientState")
    cs.Source = "return __MockClientState"
    client:AddChild(cs)
    ps:AddChild(client)
    PlayerObj:AddChild(ps)
    local backpack = Instance.new("Backpack", "Backpack")
    local gun = Instance.new("Tool", "Gun")
    gun.RequiresHandle = false
    function gun:Activate()
        GunActivations = GunActivations + 1
    end
    backpack:AddChild(gun)
    PlayerObj:AddChild(backpack)
    PlayerObj.Idled = Signal.new()
    PlayerObj.AncestryChanged = Signal.new()
    PlayerObj.CharacterAdded = Signal.new()
    Character = buildCharacter()
    PlayerObj.Character = Character
    Workspace:AddChild(Character)
end

local Players = { LocalPlayer = PlayerObj }
local RunService = {
    IsStudio = function()
        return false
    end,
    Heartbeat = Signal.new(),
    Stepped = Signal.new(),
    PreRender = Signal.new(),
    RenderStepped = Signal.new(),
}
local GuiService = { ErrorMessageChanged = Signal.new() }
local ProximityPromptService = { PromptButtonHoldBegan = Signal.new() }
local Lighting = {}
local HttpService = {
    JSONEncode = function(_, t)
        return tostring(t)
    end,
    JSONDecode = function(_, s)
        return {}
    end,
    GenerateGUID = function()
        return "guid"
    end,
}
local TeleportService = {
    Teleport = function() end,
    TeleportToPlaceInstance = function() end,
}
local MarketplaceService = {
    GetProductInfo = function()
        return { Name = "SCP Incremental" }
    end,
}
local UIS = {
    TouchEnabled = false,
    KeyboardEnabled = true,
}
local VirtualUser = {
    CaptureController = function() end,
    ClickButton2 = function() end,
}
local ServicesMap = {
    Players = Players,
    RunService = RunService,
    ReplicatedStorage = RS,
    Lighting = Lighting,
    HttpService = HttpService,
    GuiService = GuiService,
    TeleportService = TeleportService,
    MarketplaceService = MarketplaceService,
    UserInputService = UIS,
    VirtualUser = VirtualUser,
    ProximityPromptService = ProximityPromptService,
    Workspace = Workspace,
}
local Game
do
    Game = {
        PlaceId = 123456,
        JobId = "job",
        Workspace = Workspace,
        Loaded = Signal.new(),
    }
    Game.GetService = function(_, name)
        return ServicesMap[name] or Instance.new("Folder", name)
    end
    Game.HttpGet = function(_, url)
        if string.find(url, "Library.lua", 1, true) then
            return "return __LinoriaLibrary()"
        elseif string.find(url, "ThemeManager.lua", 1, true) then
            return "return __ThemeManagerLoader()"
        elseif string.find(url, "SaveManager.lua", 1, true) then
            return "return __SaveManagerLoader()"
        end
        error("unexpected HttpGet: " .. tostring(url))
    end
    Game.IsLoaded = function()
        return true
    end
end
G.game = Game

local chunk, loadErr = load(SCP_SRC, "@SCPIncremental", "t", G)
assert(chunk, "script compile failed: " .. tostring(loadErr))
local ok, runErr = pcall(chunk)
check("script loads without runtime error", ok)
if not ok then
    print("RUNTIME ERROR: " .. tostring(runErr))
end

local function hasErrorNotify()
    for _, n in ipairs(MockState.Notifies) do
        if string.sub(n, 1, 6) == "ERROR:" then
            return true
        end
    end
    return false
end
local function hasStepErrorNotify()
    for _, n in ipairs(MockState.Notifies) do
        if string.sub(n, 1, 9) == "Error in " then
            return true
        end
    end
    return false
end
check("no ERROR notify at load", not hasErrorNotify())
check("window created", MockState.Windows == 1)
check("guard set", G.ayasemiyatongekissazumirisa == true)

check("toggle SCPUpgrades default true", Library.Toggles.SCPUpgrades ~= nil and Library.Toggles.SCPUpgrades.Value == true)
check("toggle SCPRebirth default true", Library.Toggles.SCPRebirth ~= nil and Library.Toggles.SCPRebirth.Value == true)
check("toggle SCPPrestige default false", Library.Toggles.SCPPrestige ~= nil and Library.Toggles.SCPPrestige.Value == false)
check("toggle SCPGun default true", Library.Toggles.SCPGun ~= nil and Library.Toggles.SCPGun.Value == true)
check("toggle SCPRanks default true", Library.Toggles.SCPRanks ~= nil and Library.Toggles.SCPRanks.Value == true)
check("toggle SCPEquipRank default true", Library.Toggles.SCPEquipRank ~= nil and Library.Toggles.SCPEquipRank.Value == true)
check("toggle SCPGems default true", Library.Toggles.SCPGems ~= nil and Library.Toggles.SCPGems.Value == true)
check("toggle SCPGunFire default false", Library.Toggles.SCPGunFire ~= nil and Library.Toggles.SCPGunFire.Value == false)
check("toggle SCPTears default false", Library.Toggles.SCPTears ~= nil and Library.Toggles.SCPTears.Value == false)
check("toggle SCPLove default false", Library.Toggles.SCPLove ~= nil and Library.Toggles.SCPLove.Value == false)
check("toggle SCPRunes default false", Library.Toggles.SCPRunes ~= nil and Library.Toggles.SCPRunes.Value == false)
check("toggle SCPPotions default false", Library.Toggles.SCPPotions ~= nil and Library.Toggles.SCPPotions.Value == false)
check("toggle SCPTickets default false", Library.Toggles.SCPTickets ~= nil and Library.Toggles.SCPTickets.Value == false)
check("toggle SCPGroup default false", Library.Toggles.SCPGroup ~= nil and Library.Toggles.SCPGroup.Value == false)
check("toggle SCPLizard default false", Library.Toggles.SCPLizard ~= nil and Library.Toggles.SCPLizard.Value == false)
check("toggle SCPConvert default false", Library.Toggles.SCPConvert ~= nil and Library.Toggles.SCPConvert.Value == false)
check("dropdown SCPUpWalls exists with All", Library.Options.SCPUpWalls ~= nil and table.find(Library.Options.SCPUpWalls.Values, "All") ~= nil)
check("dropdown SCPUpWalls All selected", Library.Options.SCPUpWalls.Value ~= nil and Library.Options.SCPUpWalls.Value["All"] == true)
check("dropdown SCPConverts exists", Library.Options.SCPConverts ~= nil)
check("dropdown SCPPotionsSel exists", Library.Options.SCPPotionsSel ~= nil)
check("dropdown SCPRuneStations exists", Library.Options.SCPRuneStations ~= nil)
check("slider SCPDwell default 30", Library.Options.SCPDwell ~= nil and Library.Options.SCPDwell.Value == 30)
check("dropdown SCPTeleport exists", Library.Options.SCPTeleport ~= nil and #Library.Options.SCPTeleport.Values > 0)
check("SaveManager folder Yuri/SCPInc", SaveManager.Folder == "Yuri/SCPInc")
check("tabs include World/Stats", table.find(MockState.Tabs, "World") ~= nil and table.find(MockState.Tabs, "Stats") ~= nil)

pump(0.3)
check("no ERROR notify after first pump", not hasErrorNotify())
check("no step errors after first pump", not hasStepErrorNotify())

local function statLabelText(prefix)
    for _, l in ipairs(MockState.AllLabels) do
        if string.sub(l.Text, 1, #prefix) == prefix then
            return l.Text
        end
    end
    return nil
end
check("stats label Peanuts live", statLabelText("Peanuts: ") == "Peanuts: 90.0K")
check("stats label Prestige shows 3", statLabelText("Prestige: ") == "Prestige: 3")
check("stats label Gun Tier shows 1 (Sidearm)", statLabelText("Gun Tier: ") == "Gun Tier: 1 (Sidearm)")
check("stats label Keycards shows 0", statLabelText("Keycards: ") == "Keycards: 0")
check("stats label Tickets shows 15", statLabelText("Tickets: ") == "Tickets: 15")
check("stats label Rank shows D-Class", statLabelText("Rank: ") == "Rank: D-Class")

pump(1.5)
check("AutoBuyUpgrades bought T1_EarnMore to max", GameState.upgrades.T1_EarnMore == 5)
check("AutoBuyUpgrades bought T1_Speed to max", GameState.upgrades.T1_Speed == 3)
check("AutoBuyUpgrades skipped unaffordable R_Multi", (GameState.upgrades.R_Multi or 0) == 0)
check("AutoBuyUpgrades skipped locked-wall L_A", (GameState.upgrades.L_A or 0) == 0)
check("AutoBuyUpgrades skipped B_Dmg (requires Wall_Love)", (GameState.upgrades.B_Dmg or 0) == 0)
check("AutoBuyUpgrades skipped prestige-gated", (GameState.upgrades.T1_PrestigeGated or 0) == 0)
check("buyMax called for T1_EarnMore", findCall("buyMax", function(c)
    return c.id == "T1_EarnMore"
end) ~= nil)
check("buyMax never called for B_Dmg", findCall("buyMax", function(c)
    return c.id == "B_Dmg"
end) == nil)
check("no rebirth below threshold", countCalls("rebirth") == 0)
check("no gun purchase without bones", countCalls("request", function(c)
    return c.action == "BuyGun"
end) == 0)
check("no rank rolls without keycards", countCalls("rollRank") == 0)
check("no equip while best already equipped", countCalls("equipRank") == 0)
check("no gem claim while on cooldown", countCalls("claimGems") == 0)

GameState.currencies.Peanuts = 200000
pump(1.5)
check("AutoRebirth fired once above threshold", countCalls("rebirth") == 1)
check("peanuts reset after rebirth", GameState.currencies.Peanuts == 0)

GameState.currencies.Bones = 600
pump(1.5)
check("AutoBuyGun fired once", countCalls("request", function(c)
    return c.action == "BuyGun"
end) == 1)
check("gun tier advanced to 2", GameState.gunTier == 2)
pump(1.5)
check("no second gun purchase when poor", countCalls("request", function(c)
    return c.action == "BuyGun"
end) == 1)

GameState.keycards = 30
pump(0.7)
check("AutoRollRanks first batch capped at 25", findCall("rollRank", function(c)
    return c.count == 25
end) ~= nil)
pump(0.7)
check("AutoRollRanks rolls remainder", findCall("rollRank", function(c)
    return c.count == 5
end) ~= nil)
check("keycards drained to 0", GameState.keycards == 0)

GameState.ranks.O5 = true
pump(2.5)
check("AutoEquipBest equipped O5", findCall("equipRank", function(c)
    return c.id == "O5"
end) ~= nil)
check("equipped rank is O5", GameState.equippedRank == "O5")
pump(2.5)
check("equip not repeated", countCalls("equipRank") == 1)

GameState.gemClaim.lastClaimAt = 0
pump(31)
check("AutoClaimGems fired once", countCalls("claimGems") == 1)

do
    Library.Toggles.SCPRebirth:SetValue(false)
    Library.Toggles.SCPPrestige:SetValue(true)
    GameState.currencies.Peanuts = 1e10
    pump(2.5)
    check("AutoPrestige fired", countCalls("prestige") == 1)
    check("prestige advanced to 4", GameState.prestige == 4)
    check("peanuts reset after prestige", GameState.currencies.Peanuts == 0)
    pump(2.5)
    check("no prestige repeat while poor", countCalls("prestige") == 1)
    Library.Toggles.SCPPrestige:SetValue(false)
end

do
    Library.Toggles.SCPConvert:SetValue(true)
    Library.Options.SCPConverts.Value = { TearsToPills = true }
    GameState.currencies.Tears = 5000
    pump(2.5)
    check("AutoConvert converted TearsToPills once", countCalls("convert", function(c)
        return c.id == "TearsToPills"
    end) == 1)
    check("tears reset after convert", GameState.currencies.Tears == 0)
    check("BonesToBullets not converted (not selected)", countCalls("convert", function(c)
        return c.id == "BonesToBullets"
    end) == 0)
    Library.Toggles.SCPConvert:SetValue(false)
end

do
    Library.Toggles.SCPPotions:SetValue(true)
    Library.Options.SCPPotionsSel.Value = { ["2x Stat Boost"] = true }
    pump(5.5)
    check("AutoPotions used StatBoost once", countCalls("usePotion", function(c)
        return c.id == "StatBoost"
    end) == 1)
    check("RuneLuck potion not used (not selected)", countCalls("usePotion", function(c)
        return c.id == "RuneLuck"
    end) == 0)
    pump(6)
    check("AutoPotions no re-use while active", countCalls("usePotion") == 1)
    Library.Toggles.SCPPotions:SetValue(false)
end

do
    Library.Toggles.SCPTickets:SetValue(true)
    pump(35)
    check("ticket price queries sent", countCalls("request", function(c)
        return c.action == "GetTicketPrice"
    end) >= 2)
    check("AutoTickets bought cheapest product", findCall("request", function(c)
        return c.action == "BuyWithTickets" and c.payload.productId == 3712298906
    end) ~= nil)
    check("tickets deducted by server", GameState.tickets == 5)
    check("expensive product not bought", findCall("request", function(c)
        return c.action == "BuyWithTickets" and c.payload.productId == 3712298920
    end) == nil)
    Library.Toggles.SCPTickets:SetValue(false)
end

do
    Library.Toggles.SCPGroup:SetValue(true)
    pump(11)
    check("AutoGroupReward fired once", countCalls("request", function(c)
        return c.action == "ClaimGroupReward"
    end) == 1)
    pump(11)
    check("AutoGroupReward not repeated", countCalls("request", function(c)
        return c.action == "ClaimGroupReward"
    end) == 1)
    Library.Toggles.SCPGroup:SetValue(false)
end

do
    Library.Toggles.SCPLizard:SetValue(true)
    pump(5.5)
    check("AutoLizardLevel selected highest tier", findCall("request", function(c)
        return c.action == "SelectLizardLevel" and c.payload.tier == 5
    end) ~= nil)
    check("lizard tier advanced to 5", MyLizard:GetAttribute("Tier") == 5)
    pump(5.5)
    check("AutoLizardLevel not repeated", countCalls("request", function(c)
        return c.action == "SelectLizardLevel"
    end) == 1)
    Library.Toggles.SCPLizard:SetValue(false)
end

do
    Library.Options.SCPDwell.Value = 5
    Library.Options.SCPRuneStations.Value = { ["Basic Runes"] = true }
    Library.Toggles.SCPTears:SetValue(true)
    Library.Toggles.SCPLove:SetValue(true)
    Library.Toggles.SCPRunes:SetValue(true)
    pump(0.3)
    local hrp = Character.HumanoidRootPart
    local nearTear = (hrp.Position - Workspace:FindFirstChild("tearpad").Position).Magnitude < 5
    check("farm position starts at tearpad", nearTear)
    pump(6)
    local nearSlime = (hrp.Position - Workspace:FindFirstChild("slimewalkzone").Position).Magnitude < 5
    check("farm position rotates to slime zone", nearSlime)
    pump(6)
    local basic = Workspace:FindFirstChild("Locations"):FindFirstChild("RuneRoll1")
    local nearStation = (hrp.Position - basic:GetPivot().Position).Magnitude < 5
    check("farm position includes rune station", nearStation)
    Library.Toggles.SCPTears:SetValue(false)
    Library.Toggles.SCPLove:SetValue(false)
    Library.Toggles.SCPRunes:SetValue(false)
    local before = #Calls
    pump(4)
    local idle = true
    for i = before + 1, #Calls do
        if Calls[i].fn == "request" or Calls[i].fn == "buyMax" then
            idle = false
        end
    end
    check("farm threads stopped after toggle off", idle)
end

do
    local char = buildCharacter()
    Workspace:AddChild(char)
    PlayerObj.Character = char
    Character = char
    char.HumanoidRootPart:SetCFrame(CFrame.new(1000, 5, 1000))
    Library.Toggles.SCPGunFire:SetValue(true)
    pump(1.5)
    check("gun equipped from backpack", char:FindFirstChild("Gun") ~= nil)
    check("gun activated repeatedly", GunActivations >= 3)
    local nearShoot = (char.HumanoidRootPart.Position - Workspace:FindFirstChild("shootinghere").Position).Magnitude < 30
    check("repositioned to shooting gallery", nearShoot)
    local before = GunActivations
    pump(1)
    check("gun keeps firing", GunActivations > before)
    Library.Toggles.SCPGunFire:SetValue(false)
    local frozen = GunActivations
    pump(1)
    check("gun stops after toggle off", GunActivations == frozen)
end

do
    local teleButton = nil
    for _, b in ipairs(MockState.Buttons) do
        if b.Text == "Teleport" then
            teleButton = b
        end
    end
    check("teleport button exists", teleButton ~= nil)
    Library.Options.SCPTeleport.Value = "Gem Claim Board"
    teleButton.Func()
    local board = Workspace:FindFirstChild("Dailies"):FindFirstChild("ClaimBoard")
    local near = (Character.HumanoidRootPart.Position - board:GetPivot().Position).Magnitude < 5
    check("teleport lands at gem board", near)
    Library.Options.SCPTeleport.Value = "Rank Zone"
    teleButton.Func()
    local hitbox = Workspace:FindFirstChild("RankZone"):FindFirstChild("Hitbox")
    near = (Character.HumanoidRootPart.Position - hitbox.Position).Magnitude < 5
    check("teleport lands at rank zone", near)
    Library.Options.SCPTeleport.Value = "Basic Runes Station"
    teleButton.Func()
    local basic = Workspace:FindFirstChild("Locations"):FindFirstChild("RuneRoll1")
    near = (Character.HumanoidRootPart.Position - basic:GetPivot().Position).Magnitude < 5
    check("teleport lands at rune station", near)
end

do
    local before = #Calls
    Library.Toggles.SCPUpgrades:SetValue(false)
    pump(2)
    local stable = true
    for i = before + 1, #Calls do
        if Calls[i].fn == "buyMax" then
            stable = false
        end
    end
    check("upgrade loop stops after toggle off", stable)
    Library.Toggles.SCPUpgrades:SetValue(true)
end

check("no step errors during entire run", not hasStepErrorNotify())

do
    local unloadButton = nil
    for _, b in ipairs(MockState.Buttons) do
        if b.Text == "Unload" then
            unloadButton = b
        end
    end
    check("unload button exists", unloadButton ~= nil)
    unloadButton.Func()
    check("guard reset after unload", G.ayasemiyatongekissazumirisa == false)
    check("Library unloaded", Library.Unloaded == true)
    pump(1)
    check("no ERROR notify after unload pump", not hasErrorNotify())
end

print(string.format("\n===== RESULTS: %d passed, %d failed =====", Pass, Fail))
if #Failures > 0 then
    print("FAILED:")
    for _, f in ipairs(Failures) do
        print("  - " .. f)
    end
    os.exit(1)
end
