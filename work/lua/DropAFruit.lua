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
    if type(Config) == "string" then
        return Toggles[Config], Options[Config .. "Value"]
    end
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
local realRS = game:GetService("ReplicatedStorage")
local realPlr = game:GetService("Players").LocalPlayer

Shared.Net = { Profile = nil, PlotRoll = nil }
Shared.Memo = { Sent = {}, RollTime = 0, DailyLast = nil, EquipCount = -1 }
Shared.RState = { Busy = false, Since = 0 }

local function ResolveModules()
    local M = {}
    M.Remotes = GetSafeModule(GetObject(realRS, "Shared"), "Remotes")
    M.ReplicaController = GetSafeModule(GetObject(realRS, "Shared.Modules.Replica"), "ReplicaController")
    M.Config = GetSafeModule(GetObject(realRS, "Shared"), "Config")
    M.EntityUtil = GetSafeModule(GetObject(realRS, "Shared.Modules.Game.Util"), "EntityUtil")
    M.UpgradeUtil = GetSafeModule(GetObject(realRS, "Shared.Modules.Game.Util"), "UpgradeUtil")
    M.RebirthUtil = GetSafeModule(GetObject(realRS, "Shared.Modules.Game.Util"), "RebirthUtil")
    M.InventoryUtil = GetSafeModule(GetObject(realRS, "Shared.Modules.Game.Util"), "InventoryUtil")
    M.IndexRewardUtil = GetSafeModule(GetObject(realRS, "Shared.Modules.Game.Util"), "IndexRewardUtil")
    M.AutoRollUtil = GetSafeModule(GetObject(realRS, "Shared.Modules.Game.Util"), "AutoRollUtil")
    M.Purchase = GetSafeModule(GetObject(realRS, "Shared.Client.Modules.Util"), "Purchase")
    M.Time = GetSafeModule(GetObject(realRS, "Shared.Modules.Core"), "Time")
    if M.Remotes and M.ReplicaController and M.Config then
        Shared.Modules = M
        return true
    end
    return false
end

local function FindReplica(classToken, matchFn)
    local M = Shared.Modules
    if not M then return nil end
    for _, replica in pairs(M.ReplicaController._replicas) do
        if replica.ClassToken == classToken and (not matchFn or matchFn(replica)) then
            return replica
        end
    end
    return nil
end

local function GetData()
    return Shared.Net.Profile and Shared.Net.Profile.Data or nil
end

local function RarityNames()
    local M = Shared.Modules
    if not M or not M.AutoRollUtil then return {} end
    local ok, entries = pcall(function() return M.AutoRollUtil.getEntries("Rarity") end)
    if not ok or not entries then return {} end
    local names = {}
    for _, entry in ipairs(entries) do
        table.insert(names, entry.Name)
    end
    return names
end

local function MutationNames()
    local M = Shared.Modules
    if not M or not M.AutoRollUtil then return {} end
    local ok, entries = pcall(function() return M.AutoRollUtil.getEntries("Mutation") end)
    if not ok or not entries then return {} end
    local names = {}
    for _, entry in ipairs(entries) do
        table.insert(names, entry.Name)
    end
    return names
end

ResolveModules()

Thread("Init", function()
    while not Library.Unloaded do
        if not Shared.Modules then
            ResolveModules()
        end
        if Shared.Modules then
            local M = Shared.Modules
            if not Shared.Net.Profile then
                Shared.Net.Profile = FindReplica(M.Config.Player.Profile.ClassToken, function(replica)
                    return replica.Tags and replica.Tags.Player == realPlr
                end)
            end
            if not Shared.Net.PlotRoll then
                Shared.Net.PlotRoll = FindReplica("PlotRoll", function(replica)
                    return replica.Data and replica.Data.Player == realPlr
                end)
            end
            if Shared.Net.Profile and Shared.Net.PlotRoll then
                break
            end
        end
        task.wait(1)
    end
end, true)

local function Func_AutoHole()
    while Toggles.AutoHole.Value do
        local ok, err = pcall(function()
            local M = Shared.Modules
            if not M then return end
            local now = os.clock()
            for id, at in pairs(Shared.Memo.Sent) do
                if now - at > 30 then
                    Shared.Memo.Sent[id] = nil
                end
            end
            for _, replica in pairs(M.ReplicaController._replicas) do
                if replica.ClassToken == "Fruit" then
                    local parent = replica.Parent
                    local owner = parent and parent.Data and parent.Data.Player
                    if owner == realPlr and not Shared.Memo.Sent[replica.Id] then
                        local state = replica.Data and replica.Data.State
                        if state == "Resting" or state == "Falling" or state == "Thrown" then
                            Shared.Memo.Sent[replica.Id] = now
                            replica:FireServer("SendToHole")
                        end
                    end
                end
            end
        end)
        if not ok then notyuri("AutoHole", err) end
        task.wait(0.5)
    end
