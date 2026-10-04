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

Shared.Potato = {
    Modules = nil,
    Pile = nil,
    Session = nil,
    SessionDead = false,
    Joined = false,
    LastCreate = 0,
    Memo = { Daily = 0, Group = 0, Roll = 0 },
}

local function ResolveModules()
    local M = {}
    M.Packets = GetSafeModule(GetObject(realRS, "Modules.Resources"), "Packets")
    M.Pile = GetSafeModule(GetObject(realRS, "Shared"), "PotatoPileShared")
    M.Kinds = GetSafeModule(GetObject(realRS, "Shared"), "PotatoKindShared")
    M.Tools = GetSafeModule(GetObject(realRS, "Shared"), "ToolUpgradeShared")
    M.PeelTools = GetSafeModule(GetObject(realRS, "Shared"), "PeelToolShared")
    M.Carry = GetSafeModule(GetObject(realRS, "Shared"), "CarryUpgradeShared")
    M.Lobby = GetSafeModule(GetObject(realRS, "Shared"), "LobbyUpgradeShared")
    M.Class = GetSafeModule(GetObject(realRS, "Shared"), "ClassShared")
    M.Daily = GetSafeModule(GetObject(realRS, "Shared"), "DailyRewardShared")
    M.Table = GetSafeModule(GetObject(realRS, "Shared"), "PotatoTableShared")
    M.Store = GetSafeModule(GetObject(realRS, "Shared"), "StoreShared")
    M.Queue = GetSafeModule(GetObject(realRS, "Shared"), "QueueShared")
    M.Keys = GetSafeModule(GetObject(realRS, "Shared"), "KeyShared")
    M.Group = GetSafeModule(GetObject(realRS, "Shared"), "GroupRewardShared")
    M.PlayerState = GetSafeModule(GetObject(realRS, "Shared"), "PlayerStateShared")
    M.ToolCtl = GetSafeModule(GetObject(realRS, "Controllers"), "ToolEquipController")
    if M.Packets and M.Pile and M.Kinds and M.Tools and M.PeelTools and M.Carry and M.Lobby and M.Class and M.Daily and M.Table and M.Store and M.Queue and M.Keys and M.Group and M.PlayerState and M.ToolCtl then
        Shared.Potato.Modules = M
        return true
    end
    return false
end

local function GetState()
    local M = Shared.Potato.Modules
    if not M then return nil, nil end
    local state = M.PlayerState.TryGetPlayerState(realPlr)
    if not state or not state._SaveDataLoaded then return nil, nil end
    return M, state
end

local function GetMachines()
    local M = Shared.Potato.Modules
    if not M then return nil end
    local map = workspace:FindFirstChild("Map")
    local folder = map and map:FindFirstChild(M.Table.MACHINES_FOLDER_NAME)
    return folder
end

local function GetCrateArea(name)
    local M = Shared.Potato.Modules
    if not M then return nil end
    local folder = GetMachines()
    local crate = folder and folder:FindFirstChild(name)
    local area = crate and crate:FindFirstChild(M.Table.CRATE_AREA_NAME)
    if area and area:IsA("BasePart") then
        return area, crate
    end
    return nil
end

local function CountAt(inst)
    local M = Shared.Potato.Modules
    if not M or not inst then return 0 end
    return M.Table.GetCount(inst) or 0
end

local function AreaPrompt(name, promptName)
    local area = GetCrateArea(name)
    local prompt = area and area:FindFirstChild(promptName)
    if prompt and prompt:IsA("ProximityPrompt") then
        return prompt
    end
    return nil
end

local function MachineRoot(machineName, rootName)
    local folder = GetMachines()
    local machine = folder and folder:FindFirstChild(machineName)
    local root = machine and machine:FindFirstChild(rootName)
    if root and root:IsA("BasePart") then
        return root, machine
    end
    return nil
end

local function MachinePrompt(machineName, rootName, promptName)
    local root = MachineRoot(machineName, rootName)
    local prompt = root and root:FindFirstChild(promptName)
    if prompt and prompt:IsA("ProximityPrompt") then
        return prompt
    end
    return nil
end

