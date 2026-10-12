if getgenv().ayasemiyatongekissazumirisa then
    warn("yuri")
    return
end
function missing(t, f, fallback)
        if type(f) == t then return f end
        return fallback
end
cloneref = missing("function", cloneref, function(...) return ... end)
getgc = missing("function", getgc or get_gc_objects)
getconnections = missing("function", getconnections or get_signal_cons)
local Support = {
    Webhook = (typeof(request) == "function" or typeof(http_request) == "function"),
    Clipboard = (typeof(setclipboard) == "function"),
    FileIO = (typeof(writefile) == "function" and typeof(isfile) == "function"),
    QueueOnTeleport = (typeof(queue_on_teleport) == "function" or typeof(queueonteleport) == "function"),
    Connections = (typeof(getconnections) == "function"),
    FPS = (typeof(setfpscap) == "function"),
    Proximity = (typeof(fireproximityprompt) == "function"),
    HookMeta = (typeof(hookmetamethod) == "function"),
    Firesignal = (typeof(firesignal) == "function"),
}
Services = setmetatable({}, {
        __index = function(self, name)
                local success, cache = pcall(function()
                        return cloneref(game:GetService(name))
                end)
                if success then
                        rawset(self, name, cache)
                        return cache
                else
                        error("Invalid Service: " .. tostring(name))
                end
        end
})
local Players = Services.Players
local Plr = setmetatable({}, {
    __index = function(_, key)
        local lp = Players.LocalPlayer
        if not lp then return nil end
        local val = lp[key]
        if type(val) == "function" then
            return function(_, ...)
                return val(lp, ...)
            end
        end
        return val
    end,
    __newindex = function(_, key, value)
        local lp = Players.LocalPlayer
        if not lp then return end
        lp[key] = value
    end,
})
local Lighting = Services.Lighting
local RS = Services.ReplicatedStorage
local RunService = Services.RunService
local HttpService = Services.HttpService
local GuiService = Services.GuiService
local TeleportService = Services.TeleportService
local Marketplace = Services.MarketplaceService
local UIS = Services.UserInputService
local VirtualUser = Services.VirtualUser
local v, Asset = pcall(function()
    return Marketplace:GetProductInfo(game.PlaceId)
end)
local assetName = "game name"
if v and Asset then
    assetName = Asset.Name
end
local executorName = (identifyexecutor and identifyexecutor() or "Unknown"):lower()
local executorDisplayName = (identifyexecutor and identifyexecutor() or "Unknown")
local LimitedExecutors = {"xeno", "solara",}
local isLimitedExecutor = false
for _, name in ipairs(LimitedExecutors) do
    if string.find(executorName, name) then
        isLimitedExecutor = true
        break
    end
