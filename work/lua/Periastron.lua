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
local CS = Services.CollectionService
Shared.Labels = Shared.Labels or {}
local Periastron = {
    Me = nil,
    MeMT = nil,
    OrigFire = nil,
    Shared = nil,
    ContractConfig = nil,
    UnitUpgradeConfig = nil,
    UnitStats = nil,
    TargetPriority = nil,
    MapConfig = nil,
    CrateConfig = nil,
    Replica = nil,
    DataController = nil,
    Place = "None",
    Cash = 0,
    Wave = 0,
    Speed = 1,
    Intermission = false,
    ReadyFiredWave = -1,
    SoldWave = -1,
    SoldDone = false,
    LeaveWave = -1,
    LeaveDone = false,
    Units = {},
    Deck = {},
    DeckLoaded = false,
    SlotPos = {},
    FailPos = {},
    UpgradesGiven = {},
    Match = {Over = false, Won = false, Started = false},
    Group = {JoinedAt = 0, LastChange = nil},
    QueueTicks = 0,
    Weather = nil,
}
local MState = {
    Rec = false,
    Rep = false,
    Cur = nil,
    Load = nil,
    Index = 1,
    Step = 0,
    Total = 0,
    LabelRef = nil,
    SelfFire = false,
    Hooked = false,
    PendingLabel = nil,
    Pending = {},
    Saved = false,
}
local MDir = "Yuri/PeriastronTD/Macros"
local StatsLabel = nil
local PosLabel = nil
local UpdatePosLabel = nil
local GAME_PLACE_ID = 109030368179494
local LOBBY_PLACE_ID = 132304466547289
local SLOT_COUNT = 6
local PlaceValid = false
local LobbyValid = false

local function DetectPlace()
    if game.PlaceId == GAME_PLACE_ID then
        Periastron.Place = "Game"
    elseif game.PlaceId == LOBBY_PLACE_ID then
        Periastron.Place = "Lobby"
    elseif workspace:FindFirstChild("PathScriptable") then
        Periastron.Place = "Game"
    elseif workspace:FindFirstChild("UnboxingCrates") or workspace:FindFirstChild("ContractsBoard") then
        Periastron.Place = "Lobby"
    else
        local deadline = os.clock() + 10
        while os.clock() < deadline and not Library.Unloaded do
            task.wait(0.5)
            if workspace:FindFirstChild("PathScriptable") then
                Periastron.Place = "Game"
                break
            end
            if workspace:FindFirstChild("UnboxingCrates") or workspace:FindFirstChild("ContractsBoard") then
                Periastron.Place = "Lobby"
                break
            end
        end
    end
    PlaceValid = Periastron.Place == "Game"
    LobbyValid = Periastron.Place == "Lobby"
    Library:Notify("Periastron: " .. Periastron.Place .. " place detected", 4)
    notyuri("[Periastron] place =", Periastron.Place, "PlaceId =", tostring(game.PlaceId))
end

local function BindMe()
    local shared = RS:FindFirstChild("Shared")
    if not shared then
        shared = RS:WaitForChild("Shared", 10)
    end
    if not shared then
        Library:Notify("Periastron: Shared folder missing - game features disabled", 6)
        notyuri("[Periastron] Shared folder missing")
        return false
    end
    local ok, meMod = pcall(function()
        return require(shared:WaitForChild("Vendor", 10):WaitForChild("Me", 10))
    end)
    if ok and type(meMod) == "table" and type(meMod.new) == "function" then
        Periastron.Me = meMod.new()
    end
    if not Periastron.Me then
        Library:Notify("Periastron: Me module failed - game features disabled", 6)
        notyuri("[Periastron] Me module failed")
        return false
    end
    local mt = getmetatable(Periastron.Me)
    if type(mt) == "table" and type(mt.Fire) == "function" then
        Periastron.MeMT = mt
        Periastron.OrigFire = mt.Fire
    end
    local okCfg, cfg = pcall(function()
        return require(shared:WaitForChild("Config", 10):WaitForChild("SharedConfig", 10))
    end)
    if okCfg and type(cfg) == "table" then
        Periastron.Shared = cfg
        Periastron.UnitUpgradeConfig = cfg.UnitUpgradeConfig
        Periastron.UnitStats = cfg.UnitStats
        Periastron.TargetPriority = cfg.TargetPriority
        Periastron.MapConfig = cfg.MapConfig
        Periastron.CrateConfig = cfg.CrateConfig
        Periastron.ContractConfig = cfg.ContractConfig
    end
    return true
end

local function FireGame(name, ...)
    local me = Periastron.Me
    if not me then return false end
    MState.SelfFire = true
    local ok, err
    if Periastron.OrigFire then
        ok, err = pcall(Periastron.OrigFire, me, name, ...)
    else
        ok, err = pcall(me.Fire, me, name, ...)
    end
    MState.SelfFire = false
    if not ok then
        notyuri("[Periastron] Fire", tostring(name), "FAILED:", tostring(err))
    end
    return ok
end

local function ListenGame(name, fn)
    local me = Periastron.Me
    if not me then return false end
    local ok, err = pcall(function()
        me:Listen(name, fn)
    end)
    if not ok then
        notyuri("[Periastron] Listen", tostring(name), "FAILED:", tostring(err))
    end
    return ok
end

local function GetReplicaData()
    local rep = Periastron.Replica
    if rep and type(rep.Data) == "table" then
        return rep.Data
    end
    return nil
end

local function BindReplica()
    local me = Periastron.Me
    if not (me and Periastron.DataController) then return end
    local dc = Periastron.DataController
    if type(dc.GetReplica) ~= "function" then return end
    local ok, rep = pcall(function()
        return dc:GetReplica()
    end)
    if ok and rep and type(rep) == "table" and type(rep.Data) == "table" then
        Periastron.Replica = rep
        notyuri("[Periastron] replica bound")
    else
        notyuri("[Periastron] replica not ready yet")
    end
end

local function FetchDataController()
    local me = Periastron.Me
    if not me then return end
    local dc
    pcall(function()
        dc = me:Get("DataController", false, false)
    end)
    if dc then
        Periastron.DataController = dc
        BindReplica()
        return
    end
    task.spawn(function()
        local deadline = os.clock() + 30
        while os.clock() < deadline and not Library.Unloaded do
            local got
            pcall(function()
                got = me:Get("DataController", false, true)
            end)
            if got then
                Periastron.DataController = got
                BindReplica()
                return
            end
            task.wait(1)
        end
        if not Periastron.DataController then
            notyuri("[Periastron] DataController never loaded (30s)")
        end
    end)
end

local function SanitizeDeck(equipped, limit)
    local out = {}
    local n = 0
    if type(equipped) == "table" then
        for i, name in ipairs(equipped) do
            if type(name) == "string" and i <= (limit or SLOT_COUNT) then
                n = n + 1
                out[n] = name
            end
        end
    end
    return out
end