local function MachinePricePrompt(machineName)
    local M = Shared.Potato.Modules
    local folder = GetMachines()
    local machine = folder and folder:FindFirstChild(machineName)
    local price = machine and machine:FindFirstChild(M.Store.PRICE_PART_NAME)
    local holder = price and price:FindFirstChild(M.Store.PROMPT_ATTACHMENT_NAME)
    local prompt = holder and holder:FindFirstChildOfClass("ProximityPrompt")
    return prompt
end

local function StorePrompt(category, itemName)
    local M = Shared.Potato.Modules
    if not M then return nil end
    local map = workspace:FindFirstChild("Map")
    local store = map and map:FindFirstChild(M.Store.FOLDER_NAME)
    local cat = store and store:FindFirstChild(category)
    local item = cat and cat:FindFirstChild(itemName)
    local price = item and item:FindFirstChild(M.Store.PRICE_PART_NAME)
    local holder = price and price:FindFirstChild(M.Store.PROMPT_ATTACHMENT_NAME)
    local prompt = holder and holder:FindFirstChildOfClass("ProximityPrompt")
    return prompt
end

local function GetPeels(model)
    local list = {}
    for _, child in ipairs(model:GetChildren()) do
        if child.Name == "Peel" and child:IsA("BasePart") then
            table.insert(list, child)
        end
    end
    return list
end

local function KindName(pile, id)
    local M = Shared.Potato.Modules
    if not M then return nil end
    if M.Pile.IsDiamond(pile, id) then
        return "Diamond"
    end
    local kind = M.Kinds.Kinds[M.Pile.GetKind(pile, id)]
    return kind and kind.Name or nil
end

local function OnPileSynced(seed, removed, keyId)
    local M = Shared.Potato.Modules
    if not M then return end
    local state = M.Pile.CreatePile(seed)
    if keyId then
        M.Pile.SetKeyPotato(state, keyId)
    end
    for _, id in ipairs(removed or {}) do
        M.Pile.RemovePotato(state, id)
    end
    Shared.Potato.Pile = state
end

local function OnPileRemoval(ids)
    local M = Shared.Potato.Modules
    local pile = Shared.Potato.Pile
    if not M or not pile then return end
    for _, id in ipairs(ids or {}) do
        M.Pile.RemovePotato(pile, id)
    end
end

local function InstallListeners()
    local M = Shared.Potato.Modules
    SafeConnect("PotatoPileSynced", function() return M.Packets.PotatoPileSynced.OnClientEvent end, OnPileSynced)
    SafeConnect("PotatoesPicked", function() return M.Packets.PotatoesPicked.OnClientEvent end, function(_, ids)
        OnPileRemoval(ids)
    end)
    SafeConnect("PotatoRemoved", function() return M.Packets.PotatoRemoved.OnClientEvent end, function(id)
        OnPileRemoval({ id })
    end)
    SafeConnect("PotatoKeyMoved", function() return M.Packets.PotatoKeyMoved.OnClientEvent end, function(keyId)
        local pile = Shared.Potato.Pile
        local M2 = Shared.Potato.Modules
        if pile and M2 then
            M2.Pile.SetKeyPotato(pile, keyId)
        end
    end)
    SafeConnect("PotatoPeelStarted", function() return M.Packets.PeelingStarted.OnClientEvent end, function(_, _, toolId)
        Shared.Potato.Session = { ToolId = toolId, Fired = {}, Next = 0, Sync = 0 }
        Shared.Potato.SessionDead = false
    end)
    SafeConnect("PotatoPeelNext", function() return M.Packets.PeelingNextPotato.OnClientEvent end, function(_, toolId)
        local session = Shared.Potato.Session
        if session then
            session.ToolId = toolId
            session.Fired = {}
            session.Next = 0
        end
    end)
    SafeConnect("PotatoPeelStopped", function() return M.Packets.PeelingStopped.OnClientEvent end, function()
        Shared.Potato.Session = nil
        Shared.Potato.SessionDead = true
    end)
    SafeConnect("PotatoKeyRevealed", function() return M.Packets.KeyRevealed.OnClientEvent end, function()
        Shared.Potato.Session = nil
        Shared.Potato.SessionDead = true
    end)
    SafeConnect("PotatoEscaped", function() return M.Packets.Escaped.OnClientEvent end, function()
        Shared.Potato.Session = nil
        Shared.Potato.SessionDead = true
    end)
    SafeConnect("PotatoQueueJoined", function() return M.Packets.QueueJoined.OnClientEvent end, function()
        Shared.Potato.Joined = true
    end)
    SafeConnect("PotatoQueueLeft", function() return M.Packets.QueueLeft.OnClientEvent end, function()
        Shared.Potato.Joined = false
    end)
    SafeConnect("PotatoQueueTeleporting", function() return M.Packets.QueueTeleporting.OnClientEvent end, function()
        Shared.Potato.Joined = true
    end)
