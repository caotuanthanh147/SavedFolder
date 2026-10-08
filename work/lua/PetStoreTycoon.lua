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
local Plr = Players.LocalPlayer
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
local function TPTo(target, offset)
    local char = GetCharacter()
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    local cframe
    if typeof(target) == "CFrame" then
        cframe = target
    elseif typeof(target) == "Vector3" then
        cframe = CFrame.new(target)
    elseif typeof(target) == "Instance" then
        if target:IsA("BasePart") then
            cframe = target.CFrame
        elseif target:IsA("Model") then
            cframe = target:GetPivot()
        end
    end
    if not cframe then return false end
    if offset then
        cframe = cframe * CFrame.new(offset)
    end
    hrp.CFrame = cframe
    return true
end
local function TweenTo(speed, target, offset, arive)
    local char = GetCharacter()
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    local cframe
    if typeof(target) == "CFrame" then
        cframe = target
    elseif typeof(target) == "Vector3" then
        cframe = CFrame.new(target)
    elseif typeof(target) == "Instance" then
        if target:IsA("BasePart") then
            cframe = target.CFrame
        elseif target:IsA("Model") then
            cframe = target:GetPivot()
        end
    end
    if not cframe then return false end
    if offset then
        cframe = cframe * CFrame.new(offset)
    end
    local goal = cframe.Position
    while true do
        local _, delta = RunService.Stepped:Wait()
        char = GetCharacter()
        hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then return false end
        local diff = goal - hrp.Position
        local dist = diff.Magnitude
        if arive and dist <= arive then
            return true
        end
        local stepDist = speed * delta
        if dist <= stepDist then
            hrp.CFrame = cframe
            return true
        end
        hrp.CFrame = CFrame.new(hrp.Position + diff.Unit * stepDist) * (hrp.CFrame - hrp.CFrame.Position)
    end
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
Shared.BoxGens = {}
Shared.Memo = { Mess = {}, Care = {}, Box = {}, Fill = {} }
Shared.Checkout = { Seq = 0, State = nil, Active = false, At = 0, Recent = {} }
Shared.StockCursor = {}
Shared.Connects = {}

local ActivePlot = nil
local PlayerData = nil
local ShelfRules = nil
local EnclosureRules = nil
local Maintenance = nil
local CheckoutMoney = nil

local function EnsureModules()
    local mods = GetObject(RS, "Modules")
    if not mods then return end
    if not ActivePlot then ActivePlot = GetSafeModule(mods, "ActivePlot") end
    if not PlayerData then PlayerData = GetSafeModule(mods, "PlayerDataClient") end
    if not ShelfRules then ShelfRules = GetSafeModule(mods, "ShelfRules") end
    if not EnclosureRules then EnclosureRules = GetSafeModule(mods, "EnclosureRules") end
    if not Maintenance then Maintenance = GetSafeModule(mods, "EnclosureMaintenance") end
    if not CheckoutMoney then CheckoutMoney = GetSafeModule(mods, "CheckoutMoney") end
end
EnsureModules()

local function PopulateRemotes()
    local root = GetObject(RS, "Remotes")
    if not root then return end
    Remotes.OrderItem = GetObject(root, "Plot.OrderItem")
    Remotes.StartNextDay = GetObject(root, "Plot.StartNextDay")
    Remotes.SetGoodPrice = GetObject(root, "Goods.SetGoodPrice")
    Remotes.PlaceGoods = GetObject(root, "Goods.PlaceGoods")
    Remotes.PickUpBox = GetObject(root, "Goods.PickUpBox")
    Remotes.BeginShift = GetObject(root, "Checkout.BeginShift")
    Remotes.ScanCurrent = GetObject(root, "Checkout.ScanCurrent")
    Remotes.AcceptPayment = GetObject(root, "Checkout.AcceptPresentedPayment")
    Remotes.SubmitCashChange = GetObject(root, "Checkout.SubmitCashChange")
    Remotes.SubmitCardAmount = GetObject(root, "Checkout.SubmitCardAmount")
    Remotes.EndShift = GetObject(root, "Checkout.EndShift")
    Remotes.CleanMess = GetObject(root, "Mess.Clean")
    Remotes.BeginCare = GetObject(root, "Enclosures.BeginCare")
    Remotes.CompleteCare = GetObject(root, "Enclosures.CompleteCare")
    Remotes.CurbsideAccept = GetObject(root, "Curbside.Accept")
    Remotes.BoxReport = GetObject(root, "Boxes.Report")
