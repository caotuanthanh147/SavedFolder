local PLACE = (arg and arg[1]) or "Round"
local passCount, failCount = 0, 0
local failures = {}
local function check(name, cond)
    if cond then passCount = passCount + 1 else failCount = failCount + 1; failures[#failures + 1] = name; print("FAIL: " .. name) end
end
if not math.clamp then
    math.clamp = function(x, lo, hi) return math.max(lo, math.min(hi, x)) end
end
if not table.find then
    table.find = function(list, value)
        for i, v in ipairs(list) do if v == value then return i end end
        return nil
    end
end
if not table.freeze then
    table.freeze = function(t) return t end
end
local notifies = {}
local notyuriLog = {}
local virtualClock = 100
local spawnedCos = {}
local function trackCo(co)
    spawnedCos[#spawnedCos + 1] = co
    return co
end
local function coAlive(co)
    return co and coroutine.status(co) == "suspended"
end
local function pumpAll(n)
    for _ = 1, (n or 1) do
        for _, co in ipairs(spawnedCos) do
            if coAlive(co) then
                local ok, err = coroutine.resume(co)
                if not ok then notyuriLog[#notyuriLog + 1] = "CO-ERR: " .. tostring(err) end
            end
        end
    end
end
SPAWN_LOG = false
local spawnLog = {}
task = {
    wait = function(t)
        virtualClock = virtualClock + (t or 0.1)
        if select(2, coroutine.running()) == false then
            coroutine.yield()
        end
    end,
    spawn = function(f, ...)
        local callerTb = nil
        if SPAWN_LOG then
            callerTb = debug.traceback("spawned-from", 2)
        end
        local co
        co = coroutine.create(function(...)
            if callerTb then
                spawnLog[#spawnLog + 1] = { tb = callerTb, co = co }
            end
            return f(...)
        end)
        local ok, err = coroutine.resume(co, ...)
        if not ok then error(err) end
        return trackCo(co)
    end,
    delay = function(t, f) end,
    defer = function(f, ...) local ok, err = coroutine.resume(coroutine.create(f), ...) if not ok then notyuriLog[#notyuriLog + 1] = "DEFER-ERR: " .. tostring(err) end end,
    cancel = function(co) pcall(coroutine.close, co) end,
}
tick = function() return virtualClock end
local V3mt = {}
local function v3(x, y, z)
    x, y, z = x or 0, y or 0, z or 0
    return setmetatable({ X = x, Y = y, Z = z, Magnitude = math.sqrt(x * x + y * y + z * z), Unit = nil }, V3mt)
end
V3mt.__add = function(a, b) return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V3mt.__sub = function(a, b) return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V3mt.__index = function(t, k)
    if k == "Unit" then
        local m = t.Magnitude
        if m == 0 then return v3(0, 0, 0) end
        return v3(t.X / m, t.Y / m, t.Z / m)
    end
    return nil
end
Vector3 = { new = v3, zero = v3(0, 0, 0) }
Vector2 = { new = function(x, y) return { X = x or 0, Y = y or 0, Magnitude = math.sqrt((x or 0) ^ 2 + (y or 0) ^ 2) } end }
local CFmt = {}
local function cf(pos) return setmetatable({ Position = pos or v3() }, CFmt) end
CFmt.__sub = function(a, b)
    local ap, bp = a.Position or v3(), b.Position or v3()
    return v3(ap.X - bp.X, ap.Y - bp.Y, ap.Z - bp.Z)
end
CFmt.__mul = function(a, b)
    local ap, bp = a.Position or v3(), b.Position or v3()
    return cf(v3(ap.X + bp.X, ap.Y + bp.Y, ap.Z + bp.Z))
end
CFrame = {
    new = function(x, y, z)
        if type(x) == "table" then return cf(x) end
        return cf(v3(x, y, z))
    end,
}
Color3 = { fromRGB = function(r, g, b) return { R = r, G = g, B = b } end }
Enum = { RaycastFilterType = { Include = 1, Exclude = 2 } }
RaycastParams = { new = function() return { FilterType = nil, FilterDescendantsInstances = nil } end }
local Signal = {}
Signal.__index = Signal
local function makeSignal(name)
    return setmetatable({ Name = name or "Signal", _handlers = {} }, Signal)
end
function Signal:Connect(fn)
    self._handlers[#self._handlers + 1] = fn
    return { Connected = true, Disconnect = function() end }
end
function Signal:Fire(...)
    for _, fn in ipairs(self._handlers) do
        local ok, err = pcall(fn, ...)
        if not ok then notyuriLog[#notyuriLog + 1] = "SIG-ERR: " .. tostring(err) end
    end
end
function Signal:Wait()
    return nil, 100
end
local Inst = {}
Inst.__index = Inst
local function makeInst(name, className)
    local self = setmetatable({ Name = name, ClassName = className, _children = {}, _attrs = {}, _signals = {}, Position = v3(), Size = v3(4, 2, 4), Value = 0 }, Inst)
    return self
end
local ClassParents = { Part = "BasePart", MeshPart = "BasePart", SpawnLocation = "BasePart", WedgePart = "BasePart", Configuration = "Configuration" }
function Inst:IsA(c)
    if self.ClassName == c then return true end
    return ClassParents[self.ClassName] == c
end
function Inst:FindFirstChild(n)
    for _, c in ipairs(self._children) do if c.Name == n then return c end end
    return nil
end
function Inst:WaitForChild(n, t)
    local found = self:FindFirstChild(n)
    if found or (t and t <= 0) then return found end
    return found
end
function Inst:GetChildren()
    local list = {}
    for _, c in ipairs(self._children) do list[#list + 1] = c end
    table.sort(list, function(a, b) return a.Name < b.Name end)
    return list
end
function Inst:GetDescendants()
    local list = {}
    local function walk(folder)
        for _, c in pairs(folder._children) do
            list[#list + 1] = c
            walk(c)
        end
    end
    walk(self)
    return list
end
function Inst:IsDescendantOf(anc)
    local cur = self
    while cur do
        if cur == anc then return true end
        cur = cur.Parent
    end
    return false
end
function Inst:GetAttribute(k) return self._attrs[k] end
function Inst:SetAttribute(k, v)
    self._attrs[k] = v
    local sig = self._signals["attr_" .. k]
    if sig then sig:Fire(v) end
end
function Inst:GetAttributeChangedSignal(k)
    if not self._signals["attr_" .. k] then self._signals["attr_" .. k] = makeSignal("attr:" .. self.Name .. "." .. k) end
    return self._signals["attr_" .. k]
end
function Inst:FindFirstChildWhichIsA(c)
    for _, child in pairs(self._children) do
        if child:IsA(c) then return child end
    end
    return nil
end
function Inst:FindFirstChildOfClass(c)
    for _, child in pairs(self._children) do
        if child.ClassName == c then return child end
    end
    return nil
end
function Inst:AddChild(child)
    self._children[#self._children + 1] = child
    child.Parent = self
    return child
end
function Inst:RemoveChild(name)
    for i, c in ipairs(self._children) do
        if c.Name == name then
            table.remove(self._children, i)
            c.Parent = nil
            return c
        end
    end
    return nil
end
function Inst:GetPivot() return cf(self.Position) end
function Inst:PivotTo(c2) self.Position = c2.Position end
function Inst:GetBoundingBox() return cf(self.Position), self.Size end
function Inst:Clone()
    local c = makeInst(self.Name, self.ClassName)
    for k, v in pairs(self._attrs) do c._attrs[k] = v end
    return c
end
function Inst:Destroy()
    if self.Parent then
        for i, c in ipairs(self.Parent._children) do
            if c == self then
                table.remove(self.Parent._children, i)
                break
            end
        end
    end
end
function Inst:Split(s) 
    local out = {}
    for part in string.gmatch(s or "", "[^%.]+") do out[#out + 1] = part end
    return out
end
string.split = function(s, sep)
    local out = {}
    for part in string.gmatch(s or "", "([^" .. (sep or ",") .. "]+)") do out[#out + 1] = part end
    return out
end
local fires = {}
local fireLog = {}
local invokes = {}
local invokeResults = {}
local invokeScript = {}
local currentMethod = nil
local namecallDispatcher
local namecallHook
local function mockRemote(name, className)
    local r = makeInst(name, className or "RemoteEvent")
    if r.ClassName == "RemoteEvent" then
        r.InvokeServerRaw = function() error("RemoteEvent has no InvokeServer") end
        r.InvokeServer = function() error("RemoteEvent InvokeServer") end
        r._FireRaw = function(_, ...)
            fires[name] = fires[name] or {}
            local entry = { n = select("#", ...) }
            for i = 1, entry.n do entry[i] = select(i, ...) end
            table.insert(fires[name], entry)
            fireLog[#fireLog + 1] = name
        end
        r.FireServer = function(self, ...)
            currentMethod = "FireServer"
            return namecallHook(self, ...)
        end
        r.OnClientEvent = makeSignal(name .. ".OnClientEvent")
    else
        r._InvokeRaw = function(_, ...)
            invokes[name] = invokes[name] or {}
            local entry = { n = select("#", ...) }
            for i = 1, entry.n do entry[i] = select(i, ...) end
            table.insert(invokes[name], entry)
            local scriptFn = invokeScript[name]
            if type(scriptFn) == "function" then return scriptFn(...) end
            return invokeResults[name]
        end
        r._FireRaw = function() error("RemoteFunction has no FireServer") end
        r.InvokeServer = function(self, ...)
            currentMethod = "InvokeServer"
            return namecallHook(self, ...)
        end
    end
    return r
end
namecallDispatcher = function(self, ...)
    if currentMethod == "InvokeServer" then
        return self:_InvokeRaw(...)
    elseif currentMethod == "FireServer" then
        self:_FireRaw(...)
        return nil
    end
    error("unexpected namecall method: " .. tostring(currentMethod))
end
namecallHook = namecallDispatcher
hookmetamethod = function(g, m, hook)
    local old = namecallHook
    namecallHook = hook
    return old
end
getnamecallmethod = function() return currentMethod end
newcclosure = function(f) return f end
local httpRequests = {}
request = function(opts)
    httpRequests[#httpRequests + 1] = opts
    return { StatusCode = 200, Success = true }
end
typeof = function(v)
    if type(v) == "table" then
        local mt = getmetatable(v)
        if mt == V3mt then return "Vector3" end
        if mt == CFmt then return "CFrame" end
        if rawget(v, "ClassName") then return "Instance" end
    end
    return type(v)
end
local files = {}
isfolder = function(p) return true end
makefolder = function(p) end
isfile = function(p) return files[p] ~= nil end
writefile = function(p, c) files[p] = c end
readfile = function(p) return files[p] end
delfile = function(p) files[p] = nil end
appendfile = function(p, c) files[p] = (files[p] or "") .. c end
listfiles = function(p)
    local out = {}
    local prefix = p .. "/"
    for k in pairs(files) do
        if k:sub(1, #prefix) == prefix and not k:find("/", #prefix + 1, true) then
            out[#out + 1] = k
        end
    end
    return out
end
getgenv = function() return _G end
cloneref = function(x) return x end
getconnections = function(sig)
    return { { Disable = function() end, Enable = function() end, Disconnect = function() end } }
end
get_signal_cons = getconnections
getgc = function() return {} end
identifyexecutor = function() return "Harness" end
setfpscap = function() end
setclipboard = function() end
hookfunction = function(f) return f end
queue_on_teleport = function() end
queueonteleport = function() end
fireproximityprompt = function() end
fireclickdetector = function() end
firetouchinterest = function() end
firesignal = function(sig, ...) sig:Fire(...) end
coroutineRunningShim = coroutine.running
local function requireShim(obj)
    if type(obj) == "table" and obj.__module ~= nil then return obj.__module end
    error("require: not a mock module " .. tostring(obj and obj.Name))
end
require = requireShim
local function makeModule(name, tbl)
    local m = makeInst(name, "ModuleScript")
    m.__module = tbl
    return m
end
if not table.create then
    table.create = function(n, v)
        local t = {}
        if v ~= nil then for i = 1, n do t[i] = v end end
        return t
    end
end
if not table.clone then
    table.clone = function(t)
        local c = {}
        for k, v in pairs(t) do c[k] = v end
        return c
    end
end
if not table.clear then
    table.clear = function(t) for k in pairs(t) do t[k] = nil end end
end
unpack = table.unpack

local Toggles = {}
local Options = {}
local Labels = {}
local elementLog = {}
local Library
local function makeToggle(id, info)
    local t = { Value = info.Default or false, _onChanged = {}, Id = id }
    function t:OnChanged(fn) self._onChanged[#self._onChanged + 1] = fn end
    function t:SetValue(v)
        self.Value = v
        for _, fn in ipairs(self._onChanged) do task.spawn(fn, v) end
    end
    Toggles[id] = t
    elementLog[#elementLog + 1] = { kind = "Toggle", id = id }
    return t
end
local function makeOption(id, info)
    local o = { Value = info.Default, Values = info.Values or {}, _onChanged = {}, Id = id }
    if info.Multi then
        local m = {}
        for _, l in ipairs(info.Default or {}) do m[l] = true end
        o.Value = m
    end
    function o:OnChanged(fn) self._onChanged[#self._onChanged + 1] = fn end
    function o:SetValues(list)
        self.Values = list
        if not info.Multi and self.Value ~= nil and not table.find(list, self.Value) then
            if list[1] ~= nil then self.Value = list[1] end
        end
    end
    function o:SetVisible(v) self.Visible = v end
    function o:SetValue(v)
        self.Value = v
        for _, fn in ipairs(self._onChanged) do task.spawn(fn, v) end
    end
    Options[id] = o
    elementLog[#elementLog + 1] = { kind = info._optKind or "Option", id = id }
    return o
end
local function makeLabelMock(id, text)
    local l = { Value = text, Id = id }
    function l:SetText(s) l.Value = s end
    function l:AddKeyPicker(id2, info) return makeOption(id2, { Default = info.Default }) end
    Labels[id] = l
    return l
end
local Groupbox = {}
Groupbox.__index = Groupbox
local function makeGroupbox(name)
    return setmetatable({ Name = name }, Groupbox)
end
function Groupbox:AddToggle(id, info) return makeToggle(id, info) end
function Groupbox:AddDropdown(id, info)
    info._optKind = "Dropdown"
    return makeOption(id, info)
end
function Groupbox:AddSlider(id, info)
    info._optKind = "Slider"
    info.Default = info.Default or info.Min or 0
    return makeOption(id, info)
end
function Groupbox:AddInput(id, info)
    info._optKind = "Input"
    info.Default = info.Default or ""
    return makeOption(id, info)
end
function Groupbox:AddButton(a, b)
    local info = type(a) == "table" and a or { Text = a, Func = b }
    elementLog[#elementLog + 1] = { kind = "Button", id = info and info.Text or "?", func = info.Func }
    return { AddButton = function(self2, t2)
        elementLog[#elementLog + 1] = { kind = "SubButton", id = t2.Text }
        return self2
    end }
end
local labelCounter = 0
function Groupbox:AddLabel(text, wrap, id)
    labelCounter = labelCounter + 1
    return makeLabelMock(id or ("L" .. labelCounter), text)
end
function Groupbox:AddDivider() return self end
function Groupbox:AddKeyPicker(id, info) return makeOption(id, { Default = info.Default }) end
local makeTabbox
local Tab = {}
Tab.__index = Tab
local function makeTab(name)
    return setmetatable({ Name = name }, Tab)
end
function Tab:AddLeftGroupbox(n) return makeGroupbox(n) end
function Tab:AddToggle(id, info) return makeToggle(id, info) end
function Tab:AddDropdown(id, info)
    info._optKind = "Dropdown"
    return makeOption(id, info)
end
function Tab:AddSlider(id, info)
    info._optKind = "Slider"
    info.Default = info.Default or info.Min or 0
    return makeOption(id, info)
end
function Tab:AddInput(id, info)
    info._optKind = "Input"
    info.Default = info.Default or ""
    return makeOption(id, info)
end
function Tab:AddButton(a, b)
    local info = type(a) == "table" and a or { Text = a, Func = b }
    elementLog[#elementLog + 1] = { kind = "Button", id = info and info.Text or "?", func = info.Func }
    return { AddButton = function(self2, t2)
        elementLog[#elementLog + 1] = { kind = "SubButton", id = t2.Text }
        return self2
    end }
end
function Tab:AddLabel(text, wrap, id)
    labelCounter = labelCounter + 1
    return makeLabelMock("tablabel" .. tostring(labelCounter), text)
end
function Tab:AddDivider() return self end
function Tab:AddRightGroupbox(n) return makeGroupbox(n) end
function Tab:AddGroupbox(n) return makeGroupbox(n) end
function Tab:AddLeftTabbox() return makeTabbox() end
function Tab:AddRightTabbox() return makeTabbox() end
function Tab:AddTab(n) return makeTab(n) end
local Tabbox = {}
Tabbox.__index = Tabbox
makeTabbox = function()
    return setmetatable({}, Tabbox)
end
function Tabbox:AddTab(n) return makeTab(n) end
local Window = {}
Window.__index = Window
local function makeWindow()
    return setmetatable({}, Window)
end
function Window:AddTab(n) return makeTab(n) end
function Window:SetWindowTitle() end
function Window:Toggle() end
Library = {
    Unloaded = false,
    Notify = function(self, msg, t)
        if type(self) ~= "table" then msg = self end
        notifies[#notifies + 1] = tostring(msg)
    end,
    Toggles = Toggles,
    Options = Options,
    Labels = Labels,
    KeybindFrame = { Visible = false },
    CreateWindow = function() return makeWindow() end,
    SetDPIScale = function() end,
    SetWatermark = function() end,
    SetWatermarkVisibility = function() end,
    Unload = function() Library.Unloaded = true end,
    OnUnload = function() end,
    GiveSignal = function() end,
    SetNotifySide = function() end,
    NotifySide = "Left",
    ShowToggleFrameInKeybinds = true,
    ShowCustomCursor = true,
    ToggleKeybind = nil,
}
getgenv().Library = Library
getgenv().Linoria = Library
getgenv().skip_getgenv_linoria = true
local SaveManager
SaveManager = {
    SetLibrary = function() end,
    SetFolder = function(self, f) SaveManager.Folder = f end,
    SetSubFolder = function() end,
    IgnoreThemeSettings = function() end,
    SetIgnoreIndexes = function() end,
    BuildConfigSection = function() end,
    LoadAutoloadConfig = function() end,
    SetLoadingOrder = function() end,
    AttemptSave = function() end,
}
local ThemeManager = {
    SetLibrary = function() end,
    SetFolder = function() end,
    ApplyToTab = function() end,
    ApplyToGroupbox = function() end,
}
local HttpService = {
    JSONEncode = function(self, t) return (function()
        local parts = {}
        local function esc(s) return tostring(s):gsub('[%c"\\]', function(c) return string.format("\\u%04x", string.byte(c)) end) end
        local function encode(v)
            local tv = type(v)
            if tv == "table" then
                local isArr = (#v > 0)
                local items = {}
                if isArr then
                    for _, item in ipairs(v) do items[#items + 1] = encode(item) end
                    return "[" .. table.concat(items, ",") .. "]"
                end
                for k, item in pairs(v) do items[#items + 1] = '"' .. esc(k) .. '":' .. encode(item) end
                return "{" .. table.concat(items, ",") .. "}"
            elseif tv == "string" then
                return '"' .. esc(v) .. '"'
            elseif tv == "boolean" then
                return tostring(v)
            elseif tv == "number" then
                return tostring(v)
            end
            return "null"
        end
        return encode(t)
    end)() end,
    JSONDecode = function(self, s)
        local s2 = s
        return (function()
            local arr = {}
            local dict = {}
            local pos = 1
            local json = s2
            local function skipWs()
                while pos <= #json and json:sub(pos, pos):match("[%s]") do pos = pos + 1 end
            end
            local function parseValue()
                skipWs()
                local c = json:sub(pos, pos)
                if c == "{" then
                    pos = pos + 1
                    local obj = {}
                    skipWs()
                    if json:sub(pos, pos) == "}" then pos = pos + 1 return obj end
                    while true do
                        skipWs()
                        local key = parseValue()
                        skipWs()
                        pos = pos + 1
                        local val = parseValue()
                        obj[key] = val
                        skipWs()
                        local d = json:sub(pos, pos)
                        pos = pos + 1
                        if d == "}" then return obj end
                    end
                elseif c == "[" then
                    pos = pos + 1
                    local obj = {}
                    skipWs()
                    if json:sub(pos, pos) == "]" then pos = pos + 1 return obj end
                    while true do
                        obj[#obj + 1] = parseValue()
                        skipWs()
                        local d = json:sub(pos, pos)
                        pos = pos + 1
                        if d == "]" then return obj end
                    end
                elseif c == '"' then
                    pos = pos + 1
                    local out = {}
                    while true do
                        local ch = json:sub(pos, pos)
                        if ch == '"' then pos = pos + 1 break end
                        if ch == "\\" then
                            local nxt = json:sub(pos + 1, pos + 1)
                            if nxt == "u" then
                                local hex = json:sub(pos + 2, pos + 5)
                                out[#out + 1] = string.char(tonumber(hex, 16) or 63)
                                pos = pos + 6
                            else
                                out[#out + 1] = nxt
                                pos = pos + 2
                            end
                        else
                            out[#out + 1] = ch
                            pos = pos + 1
                        end
                    end
                    return table.concat(out)
                elseif json:sub(pos, pos + 3) == "true" then
                    pos = pos + 4
                    return true
                elseif json:sub(pos, pos + 4) == "false" then
                    pos = pos + 5
                    return false
                elseif json:sub(pos, pos + 3) == "null" then
                    pos = pos + 4
                    return nil
                else
                    local num = json:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
                    if num then
                        pos = pos + #num
                        return tonumber(num)
                    end
                    error("bad json at " .. pos)
                end
            end
            return parseValue()
        end)()
    end,
    GenerateGUID = function() return "guid" end,
}
local RunService = { Stepped = makeSignal("Stepped"), Heartbeat = makeSignal("Heartbeat"), RenderStepped = makeSignal("RenderStepped"), IsServer = function() return false end, Set3dRenderingEnabled = function() end }
local UIS = { TouchEnabled = false, KeyboardEnabled = true }
local VirtualUser = { CaptureController = function() end, ClickButton2 = function() end }
local gameJoinPads = {}
local CollectionService = { HasTag = function() return false end, GetTagged = function(_, tag) return (tag == "GameJoinPad" and gameJoinPads) or {} end, GetInstanceAddedSignal = function() return makeSignal() end, GetInstanceRemovedSignal = function() return makeSignal() end }
local Marketplace = { GetProductInfo = function() return { Name = "SNACK Defense!" } end, PromptPurchase = function() end }
local Services = {}
local function addService(name, obj) Services[name] = obj end
addService("Players", { LocalPlayer = nil })
addService("ReplicatedStorage", nil)
addService("RunService", RunService)
addService("HttpService", HttpService)
addService("GuiService", { SelectedObject = nil })
addService("TeleportService", { Teleport = function() end, TeleportToPlaceInstance = function() end })
addService("MarketplaceService", Marketplace)
addService("UserInputService", UIS)
addService("VirtualUser", VirtualUser)
addService("Lighting", { GlobalShadows = true, FogEnd = 1, Brightness = 1, ClockTime = 14 })
addService("CollectionService", CollectionService)
addService("ProximityPromptService", { PromptButtonHoldBegan = makeSignal("PPS") })
addService("VirtualInputManager", { SendKeyEvent = function() end })
game = {
    PlaceId = (PLACE == "Lobby" and 99714898369873) or (PLACE == "Afk" and 128786154993450) or 108164777899140,
    JobId = "job-1",
    GameId = 10231502419,
    GetService = function(self, name)
        return Services[name] or error("Invalid Service: " .. name)
    end,
    HttpGet = function(self, url)
        if url:find("Library.lua") then return "LIB" end
        if url:find("ThemeManager") then return "THEME" end
        if url:find("SaveManager") then return "SAVE" end
        return ""
    end,
    IsLoaded = function() return true end,
}
local loadstringShim = function(s)
    if s == "LIB" then return function() return Library end end
    if s == "THEME" then return function() return ThemeManager end end
    if s == "SAVE" then return function() return SaveManager end end
    return function() return nil end
end
loadstring = loadstringShim

local RS = makeInst("ReplicatedStorage", "ReplicatedStorage")
Services.ReplicatedStorage = RS
workspace = makeInst("Workspace", "Workspace")
function workspace:Raycast(origin, dir, params)
    if dir.Y >= 0 then return nil end
    local map = nil
    if type(params) == "table" and type(params.FilterDescendantsInstances) == "table" then
        for _, inst in ipairs(params.FilterDescendantsInstances) do
            if type(inst) == "table" and inst.Parent == workspace then
                map = inst
                break
            end
        end
    end
    if not map then return nil end
    return { Instance = map, Position = v3(origin.X, 0, origin.Z) }
end
workspace.Gravity = 192
workspace.CurrentCamera = { FieldOfView = 70 }
local PLR_USER_ID = 42
local Plr = makeInst("hspspjl", "Player")
Plr.UserId = PLR_USER_ID
Services.Players.LocalPlayer = Plr
local charRoot = makeInst("HumanoidRootPart", "Part")
charRoot.Position = v3(0, 5, 0)
charRoot.CFrame = cf(charRoot.Position)
local humanoid = makeInst("Humanoid", "Humanoid")
local character = makeInst("Char", "Model")
character:AddChild(charRoot)
character:AddChild(humanoid)
character.PrimaryPart = charRoot
Plr.Character = character
Plr:SetAttribute("DataLoaded", true)
Plr:SetAttribute("RoundCurrency", 1000)
Plr:SetAttribute("IsPartyHost", false)
Plr:SetAttribute("PartyPadId", "")
Plr:SetAttribute("WinStreak", 3)
Plr:SetAttribute("GroupRewardClaimed", false)
Plr:SetAttribute("QuestsUnlocked", true)
Plr:SetAttribute("OwnsSpeed3", false)
Plr:SetAttribute("OwnsSpeed5", false)
local FrameworkEvents = makeInst("FrameworkEvents", "Folder")
RS:AddChild(FrameworkEvents)
local function addRemote(name, className)
    local r = mockRemote(name, className)
    FrameworkEvents:AddChild(r)
    return r
end
local ROUND_REMOTE_DEFS = {
    { "PlaceTower", "RemoteFunction" }, { "UpgradeTower", "RemoteFunction" }, { "SellTower", "RemoteFunction" }, { "SetTowerTarget", "RemoteFunction" },
    { "SetHeldTower", "RemoteEvent" }, { "RequestGameSpeed", "RemoteEvent" }, { "RequestPauseToggle", "RemoteEvent" }, { "ModalVote", "RemoteEvent" },
    { "RequestNextLevel", "RemoteEvent" }, { "RequestReplayLevel", "RemoteEvent" }, { "RequestReturnToLobby", "RemoteEvent" }, { "RequestRestartMatch", "RemoteEvent" }, { "RequestPlayNewMap", "RemoteEvent" },
}
local LOBBY_REMOTE_DEFS = {
    { "QuestState", "RemoteFunction" }, { "QuestClaim", "RemoteFunction" }, { "StarsFuseRequest", "RemoteFunction" }, { "RequestGroupRewardClaim", "RemoteFunction" }, { "IndexRewardClaim", "RemoteFunction" },
    { "RequestPlay", "RemoteEvent" }, { "LeaveParty", "RemoteEvent" }, { "RequestSummon", "RemoteEvent" }, { "EquipBestTowers", "RemoteEvent" },
    { "DeleteTowers", "RemoteEvent" }, { "SetTowerEquipped", "RemoteEvent" }, { "RequestTraitRoll", "RemoteEvent" }, { "RequestAfkTeleport", "RemoteEvent" },
    { "MatchRejoinAnswer", "RemoteEvent" }, { "MatchRejoinOffer", "RemoteEvent" },
    { "RequestStartGame", "RemoteEvent" },
}
local remoteDefs = (PLACE == "Lobby" and LOBBY_REMOTE_DEFS) or ROUND_REMOTE_DEFS
for _, def in ipairs(remoteDefs) do
    addRemote(def[1], def[2])
end
if PLACE == "Round" then
    RS:SetAttribute("SelectedMap", "CandyDefense")
    RS:SetAttribute("SelectedLevel", 1)
    RS:SetAttribute("RoundActive", true)
    RS:SetAttribute("RoundPhase", "Prep")
else
    RS:SetAttribute("RoundActive", false)
    RS:SetAttribute("RoundPhase", "Waiting")
end
RS:SetAttribute("CurrentWave", 2)
RS:SetAttribute("TotalWaves", 6)
RS:SetAttribute("WavesCleared", 1)
RS:SetAttribute("BaseHealth", 150)
RS:SetAttribute("BaseHealthMax", 150)
RS:SetAttribute("ModalVoteId", 0)
RS:SetAttribute("EndlessMatch", false)
RS:SetAttribute("MatchId", "match-1")
RS:SetAttribute("MobsRemaining", 5)
RS:SetAttribute("MatchBestWave", 0)
RS:SetAttribute("MatchDuration", 120)
RS:SetAttribute("GameSpeed", 1)
local PlacementMath = {
    GRID_SIZE = 0.25,
    SPACING_PADDING = 0.25,
    FOOTPRINT_SCALE = 0.7071,
    snapAxis = function(x, s) return math.floor(x / s + 0.5) * s end,
    footprintRadius = function(x, z) return 0.7071 * 0.5 * math.sqrt(x * x + z * z) end,
    hasClearance = function(pos, radius, others, padding)
        local pad = padding or 0.25
        for _, other in ipairs(others or {}) do
            local dx = pos.X - other.position.X
            local dz = pos.Z - other.position.Z
            local need = radius + other.radius + pad
            if dx * dx + dz * dz < need * need then
                return false, other
            end
        end
        return true
    end,
    spotSampleRadius = function(r)
        local n = tonumber(r) or 0
        if n <= 0 then return 0 end
        return n * 0.85 + 0.5
    end,
    maxForTower = function(cfg, settings)
        if cfg.CustomMaxPerPlayer ~= nil then return cfg.CustomMaxPerPlayer end
        return settings and settings.MaxTowerPerPlayer
    end,
}
local PA_LAYOUT = {
    cols = 11, rows = 11, cell = 2, minX = 0, minZ = 0,
    legal = {}, groundY = {}, clearance = {},
}
for i = 1, 121 do
    PA_LAYOUT.legal[i] = true
    PA_LAYOUT.groundY[i] = 0
    PA_LAYOUT.clearance[i] = 999
end
local PlacementArea = {
    Get = function() return PA_LAYOUT end,
    Start = function() end,
    IndexOf = function(l, x, z)
        local c = math.floor((x - l.minX) / l.cell + 0.5) + 1
        local r = math.floor((z - l.minZ) / l.cell + 0.5) + 1
        if c < 1 or c > l.cols or r < 1 or r > l.rows then return nil end
        return (r - 1) * l.cols + c
    end,
    ForEachCellByDistance = function(l, x, z, maxDist, fn)
        local cc = math.floor((x - l.minX) / l.cell + 0.5) + 1
        local cr = math.floor((z - l.minZ) / l.cell + 0.5) + 1
        local rings = math.ceil((maxDist or 100) / l.cell)
        local function offer(c, r)
            if c < 1 or c > l.cols or r < 1 or r > l.rows then return false end
            local idx = (r - 1) * l.cols + c
            if not l.legal[idx] then return false end
            local cx = l.minX + (c - 1) * l.cell
            local cz = l.minZ + (r - 1) * l.cell
            return fn(idx, cx, cz, l.groundY[idx], l.clearance[idx]) == true
        end
        if cc >= 1 and cc <= l.cols and cr >= 1 and cr <= l.rows and offer(cc, cr) then return end
        for ring = 1, rings do
            for c = cc - ring, cc + ring do
                if offer(c, cr - ring) then return end
                if offer(c, cr + ring) then return end
            end
            for r = cr - ring + 1, cr + ring - 1 do
                if offer(cc - ring, r) then return end
                if offer(cc + ring, r) then return end
            end
        end
    end,
}
local TowersMock = {
    Towers = {
        Melon = { Name = "Melon", Cost = 250, Range = 30, Rarity = "common", Upgrades = { { Cost = 200 }, { Cost = 450 }, { Cost = 900 } }, CanHitAir = false },
        Soup = { Name = "Soup", Cost = 500, Range = 12, Rarity = "common", Upgrades = { { Cost = 400 }, { Cost = 800 } }, CanHitAir = false },
        Fortune = { Name = "Fortune", Cost = 1300, Range = 40, Rarity = "mythic", CustomMaxPerPlayer = 1, Upgrades = { { Cost = 1040 } }, CanHitAir = true },
    },
    GlobalSettings = { MaxTotalTowers = 20, MaxTowerPerPlayer = 6 },
}
local TowerTraitsMock = {
    Get = function(_, trait)
        local map = { ["Damage1"] = { Tier = 1 }, ["Damage2"] = { Tier = 2 }, ["Reach2"] = { Tier = 2 }, ["Reach3"] = { Tier = 3 } }
        return map[trait]
    end,
    IsTrait = function(_, trait) return trait == "Damage1" or trait == "Damage2" or trait == "Reach2" or trait == "Reach3" end,
}
local TowerStarsMock = {
    MaxStars = 5,
    CopiesPerStar = { basic = 5, common = 5, rare = 5, epic = 5, legendary = 4, mythic = 2 },
    ExclusiveCopies = 3,
    MaxFodder = 5,
    copiesFor = function(_, cfg)
        if cfg.Limited == true then return 3 end
        return TowerStarsMock.CopiesPerStar[cfg.Rarity] or 5
    end,
    starsOf = function(_, n) return math.clamp(math.floor(tonumber(n) or 0), 0, 5) end,
}
local SummonDictionaryMock = {
    BasicSummon = { Name = "Basic Summon", Cost = { { Currency = "Gems", Amount = 100, CanBuy = true, AvailableAmounts = { 1, 5 } } } },
    GourmetSummon = { Name = "Gourmet Summon", Cost = { { Currency = "Gems", Amount = 500, CanBuy = true, AvailableAmounts = { 1, 5 } } } },
    JackpotSummon = { Name = "Jackpot Summon", Cost = { { Currency = "Robux", Amount = 199, CanBuy = true, AvailableAmounts = { 1, 3 } } } },
}
local QuestsMock = {
    Boards = { Daily = "Daily", Weekly = "Weekly" },
    Slots = { Daily = { "Tier1", "Tier2", "Tier3", "Vip" }, Weekly = { "Tier1", "Tier2", "Tier3", "Tier4" } },
    isClaimable = function(_, entry)
        return (entry.Target or math.huge) <= (entry.Progress or 0) and entry.Claimed ~= true
    end,
}
local FrameworkSettingsMock = {
    LobbyPlaceId = 99714898369873,
    RoundPlaceId = 108164777899140,
    AfkPlaceId = 128786154993450,
    IsLobbyPlace = function(_) return game.PlaceId == 99714898369873 end,
    IsAfkPlace = function(_) return game.PlaceId == 128786154993450 end,
}
local LevelCurveMock = {
    Curve = { MaxWaves = { 6, 10, 14, 20, 26, 32 } },
}
local Templates = makeInst("Templates", "Folder")
Templates:AddChild(makeModule("FrameworkSettings", FrameworkSettingsMock))
Templates:AddChild(makeModule("Towers", TowersMock))
Templates:AddChild(makeModule("TowerTraits", TowerTraitsMock))
Templates:AddChild(makeModule("TowerStars", TowerStarsMock))
Templates:AddChild(makeModule("SummonDictionary", SummonDictionaryMock))
Templates:AddChild(makeModule("Quests", QuestsMock))
local MapsFolder = makeInst("Maps", "Folder")
MapsFolder:AddChild(makeModule("CandyDefense", { MapDisplayName = "Candy Defense" }))
MapsFolder:AddChild(makeModule("EnchantedForest", { MapDisplayName = "Enchanted Forest" }))
MapsFolder:AddChild(makeModule("DumplingDefense", { MapDisplayName = "Dumpling Defense" }))
MapsFolder:AddChild(makeModule("Geometry", {}))
MapsFolder:AddChild(makeModule("LevelCurve", LevelCurveMock))
MapsFolder:AddChild(makeModule("RosterTuning", {}))
Templates:AddChild(MapsFolder)
local ReplicatedFramework = makeInst("ReplicatedFramework", "Folder")
ReplicatedFramework:AddChild(Templates)
local UtilitiesFolder = makeInst("Utilities", "Folder")
ReplicatedFramework:AddChild(UtilitiesFolder)
RS:AddChild(ReplicatedFramework)
local InRoundCode = makeInst("InRoundCode", "Folder")
InRoundCode:AddChild(makeModule("PlacementMath", PlacementMath))
RS:AddChild(InRoundCode)
local RSPlayerTowers = makeInst("PlayerTowers", "Folder")
local function addTowerModel(name, sizeX, sizeZ)
    local m = makeInst(name, "Model")
    m.Size = v3(sizeX or 4, 6, sizeZ or 4)
    local root = makeInst("TowerRoot", "Part")
    root.Position = v3()
    m:AddChild(root)
    m.PrimaryPart = root
    RSPlayerTowers:AddChild(m)
    return m
end
addTowerModel("Melon", 4, 4)
addTowerModel("Soup", 3, 3)
addTowerModel("Fortune", 5, 5)
RS:AddChild(RSPlayerTowers)
TowersMock.TowerModels = RSPlayerTowers
local PlayerScripts = makeInst("PlayerScripts", "Folder")
local function buildPlayerScripts()
    PlayerScripts._children = {}
    if PLACE ~= "Lobby" then
        local inRound = makeInst("InRoundCode", "Folder")
        local utilsFolder = makeInst("Utilities", "Folder")
        utilsFolder:AddChild(makeModule("PlacementArea", PlacementArea))
        inRound:AddChild(utilsFolder)
        PlayerScripts:AddChild(inRound)
    end
end
buildPlayerScripts()
Plr:AddChild(PlayerScripts)
local TowerSlots = makeInst("TowerSlots", "Folder")
local function addSlot(i, tower, uid, unlocked)
    local slot = makeInst(tostring(i), "Folder")
    slot:SetAttribute("Tower", tower or "")
    slot:SetAttribute("TowerUid", uid or "")
    slot:SetAttribute("Unlocked", unlocked == true)
    TowerSlots:AddChild(slot)
    return slot
end
addSlot(1, "Melon", "1", true)
addSlot(2, "Soup", "2", true)
addSlot(3, "", "", false)
Plr:AddChild(TowerSlots)
local PlayerTowers = makeInst("PlayerTowers", "Folder")
PlayerTowers:SetAttribute("MaxStorage", 100)
local function addOwnedTower(uid, tower, opts)
    opts = opts or {}
    local entry = makeInst(uid, "Folder")
    entry:SetAttribute("Tower", tower)
    entry:SetAttribute("Level", opts.level or 1)
    entry:SetAttribute("Stars", opts.stars or 0)
    entry:SetAttribute("Shiny", opts.shiny == true)
    entry:SetAttribute("Locked", opts.locked == true)
    entry:SetAttribute("Trait", opts.trait or "")
    entry:SetAttribute("TraitRolls", 0)
    entry:SetAttribute("XP", 0)
    entry:SetAttribute("Serial", opts.serial or 1)
    entry:SetAttribute("EquippedSlot", opts.slot or 0)
    PlayerTowers:AddChild(entry)
    return entry
end
addOwnedTower("1", "Melon", { slot = 1, stars = 1, trait = "Damage1" })
addOwnedTower("2", "Soup", { slot = 2, trait = "" })
for i = 1, 6 do
    addOwnedTower(tostring(10 + i), "Soup", { serial = 10 + i })
end
Plr:AddChild(PlayerTowers)
local PlayerItems = makeInst("PlayerItems", "Folder")
local dice = makeInst("TraitDice", "NumberValue")
dice.Value = 3
PlayerItems:AddChild(dice)
Plr:AddChild(PlayerItems)
local PlayerMapStats = makeInst("PlayerMapStats", "Folder")
local candyStats = makeInst("CandyDefense", "Folder")
local function addMapLevel(parent, n, beaten)
    local lv = makeInst("Level_" .. n, "Folder")
    lv:SetAttribute("Beaten", beaten == true)
    lv:SetAttribute("Attempts", 1)
    parent:AddChild(lv)
end
addMapLevel(candyStats, 1, true)
addMapLevel(candyStats, 2, false)
PlayerMapStats:AddChild(candyStats)
Plr:AddChild(PlayerMapStats)
local leaderstats = makeInst("leaderstats", "Folder")
local gemsValue = makeInst("Gems", "IntValue")
gemsValue.Value = 1200
leaderstats:AddChild(gemsValue)
local levelValue = makeInst("Level", "IntValue")
levelValue.Value = 9
leaderstats:AddChild(levelValue)
Plr:AddChild(leaderstats)
local PlayerLevelStats = makeInst("PlayerLevelStats", "Folder")
PlayerLevelStats:SetAttribute("Level", 9)
PlayerLevelStats:SetAttribute("Progress", 0.5)
PlayerLevelStats:SetAttribute("MaxLevel", 200)
Plr:AddChild(PlayerLevelStats)
local CandyDefense = makeInst("CandyDefense", "Folder")
local PlacedTowersFolder = makeInst("PlacedTowers", "Folder")
CandyDefense:AddChild(PlacedTowersFolder)
workspace:AddChild(CandyDefense)
local function addPlacedTower(name, x, z, owner, level, mode)
    local model = makeInst(name, "Model")
    model:SetAttribute("OwnerUserId", owner or PLR_USER_ID)
    model:SetAttribute("TowerUid", "u" .. tostring(math.random(10000)))
    local cfg = makeInst("TowerConfig", "Configuration")
    cfg:SetAttribute("Level", level or 0)
    cfg:SetAttribute("TargetingMode", mode or "First")
    model:AddChild(cfg)
    local root = makeInst("TowerRoot", "Part")
    root.Position = v3(x, 0, z)
    model:AddChild(root)
    model.PrimaryPart = root
    model.Size = v3(4, 6, 4)
    PlacedTowersFolder:AddChild(model)
    return model
end
local LobbyFolder = makeInst("Lobby", "Folder")
local ZonesFolder = makeInst("Zones", "Folder")
local FunctionalFolder = makeInst("Functional", "Folder")
local function addZone(name, x, z)
    local zone = makeInst(name, "Model")
    local part = makeInst("Part", "Part")
    part.Position = v3(x, 0, z)
    zone:AddChild(part)
    zone.PrimaryPart = part
    ZonesFolder:AddChild(zone)
    return zone
end
addZone("CircularZone", 30, 0)
addZone("CircularZone2", -30, 0)
FunctionalFolder:AddChild(ZonesFolder)
LobbyFolder:AddChild(FunctionalFolder)
workspace:AddChild(LobbyFolder)

local JoinPadsFolder = makeInst("Join Pads", "Folder")
local JoinPadsRegular = makeInst("Regular Mode", "Folder")
JoinPadsFolder:AddChild(JoinPadsRegular)
local PadFunctional = makeInst("Functional", "Folder")
PadFunctional:AddChild(JoinPadsFolder)
workspace:AddChild(PadFunctional)
local function addJoinPad(padName, x, z, hostUserId, roundType)
    local pad = makeInst("GameJoinPad", "Model")
    pad:SetAttribute("HostUserId", hostUserId)
    if roundType then pad:SetAttribute("RoundType", roundType) end
    local walls = makeInst("Walls", "Model")
    for wi = 1, 2 do
        local wp = makeInst("Part", "Part")
        wp.Position = v3(x + wi, 0, z)
        wp.CFrame = cf(wp.Position)
        walls:AddChild(wp)
    end
    pad:AddChild(walls)
    local status = makeInst("Status", "Part")
    status.Position = v3(x, 0, z)
    status.CFrame = cf(status.Position)
    pad:AddChild(status)
    JoinPadsRegular:AddChild(pad)
    gameJoinPads[#gameJoinPads + 1] = pad
    return pad
end
local openPad = addJoinPad("GameJoinPad", 60, 10, 0, nil)
local busyPad = addJoinPad("GameJoinPad", -60, 10, 777, nil)
local endlessPad = addJoinPad("GameJoinPad", 90, 10, 0, "Endless")
local firstOpenWallPos = openPad:FindFirstChild("Walls"):GetChildren()[1].Position

local function GetOwnTowersProxy()
    local mapName = RS:GetAttribute("SelectedMap")
    local map = mapName and workspace:FindFirstChild(mapName)
    local folder = (map and map:FindFirstChild("PlacedTowers")) or workspace:FindFirstChild("PlacedTowers")
    local n = 0
    if folder then
        for _, model in ipairs(folder:GetChildren()) do
            if model:IsA("Model") and model:GetAttribute("OwnerUserId") == Plr.UserId then n = n + 1 end
        end
    end
    return n
end
local function lastFired(name)
    local list = fires[name]
    return list and list[#list] or nil
end
local function fireCount(name)
    return (fires[name] and #fires[name]) or 0
end
local function invokeCount(name)
    return (invokes[name] and #invokes[name]) or 0
end
local function lastInvoke(name)
    local list = invokes[name]
    return list and list[#list] or nil
end
local function firstInvoke(name)
    local list = invokes[name]
    return list and list[1] or nil
end
local function anyLabelContains(fragment)
    for _, l in pairs(Labels) do
        if type(l.Value) == "string" and l.Value:find(fragment, 1, true) then return true, l.Value end
    end
    return false
end
local function pressButton(text)
    for _, entry in ipairs(elementLog) do
        if entry.kind == "Button" and entry.id == text and entry.func then
            entry.func()
            return true
        end
    end
    return false
end
local function clearRoundState()
    PlacedTowersFolder._children = {}
    invokes.PlaceTower = nil
    invokes.UpgradeTower = nil
    invokes.SellTower = nil
    fires.RequestReturnToLobby = nil
end

local CloneFolder = makeInst("FrameworkEvents", "Folder")
local CloneByOrig = {}
for _, origChild in ipairs(FrameworkEvents:GetChildren()) do
    local clone = makeInst(origChild.Name, origChild.ClassName)
    if origChild.ClassName == "RemoteEvent" then
        clone.OnClientEvent = origChild.OnClientEvent
        clone._FireRaw = origChild._FireRaw
        clone.FireServer = function(s2, ...)
            currentMethod = "FireServer"
            return namecallHook(s2, ...)
        end
    else
        clone._InvokeRaw = origChild._InvokeRaw
        clone.InvokeServer = function(s2, ...)
            currentMethod = "InvokeServer"
            return namecallHook(s2, ...)
        end
    end
    CloneByOrig[origChild] = clone
    CloneFolder:AddChild(clone)
end
local CloneRS = setmetatable({ Name = "ReplicatedStorage", ClassName = "ReplicatedStorage" }, {
    __index = function(_, k)
        if k == "FindFirstChild" then
            return function(_, n)
                if n == "FrameworkEvents" then return CloneFolder end
                return RS:FindFirstChild(n)
            end
        elseif k == "WaitForChild" then
            return function(_, n, t)
                if n == "FrameworkEvents" then return CloneFolder end
                return RS:WaitForChild(n, t)
            end
        elseif k == "GetChildren" then
            return function()
                local list = RS:GetChildren()
                local hasClone = false
                for _, c in ipairs(list) do if c == CloneFolder then hasClone = true end end
                if not hasClone then list[#list + 1] = CloneFolder end
                return list
            end
        else
            return RS[k]
        end
    end,
})
cloneref = function(x)
    if x == RS then return CloneRS end
    return x
end

getgenv().ayasemiyatongekissazumirisa = nil
local chunk, loadErr = loadfile("/tmp/snack_debug.lua")
check("script compiles (" .. PLACE .. ")", chunk ~= nil)
local ok, runErr
if chunk then
    ok, runErr = pcall(chunk)
end
check("script runs without fatal error (" .. PLACE .. ")", ok == true)
if not ok then print("RUN ERR: " .. tostring(runErr)) end
local function noLoadErrors()
    for _, n in ipairs(notifies) do
        if n:find("ERROR", 1, true) then return false end
    end
    return true
end
check("no template-level ERROR notify (" .. PLACE .. ")", noLoadErrors())
if not noLoadErrors() then
    for _, n in ipairs(notifies) do print("  NOTIFY: " .. n) end
    for i, n in ipairs(notyuriLog) do if i <= 15 then print("  LOG: " .. n) end end
end
check("SaveManager folder set", SaveManager.Folder == "Yuri/Snack")

-- violation absence checks (all places)
check("absence: no AutoTarget toggle", Toggles.AutoTarget == nil)
check("absence: no AutoQuests toggle", Toggles.AutoQuests == nil)
check("absence: no AutoIndex toggle", Toggles.AutoIndex == nil)
check("absence: no GroupReward toggle", Toggles.GroupReward == nil)
check("absence: no AfkTeleport toggle", Toggles.AfkTeleport == nil)
check("absence: no EquipBest toggle", Toggles.EquipBest == nil)
check("absence: no PlaceDelay slider", Options.PlaceDelay == nil)
check("absence: no PlaceTowers multi", Options.PlaceTowers == nil)
check("absence: no UpgradeTowers multi", Options.UpgradeTowers == nil)
check("absence: no SellTowers multi", Options.SellTowers == nil)
check("absence: no TargetTowers multi", Options.TargetTowers == nil)
check("absence: no TargetMode dropdown", Options.TargetMode == nil)
check("absence: no MacroName input", Options.MacroName == nil)
check("absence: no old Speed dropdown", Options.Speed == nil)
check("absence: no Snack-prefixed toggles", Toggles.SnackAutoPlace == nil and Toggles.SnackAutoQueue == nil)
check("absence: no stats labels", not anyLabelContains("Trait Dice") and not anyLabelContains("Gems 1,200") and not anyLabelContains("Wave 2/6"))

if PLACE == "Round" then
    -- element existence
    check("round: AutoPlace toggle exists", Toggles.AutoPlace ~= nil)
    check("round: AutoUpgrade toggle exists", Toggles.AutoUpgrade ~= nil)
    check("round: AutoSell slider-toggle exists", Toggles.AutoSell ~= nil and Options.AutoSellValue ~= nil)
    check("round: AutoVote toggle exists", Toggles.AutoVote ~= nil)
    check("round: AutoFlow toggle exists", Toggles.AutoFlow ~= nil)
    check("round: AutoSpeed toggle exists", Toggles.AutoSpeed ~= nil)
    check("round: AutoLeave toggle exists", Toggles.AutoLeave ~= nil)
    check("round: PlaceAndUpgrade toggle exists", Toggles.PlaceAndUpgrade ~= nil)
    check("round: UpgradeMethod dropdown exists", Options.UpgradeMethod ~= nil)
    check("round: MacroRecord toggle exists", Toggles.MacroRecord ~= nil)
    check("round: LoadMacro toggle exists", Toggles.LoadMacro ~= nil)
    check("round: WHMatchEnd toggle exists", Toggles.WHMatchEnd ~= nil)
    check("round: WebhookURL input exists", Options.WebhookURL ~= nil)
    check("round: AutoLeaveValue slider exists", Options.AutoLeaveValue ~= nil)
    check("round: SpeedTarget dropdown exists", Options.SpeedTarget ~= nil)
    check("round: DefeatMode dropdown exists", Options.DefeatMode ~= nil)
    check("round: per-slot limit sliders exist", Options.PlaceOrder1 ~= nil and Options.PlaceWave6 ~= nil and Options.PlaceLimit3 ~= nil and Options.UpgradeLimit6 ~= nil)
    check("round: slot select dropdowns exist", Options.SetSlotSelect ~= nil and Options.ResetSlotSelect ~= nil)
    check("round: speed target values", table.concat(Options.SpeedTarget.Values, ",") == "1,2" and Options.SpeedTarget.Value == "2")
    check("round: upgrade method values", table.concat(Options.UpgradeMethod.Values, ","):find("Lowest Level", 1, true) ~= nil)
    check("round: replay mode values", table.concat(Options.ReplayMode.Values, ",") == "Time,Money" and Options.ReplayMode.Value == "Time")
    check("round: positions label starts unset", anyLabelContains("No positions set"))

    invokeScript.PlaceTower = function() return { success = true, cost = 250 } end
    invokeScript.UpgradeTower = function(payload)
        local model = payload and payload.tower
        local cfg = model and model:FindFirstChild("TowerConfig")
        if cfg then cfg:SetAttribute("Level", (tonumber(cfg:GetAttribute("Level")) or 0) + 1) end
        return { success = true, cost = 200 }
    end
    invokeScript.SellTower = function() return { success = true, refund = 100 } end
    invokeScript.SetTowerTarget = function() return { success = true } end

    -- autoplace basic (no saved positions -> game grid fallback)
    Toggles.AutoPlace:SetValue(true)
    pumpAll(4)
    local placeFirst = firstInvoke("PlaceTower")
    check("round: autoplace fires PlaceTower", placeFirst ~= nil)
    if placeFirst then
        check("round: first place payload is slot-1 tower", placeFirst[1].towerKey == "Melon" and placeFirst[1].slotIndex == 1)
        check("round: place payload coords are grid center", placeFirst[1].x == 10 and placeFirst[1].z == 10 and placeFirst[1].y == 0)
        check("round: place payload rotationY", placeFirst[1].rotationY == 0)
    end
    check("round: second place payload is slot-2 tower", invokeCount("PlaceTower") >= 2 and invokes.PlaceTower[2][1].towerKey == "Soup")
    Toggles.AutoPlace:SetValue(false)
    pumpAll(2)

    -- place wave gate
    Options.PlaceWave2:SetValue(3)
    clearRoundState()
    Toggles.AutoPlace:SetValue(true)
    pumpAll(4)
    local waveGateOk = invokeCount("PlaceTower") >= 1
    for _, entry in ipairs(invokes.PlaceTower or {}) do
        if entry[1].towerKey == "Soup" then waveGateOk = false end
    end
    check("round: place wave gate blocks slot 2", waveGateOk and firstInvoke("PlaceTower")[1].towerKey == "Melon")
    Toggles.AutoPlace:SetValue(false)
    pumpAll(2)
    Options.PlaceWave2:SetValue(0)

    -- place limit gate
    clearRoundState()
    addPlacedTower("Melon", 1, 1)
    Options.PlaceLimit1:SetValue(1)
    Toggles.AutoPlace:SetValue(true)
    pumpAll(4)
    local limitOk = invokeCount("PlaceTower") >= 1
    for _, entry in ipairs(invokes.PlaceTower or {}) do
        if entry[1].towerKey == "Melon" then limitOk = false end
    end
    check("round: place limit gate blocks slot 1", limitOk and firstInvoke("PlaceTower")[1].towerKey == "Soup")
    Toggles.AutoPlace:SetValue(false)
    pumpAll(2)
    Options.PlaceLimit1:SetValue(0)

    -- board cap gate
    clearRoundState()
    for i = 1, 20 do
        addPlacedTower("Melon", i * 2, 0)
    end
    Toggles.AutoPlace:SetValue(true)
    pumpAll(4)
    check("round: autoplace respects board cap", invokeCount("PlaceTower") == 0)
    Toggles.AutoPlace:SetValue(false)
    pumpAll(2)

    -- saved positions: set slot 1 position at character
    clearRoundState()
    check("round: set slot position button works", pressButton("Set Slot Position"))
    pumpAll(2)
    check("round: positions label shows saved pos", anyLabelContains("Slot 1 (Melon): 1 pos"))
    check("round: positions file saved", files["Yuri/Snack/position.json"] ~= nil)
    Toggles.AutoPlace:SetValue(true)
    pumpAll(4)
    local savedPlace = firstInvoke("PlaceTower")
    check("round: autoplace uses saved position", savedPlace ~= nil and savedPlace[1].x == 0 and savedPlace[1].z == 0 and savedPlace[1].y == 0)
    Toggles.AutoPlace:SetValue(false)
    pumpAll(2)

    -- place and upgrade chain
    clearRoundState()
    local chainTower = addPlacedTower("Melon", 0.5, 0.5)
    Toggles.PlaceAndUpgrade:SetValue(true)
    Toggles.AutoPlace:SetValue(true)
    pumpAll(8)
    check("round: place+upgrade chains upgrades", invokeCount("UpgradeTower") >= 1)
    Toggles.AutoPlace:SetValue(false)
    Toggles.PlaceAndUpgrade:SetValue(false)
    pumpAll(2)

    -- reset positions
    pressButton("Reset Position")
    pumpAll(2)
    check("round: reset positions label", anyLabelContains("No positions set"))

    -- autoupgrade lowest level
    PlacedTowersFolder._children = {}
    invokes.UpgradeTower = nil
    local melonModel = addPlacedTower("Melon", 1, 1, nil, 1)
    local soupModel = addPlacedTower("Soup", 7, 7, nil, 0)
    Toggles.AutoUpgrade:SetValue(true)
    pumpAll(3)
    local upgInvoke = firstInvoke("UpgradeTower")
    check("round: autoupgrade fires UpgradeTower", upgInvoke ~= nil)
    if upgInvoke then
        check("round: lowest level picked first", upgInvoke[1].tower == soupModel)
    end
    Toggles.AutoUpgrade:SetValue(false)
    pumpAll(2)

    -- upgrade method slot order
    PlacedTowersFolder._children = {}
    invokes.UpgradeTower = nil
    local melonModel = addPlacedTower("Melon", 1, 1, nil, 1)
    local soupModel = addPlacedTower("Soup", 7, 7, nil, 0)
    Options.UpgradeMethod:SetValue("Hotbar left to right (until Max)")
    Toggles.AutoUpgrade:SetValue(true)
    pumpAll(3)
    upgInvoke = firstInvoke("UpgradeTower")
    check("round: slot order method picks slot 1", upgInvoke ~= nil and upgInvoke[1].tower == melonModel)
    Toggles.AutoUpgrade:SetValue(false)
    pumpAll(2)
    Options.UpgradeMethod:SetValue("Lowest Level (Spread Upgrade)")

    -- upgrade limit gate
    PlacedTowersFolder._children = {}
    invokes.UpgradeTower = nil
    local limMelon = addPlacedTower("Melon", 1, 1, nil, 2)
    local limSoup = addPlacedTower("Soup", 7, 7, nil, 1)
    Options.UpgradeLimit1:SetValue(1)
    Toggles.AutoUpgrade:SetValue(true)
    pumpAll(3)
    upgInvoke = firstInvoke("UpgradeTower")
    check("round: upgrade limit filters slot 1", upgInvoke ~= nil and upgInvoke[1].tower == limSoup and upgInvoke[1].tower ~= limMelon)
    Toggles.AutoUpgrade:SetValue(false)
    pumpAll(2)
    Options.UpgradeLimit1:SetValue(0)

    -- auto sell at wave
    clearRoundState()
    addPlacedTower("Melon", 1, 1)
    addPlacedTower("Soup", 7, 7)
    Options.AutoSellValue:SetValue(2)
    Toggles.AutoSell:SetValue(true)
    pumpAll(3)
    check("round: auto sell at wave sells all", invokeCount("SellTower") >= 2)
    Toggles.AutoSell:SetValue(false)
    pumpAll(2)

    -- auto leave at wave
    clearRoundState()
    Options.AutoLeaveValue:SetValue(3)
    Toggles.AutoLeave:SetValue(true)
    pumpAll(3)
    check("round: auto leave waits for wave", fireCount("RequestReturnToLobby") == 0)
    RS:SetAttribute("CurrentWave", 4)
    pumpAll(3)
    check("round: auto leave fires once per wave", fireCount("RequestReturnToLobby") == 1)
    pumpAll(3)
    check("round: auto leave dedupes same wave", fireCount("RequestReturnToLobby") == 1)
    Toggles.AutoLeave:SetValue(false)
    pumpAll(2)

    -- auto vote
    Toggles.AutoVote:SetValue(true)
    RS:SetAttribute("ModalVoteId", 7)
    pumpAll(2)
    check("round: autovote fires ModalVote yes", fireCount("ModalVote") == 1 and lastFired("ModalVote")[1] == 7 and lastFired("ModalVote")[2] == true)
    pumpAll(3)
    check("round: autovote dedupes same vote id", fireCount("ModalVote") == 1)
    RS:SetAttribute("ModalVoteId", 8)
    pumpAll(2)
    check("round: autovote fires on new vote id", fireCount("ModalVote") == 2)
    Toggles.AutoVote:SetValue(false)
    pumpAll(2)

    -- auto flow
    fires.RequestNextLevel = nil
    Toggles.AutoFlow:SetValue(true)
    RS:SetAttribute("RoundPhase", "Complete")
    pumpAll(2)
    check("round: autoflow next level on victory", fireCount("RequestNextLevel") == 1)
    fires.RequestReplayLevel = nil
    RS:SetAttribute("RoundPhase", "Defeat")
    pumpAll(2)
    check("round: autoflow replay on defeat", fireCount("RequestReplayLevel") == 1)
    fires.RequestReturnToLobby = nil
    Options.DefeatMode:SetValue("Return to Lobby")
    RS:SetAttribute("RoundPhase", "Defeat")
    pumpAll(2)
    check("round: autoflow lobby on defeat mode", fireCount("RequestReturnToLobby") == 1)
    Toggles.AutoFlow:SetValue(false)
    pumpAll(2)

    -- auto speed
    fires.RequestGameSpeed = nil
    Toggles.AutoSpeed:SetValue(true)
    pumpAll(2)
    check("round: autospeed fires speed target", fireCount("RequestGameSpeed") >= 1 and tonumber(lastFired("RequestGameSpeed")[1]) == 2)
    Toggles.AutoSpeed:SetValue(false)
    pumpAll(4)

    -- webhook
    Options.WebhookURL:SetValue("http://hook.test")
    Toggles.WHMatchEnd:SetValue(true)
    httpRequests = {}
    RS:SetAttribute("RoundPhase", "Complete")
    pumpAll(2)
    check("round: webhook posts on match end", #httpRequests == 1)
    if httpRequests[1] then
        check("round: webhook body has victory + map", httpRequests[1].Body:find("Victory", 1, true) and httpRequests[1].Body:find("CandyDefense", 1, true))
        check("round: webhook posts to configured url", httpRequests[1].Url == "http://hook.test")
    end
    RS:SetAttribute("RoundPhase", "Defeat")
    pumpAll(2)
    check("round: webhook deduped per match", #httpRequests == 1)
    Toggles.WHMatchEnd:SetValue(false)
    pumpAll(2)

    -- macro record + replay
    clearRoundState()
    PlacedTowersFolder._children = {}
    Options.FileName:SetValue("testm")
    local placeTowerRemote = FrameworkEvents:FindFirstChild("PlaceTower")
    local upgradeTowerRemote = FrameworkEvents:FindFirstChild("UpgradeTower")
    local preRecordPayload = { towerKey = "Melon", slotIndex = 1, x = 3, y = 0, z = 4, rotationY = 90 }
    placeTowerRemote:InvokeServer(preRecordPayload)
    pumpAll(2)
    Toggles.MacroRecord:SetValue(true)
    pumpAll(3)
    local logText = files["1log.txt"] or ""
    check("round: orig remote refs resolved for hook", logText:find("orig remote refs resolved: 4", 1, true) ~= nil)
    local recordPayload = { towerKey = "Melon", slotIndex = 1, x = 3, y = 0, z = 4, rotationY = 90 }
    placeTowerRemote:InvokeServer(recordPayload)
    local recordedTower = addPlacedTower("Melon", 3, 4, nil, 0, "First")
    pumpAll(3)
    upgradeTowerRemote:InvokeServer({ tower = recordedTower })
    RS:SetAttribute("RoundActive", false)
    pumpAll(4)
    local savedRaw = files["Yuri/Snack/Macros/testm.json"]
    check("round: macro saved to file", savedRaw ~= nil)
    local macroData
    if savedRaw then
        macroData = HttpService:JSONDecode(savedRaw)
    end
    check("round: macro has 2 entries", macroData and macroData["1"] ~= nil and macroData["2"] ~= nil and macroData["3"] == nil)
    if macroData and macroData["1"] then
        local e1 = macroData["1"]
        check("round: macro place entry fields", e1.Type == "Place" and e1.Name == "Melon" and e1.Slot == 1 and e1.Rot == 90 and e1.Pos[1] == 3 and e1.Pos[3] == 4 and e1.Key ~= nil)
        local e2 = macroData["2"]
        check("round: macro upgrade entry fields", e2 and e2.Type == "Upgrade" and e2.LVL == 1 and e2.Name == "Melon")
    end
    check("round: macro dropdown refreshed with saved name", table.find(Options.MacroSelected.Values, "testm") ~= nil)
    Toggles.MacroRecord:SetValue(false)
    pumpAll(2)
    RS:SetAttribute("RoundActive", true)
    RS:SetAttribute("RoundPhase", "Prep")
    Plr:SetAttribute("RoundCurrency", 2000)
    local replayCfg = recordedTower and recordedTower:FindFirstChild("TowerConfig")
    if replayCfg then replayCfg:SetAttribute("Level", 0) end
    invokes.PlaceTower = nil
    invokes.UpgradeTower = nil
    Options.MacroSelected:SetValue("testm")
    Toggles.LoadMacro:SetValue(true)
    pumpAll(8)
    local replayPlace = lastInvoke("PlaceTower")
    check("round: replay fires place with recorded pos", replayPlace ~= nil and replayPlace[1].x == 3 and replayPlace[1].z == 4 and replayPlace[1].rotationY == 90)
    check("round: replay fires upgrade", invokeCount("UpgradeTower") >= 1)
    Toggles.LoadMacro:SetValue(false)
    pumpAll(2)
elseif PLACE == "Lobby" then
    check("lobby: AutoQueue toggle exists", Toggles.AutoQueue ~= nil)
    check("lobby: AutoSummon toggle exists", Toggles.AutoSummon ~= nil)
    check("lobby: AutoTraitRoll toggle exists", Toggles.AutoTraitRoll ~= nil)
    check("lobby: AutoFuse toggle exists", Toggles.AutoFuse ~= nil)
    check("lobby: AutoRejoin toggle exists", Toggles.AutoRejoin ~= nil)
    check("lobby: queue map dropdown exists", Options.QueueMap ~= nil)
    check("lobby: queue level dropdown exists", Options.QueueLevel ~= nil)
    check("lobby: summon banner dropdown exists", Options.SummonBanner ~= nil)
    check("lobby: summon amount dropdown exists", Options.SummonAmount ~= nil)
    check("lobby: summon reserve slider exists", Options.SummonReserve ~= nil)
    check("lobby: trait towers multi exists", Options.TraitTowers ~= nil)
    check("lobby: trait stop dropdown exists", Options.TraitStop ~= nil)
    check("lobby: macro + positions labels exist", anyLabelContains("No positions set") and anyLabelContains("Idle"))
    check("lobby: maps enumerated sorted", table.concat(Options.QueueMap.Values, ",") == "CandyDefense,DumplingDefense,EnchantedForest")
    local lvlValues = table.concat(Options.QueueLevel.Values, ",")
    check("lobby: level dropdown built", lvlValues:find("Highest Unlocked", 1, true) and lvlValues:find("6", 1, true))
    check("lobby: banner labels sorted by cost", Options.SummonBanner.Values[1] == "BasicSummon (100 gems)" and Options.SummonBanner.Values[2] == "GourmetSummon (500 gems)")
    Toggles.AutoQueue:SetValue(true)
    pumpAll(3)
    check("lobby: queue waits without host (no fire yet)", fireCount("RequestPlay") == 0)
    local tpPos = charRoot.CFrame and charRoot.CFrame.Position
    check("lobby: queue teleports to open pad wall",
        tpPos ~= nil and (tpPos.X == 61 or tpPos.X == 62) and tpPos.Z == 10)
    check("lobby: queue ignores busy and endless pads",
        tpPos ~= nil and tpPos.X ~= -59 and tpPos.X ~= -60 and tpPos.X ~= 91 and tpPos.X ~= 92)
    Plr:SetAttribute("IsPartyHost", true)
    Plr:SetAttribute("PartyPadId", "openpad-1")
    pumpAll(14)
    local play = lastFired("RequestPlay")
    check("lobby: queue fires RequestPlay", play ~= nil)
    if play then
        check("lobby: RequestPlay map arg", play[1] == "CandyDefense")
        check("lobby: RequestPlay highest unlocked level arg", play[2] == 2)
    end
    check("lobby: queue fires RequestStartGame after play", fireCount("RequestStartGame") >= 1 and fireCount("RequestStartGame") <= fireCount("RequestPlay"))
    Toggles.AutoQueue:SetValue(false)
    pumpAll(2)
    Toggles.AutoSummon:SetValue(true)
    pumpAll(3)
    local summon = lastFired("RequestSummon")
    check("lobby: summon fires with banner key + amount", summon ~= nil and summon[1] == "BasicSummon" and summon[2] == 1)
    local summonCountBeforeReserve = fireCount("RequestSummon")
    Options.SummonReserve:SetValue(2000)
    pumpAll(40)
    check("lobby: summon respects gem reserve", fireCount("RequestSummon") == summonCountBeforeReserve)
    Toggles.AutoSummon:SetValue(false)
    pumpAll(2)
    Options.TraitTowers:SetValue({ ["Soup"] = true })
    Toggles.AutoTraitRoll:SetValue(true)
    pumpAll(2)
    local traitRoll = lastFired("RequestTraitRoll")
    check("lobby: trait roll fires for equipped uid", traitRoll ~= nil and traitRoll[1] == "2")
    Toggles.AutoTraitRoll:SetValue(false)
    pumpAll(2)
    invokeScript.StarsFuseRequest = function(_, target, fodder)
        return { ok = true }
    end
    Toggles.AutoFuse:SetValue(true)
    pumpAll(2)
    local fuse = lastInvoke("StarsFuseRequest")
    check("lobby: fuse invokes StarsFuseRequest", fuse ~= nil)
    if fuse then
        check("lobby: fuse target uid", fuse[1] == "11")
        check("lobby: fuse fodder count matches copiesFor", fuse[2] and #fuse[2] == 5)
        check("lobby: fuse fodder excludes equipped copy", table.find(fuse[2], "2") == nil)
    end
    Toggles.AutoFuse:SetValue(false)
    pumpAll(2)
    Toggles.AutoRejoin:SetValue(true)
    local offerSignal = FrameworkEvents:FindFirstChild("MatchRejoinOffer").OnClientEvent
    offerSignal:Fire({ Map = "CandyDefense", Level = 2 })
    pumpAll(2)
    check("lobby: rejoin offer accepted", fireCount("MatchRejoinAnswer") == 1 and lastFired("MatchRejoinAnswer")[1] == true)
    Toggles.AutoRejoin:SetValue(false)
    offerSignal:Fire({ Map = "CandyDefense", Level = 2 })
    pumpAll(2)
    check("lobby: rejoin answer gated by toggle", fireCount("MatchRejoinAnswer") == 1)
    pumpAll(4)
else
    check("afk place: script loads with ui intact", Toggles.AutoQueue ~= nil and Toggles.AutoPlace ~= nil)
    check("afk place: positions label fallback", anyLabelContains("No positions set"))
end
print(("RESULT %s: %d passed, %d failed"):format(PLACE, passCount, failCount))
if failCount > 0 then
    for _, f in ipairs(failures) do print("  FAILED: " .. f) end
    os.exit(1)
end