end

ResolveModules()

Thread("Init", function()
    while not Library.Unloaded do
        if not Shared.Potato.Modules then
            ResolveModules()
        end
        if Shared.Potato.Modules then
            InstallListeners()
            break
        end
        task.wait(1)
    end
end, true)

local function BestPickTool()
    local M = Shared.Potato.Modules
    if not M then return nil end
    for i = #M.Tools.Tools, 1, -1 do
        local tool = M.Tools.Tools[i]
        if M.ToolCtl.CanUseTool(tool.Id) then
            return tool.Id
        end
    end
    return nil
end

local function PickInterval()
    local M = Shared.Potato.Modules
    if not M then return 1 end
    local tool = M.ToolCtl.GetEquippedTool()
    local interval = M.Tools.GetPickInterval(M.ToolCtl.GetEquippedUpgrades(), tool, M.ToolCtl.GetClassId(), M.ToolCtl.IsOnTrial(tool))
    if type(interval) ~= "number" or interval < 0.05 or interval ~= interval then
        interval = 0.05
    end
    return interval
end

local function Func_AutoPick()
    while Toggles.AutoPick.Value do
        local ok, err = pcall(function()
            local M, state = GetState()
            if not M then return end
            local best = BestPickTool()
            if best and M.ToolCtl.GetEquippedTool() ~= best then
                M.ToolCtl.Equip(best)
            end
            if M.ToolCtl.IsOverheated() or not M.ToolCtl.HasCharge() then return end
            local pile = Shared.Potato.Pile
            if not pile then return end
            local bagFull = M.Carry.GetPlayerCapacity(state.CarryLevel, state.Gamepasses, state.SaveData.LobbyUpgrades) <= state.Potatoes
            local wanted = AddMultiDropdown("PickKinds")
            local anyWanted = next(wanted) ~= nil
            local target = nil
            M.Pile.ForEachSlot(function(slot)
                if target then return end
                local id = M.Pile.GetPotatoInSlot(pile, slot)
                if not id then return end
                if not M.Pile.IsExposed(pile, id) then return end
                local name = KindName(pile, id)
                if not name then return end
                if anyWanted and not wanted[name] then return end
                if bagFull and not (M.Pile.IsKeyPotato(pile, id) or M.Pile.IsDiamond(pile, id)) then return end
                target = id
            end)
            if not target then return end
            M.ToolCtl.Use()
            M.Packets.PotatoPick:Fire(target)
        end)
        if not ok then notyuri("AutoPick", err) end
        task.wait(PickInterval())
    end
end

local function Func_AutoPlace()
    while Toggles.AutoPlace.Value do
        local ok, err = pcall(function()
            local M, state = GetState()
            if not M or state.Potatoes <= 0 then return end
            local prompt = AreaPrompt(M.Table.INPUT_CRATE_NAME, M.Table.PLACE_PROMPT_NAME)
            if not prompt then return end
            FirePP(prompt, true)
        end)
        if not ok then notyuri("AutoPlace", err) end
        task.wait(1)
    end
end

local function Func_AutoLoad()
    while Toggles.AutoLoad.Value do
        local ok, err = pcall(function()
            local M, state = GetState()
            if not M then return end
            local machineName, rootName
            if state.HasAutoPeeler then
                machineName = M.Table.AUTO_PEELER_MACHINE_NAME
                rootName = M.Table.AUTO_PEELER_ROOT_NAME
            elseif state.HasHandPeeler then
                machineName = M.Table.HAND_MACHINE_NAME
                rootName = M.Table.HAND_MACHINE_ROOT_NAME
            else
                return
            end
            local area = GetCrateArea(M.Table.INPUT_CRATE_NAME)
            if CountAt(area) <= 0 then return end
            local prompt = MachinePrompt(machineName, rootName, M.Table.LOAD_PROMPT_NAME)
            if not prompt then return end
            FirePP(prompt, true)
        end)
        if not ok then notyuri("AutoLoad", err) end
        task.wait(1)
    end