end

local function ConnectListeners()
    local function Once(key, path, handler)
        if Shared.Connects[key] then return end
        local ev = GetObject(RS, path)
        if ev and ev.OnClientEvent then
            SafeConnect(key, function() return ev.OnClientEvent end, handler)
            Shared.Connects[key] = true
        end
    end
    Once("BoxSpawn", "Remotes.Boxes.Spawn", function(key, plotName, extra, props, cframe, gen)
        if type(key) == "string" and type(gen) == "number" then
            Shared.BoxGens[key] = gen
        end
    end)
    Once("CheckoutState", "Remotes.UI.CheckoutState", function(state)
        Shared.Checkout.State = state
        if type(state) == "table" then
            Shared.Checkout.At = os.clock()
        end
    end)
    Once("DaySummary", "Remotes.UI.DaySummary", function()
        if Toggles.AutoNextDay and Toggles.AutoNextDay.Value then
            task.delay(1, function()
                if Toggles.AutoNextDay.Value and Remotes.StartNextDay then
                    Remotes.StartNextDay:FireServer()
                end
            end)
        end
    end)
end

PopulateRemotes()
task.spawn(function()
    for _ = 1, 30 do
        PopulateRemotes()
        ConnectListeners()
        if Remotes.OrderItem and Remotes.BeginShift and Remotes.CleanMess and Shared.Connects.BoxSpawn then
            break
        end
        task.wait(2)
    end
end)

local function GetPlot()
    if ActivePlot then
        local ok, res = pcall(function() return ActivePlot.getPlot() end)
        if ok then return res end
    end
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return nil end
    local host = Plr:GetAttribute("ActivePlotOwnerUserId")
    if type(host) ~= "number" then host = Plr.UserId end
    for _, p in ipairs(plots:GetChildren()) do
        if p:GetAttribute("OwnerUserId") == host then
            return p
        end
    end
    return nil
end

local function GoodInfo(key)
    local root = GetObject(RS, "Goods")
    if not root then return nil end
    for _, cat in ipairs(root:GetChildren()) do
        if cat:IsA("Folder") then
            for _, sub in ipairs(cat:GetChildren()) do
                if sub:IsA("Folder") then
                    local it = sub:FindFirstChild(key)
                    if it and (it:IsA("Model") or it:IsA("BasePart")) then
                        local qty = it:GetAttribute("BoxQuantity")
                        local price = it:GetAttribute("BoxPrice")
                        return {
                            key = key,
                            category = cat.Name,
                            subCategory = sub.Name,
                            qty = type(qty) == "number" and math.floor(qty) or 1,
                            price = type(price) == "number" and price or 0,
                            item = it,
                        }
                    end
                end
            end
        end
    end
    return nil
end

local function GoodsBySize()
    local out = { Small = {}, Medium = {}, Large = {} }
    local root = GetObject(RS, "Goods")
    if not root then return out end
    for _, cat in ipairs(root:GetChildren()) do
        if cat:IsA("Folder") then
            for _, sub in ipairs(cat:GetChildren()) do
                if sub:IsA("Folder") and (sub.Name == "Small" or sub.Name == "Medium" or sub.Name == "Large") then
                    for _, item in ipairs(sub:GetChildren()) do
                        if item:IsA("Model") or item:IsA("BasePart") then
                            local qty = item:GetAttribute("BoxQuantity")
                            table.insert(out[sub.Name], {
                                key = item.Name,
                                category = cat.Name,
                                subCategory = sub.Name,
                                qty = type(qty) == "number" and math.floor(qty) or 1,
                                item = item,
                            })
                        end
                    end
                end
            end
        end
    end
    return out
end

local function GreedyCounts(cents)
    local counts = {}
    if not CheckoutMoney or type(CheckoutMoney.Denominations) ~= "table" then
        return counts
    end
    local list = {}
    for _, d in ipairs(CheckoutMoney.Denominations) do
        table.insert(list, d)
    end
    table.sort(list, function(a, b) return a.cents > b.cents end)
    local rest = cents
    for _, d in ipairs(list) do
        local n = math.floor(rest / d.cents)
        if n > 0 then
            counts[d.id] = n
            rest = rest - n * d.cents
        end
    end
    return counts
