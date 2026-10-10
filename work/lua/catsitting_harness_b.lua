local CHECKS = { pass = 0, fail = 0 }
local function CHECK(name, cond)
    if cond then
        CHECKS.pass = CHECKS.pass + 1
        print("PASS " .. name)
    else
        CHECKS.fail = CHECKS.fail + 1
        print("FAIL " .. name)
    end
end

local MODE = arg and arg[1] or "house"

local SIM = { time = 0, tasks = {} }
local task = {}
task.spawn = function(f, ...)
    local co = coroutine.create(f)
    SIM.tasks[#SIM.tasks + 1] = { co = co, wake = SIM.time, args = table.pack(...), started = false }
    return co
end
task.defer = function(f, ...)
    local co = coroutine.create(f)
    SIM.tasks[#SIM.tasks + 1] = { co = co, wake = SIM.time + 1 / 60, args = table.pack(...), started = false }
    return co
end
task.delay = function(d, f, ...)
    local co = coroutine.create(f)
    SIM.tasks[#SIM.tasks + 1] = { co = co, wake = SIM.time + (d or 0), args = table.pack(...), started = false }
    return co
end
task.cancel = function(co)
    for i = #SIM.tasks, 1, -1 do
        if SIM.tasks[i].co == co then
            table.remove(SIM.tasks, i)
        end
    end
    pcall(coroutine.close, co)
end
task.wait = function(t)
    coroutine.yield(t or (1 / 60))
    return t or (1 / 60)
end
local runTasks
runTasks = function(duration)
    local target = SIM.time + duration
    while true do
        local idx, best = nil, nil
        for i, e in ipairs(SIM.tasks) do
            if coroutine.status(e.co) ~= "dead" and e.wake <= target then
                if not best or e.wake < best.wake then
                    idx, best = i, e
                end
            end
        end
        if not idx then
            break
        end
        if SIM.time < best.wake then
            SIM.time = best.wake
        end
        local ok, a = coroutine.resume(best.co)
        if not ok then
            error("task crashed: " .. tostring(a))
        end
        if coroutine.status(best.co) == "dead" then
            table.remove(SIM.tasks, idx)
        else
            best.wake = SIM.time + (tonumber(a) or (1 / 60))
        end
    end
    if SIM.time < target then
        SIM.time = target
    end
end

local Vec3MT = {}
Vec3MT.__index = function(t, k)
    if k == "Magnitude" then
        return math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z)
    end
    if k == "Unit" then
        local m = math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z)
        if m == 0 then
            return { X = 0, Y = 0, Z = 0 }
        end
        return setmetatable({ X = t.X / m, Y = t.Y / m, Z = t.Z / m }, Vec3MT)
    end
    return nil
end
Vec3MT.__sub = function(a, b)
    return setmetatable({ X = a.X - b.X, Y = a.Y - b.Y, Z = a.Z - b.Z }, Vec3MT)
end
Vec3MT.__add = function(a, b)
    return setmetatable({ X = a.X + b.X, Y = a.Y + b.Y, Z = a.Z + b.Z }, Vec3MT)
end
Vec3MT.__mul = function(a, b)
    if type(a) == "number" then
        return setmetatable({ X = a * b.X, Y = a * b.Y, Z = a * b.Z }, Vec3MT)
    end
    return setmetatable({ X = a.X * b, Y = a.Y * b, Z = a.Z * b }, Vec3MT)
end
local function v3(x, y, z)
    return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, Vec3MT)
end
local function ud2(xs, xo, ys, yo)
    return { X = { Scale = xs or 0, Offset = xo or 0 }, Y = { Scale = ys or 0, Offset = yo or 0 } }
end

local CLASS_PARENTS = {
    ImageButton = { "GuiButton", "GuiObject", "Instance" },
    ImageLabel = { "GuiObject", "Instance" },
    TextLabel = { "GuiObject", "Instance" },
    Frame = { "GuiObject", "Instance" },
    ScreenGui = { "LayerCollector", "GuiBase2d", "Instance" },
    Model = { "Instance" },
    Folder = { "Instance" },
    Part = { "BasePart", "Instance" },
    MeshPart = { "BasePart", "Instance" },
    Attachment = { "Instance" },
    ModuleScript = { "Instance" },
    LocalScript = { "Instance" },
    Humanoid = { "Instance" },
    PlayerGui = { "Instance" },
    Backpack = { "Instance" },
    Tool = { "Instance" },
    RemoteEvent = { "Instance" },
    RemoteFunction = { "Instance" },
    ProximityPrompt = { "Instance" },
    Camera = { "Instance" },
    Workspace = { "Instance" },
    Player = { "Instance" },
}