end

local function Func_AutoCrank()
    while Toggles.AutoCrank.Value do
        local ok, err = pcall(function()
            local M, state = GetState()
            if not M then return end
            if not state.HasHandPeeler or state.HasAutoPeeler then return end
            local root = MachineRoot(M.Table.HAND_MACHINE_NAME, M.Table.HAND_MACHINE_ROOT_NAME)
            if CountAt(root) <= 0 then return end
            local folder = GetMachines()
            local machine = folder and folder:FindFirstChild(M.Table.HAND_MACHINE_NAME)
            local prompt = machine and machine:FindFirstChild(M.Table.CRANK_PROMPT_NAME, true)
            if not prompt or not prompt:IsA("ProximityPrompt") then return end
            FirePP(prompt, true)
        end)
        if not ok then notyuri("AutoCrank", err) end
        task.wait(0.5)
    end
end

local function Func_AutoSell()
    while Toggles.AutoSell.Value do
        local ok, err = pcall(function()
            local M = Shared.Potato.Modules
            if not M then return end
            local area = GetCrateArea(M.Table.OUTPUT_CRATE_NAME)
            if CountAt(area) <= 0 then return end
            local prompt = AreaPrompt(M.Table.OUTPUT_CRATE_NAME, M.Table.SELL_PROMPT_NAME)
            if not prompt then return end
            FirePP(prompt, true)
        end)
        if not ok then notyuri("AutoSell", err) end
        task.wait(1)
    end
end

local function Func_AutoBuyMachines()
    while Toggles.AutoBuyMachines.Value do
        local ok, err = pcall(function()
            local M, state = GetState()
            if not M then return end
            if not state.HasHandPeeler and state.Cash >= M.Table.HAND_PEELER_COST then
                local prompt = MachinePricePrompt(M.Table.HAND_MACHINE_NAME)
                if prompt then
                    FirePP(prompt, true)
                    return
                end
            end
            if not state.HasAutoPeeler and state.Cash >= M.Table.AUTO_PEELER_COST then
                local prompt = MachinePricePrompt(M.Table.AUTO_PEELER_MACHINE_NAME)
                if prompt then
                    FirePP(prompt, true)
                    return
                end
            end
        end)
        if not ok then notyuri("AutoBuyMachines", err) end
        task.wait(1)
    end
end

local function Func_AutoBuyTools()
    while Toggles.AutoBuyTools.Value do
        local ok, err = pcall(function()
            local M, state = GetState()
            if not M then return end
            for _, tool in ipairs(M.Tools.Tools) do
                if tool.Price and not state.Tools[tool.Id] and state.Cash >= tool.Price then
                    local prompt = StorePrompt(M.Store.TOOLS_CATEGORY, tool.ItemName)
                    if prompt then
                        FirePP(prompt, true)
                        return
                    end
                end
            end
            local nextCarry = M.Carry.Levels[state.CarryLevel + 1]
            if nextCarry and state.Cash >= nextCarry.Cost then
                local prompt = StorePrompt(M.Store.STORAGE_CATEGORY, nextCarry.ItemName)
                if prompt then
                    FirePP(prompt, true)
                    return
                end
            end
            for _, tool in ipairs(M.PeelTools.Tools) do
                if tool.Price and not M.PeelTools.IsOutclassed(state.PeelTools, tool.Id) and state.Cash >= tool.Price then
                    local prompt = StorePrompt(M.Store.PEELERS_CATEGORY, tool.ItemName)
                    if prompt then
                        FirePP(prompt, true)
                        return
                    end
                end
            end
        end)
        if not ok then notyuri("AutoBuyTools", err) end
        task.wait(1)
    end
end