end

local function ReportBox(boxKey, cframe)
    local gen = Shared.BoxGens[boxKey]
    if not gen or not Remotes.BoxReport then return end
    pcall(function()
        Remotes.BoxReport:FireServer({ { k = boxKey, c = cframe, g = gen } })
    end)
end

local function FindTill(plot)
    for _, inst in ipairs(plot:GetDescendants()) do
        if inst:IsA("Model") and inst.Name == "Checkout" then
            local f = inst:FindFirstChild("Foundation")
            if f and f:IsA("BasePart") then
                return inst
            end
        end
    end
    return nil
end

local function StockSlot(plot, pick, shelf, shelfKey, slot, idx)
    if not Remotes.OrderItem or not Remotes.PickUpBox or not Remotes.PlaceGoods then return end
    Remotes.OrderItem:FireServer({ category = pick.category, subCategory = pick.subCategory, item = pick.key })
    local boxes = plot:FindFirstChild("Boxes")
    if not boxes then
        boxes = plot:WaitForChild("Boxes", 6)
    end
    if not boxes then return end
    local boxKey = nil
    local t0 = os.clock()
    while os.clock() - t0 < 6 do
        for _, b in ipairs(boxes:GetChildren()) do
            local k = b:GetAttribute("BoxKey")
            if type(k) == "string" and not Shared.Memo.Box[k] then
                boxKey = k
                break
            end
        end
        if boxKey then break end
        task.wait(0.25)
    end
    if not boxKey then return end
    Shared.Memo.Box[boxKey] = os.clock()
    for k in pairs(Shared.Memo.Box) do
        if os.clock() - Shared.Memo.Box[k] > 120 then
            Shared.Memo.Box[k] = nil
        end
    end
    local box = boxes:FindFirstChild(boxKey)
    if box then
        TPTo(box)
    end
    Remotes.PickUpBox:FireServer(boxKey)
    task.wait(0.5)
    local gp = ShelfRules and ShelfRules.goodsPartOf(slot) or nil
    if gp then
        TPTo(gp, Vector3.new(0, 2, 0))
        ReportBox(boxKey, gp.CFrame)
    else
        TPTo(shelf)
    end
    SafeInvoke(Remotes.PlaceGoods, nil, boxKey, shelfKey, idx)
end

