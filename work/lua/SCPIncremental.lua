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
function AddSliderToggle(Config)
    local Toggle = Config.Group:AddToggle(Config.Id, {
        Text = Config.Text,
        Default = Config.DefaultToggle or false,
        Disabled = Config.Disabled,
    })
    local Slider = Config.Group:AddSlider(Config.Id .. "Value", {
        Text = Config.Text,
        Default = Config.Default,
        Min = Config.Min,
        Max = Config.Max,
        Rounding = Config.Rounding or 0,
        Compact = true,
        Visible = false
    })
    Toggle:OnChanged(function()
        Slider:SetVisible(Toggle.Value)
    end)
    return Toggle, Slider
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
local TPW_T, TPW_S = AddSliderToggle({ Group = GB.Player.Left.General, Id = "TPW", Text = "TPWalk", Default = 1, Min = 1, Max = 30, Rounding = 1 })
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
local FPS_T, FPS_S = AddSliderToggle({ Group = GB.Player.Left.General, Id = "LimitFPS", Text = "Set Max FPS", Disabled = not Support.FPS, Default = 60, Min = 5, Max = 360 })
GB.Player.Left.General:AddToggle("FPSBoost", { Text = "FPS Boost" })
GB.Player.Left.Server:AddToggle("AntiAFK", {
    Text = "Anti AFK",
    Default = true,
    Disabled = not Support.Connections,
})
GB.Player.Left.Server:AddToggle("AutoReconnect", { Text = "Auto Reconnect" })
GB.Player.Left.Server:AddToggle("NoGameplayPaused", { Text = "No Gameplay Paused"})
GB.Player.Left.Server:AddButton({ Text = "Serverhop", Func = function() Serverhop() end })
GB.Player.Left.Server:AddButton({ Text = "Rejoin", Func = function() Services.TeleportService:Teleport(game.PlaceId, Plr) end })
GB.Player.Left.Server:AddToggle("AutoServerhop", { Text = "Auto Serverhop" })
GB.Player.Left.Server:AddSlider("AutoHopMins", { Text = "Minutes", Default = 30, Min = 0, Max = 300, Compact = true, Rounding = 0 })
GB.Player.Right.Game:AddToggle("InstantPP", { Text = "Instant Prompt" })
GB.Player.Right.Game:AddToggle("Fullbright", { Text = "Fullbright" })
GB.Player.Right.Game:AddToggle("NoFog", { Text = "No Fog" })
AddSliderToggle({ Group = GB.Player.Right.Game, Id = "OverrideTime", Text = "Time Of Day", Default = 12, Min = 0, Max = 24, Rounding = 1 })
Toggles.AntiKnockback:OnChanged(function(state)
    Thread("AntiKnockback", Func_AntiKnockback, state)
end)
Toggles.TPW:OnChanged(function(v)
    TPW_S:SetVisible(TPW_T.Value)
    Thread("TPW", FuncTPW, v)
end)
Toggles.Noclip:OnChanged(function(v)
    Thread("Noclip", FuncNoclip, v)
end)
Toggles.AutoServerhop:OnChanged(function(state)
    Thread("AutoServerhop", function()
        local lastHop = tick()
        while Toggles.AutoServerhop.Value do
            task.wait(5)
            if not Toggles.AutoServerhop.Value then break end
            if (tick() - lastHop) >= (Options.AutoHopMins.Value * 60) then
                Serverhop()
                break
            end
        end
    end, state)
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
    if FPS_T.Value then
        setfpscap(FPS_S.Value)
    end
end)
Toggles.LimitFPS:OnChanged(function(v)
    FPS_S:SetVisible(FPS_T.Value)
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
Shared.Labels = {}
local Net = GetSafeModule(GetObject(RS, "Shared"), "Net")
local BigNum = GetSafeModule(GetObject(RS, "Shared"), "BigNum")
local ConfigFolder = GetObject(RS, "Config")
local Upgrades = ConfigFolder and GetSafeModule(ConfigFolder, "Upgrades") or nil
local Walls = ConfigFolder and GetSafeModule(ConfigFolder, "Walls") or nil
local Currencies = ConfigFolder and GetSafeModule(ConfigFolder, "Currencies") or nil
local Prestiges = ConfigFolder and GetSafeModule(ConfigFolder, "Prestiges") or nil
local Guns = ConfigFolder and GetSafeModule(ConfigFolder, "Guns") or nil
local Ranks = ConfigFolder and GetSafeModule(ConfigFolder, "Ranks") or nil
local Converts = ConfigFolder and GetSafeModule(ConfigFolder, "Converts") or nil
local Potions = ConfigFolder and GetSafeModule(ConfigFolder, "Potions") or nil
local GemClaims = ConfigFolder and GetSafeModule(ConfigFolder, "GemClaims") or nil
local RuneStations = ConfigFolder and GetSafeModule(ConfigFolder, "RuneStations") or nil
local CS = GetSafeModule(GetObject(Plr, "PlayerScripts.Client"), "ClientState")
local SCP = {}
SCP.GroupTried = false
SCP.TicketQueried = false
SCP.TicketPrices = {}
local WallNameToId = {}
local ConvertIds = {}
local PotionNameToId = {}
local StationLabels = {}
local TeleportLabels = {}
local StatRows = {}

local function SCPReady()
    if not (CS and Net and Upgrades and Walls and Currencies and Prestiges and Guns and Ranks and GemClaims) then
        return false
    end
    if CS.isReady and not CS.isReady() then
        return false
    end
    return true
end

local function MeetsRequires(upg)
    local req = upg.Requires
    if not req then
        return true
    end
    if req.Prestige and CS.getPrestige() < req.Prestige then
        return false
    end
    local ups = req.Upgrades
    if ups then
        for _, r in ipairs(ups) do
            if CS.getLevel(r.Id) < r.Level then
                return false
            end
        end
    end
    local reqWalls = req.Walls
    if reqWalls then
        for _, w in ipairs(reqWalls) do
            if not CS.isWallUnlocked(w) then
                return false
            end
        end
    end
    local flags = req.Flags
    if flags then
        for _, f in ipairs(flags) do
            if Plr:GetAttribute(f) ~= true then
                return false
            end
        end
    end
    return true
end

local function GetStations()
    local out = {}
    local locations = workspace:FindFirstChild("Locations")
    if locations then
        for _, model in ipairs(locations:GetChildren()) do
            local sid = model:GetAttribute("StationId")
            if sid then
                local def = RuneStations and RuneStations.ById and RuneStations.ById[sid] or nil
                local label = (def and def.Name) or model.Name
                table.insert(out, { label = label, model = model })
            end
        end
    end
    table.sort(out, function(a, b)
        return a.label < b.label
    end)
    return out
end

local function FindMyLizard()
    local scene = workspace:FindFirstChild("LizardScene")
    if not scene then
        return nil
    end
    for _, model in ipairs(scene:GetChildren()) do
        if model:IsA("Model") and model:GetAttribute("OwnerUserId") == Plr.UserId then
            return model
        end
    end
    return nil
end

local function EquipGun()
    local char = GetCharacter()
    if not char then
        return nil
    end
    local tool = char:FindFirstChild("Gun")
    if tool and tool:IsA("Tool") then
        return tool
    end
    local backpack = Plr:FindFirstChild("Backpack")
    if not backpack then
        return nil
    end
    tool = backpack:FindFirstChild("Gun")
    if tool and tool:IsA("Tool") then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            pcall(function()
                hum:EquipTool(tool)
            end)
            task.wait(0.1)
            return char:FindFirstChild("Gun")
        end
    end
    return nil
end

local function StepUpgrades()
    local selected = AddMultiDropdown("SCPUpWalls")
    for _, wall in ipairs(Walls.List) do
        if selected[wall.Name] and CS.isWallUnlocked(wall.Id) then
            local list = Upgrades.forWall(wall.Id)
            for _, upg in ipairs(list) do
                if CS.getLevel(upg.Id) < upg.MaxLevel then
                    if MeetsRequires(upg) and CS.canAfford(upg.Id) then
                        CS.buyMax(upg.Id)
                    end
                end
            end
        end
    end
end

local function StepRebirth()
    if CS.canRebirth() then
        CS.rebirth()
    end
end

local function StepPrestige()
    local nextP = Prestiges.next(CS.getPrestige())
    if nextP and nextP.Cost then
        if BigNum.gte(CS.getCurrency("Peanuts"), BigNum.new(nextP.Cost)) then
            CS.prestige()
        end
    end
end

local function StepGun()
    local tier = (CS.getGunTier and CS.getGunTier()) or 1
    local nextGun = Guns.get(tier + 1)
    if nextGun and nextGun.Price then
        if BigNum.gte(CS.getCurrency("Bones"), BigNum.new(nextGun.Price)) then
            CS.request(Net.Actions.BuyGun, {})
        end
    end
end

local function StepConvert()
    local selected = AddMultiDropdown("SCPConverts")
    for _, conv in ipairs(Converts.List) do
        if selected[conv.Id] then
            if BigNum.gte(CS.getCurrency(conv.From), BigNum.new(conv.Requirement)) then
                CS.convert(conv.Id)
            end
        end
    end
end

local function StepRanks()
    if CS.getPrestige() < Ranks.REQUIRED_PRESTIGE then
        return
    end
    local kc = CS.getKeycards()
    if kc >= 1 then
        CS.rollRank(math.min(kc, 25))
    end
end

local function StepEquipBest()
    local owned = CS.getRanks()
    local best = Ranks.best(owned)
    if best and owned[best.Id] then
        if CS.getEquippedRank() ~= best.Id then
            CS.equipRank(best.Id)
        end
    end
end

local function StepGems()
    local lastAt = CS.getGemClaim()
    local now = workspace:GetServerTimeNow()
    if GemClaims.isReady(lastAt, now) then
        CS.claimGems()
    end
end

local function StepGroup()
    if SCP.GroupTried then
        return
    end
    SCP.GroupTried = true
    CS.request(Net.Actions.ClaimGroupReward, {}, function() end)
end

local function StepPotions()
    local selected = AddMultiDropdown("SCPPotionsSel")
    local owned = CS.getPotions()
    local now = workspace:GetServerTimeNow()
    for _, pot in ipairs(Potions.List) do
        if selected[pot.Name] and (owned[pot.Id] or 0) >= 1 then
            local expires = Plr:GetAttribute(pot.ExpiryAttribute)
            local active = false
            if type(expires) == "number" and expires > now then
                active = true
            end
            if not active then
                local activeAttr = pot.ExpiryAttribute:gsub("ExpiresAt", "Active")
                if Plr:GetAttribute(activeAttr) == true then
                    active = true
                end
            end
            if not active then
                CS.usePotion(pot.Id, 1)
            end
        end
    end
end

local function StepTickets()
    if not SCP.TicketQueried then
        SCP.TicketQueried = true
        for productId in pairs(Ranks.KeycardProducts) do
            CS.request(Net.Actions.GetTicketPrice, { productId = productId }, function(ok, err, res)
                if ok and type(res) == "table" and type(res.price) == "number" and res.price > 0 then
                    SCP.TicketPrices[productId] = res.price
                end
            end)
        end
        return
    end
    local tickets = CS.getTickets()
    local order = {}
    for productId, price in pairs(SCP.TicketPrices) do
        table.insert(order, { id = productId, price = price })
    end
    table.sort(order, function(a, b)
        return a.price < b.price
    end)
    for _, entry in ipairs(order) do
        if tickets >= entry.price then
            CS.request(Net.Actions.BuyWithTickets, { productId = entry.id }, function() end)
            tickets = tickets - entry.price
        end
    end
end

local function StepLizard()
    local mine = FindMyLizard()
    if not mine then
        return
    end
    local tier = mine:GetAttribute("Tier") or 1
    local highest = mine:GetAttribute("Highest") or 1
    if tier < highest then
        CS.request(Net.Actions.SelectLizardLevel, { tier = highest })
    end
end

local function StepGunFire()
    local tool = EquipGun()
    if not tool then
        task.wait(0.5)
        return
    end
    local rate = (Guns.BASE_SHOTS_PER_SECOND or 4) * ((Guns.get(CS.getGunTier()) or {}).FireRate or 1)
    if rate < 0.2 then
        rate = 0.2
    end
    local target = FindMyLizard()
    if not target then
        local zombieFolder = workspace:FindFirstChild("ZombieLocal")
        if zombieFolder then
            local list = {}
            for _, m in ipairs(zombieFolder:GetChildren()) do
                if m:IsA("Model") then
                    table.insert(list, m)
                end
            end
            if #list > 0 then
                target = GetNearest(list)
            end
        end
    end
    local char = GetCharacter()
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp then
        local shootingPart = workspace:FindFirstChild("shootinghere")
        if shootingPart and shootingPart:IsA("BasePart") then
            if (hrp.Position - shootingPart.Position).Magnitude > 25 then
                TPTo(shootingPart)
            end
        end
    end
    char = GetCharacter()
    hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp and target then
        local pivot = target:GetPivot()
        local pos = pivot.Position
        hrp.CFrame = CFrame.lookAt(hrp.Position, Vector3.new(pos.X, hrp.Position.Y, pos.Z))
    end
    pcall(function()
        tool:Activate()
    end)
    task.wait(1 / rate)
end

local function BuildFarmTasks()
    local tasks = {}
    if Toggles.SCPTears and Toggles.SCPTears.Value then
        local pad = workspace:FindFirstChild("tearpad")
        if pad then
            table.insert(tasks, pad)
        end
    end
    if Toggles.SCPLove and Toggles.SCPLove.Value then
        local zone = workspace:FindFirstChild("slimewalkzone")
        if zone then
            table.insert(tasks, zone)
        end
    end
    if Toggles.SCPRunes and Toggles.SCPRunes.Value then
        local selected = AddMultiDropdown("SCPRuneStations")
        for _, station in ipairs(GetStations()) do
            if selected[station.label] then
                table.insert(tasks, station.model)
            end
        end
    end
    return tasks
end

local function FarmAnyActive()
    if Toggles.SCPLove and Toggles.SCPLove.Value then
        return true
    end
    if Toggles.SCPTears and Toggles.SCPTears.Value then
        return true
    end
    if Toggles.SCPRunes and Toggles.SCPRunes.Value then
        return true
    end
    return false
end

local function FuncFarmPosition()
    local idx = 1
    while FarmAnyActive() do
        if Library.Unloaded then
            return
        end
        local tasks = BuildFarmTasks()
        if #tasks == 0 then
            task.wait(1)
        else
            if idx > #tasks then
                idx = 1
            end
            local spot = tasks[idx]
            idx = idx + 1
            local dwell = 30
            if Options.SCPDwell then
                dwell = math.clamp(Options.SCPDwell.Value, 5, 300)
            end
            TPTo(spot)
            local elapsed = 0
            while elapsed < dwell do
                if not FarmAnyActive() then
                    break
                end
                if Library.Unloaded then
                    return
                end
                task.wait(1)
                elapsed = elapsed + 1
            end
        end
    end
end

local function SyncFarmThread()
    Thread("SCP.Farm", FuncFarmPosition, FarmAnyActive() and true or false)
end

local function FuncUpgrades()
    while Toggles.SCPUpgrades.Value do
        pcall(function()
            if SCPReady() then
                StepUpgrades()
            end
        end)
        task.wait(0.5)
    end
end

local function FuncRebirth()
    while Toggles.SCPRebirth.Value do
        pcall(function()
            if SCPReady() then
                StepRebirth()
            end
        end)
        task.wait(1)
    end
end

local function FuncPrestige()
    while Toggles.SCPPrestige.Value do
        pcall(function()
            if SCPReady() then
                StepPrestige()
            end
        end)
        task.wait(2)
    end
end

local function FuncGun()
    while Toggles.SCPGun.Value do
        pcall(function()
            if SCPReady() then
                StepGun()
            end
        end)
        task.wait(1)
    end
end

local function FuncConvert()
    while Toggles.SCPConvert.Value do
        pcall(function()
            if SCPReady() then
                StepConvert()
            end
        end)
        task.wait(2)
    end
end

local function FuncRanks()
    while Toggles.SCPRanks.Value do
        pcall(function()
            if SCPReady() then
                StepRanks()
            end
        end)
        task.wait(0.5)
    end
end

local function FuncEquipRank()
    while Toggles.SCPEquipRank.Value do
        pcall(function()
            if SCPReady() then
                StepEquipBest()
            end
        end)
        task.wait(2)
    end
end

local function FuncGems()
    while Toggles.SCPGems.Value do
        pcall(function()
            if SCPReady() then
                StepGems()
            end
        end)
        task.wait(30)
    end
end

local function FuncGroup()
    while Toggles.SCPGroup.Value do
        pcall(function()
            if SCPReady() then
                StepGroup()
            end
        end)
        task.wait(10)
    end
end

local function FuncPotions()
    while Toggles.SCPPotions.Value do
        pcall(function()
            if SCPReady() then
                StepPotions()
            end
        end)
        task.wait(5)
    end
end

local function FuncTickets()
    while Toggles.SCPTickets.Value do
        pcall(function()
            if SCPReady() then
                StepTickets()
            end
        end)
        task.wait(30)
    end
end

local function FuncLizard()
    while Toggles.SCPLizard.Value do
        pcall(function()
            if SCPReady() then
                StepLizard()
            end
        end)
        task.wait(5)
    end
end

local function FuncGunFire()
    while Toggles.SCPGunFire.Value do
        local ok = pcall(function()
            if SCPReady() then
                StepGunFire()
            else
                task.wait(0.5)
            end
        end)
        if not ok then
            task.wait(0.5)
        end
    end
end

local function FuncStats()
    while not Library.Unloaded do
        pcall(function()
            if SCPReady() then
                for i, row in ipairs(StatRows) do
                    local text = "-"
                    if row.kind == "currency" then
                        local v = CS.getCurrency(row.currencyId)
                        if BigNum and BigNum.format then
                            text = BigNum.format(v, { trim = true })
                        else
                            text = tostring(v)
                        end
                    elseif row.kind == "prestige" then
                        text = tostring(CS.getPrestige() or 0)
                    elseif row.kind == "gun" then
                        local tier = (CS.getGunTier and CS.getGunTier()) or 1
                        local def = Guns.get(tier)
                        text = tostring(tier) .. (def and (" (" .. tostring(def.Name) .. ")") or "")
                    elseif row.kind == "rank" then
                        local id = CS.getEquippedRank()
                        local def = id and Ranks.ById and Ranks.ById[id] or nil
                        text = (def and def.Name) or "None"
                    elseif row.kind == "keycards" then
                        text = tostring(CS.getKeycards() or 0)
                    elseif row.kind == "tickets" then
                        text = tostring(CS.getTickets() or 0)
                    end
                    SafeLabel("SCPStat" .. i, row.label .. ": " .. text)
                end
            else
                for i, row in ipairs(StatRows) do
                    SafeLabel("SCPStat" .. i, row.label .. ": -")
                end
            end
        end)
        task.wait(1)
    end
end

TB_Tabs.Autofarm.T2 = TB.Main.Left.Autofarm:AddTab("World")
TB_Tabs.Autofarm2.T2 = TB.Main.Right.Autofarm:AddTab("Stats")
local GBFarmMain = TB_Tabs.Autofarm.T1:AddGroupbox("Autofarm")
GBFarmMain:AddToggle("SCPUpgrades", { Text = "Auto Buy Upgrades", Default = true })
GBFarmMain:AddToggle("SCPRebirth", { Text = "Auto Rebirth", Default = true })
GBFarmMain:AddToggle("SCPPrestige", { Text = "Auto Prestige", Default = false })
GBFarmMain:AddToggle("SCPGun", { Text = "Auto Buy Gun", Default = true })
GBFarmMain:AddToggle("SCPConvert", { Text = "Auto Convert", Default = false })
GBFarmMain:AddToggle("SCPRanks", { Text = "Auto Roll Ranks", Default = true })
GBFarmMain:AddToggle("SCPEquipRank", { Text = "Auto Equip Best Rank", Default = true })
local GBClaims = TB_Tabs.Autofarm.T1:AddGroupbox("Claims")
GBClaims:AddToggle("SCPGems", { Text = "Auto Claim Gems", Default = true })
GBClaims:AddToggle("SCPGroup", { Text = "Auto Group Reward", Default = false })
GBClaims:AddToggle("SCPPotions", { Text = "Auto Use Potions", Default = false })
GBClaims:AddToggle("SCPTickets", { Text = "Auto Buy With Tickets", Default = false })
GBClaims:AddToggle("SCPLizard", { Text = "Auto Lizard Max Level", Default = false })
local GBCombat = TB_Tabs.Autofarm.T2:AddGroupbox("Combat")
GBCombat:AddToggle("SCPGunFire", { Text = "Auto Gun Fire", Default = false })
local GBPos = TB_Tabs.Autofarm.T2:AddGroupbox("Farm Position")
GBPos:AddToggle("SCPTears", { Text = "Farm Tears (Stand)", Default = false })
GBPos:AddToggle("SCPLove", { Text = "Farm Love (Stand)", Default = false })
GBPos:AddToggle("SCPRunes", { Text = "Farm Runes (Stand)", Default = false })
GBPos:AddSlider("SCPDwell", { Text = "Dwell Seconds", Default = 30, Min = 5, Max = 300, Rounding = 0, Compact = true })
local GBSelect = TB_Tabs.Autofarm2.T1:AddGroupbox("Selections")
local GBTele = TB_Tabs.Autofarm2.T1:AddGroupbox("Teleport")
local GBStats = TB_Tabs.Autofarm2.T2:AddGroupbox("Live Stats")

do
    local wallValues = {}
    if Walls then
        for _, wall in ipairs(Walls.List) do
            table.insert(wallValues, wall.Name)
            WallNameToId[wall.Name] = wall.Id
        end
        table.sort(wallValues)
    end
    AddMultiDropdown(GBSelect, "SCPUpWalls", { Values = wallValues, Text = "Upgrade Walls", Default = { All = true } })
end
do
    local convertValues = {}
    if Converts then
        for _, conv in ipairs(Converts.List) do
            table.insert(convertValues, conv.Id)
            ConvertIds[conv.Id] = true
        end
        table.sort(convertValues)
    end
    AddMultiDropdown(GBSelect, "SCPConverts", { Values = convertValues, Text = "Converts" })
end
do
    local potionValues = {}
    if Potions then
        for _, pot in ipairs(Potions.List) do
            table.insert(potionValues, pot.Name)
            PotionNameToId[pot.Name] = pot.Id
        end
        table.sort(potionValues)
    end
    AddMultiDropdown(GBSelect, "SCPPotionsSel", { Values = potionValues, Text = "Potions" })
end
do
    for _, station in ipairs(GetStations()) do
        table.insert(StationLabels, station.label)
    end
    AddMultiDropdown(GBPos, "SCPRuneStations", { Values = StationLabels, Text = "Rune Stations" })
end
do
    local spots = {
        { "Spawn", function() return workspace:FindFirstChild("SpawnLocation") end },
        { "Tear Pad", function() return workspace:FindFirstChild("tearpad") end },
        { "Slime Zone", function() return workspace:FindFirstChild("slimewalkzone") end },
        { "Rank Zone", function() return GetObject(workspace, "RankZone.Hitbox") end },
        { "Shooting Gallery", function() return workspace:FindFirstChild("shootinghere") end },
        { "Lizard Level Wall", function() return workspace:FindFirstChild("changelevels") end },
        { "Gun Wall", function() return workspace:FindFirstChild("gunupgradewall") end },
        { "Prestige Wall", function() return workspace:FindFirstChild("prrestigewall") end },
        { "Gem Claim Board", function() return GetObject(workspace, "Dailies.ClaimBoard") end },
        { "Zombie Roll", function() return workspace:FindFirstChild("xzombieroll") end },
        { "Zombie Sell", function() return workspace:FindFirstChild("zombiesell") end },
        { "Milestone Wall", function() return workspace:FindFirstChild("milestonewall") end },
        { "Bonus Wall", function() return workspace:FindFirstChild("bonus wall") end },
        { "Convert (Tears)", function() return workspace:FindFirstChild("convert wall") end },
        { "Convert (Bullets)", function() return workspace:FindFirstChild("convert walltobullets") end },
    }
    for _, station in ipairs(GetStations()) do
        table.insert(spots, { station.label .. " Station", (function(model)
            return function() return model end
        end)(station.model) })
    end
    local labels = {}
    for i, spot in ipairs(spots) do
        labels[i] = spot[1]
        TeleportLabels[i] = spot
    end
    GBTele:AddDropdown("SCPTeleport", { Text = "Destination", Values = labels, Default = labels[1] or "Spawn" })
    GBTele:AddButton({ Text = "Teleport", Func = function()
        local pick = Options.SCPTeleport and Options.SCPTeleport.Value or nil
        if type(pick) ~= "string" then
            return
        end
        for _, spot in ipairs(TeleportLabels) do
            if spot[1] == pick then
                local target = spot[2]()
                if target then
                    TPTo(target)
                end
                return
            end
        end
    end })
end
do
    if Currencies then
        local sorted = {}
        for i, cur in ipairs(Currencies.List) do
            table.insert(sorted, { cur = cur, order = cur.Order or i, idx = i })
        end
        table.sort(sorted, function(a, b)
            if a.order ~= b.order then
                return a.order < b.order
            end
            return a.idx < b.idx
        end)
        for _, entry in ipairs(sorted) do
            table.insert(StatRows, { kind = "currency", label = entry.cur.Name, currencyId = entry.cur.Id })
        end
    end
    table.insert(StatRows, { kind = "prestige", label = "Prestige" })
    table.insert(StatRows, { kind = "gun", label = "Gun Tier" })
    table.insert(StatRows, { kind = "rank", label = "Rank" })
    table.insert(StatRows, { kind = "keycards", label = "Keycards" })
    table.insert(StatRows, { kind = "tickets", label = "Tickets" })
    for i, row in ipairs(StatRows) do
        SafeLabel(GBStats, "SCPStat" .. i, row.label .. ": -")
    end
end

Toggles.SCPUpgrades:OnChanged(function(state)
    Thread("SCP.Upgrades", SafeLoop("SCP.Upgrades", FuncUpgrades), state)
end)
Toggles.SCPRebirth:OnChanged(function(state)
    Thread("SCP.Rebirth", SafeLoop("SCP.Rebirth", FuncRebirth), state)
end)
Toggles.SCPPrestige:OnChanged(function(state)
    Thread("SCP.Prestige", SafeLoop("SCP.Prestige", FuncPrestige), state)
end)
Toggles.SCPGun:OnChanged(function(state)
    Thread("SCP.Gun", SafeLoop("SCP.Gun", FuncGun), state)
end)
Toggles.SCPConvert:OnChanged(function(state)
    Thread("SCP.Convert", SafeLoop("SCP.Convert", FuncConvert), state)
end)
Toggles.SCPRanks:OnChanged(function(state)
    Thread("SCP.Ranks", SafeLoop("SCP.Ranks", FuncRanks), state)
end)
Toggles.SCPEquipRank:OnChanged(function(state)
    Thread("SCP.EquipRank", SafeLoop("SCP.EquipRank", FuncEquipRank), state)
end)
Toggles.SCPGems:OnChanged(function(state)
    Thread("SCP.Gems", SafeLoop("SCP.Gems", FuncGems), state)
end)
Toggles.SCPGroup:OnChanged(function(state)
    Thread("SCP.Group", SafeLoop("SCP.Group", FuncGroup), state)
end)
Toggles.SCPPotions:OnChanged(function(state)
    Thread("SCP.Potions", SafeLoop("SCP.Potions", FuncPotions), state)
end)
Toggles.SCPTickets:OnChanged(function(state)
    Thread("SCP.Tickets", SafeLoop("SCP.Tickets", FuncTickets), state)
end)
Toggles.SCPLizard:OnChanged(function(state)
    Thread("SCP.Lizard", SafeLoop("SCP.Lizard", FuncLizard), state)
end)
Toggles.SCPGunFire:OnChanged(function(state)
    Thread("SCP.GunFire", SafeLoop("SCP.GunFire", FuncGunFire), state)
end)
Toggles.SCPTears:OnChanged(SyncFarmThread)
Toggles.SCPLove:OnChanged(SyncFarmThread)
Toggles.SCPRunes:OnChanged(SyncFarmThread)

if CS then
    Thread("SCP.Stats", SafeLoop("SCP.Stats", FuncStats), true)
    if Toggles.SCPUpgrades.Value then
        Thread("SCP.Upgrades", SafeLoop("SCP.Upgrades", FuncUpgrades), true)
    end
    if Toggles.SCPRebirth.Value then
        Thread("SCP.Rebirth", SafeLoop("SCP.Rebirth", FuncRebirth), true)
    end
    if Toggles.SCPGun.Value then
        Thread("SCP.Gun", SafeLoop("SCP.Gun", FuncGun), true)
    end
    if Toggles.SCPRanks.Value then
        Thread("SCP.Ranks", SafeLoop("SCP.Ranks", FuncRanks), true)
    end
    if Toggles.SCPEquipRank.Value then
        Thread("SCP.EquipRank", SafeLoop("SCP.EquipRank", FuncEquipRank), true)
    end
    if Toggles.SCPGems.Value then
        Thread("SCP.Gems", SafeLoop("SCP.Gems", FuncGems), true)
    end
    if not (Upgrades and Walls and Currencies and Prestiges and Guns and Ranks and GemClaims and Net and BigNum) then
        Library:Notify("Some game modules failed to load.", 5)
    end
else
    Library:Notify("ClientState not found.", 5)
end
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
SaveManager:SetFolder("Yuri/SCPInc")
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