local function Func_AutoUpgradeTools()
    while Toggles.AutoUpgradeTools.Value do
        local ok, err = pcall(function()
            local M, state = GetState()
            if not M then return end
            local cheapest = nil
            local function consider(toolId)
                local upgradeable = M.Tools.GetUpgradeable(toolId)
                if not upgradeable then return end
                for _, upg in ipairs(upgradeable.Upgrades) do
                    local level = M.Tools.GetLevel(state.Upgrades, toolId, upg.Id)
                    local cost = M.Tools.GetNextCost(upg, level)
                    if cost and state.Cash >= cost and (not cheapest or cost < cheapest.cost) then
                        cheapest = { Tool = toolId, Upgrade = upg.Id, cost = cost }
                    end
                end
            end
            consider(M.Tools.BODY)
            for _, tool in ipairs(M.Tools.Tools) do
                if M.Tools.OwnsTool(state.Tools, tool.Id) then
                    consider(tool.Id)
                end
            end
            if state.HasHandPeeler then
                consider(M.Tools.HAND_PEELER)
            end
            if state.HasAutoPeeler then
                consider(M.Tools.AUTO_PEELER)
            end
            if cheapest then
                M.Packets.ToolUpgradePurchase:Fire(cheapest.Tool, cheapest.Upgrade)
            end
        end)
        if not ok then notyuri("AutoUpgradeTools", err) end
        task.wait(0.5)
    end
end

local function SessionPotato()
    local M = Shared.Potato.Modules
    if not M then return nil end
    local area = GetCrateArea(M.Table.INPUT_CRATE_NAME)
    if not area then return nil end
    local anchor = area.CFrame * CFrame.new(0, area.Size.Y / 2 + 1, 0)
    local best, bestDist = nil, 1
    for _, inst in ipairs(workspace:GetChildren()) do
        if inst:IsA("Model") then
            local peels = GetPeels(inst)
            if #peels > 0 then
                local dist = (inst:GetPivot().Position - anchor.Position).Magnitude
                if dist < bestDist then
                    best, bestDist = inst, dist
                end
            end
        end
    end
    return best
end