local function Func_AutoStock()
    while Toggles.AutoStock.Value do
        local ok, err = pcall(function()
            EnsureModules()
            if not ShelfRules or not ActivePlot then return end
            local plot = GetPlot()
            if not plot then return end
            local goodsData = PlayerData and PlayerData.getGoods() or nil
            local shelvesData = type(goodsData) == "table" and type(goodsData.Shelves) == "table" and goodsData.Shelves or nil
            if not shelvesData then return end
            local now = os.clock()
            for k in pairs(Shared.Memo.Fill) do
                if now - Shared.Memo.Fill[k] > 120 then
                    Shared.Memo.Fill[k] = nil
                end
            end
            local bySize = GoodsBySize()
            for _, shelf in ipairs(plot:GetDescendants()) do
                if shelf:IsA("Model") and ShelfRules.isShelf(shelf) then
                    local shelfKey = shelf:GetAttribute("ItemId")
                    local size = ShelfRules.slotSizeOf(shelf)
                    if type(shelfKey) == "string" and size then
                        local slots = ShelfRules.slotModels(shelf)
                        local used = {}
                        for _, slot in ipairs(slots) do
                            local idx = slot:GetAttribute(ShelfRules.SLOT_INDEX_ATTR)
                            if type(idx) == "number" then
                                local data = shelvesData[shelfKey] and shelvesData[shelfKey][tostring(idx)] or nil
                                if type(data) == "table" and type(data.Good) == "string" then
                                    used[data.Good] = true
                                end
                            end
                        end
                        for _, slot in ipairs(slots) do
                            local idx = slot:GetAttribute(ShelfRules.SLOT_INDEX_ATTR)
                            if type(idx) == "number" then
                                local fk = shelfKey .. "." .. idx
                                local fa = Shared.Memo.Fill[fk] or 0
                                if now - fa > 15 then
                                    local data = shelvesData[shelfKey] and shelvesData[shelfKey][tostring(idx)] or nil
                                    local good = type(data) == "table" and data.Good or nil
                                    local qty = type(data) == "table" and tonumber(data.Qty) or 0
                                    local pick = nil
                                    if good then
                                        local info = GoodInfo(good)
                                        if info and qty < info.qty then
                                            pick = info
                                        end
                                    else
                                        local picks = bySize[size] or {}
                                        if #picks > 0 then
                                            Shared.StockCursor[shelfKey] = (Shared.StockCursor[shelfKey] or 0) + 1
                                            local cursor = Shared.StockCursor[shelfKey]
                                            for i = 1, #picks do
                                                local cand = picks[((cursor - 1 + i - 1) % #picks) + 1]
                                                if not used[cand.key] then
                                                    pick = cand
                                                    break
                                                end
                                            end
                                            pick = pick or picks[((cursor - 1) % #picks) + 1]
                                        end
                                    end
                                    if pick then
                                        Shared.Memo.Fill[fk] = now
                                        StockSlot(plot, pick, shelf, shelfKey, slot, idx)
                                        return
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end)
        if not ok then notyuri("AutoStock err:", tostring(err)) end
        task.wait(1)
    end
end

local function Func_AutoCheckout()
    while Toggles.AutoCheckout.Value do
        local ok, err = pcall(function()
            EnsureModules()
            if not ActivePlot then return end
            local plot = GetPlot()
            if not plot then return end
            if not Remotes.BeginShift then return end
            local till = FindTill(plot)
            if not till then return end
            local st = Shared.Checkout.State
            if type(st) ~= "table" or st.transactionId == nil or type(st.phase) ~= "string" then
                if Shared.Checkout.Active and os.clock() - Shared.Checkout.At > 25 then
                    if Remotes.EndShift then
                        Remotes.EndShift:FireServer()
                    end
                    Shared.Checkout.Active = false
                elseif not Shared.Checkout.Active then
                    local res = SafeInvoke(Remotes.BeginShift, nil, till)
                    if type(res) == "table" and res.ok then
                        Shared.Checkout.Active = true
                        Shared.Checkout.At = os.clock()
                        if type(res.state) == "table" then
                            Shared.Checkout.State = res.state
                        end
                    end
                end
                return
            end
            Shared.Checkout.At = os.clock()
            if st.phase == "Scanning" then
                local scanned = {}
                for _, line in ipairs(st.itemLines or {}) do
                    if line.scanned then
                        scanned[line.sourceIndex] = true
                    end
                end
                local now = os.clock()
                for k in pairs(Shared.Checkout.Recent) do
                    if now - Shared.Checkout.Recent[k] > 60 then
                        Shared.Checkout.Recent[k] = nil
                    end
                end
                for _, child in ipairs(till:GetChildren()) do
                    local idx = child:GetAttribute("CheckoutItemIndex")
                    if type(idx) == "number" and child:GetAttribute("CheckoutTransactionId") == st.transactionId and not scanned[idx] then
                        local rk = tostring(st.transactionId) .. "." .. idx
                        local ra = Shared.Checkout.Recent[rk]
                        if not ra or now - ra > 3 then
                            Shared.Checkout.Recent[rk] = now
                            Shared.Checkout.Seq = Shared.Checkout.Seq + 1
                            if Remotes.ScanCurrent then
                                Remotes.ScanCurrent:FireServer(child, st.transactionId, Shared.Checkout.Seq)
                            end
                        end
                        return
                    end
                end
            elseif st.phase == "AwaitingPayment" then
                if Remotes.AcceptPayment then
                    Remotes.AcceptPayment:FireServer(true)
                end
            elseif st.phase == "CashChange" then
                local due = tonumber(st.changeDueCents) or 0
                if due > 0 and Remotes.SubmitCashChange then
                    local counts = GreedyCounts(due)
                    if next(counts) then
                        Remotes.SubmitCashChange:FireServer(counts)
                    end
                end
            elseif st.phase == "CardEntry" then
                local total = tonumber(st.totalCents) or 0
                if total > 0 and Remotes.SubmitCardAmount then
                    Remotes.SubmitCardAmount:FireServer(total)
                end
            end
        end)
        if not ok then notyuri("AutoCheckout err:", tostring(err)) end
        task.wait(0.3)
    end
end

local function Func_AutoClean()
    while Toggles.AutoClean.Value do
        local ok, err = pcall(function()
            EnsureModules()
            if not ActivePlot then return end
            local plot = GetPlot()
            if not plot then return end
            local present = {}
            for _, inst in ipairs(plot:GetDescendants()) do
                local id = inst:GetAttribute("MessId")
                if type(id) == "string" then
                    present[id] = true
                    if not Shared.Memo.Mess[id] then
                        Shared.Memo.Mess[id] = true
                        TPTo(inst)
                        task.wait(0.2)
                        if Remotes.CleanMess then
                            Remotes.CleanMess:FireServer({ messId = id })
                        end
                        return
                    end
                end
            end
            for id in pairs(Shared.Memo.Mess) do
                if not present[id] then
                    Shared.Memo.Mess[id] = nil
                end
            end
        end)
        if not ok then notyuri("AutoClean err:", tostring(err)) end
        task.wait(1)
    end
end

local function Func_AutoPrice()
    while Toggles.AutoPrice.Value do
        local ok, err = pcall(function()
            EnsureModules()
            if not ShelfRules or not ActivePlot then return end
            local plot = GetPlot()
            if not plot then return end
            local goodsData = PlayerData and PlayerData.getGoods() or nil
            local shelvesData = type(goodsData) == "table" and type(goodsData.Shelves) == "table" and goodsData.Shelves or nil
            if not shelvesData then return end
            local priced = {}
            for _, shelf in ipairs(plot:GetDescendants()) do
                if shelf:IsA("Model") and ShelfRules.isShelf(shelf) then
                    local shelfKey = shelf:GetAttribute("ItemId")
                    if type(shelfKey) == "string" then
                        for _, slot in ipairs(ShelfRules.slotModels(shelf)) do
                            local idx = slot:GetAttribute(ShelfRules.SLOT_INDEX_ATTR)
                            if type(idx) == "number" then
                                local data = shelvesData[shelfKey] and shelvesData[shelfKey][tostring(idx)] or nil
                                local good = type(data) == "table" and data.Good or nil
                                local gp = ShelfRules.goodsPartOf(slot)
                                if type(good) == "string" and gp and not priced[good] then
                                    local current = gp:GetAttribute(ShelfRules.PRICE_ATTR)
                                    if type(current) == "number" then
                                        local info = GoodInfo(good)
                                        if info and info.item then
                                            local optimal = ShelfRules.optimalPriceOf(info.item)
                                            if type(optimal) == "number" and math.abs(optimal - current) > 0.05 then
                                                if Remotes.SetGoodPrice then
                                                    Remotes.SetGoodPrice:FireServer(good, optimal)
                                                    priced[good] = true
                                                    return
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end)
        if not ok then notyuri("AutoPrice err:", tostring(err)) end
        task.wait(2)
    end
end

local function Care(enc, itemKey, feature, petKey)
    if not Remotes.BeginCare or not Remotes.CompleteCare then return end
    TPTo(enc)
    local payload = { itemKey = itemKey, feature = feature, petKey = petKey }
    local res = SafeInvoke(Remotes.BeginCare, nil, payload)
    if type(res) == "table" and res.ok and type(res.token) == "string" then
        payload.token = res.token
        payload.quiet = true
        SafeInvoke(Remotes.CompleteCare, nil, payload)
    end
end

local function Func_AutoPetCare()
    while Toggles.AutoPetCare.Value do
        local ok, err = pcall(function()
            EnsureModules()
            if not Maintenance or not EnclosureRules or not ActivePlot then return end
            local plot = GetPlot()
            if not plot then return end
            local now = os.clock()
            for _, enc in ipairs(plot:GetDescendants()) do
                if enc:IsA("Model") and EnclosureRules.isEnclosure(enc) then
                    local itemKey = enc:GetAttribute("ItemId")
                    if type(itemKey) == "string" then
                        for _, feature in ipairs(Maintenance.featuresOf(enc)) do
                            local def = Maintenance.get and Maintenance.get(feature) or nil
                            if not def and type(Maintenance.Features) == "table" then
                                def = Maintenance.Features[feature]
                            end
                            if def then
                                local gate = def.restoreGate or 90
                                if Maintenance.restoreGateFor then
                                    gate = Maintenance.restoreGateFor(def) or gate
                                end
                                local ck = itemKey .. "." .. feature
                                local at = Shared.Memo.Care[ck] or 0
                                if now - at > 30 then
                                    if def.scope == "animal" then
                                        local keys = Maintenance.needyPetKeysOf(enc, feature)
                                        if #keys > 0 then
                                            local pets = enc:FindFirstChild("Pets")
                                            local pm = pets and pets:FindFirstChild(keys[1]) or nil
                                            local pk = pm and pm:GetAttribute("PetKey") or keys[1]
                                            Shared.Memo.Care[ck] = now
                                            Care(enc, itemKey, feature, pk)
                                            return
                                        end
                                    else
                                        local need = tonumber(enc:GetAttribute("Need_" .. feature))
                                        if need and need < gate then
                                            Shared.Memo.Care[ck] = now
                                            Care(enc, itemKey, feature, nil)
                                            return
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end)
        if not ok then notyuri("AutoPetCare err:", tostring(err)) end
        task.wait(2)
    end
end

local function Func_AutoCurbside()
    while Toggles.AutoCurbside.Value do
        local ok, err = pcall(function()
            EnsureModules()
            if not ActivePlot or not Remotes.CurbsideAccept then return end
            local host = Plr.UserId
            if ActivePlot.getHostUserId then
                host = ActivePlot.getHostUserId()
            end
            for _, car in ipairs(Services.CollectionService:GetTagged("CurbsideCar")) do
                if car:IsA("Model") and car:GetAttribute("OwnerUserId") == host then
                    local accepted = car:GetAttribute("CurbsideAcceptedBy")
                    if (accepted == nil or accepted == 0) and car:GetAttribute("CurbsideWindow") ~= nil then
                        TPTo(car)
                        task.wait(0.2)
                        Remotes.CurbsideAccept:FireServer(car)
                        return
                    end
                end
            end
        end)
        if not ok then notyuri("AutoCurbside err:", tostring(err)) end
        task.wait(2)
    end
end

TB_Tabs.Autofarm.T1:AddDivider()
TB_Tabs.Autofarm.T1:AddToggle("AutoStock", { Text = "Auto Stock" })
TB_Tabs.Autofarm.T1:AddToggle("AutoCheckout", { Text = "Auto Checkout" })
TB_Tabs.Autofarm.T1:AddToggle("AutoClean", { Text = "Auto Clean" })
TB_Tabs.Autofarm.T1:AddDivider()
TB_Tabs.Autofarm.T1:AddToggle("AutoPrice", { Text = "Auto Price" })
TB_Tabs.Autofarm.T1:AddToggle("AutoPetCare", { Text = "Auto Pet Care" })
TB_Tabs.Autofarm.T1:AddToggle("AutoCurbside", { Text = "Auto Curbside" })
TB_Tabs.Autofarm.T1:AddToggle("AutoNextDay", { Text = "Auto Next Day" })

Toggles.AutoStock:OnChanged(function(state)
    Thread("AutoStock", SafeLoop("AutoStock", Func_AutoStock), state)
end)
Toggles.AutoCheckout:OnChanged(function(state)
    Thread("AutoCheckout", SafeLoop("AutoCheckout", Func_AutoCheckout), state)
    if not state and Shared.Checkout.Active then
        Shared.Checkout.Active = false
        Shared.Checkout.State = nil
        if Remotes.EndShift then
            pcall(function() Remotes.EndShift:FireServer() end)
        end
    end
end)
Toggles.AutoClean:OnChanged(function(state)
    Thread("AutoClean", SafeLoop("AutoClean", Func_AutoClean), state)
end)
Toggles.AutoPrice:OnChanged(function(state)
    Thread("AutoPrice", SafeLoop("AutoPrice", Func_AutoPrice), state)
end)
Toggles.AutoPetCare:OnChanged(function(state)
    Thread("AutoPetCare", SafeLoop("AutoPetCare", Func_AutoPetCare), state)
end)
Toggles.AutoCurbside:OnChanged(function(state)
    Thread("AutoCurbside", SafeLoop("AutoCurbside", Func_AutoCurbside), state)
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
SaveManager:SetFolder("Yuri/Pet Store Tycoon")
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