end

local function Func_AutoRoll()
    while Toggles.AutoRoll.Value do
        local ok, err = pcall(function()
            local M = Shared.Modules
            local data = GetData()
            local plot = Shared.Net.PlotRoll
            if not M or not data or not plot or not plot.Data then return end
            local result = plot.Data.RollResult
            if result and result.Time ~= Shared.Memo.RollTime then
                Shared.Memo.RollTime = result.Time
                Shared.RState.Busy = false
                local rarities = AddMultiDropdown("RollRarities")
                local mutations = AddMultiDropdown("RollMutations")
                local nextBuy = nil
                for i, name in ipairs(result.Entities) do
                    local meta = M.Config.Entities[name]
                    if meta then
                        local mut = result.Mutations and result.Mutations[i] or nil
                        if rarities[meta.Rarity] or (mut and mutations[mut]) then
                            local cost = M.EntityUtil.getCost(name, mut)
                            local coin = data.Stats[cost.Type] or 0
                            if not M.InventoryUtil.isBackpackFull(data) and coin >= cost.Amount then
                                nextBuy = i
                                break
                            end
                        end
                    end
                end
                if nextBuy then
                    M.Remotes.plot.roll.buy:fire(nextBuy)
                end
                task.wait(M.Config.Roll.Auto.Delay or 0.35)
            end
            if not Shared.RState.Busy then
                Shared.RState.Busy = true
                Shared.RState.Since = os.clock()
                M.Remotes.plot.roll.pull:fire()
            elseif os.clock() - Shared.RState.Since > 8 then
                Shared.RState.Busy = false
            end
        end)
        if not ok then notyuri("AutoRoll", err) end
        task.wait(0.1)
    end
    Shared.RState.Busy = false
end

local function Func_AutoPlace()
    while Toggles.AutoPlace.Value do
        local ok, err = pcall(function()
            local M = Shared.Modules
            local data = GetData()
            if not M or not data then return end
            local limit = M.UpgradeUtil.getValue("entityPlaceLimit", data.Upgrades, data.RebirthUpgrades)
            local placed = 0
            for _, item in pairs(data.Inventory.List) do
                if item.Placed then
                    placed = placed + 1
                end
            end
            for id, item in pairs(data.Inventory.List) do
                if placed >= limit then break end
                if not item.Placed then
                    placed = placed + 1
                    M.Remotes.entity.place:fire(id)
                end
            end
        end)
        if not ok then notyuri("AutoPlace", err) end
        task.wait(1)
    end
end

local function Func_AutoUpgrade()
    while Toggles.AutoUpgrade.Value do
        local ok, err = pcall(function()
            local M = Shared.Modules
            local data = GetData()
            if not M or not data then return end
            local maxLevel = M.EntityUtil.getMaxLevel(data.Upgrades, data.RebirthUpgrades)
            local spend = 0
            for id, item in pairs(data.Inventory.List) do
                if item.Placed and (item.Level or 0) < maxLevel then
                    local cost = M.EntityUtil.getUpgradeCost(item.Name, item.Level, item.Mutation)
                    local coin = data.Stats[cost.Type] or 0
                    if coin - spend >= cost.Amount then
                        spend = spend + cost.Amount
                        M.Remotes.entity.upgrade:fire(id)
                    end
                end
            end
        end)
        if not ok then notyuri("AutoUpgrade", err) end
        task.wait(1)
    end
end

local function Func_AutoEquipBest()
    while Toggles.AutoEquipBest.Value do
        local ok, err = pcall(function()
            local M = Shared.Modules
            local data = GetData()
            if not M or not data then return end
            local count = 0
            for _ in pairs(data.Inventory.List) do
                count = count + 1
            end
            if count ~= Shared.Memo.EquipCount then
                Shared.Memo.EquipCount = count
                M.Remotes.entity.equipBest:fire()
            end
        end)
        if not ok then notyuri("AutoEquipBest", err) end
        task.wait(2)
    end
end