local function RefreshDeck()
    local data = GetReplicaData()
    if not data then return false end
    local equipped = data.EquippedUnits
    if type(equipped) ~= "table" then return false end
    local limit = SLOT_COUNT
    if type(data.CardLimit) == "number" then
        limit = math.min(SLOT_COUNT, math.max(1, math.floor(data.CardLimit)))
    end
    local deck = SanitizeDeck(equipped, limit)
    if #deck == 0 then return false end
    local changed = not Periastron.DeckLoaded
    for i = 1, SLOT_COUNT do
        local nv = deck[i]
        if Periastron.Deck[i] ~= nv then
            Periastron.Deck[i] = nv
            changed = true
        end
    end
    Periastron.DeckLoaded = true
    return changed
end

local function GetSlotDisplayNames()
    local names = {}
    for i = 1, SLOT_COUNT do
        local name = Periastron.Deck[i]
        if name then
            table.insert(names, string.format("Slot %d: %s", i, name))
        else
            table.insert(names, string.format("Slot %d: (empty)", i))
        end
    end
    return names
end

local function SlotDisplayToNumber(display)
    local n = tonumber(tostring(display):match("^Slot (%d+)"))
    return n
end

local function GetPlaceCost(name)
    local cfg = Periastron.UnitUpgradeConfig
    if cfg and type(cfg.GetPlaceCost) == "function" then
        local ok, cost = pcall(cfg.GetPlaceCost, cfg, name, nil)
        if ok and type(cost) == "number" then
            return cost
        end
    end
    return 0
end

local function GetUpgradeCost(name, level)
    local cfg = Periastron.UnitUpgradeConfig
    if cfg and type(cfg.GetCost) == "function" then
        local ok, cost = pcall(cfg.GetCost, cfg, name, level or 0)
        if ok and type(cost) == "number" then
            return cost
        end
    end
    return 0
end

local function IsMaxedLevel(name, level)
    local cfg = Periastron.UnitUpgradeConfig
    if cfg and type(cfg.IsMaxed) == "function" then
        local ok, res = pcall(cfg.IsMaxed, cfg, name, level or 0)
        if ok then
            return res == true
        end
    end
    return (level or 0) >= 5
end

local function GetUnitRange(name)
    local stats = Periastron.UnitStats
    if type(stats) == "table" and type(stats[name]) == "table" and type(stats[name].Range) == "number" then
        return stats[name].Range
    end
    return 10
end

local function RegisterUnit(name, cframe, ownerUserId, unitId, upgrades)
    if type(unitId) ~= "number" then return end
    Periastron.Units[unitId] = {
        name = tostring(name),
        unitId = unitId,
        own = ownerUserId == Plr.UserId,
        upgrades = tonumber(upgrades) or 0,
        pos = (cframe and cframe.Position) or nil,
        model = nil,
    }
    task.spawn(function()
        for _ = 1, 12 do
            if Library.Unloaded then return end
            for _, m in ipairs(workspace:GetChildren()) do
                if m:IsA("Model") and m:GetAttribute("UnitID") == unitId then
                    local rec = Periastron.Units[unitId]
                    if rec then
                        rec.model = m
                        rec.pos = m:GetPivot().Position
                    end
                    return
                end
            end
            task.wait(0.25)
        end
    end)
end

local function CountOwnedByName(name)
    local n = 0
    for _, u in pairs(Periastron.Units) do
        if u.own and u.name == name then
            n = n + 1
        end
    end
    return n
end

local function HotbarIndexOf(name)
    for i, dn in ipairs(Periastron.Deck) do
        if dn == name then
            return i
        end
    end
    return nil
end

local function SlotForName(name)
    return HotbarIndexOf(name)
end

local function PosKey(pos)
    return string.format("%.1f_%.1f_%.1f", pos.X, pos.Y, pos.Z)
end

local function FailPosBlocked(pos)
    return Periastron.FailPos[PosKey(pos)] ~= nil
end

local function MarkFailPos(pos)
    Periastron.FailPos[PosKey(pos)] = tick()
end

local function ClearExpiredFailPos()
    local now = tick()
    for k, t in pairs(Periastron.FailPos) do
        if type(t) == "number" and now - t > 120 then
            Periastron.FailPos[k] = nil
        end
    end
end

local function IsSpotValid(pos)
    if not (pos and pos.X and pos.Y and pos.Z) then return false end
    local char = GetCharacter()
    local exclude = {}
    if char then
        table.insert(exclude, char)
    end
    local gridParts = {}
    pcall(function()
        for _, p in ipairs(CS:GetTagged("Grid")) do
            table.insert(gridParts, p)
        end
    end)
    local probeCF = CFrame.new(pos)
    local probeSize = Vector3.new(2.5, 5, 2.5)
    if #gridParts > 0 then
        local pathParams = OverlapParams.new()
        pathParams.FilterType = Enum.RaycastFilterType.Include
        pathParams.FilterDescendantsInstances = gridParts
        local hits = workspace:GetPartBoundsInBox(probeCF, probeSize, pathParams)
        if #hits > 0 then
            return false
        end
        for _, p in ipairs(gridParts) do
            table.insert(exclude, p)
        end
    end
    local obsParams = OverlapParams.new()
    obsParams.FilterType = Enum.RaycastFilterType.Exclude
    obsParams.FilterDescendantsInstances = exclude
    local obsHits = workspace:GetPartBoundsInBox(probeCF, probeSize, obsParams)
    if #obsHits > 0 then
        return false
    end
    return true
end

local function GetPathNodePositions()
    local nodes = {}
    local folder = workspace:FindFirstChild("PathScriptable")
    folder = folder and folder:FindFirstChild("Nodes")
    if folder then
        for _, n in ipairs(folder:GetChildren()) do
            local p = nil
            pcall(function()
                if n:IsA("BasePart") then
                    p = n.Position
                elseif n:IsA("Model") then
                    p = n:GetPivot().Position
                elseif n:IsA("Attachment") then
                    p = n.WorldPosition
                end
            end)
            if p then
                table.insert(nodes, p)
            end
        end
    end
    return nodes
end

local function FindSpotNear(center)
    if IsSpotValid(center) and not FailPosBlocked(center) then
        return center
    end
    local offsets = {
        Vector3.new(6, 0, 0), Vector3.new(-6, 0, 0), Vector3.new(0, 0, 6), Vector3.new(0, 0, -6),
        Vector3.new(6, 0, 6), Vector3.new(-6, 0, 6), Vector3.new(6, 0, -6), Vector3.new(-6, 0, -6),
        Vector3.new(12, 0, 0), Vector3.new(-12, 0, 0), Vector3.new(0, 0, 12), Vector3.new(0, 0, -12),
        Vector3.new(9, 0, 9), Vector3.new(-9, 0, -9), Vector3.new(9, 0, -9), Vector3.new(-9, 0, 9),
        Vector3.new(16, 0, 0), Vector3.new(-16, 0, 0), Vector3.new(0, 0, 16), Vector3.new(0, 0, -16),
        Vector3.new(12, 0, 12), Vector3.new(-12, 0, -12), Vector3.new(12, 0, -12), Vector3.new(-12, 0, 12),
    }
    for _, off in ipairs(offsets) do
        local cand = center + off
        if not FailPosBlocked(cand) and IsSpotValid(cand) then
            return cand
        end
    end
    return nil