local function Signal(name)
    local sig = { __signal = true, Name = name, handlers = {}, fired = 0 }
    sig.Connect = function(self, fn)
        self.handlers[#self.handlers + 1] = fn
        return { __istype = "RBXScriptConnection", Disconnect = function() end }
    end
    sig.Fire = function(self, ...)
        self.fired = self.fired + 1
        for _, fn in ipairs(self.handlers) do
            fn(...)
        end
    end
    return sig
end
local function SignalOf()
    return Signal("sig")
end

local function inst(className, name)
    local o = {
        __inst = true,
        __istype = className,
        ClassName = className,
        Name = name or className,
        _children = {},
        _attrs = {},
        _signals = {},
        Parent = nil,
    }
    o.IsA = function(self, class)
        if self.ClassName == class then
            return true
        end
        for _, p in ipairs(CLASS_PARENTS[self.ClassName] or {}) do
            if p == class then
                return true
            end
        end
        return false
    end
    o.FindFirstChild = function(self, childName)
        for _, c in ipairs(self._children) do
            if c.Name == childName then
                return c
            end
        end
        return nil
    end
    o.FindFirstChildOfClass = function(self, class)
        for _, c in ipairs(self._children) do
            if c.ClassName == class then
                return c
            end
        end
        return nil
    end
    local function findWhichIsARec(x, class)
        for _, c in ipairs(x._children) do
            if c:IsA(class) then
                return c
            end
            local deep = findWhichIsARec(c, class)
            if deep then
                return deep
            end
        end
        return nil
    end
    o.FindFirstChildWhichIsA = function(self, class, recursive)
        if recursive then
            return findWhichIsARec(self, class)
        end
        for _, c in ipairs(self._children) do
            if c:IsA(class) then
                return c
            end
        end
        return nil
    end
    o.FindFirstAncestorWhichIsA = function(self, class)
        local p = self.Parent
        while p do
            if p.IsA and p:IsA(class) then
                return p
            end
            p = p.Parent
        end
        return nil
    end
    o.GetChildren = function(self)
        local out = {}
        for i, c in ipairs(self._children) do
            out[i] = c
        end
        return out
    end
    o.GetDescendants = function(self)
        local out = {}
        local function rec(x)
            for _, c in ipairs(x._children) do
                out[#out + 1] = c
                rec(c)
            end
        end
        rec(self)
        return out
    end
    o.WaitForChild = function(self, childName)
        return self:FindFirstChild(childName)
    end
    o.GetAttribute = function(self, k)
        return self._attrs[k]
    end
    o.SetAttribute = function(self, k, v)
        self._attrs[k] = v
    end
    o.GetAttributeChangedSignal = function(self, k)
        if not self._signals[k] then
            self._signals[k] = SignalOf()
        end
        return self._signals[k]
    end
    o.GetPropertyChangedSignal = function(self, k)
        if not self._signals[k] then
            self._signals[k] = SignalOf()
        end
        return self._signals[k]
    end
    o.GetPivot = function(self)
        return { __istype = "CFrame", Position = self.Position or v3(0, 0, 0) }
    end
    return o
end
local function child(parent, className, name)
    local c = inst(className, name)
    c.Parent = parent
    table.insert(parent._children, c)
    return c
end
local function part(parent, name, x, y, z)
    local p = child(parent, "Part", name)
    p.Position = v3(x or 0, y or 0, z or 0)
    p.CFrame = { __istype = "CFrame", Position = p.Position }
    return p
end
local function prompt(parent, name)
    local pp = child(parent, "ProximityPrompt", name)
    pp.MaxActivationDistance = 8
    pp._fired = 0
    return pp
end

local GENV = {}
local NOTYURI_LOG = {}
local FILES = {}
local PROMPT_FIRES = {}

local Services = {}
local game = {
    PlaceId = 991777,
    JobId = "job1",
    GetService = function(self, name)
        return Services[name]
    end,
    HttpGet = function(self, url)
        if url:find("Library%.lua") then
            return "return _MOCK_LIBRARY"
        elseif url:find("ThemeManager") then
            return "return _MOCK_THEME"
        elseif url:find("SaveManager") then
            return "return _MOCK_SAVE"
        end
        return "return nil"
    end,
}

local Players = inst("Players", "Players")
Services.Players = Players
local Plr = inst("Player", "tester")
Plr.UserId = 1
Plr.Name = "tester"
Plr.Idled = SignalOf()
Plr.CharacterAdded = SignalOf()
Plr.CameraMaxZoomDistance = 128
table.insert(Players._children, Plr)
Players.GetPlayers = function(self)
    return {}
end
Players.LocalPlayer = Plr

local Lighting = inst("Lighting", "Lighting")
Services.Lighting = Lighting
local RunService = inst("RunService", "RunService")
RunService.Stepped = SignalOf()
RunService.Heartbeat = SignalOf()
RunService.RenderStepped = SignalOf()
Services.RunService = RunService
local HttpService = inst("HttpService", "HttpService")
HttpService.JSONEncode = function(self, t)
    return "{}"
end
HttpService.JSONDecode = function(self, s)
    return {}
end
HttpService.GenerateGUID = function(self, b)
    return "guid"
end
Services.HttpService = HttpService
local GuiService = inst("GuiService", "GuiService")
GuiService.ErrorMessageChanged = SignalOf()
Services.GuiService = GuiService
Services.TeleportService = inst("TeleportService", "TeleportService")
local UIS = inst("UserInputService", "UserInputService")
UIS.TouchEnabled = false
UIS.KeyboardEnabled = true
Services.UserInputService = UIS
Services.VirtualUser = inst("VirtualUser", "VirtualUser")
local Marketplace = inst("MarketplaceService", "MarketplaceService")
Marketplace.GetProductInfo = function(self, id)
    return { Name = "7 Days Cat-Sitting" }
end
Services.MarketplaceService = Marketplace
Services.ProximityPromptService = inst("ProximityPromptService", "PPS")
Services.ProximityPromptService.PromptButtonHoldBegan = SignalOf()
Services.VirtualInputManager = nil

local workspace = inst("Workspace", "Workspace")
local camera = inst("Camera", "Camera")
camera.CFrame = { __istype = "CFrame", Position = v3(0, 5, 0) }
workspace.CurrentCamera = camera

local charModel = inst("Model", "tester")
local hrp = part(charModel, "HumanoidRootPart", 0, 2, 0)
local humanoid = child(charModel, "Humanoid", "Humanoid")
humanoid.WalkSpeed = 16
humanoid.JumpPower = 50
humanoid.Health = 100
Plr.Character = charModel
local Backpack = inst("Backpack", "Backpack")
table.insert(Plr._children, Backpack)
local PlayerGui = inst("PlayerGui", "PlayerGui")
table.insert(Plr._children, PlayerGui)
humanoid.EquipTool = function(self, tool)
    tool.Parent = charModel
    for i, c in ipairs(Backpack._children) do
        if c == tool then
            table.remove(Backpack._children, i)
            break
        end
    end
    table.insert(charModel._children, tool)
end

local RS = inst("Folder", "ReplicatedStorage")
Services.ReplicatedStorage = RS

local Wire = {}
local function ensureFolder(name)
    local f = RS:FindFirstChild(name)
    if not f then
        f = child(RS, "Folder", name)
    end
    return f
end
local function mkRemote(folder, name)
    local folderObj = ensureFolder(folder)
    local r = child(folderObj, "RemoteEvent", name)
    r._calls = {}
    r.OnClientEvent = SignalOf(name)
    Wire[name] = r
    return r
end
local function mkRemoteFunction(folder, name)
    local folderObj = ensureFolder(folder)
    local r = child(folderObj, "RemoteFunction", name)
    r._calls = {}
    Wire[name] = r
    return r
end

local function mkElem(className)
    local e = { __elem = className, Value = nil, Values = {}, _onchanged = {}, _callback = nil }
    e.OnChanged = function(self, fn)
        self._onchanged[#self._onchanged + 1] = fn
        return self
    end
    e.SetValue = function(self, v)
        self.Value = v
        for _, fn in ipairs(self._onchanged) do
            fn(v)
        end
        if self._callback then
            self._callback(v)
        end
    end
    e.SetValues = function(self, list)
        self.Values = list
    end
    e.SetVisible = function(self, v) end
    e.SetDisabled = function(self, v) end
    e.AddColorPicker = function(self, ...)
        return mkElem("ColorPicker")
    end
    e.AddKeyPicker = function(self, ...)
        return mkElem("KeyPicker")
    end
    e.SetText = function(self, s) end
    return e
end

local Toggles = {}
local Options = {}
local Labels = {}
local Buttons = {}
local NOTIFICATIONS = {}

local function attachElementCtors(t)
    t.AddToggle = function(self, id, info)
        local e = mkElem("Toggle")
        e.Value = info and info.Default or false
        if info and info.Callback then
            e._callback = info.Callback
        end
        Toggles[id] = e
        return e
    end
    t.AddDropdown = function(self, id, info)
        local e = mkElem("Dropdown")
        e.Values = info and info.Values or {}
        e.Value = info and info.Default or nil
        if info and info.Callback then
            e._callback = info.Callback
        end
        Options[id] = e
        return e
    end
    t.AddButton = function(self, a, b)
        local info = type(a) == "table" and a or { Text = a, Func = b }
        Buttons[info.Text] = info.Func
        return mkElem("Button")
    end
    t.AddDivider = function(self)
        return mkElem("Divider")
    end
    t.AddSlider = function(self, id, info)
        local e = mkElem("Slider")
        e.Value = info and info.Default or 0
        Options[id] = e
        return e
    end
    t.AddLabel = function(self, a, b, c)
        local text = type(a) == "string" and a or (type(a) == "table" and (a.Text or "?") or "?")
        local e = mkElem("Label")
        e.AddKeyPicker = function(self, id, info)
            local k = mkElem("KeyPicker")
            Options[id] = k
            return k
        end
        Labels[text] = e
        return e
    end
    t.AddInput = function(self, id, info)
        local e = mkElem("Input")
        Options[id] = e
        return e
    end
    t.AddKeyPicker = function(self, id, info)
        local k = mkElem("KeyPicker")
        Options[id] = k
        return k
    end
    return t
end

local Library = {
    Toggles = Toggles,
    Options = Options,
    Labels = Labels,
    Unloaded = false,
    KeybindFrame = { Visible = false },
    NotifySide = "Left",
    ShowToggleFrameInKeybinds = true,
    ShowCustomCursor = true,
    Notify = function(self, desc, time)
        NOTIFICATIONS[#NOTIFICATIONS + 1] = tostring(desc)
    end,
    SetDPIScale = function(self, n) end,
    Unload = function(self)
        self.Unloaded = true
    end,
    OnUnload = function(self, fn) end,
    GiveSignal = function(self, c) end,
    SetWatermark = function(self, s) end,
    CreateWindow = function(self, info)
        local Window = { Title = info.Title }
        Window.AddTab = function(self, name)
            local tab = { Name = name }
            local function mkGB()
                return attachElementCtors(mkElem("Groupbox"))
            end
            tab.AddLeftGroupbox = function(self, gbName)
                return mkGB()
            end
            tab.AddRightGroupbox = function(self, gbName)
                return mkGB()
            end
            tab.AddGroupbox = function(self, gbName)
                return mkGB()
            end
            local function mkTB()
                local tb = {}
                tb.AddTab = function(self, tabName)
                    return attachElementCtors(mkElem("Tab"))
                end
                return tb
            end
            tab.AddLeftTabbox = function(self)
                return mkTB()
            end
            tab.AddRightTabbox = function(self)
                return mkTB()
            end
            return tab
        end
        Window.SetWindowTitle = function(self, s) end
        Window.AddDialog = function(self, a, b) end
        return Window
    end,
}
local ThemeManager = {
    SetLibrary = function(self, l) end,
    SetFolder = function(self, f) end,
    ApplyToTab = function(self, t) end,
    ApplyToGroupbox = function(self, g) end,
}
local SaveManagerCalls = {}
local SaveManager = {
    SetLibrary = function(self, l) end,
    SetFolder = function(self, f)
        SaveManagerCalls.folder = f
    end,
    SetSubFolder = function(self, f) end,
    IgnoreThemeSettings = function(self) end,
    SetIgnoreIndexes = function(self, t) end,
    BuildConfigSection = function(self, t) end,
    LoadAutoloadConfig = function(self) end,
    SetLoadingOrder = function(self, a, b) end,
}

math.clamp = function(x, a, b)
    return math.max(a, math.min(b, x))
end
table.create = function(n)
    return {}
end
table.clear = function(t)
    for k in pairs(t) do
        t[k] = nil
    end
end
string.split = function(s, sep)
    local out = {}
    for part in string.gmatch(s, "([^" .. sep .. "]+)") do
        out[#out + 1] = part
    end
    return out
end

local mockOS = {
    clock = function()
        return SIM.time
    end,
    time = function()
        return 1000000 + math.floor(SIM.time)
    end,
    date = os.date,
}

local function setAttr(obj, k, v)
    obj:SetAttribute(k, v)
end

local ENV
ENV = setmetatable({
    game = game,
    workspace = workspace,
    task = task,
    math = math,
    table = table,
    string = string,
    os = mockOS,
    coroutine = coroutine,
    pcall = pcall,
    xpcall = xpcall,
    select = select,
    ipairs = ipairs,
    pairs = pairs,
    next = next,
    type = type,
    tostring = tostring,
    tonumber = tonumber,
    error = error,
    assert = assert,
    setmetatable = setmetatable,
    getmetatable = getmetatable,
    rawget = rawget,
    rawset = rawset,
    rawequal = rawequal,
    print = print,
    warn = function(...) end,
    unpack = table.unpack,
    tick = function()
        return SIM.time
    end,
    typeof = function(v)
        if type(v) == "table" then
            if v.__signal then
                return "RBXScriptSignal"
            end
            if v.__inst then
                return "Instance"
            end
            if v.__istype then
                return v.__istype
            end
        end
        return type(v)
    end,
    getgenv = function()
        return GENV
    end,
    require = function(obj)
        error("cannot require")
    end,
    firesignal = function(sig, ...)
        sig:Fire(...)
    end,
    fireproximityprompt = function(pp)
        PROMPT_FIRES[#PROMPT_FIRES + 1] = pp
        pp._fired = pp._fired + 1
        if pp._semantics then
            pp._semantics()
        end
    end,
    firetouchinterest = function(a, b, c)
        PROMPT_FIRES[#PROMPT_FIRES + 1] = { _touch = a }
    end,
    loadstring = function(src)
        return load(src, "@mockload", "t", ENV)
    end,
    writefile = function(f, s)
        FILES[f] = s
    end,
    isfile = function(f)
        return FILES[f] ~= nil
    end,
    appendfile = function(f, s)
        if f == "1log.txt" then
            NOTYURI_LOG[#NOTYURI_LOG + 1] = s
        end
        FILES[f] = (FILES[f] or "") .. s
    end,
    delfile = function(f)
        FILES[f] = nil
    end,
    identifyexecutor = nil,
    isexecutorclosure = function()
        return false
    end,
    _MOCK_LIBRARY = Library,
    _MOCK_THEME = ThemeManager,
    _MOCK_SAVE = SaveManager,
    CFrame = {
        new = function(...)
            local arg = { ... }
            return { __istype = "CFrame", Position = arg[1] }
        end,
        lookAt = function(a, b)
            return { __istype = "CFrame", Position = a }
        end,
    },
    Vector3 = { new = v3 },
    Vector2 = { new = function(x, y)
        return { X = x or 0, Y = y or 0 }
    end },
    UDim2 = { new = ud2 },
    Color3 = {
        new = function(...)
            return { __istype = "Color3" }
        end,
    },
    Enum = setmetatable({}, { __index = function()
        return setmetatable({}, { __index = function()
            return {}
        end })
    end }),
    Instance = {
        new = function(className, parent)
            local o = inst(className, className)
            if parent then
                o.Parent = parent
                table.insert(parent._children, o)
            end
            return o
        end,
    },
}, {
    __index = function(t, k)
        return nil
    end,
})

if MODE == "house" then
    local House = child(workspace, "Folder", "House")
    local partsFolder = child(House, "Folder", "Parts")
    local interiorLayout = child(partsFolder, "Folder", "InteriorLayout")
    local curtains = child(interiorLayout, "Folder", "Curtains")
    local curtainModels = {}
    for i = 1, 8 do
        local cm = child(curtains, "Model", string.format("%02d_Curtain_Glass", i))
        local anchor = part(cm, "BlindsPromptAnchor", i, 1, i)
        local bp = prompt(child(anchor, "Attachment", "BlindsPromptAnchor"), "BlindsPrompt")
        bp._semantics = function()
            setAttr(cm, "Closed", true)
        end
        curtainModels[#curtainModels + 1] = cm
    end
    local bedroom = child(partsFolder, "Folder", "Bedroom")
    local mattress = part(bedroom, "Mattress", 2, 0, 2)
    local SleepPrompt = prompt(child(mattress, "Attachment", "SleepPromptAttachment"), "SleepPrompt")
    local laundry = child(partsFolder, "Folder", "Laundry")
    local litterBox = part(laundry, "LitterBox", 3, 0, 3)
    local CleanLitterPrompt = prompt(child(litterBox, "Attachment", "LitterInteraction"), "CleanLitterPrompt")

    local important = child(House, "Folder", "Important")
    local doors = child(important, "Folder", "Doors")
    local frontDoor = child(doors, "Model", "Front Door")
    local frontLeaf = child(frontDoor, "Model", "Leaf")
    local deadbolt = part(frontLeaf, "Deadbolt", 1, 1, 1)
    local LockPrompt = prompt(child(deadbolt, "Attachment", "LockPromptAttachment"), "LockPrompt")
    prompt(child(deadbolt, "Attachment", "LockPromptAttachment"), "UnlockPrompt")
    local frontHandle = part(frontLeaf, "Handle", 1, 1, 1.5)
    prompt(child(frontHandle, "Attachment", "DoorPromptAttachment"), "OpenClosePrompt")

    local roomLighting = child(important, "Folder", "RoomLighting")
    local roomsFolder = child(roomLighting, "Folder", "Rooms")
    local Rooms = {}
    local roomDefs = { { "LivingRoom", "LivingRoom" }, { "Hallway", "BedroomHall" }, { "Bathroom", "Bathroom" }, { "LaundryUtility", "Laundry" }, { "KitchenDining", "Kitchen" }, { "Bedroom", "Bedroom" } }
    for _, def in ipairs(roomDefs) do
        local rf = child(roomsFolder, "Folder", def[1])
        setAttr(rf, "On", def[1] ~= "Bathroom")
        Rooms[def[1]] = rf
    end
    local switchesFolder = child(roomLighting, "Folder", "Switches")
    for _, def in ipairs({ { "BathroomSwitch", "Bathroom" }, { "BedroomSwitch", "Bedroom" }, { "BedroomHallSwitch", "Hallway" }, { "LivingRoomSwitch", "LivingRoom" }, { "EntryHallSwitch", "Hallway" }, { "KitchenSwitch", "KitchenDining" }, { "LaundrySwitch", "LaundryUtility" } }) do
        local sw = child(switchesFolder, "Model", def[1])
        local faceplate = part(sw, "Faceplate", 0, 1, 0)
        local interaction = child(faceplate, "Attachment", "Interaction")
        local lsp = prompt(interaction, "LightSwitchPrompt")
        setAttr(lsp, "Room", def[2])
        local room = def[2]
        lsp._semantics = function()
            local rf = Rooms[room]
            if rf then
                setAttr(rf, "On", rf:GetAttribute("On") ~= true)
            end
        end
    end

    local kitchen = child(important, "Folder", "Kitchen")
    local cabinets = child(kitchen, "Folder", "Cabinets")
    local baseN1 = child(cabinets, "Model", "Base_N1")
    local catFoodCan = child(baseN1, "Model", "CatFoodCan")
    local canBody = part(catFoodCan, "CanBody", 4, 1, 4)
    local CanTake = prompt(child(canBody, "Attachment", "TakePromptAttachment"), "TakePrompt")
    local foodBowlFolder = child(kitchen, "Folder", "FoodBowl")
    local foodBowlModel = child(foodBowlFolder, "Model", "Food Bowl")
    local bowlCylinder = part(foodBowlModel, "Cylinder", 5, 0, 5)
    local FillPrompt = prompt(child(bowlCylinder, "Attachment", "FillPromptAttachment"), "FillPrompt")
    local fridge = child(kitchen, "Model", "Fridge")
    local tvDinner = child(fridge, "Model", "TVDinner")
    local tray = part(tvDinner, "Tray", 6, 1, 6)
    local DinnerTake = prompt(child(tray, "Attachment", "TakePromptAttachment"), "TakePrompt")
    local microwave = child(cabinets, "Model", "Microwave")
    local mwDoor = child(microwave, "Model", "Door")
    local mwLeaf = child(mwDoor, "Model", "Leaf")
    local mwPanel = part(mwLeaf, "Panel", 7, 1, 7)
    local MwDoorPrompt = prompt(child(mwPanel, "Attachment", "OpenClosePromptAttachment"), "OpenClosePrompt")
    local carcass = child(microwave, "Model", "Carcass")
    local turntable = part(carcass, "Turntable", 7, 0.5, 7)
    local CookPrompt = prompt(child(turntable, "Attachment", "CookPromptAttachment"), "CookPrompt")
    local livingRoom = child(important, "Folder", "LivingRoom")
    local laserPointer = child(livingRoom, "Model", "LaserPointer")
    local laserBody = part(laserPointer, "Body", 8, 1, 8)
    local LaserTake = prompt(child(laserBody, "Attachment", "TakePromptAttachment"), "TakePrompt")
    local tv = child(livingRoom, "Model", "TV")
    local tvScreen = part(tv, "Screen", 9, 1, 9)
    local TVPrompt = prompt(child(tvScreen, "Attachment", "TogglePromptAttachment"), "TogglePrompt")
    local bathroom = child(important, "Folder", "Bathroom")
    local toilet = child(bathroom, "Model", "Toilet")
    local flushModel = child(toilet, "Model", "Flush")
    local lever = part(flushModel, "Lever", 10, 1, 10)
    local FlushPrompt = prompt(child(lever, "Attachment", "FlushPromptAttachment"), "FlushPrompt")
    local floorLamp = child(livingRoom, "Model", "FloorLamp")
    part(floorLamp, "Pole", 11, 1, 11)

    local Neighborhood = child(workspace, "Folder", "Neighborhood")
    local nparts = child(Neighborhood, "Folder", "Parts")
    local frontYard = child(nparts, "Model", "PetsitFrontYard")
    local mailboxModel = child(frontYard, "Model", "Mailbox")
    local mailboxBody = part(mailboxModel, "Body", 20, 2, 20)
    local MailboxPrompt = prompt(child(mailboxBody, "Attachment", "MailPromptAttachment"), "MailboxPrompt")

    local Cat = child(workspace, "Model", "Cat")
    Cat.Position = v3(0, 0, 5)
    local catBody = part(Cat, "Body", 0, 0, 5)

    local LitterGui = child(PlayerGui, "ScreenGui", "LitterCleaningGui")
    local LitterPanel = child(LitterGui, "Frame", "Panel")
    local LitterBoard = child(LitterPanel, "Frame", "Board")
    local Bag = child(LitterBoard, "Frame", "Bag")
    Bag.Position = ud2(0.35, 0, 0.4, 0)
    Bag.Size = ud2(0.2, 0, 0.2, 0)

    local PetRemote = mkRemote("Cat", "Pet")
    local StareRemote = mkRemote("Cat", "Stare")
    local EatRemote = mkRemote("Meal", "Eat")
    local LaserRemote = mkRemote("Laser", "Point")
    local PhotoRemote = mkRemote("Phone", "Photo")
    local LitterRemote = mkRemote("LitterCleaning", "Event")

    for _, flag in ipairs({ "Chore_Feed", "Chore_Eat", "Chore_Litter", "Chore_Lock", "Chore_Mail", "Chore_Play" }) do
        setAttr(workspace, flag, false)
    end
    for _, flag in ipairs({ "Catzilla", "CreepyHead", "FakeDoor", "Grandma", "Misplaced", "Seeker", "SmilingMan", "StalkerInBedroom", "ToiletFace", "VoidOutside", "WindowMonster" }) do
        setAttr(workspace, flag, false)
    end
    setAttr(workspace, "Night", 1)
    setAttr(workspace, "PetCount", 0)
    setAttr(workspace, "CreepyStare", 0)

    local tookCan = false
    CanTake._semantics = function()
        tookCan = true
    end
    FillPrompt._semantics = function()
        if tookCan then
            setAttr(workspace, "Chore_Feed", true)
        end
    end
    DinnerTake._semantics = function()
        if not Backpack:FindFirstChild("TV Dinner") then
            local t = child(Backpack, "Tool", "TV Dinner")
            setAttr(t, "Meal", true)
            setAttr(t, "Hot", false)
        end
    end
    MwDoorPrompt._semantics = function()
        setAttr(mwDoor, "Open", true)
    end
    CookPrompt._semantics = function()
        local t = Backpack:FindFirstChild("TV Dinner")
        if t and mwDoor:GetAttribute("Open") then
            task.delay(1.0, function()
                setAttr(t, "Hot", true)
            end)
        end
    end
    EatRemote.FireServer = function(self)
        self._calls[#self._calls + 1] = true
        local t = Backpack:FindFirstChild("TV Dinner") or charModel:FindFirstChild("TV Dinner")
        if t and t:GetAttribute("Hot") then
            for i, c in ipairs(t.Parent._children) do
                if c == t then
                    table.remove(t.Parent._children, i)
                    break
                end
            end
            t.Parent = nil
            setAttr(workspace, "Chore_Eat", true)
        end
    end
    MailboxPrompt._semantics = function()
        setAttr(workspace, "Chore_Mail", true)
    end
    LockPrompt._semantics = function()
        setAttr(workspace, "Chore_Lock", true)
    end
    LaserTake._semantics = function()
        if not Backpack:FindFirstChild("Laser Pointer") then
            local t = child(Backpack, "Tool", "Laser Pointer")
            setAttr(t, "Laser", true)
        end
    end
    LaserRemote.FireServer = function(self, pos, active)
        self._calls[#self._calls + 1] = { pos = pos, active = active }
        if active and pos and Cat.Position then
            local d = (pos - Cat.Position).Magnitude
            if d <= 8 then
                LaserRemote._nearCount = (LaserRemote._nearCount or 0) + 1
                if LaserRemote._nearCount >= 10 then
                    setAttr(workspace, "Chore_Play", true)
                end
            end
        end
    end
    PetRemote.FireServer = function(self)
        self._calls[#self._calls + 1] = true
        setAttr(workspace, "PetCount", (workspace:GetAttribute("PetCount") or 0) + 1)
    end
    StareRemote.FireServer = function(self, seconds)
        self._calls[#self._calls + 1] = seconds
        local progress = (workspace:GetAttribute("CreepyStare") or 0) + (tonumber(seconds) or 0) / 8
        if progress >= 1 then
            setAttr(workspace, "CreepyStare", 1)
            setAttr(workspace, "CreepyHead", false)
        else
            setAttr(workspace, "CreepyStare", progress)
        end
    end
    PhotoRemote.FireServer = function(self, cframe, instArg)
        self._calls[#self._calls + 1] = { cframe = cframe, target = instArg }
        local owner = instArg and instArg.Parent
        if owner and owner.Parent == workspace and owner.Name == "SmilingMan" then
            setAttr(workspace, "SmilingMan", false)
        end
        if owner and owner.Parent == livingRoom and owner.Name == "FloorLamp" then
            setAttr(workspace, "Misplaced", false)
        end
    end
    TVPrompt._semantics = function()
        setAttr(tv, "On", true)
        task.delay(1.0, function()
            setAttr(workspace, "Catzilla", false)
        end)
    end
    FlushPrompt._semantics = function()
        setAttr(workspace, "ToiletFace", false)
    end

    local litterSid = 0
    CleanLitterPrompt._semantics = function()
        litterSid = litterSid + 1
        local sid = litterSid
        task.delay(0.2, function()
            LitterRemote.OnClientEvent:Fire("Start", sid)
        end)
    end
    LitterRemote._grabbed = {}
    LitterRemote._collected = 0
    LitterRemote.FireServer = function(self, op, sid, a, b, c)
        self._calls[#self._calls + 1] = { op = op, sid = sid, a = a, b = b, c = c }
        if op == "Grab" then
            self._grabbed[a] = true
        elseif op == "Drop" then
            if self._grabbed[a] then
                self._grabbed[a] = nil
                if type(b) == "number" and type(c) == "number" and b >= Bag.Position.X.Scale and b <= Bag.Position.X.Scale + Bag.Size.X.Scale and c >= Bag.Position.Y.Scale and c <= Bag.Position.Y.Scale + Bag.Size.Y.Scale then
                    self._collected = self._collected + 1
                    task.delay(0.1, function()
                        LitterRemote.OnClientEvent:Fire("Collected", sid, { index = a, found = self._collected })
                        if self._collected >= 5 then
                            LitterRemote.OnClientEvent:Fire("Win", sid)
                            setAttr(workspace, "Chore_Litter", true)
                        end
                    end)
                else
                    task.delay(0.1, function()
                        LitterRemote.OnClientEvent:Fire("Retry", sid, a)
                    end)
                end
            end
        elseif op == "Cancel" then
            self._grabbed = {}
        end
    end
    SleepPrompt._semantics = function()
        local allDone = true
        for _, flag in ipairs({ "Chore_Feed", "Chore_Eat", "Chore_Litter", "Chore_Lock", "Chore_Mail", "Chore_Play" }) do
            if workspace:GetAttribute(flag) ~= true then
                allDone = false
            end
        end
        local clear = true
        for _, flag in ipairs({ "Catzilla", "CreepyHead", "FakeDoor", "Grandma", "Misplaced", "Seeker", "SmilingMan", "StalkerInBedroom", "ToiletFace", "VoidOutside", "WindowMonster" }) do
            if workspace:GetAttribute(flag) == true then
                clear = false
            end
        end
        if allDone and clear then
            setAttr(workspace, "Night", (workspace:GetAttribute("Night") or 1) + 1)
            for _, flag in ipairs({ "Chore_Feed", "Chore_Eat", "Chore_Litter", "Chore_Lock", "Chore_Mail", "Chore_Play" }) do
                setAttr(workspace, flag, false)
            end
        end
    end

    local SCRIPT_PATH = "/home/z/my-project/Yuri/CatSitting/CatSitting.lua"
    local f = io.open(SCRIPT_PATH, "rb")
    assert(f, "script file missing")
    local src = f:read("*a")
    f:close()
    local chunk, loadErr = load(src, "CatSitting", "t", ENV)
    assert(chunk, "script load error: " .. tostring(loadErr))

    local ok, scriptErr = pcall(chunk)
    CHECK("script loads without error", ok)
    if not ok then
        print("LOAD ERROR: " .. tostring(scriptErr))
    end
    CHECK("guard set on load", GENV.ayasemiyatongekissazumirisa == true)
    CHECK("no ERROR notification on load", #NOTIFICATIONS == 0 or not NOTIFICATIONS[1]:find("ERROR"))
    CHECK("SaveManager folder Yuri/CatSitting", SaveManagerCalls.folder == "Yuri/CatSitting")
    CHECK("toggle AutoChores exists", Toggles.AutoChores ~= nil)
    CHECK("toggle AutoPlay exists", Toggles.AutoPlay ~= nil)
    CHECK("toggle AutoPet exists", Toggles.AutoPet ~= nil)
    CHECK("toggle AutoSleep exists", Toggles.AutoSleep ~= nil)
    CHECK("toggle AutoAnomalies exists", Toggles.AutoAnomalies ~= nil)
    CHECK("toggle AutoQueue exists", Toggles.AutoQueue ~= nil)
    CHECK("toggle AutoCrate exists", Toggles.AutoCrate ~= nil)

    Toggles.AutoChores:SetValue(true)
    runTasks(14)
    CHECK("AutoChores: feed flow fires can + fill prompts", CanTake._fired >= 1 and FillPrompt._fired >= 1)
    CHECK("AutoChores: Chore_Feed completes", workspace:GetAttribute("Chore_Feed") == true)
    CHECK("AutoChores: eat flow takes dinner, opens microwave, cooks", DinnerTake._fired >= 1 and MwDoorPrompt._fired >= 1 and CookPrompt._fired >= 1)
    CHECK("AutoChores: meal eaten via wire", #EatRemote._calls >= 1 and workspace:GetAttribute("Chore_Eat") == true)
    CHECK("AutoChores: mail collected", MailboxPrompt._fired >= 1 and workspace:GetAttribute("Chore_Mail") == true)
    CHECK("AutoChores: door locked", LockPrompt._fired >= 1 and workspace:GetAttribute("Chore_Lock") == true)
    CHECK("AutoChores: litter minigame won via Grab/Drop wires", #LitterRemote._calls >= 10 and workspace:GetAttribute("Chore_Litter") == true)
    local litterDrops = 0
    local litterDropsInBag = 0
    for _, c in ipairs(LitterRemote._calls) do
        if c.op == "Drop" then
            litterDrops = litterDrops + 1
            if c.b >= Bag.Position.X.Scale and c.b <= Bag.Position.X.Scale + Bag.Size.X.Scale and c.c >= Bag.Position.Y.Scale and c.c <= Bag.Position.Y.Scale + Bag.Size.Y.Scale then
                litterDropsInBag = litterDropsInBag + 1
            end
        end
    end
    CHECK("litter drop coords inside bag rect", litterDrops >= 5 and litterDropsInBag == litterDrops)
    Toggles.AutoChores:SetValue(false)

    Toggles.AutoPet:SetValue(true)
    runTasks(3)
    CHECK("AutoPet: pet wire fires repeatedly", #PetRemote._calls >= 5)
    CHECK("AutoPet: PetCount increments", (workspace:GetAttribute("PetCount") or 0) >= 5)
    local petSnapshot = #PetRemote._calls
    Toggles.AutoPet:SetValue(false)
    runTasks(1)
    CHECK("AutoPet: stops on toggle off", #PetRemote._calls == petSnapshot)

    Toggles.AutoPlay:SetValue(true)
    runTasks(6)
    CHECK("AutoPlay: laser tool taken and equipped", LaserTake._fired >= 1 and charModel:FindFirstChild("Laser Pointer") ~= nil)
    CHECK("AutoPlay: laser point wires fire near cat", (LaserRemote._nearCount or 0) >= 10)
    CHECK("AutoPlay: Chore_Play completes", workspace:GetAttribute("Chore_Play") == true)
    local laserCalls = LaserRemote._calls
    local lastCall = laserCalls[#laserCalls]
    CHECK("AutoPlay: stop signal sent (nil, false)", lastCall ~= nil and lastCall.active == false and lastCall.pos == nil)
    local maxDx, minZ, maxZ = 0, math.huge, -math.huge
    for _, c in ipairs(laserCalls) do
        if c.active and c.pos then
            local dx = math.abs(c.pos.X - Cat.Position.X)
            if dx > maxDx then
                maxDx = dx
            end
            if c.pos.Z < minZ then
                minZ = c.pos.Z
            end
            if c.pos.Z > maxZ then
                maxZ = c.pos.Z
            end
        end
    end
    CHECK("AutoPlay: dot oscillates on one axis (no cat spinning)", maxDx <= 4.5 and (maxZ - minZ) <= 0.001)
    Toggles.AutoPlay:SetValue(false)

    Toggles.AutoAnomalies:SetValue(true)
    setAttr(workspace, "Grandma", true)
    runTasks(4)
    CHECK("AutoAnomalies: lights off for On rooms", Rooms.LivingRoom:GetAttribute("On") == false and Rooms.KitchenDining:GetAttribute("On") == false)
    CHECK("AutoAnomalies: already-off room stays off", Rooms.Bathroom:GetAttribute("On") == false)
    local switchFired = 0
    for _, p in ipairs(PROMPT_FIRES) do
        if p.Name == "LightSwitchPrompt" then
            switchFired = switchFired + 1
        end
    end
    CHECK("AutoAnomalies: 5 switch prompts fired (Bathroom skipped, Hallway dual-switch deduped)", switchFired == 5)
    setAttr(workspace, "Grandma", false)

    setAttr(workspace, "VoidOutside", true)
    runTasks(9)
    local blindsFired = 0
    for _, p in ipairs(PROMPT_FIRES) do
        if p.Name == "BlindsPrompt" then
            blindsFired = blindsFired + 1
        end
    end
    local curtainFireList = {}
    for _, cm in ipairs(curtainModels) do
        local bp = cm:FindFirstChildWhichIsA("ProximityPrompt", true)
        curtainFireList[#curtainFireList + 1] = cm.Name .. "=" .. tostring(bp and bp._fired or "nf")
    end
    print("DBG curtains " .. table.concat(curtainFireList, " "))
    CHECK("AutoAnomalies: all 8 curtains closed once", blindsFired == 8)
    setAttr(workspace, "VoidOutside", false)
    runTasks(2)

    setAttr(workspace, "Catzilla", true)
    runTasks(6)
    CHECK("AutoAnomalies: TV toggled once for Catzilla", TVPrompt._fired == 1)
    CHECK("AutoAnomalies: Catzilla resolved", workspace:GetAttribute("Catzilla") == false)

    setAttr(workspace, "ToiletFace", true)
    runTasks(3)
    CHECK("AutoAnomalies: toilet flushed for ToiletFace", FlushPrompt._fired >= 1 and workspace:GetAttribute("ToiletFace") == false)

    setAttr(workspace, "CreepyHead", true)
    setAttr(workspace, "CreepyStare", 0)
    local CreepyCatHead = child(Cat, "Model", "CreepyCatHead")
    part(CreepyCatHead, "Head", 0, 1, 5)
    runTasks(6)
    CHECK("AutoAnomalies: stare wire fires with batched seconds", #StareRemote._calls >= 2)
    CHECK("AutoAnomalies: CreepyHead resolved via client-authored stare time", workspace:GetAttribute("CreepyHead") == false)

    local smilingMan = child(workspace, "Model", "SmilingMan")
    part(smilingMan, "Body", 30, 1, 30)
    setAttr(workspace, "SmilingMan", true)
    runTasks(6)
    CHECK("AutoAnomalies: photo wire fires at SmilingMan instance", #PhotoRemote._calls >= 1 and PhotoRemote._calls[1].target ~= nil)
    CHECK("AutoAnomalies: SmilingMan resolved", workspace:GetAttribute("SmilingMan") == false)

    setAttr(workspace, "Misplaced", true)
    runTasks(14)
    local photoHitLamp = false
    for _, c in ipairs(PhotoRemote._calls) do
        if c.target and c.target.Parent and c.target.Parent.Name == "FloorLamp" then
            photoHitLamp = true
        end
    end
    print("DBG misplaced=" .. tostring(workspace:GetAttribute("Misplaced")) .. " hitLamp=" .. tostring(photoHitLamp) .. " photoCalls=" .. tostring(#PhotoRemote._calls)); CHECK("AutoAnomalies: misplaced sweep photographs the displaced item", photoHitLamp and workspace:GetAttribute("Misplaced") == false)
    Toggles.AutoAnomalies:SetValue(false)

    local houseDoorFired = 0
    for _, p in ipairs(PROMPT_FIRES) do
        if p.Name == "OpenClosePrompt" and p ~= MwDoorPrompt then
            houseDoorFired = houseDoorFired + 1
        end
    end
    CHECK("FakeDoor respected: house door prompts never auto-fired", houseDoorFired == 0)

    for _, flag in ipairs({ "Chore_Feed", "Chore_Eat", "Chore_Litter", "Chore_Lock", "Chore_Mail", "Chore_Play" }) do
        setAttr(workspace, flag, true)
    end
    Toggles.AutoSleep:SetValue(true)
    runTasks(4)
    CHECK("AutoSleep: advances night when chores done and clear", workspace:GetAttribute("Night") == 2)
    Toggles.AutoSleep:SetValue(false)
    setAttr(workspace, "Night", 1)
    for _, flag in ipairs({ "Chore_Feed", "Chore_Eat", "Chore_Litter", "Chore_Lock", "Chore_Mail", "Chore_Play" }) do
        setAttr(workspace, flag, false)
    end
    Toggles.AutoSleep:SetValue(true)
    runTasks(4)
    CHECK("AutoSleep: never sleeps with pending chores", workspace:GetAttribute("Night") == 1)
    Toggles.AutoSleep:SetValue(false)

    local autoErrors = 0
    for _, line in ipairs(NOTYURI_LOG) do
        if line:find("AutoChores") or line:find("AutoPlay") or line:find("AutoPet") or line:find("AutoSleep") or line:find("AutoAnomalies") then
            autoErrors = autoErrors + 1
        end
    end
    CHECK("no Auto* loop errors logged", autoErrors == 0)
elseif MODE == "lobby" then
    local Lobby = child(workspace, "Folder", "Lobby")
    local lobbyImportant = child(Lobby, "Folder", "Important")
    local teleportPod = child(lobbyImportant, "Model", "TeleportPod")
    local zone = part(teleportPod, "Zone", 0, 0, 0)

    local GetStateRF = mkRemoteFunction("Shop", "GetState")
    local OpenCrateRF = mkRemoteFunction("Shop", "OpenCrate")
    local cash = 50
    GetStateRF.InvokeServer = function(self)
        self._calls[#self._calls + 1] = true
        return { cash = cash, owned = {}, equipped = "Orange" }
    end
    OpenCrateRF.InvokeServer = function(self)
        self._calls[#self._calls + 1] = true
        if cash < 10 then
            return { ok = false, reason = "cash", state = { cash = cash } }
        end
        cash = cash - 10
        return { ok = true, state = { cash = cash }, reel = {} }
    end

    local SCRIPT_PATH = "/home/z/my-project/Yuri/CatSitting/CatSitting.lua"
    local f = io.open(SCRIPT_PATH, "rb")
    assert(f, "script file missing")
    local src = f:read("*a")
    f:close()
    local chunk, loadErr = load(src, "CatSitting", "t", ENV)
    assert(chunk, "script load error: " .. tostring(loadErr))

    local ok, scriptErr = pcall(chunk)
    CHECK("lobby: script loads without error", ok)
    if not ok then
        print("LOAD ERROR: " .. tostring(scriptErr))
    end
    CHECK("lobby: no ERROR notification on load", #NOTIFICATIONS == 0 or not NOTIFICATIONS[1]:find("ERROR"))
    CHECK("lobby: SaveManager folder Yuri/CatSitting", SaveManagerCalls.folder == "Yuri/CatSitting")
    CHECK("lobby: AutoCrate toggle exists", Toggles.AutoCrate ~= nil)
    CHECK("lobby: AutoQueue toggle exists", Toggles.AutoQueue ~= nil)

    Toggles.AutoCrate:SetValue(true)
    runTasks(10)
    CHECK("lobby: AutoCrate drains crates until under 10 cash", #OpenCrateRF._calls == 5 and cash == 0)
    local crateSnapshot = #OpenCrateRF._calls
    runTasks(6)
    CHECK("lobby: AutoCrate stops when cash is under cost", #OpenCrateRF._calls == crateSnapshot)
    Toggles.AutoCrate:SetValue(false)

    Toggles.AutoQueue:SetValue(true)
    runTasks(3)
    local touched = false
    for _, p in ipairs(PROMPT_FIRES) do
        if p._touch == zone then
            touched = true
        end
    end
    CHECK("lobby: AutoQueue fires touch on TeleportPod Zone", touched)
    CHECK("lobby: AutoQueue positions player at zone", (hrp.Position - zone.Position).Magnitude <= 5)
    Toggles.AutoQueue:SetValue(false)

    local autoErrors = 0
    for _, line in ipairs(NOTYURI_LOG) do
        if line:find("AutoCrate") or line:find("AutoQueue") then
            autoErrors = autoErrors + 1
        end
    end
    CHECK("lobby: no Auto* loop errors logged", autoErrors == 0)
end

print(string.format("\n[%s] === %d/%d checks passed ===", MODE, CHECKS.pass, CHECKS.pass + CHECKS.fail))
if CHECKS.fail > 0 then
    os.exit(1)
end