end
local l,f={},"1log.txt";if isfile and isfile(f)then delfile(f)end;if writefile then writefile(f,"")end;function notyuri(...)local t=table.create(select("#",...))for i=1,select("#",...)do t[i]=tostring(select(i,...))end local s=("[%s] %s"):format(os.date("%H:%M:%S"),table.concat(t," "));l[#l+1]=s;if appendfile then appendfile(f,s.."\n")end end
local repo = "https://raw.githubusercontent.com/iLove-yuri/Linoria/main/"
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()
getgenv().ayasemiyatongekissazumirisa = true
local Options = Library.Options
local Toggles = Library.Toggles
Library.ShowToggleFrameInKeybinds = true
Library.ShowCustomCursor = true
Library.NotifySide = "Left"
local function AddInfo(Window)
    local InfoTab = Window:AddTab("Info")
    local InfoLeft = InfoTab:AddLeftGroupbox("Information")
    local statusText = isLimitedExecutor and "<font color='#FFA500'>Semi-Working</font>" or "<font color='#00FF00'>Working</font>"
    local extraNote = isLimitedExecutor
        and "<b>NOTE:</b> May experiencing bugs for some features!"
        or "All features should works properly!"
    InfoLeft:AddLabel("<b>Executor:</b> " .. executorDisplayName .. "\n<b>Status:</b> " .. statusText .. "\n" .. extraNote, true)
    local InfoRight = InfoTab:AddRightGroupbox("Others")
    InfoRight:AddButton({
        Text = "Join Discord Server",
        Func = function()
            local inviteCode = "6pCsSbVd3E"
            local inviteLink = "https://discord.gg/" .. inviteCode
            local success = false
            if request then
                success = pcall(function()
                    request({
                        Url = "http://127.0.0.1:6463/rpc?v=1",
                        Method = "POST",
                        Headers = {
                            ["Content-Type"] = "application/json",
                            ["Origin"] = "https://discord.com"
                        },
                        Body = HttpService:JSONEncode({
                            cmd = "INVITE_BROWSER",
                            args = { code = inviteCode },
                            nonce = HttpService:GenerateGUID(false)
                        })
                    })
                end)
            end
            if not success and setclipboard then
                setclipboard(inviteLink)
            end
        end,
    })
end
local eh_success, err = pcall(function()
local function GetObject(parent, pathString)
    local current = parent
    for _, name in ipairs(pathString:split(".")) do
        if not current then return nil end
        current = current:FindFirstChild(name)
    end
    return current
end
local function GetSafeModule(parent, name)
    local obj = parent:FindFirstChild(name)
    if obj and obj:IsA("ModuleScript") then
        local success, result = pcall(require, obj)
        if success then return result end
    end
    return nil
end
local Remotes = {
}
local Modules = {
}
local Flags = {}
local Shared = {
}
local Connections = {
    Player_General = nil,
    Knockback = {},
    Reconnect = nil,
    ActiveTween = nil,
}
function AddMultiDropdown(group, id, config)
    if type(group) == "string" then
        local selected = {}
        local dropdown = Options[group]
        local values = dropdown and dropdown.Values or {}
        local chosen = dropdown and dropdown.Value or {}
        if chosen["All"] then
            for _, label in ipairs(values) do
                if label ~= "All" then selected[label] = true end
            end
        else
            for label, active in pairs(chosen) do
                if active and label ~= "All" then selected[label] = true end
            end
        end
        return selected
    end
    config = config or {}
    local values = { "All" }
    for _, v in ipairs(config.Values or {}) do
        table.insert(values, v)
    end
    group:AddDropdown(id, {
        Text = config.Text,
        Values = values,
        Default = config.Default or {},
        Multi = true,
        Searchable = true,
        Callback = config.Callback,
    })
    return Options[id]
end
function SafeLabel(target, id, text)
    if type(target) == "string" then
        local entry = Shared.Labels[target]
        if entry then
            entry.Text = id
            entry.Dirty = true
        end
        return
    end
    local label = target:AddLabel(text, true)
    Shared.Labels[id] = {Label = label, Text = text, Dirty = false}
    Thread("SafeLabel", function()
        while not Library.Unloaded do
            for key, entry in pairs(Shared.Labels) do
                if entry.Dirty then
                    entry.Dirty = false
                    local ok, err = pcall(function()
                        entry.Label:SetText(entry.Text)
                    end)
                    if not ok then
                    end
                end
            end
            task.wait()
        end
    end, true)
    return label
end
function AddSliderToggle(Config, ...)
    local Handlers = {...}
    local Toggle, Slider
    Toggle = Config.Group:AddToggle(Config.Id, {
        Text = Config.Text,
        Default = Config.DefaultToggle or false,
        Disabled = Config.Disabled,
        Callback = function(state)
            if Slider then Slider:SetVisible(state) end
            for _, Handler in ipairs(Handlers) do
                Handler(state, Toggle, Slider)
            end
        end,
    })
    Slider = Config.Group:AddSlider(Config.Id .. "Value", {
        Text = Config.Text,
        Default = Config.Default,
        Min = Config.Min,
        Max = Config.Max,
        Rounding = Config.Rounding or 0,
        Compact = true,
        Visible = false
    })
    return Toggles[Config.Id], Options[Config.Id .. "Value"]
end
local function SafeConnect(key, getSignalFn, handler)
    local ok, signal = pcall(getSignalFn)
    if not ok or not signal then
        return
    end
    Connections[key] = signal:Connect(handler)
end
local function SafeInvoke(remote, skip, ...)
    local args = {...}
    local result = nil
    task.spawn(function()
        local success, res = pcall(function()
            return remote:InvokeServer(unpack(args))
        end)
        result = res
    end)
    if skip then return end
    local start = tick()
    repeat task.wait() until result ~= nil or (tick() - start) > 2
    return result
end
local function fire_event(signal, ...)
    if firesignal then
        return firesignal(signal, ...)
    elseif getconnections then
        local args = {...}
        for _, connection in ipairs(getconnections(signal)) do
            if connection.Fire then
                pcall(function() connection:Fire(unpack(args)) end)
            elseif connection.Function then
                task.spawn(connection.Function, unpack(args))
            end
        end
    else
        warn("Your executor does not support firesignal or getconnections.")
    end
end
local function Cleanup(tbl)
    for key, value in pairs(tbl) do
        if typeof(value) == "RBXScriptConnection" then
            value:Disconnect()
            tbl[key] = nil
        elseif typeof(value) == 'thread' then
            task.cancel(value)
            tbl[key] = nil
        elseif type(value) == 'table' then
            Cleanup(value)
        end
    end
end
function Thread(featurePath, featureFunc, isEnabled, ...)
    local pathParts = featurePath:split(".")
    local currentTable = Flags
    for i = 1, #pathParts - 1 do
        local part = pathParts[i]
        if not currentTable[part] then currentTable[part] = {} end
        currentTable = currentTable[part]
    end
    local flagKey = pathParts[#pathParts]
    local activeThread = currentTable[flagKey]
    if isEnabled then
        if not activeThread or coroutine.status(activeThread) == "dead" then
            currentTable[flagKey] = task.spawn(featureFunc, ...)
        end
    else
        if activeThread and typeof(activeThread) == 'thread' then
            task.cancel(activeThread)
            currentTable[flagKey] = nil
        end
    end
end
local function SafeLoop(name, func)
    return function()
        local success, err = pcall(func)
        if not success then
            Library:Notify("Error in ["..name.."]: "..tostring(err), 10)
            warn("Error in ["..name.."]: "..tostring(err))
        end
    end
end
local function CommaFormat(n)
    local s = tostring(n)
    return s:reverse():gsub("%d%d%d", "%1,"):reverse():gsub("^,", "")
end
local function Abbreviate(n)
    local abbrev = {{1e12, "T"}, {1e9, "B"}, {1e6, "M"}, {1e3, "K"}}
    for _, v in ipairs(abbrev) do
        if n >= v[1] then return string.format("%.1f%s", n / v[1], v[2]) end
    end
    return tostring(n)
end
local function GetCharacter()
    local c = Plr.Character
    return (c and c:FindFirstChild("HumanoidRootPart") and c:FindFirstChildOfClass("Humanoid")) and c or nil
end
local function GetPosition(target)
    local kind = typeof(target)
    if kind == "CFrame" then
        return target
    elseif kind == "Vector3" then
        return CFrame.new(target)
    elseif kind == "Instance" then
        if target:IsA("BasePart") then
            return target.CFrame
        elseif target:IsA("Model") then
            return target:GetPivot()
        end
    end
    return nil
end
local function GetNearest(list, filterFn)
    local char = GetCharacter()
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    local best, bestDist = nil, math.huge
    for _, inst in ipairs(list) do
        if not filterFn or filterFn(inst) then
            local part = inst:IsA("BasePart") and inst or (inst:IsA("Model") and inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart"))
            if part then
                local dist = (part.Position - root.Position).Magnitude
                if dist < bestDist then
                    bestDist = dist
                    best = inst
                end
            end
        end
    end
    return best, bestDist
end
local function TPTo(target, offset)
    local char = GetCharacter()
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    local cframe = GetPosition(target)
    if not cframe then return false end
    if offset then
        cframe = cframe * CFrame.new(offset)
    end
    hrp.CFrame = cframe
    return true
end
local function TweenTo(speed, target, offset, arive)
    local char = GetCharacter()
    if not char then return false end
    local cframe = GetPosition(target)
    if not cframe then return false end
    if offset then
        cframe = cframe * CFrame.new(offset)
    end
    local goal = cframe.Position
    if Connections.ActiveTween then
        local previous = Connections.ActiveTween
        Connections.ActiveTween = nil
        Thread("Tween", nil, false)
        previous.Hum.PlatformStand = previous.WasPlatformStand
        task.spawn(previous.Caller, false)
    end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local wasPlatformStand = hum.PlatformStand
    local caller = coroutine.running()
    local state = {
        Caller = caller,
        Hum = hum,
        WasPlatformStand = wasPlatformStand,
    }
    Connections.ActiveTween = state
    hum.PlatformStand = true
    Thread("Tween", function()
        local reached = false
        while true do
            local _, delta = RunService.Stepped:Wait()
            local current = GetCharacter()
            if not current then break end
            for _, part in ipairs(current:GetDescendants()) do
                if part:IsA("BasePart") and part.CanCollide then
                    part.CanCollide = false
                end
            end
            local hrp = current.HumanoidRootPart
            hrp.AssemblyLinearVelocity = Vector3.zero
            local diff = goal - hrp.Position
            local dist = diff.Magnitude
            if arive and dist <= arive then
                reached = true
                break
            end
            local stepDist = speed * delta
            if dist <= stepDist then
                hrp.CFrame = cframe
                reached = true
                break
            end
            hrp.CFrame = hrp.CFrame + diff.Unit * stepDist
        end
        if Connections.ActiveTween == state then
            Connections.ActiveTween = nil
        end
        hum.PlatformStand = wasPlatformStand
        task.spawn(caller, reached)
    end, true)
    return coroutine.yield()
end
local function FuncTPW()
    while true do
        local delta = RunService.Heartbeat:Wait()
        local char = GetCharacter()
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if char and hum and hum.Health > 0 then
            if hum.MoveDirection.Magnitude > 0 then
                local speed = Options.TPWValue.Value
                char:TranslateBy(hum.MoveDirection * speed * delta * 10)
            end
        end
    end
end
local function FuncNoclip()
    while Toggles.Noclip.Value do
        RunService.Stepped:Wait()
        local char = GetCharacter()
        if char then
            for _, part in pairs(char:GetDescendants()) do
                if part:IsA("BasePart") and part.CanCollide then
                    part.CanCollide = false
                end
            end
        end
    end
end
local function Func_AntiKnockback()
    if type(Connections.Knockback) == "table" then
        for _, conn in pairs(Connections.Knockback) do
            if conn then conn:Disconnect() end
        end
        table.clear(Connections.Knockback)
    else
        Connections.Knockback = {}
    end
    local function ApplyAntiKB(character)
        if not character then return end
        local root = character:WaitForChild("HumanoidRootPart", 10)
        if root then
            local conn = root.ChildAdded:Connect(function(child)
                if not Toggles.AntiKnockback.Value then return end
                if child:IsA("BodyVelocity") and child.MaxForce == Vector3.new(40000, 40000, 40000) then
                    child:Destroy()
                end
            end)
            table.insert(Connections.Knockback, conn)
        end
    end
    if Plr.Character then
        ApplyAntiKB(Plr.Character)
    end
    local charAddedConn = Plr.CharacterAdded:Connect(function(newChar)
        ApplyAntiKB(newChar)
    end)
    table.insert(Connections.Knockback, charAddedConn)
    repeat task.wait(1) until not Toggles.AntiKnockback.Value
    for _, conn in pairs(Connections.Knockback) do
        if conn then conn:Disconnect() end
    end
    table.clear(Connections.Knockback)
end
local function Func_AutoReconnect()
    if Connections.Reconnect then Connections.Reconnect:Disconnect() end
    Connections.Reconnect = GuiService.ErrorMessageChanged:Connect(function()
        if not Toggles.AutoReconnect.Value then return end
        task.delay(2, function()
            pcall(function()
                local promptOverlay = game:GetService("CoreGui"):FindFirstChild("RobloxPromptGui")
                if promptOverlay then
                    local errorPrompt = promptOverlay.promptOverlay:FindFirstChild("ErrorPrompt")
                    if errorPrompt and errorPrompt.Visible then
                        local secondaryTimer = 5
                        task.wait(secondaryTimer)
                        TeleportService:Teleport(game.PlaceId, Plr)
                    end
                end
            end)
        end)
    end)
end
local function Func_NoGameplayPaused()
    while Toggles.NoGameplayPaused.Value do
        local success, err = pcall(function()
            local pauseGui = game:GetService("CoreGui").RobloxGui:FindFirstChild("CoreScripts/NetworkPause")
            if pauseGui then
                pauseGui:Destroy()
            end
        end)
        task.wait(1)
    end
end
local function ApplyFPSBoost(state)
    if not state then return end
    pcall(function()
        Lighting.GlobalShadows = false
        Lighting.FogEnd = 9e9
        Lighting.Brightness = 1
        for _, v in pairs(Lighting:GetChildren()) do
            if v:IsA("PostProcessEffect") or v:IsA("BloomEffect") or v:IsA("BlurEffect") or v:IsA("SunRaysEffect") then
                v.Enabled = false
            end
        end
        task.spawn(function()
            for i, v in pairs(workspace:GetDescendants()) do
                if Toggles.FPSBoost and not Toggles.FPSBoost.Value then break end
                pcall(function()
                    if v:IsA("BasePart") then
                        v.Material = Enum.Material.SmoothPlastic
                        v.CastShadow = false
                    elseif v:IsA("Decal") or v:IsA("Texture") then
                        v:Destroy()
                    elseif v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Beam") then
                        v.Enabled = false
                    end
                end)
                if i % 500 == 0 then task.wait() end
            end
        end)
    end)
end
function gsc(guiObject)
    if not guiObject then return false end
    local success = false
    pcall(function()
        if Services.GuiService and Services.VirtualInputManager then
            Services.GuiService.SelectedObject = guiObject
            task.wait(0.05)
            local keys = {Enum.KeyCode.Return, Enum.KeyCode.KeypadEnter, Enum.KeyCode.ButtonA}
            for _, key in ipairs(keys) do
                Services.VirtualInputManager:SendKeyEvent(true, key, false, game); task.wait(0.03)
                Services.VirtualInputManager:SendKeyEvent(false, key, false, game); task.wait(0.03)
            end
            Services.GuiService.SelectedObject = nil
            success = true
        end
    end)
    return success
end
local function FireCD(target)
    if not fireclickdetector then
        return
    end
    if not target or not target:IsA("ClickDetector") then
        return
    end
    fireclickdetector(target)
end
local function FirePP(target, teleport)
    if not fireproximityprompt then return end
    if not target or not target:IsA("ProximityPrompt") then return end
    if teleport then
        local char = GetCharacter()
        local hrp = char and GetObject(char, "HumanoidRootPart")
        local part = target.Parent
        local isModel = false
        if part then
            if part:IsA("Model") then
                isModel = true
            elseif not part:IsA("BasePart") then
                part = target:FindFirstAncestorWhichIsA("BasePart")
                if not part then
                    part = target:FindFirstAncestorWhichIsA("Model")
                    if part then
                        isModel = true
                    end
                end
            end
        end
        if hrp and part then
            local pos = isModel and part:GetPivot().Position or part.Position
            if (hrp.Position - pos).Magnitude > target.MaxActivationDistance then
                TPTo(part)
                task.wait(0.2)
            end
        end
    end
    fireproximityprompt(target)
end
local function FireTI(target)
    if not firetouchinterest then
        return
    end
    local root = Plr.Character and Plr.Character:FindFirstChild("HumanoidRootPart")
    if not root then
        return
    end
    local part
    if target:IsA("BasePart") then
        part = target
    else
        part = target:FindFirstAncestorWhichIsA("BasePart")
    end
    if not part then
        return
    end
    task.spawn(function()
        firetouchinterest(part, root, true)
        task.wait()
        firetouchinterest(part, root, false)
    end)
end
local function Serverhop()
    local hopSuccess, hopErr = pcall(function()
        local baseUrl = 'https://games.roblox.com/v1/games/' .. game.PlaceId .. '/servers/Public?sortOrder=Asc&limit=100'
        local servers = {}
        local cursor = ''
        for _ = 1, 3 do
            local url = baseUrl
            if cursor ~= '' then url = url .. '&cursor=' .. cursor end
            local pages = game:HttpGet(url)
            local data = HttpService:JSONDecode(pages)
            for _, server in ipairs(data.data) do
                if server.playing < server.maxPlayers and server.id ~= game.JobId then
                    table.insert(servers, server)
                end
            end
            cursor = data.nextPageCursor
            if not cursor or cursor == '' then break end
        end
        table.sort(servers, function(a, b) return a.playing < b.playing end)
        if #servers == 0 then
            Library:Notify("No servers found to hop to.", 3)
            return
        end
        local best = servers[1]
        for _, server in ipairs(servers) do
            if server.playing > 0 then
                best = server
                break
            end
        end
        TeleportService:TeleportToPlaceInstance(game.PlaceId, best.id, Plr)
    end)
    if not hopSuccess then
        Library:Notify("Serverhop failed: " .. tostring(hopErr), 5)
    end
end
local Window = Library:CreateWindow({
        Title = "Yuri",
        Center = true,
        AutoShow = true,
        Resizable = true,
        ShowCustomCursor = false,
        UnlockMouseWhileOpen = false,
        NotifySide = "Left",
        TabPadding = 8,
        MenuFadeTime = 0.2
})
AddInfo(Window)
local Tabs = {
        Main = Window:AddTab("Main"),
    Player = Window:AddTab("Player"),
    Config = Window:AddTab("Config"),
}
local TB = {
    Main = {
        Left = {
            Autofarm = Tabs.Main:AddLeftTabbox(),
        },
        Right = {
            Autofarm = Tabs.Main:AddRightTabbox(),
        },
    },
}
local TB_Tabs = {
    Autofarm = {
        T1 = TB.Main.Left.Autofarm:AddTab("Autofarm"),
    },
    Autofarm2 = {
        T1 = TB.Main.Right.Autofarm:AddTab("Config"),
    },
}
local GB = {
    Player = {
        Left = {
            General = Tabs.Player:AddLeftGroupbox("General"),
            Server  = Tabs.Player:AddLeftGroupbox("Server"),
        },
        Right = {
            Game = Tabs.Player:AddRightGroupbox("Game"),
        },
    },
}
AddSliderToggle({ Group = GB.Player.Left.General, Id = "WS", Text = "WalkSpeed", Default = 16, Min = 16, Max = 1000 })
AddSliderToggle({ Group = GB.Player.Left.General, Id = "TPW", Text = "TPWalk", Default = 1, Min = 1, Max = 30, Rounding = 1 })
AddSliderToggle({ Group = GB.Player.Left.General, Id = "JP", Text = "JumpPower", Default = 50, Min = 0, Max = 500 })
AddSliderToggle({ Group = GB.Player.Left.General, Id = "HH", Text = "HipHeight", Default = 2, Min = 0, Max = 10, Rounding = 1 })
GB.Player.Left.General:AddToggle("Noclip", { Text = "Noclip" })
GB.Player.Left.General:AddToggle("AntiKnockback", {
    Text = "Anti Knockback",
    Default = false,
})
GB.Player.Left.General:AddToggle("Disable3DRender", { Text = "Disable 3D Rendering" })
AddSliderToggle({ Group = GB.Player.Left.General, Id = "Grav", Text = "Gravity", Default = 196, Min = 0, Max = 500, Rounding = 1})
AddSliderToggle({ Group = GB.Player.Left.General, Id = "Zoom", Text = "Camera Zoom", Default = 128, Min = 128, Max = 10000 })
AddSliderToggle({ Group = GB.Player.Left.General, Id = "FOV", Text = "Field of View", Default = 70, Min = 30, Max = 120 })
AddSliderToggle({ Group = GB.Player.Left.General, Id = "LimitFPS", Text = "Set Max FPS", Disabled = not Support.FPS, Default = 60, Min = 5, Max = 360 })
GB.Player.Left.General:AddToggle("FPSBoost", { Text = "FPS Boost" })
GB.Player.Left.Server:AddToggle("AntiAFK", {
    Text = "Anti AFK",
    Default = true,
    Disabled = not Support.Connections,
})
GB.Player.Left.Server:AddToggle("AutoJump", { Text = "Auto Jump" })
Toggles.AutoJump:OnChanged(function(state)
    Thread("AutoJump", function()
        while Toggles.AutoJump.Value do
            local hum = Plr.Character and Plr.Character:FindFirstChildWhichIsA("Humanoid")
            if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
            Services.VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.W, false, game)
            task.wait(0.3)
            Services.VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.W, false, game)
            task.wait(5)
        end
    end, state)
end)
GB.Player.Left.Server:AddToggle("AutoReconnect", { Text = "Auto Reconnect" })
GB.Player.Left.Server:AddToggle("NoGameplayPaused", { Text = "No Gameplay Paused"})
GB.Player.Left.Server:AddButton({ Text = "Serverhop", Func = function() Serverhop() end })
GB.Player.Left.Server:AddButton({ Text = "Rejoin", Func = function() Services.TeleportService:Teleport(game.PlaceId, Plr) end })
AddSliderToggle({ Group = GB.Player.Left.Server, Id = "AutoServerhop", Text = "Auto Serverhop (Minutes)", Default = 30, Min = 0, Max = 300 }, function(state)
    Thread("AutoServerhop", function()
        local lastHop = tick()
        while Toggles.AutoServerhop.Value do
            task.wait(5)
            if not Toggles.AutoServerhop.Value then break end
            if (tick() - lastHop) >= (Options.AutoServerhopValue.Value * 60) then
                Serverhop()
                break
            end
        end
    end, state)
end)
AddSliderToggle({ Group = GB.Player.Left.Server, Id = "AutoRejoin", Text = "Auto Rejoin (Minutes)", Default = 30, Min = 0, Max = 300 }, function(state)
    Thread("AutoRejoin", function()
        local lastRejoin = tick()
        while Toggles.AutoRejoin.Value do
            task.wait(5)
            if not Toggles.AutoRejoin.Value then break end
            if (tick() - lastRejoin) >= (Options.AutoRejoinValue.Value * 60) then
                TeleportService:Teleport(game.PlaceId, Plr)
                break
            end
        end
    end, state)
end)
GB.Player.Right.Game:AddToggle("InstantPP", { Text = "Instant Prompt" })
GB.Player.Right.Game:AddToggle("Fullbright", { Text = "Fullbright" })
GB.Player.Right.Game:AddToggle("NoFog", { Text = "No Fog" })
AddSliderToggle({ Group = GB.Player.Right.Game, Id = "OverrideTime", Text = "Time Of Day", Default = 12, Min = 0, Max = 24, Rounding = 1 })
Toggles.AntiKnockback:OnChanged(function(state)
    Thread("AntiKnockback", Func_AntiKnockback, state)
end)
Toggles.TPW:OnChanged(function(v)
    Thread("TPW", FuncTPW, v)
end)
Toggles.Noclip:OnChanged(function(v)
    Thread("Noclip", FuncNoclip, v)
end)
Connections.Player_General = RunService.Stepped:Connect(function()
    local Hum = Plr.Character and Plr.Character:FindFirstChildOfClass("Humanoid")
    if Hum then
        if Toggles.WS.Value then Hum.WalkSpeed = Options.WSValue.Value end
        if Toggles.JP.Value then Hum.JumpPower = Options.JPValue.Value Hum.UseJumpPower = true end
        if Toggles.HH.Value then Hum.HipHeight = Options.HHValue.Value end
    end
    workspace.Gravity = Toggles.Grav.Value and Options.GravValue.Value or 192
    if Toggles.FOV.Value then workspace.CurrentCamera.FieldOfView = Options.FOVValue.Value end
    if Toggles.Zoom.Value then Plr.CameraMaxZoomDistance = Options.ZoomValue.Value end
end)
task.spawn(function()
    while task.wait() do
        if Toggles.Fullbright.Value then
            Lighting.Brightness = 2
            Lighting.ClockTime = 14
            Lighting.GlobalShadows = false
        elseif Toggles.OverrideTime.Value then
            Lighting.ClockTime = Options.OverrideTimeValue.Value
        end
        if Toggles.NoFog.Value then Lighting.FogEnd = 9e9 end
        if Library.Unloaded then break end
    end
end)
Options.LimitFPSValue:OnChanged(function()
    if Toggles.LimitFPS.Value then
        setfpscap(Options.LimitFPSValue.Value)
    end
end)
Toggles.LimitFPS:OnChanged(function(v)
    if not v and Support.FPS then
        setfpscap(2000)
    end
end)
Toggles.Disable3DRender:OnChanged(function(v) RunService:Set3dRenderingEnabled(not v) end)
Toggles.FPSBoost:OnChanged(function(state)
    ApplyFPSBoost(state)
end)
Toggles.AutoReconnect:OnChanged(function(state)
    if state then Func_AutoReconnect() end
end)
Toggles.NoGameplayPaused:OnChanged(function(state)
    Thread("NoGameplayPaused", SafeLoop("Anti-Pause", Func_NoGameplayPaused), state)
end)
game:GetService("ProximityPromptService").PromptButtonHoldBegan:Connect(function(prompt)
    if Toggles.InstantPP and Toggles.InstantPP.Value then
        prompt.HoldDuration = 0
    end
end)
local antiAFKConn = nil
local function RunAntiAFK()
    if antiAFKConn then antiAFKConn:Enable() return end
    local GC = getconnections or get_signal_cons
    if GC then
        local conns = GC(Players.LocalPlayer.Idled)
        local target = conns and conns[1]
        if target and target.Disable then
            target:Disable()
            antiAFKConn = target
            return
        end
        for _, c in pairs(conns or {}) do
            if c.Disable then
                c:Disable()
                antiAFKConn = c
                return
            elseif c.Disconnect then
                c:Disconnect()
                return
            end
        end
    end
    Players.LocalPlayer.Idled:Connect(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end
Toggles.AntiAFK:OnChanged(function(state)
    if state then
        RunAntiAFK()
    elseif antiAFKConn and antiAFKConn.Enable then
        antiAFKConn:Enable()
    end
end)
if Toggles.AntiAFK.Value then RunAntiAFK() end
local MFolder = RS:FindFirstChild("Meeting") or RS:WaitForChild("Meeting", 15)
local RFolder = MFolder and MFolder:FindFirstChild("Remotes")
for _, Name in ipairs({ "GetState", "StateUpdated", "SubmitEmail", "SetLaptopView", "JoinMeeting", "DismissScam", "SmackLaptop", "InterruptAction", "UseRelaxItem", "ThrowPaper", "OfficeEvent", "OfficeEventAction", "BossQuiz", "BossQuizAnswer", "HackAction", "HackUpdate", "BuyUpgrade", "ClaimPlaytime", "AlienAction", "HwAction", "VerityAction", "VerityCue", "LaptopFightAction", "LaptopFightCue" }) do
    Remotes[Name] = RFolder and RFolder:FindFirstChild(Name)
end
Shared.ME = {}
Shared.Seen = { Ads = {}, Quiz = {}, Claimed = {}, Upgraded = {} }
Shared.HackGen = 0
Shared.HackAt = 0
Shared.HackViewAt = 0
Shared.HackUntil = 0
Shared.SubmitAt = 0
Shared.Slack = 0
Shared.SmackAt = 0
Shared.RelaxAt = 0
Shared.RollCall = nil
Shared.Printer = nil
Shared.Dance = nil
Shared.DanceMe = false
Shared.Vty = { Path = nil, NextAt = 0 }
Shared.LF = { Active = false, EndsAt = 0, SwingAt = 0 }
Shared.War = { Fire = 0, Warn = nil, HwFire = 0, HwWarn = nil, HwQte = nil }
Shared.Compliments = {
    ["You, sir!"] = true,
    ["Obviously, sir!"] = true,
    ["10/10, stunning!"] = true,
    ["You do, boss!"] = true,
    ["Perfect as always!"] = true,
    ["You, the legend!"] = true,
    ["Best one ever!"] = true,
    ["A total genius!"] = true,
    ["You are, sir!"] = true,
    ["You should be KING!"] = true,
    ["They're amazing!"] = true,
    ["¡Usted, señor!"] = true,
    ["¡Obviamente, señor!"] = true,
    ["¡10/10, preciosa!"] = true,
    ["¡Usted, jefe!"] = true,
    ["¡Perfecto como siempre!"] = true,
    ["¡Usted, la leyenda!"] = true,
    ["¡La mejor de todas!"] = true,
    ["¡Un genio total!"] = true,
    ["¡Debería ser REY!"] = true,
    ["¡Son increíbles!"] = true,
}

local function Func_AutoJoin()
    while Toggles.AutoJoin.Value do
        local ok, err = pcall(function()
            if Remotes.JoinMeeting and MFolder and Plr:GetAttribute("MeetingJoined") ~= true and Plr:GetAttribute("ReturnToMenu") ~= true and Plr:GetAttribute("DayOffIn") ~= true and MFolder:GetAttribute("DayOff") ~= true then
                local Phase = MFolder:GetAttribute("RoundPhase")
                if Phase == "Countdown" or MFolder:GetAttribute("RoundActive") == true then
                    Remotes.JoinMeeting:FireServer()
                end
            end
        end)
        if not ok then notyuri("AutoJoin", err) end
        task.wait(2)
    end
end

local function Func_AutoWork()
    while Toggles.AutoWork.Value do
        local ok, err = pcall(function()
            local S = Shared.ME
            local R = S.AnswerResult
            if type(R) == "table" and R.Id ~= Shared.Seen.Result then
                Shared.Seen.Result = R.Id
                if R.Correct == false then
                    Library:Notify("Wrong answer, expected " .. tostring(R.Right), 4)
                end
            end
            local Event = MFolder and MFolder:GetAttribute("OfficeEvent")
            local Blocked = Plr:GetAttribute("DayOffIn") == true or Event == "PlayerPresentation" or Event == "LaptopFight" or Event == "DayOff"
            if S.Ready and S.Email and not S.Recovering and not S.LaptopBroken and not Blocked then
                if S.LaptopView ~= true and os.clock() - Shared.Slack > 0.3 then
                    Shared.Slack = os.clock()
                    Remotes.SetLaptopView:FireServer(true)
                    return
                end
                if os.clock() - Shared.SubmitAt < 0.8 then return end
                local E = S.Email
                local Choice = nil
                if E.IsScam then
                    Choice = "DELETE"
                elseif E.Kind == "WRITE" then
                    Choice = "WRITE"
                else
                    for Word in string.gmatch(string.lower(tostring(E.Text or "")), "[%a\128-\255]+") do
                        if Word:sub(1, 6) == "approv" or Word:sub(1, 5) == "aprob" or Word:sub(1, 6) == "aprueb" or Word:sub(1, 4) == "apru" then
                            Choice = "APPROVE"
                            break
                        end
                        if Word:sub(1, 7) == "forward" or Word:sub(1, 5) == "reenv" then
                            Choice = "FORWARD"
                            break
                        end
                    end
                end
                if Choice then
                    Shared.SubmitAt = os.clock()
                    Remotes.SubmitEmail:FireServer(E.Token, Choice)
                elseif Shared.SkipToken ~= E.Token then
                    Shared.SkipToken = E.Token
                    Library:Notify("Unrecognized email, skipping: " .. tostring(E.Subject), 5)
                end
            elseif S.LaptopView == true and not S.Email and os.clock() - Shared.HackViewAt > 4 then
                Remotes.SetLaptopView:FireServer(false)
            end
        end)
        if not ok then notyuri("AutoWork", err) end
        task.wait(0.25)
    end
end

local function Func_AutoSmack()
    while Toggles.AutoSmack.Value do
        local ok, err = pcall(function()
            local S = Shared.ME
            if S.LaptopBroken and (S.SmacksLeft or 0) > 0 and os.clock() - Shared.SmackAt > 0.25 then
                Shared.SmackAt = os.clock()
                Remotes.SmackLaptop:FireServer()
            end
        end)
        if not ok then notyuri("AutoSmack", err) end
        task.wait(0.1)
    end
end

local function Func_AutoAds()
    while Toggles.AutoAds.Value do
        local ok, err = pcall(function()
            local Ads = Shared.ME.ScamAds
            if type(Ads) == "table" then
                for _, Ad in ipairs(Ads) do
                    if type(Ad) == "table" and Ad.Id and not Shared.Seen.Ads[Ad.Id] then
                        Shared.Seen.Ads[Ad.Id] = true
                        Remotes.DismissScam:FireServer(Ad.Id)
                        task.wait(0.2)
                    end
                end
            end
        end)
        if not ok then notyuri("AutoAds", err) end
        task.wait(0.25)
    end
end

local function Func_AutoInterrupt()
    while Toggles.AutoInterrupt.Value do
        local ok, err = pcall(function()
            local I = Shared.ME.Interrupt
            if type(I) == "table" and I.Id then
                if I.Id ~= Shared.Seen.Interrupt then
                    Shared.Seen.Interrupt = I.Id
                    if I.Kind == "Call" then
                        Remotes.InterruptAction:FireServer(I.Id, "decline")
                        return
                    end
                end
                if I.Kind == "Update" then
                    Remotes.InterruptAction:FireServer(I.Id, "click")
                    task.wait(0.1)
                end
            end
        end)
        if not ok then notyuri("AutoInterrupt", err) end
        task.wait(0.1)
    end
end

local function Func_AutoEvents()
    while Toggles.AutoEvents.Value do
        local ok, err = pcall(function()
            local RC = Shared.RollCall
            if RC and RC.Id and not RC.Done then
                RC.Done = true
                Remotes.OfficeEventAction:FireServer("here", RC.Id)
            end
            local P = Shared.Printer
            if P and P.Id and P.Count < P.Need then
                local T = workspace:GetServerTimeNow()
                if P.StartsAt <= T and T <= P.EndsAt then
                    P.Count = P.Count + 1
                    Remotes.OfficeEventAction:FireServer("kick", P.Id)
                    task.wait(0.05)
                end
            end
            local D = Shared.Dance
            if D and D.Id and Shared.DanceMe and D.Count < D.Need then
                local T = workspace:GetServerTimeNow()
                if D.StartsAt - 0.15 <= T and T <= D.EndsAt then
                    D.Count = D.Count + 1
                    Remotes.OfficeEventAction:FireServer("dance", D.Id)
                    task.wait(0.15)
                end
            end
        end)
        if not ok then notyuri("AutoEvents", err) end
        task.wait(0.05)
    end
end

local function Func_AutoHack()
    while Toggles.AutoHack.Value do
        local ok, err = pcall(function()
            if not Remotes.HackAction then return end
            local Boss = workspace:FindFirstChild("Boss")
            if Boss and Boss:GetAttribute("BossState") == "BEHIND_PLAYER" and Boss:GetAttribute("WatchedUserId") == Plr.UserId then return end
            if (Plr:GetAttribute("HackReadyAt") or 0) > workspace:GetServerTimeNow() then return end
            if MFolder then
                local Ends = MFolder:GetAttribute("RoundEndsAt")
                if Ends ~= nil and MFolder:GetAttribute("DayOff") ~= true and Ends - 60 <= workspace:GetServerTimeNow() then return end
            end
            if workspace:GetServerTimeNow() < Shared.HackUntil + 0.5 then return end
            if os.clock() - Shared.HackAt < 3 then return end
            Shared.HackAt = os.clock()
            if Shared.ME.LaptopView ~= true then
                Shared.HackViewAt = os.clock()
                Remotes.SetLaptopView:FireServer(true)
            else
                Remotes.HackAction:FireServer("start")
            end
        end)
        if not ok then notyuri("AutoHack", err) end
        task.wait(0.5)
    end
end

local function Func_AutoPaper()
    while Toggles.AutoPaper.Value do
        local ok, err = pcall(function()
            if not Remotes.ThrowPaper then return end
            if Plr:GetAttribute("MeetingJoined") ~= true or Plr:GetAttribute("LaptopView") == true or Plr:GetAttribute("EventLock") == true then return end
            local T = workspace:GetServerTimeNow()
            local War = false
            local Window = false
            if MFolder then
                if MFolder:GetAttribute("OfficeEvent") == "PaperFight" then
                    War = true
                    Window = (MFolder:GetAttribute("PaperFightStartsAt") or math.huge) <= T and T < (MFolder:GetAttribute("PaperFightEndsAt") or 0)
                end
                if not Window and MFolder:GetAttribute("RoundPhase") == "Countdown" then
                    Window = 5 < (MFolder:GetAttribute("CountdownEndsAt") or 0) - T
                end
            end
            if not Window then return end
            if War and Plr:GetAttribute("SeatName") == nil then return end
            local Char = GetCharacter()
            local Hum = Char and Char:FindFirstChildOfClass("Humanoid")
            local Held = Char and Char:FindFirstChildOfClass("Tool")
            if not (Held and Held:GetAttribute("MeetingPaper") == true) then
                local Pack = Plr:FindFirstChild("Backpack")
                for _, Tool in ipairs(Pack and Pack:GetChildren() or {}) do
                    if Tool:IsA("Tool") and Tool:GetAttribute("MeetingPaper") == true and Hum then
                        Hum:EquipTool(Tool)
                        break
                    end
                end
                return
            end
            local Root = Char:FindFirstChild("HumanoidRootPart")
            if not Root then return end
            local MyTeam = War and Plr:GetAttribute("WarTeam") or nil
            local Best, BestDist = nil, 90
            for _, P in ipairs(Players:GetPlayers()) do
                if P ~= Players.LocalPlayer and P:GetAttribute("SeatName") and P:GetAttribute("MeetingJoined") == true and (MyTeam == nil or (P:GetAttribute("WarTeam") ~= nil and P:GetAttribute("WarTeam") ~= MyTeam)) then
                    local Head = P.Character and P.Character:FindFirstChild("Head")
                    if Head then
                        local Dist = (Head.Position - Root.Position).Magnitude
                        if Dist < BestDist then
                            Best, BestDist = P, Dist
                        end
                    end
                end
            end
            for _, M in ipairs(workspace:GetChildren()) do
                if M:GetAttribute("MeetingDummy") and (MyTeam == nil or (M:GetAttribute("WarTeam") ~= nil and M:GetAttribute("WarTeam") ~= MyTeam)) then
                    local Head = M:FindFirstChild("Head")
                    if Head then
                        local Dist = (Head.Position - Root.Position).Magnitude
                        if Dist < BestDist then
                            Best, BestDist = M, Dist
                        end
                    end
                end
            end
            if Best then
                Remotes.ThrowPaper:FireServer(Best)
            end
        end)
        if not ok then notyuri("AutoPaper", err) end
        task.wait(0.3)
    end
end

local function Func_AutoRelax()
    while Toggles.AutoRelax.Value do
        local ok, err = pcall(function()
            if (Shared.ME.Pressure or 0) < Options.RelaxAt.Value then return end
            if os.clock() - Shared.RelaxAt < 7 then return end
            local Boss = workspace:FindFirstChild("Boss")
            local State = Boss and Boss:GetAttribute("BossState")
            if not (Boss == nil or State == "LEAVING" or (State == "BEHIND_PLAYER" and Boss:GetAttribute("WatchedUserId") ~= Plr.UserId)) then return end
            local Char = Plr.Character
            local Held = Char and Char:FindFirstChildOfClass("Tool")
            if Held and Held:GetAttribute("MeetingRelaxItem") == "ButterSquishy" then
                Shared.RelaxAt = os.clock()
                Remotes.UseRelaxItem:FireServer(Held)
            else
                local Hum = Char and Char:FindFirstChildOfClass("Humanoid")
                local Pack = Plr:FindFirstChild("Backpack")
                for _, Tool in ipairs(Pack and Pack:GetChildren() or {}) do
                    if Tool:IsA("Tool") and Tool:GetAttribute("MeetingRelaxItem") == "ButterSquishy" and Hum then
                        Hum:EquipTool(Tool)
                        break
                    end
                end
            end
        end)
        if not ok then notyuri("AutoRelax", err) end
        task.wait(1)
    end
end

local function Func_AutoClaim()
    while Toggles.AutoClaim.Value do
        local ok, err = pcall(function()
            local Cfg = GetSafeModule(MFolder, "CareerConfig")
            local Start = Plr:GetAttribute("PlaytimeStart")
            if not (Cfg and Remotes.ClaimPlaytime and Start and Plr:GetAttribute("EconomyReady")) then return end
            local Elapsed = workspace:GetServerTimeNow() - Start
            local Claimed = Plr:GetAttribute("PlaytimeClaimed") or 0
            for K, Tier in ipairs(Cfg.Playtime) do
                if Elapsed >= Tier.Minutes * 60 and math.floor(Claimed / 2 ^ (K - 1)) % 2 ~= 1 and not Shared.Seen.Claimed[K] then
                    Shared.Seen.Claimed[K] = true
                    Remotes.ClaimPlaytime:FireServer(K)
                end
            end
        end)
        if not ok then notyuri("AutoClaim", err) end
        task.wait(5)
    end
end

local function Func_AutoUpgrade()
    while Toggles.AutoUpgrade.Value do
        local ok, err = pcall(function()
            local Cfg = GetSafeModule(MFolder, "CareerConfig")
            if not (Cfg and Remotes.BuyUpgrade) then return end
            local Rank = Plr:GetAttribute("Rank") or Cfg.RankIndex(Plr:GetAttribute("Exp") or 0)
            local Bobux = Plr:GetAttribute("Bobux") or 0
            local Best = nil
            for _, Track in ipairs({ { "Paper", Cfg.PaperUpgrades, "PaperLevel" }, { "Phone", Cfg.PhoneUpgrades, "PhoneLevel" } }) do
                local Next = Track[2][(Plr:GetAttribute(Track[3]) or 0) + 1]
                if Next and Bobux >= Next.Price and (not Next.Rank or Next.Rank <= Rank) and not Shared.Seen.Upgraded[Track[1] .. (Plr:GetAttribute(Track[3]) or 0)] then
                    if not Best or Next.Price < Best[2].Price then
                        Best = { Track[1], Next, Track[1] .. (Plr:GetAttribute(Track[3]) or 0) }
                    end
                end
            end
            if Best then
                Shared.Seen.Upgraded[Best[3]] = true
                Remotes.BuyUpgrade:FireServer(Best[1])
            end
        end)
        if not ok then notyuri("AutoUpgrade", err) end
        task.wait(5)
    end
end

local function Func_AutoAlien()
    while Toggles.AutoAlien.Value do
        local ok, err = pcall(function()
            if not (Remotes.AlienAction and MFolder) then return end
            local Phase = MFolder:GetAttribute("AlienPhase")
            if Phase ~= "Fight" and Phase ~= "Finale" then return end
            local Cfg = GetSafeModule(MFolder, "AlienConfig")
            local T = workspace:GetServerTimeNow()
            local Dodge = MFolder:GetAttribute("AlienDodgeAt")
            if not (Dodge and T - Dodge < (Cfg and Cfg.DodgeSeconds or 2.4)) and T >= (MFolder:GetAttribute("AlienZappedUntil") or 0) then
                if os.clock() - Shared.War.Fire >= (Cfg and Cfg.FireInterval or 0.085) then
                    Shared.War.Fire = os.clock()
                    Remotes.AlienAction:FireServer("fire")
                end
            end
            local Warn = MFolder:GetAttribute("AlienWarnId")
            if Warn ~= nil and Warn ~= Shared.War.Warn then
                Shared.War.Warn = Warn
                Remotes.AlienAction:FireServer("shield")
            end
        end)
        if not ok then notyuri("AutoAlien", err) end
        task.wait(0.05)
    end
end

local function Func_AutoHalloween()
    while Toggles.AutoHalloween.Value do
        local ok, err = pcall(function()
            if not (Remotes.HwAction and MFolder) then return end
            local Phase = MFolder:GetAttribute("HwPhase")
            if Phase ~= "Fight" and Phase ~= "Finale" and Phase ~= "Climax" then return end
            local Cfg = GetSafeModule(MFolder, "HalloweenConfig")
            local T = workspace:GetServerTimeNow()
            if Phase ~= "Climax" then
                local Dodge = MFolder:GetAttribute("HwDodgeAt")
                if not (Dodge and T - Dodge < (Cfg and Cfg.DodgeSeconds or 2.4)) and T >= (MFolder:GetAttribute("HwZappedUntil") or 0) then
                    if os.clock() - Shared.War.HwFire >= (Cfg and Cfg.FireInterval or 0.085) then
                        Shared.War.HwFire = os.clock()
                        Remotes.HwAction:FireServer("fire")
                    end
                end
            else
                local QKind = MFolder:GetAttribute("HwQteKind")
                local QAt = MFolder:GetAttribute("HwQteAt")
                local QEnd = MFolder:GetAttribute("HwQteEnd")
                if QKind and QAt and QEnd and QAt - 0.05 <= T and T <= QEnd then
                    if QKind == "Mash" then
                        if os.clock() - Shared.War.HwFire >= (Cfg and Cfg.FireInterval or 0.085) then
                            Shared.War.HwFire = os.clock()
                            Remotes.HwAction:FireServer("fire")
                        end
                    elseif QKind == "Dodge" and MFolder:GetAttribute("HwQteId") ~= Shared.War.HwQte then
                        Shared.War.HwQte = MFolder:GetAttribute("HwQteId")
                        Remotes.HwAction:FireServer("shield")
                    end
                end
            end
            local Warn = MFolder:GetAttribute("HwWarnId")
            if Warn ~= nil and Warn ~= Shared.War.HwWarn then
                Shared.War.HwWarn = Warn
                Remotes.HwAction:FireServer("shield")
            end
        end)
        if not ok then notyuri("AutoHalloween", err) end
        task.wait(0.05)
    end
end

local function Func_AutoVerity()
    while Toggles.AutoVerity.Value do
        local ok, err = pcall(function()
            local Path = Shared.Vty.Path
            if not (Path and Remotes.VerityAction) then return end
            if Plr:GetAttribute("MeetingJoined") ~= true or Plr:GetAttribute("ReturnToMenu") == true then return end
            if os.clock() < Shared.Vty.NextAt then return end
            local Cfg = GetSafeModule(MFolder, "VerityConfig")
            if not Cfg then return end
            local Char = GetCharacter()
            local Head = Char and Char:FindFirstChild("Head")
            if not Head then return end
            Shared.Vty.NextAt = os.clock() + Cfg.ThrowRate
            local T = workspace:GetServerTimeNow()
            local Origin = Head.Position + Vector3.new(0, 0.2, 0)
            local Cur = Path:Pos(T)
            local Eta = (Cur - Origin).Magnitude / Cfg.BallSpeed
            local Aim = Path:Pos(T + Eta) + Vector3.new(0, Eta * Eta * 6, 0)
            Remotes.VerityAction:FireServer("throw", Origin, (Aim - Origin).Unit)
        end)
        if not ok then notyuri("AutoVerity", err) end
        task.wait(0.1)
    end
end

local function Func_AutoLaptopFight()
    while Toggles.AutoLaptopFight.Value do
        local ok, err = pcall(function()
            if not (Shared.LF.Active and Remotes.LaptopFightAction) then return end
            local T = workspace:GetServerTimeNow()
            if T > Shared.LF.EndsAt then return end
            local Char = GetCharacter()
            if not (Char and Char:FindFirstChild("FightLaptop")) then return end
            if os.clock() - Shared.LF.SwingAt < 0.55 then return end
            Shared.LF.SwingAt = os.clock()
            Remotes.LaptopFightAction:FireServer("swing")
            task.wait(0.16)
            local Root = Char:FindFirstChild("HumanoidRootPart")
            local Cfg = GetSafeModule(MFolder, "LaptopFightConfig")
            if not (Root and Cfg) then return end
            local Look = Root.CFrame.LookVector
            local Flat = Vector3.new(Look.X, 0, Look.Z)
            local Fwd = Root.Position + (0.1 < Flat.Magnitude and Flat.Unit or Vector3.new(0, 0, -1)) * Cfg.HitboxForward
            local Found = {}
            local function Check(Model)
                local Part = Model and Model:FindFirstChild("HumanoidRootPart")
                if not (Part and Model ~= Char) then return end
                if Cfg.HitboxHeight < math.abs(Part.Position.Y - Root.Position.Y) then return end
                local A = Vector3.new(Part.Position.X - Fwd.X, 0, Part.Position.Z - Fwd.Z).Magnitude
                local B = Vector3.new(Part.Position.X - Root.Position.X, 0, Part.Position.Z - Root.Position.Z).Magnitude
                if A <= Cfg.HitboxRadius + 1 or B <= 2.2 then
                    table.insert(Found, { Model, B })
                end
            end
            for _, P in ipairs(Players:GetPlayers()) do
                if P ~= Players.LocalPlayer and P:GetAttribute("LaptopFighter") == true then
                    Check(P.Character)
                end
            end
            local Dummies = workspace:FindFirstChild("LaptopFightDummies")
            if Dummies then
                for _, M in ipairs(Dummies:GetChildren()) do
                    Check(M)
                end
            end
            table.sort(Found, function(A, B) return A[2] < B[2] end)
            local Hits = {}
            for I = 1, math.min(#Found, 4) do
                Hits[I] = Found[I][1]
            end
            if #Hits > 0 then
                Remotes.LaptopFightAction:FireServer("hit", Hits)
            end
        end)
        if not ok then notyuri("AutoLaptopFight", err) end
        task.wait(0.1)
    end
end

do
    SafeConnect("StateUpdated", function()
        return Remotes.StateUpdated and Remotes.StateUpdated.OnClientEvent
    end, function(S)
        if type(S) == "table" then
            Shared.ME = S
        end
    end)
    SafeConnect("OfficeEvent", function()
        return Remotes.OfficeEvent and Remotes.OfficeEvent.OnClientEvent
    end, function(Kind, Data)
        Data = type(Data) == "table" and Data or {}
        if Kind == "RollCallAsk" then
            Shared.RollCall = { Id = Data.Id, Done = false }
        elseif Kind == "PrinterKick" then
            Shared.Printer = { Id = Data.Id, StartsAt = Data.StartsAt or workspace:GetServerTimeNow(), EndsAt = Data.EndsAt or 0, Need = Data.Need or 16, Count = 0 }
        elseif Kind == "DanceStart" then
            Shared.Dance = { Id = Data.Id, StartsAt = Data.StartsAt or workspace:GetServerTimeNow(), EndsAt = Data.EndsAt or 0, Need = Data.Need or 34, Count = 0 }
        elseif Kind == "DancePicked" then
            Shared.DanceMe = Data.UserId == Plr.UserId
        elseif Kind == "RollCallResult" or Kind == "CalledOut" then
            Shared.RollCall = nil
        elseif Kind == "DanceResult" then
            Shared.Dance = nil
            Shared.DanceMe = false
        elseif Kind == "EventEnd" then
            Shared.RollCall = nil
            Shared.Printer = nil
            Shared.Dance = nil
            Shared.DanceMe = false
        end
    end)
    SafeConnect("BossQuiz", function()
        return Remotes.BossQuiz and Remotes.BossQuiz.OnClientEvent
    end, function(Q)
        if not (Toggles.AutoQuiz and Toggles.AutoQuiz.Value) then return end
        if type(Q) ~= "table" or Q.Result or Shared.Seen.Quiz[Q.Id] then return end
        if type(Q.Options) ~= "table" then return end
        for I, Opt in ipairs(Q.Options) do
            if Shared.Compliments[Opt] then
                Shared.Seen.Quiz[Q.Id] = true
                local Wait = math.max(0, (Q.ReadyAt or workspace:GetServerTimeNow()) - workspace:GetServerTimeNow()) + 0.75
                task.delay(Wait, function()
                    if Toggles.AutoQuiz.Value and workspace:GetServerTimeNow() < (Q.EndsAt or 0) then
                        Remotes.BossQuizAnswer:FireServer(Q.Id, I)
                    end
                end)
                return
            end
        end
    end)
    SafeConnect("HackUpdate", function()
        return Remotes.HackUpdate and Remotes.HackUpdate.OnClientEvent
    end, function(U)
        if type(U) ~= "table" then return end
        if type(U.RoundEnd) == "number" then
            Shared.HackUntil = U.RoundEnd
        end
        if U.State == "active" and not U.Local and type(U.Chart) == "table" and U.RoundStart and Remotes.HackAction then
            Shared.HackGen = Shared.HackGen + 1
            local Gen = Shared.HackGen
            local Id, Round, Start, Notes = U.Id, U.Round, U.RoundStart, U.Chart.notes or {}
            Thread("HackTaps", nil, false)
            Thread("HackTaps", SafeLoop("HackTaps", function()
                for _, Note in ipairs(Notes) do
                    if Shared.HackGen ~= Gen then return end
                    local Delay = Start + Note.t - workspace:GetServerTimeNow() - 0.06
                    if Delay > 0 then
                        task.wait(Delay)
                    end
                    if Shared.HackGen ~= Gen then return end
                    Remotes.HackAction:FireServer("tap", Id, Round, Note.d, Start + Note.t)
                    task.wait(0.02)
                end
            end), true)
        end
    end)
    SafeConnect("VerityCue", function()
        return Remotes.VerityCue and Remotes.VerityCue.OnClientEvent
    end, function(Kind, Data)
        if Kind == "Fight" and type(Data) == "table" then
            local Path = GetSafeModule(MFolder, "VerityPath")
            if Path then
                Shared.Vty.Path = Path.new(Data.Seed, Data.StartAt, Data.Hover, Data.Min, Data.Max)
                Shared.Vty.NextAt = 0
            end
        elseif Kind == "Dodge" and Shared.Vty.Path and type(Data) == "table" then
            Shared.Vty.Path:AddDodge(Data.T0, Data.Dir, Data.Amp)
        elseif Kind == "End" then
            Shared.Vty.Path = nil
        end
    end)
    SafeConnect("LaptopFightCue", function()
        return Remotes.LaptopFightCue and Remotes.LaptopFightCue.OnClientEvent
    end, function(Kind, Data)
        if Kind == "Fight" then
            Shared.LF.Active = true
            Shared.LF.EndsAt = (type(Data) == "table" and Data.EndsAt) or workspace:GetServerTimeNow() + 35
        elseif Kind == "End" then
            Shared.LF.Active = false
        end
    end)
    if Remotes.GetState then
        task.spawn(function()
            local Res = SafeInvoke(Remotes.GetState)
            if type(Res) == "table" then
                Shared.ME = Res
            end
        end)
    end
end

TB_Tabs.Autofarm.T1:AddToggle("AutoJoin", { Text = "Auto Join", Default = false })
TB_Tabs.Autofarm.T1:AddToggle("AutoWork", { Text = "Auto Work", Default = false })
TB_Tabs.Autofarm.T1:AddToggle("AutoSmack", { Text = "Auto Smack", Default = false })
TB_Tabs.Autofarm.T1:AddToggle("AutoAds", { Text = "Auto Dismiss Ads", Default = false })
TB_Tabs.Autofarm.T1:AddToggle("AutoInterrupt", { Text = "Auto Interrupt", Default = false })
TB_Tabs.Autofarm.T1:AddDivider()
TB_Tabs.Autofarm.T1:AddToggle("AutoEvents", { Text = "Auto Events", Default = false })
TB_Tabs.Autofarm.T1:AddToggle("AutoQuiz", { Text = "Auto Quiz", Default = false })
TB_Tabs.Autofarm.T1:AddToggle("AutoHack", { Text = "Auto Hack", Default = false })
TB_Tabs.Autofarm.T1:AddToggle("AutoPaper", { Text = "Auto Paper Fight", Default = false })
TB_Tabs.Autofarm.T1:AddDivider()
TB_Tabs.Autofarm.T1:AddToggle("AutoRelax", { Text = "Auto Relax", Default = false })
TB_Tabs.Autofarm.T1:AddSlider("RelaxAt", { Text = "Relax At", Default = 60, Min = 30, Max = 95, Rounding = 0, Compact = true })
TB_Tabs.Autofarm.T1:AddToggle("AutoClaim", { Text = "Auto Claim Playtime", Default = false })
TB_Tabs.Autofarm.T1:AddToggle("AutoUpgrade", { Text = "Auto Upgrade", Default = false })
TB_Tabs.Autofarm.T1:AddDivider()
TB_Tabs.Autofarm.T1:AddToggle("AutoAlien", { Text = "Auto Old PC", Default = false })
TB_Tabs.Autofarm.T1:AddToggle("AutoHalloween", { Text = "Auto Halloween", Default = false })
TB_Tabs.Autofarm.T1:AddToggle("AutoVerity", { Text = "Auto Verity", Default = false })
TB_Tabs.Autofarm.T1:AddToggle("AutoLaptopFight", { Text = "Auto Laptop Fight", Default = false })

Toggles.AutoJoin:OnChanged(function(state)
    Thread("AutoJoin", SafeLoop("AutoJoin", Func_AutoJoin), state)
end)
Toggles.AutoWork:OnChanged(function(state)
    Thread("AutoWork", SafeLoop("AutoWork", Func_AutoWork), state)
end)
Toggles.AutoSmack:OnChanged(function(state)
    Thread("AutoSmack", SafeLoop("AutoSmack", Func_AutoSmack), state)
end)
Toggles.AutoAds:OnChanged(function(state)
    Thread("AutoAds", SafeLoop("AutoAds", Func_AutoAds), state)
end)
Toggles.AutoInterrupt:OnChanged(function(state)
    Thread("AutoInterrupt", SafeLoop("AutoInterrupt", Func_AutoInterrupt), state)
end)
Toggles.AutoEvents:OnChanged(function(state)
    Thread("AutoEvents", SafeLoop("AutoEvents", Func_AutoEvents), state)
end)
Toggles.AutoHack:OnChanged(function(state)
    Thread("AutoHack", SafeLoop("AutoHack", Func_AutoHack), state)
end)
Toggles.AutoPaper:OnChanged(function(state)
    Thread("AutoPaper", SafeLoop("AutoPaper", Func_AutoPaper), state)
end)
Toggles.AutoRelax:OnChanged(function(state)
    Thread("AutoRelax", SafeLoop("AutoRelax", Func_AutoRelax), state)
end)
Toggles.AutoClaim:OnChanged(function(state)
    Thread("AutoClaim", SafeLoop("AutoClaim", Func_AutoClaim), state)
end)
Toggles.AutoUpgrade:OnChanged(function(state)
    Thread("AutoUpgrade", SafeLoop("AutoUpgrade", Func_AutoUpgrade), state)
end)
Toggles.AutoAlien:OnChanged(function(state)
    Thread("AutoAlien", SafeLoop("AutoAlien", Func_AutoAlien), state)
end)
Toggles.AutoHalloween:OnChanged(function(state)
    Thread("AutoHalloween", SafeLoop("AutoHalloween", Func_AutoHalloween), state)
end)
Toggles.AutoVerity:OnChanged(function(state)
    Thread("AutoVerity", SafeLoop("AutoVerity", Func_AutoVerity), state)
end)
Toggles.AutoLaptopFight:OnChanged(function(state)
    Thread("AutoLaptopFight", SafeLoop("AutoLaptopFight", Func_AutoLaptopFight), state)
end)
local MenuGroup = Tabs.Config:AddLeftGroupbox("Menu")
MenuGroup:AddToggle("AutoShowUI", {
    Text = "Auto Show UI",
    Default = true,
})
MenuGroup:AddToggle("KeybindMenuOpen", {
        Default = Library.KeybindFrame.Visible,
        Text = "Open Keybind Menu",
        Callback = function(value)
                Library.KeybindFrame.Visible = value
        end,
})
MenuGroup:AddToggle("ShowCustomCursor", {
        Text = "Custom Cursor",
        Default = false,
        Callback = function(Value)
                Library.ShowCustomCursor = Value
        end,
})
MenuGroup:AddDropdown("NotificationSide", {
        Values = { "Left", "Right" },
        Default = "Right",
        Text = "Notification Side",
        Callback = function(Value)
                Library:SetNotifySide(Value)
        end,
})
MenuGroup:AddDropdown("DPIDropdown", {
        Values = { "50%", "75%", "100%", "125%", "150%", "175%", "200%" },
        Default = "100%",
        Text = "DPI Scale",
        Callback = function(Value)
                Value = Value:gsub("%%", "")
                local DPI = tonumber(Value)
                Library:SetDPIScale(DPI)
        end,
})
MenuGroup:AddDivider()
MenuGroup:AddLabel("Menu bind")
        :AddKeyPicker("MenuKeybind", { Default = "U", NoUI = true, Text = "Menu keybind" })
MenuGroup:AddButton("Unload", function()
    getgenv().ayasemiyatongekissazumirisa = false
    if antiAFKConn and antiAFKConn.Enable then pcall(function() antiAFKConn:Enable() end) end
    if Support.FPS then pcall(function() setfpscap(2000) end) end
    Cleanup(Connections)
    Cleanup(Flags)
        Library:Unload()
end)
Library.ToggleKeybind = Options.MenuKeybind
ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
ThemeManager:SetFolder("Yuri")
SaveManager:SetFolder("Yuri/DontGetFired")
SaveManager:BuildConfigSection(Tabs.Config)
ThemeManager:ApplyToTab(Tabs.Config)
task.defer(function()
    SaveManager:LoadAutoloadConfig()
end)
SaveManager:SetLoadingOrder(true, {"Dropdown", "Slider", "ColorPicker", "KeyPicker", "Input", "Toggle"})
if UIS.TouchEnabled and not UIS.KeyboardEnabled then
    Library:SetDPIScale(75)
elseif UIS.KeyboardEnabled then
    Library:SetDPIScale(100)
end
Library:Notify("Script loaded.", 2)
Library:Notify("Yuri!", 5)
end)
if not eh_success then
    Library:Notify("ERROR: " .. tostring(err), 4)
    notyuri("ERROR: " .. tostring(err))
end