local function Func_AutoPeel()
    while Toggles.AutoPeel.Value do
        local ok, err = pcall(function()
            local M, state = GetState()
            if not M then return end
            if Shared.Potato.SessionDead then return end
            local model = SessionPotato()
            if not model then return end
            local session = Shared.Potato.Session
            if not session then
                session = { ToolId = nil, Fired = {}, Next = 0, Sync = 0 }
                Shared.Potato.Session = session
            end
            if not session.Fired then
                session.Fired = {}
            end
            local now = os.clock()
            if now - session.Sync >= 0.08 then
                session.Sync = now
                M.Packets.PeelingSync:Fire(model:GetPivot())
            end
            local tool = session.ToolId and M.PeelTools.GetTool(session.ToolId) or nil
            if not tool then
                tool = M.PeelTools.GetBestTool(state.PeelTools)
            end
            local peels = GetPeels(model)
            if #peels == 0 then return end
            if now < (session.Next or 0) then return end
            local interval = (tool.PotatoCount or 1) / (tool.AutoPeelRate * #peels)
            if tool.InstantPeel then
                for i, peel in ipairs(peels) do
                    if not session.Fired[i] then
                        session.Fired[i] = true
                        M.Packets.PeelingPeelRemoved:Fire(i, peel.Position)
                    end
                end
                M.Packets.PeelingFinished:Fire()
                session.Next = now + interval
                return
            end
            local pending = nil
            for i, peel in ipairs(peels) do
                if not session.Fired[i] then
                    pending = i
                    break
                end
            end
            if not pending then return end
            session.Fired[pending] = true
            M.Packets.PeelingPeelRemoved:Fire(pending, peels[pending].Position)
            local more = false
            for i in ipairs(peels) do
                if not session.Fired[i] then
                    more = true
                    break
                end
            end
            if not more then
                for i in ipairs(peels) do
                    session.Fired[i] = nil
                end
                M.Packets.PeelingFinished:Fire()
            end
            session.Next = now + interval
        end)
        if not ok then notyuri("AutoPeel", err) end
        task.wait(0.05)
    end
end

local function Func_AutoEscape()
    while Toggles.AutoEscape.Value do
        local ok, err = pcall(function()
            local M, state = GetState()
            if not M or not state.HasKey then return end
            local keyhole = workspace:FindFirstChild(M.Keys.KEYHOLE_NAME, true)
            if not keyhole or not keyhole:IsA("BasePart") then return end
            local prompt = keyhole:FindFirstChildOfClass("ProximityPrompt")
            if not prompt then return end
            FirePP(prompt, true)
        end)
        if not ok then notyuri("AutoEscape", err) end
        task.wait(1)
    end
end

local function Func_AutoQueue()
    while Toggles.AutoQueue.Value do
        local ok, err = pcall(function()
            local M = Shared.Potato.Modules
            if not M or Shared.Potato.Joined then return end
            local zones = GetObject(workspace, "Map.Zones." .. M.Queue.MATCHMAKING_FOLDER_NAME)
            if not zones then return end
            local zone = nil
            for _, child in ipairs(zones:GetChildren()) do
                if child:IsA("Folder") then
                    zone = child
                    break
                end
            end
            if not zone then return end
            local pad = M.Queue.FindPad(zone)
            if not pad then return end
            TPTo(pad)
            task.wait(0.4)
            local now = os.clock()
            if now - Shared.Potato.LastCreate >= 3 then
                Shared.Potato.LastCreate = now
                local size = tonumber(Options.QueueSize.Value) or 1
                M.Packets.QueueCreate:Fire(size, false, false)
            end
        end)
        if not ok then notyuri("AutoQueue", err) end
        task.wait(1)
    end
end

local function Func_AutoClassRoll()
    while Toggles.AutoClassRoll.Value do
        local ok, err = pcall(function()
            local M, state = GetState()
            if not M then return end
            local save = state.SaveData
            local active = M.Class.GetActiveClassId(save, state.Gamepasses)
            if M.Class.IsStoppedAt(active, save.StopAtClass or "") then return end
            if (save.FreeRolls or 0) <= 0 and save.Diamonds < M.Class.ROLL_COST then return end
            local now = os.clock()
            if now - Shared.Potato.Memo.Roll < 3.5 then return end
            Shared.Potato.Memo.Roll = now
            M.Packets.ClassRoll:Fire()
        end)
        if not ok then notyuri("AutoClassRoll", err) end
        task.wait(0.5)
    end
end

local function Func_AutoLobbyUpgrades()
    while Toggles.AutoLobbyUpgrades.Value do
        local ok, err = pcall(function()
            local M, state = GetState()
            if not M then return end
            local save = state.SaveData
            local cheapest = nil
            for _, upg in ipairs(M.Lobby.Upgrades) do
                local level = M.Lobby.GetLevel(save.LobbyUpgrades, upg.Id)
                local cost = M.Lobby.GetNextCost(upg, level)
                if cost and save.Diamonds >= cost and (not cheapest or cost < cheapest.cost) then
                    cheapest = { Id = upg.Id, cost = cost }
                end
            end
            if cheapest then
                M.Packets.LobbyUpgradePurchase:Fire(cheapest.Id)
            end
        end)
        if not ok then notyuri("AutoLobbyUpgrades", err) end
        task.wait(1)
    end
end

local function Func_AutoClaimDaily()
    while Toggles.AutoClaimDaily.Value do
        local ok, err = pcall(function()
            local M, state = GetState()
            if not M then return end
            local save = state.SaveData
            if not M.Daily.GetClaimableDay(save.DailyRewardDay, save.DailyRewardClaimDate, M.Daily.GetToday()) then return end
            local now = os.clock()
            if now - Shared.Potato.Memo.Daily < 30 then return end
            Shared.Potato.Memo.Daily = now
            M.Packets.DailyRewardClaim:Fire()
        end)
        if not ok then notyuri("AutoClaimDaily", err) end
        task.wait(5)
    end
end

local function Func_AutoClaimGroup()
    while Toggles.AutoClaimGroup.Value do
        local ok, err = pcall(function()
            local M, state = GetState()
            if not M then return end
            if state.SaveData.GroupRewardClaimed then return end
            local now = os.clock()
            if now - Shared.Potato.Memo.Group < 30 then return end
            Shared.Potato.Memo.Group = now
            M.Packets.GroupRewardClaim:Fire(M.Group.CLAIM)
        end)
        if not ok then notyuri("AutoClaimGroup", err) end
        task.wait(5)
    end
end

local function KindNames()
    local M = Shared.Potato.Modules
    local names = {}
    if M then
        for _, kind in ipairs(M.Kinds.Kinds) do
            table.insert(names, kind.Name)
        end
    end
    return names
end

local T1 = TB_Tabs.Autofarm.T1
T1:AddToggle("AutoPick", { Text = "Auto Pick" })
AddMultiDropdown(T1, "PickKinds", { Text = "Pick Kinds", Values = KindNames(), Default = { "All" } })
if #KindNames() == 0 then
    Thread("PickKinds", function()
        while not Library.Unloaded do
            if Shared.Potato.Modules then
                Options.PickKinds:SetValues(KindNames())
                return
            end
            task.wait(1)
        end
    end, true)
end
T1:AddDivider()
T1:AddToggle("AutoPlace", { Text = "Auto Place" })
T1:AddToggle("AutoLoad", { Text = "Auto Load" })
T1:AddToggle("AutoCrank", { Text = "Auto Crank" })
T1:AddToggle("AutoSell", { Text = "Auto Sell" })
T1:AddToggle("AutoBuyMachines", { Text = "Auto Buy Machines" })
T1:AddDivider()
T1:AddToggle("AutoBuyTools", { Text = "Auto Buy Tools" })
T1:AddToggle("AutoUpgradeTools", { Text = "Auto Upgrade Tools" })
T1:AddDivider()
T1:AddToggle("AutoPeel", { Text = "Auto Peel" })
T1:AddToggle("AutoEscape", { Text = "Auto Escape" })
T1:AddDivider()
T1:AddToggle("AutoQueue", { Text = "Auto Queue" })
T1:AddDropdown("QueueSize", { Text = "Queue Size", Values = { "1", "2", "3", "4" }, Default = "1", Callback = nil })
T1:AddToggle("AutoClassRoll", { Text = "Auto Class Roll" })
T1:AddToggle("AutoLobbyUpgrades", { Text = "Auto Lobby Upgrades" })
T1:AddDivider()
T1:AddToggle("AutoClaimDaily", { Text = "Auto Claim Daily" })
T1:AddToggle("AutoClaimGroup", { Text = "Auto Claim Group" })

Toggles.AutoPick:OnChanged(function(state)
    Thread("AutoPick", SafeLoop("AutoPick", Func_AutoPick), state)
end)
Toggles.AutoPlace:OnChanged(function(state)
    Thread("AutoPlace", SafeLoop("AutoPlace", Func_AutoPlace), state)
end)
Toggles.AutoLoad:OnChanged(function(state)
    Thread("AutoLoad", SafeLoop("AutoLoad", Func_AutoLoad), state)
end)
Toggles.AutoCrank:OnChanged(function(state)
    Thread("AutoCrank", SafeLoop("AutoCrank", Func_AutoCrank), state)
end)
Toggles.AutoSell:OnChanged(function(state)
    Thread("AutoSell", SafeLoop("AutoSell", Func_AutoSell), state)
end)
Toggles.AutoBuyMachines:OnChanged(function(state)
    Thread("AutoBuyMachines", SafeLoop("AutoBuyMachines", Func_AutoBuyMachines), state)
end)
Toggles.AutoBuyTools:OnChanged(function(state)
    Thread("AutoBuyTools", SafeLoop("AutoBuyTools", Func_AutoBuyTools), state)
end)
Toggles.AutoUpgradeTools:OnChanged(function(state)
    Thread("AutoUpgradeTools", SafeLoop("AutoUpgradeTools", Func_AutoUpgradeTools), state)
end)
Toggles.AutoPeel:OnChanged(function(state)
    Thread("AutoPeel", SafeLoop("AutoPeel", Func_AutoPeel), state)
end)
Toggles.AutoEscape:OnChanged(function(state)
    Thread("AutoEscape", SafeLoop("AutoEscape", Func_AutoEscape), state)
end)
Toggles.AutoQueue:OnChanged(function(state)
    Thread("AutoQueue", SafeLoop("AutoQueue", Func_AutoQueue), state)
end)
Toggles.AutoClassRoll:OnChanged(function(state)
    Thread("AutoClassRoll", SafeLoop("AutoClassRoll", Func_AutoClassRoll), state)
end)
Toggles.AutoLobbyUpgrades:OnChanged(function(state)
    Thread("AutoLobbyUpgrades", SafeLoop("AutoLobbyUpgrades", Func_AutoLobbyUpgrades), state)
end)
Toggles.AutoClaimDaily:OnChanged(function(state)
    Thread("AutoClaimDaily", SafeLoop("AutoClaimDaily", Func_AutoClaimDaily), state)
end)
Toggles.AutoClaimGroup:OnChanged(function(state)
    Thread("AutoClaimGroup", SafeLoop("AutoClaimGroup", Func_AutoClaimGroup), state)
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
SaveManager:SetFolder("Yuri/Potato")
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