local function Func_AutoSell()
    while Toggles.AutoSell.Value do
        local ok, err = pcall(function()
            local M = Shared.Modules
            local data = GetData()
            if not M or not data then return end
            local wanted = AddMultiDropdown("SellRarities")
            if not next(wanted) then return end
            local batch = {}
            for id, item in pairs(data.Inventory.List) do
                if not item.Placed then
                    local meta = M.Config.Entities[item.Name]
                    if meta and wanted[meta.Rarity] then
                        table.insert(batch, id)
                    end
                end
            end
            local maxBatch = (M.Config.Entity and M.Config.Entity.Sell and M.Config.Entity.Sell.MaxBatch) or 200
            for i = 1, #batch, maxBatch do
                local chunk = {}
                table.move(batch, i, math.min(i + maxBatch - 1, #batch), 1, chunk)
                M.Remotes.entity.sell:fire(chunk)
            end
        end)
        if not ok then notyuri("AutoSell", err) end
        task.wait(2)
    end
end

local function Func_AutoBuyUpgrades()
    while Toggles.AutoBuyUpgrades.Value do
        local ok, err = pcall(function()
            local M = Shared.Modules
            local data = GetData()
            if not M or not data then return end
            if not (data.Tutorial and data.Tutorial.Completed) then return end
            local best = nil
            for id, node in pairs(M.Config.Upgrade.Tree) do
                if data.Upgrades[id] == nil and M.UpgradeUtil.isDependencyMet(node.Dependency, data.Upgrades) then
                    local cost = node.Cost
                    if cost and (not best or cost.Amount < best.Cost.Amount) then
                        local coin = data.Stats[cost.Type] or 0
                        if coin >= cost.Amount then
                            best = { Id = id, Cost = cost }
                        end
                    end
                end
            end
            if best then
                M.Remotes.upgrade:fire(best.Id)
            end
            for id, node in pairs(M.Config.Rebirth.Upgrade.List) do
                local level = data.RebirthUpgrades[id] or 0
                local required = node.RequiredRebirth or 0
                if level < #node.Levels and (data.Stats.Rebirth or 0) >= required then
                    local cost = node.Levels[level + 1].Cost
                    local crystal = data.Stats[cost.Type] or 0
                    if crystal >= cost.Amount then
                        M.Remotes.rebirth.upgrade:fire(id)
                        break
                    end
                end
            end
        end)
        if not ok then notyuri("AutoBuyUpgrades", err) end
        task.wait(2)
    end
end

local function Func_AutoRebirth()
    while Toggles.AutoRebirth.Value do
        local ok, err = pcall(function()
            local M = Shared.Modules
            local data = GetData()
            if not M or not data then return end
            if M.RebirthUtil.canRebirth(data) then
                M.Remotes.rebirth.perform:fire()
            end
        end)
        if not ok then notyuri("AutoRebirth", err) end
        task.wait(5)
    end
end

local function Func_AutoBlitz()
    while Toggles.AutoBlitz.Value do
        local ok, err = pcall(function()
            local M = Shared.Modules
            local data = GetData()
            if not M or not data or not M.Time then return end
            local last = (data.Time and data.Time.LastBlitz) or 0
            local cooldown = M.UpgradeUtil.getValue("blitzCooldown", data.Upgrades, data.RebirthUpgrades)
            if M.Time.getServerTime() - last >= cooldown then
                M.Remotes.blitz.activate:fire()
            end
        end)
        if not ok then notyuri("AutoBlitz", err) end
        task.wait(1)
    end
end

local function Func_AutoStars()
    while Toggles.AutoStars.Value do
        local ok, err = pcall(function()
            local M = Shared.Modules
            if not M or not M.Time then return end
            local weather = FindReplica(M.Config.Weather.ClassToken)
            local wdata = weather and weather.Data
            if not wdata or not wdata.Active then return end
            local active = M.Config.Weather[wdata.Active]
            local meteors = active and active.Meteors
            if not meteors then return end
            local collects = (wdata.Collects and wdata.Collects[realPlr.UserId]) or 0
            if collects >= meteors.MaxCollects then return end
            local stars = wdata.Stars
            if not stars then return end
            local now = M.Time.getServerTime()
            for starId, star in pairs(stars) do
                if star and not star.Collector and star.Position and (not star.Land or now >= star.Land) then
                    if TPTo(star.Position) then
                        task.wait(0.1)
                        M.Remotes.weather.collectStar:fire(starId)
                    end
                    break
                end
            end
        end)
        if not ok then notyuri("AutoStars", err) end
        task.wait(0.5)
    end
end

local function Func_AutoClaim()
    while Toggles.AutoClaim.Value do
        local ok, err = pcall(function()
            local M = Shared.Modules
            local data = GetData()
            if not M or not data or not data.Rewards or not M.Time then return end
            local daily = data.Rewards.Daily
            if daily and daily.LastClaim ~= Shared.Memo.DailyLast then
                local reset = M.Config.Rewards.Daily.Time.Reset
                if M.Time.getUTC() - daily.LastClaim >= reset then
                    Shared.Memo.DailyLast = daily.LastClaim
                    M.Remotes.reward.daily:fire()
                end
            end
            local group = data.Rewards.Group
            if group and not group.Claimed then
                M.Remotes.reward.group:fire()
            end
            local playtime = data.Rewards.Playtime
            if playtime then
                local elapsed = playtime.Start > 0 and (M.Time.getUTC() - playtime.Start) or 0
                for key, milestone in pairs(M.Config.Rewards.Playtime) do
                    if milestone and milestone.Time and elapsed >= milestone.Time
                        and not playtime.Claimed[tostring(key)] then
                        M.Remotes.reward.playtime:fire(key)
                    end
                end
            end
            if M.IndexRewardUtil then
                local okGoals, goals = pcall(function() return M.IndexRewardUtil.getGoals(data) end)
                if okGoals and goals then
                    for _, goal in ipairs(goals) do
                        if M.IndexRewardUtil.isReady(data, goal) then
                            M.Remotes.reward.index:fire(goal.Key)
                        end
                    end
                end
            end
        end)
        if not ok then notyuri("AutoClaim", err) end
        task.wait(30)
    end
end

local T1 = TB_Tabs.Autofarm.T1
T1:AddToggle("AutoHole", { Text = "Auto Send to Hole" })
T1:AddDivider()
T1:AddToggle("AutoRoll", { Text = "Auto Roll" })
AddMultiDropdown(T1, "RollRarities", { Text = "Roll Rarities", Values = RarityNames(), Default = {} })
AddMultiDropdown(T1, "RollMutations", { Text = "Roll Mutations", Values = MutationNames(), Default = {} })
T1:AddDivider()
T1:AddToggle("AutoPlace", { Text = "Auto Place" })
T1:AddToggle("AutoUpgrade", { Text = "Auto Upgrade" })
T1:AddToggle("AutoEquipBest", { Text = "Auto Equip Best" })
T1:AddToggle("AutoSell", { Text = "Auto Sell" })
AddMultiDropdown(T1, "SellRarities", { Text = "Sell Rarities", Values = RarityNames(), Default = {} })
T1:AddDivider()
T1:AddToggle("AutoBuyUpgrades", { Text = "Auto Buy Upgrades" })
T1:AddToggle("AutoRebirth", { Text = "Auto Rebirth" })
T1:AddDivider()
T1:AddToggle("AutoBlitz", { Text = "Auto Blitz" })
T1:AddToggle("AutoStars", { Text = "Auto Collect Stars" })
T1:AddDivider()
T1:AddToggle("AutoClaim", { Text = "Auto Claim Rewards" })

Toggles.AutoHole:OnChanged(function(state)
    Thread("AutoHole", SafeLoop("AutoHole", Func_AutoHole), state)
end)
Toggles.AutoRoll:OnChanged(function(state)
    Thread("AutoRoll", SafeLoop("AutoRoll", Func_AutoRoll), state)
end)
Toggles.AutoPlace:OnChanged(function(state)
    Thread("AutoPlace", SafeLoop("AutoPlace", Func_AutoPlace), state)
end)
Toggles.AutoUpgrade:OnChanged(function(state)
    Thread("AutoUpgrade", SafeLoop("AutoUpgrade", Func_AutoUpgrade), state)
end)
Toggles.AutoEquipBest:OnChanged(function(state)
    Thread("AutoEquipBest", SafeLoop("AutoEquipBest", Func_AutoEquipBest), state)
end)
Toggles.AutoSell:OnChanged(function(state)
    Thread("AutoSell", SafeLoop("AutoSell", Func_AutoSell), state)
end)
Toggles.AutoBuyUpgrades:OnChanged(function(state)
    Thread("AutoBuyUpgrades", SafeLoop("AutoBuyUpgrades", Func_AutoBuyUpgrades), state)
end)
Toggles.AutoRebirth:OnChanged(function(state)
    Thread("AutoRebirth", SafeLoop("AutoRebirth", Func_AutoRebirth), state)
end)
Toggles.AutoBlitz:OnChanged(function(state)
    Thread("AutoBlitz", SafeLoop("AutoBlitz", Func_AutoBlitz), state)
end)
Toggles.AutoStars:OnChanged(function(state)
    Thread("AutoStars", SafeLoop("AutoStars", Func_AutoStars), state)
end)
Toggles.AutoClaim:OnChanged(function(state)
    Thread("AutoClaim", SafeLoop("AutoClaim", Func_AutoClaim), state)
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
SaveManager:SetFolder("Yuri/Drop a Fruit")
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