end

local function AutoSpotForSlot(slot, name)
    local range = GetUnitRange(name)
    local dist = math.clamp(range * 0.7, 5, 12)
    local nodes = GetPathNodePositions()
    if #nodes == 0 then
        local char = GetCharacter()
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then
            return FindSpotNear(hrp.Position)
        end
        return nil
    end
    local step = math.max(1, math.floor(#nodes / 8))
    local i = (slot * 3) % #nodes + 1
    for _ = 1, #nodes do
        local node = nodes[i]
        local perp = Vector3.new(1, 0, 1)
        local cands = {
            node + perp * dist,
            node - perp * dist,
            node + Vector3.new(dist, 0, 0),
            node - Vector3.new(dist, 0, 0),
            node + Vector3.new(0, 0, dist),
            node - Vector3.new(0, 0, dist),
        }
        for _, cand in ipairs(cands) do
            if not FailPosBlocked(cand) and IsSpotValid(cand) then
                return cand
            end
        end
        i = ((i + step - 1) % #nodes) + 1
    end
    return nil
end

local function GetPlacePos(slot, name)
    local saved = Periastron.SlotPos[slot]
    if saved and saved.X and saved.Y and saved.Z then
        return FindSpotNear(saved)
    end
    return AutoSpotForSlot(slot, name)
end

local function LoadMDir()
    if not writefile then return end
    pcall(function()
        local built = ""
        for _, part in ipairs(MDir:split("/")) do
            built = (built == "") and part or (built .. "/" .. part)
            if not isfolder(built) then
                makefolder(built)
            end
        end
    end)
end

local function ListMacros()
    local names = {}
    local listf = listfiles or listfolder
    if not listf then return names end
    local ok, files = pcall(listf, MDir)
    if not ok or type(files) ~= "table" then return names end
    for _, path in ipairs(files) do
        if type(path) == "string" and path:sub(-5):lower() == ".json" then
            local fname = path:match("([^/\\]+)%.json$")
            if fname and fname ~= "" then
                table.insert(names, fname)
            end
        end
    end
    table.sort(names)
    return names
end

local function LoadMacro(name)
    if not name or name == "" or not readfile then return nil end
    local path = MDir .. "/" .. name .. ".json"
    local exists = false
    pcall(function()
        exists = isfile(path)
    end)
    if not exists then return nil end
    local ok, raw = pcall(readfile, path)
    if not ok or type(raw) ~= "string" or raw == "" then return nil end
    local data = nil
    pcall(function()
        data = HttpService:JSONDecode(raw)
    end)
    if type(data) ~= "table" then return nil end
    local entries = {}
    local i = 1
    while data[tostring(i)] do
        entries[i] = data[tostring(i)]
        i = i + 1
    end
    return {entries = entries}
end

local function SaveMacro(name, macro)
    if not name or name == "" or not writefile then return false end
    LoadMDir()
    local path = MDir .. "/" .. name .. ".json"
    local out = {}
    for i, entry in ipairs(macro.entries) do
        out[tostring(i)] = entry
    end
    local ok = pcall(function()
        writefile(path, HttpService:JSONEncode(out))
    end)
    return ok
end

local function UpdateMacroLabel(suffix)
    if not (MState.LabelRef and MState.LabelRef.SetText) then return end
    local txt
    if MState.Rec then
        txt = string.format("Recording [%d]%s", MState.Step, suffix and (" " .. suffix) or "")
    elseif MState.Rep then
        txt = string.format("Replaying [%d / %d]%s", MState.Index - 1, MState.Total, suffix and (" " .. suffix) or "")
    else
        txt = "Idle" .. (suffix and (" | " .. suffix) or "")
    end
    if MState.Rec then
        MState.PendingLabel = txt
    else
        local ok = pcall(function()
            MState.LabelRef:SetText(txt)
        end)
        if not ok then
            MState.PendingLabel = txt
        end
    end
end

local function RecordAct(kind, data)
    if not MState.Cur then return end
    MState.Step = MState.Step + 1
    local entry = {Type = kind, W = Periastron.Wave, M = Periastron.Cash, Seq = MState.Step}
    for k, val in pairs(data or {}) do
        entry[k] = val
    end
    table.insert(MState.Cur.entries, entry)
    UpdateMacroLabel(kind)
    notyuri("[Macro Rec]", kind, "wave", tostring(Periastron.Wave), "cash", tostring(Periastron.Cash))
end

local function InstallMacroHook()
    if MState.Hooked then return end
    local mt = Periastron.MeMT
    if type(mt) ~= "table" or type(mt.Fire) ~= "function" then
        notyuri("[Periastron] macro hook unavailable: no Me metatable")
        return
    end
    local orig = Periastron.OrigFire
    mt.Fire = function(self, name, ...)
        local rec = MState.Rec and not MState.SelfFire
        if rec and name == "PlaceUnit" then
            local a, b = ...
            if type(a) == "string" and b and b.Position and b.X then
                RecordAct("Place", {N = a, P = {b.X, b.Y, b.Z}})
            end
        elseif rec and name == "UpgradeUnit" then
            local a = ...
            if type(a) == "number" then
                local u = Periastron.Units[a]
                RecordAct("Upgrade", {N = u and u.name or "?"})
            end
        elseif rec and name == "SellUnit" then
            local a = ...
            if type(a) == "number" then
                local u = Periastron.Units[a]
                RecordAct("Sell", {N = u and u.name or "?"})
            end
        end
        return orig(self, name, ...)
    end
    MState.Hooked = true
    notyuri("[Periastron] macro hook installed on Me.Fire")
end

local function SendWebhook(title, description)
    if not Support.Webhook then return end
    local url = Options.WebhookURL and Options.WebhookURL.Value or ""
    if url == "" then return end
    pcall(function()
        local req = request or http_request
        req({
            Url = url,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = HttpService:JSONEncode({
                username = "Yuri",
                embeds = {
                    {
                        title = title,
                        description = description,
                        color = 0xFFB6C1,
                    },
                },
            }),
        })
    end)
end

local function QueueOnTeleportExec(code)
    if type(queue_on_teleport) == "function" then
        queue_on_teleport(code)
    elseif type(queueonteleport) == "function" then
        queueonteleport(code)
    end
end

local function QueueReexec()
    if not Support.QueueOnTeleport then
        notyuri("[Lobby] re-exec skipped: queue_on_teleport unsupported")
        return
    end
    local src = (Options.ExecSource and Options.ExecSource.Value) or ""
    if src == "" then
        notyuri("[Lobby] re-exec skipped: Exec Source empty")
        return
    end
    local code
    if src:sub(1, 7) == "http://" or src:sub(1, 8) == "https://" then
        code = string.format('local ok, err = pcall(function() loadstring(game:HttpGet("%s"))() end) if not ok then warn("[Yuri reexec] " .. tostring(err)) end', src)
    else
        code = string.format('local ok, err = pcall(function() if readfile and isfile and isfile("%s") then loadstring(readfile("%s"))() end end) if not ok then warn("[Yuri reexec] " .. tostring(err)) end', src, src)
    end
    QueueOnTeleportExec(code)
    Library:Notify("Re-exec queued after next teleport", 4)
    notyuri("[Lobby] re-exec queued")
end

local function ApplyGameSpeed()
    if not (Toggles.AutoSpeed and Toggles.AutoSpeed.Value and PlaceValid) then return end
    local target = tonumber((Options.SpeedTarget and Options.SpeedTarget.Value) or "2") or 2
    FireGame("SetGameSpeed", target)
end

local function DoSellAll()
    local sold = 0
    for unitId, u in pairs(Periastron.Units) do
        if u.own then
            if FireGame("SellUnit", unitId) then
                sold = sold + 1
            end
        end
    end
    if sold > 0 then
        Library:Notify("Auto Sell: sold " .. sold .. " units", 3)
        notyuri("[AutoSell] sold", tostring(sold))
    end
end

local function CheckWaveGates()
    local w = Periastron.Wave
    if Toggles.AutoSell and Toggles.AutoSell.Value and Options.AutoSellValue then
        local target = Options.AutoSellValue.Value or 0
        if target > 0 and not Periastron.SoldDone and w >= target then
            Periastron.SoldDone = true
            Periastron.SoldWave = w
            DoSellAll()
        end
    end
    if Toggles.AutoLeave and Toggles.AutoLeave.Value and Options.AutoLeaveValue then
        local target = Options.AutoLeaveValue.Value or 0
        if target > 0 and not Periastron.LeaveDone and w >= target then
            Periastron.LeaveDone = true
            Periastron.LeaveWave = w
            Library:Notify("Auto Leave: returning to lobby", 3)
            FireGame("RequestLobbyTeleport")
        end
    end
end

local function PlaceStep()
    if not (PlaceValid and not Periastron.Match.Over) then return false end
    RefreshDeck()
    local slots = {}
    for s = 1, SLOT_COUNT do
        if Periastron.Deck[s] then
            table.insert(slots, s)
        end
    end
    if #slots == 0 then return false end
    table.sort(slots, function(a, b)
        local oa = (Options["PlaceOrder" .. a] and Options["PlaceOrder" .. a].Value) or a
        local ob = (Options["PlaceOrder" .. b] and Options["PlaceOrder" .. b].Value) or b
        if oa ~= ob then
            return oa < ob
        end
        return a < b
    end)
    for _, slot in ipairs(slots) do
        local name = Periastron.Deck[slot]
        local waveGate = (Options["PlaceWave" .. slot] and Options["PlaceWave" .. slot].Value) or 0
        if Periastron.Wave >= waveGate then
            local limit = (Options["PlaceLimit" .. slot] and Options["PlaceLimit" .. slot].Value) or 0
            local have = CountOwnedByName(name)
            if limit <= 0 or have < limit then
                local pos = GetPlacePos(slot, name)
                if pos then
                    local cost = GetPlaceCost(name)
                    if Periastron.Cash >= cost then
                        if FireGame("PlaceUnit", name, CFrame.new(pos)) then
                            notyuri("[AutoPlace]", name, "at", PosKey(pos), "cost", tostring(cost))
                            return true
                        end
                    end
                else
                    MarkFailPos(Periastron.SlotPos[slot] or Vector3.new(0, 0, 0))
                end
            end
        end
    end
    return false
end

local function PickUpgradeTarget()
    local candidates = {}
    for _, u in pairs(Periastron.Units) do
        if u.own and not IsMaxedLevel(u.name, u.upgrades) then
            table.insert(candidates, u)
        end
    end
    if #candidates == 0 then return nil end
    local method = (Options.UpgradeMethod and Options.UpgradeMethod.Value) or "Lowest Level (Spread Upgrade)"
    if method:find("Lowest") then
        table.sort(candidates, function(a, b)
            if a.upgrades ~= b.upgrades then
                return a.upgrades < b.upgrades
            end
            local ia = HotbarIndexOf(a.name) or 99
            local ib = HotbarIndexOf(b.name) or 99
            return ia < ib
        end)
        return candidates[1]
    elseif method:find("Hotbar") then
        table.sort(candidates, function(a, b)
            local ia = HotbarIndexOf(a.name) or 99
            local ib = HotbarIndexOf(b.name) or 99
            if ia ~= ib then
                return ia < ib
            end
            return a.upgrades < b.upgrades
        end)
        return candidates[1]
    elseif method:find("Random") then
        return candidates[math.random(1, #candidates)]
    end
    table.sort(candidates, function(a, b)
        local sa = SlotForName(a.name) or 99
        local sb = SlotForName(b.name) or 99
        local oa = (Options["PlaceOrder" .. sa] and Options["PlaceOrder" .. sa].Value) or sa
        local ob = (Options["PlaceOrder" .. sb] and Options["PlaceOrder" .. sb].Value) or sb
        if oa ~= ob then
            return oa < ob
        end
        return a.upgrades < b.upgrades
    end)
    return candidates[1]
end

local function UpgradeLimitAllows(name)
    local slot = SlotForName(name)
    if not slot then return true end
    local limit = (Options["UpgradeLimit" .. slot] and Options["UpgradeLimit" .. slot].Value) or 0
    if limit <= 0 then return true end
    local given = Periastron.UpgradesGiven[name] or 0
    return given < limit
end

local function UpgradeStep()
    if not (PlaceValid and not Periastron.Match.Over) then return false end
    local target = PickUpgradeTarget()
    if not target then return false end
    if not UpgradeLimitAllows(target.name) then return false end
    local cost = GetUpgradeCost(target.name, target.upgrades)
    local reserve = (Options.UpgradeReserve and Options.UpgradeReserve.Value) or 0
    if Periastron.Cash - cost < reserve then return false end
    if Periastron.Cash < cost then return false end
    if FireGame("UpgradeUnit", target.unitId) then
        Periastron.UpgradesGiven[target.name] = (Periastron.UpgradesGiven[target.name] or 0) + 1
        notyuri("[AutoUpgrade]", target.name, "lvl", tostring(target.upgrades), "->", tostring(target.upgrades + 1), "cost", tostring(cost))
        return true
    end
    return false
end

local function FindTowerForEntry(entry)
    local best = nil
    for _, u in pairs(Periastron.Units) do
        if u.own and u.name == entry.N then
            if not best or u.upgrades < best.upgrades then
                best = u
            end
        end
    end
    return best
end

local function ProcessPendingSweep()
    local now = tick()
    for i = #MState.Pending, 1, -1 do
        local p = MState.Pending[i]
        if p.deadline and now > p.deadline then
            notyuri("[Macro] pending timeout:", p.kind, tostring(p.name))
            table.remove(MState.Pending, i)
        end
    end
end

local function ReplayEntryReady(entry)
    local mode = (Options.ReplayMode and Options.ReplayMode.Value) or "Wave"
    if mode == "Money" then
        return Periastron.Cash >= (entry.M or 0)
    end
    return Periastron.Wave >= (entry.W or 0)
end

local function DoMacroEntry(entry)
    if entry.Type == "Place" then
        local pos = Vector3.new(entry.P[1] or 0, entry.P[2] or 0, entry.P[3] or 0)
        local spot = FindSpotNear(pos)
        if spot then
            if FireGame("PlaceUnit", entry.N, CFrame.new(spot)) then
                table.insert(MState.Pending, {kind = "Place", name = entry.N, deadline = tick() + 6})
                return true
            end
        else
            MarkFailPos(pos)
        end
    elseif entry.Type == "Upgrade" then
        local u = FindTowerForEntry(entry)
        if u and not IsMaxedLevel(u.name, u.upgrades) then
            local cost = GetUpgradeCost(u.name, u.upgrades)
            if Periastron.Cash >= cost then
                if FireGame("UpgradeUnit", u.unitId) then
                    table.insert(MState.Pending, {kind = "Upgrade", name = entry.N, deadline = tick() + 6})
                    return true
                end
            end
        end
    elseif entry.Type == "Sell" then
        local u = FindTowerForEntry(entry)
        if u then
            if FireGame("SellUnit", u.unitId) then
                table.insert(MState.Pending, {kind = "Sell", name = entry.N, deadline = tick() + 6})
                return true
            end
        end
    end
    return false
end

local function ReplayStep()
    if not MState.Load or not MState.Load.entries then return false end
    local entries = MState.Load.entries
    if MState.Index > #entries then
        return false
    end
    ProcessPendingSweep()
    if #MState.Pending > 3 then
        return false
    end
    local entry = entries[MState.Index]
    if entry and ReplayEntryReady(entry) then
        if DoMacroEntry(entry) then
            MState.Index = MState.Index + 1
            UpdateMacroLabel()
            return true
        end
        MState.Index = MState.Index + 1
        return false
    end
    return false
end

local function ResetReplay()
    MState.Index = 1
    MState.Pending = {}
    UpdateMacroLabel()
end

local function GetPortal()
    local map = workspace:FindFirstChild("Map")
    local portals = map and map:FindFirstChild("Portals")
    if not portals then return nil end
    for _, p in ipairs(portals:GetChildren()) do
        local id = p:GetAttribute("PortalId")
        if type(id) == "number" then
            return p
        end
    end
    return nil
end

local function GetPortalEnterCFrame(portal)
    local enter = portal:FindFirstChild("PortalEnterCFrame", true)
    if enter then
        if enter:IsA("BasePart") then
            return enter.CFrame
        elseif enter:IsA("Attachment") then
            return enter.WorldCFrame
        elseif enter:IsA("Model") then
            return enter:GetPivot()
        end
    end
    return portal:GetPivot()
end

local function QueueStep()
    if not LobbyValid then return end
    local portal = GetPortal()
    if not portal then return end
    local portalId = portal:GetAttribute("PortalId")
    if type(portalId) ~= "number" then return end
    if Periastron.Group.JoinedAt > 0 and tick() - Periastron.Group.JoinedAt < 45 then return end
    local enterCF = GetPortalEnterCFrame(portal)
    local char = GetCharacter()
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp and (hrp.Position - enterCF.Position).Magnitude > 7 then
        TPTo(enterCF * CFrame.new(0, 0, 3))
    end
    Periastron.QueueTicks = Periastron.QueueTicks + 1
    local map = (Options.QueueMap and Options.QueueMap.Value) or "Join Existing"
    if map ~= "Join Existing" and Periastron.QueueTicks % 5 == 0 then
        local players = tonumber((Options.QueuePlayers and Options.QueuePlayers.Value) or "1") or 1
        Library:Notify("AutoQueue: creating group on " .. map, 3)
        FireGame("RequestCreateGroup", portalId, map, players)
    else
        FireGame("RequestJoinGroup", portalId)
    end
end

local function GetCrateCount(rarity)
    local data = GetReplicaData()
    if not data then return 0 end
    local inv = data.Inventory
    local crates = inv and inv.Crates
    if type(crates) == "table" then
        local c = crates[rarity]
        if type(c) == "number" then
            return c
        end
        if type(c) == "table" and type(c.Count) == "number" then
            return c.Count
        end
    end
    return 0
end

local function CrateStep()
    if not LobbyValid then return end
    local rarity = (Options.CrateRarity and Options.CrateRarity.Value) or "Common"
    local amount = tonumber((Options.CrateAmount and Options.CrateAmount.Value) or "1") or 1
    local have = GetCrateCount(rarity)
    if have <= 0 then return end
    local opened = 0
    while opened < amount and have - opened > 0 do
        if FireGame("RequestOpenCrate", rarity) then
            opened = opened + 1
        end
        task.wait(0.6)
    end
    if opened > 0 then
        notyuri("[AutoCrate] opened", tostring(opened), rarity)
    end
end

local function ContractStep()
    if not LobbyValid then return end
    local data = GetReplicaData()
    if not data then return end
    local contracts = data.Contracts
    if type(contracts) ~= "table" then return end
    local cfg = Periastron.ContractConfig
    if not (cfg and type(cfg.get) == "function" and type(cfg.isComplete) == "function") then return end
    for _, kind in ipairs({"Hourly", "Daily", "Weekly"}) do
        local section = contracts[kind]
        if type(section) == "table" and type(section.Slots) == "table" then
            for idx, slot in ipairs(section.Slots) do
                if type(slot) == "table" and not slot.Claimed then
                    local ok, c = pcall(cfg.get, cfg, slot.Id)
                    if ok and c then
                        local okC, done = pcall(cfg.isComplete, cfg, c, slot)
                        if okC and done then
                            if FireGame("ClaimContract", kind, idx) then
                                notyuri("[Contracts] claimed", kind, tostring(idx))
                            end
                            task.wait(0.4)
                        end
                    end
                end
            end
        end
    end
end

local function PlaceLoop()
    while Toggles.AutoPlace.Value do
        local ok, err = pcall(PlaceStep)
        if not ok then
            notyuri("[AutoPlace] step error:", tostring(err))
        end
        if Toggles.PlaceAndUpgrade and Toggles.PlaceAndUpgrade.Value then
            local okU, errU = pcall(UpgradeStep)
            if not okU then
                notyuri("[AutoUpgrade] step error:", tostring(errU))
            end
        end
        local delay = (Options.PlaceDelay and Options.PlaceDelay.Value) or 1
        ClearExpiredFailPos()
        task.wait(math.max(0.4, delay))
    end
end

local function UpgradeLoop()
    while Toggles.AutoUpgrade.Value do
        local ok, err = pcall(UpgradeStep)
        if not ok then
            notyuri("[AutoUpgrade] step error:", tostring(err))
        end
        task.wait(0.8)
    end
end

local function ReplayLoop()
    while Toggles.LoadMacro.Value do
        local ok, err = pcall(ReplayStep)
        if not ok then
            notyuri("[Macro] replay step error:", tostring(err))
        end
        task.wait(0.3)
    end
end

local function QueueLoop()
    while Toggles.AutoQueue.Value do
        local ok, err = pcall(QueueStep)
        if not ok then
            notyuri("[AutoQueue] step error:", tostring(err))
        end
        task.wait(6)
    end
end

local function CrateLoop()
    while Toggles.AutoCrate.Value do
        local ok, err = pcall(CrateStep)
        if not ok then
            notyuri("[AutoCrate] step error:", tostring(err))
        end
        task.wait(2)
    end
end

local function ContractLoop()
    while Toggles.AutoClaimContracts.Value do
        local ok, err = pcall(ContractStep)
        if not ok then
            notyuri("[Contracts] step error:", tostring(err))
        end
        task.wait(5)
    end
end

local function OnMatchEnd(won)
    Periastron.Match.Over = true
    Periastron.Match.Won = won
    local label = won and "Victory" or "Defeat"
    local desc = string.format("Place: %s | Wave: %d | Cash: %s", Periastron.Place, Periastron.Wave, CommaFormat(Periastron.Cash))
    SendWebhook("Periastron TD: " .. label, desc)
    Library:Notify("Match " .. label .. " (wave " .. Periastron.Wave .. ")", 5)
    if not won then
        local mode = (Options.DefeatMode and Options.DefeatMode.Value) or "Replay Round"
        if mode == "Return to Lobby" then
            task.delay(2, function()
                FireGame("RequestLobbyTeleport")
            end)
        end
    end
end

local function OnRoundRestarted()
    Periastron.Units = {}
    Periastron.UpgradesGiven = {}
    Periastron.SoldWave = -1
    Periastron.SoldDone = false
    Periastron.LeaveWave = -1
    Periastron.LeaveDone = false
    Periastron.Match.Over = false
    Periastron.Match.Started = true
    Periastron.ReadyFiredWave = -1
    ResetReplay()
    if Toggles.AutoReplay and Toggles.AutoReplay.Value and Toggles.LoadMacro and Toggles.LoadMacro.Value then
        MState.Rep = true
        UpdateMacroLabel()
    end
    ApplyGameSpeed()
end

local function InstallGameStateListeners()
    ListenGame("UpdateCash", function(cash)
        if type(cash) == "number" then
            Periastron.Cash = cash
        end
    end)
    ListenGame("SetWave", function(wave)
        local w = tonumber(wave)
        if w then
            Periastron.Wave = w
            Periastron.Intermission = false
            CheckWaveGates()
        end
    end)
    ListenGame("WaveIntermission", function(data)
        Periastron.Intermission = true
        if Toggles.AutoReady and Toggles.AutoReady.Value then
            if Periastron.ReadyFiredWave ~= Periastron.Wave then
                Periastron.ReadyFiredWave = Periastron.Wave
                task.delay(0.5, function()
                    FireGame("ReadyWave")
                end)
            end
        end
    end)
    ListenGame("SkipState", function(state)
        if Toggles.AutoVoteSkip and Toggles.AutoVoteSkip.Value then
            if type(state) ~= "table" or state.active ~= false then
                FireGame("VoteSkip", true)
            end
        end
    end)
    ListenGame("GameSpeedChanged", function(step)
        local s = tonumber(step)
        if s then
            Periastron.Speed = s
        end
    end)
    ListenGame("ReplicateUnit", function(name, cframe, ownerUserId, unitId, upgrades)
        RegisterUnit(name, cframe, ownerUserId, unitId, upgrades)
        for i = #MState.Pending, 1, -1 do
            local p = MState.Pending[i]
            if p.kind == "Place" and p.name == name then
                table.remove(MState.Pending, i)
            end
        end
    end)
    ListenGame("RemoveUnit", function(unitId)
        Periastron.Units[unitId] = nil
        for i = #MState.Pending, 1, -1 do
            if MState.Pending[i].kind == "Sell" then
                table.remove(MState.Pending, i)
            end
        end
    end)
    ListenGame("UnitUpgraded", function(unitId, level)
        local u = Periastron.Units[unitId]
        if u then
            u.upgrades = tonumber(level) or u.upgrades
        end
        for i = #MState.Pending, 1, -1 do
            if MState.Pending[i].kind == "Upgrade" then
                table.remove(MState.Pending, i)
            end
        end
    end)
    ListenGame("RoundRestarted", function()
        OnRoundRestarted()
    end)
    ListenGame("Win", function()
        OnMatchEnd(true)
    end)
    ListenGame("GameOver", function()
        OnMatchEnd(false)
    end)
    ListenGame("UpdateCardCounts", function() end)
    FireGame("RequestCash")
end

local function InstallLobbyStateListeners()
    ListenGame("PortalGroupChanged", function(a, b)
        Periastron.Group.LastChange = {a = a, b = b, t = tick()}
        if type(a) == "number" and a ~= 0 then
            Periastron.Group.JoinedAt = tick()
        end
    end)
end

Tabs.AutoPlay = Window:AddTab("Auto Play")
Tabs.Webhook = Window:AddTab("Webhook")
TB_Tabs.Autofarm.T2 = TB.Main.Left.Autofarm:AddTab("Macro")
TB_Tabs.Autofarm.T3 = TB.Main.Left.Autofarm:AddTab("Lobby")
TB_Tabs.Autofarm2.T2 = TB.Main.Right.Autofarm:AddTab("LobbyConfig")
local APLeft = Tabs.AutoPlay:AddLeftGroupbox("Auto Play")
local APRight = Tabs.AutoPlay:AddRightGroupbox("Limits")
local GB_Webhook = Tabs.Webhook:AddLeftGroupbox("Webhook")

APLeft:AddToggle("AutoPlace", { Text = "Auto Place" })
APLeft:AddToggle("AutoUpgrade", { Text = "Auto Upgrade" })
APLeft:AddDropdown("UpgradeMethod", {
    Text = "Upgrade Method",
    Values = {
        "Lowest Level (Spread Upgrade)",
        "Hotbar Left to Right (until Max)",
        "Randomize",
        "Customize (Slot Order)",
    },
    Default = "Lowest Level (Spread Upgrade)",
})
APLeft:AddToggle("PlaceAndUpgrade", { Text = "Place and Upgrade" })
AddSliderToggle({ Group = APLeft, Id = "AutoSell", Text = "Auto Sell at Wave", Default = 10, Min = 0, Max = 100, Rounding = 0 })
APLeft:AddSlider("UpgradeReserve", {
    Text = "Cash Reserve",
    Default = 0,
    Min = 0,
    Max = 100000,
    Rounding = 0,
    Compact = true,
})
APLeft:AddSlider("PlaceDelay", {
    Text = "Place Delay (s)",
    Default = 1,
    Min = 0.5,
    Max = 10,
    Rounding = 1,
    Compact = true,
})
APLeft:AddDivider()
APLeft:AddDropdown("SetSlotSelect", {
    Text = "Set Slot Position",
    Values = GetSlotDisplayNames(),
    Default = GetSlotDisplayNames()[1] or "",
})
APLeft:AddButton({
    Text = "Set Slot Position",
    Func = function()
        local val = (Options.SetSlotSelect and Options.SetSlotSelect.Value) or ""
        local slot = SlotDisplayToNumber(val)
        if slot then
            local char = GetCharacter()
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp then
                Periastron.SlotPos[slot] = hrp.Position
                Library:Notify("Slot " .. slot .. " position set", 3)
                UpdatePosLabel()
                return
            end
        end
        Library:Notify("Select a slot (and spawn in) first", 3)
    end,
})
APLeft:AddButton({
    Text = "Save Position for All Slots",
    Func = function()
        local char = GetCharacter()
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then
            Library:Notify("No character", 3)
            return
        end
        for s = 1, SLOT_COUNT do
            Periastron.SlotPos[s] = hrp.Position
        end
        Library:Notify("All slot positions set", 3)
        UpdatePosLabel()
    end,
})
APLeft:AddDivider()
do
    local function GetResetSlotValues()
        local names = GetSlotDisplayNames()
        table.insert(names, "All Slots")
        return names
    end
    APLeft:AddDropdown("ResetSlotSelect", {
        Text = "Reset Slot Position",
        Values = GetResetSlotValues(),
        Default = "All Slots",
    })
end
APLeft:AddButton({
    Text = "Reset Position",
    Func = function()
        local val = (Options.ResetSlotSelect and Options.ResetSlotSelect.Value) or "All Slots"
        if val == "All Slots" then
            Periastron.SlotPos = {}
        else
            local slot = SlotDisplayToNumber(val)
            if slot then
                Periastron.SlotPos[slot] = nil
            end
        end
        Periastron.FailPos = {}
        Library:Notify("Positions reset", 3)
        UpdatePosLabel()
    end,
})
PosLabel = SafeLabel(APLeft, "Positions", "No positions set")
StatsLabel = SafeLabel(APLeft, "Stats", "Detecting place...")
UpdatePosLabel = function()
    if not (PosLabel and PosLabel.SetText) then return end
    local n = 0
    for _ in pairs(Periastron.SlotPos) do
        n = n + 1
    end
    local txt
    if n == 0 then
        txt = "No positions set"
    else
        txt = string.format("%d position(s) set", n)
    end
    pcall(function()
        PosLabel.SetText(txt)
    end)
end

APRight:AddLabel("Place Order per Slot", true)
for i = 1, SLOT_COUNT do
    APRight:AddSlider("PlaceOrder" .. i, {
        Text = "Slot " .. i,
        Default = i,
        Min = 1,
        Max = SLOT_COUNT,
        Rounding = 0,
        Compact = true,
    })
end
APRight:AddDivider()
APRight:AddLabel("Place Wave per Slot", true)
for i = 1, SLOT_COUNT do
    APRight:AddSlider("PlaceWave" .. i, {
        Text = "Slot " .. i,
        Default = 0,
        Min = 0,
        Max = 50,
        Rounding = 0,
        Compact = true,
    })
end
APRight:AddDivider()
APRight:AddLabel("Place Limit per Slot", true)
for i = 1, SLOT_COUNT do
    APRight:AddSlider("PlaceLimit" .. i, {
        Text = "Slot " .. i,
        Default = 0,
        Min = 0,
        Max = 10,
        Rounding = 0,
        Compact = true,
    })
end
APRight:AddDivider()
APRight:AddLabel("Upgrade Limit per Slot", true)
for i = 1, SLOT_COUNT do
    APRight:AddSlider("UpgradeLimit" .. i, {
        Text = "Slot " .. i,
        Default = 0,
        Min = 0,
        Max = 30,
        Rounding = 0,
        Compact = true,
    })
end

TB_Tabs.Autofarm.T1:AddToggle("AutoVoteSkip", { Text = "Auto Vote Skip" })
TB_Tabs.Autofarm.T1:AddToggle("AutoReady", { Text = "Auto Ready Wave" })
TB_Tabs.Autofarm.T1:AddToggle("AutoSpeed", { Text = "Auto Game Speed" })
TB_Tabs.Autofarm.T1:AddToggle("AutoReplay", { Text = "Auto Replay Macro" })
TB_Tabs.Autofarm.T1:AddToggle("AutoLeave", { Text = "Auto Leave" })

TB_Tabs.Autofarm.T2:AddDropdown("MacroSelected", {
    Text = "Select File",
    Values = ListMacros(),
    Default = ListMacros()[1] or "",
})
TB_Tabs.Autofarm.T2:AddInput("FileName", {
    Text = "File Name",
    Default = "",
    Placeholder = "yuriyuri",
})
TB_Tabs.Autofarm.T2:AddDropdown("ReplayMode", {
    Text = "Replay Mode",
    Values = {"Wave", "Money"},
    Default = "Wave",
})
TB_Tabs.Autofarm.T2:AddToggle("MacroRecord", {
    Text = "Record Macro",
    Default = false,
})
TB_Tabs.Autofarm.T2:AddToggle("LoadMacro", {
    Text = "Play Macro",
    Default = false,
})
MState.LabelRef = SafeLabel(TB_Tabs.Autofarm.T2, "Macro", "Idle")

TB_Tabs.Autofarm.T3:AddToggle("AutoQueue", { Text = "Auto Queue (Portal)" })
TB_Tabs.Autofarm.T3:AddToggle("AutoCrate", { Text = "Auto Open Crates" })
TB_Tabs.Autofarm.T3:AddToggle("AutoClaimContracts", { Text = "Auto Claim Contracts" })
TB_Tabs.Autofarm.T3:AddToggle("AutoReexec", { Text = "Auto Re-Exec After Teleport" })
TB_Tabs.Autofarm.T3:AddInput("ExecSource", {
    Text = "Exec Source (URL or path)",
    Default = "",
    Placeholder = "https://... or workspace/file path",
})

TB_Tabs.Autofarm2.T1:AddSlider("AutoLeaveValue", {
    Text = "Leave at Wave",
    Default = 30,
    Min = 0,
    Max = 100,
    Rounding = 0,
    Compact = true,
})
TB_Tabs.Autofarm2.T1:AddDropdown("SpeedTarget", {
    Text = "Speed Target",
    Values = {"1", "2", "3", "4"},
    Default = "2",
})
TB_Tabs.Autofarm2.T1:AddDropdown("DefeatMode", {
    Text = "On Defeat",
    Values = {"Replay Round", "Return to Lobby"},
    Default = "Replay Round",
})

local mapValues = {"Join Existing"}
if Periastron.MapConfig and type(Periastron.MapConfig.MAPS) == "table" then
    local mapNames = {}
    for mapName in pairs(Periastron.MapConfig.MAPS) do
        table.insert(mapNames, mapName)
    end
    table.sort(mapNames)
    for _, m in ipairs(mapNames) do
        table.insert(mapValues, m)
    end
end
TB_Tabs.Autofarm2.T2:AddDropdown("QueueMap", {
    Text = "Map",
    Values = mapValues,
    Default = "Join Existing",
})
TB_Tabs.Autofarm2.T2:AddDropdown("QueuePlayers", {
    Text = "Players",
    Values = {"1", "2", "3", "4"},
    Default = "1",
})
TB_Tabs.Autofarm2.T2:AddDivider()
TB_Tabs.Autofarm2.T2:AddDropdown("CrateRarity", {
    Text = "Crate Rarity",
    Values = {"Common", "Rare", "Epic", "Legendary"},
    Default = "Common",
})
TB_Tabs.Autofarm2.T2:AddDropdown("CrateAmount", {
    Text = "Open Amount",
    Values = {"1", "5", "10"},
    Default = "1",
})

GB_Webhook:AddInput("WebhookURL", {
    Text = "Webhook URL",
    Default = "",
    Placeholder = "https://discord.com/api/webhooks/...",
})
GB_Webhook:AddButton({
    Text = "Test Webhook",
    Func = function()
        SendWebhook("Periastron TD", "Webhook test from " .. tostring(Plr.Name))
        Library:Notify("Webhook test sent", 3)
    end,
})

local function RefreshQueueMapDropdown()
    if not (Options.QueueMap and Periastron.MapConfig) then return end
    local mapNames = {}
    for mapName in pairs(Periastron.MapConfig.MAPS or {}) do
        table.insert(mapNames, mapName)
    end
    table.sort(mapNames)
    local values = {"Join Existing"}
    for _, m in ipairs(mapNames) do
        table.insert(values, m)
    end
    Options.QueueMap:SetValues(values)
end

local function RefreshSlotDropdowns()
    local names = GetSlotDisplayNames()
    if Options.SetSlotSelect then
        Options.SetSlotSelect:SetValues(names)
    end
    if Options.ResetSlotSelect then
        local resetNames = {}
        for _, n in ipairs(names) do
            table.insert(resetNames, n)
        end
        table.insert(resetNames, "All Slots")
        Options.ResetSlotSelect:SetValues(resetNames)
    end
    return Periastron.Deck[1] ~= nil
end

task.spawn(function()
    local deadline = os.clock() + 20
    while os.clock() < deadline and not Library.Unloaded do
        local changed = RefreshDeck()
        if changed ~= false and Periastron.Deck[1] ~= nil then
            RefreshSlotDropdowns()
            break
        end
        task.wait(1)
    end
end)

task.spawn(function()
    while not Library.Unloaded do
        task.wait(3)
        if RefreshDeck() and Periastron.Deck[1] ~= nil then
            RefreshSlotDropdowns()
        end
        RefreshQueueMapDropdown()
    end
end)

Toggles.AutoPlace:OnChanged(function(state)
    Thread("Game.AutoPlace", PlaceLoop, state)
end)
Toggles.AutoUpgrade:OnChanged(function(state)
    Thread("Game.AutoUpgrade", UpgradeLoop, state)
end)
Toggles.LoadMacro:OnChanged(function(state)
    if state then
        local name = (Options.MacroSelected and Options.MacroSelected.Value) or ""
        MState.Load = LoadMacro(name)
        MState.Index = 1
        MState.Total = MState.Load and #MState.Load.entries or 0
        MState.Rep = true
        MState.Pending = {}
        if not MState.Load then
            Library:Notify("Macro not found: " .. tostring(name), 4)
        end
        UpdateMacroLabel()
    else
        MState.Rep = false
        UpdateMacroLabel()
    end
end)
Toggles.MacroRecord:OnChanged(function(state)
    if state then
        MState.Cur = {entries = {}}
        MState.Step = 0
        MState.Rec = true
        Library:Notify("Recording macro actions", 3)
    else
        MState.Rec = false
        if MState.Cur and #MState.Cur.entries > 0 then
            local name = (Options.FileName and Options.FileName.Value) or ""
            if name == "" then
                name = (Options.MacroSelected and Options.MacroSelected.Value) or ""
            end
            if name ~= "" then
                if SaveMacro(name, MState.Cur) then
                    Library:Notify("Macro saved: " .. name .. " (" .. #MState.Cur.entries .. " actions)", 4)
                    if Options.MacroSelected then
                        Options.MacroSelected:SetValues(ListMacros())
                        Options.MacroSelected:SetValue(name)
                    end
                else
                    Library:Notify("Macro save failed (file IO?)", 4)
                end
            else
                Library:Notify("Macro not saved: no file name", 4)
            end
        end
        MState.Cur = nil
        UpdateMacroLabel()
    end
end)
Toggles.AutoQueue:OnChanged(function(state)
    Periastron.QueueTicks = 0
    Thread("Lobby.AutoQueue", QueueLoop, state)
end)
Toggles.AutoCrate:OnChanged(function(state)
    Thread("Lobby.AutoCrate", CrateLoop, state)
end)
Toggles.AutoClaimContracts:OnChanged(function(state)
    Thread("Lobby.AutoClaimContracts", ContractLoop, state)
end)
Toggles.AutoSpeed:OnChanged(function(state)
    if state then
        ApplyGameSpeed()
    end
end)
Toggles.AutoReexec:OnChanged(function(state)
    if state then
        QueueReexec()
    end
end)

task.spawn(function()
    while not Library.Unloaded do
        if StatsLabel and StatsLabel.SetText then
            local units = 0
            for _, u in pairs(Periastron.Units) do
                if u.own then
                    units = units + 1
                end
            end
            local posCount = 0
            for _ in pairs(Periastron.SlotPos) do
                posCount = posCount + 1
            end
            local txt = string.format(
                "%s | Wave %d | Cash %s | Units %d | Pos %d/6 | Speed %dx",
                Periastron.Place,
                Periastron.Wave,
                Abbreviate(Periastron.Cash),
                units,
                posCount,
                Periastron.Speed
            )
            pcall(function()
                StatsLabel:SetText(txt)
            end)
        end
        if MState.Rec and MState.PendingLabel and MState.LabelRef and MState.LabelRef.SetText then
            local txt = MState.PendingLabel
            MState.PendingLabel = nil
            pcall(function()
                MState.LabelRef.SetText(txt)
            end)
        end
        task.wait(0.5)
    end
end)

task.spawn(function()
    if not BindMe() then
        return
    end
    DetectPlace()
    if PlaceValid then
        InstallGameStateListeners()
    end
    if LobbyValid then
        InstallLobbyStateListeners()
    end
    FetchDataController()
    InstallMacroHook()
    RefreshQueueMapDropdown()
    if PlaceValid then
        RefreshDeck()
        RefreshSlotDropdowns()
    end
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
SaveManager:SetFolder("Yuri/PeriastronTD")
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
