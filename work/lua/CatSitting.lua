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
local Remotes = {
    Pet = GetObject(RS, "Cat.Pet"),
    Stare = GetObject(RS, "Cat.Stare"),
    Eat = GetObject(RS, "Meal.Eat"),
    LaserPoint = GetObject(RS, "Laser.Point"),
    Photo = GetObject(RS, "Phone.Photo"),
    Litter = GetObject(RS, "LitterCleaning.Event"),
    GetState = GetObject(RS, "Shop.GetState"),
    OpenCrate = GetObject(RS, "Shop.OpenCrate"),
}

local ChoreFlags = { "Chore_Feed", "Chore_Eat", "Chore_Litter", "Chore_Lock", "Chore_Mail", "Chore_Play" }
local AnomalyFlags = { "Catzilla", "CreepyHead", "FakeDoor", "Grandma", "Misplaced", "Seeker", "SmilingMan", "StalkerInBedroom", "ToiletFace", "VoidOutside", "WindowMonster" }

Shared.LitterSid = nil
Shared.LitterDone = {}
Shared.CurtainsClosed = nil
Shared.TVOn = nil
Shared.Staring = nil
Shared.PhotoBusy = {}

local function FindTool(attr)
    local containers = {}
    local backpack = Plr:FindFirstChildOfClass("Backpack")
    if backpack then table.insert(containers, backpack) end
    local char = GetCharacter()
    if char then table.insert(containers, char) end
    for _, container in ipairs(containers) do
        for _, tool in ipairs(container:GetChildren()) do
            if tool:IsA("Tool") and tool:GetAttribute(attr) then
                return tool
            end
        end
    end
    return nil
end

local function FirePrompt(path)
    local prompt = GetObject(workspace, path)
    if prompt then
        FirePP(prompt, true)
    end
end

local function ChoresDone()
    for _, flag in ipairs(ChoreFlags) do
        if workspace:GetAttribute(flag) ~= true then
            return false
        end
    end
    return true
end

local function AnomaliesClear()
    for _, flag in ipairs(AnomalyFlags) do
        if workspace:GetAttribute(flag) == true then
            return false
        end
    end
    return true
end

local function CloseAllCurtains()
    local curtains = GetObject(workspace, "House.Parts.InteriorLayout.Curtains")
    if not curtains then return end
    for _, model in ipairs(curtains:GetChildren()) do
        local prompt = model:FindFirstChildWhichIsA("ProximityPrompt", true)
        if prompt then
            FirePP(prompt, true)
            task.wait(0.3)
        end
    end
end

local function LightsOff()
    local switches = GetObject(workspace, "House.Important.RoomLighting.Switches")
    local rooms = GetObject(workspace, "House.Important.RoomLighting.Rooms")
    if not switches or not rooms then return end
    for _, switch in ipairs(switches:GetChildren()) do
        local prompt = switch:FindFirstChildWhichIsA("ProximityPrompt", true)
        local room = prompt and prompt:GetAttribute("Room")
        local folder = room and rooms:FindFirstChild(room)
        if prompt and folder and folder:GetAttribute("On") == true then
            FirePP(prompt, true)
            task.wait(0.3)
        end
    end
end

local function PhotoAt(target)
    local part = target:IsA("BasePart") and target or target:FindFirstChildWhichIsA("BasePart")
    local char = GetCharacter()
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not part or not hrp or not Remotes.Photo then return end
    local pos = part.Position
    local eye = pos + (hrp.Position - pos).Unit * 12
    hrp.CFrame = CFrame.new(eye)
    workspace.CurrentCamera.CFrame = CFrame.lookAt(eye, pos)
    task.wait(0.05)
    Remotes.Photo:FireServer(CFrame.lookAt(eye, pos), part)
end

local function ResolveStare()
    local cat = workspace:FindFirstChild("Cat")
    local head = cat and cat:FindFirstChild("CreepyCatHead")
    TPTo(head or cat)
    local deadline = os.clock() + 20
    while os.clock() < deadline and workspace:GetAttribute("CreepyHead") == true and Toggles.AutoAnomalies.Value do
        if Remotes.Stare then
            Remotes.Stare:FireServer(5)
        end
        task.wait(0.4)
    end
end

local function ResolvePhoto(flag)
    local deadline = os.clock() + 45
    while os.clock() < deadline and workspace:GetAttribute(flag) == true and Toggles.AutoAnomalies.Value do
        if flag == "Misplaced" then
            local roots = { GetObject(workspace, "House.Important"), GetObject(workspace, "House.Parts") }
            for _, root in ipairs(roots) do
                if root then
                    for _, inst in ipairs(root:GetDescendants()) do
                        if workspace:GetAttribute(flag) ~= true then break end
                        if inst:IsA("Model") then
                            PhotoAt(inst)
                            task.wait(0.1)
                        end
                    end
                end
            end
        else
            local target = workspace:FindFirstChild(flag)
            if target then
                PhotoAt(target)
            end
        end
        task.wait(0.5)
    end
end

local function Func_AutoChores()
    while Toggles.AutoChores.Value do
        local ok, err = pcall(function()
            if workspace:GetAttribute("Chore_Feed") ~= true then
                FirePrompt("House.Important.Kitchen.Cabinets.Base_N1.CatFoodCan.CanBody.TakePromptAttachment.TakePrompt")
                task.wait(0.4)
                FirePrompt("House.Important.Kitchen.FoodBowl.Food Bowl.Cylinder.FillPromptAttachment.FillPrompt")
                task.wait(0.4)
            end
            if workspace:GetAttribute("Chore_Eat") ~= true then
                local meal = FindTool("Meal")
                if meal then
                    if meal:GetAttribute("Hot") then
                        local char = GetCharacter()
                        local hum = char and char:FindFirstChildOfClass("Humanoid")
                        if hum and meal.Parent ~= char then
                            hum:EquipTool(meal)
                            task.wait(0.3)
                        end
                        if Remotes.Eat then
                            Remotes.Eat:FireServer()
                        end
                    else
                        FirePrompt("House.Important.Kitchen.Cabinets.Microwave.Door.Leaf.Panel.OpenClosePromptAttachment.OpenClosePrompt")
                        task.wait(0.4)
                        FirePrompt("House.Important.Kitchen.Cabinets.Microwave.Carcass.Turntable.CookPromptAttachment.CookPrompt")
                    end
                else
                    FirePrompt("House.Important.Kitchen.Fridge.TVDinner.Tray.TakePromptAttachment.TakePrompt")
                end
                task.wait(0.5)
            end
            if workspace:GetAttribute("Chore_Mail") ~= true then
                FirePrompt("Neighborhood.Parts.PetsitFrontYard.Mailbox.Body.MailPromptAttachment.MailboxPrompt")
                task.wait(0.5)
            end
            if workspace:GetAttribute("Chore_Lock") ~= true then
                FirePrompt("House.Important.Doors.Front Door.Leaf.Deadbolt.LockPromptAttachment.LockPrompt")
                task.wait(0.4)
            end
            if workspace:GetAttribute("Chore_Litter") ~= true and Shared.LitterSid == nil then
                FirePrompt("House.Parts.Laundry.LitterBox.LitterInteraction.CleanLitterPrompt")
                task.wait(1)
            end
        end)
        if not ok then
            notyuri("AutoChores:", err)
        end
        task.wait(1)
    end
end

local function Func_AutoPlay()
    while Toggles.AutoPlay.Value do
        local ok, err = pcall(function()
            if workspace:GetAttribute("Chore_Play") == true then
                if Remotes.LaserPoint then
                    Remotes.LaserPoint:FireServer(nil, false)
                end
                task.wait(2)
                return
            end
            local cat = workspace:FindFirstChild("Cat")
            if not cat then
                task.wait(1)
                return
            end
            local tool = FindTool("Laser")
            if not tool then
                FirePrompt("House.Important.LivingRoom.LaserPointer.Body.TakePromptAttachment.TakePrompt")
                task.wait(0.5)
                return
            end
            local char = GetCharacter()
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if hum and tool.Parent ~= char then
                hum:EquipTool(tool)
                task.wait(0.3)
            end
            local base = cat:GetPivot().Position
            while Toggles.AutoPlay.Value and workspace:GetAttribute("Chore_Play") ~= true do
                local offset = Vector3.new(math.sin(os.clock() * 1.2) * 4, 0.1, 1.5)
                if Remotes.LaserPoint then
                    Remotes.LaserPoint:FireServer(base + offset, true)
                end
                task.wait(0.1)
            end
            if Remotes.LaserPoint then
                Remotes.LaserPoint:FireServer(nil, false)
            end
        end)
        if not ok then
            notyuri("AutoPlay:", err)
        end
        task.wait(0.5)
    end
    if Remotes.LaserPoint then
        pcall(function()
            Remotes.LaserPoint:FireServer(nil, false)
        end)
    end
end

local function Func_AutoPet()
    while Toggles.AutoPet.Value do
        local ok, err = pcall(function()
            if not Remotes.Pet then
                task.wait(1)
                return
            end
            local cat = workspace:FindFirstChild("Cat")
            local char = GetCharacter()
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if cat and hrp then
                local pos = cat:GetPivot().Position
                if (hrp.Position - pos).Magnitude <= 40 then
                    Remotes.Pet:FireServer()
                else
                    TPTo(cat)
                end
            end
        end)
        if not ok then
            notyuri("AutoPet:", err)
        end
        task.wait(0.4)
    end
end

local function Func_AutoSleep()
    while Toggles.AutoSleep.Value do
        local ok, err = pcall(function()
            if ChoresDone() and AnomaliesClear() then
                FirePrompt("House.Parts.Bedroom.Mattress.SleepPromptAttachment.SleepPrompt")
            end
        end)
        if not ok then
            notyuri("AutoSleep:", err)
        end
        task.wait(2)
    end
end

local function Func_AutoAnomalies()
    while Toggles.AutoAnomalies.Value do
        local ok, err = pcall(function()
            if workspace:GetAttribute("Grandma") == true then
                LightsOff()
            end
            if workspace:GetAttribute("VoidOutside") == true or workspace:GetAttribute("WindowMonster") == true then
                if not Shared.CurtainsClosed then
                    Shared.CurtainsClosed = true
                    CloseAllCurtains()
                end
            else
                Shared.CurtainsClosed = nil
            end
            if workspace:GetAttribute("Catzilla") == true and not Shared.TVOn then
                Shared.TVOn = true
                FirePrompt("House.Important.LivingRoom.TV.Screen.TogglePromptAttachment.TogglePrompt")
            end
            if workspace:GetAttribute("Catzilla") ~= true then
                Shared.TVOn = nil
            end
            if workspace:GetAttribute("ToiletFace") == true then
                FirePrompt("House.Important.Bathroom.Toilet.Flush.Lever.FlushPromptAttachment.FlushPrompt")
            end
            if workspace:GetAttribute("CreepyHead") == true and not Shared.Staring then
                Shared.Staring = true
                task.spawn(function()
                    ResolveStare()
                    Shared.Staring = nil
                end)
            end
            for _, flag in ipairs({ "SmilingMan", "Misplaced" }) do
                if workspace:GetAttribute(flag) == true and not Shared.PhotoBusy[flag] then
                    Shared.PhotoBusy[flag] = true
                    task.spawn(function()
                        ResolvePhoto(flag)
                        Shared.PhotoBusy[flag] = nil
                    end)
                end
            end
        end)
        if not ok then
            notyuri("AutoAnomalies:", err)
        end
        task.wait(2)
    end
end

local function Func_AutoQueue()
    while Toggles.AutoQueue.Value do
        local ok, err = pcall(function()
            local zone = GetObject(workspace, "Lobby.Important.TeleportPod.Zone")
            if zone then
                TPTo(zone)
                FireTI(zone)
            end
        end)
        if not ok then
            notyuri("AutoQueue:", err)
        end
        task.wait(1)
    end
end

local function Func_AutoCrate()
    while Toggles.AutoCrate.Value do
        local ok, err = pcall(function()
            if not Remotes.OpenCrate then
                task.wait(2)
                return
            end
            local state = SafeInvoke(Remotes.GetState)
            local cash = type(state) == "table" and type(state.cash) == "number" and state.cash or 0
            while cash >= 10 and Toggles.AutoCrate.Value do
                local result = SafeInvoke(Remotes.OpenCrate)
                local nextCash = type(result) == "table" and type(result.state) == "table" and type(result.state.cash) == "number" and result.state.cash or nil
                if nextCash then
                    cash = nextCash
                else
                    break
                end
                task.wait(0.8)
            end
        end)
        if not ok then
            notyuri("AutoCrate:", err)
        end
        task.wait(1)
    end
end

TB_Tabs.Autofarm.T1:AddDivider()
TB_Tabs.Autofarm.T1:AddToggle("AutoChores", { Text = "Auto Chores" })
TB_Tabs.Autofarm.T1:AddToggle("AutoPlay", { Text = "Auto Play" })
TB_Tabs.Autofarm.T1:AddToggle("AutoPet", { Text = "Auto Pet" })
TB_Tabs.Autofarm.T1:AddToggle("AutoSleep", { Text = "Auto Sleep" })
TB_Tabs.Autofarm.T1:AddToggle("AutoAnomalies", { Text = "Auto Anomalies" })
TB_Tabs.Autofarm.T1:AddDivider()
TB_Tabs.Autofarm.T1:AddToggle("AutoQueue", { Text = "Auto Queue" })
TB_Tabs.Autofarm.T1:AddToggle("AutoCrate", { Text = "Auto Crate" })

Toggles.AutoChores:OnChanged(function(state)
    Thread("AutoChores", SafeLoop("AutoChores", Func_AutoChores), state)
end)
Toggles.AutoPlay:OnChanged(function(state)
    Thread("AutoPlay", SafeLoop("AutoPlay", Func_AutoPlay), state)
end)
Toggles.AutoPet:OnChanged(function(state)
    Thread("AutoPet", SafeLoop("AutoPet", Func_AutoPet), state)
end)
Toggles.AutoSleep:OnChanged(function(state)
    Thread("AutoSleep", SafeLoop("AutoSleep", Func_AutoSleep), state)
end)
Toggles.AutoAnomalies:OnChanged(function(state)
    Thread("AutoAnomalies", SafeLoop("AutoAnomalies", Func_AutoAnomalies), state)
end)
Toggles.AutoQueue:OnChanged(function(state)
    Thread("AutoQueue", SafeLoop("AutoQueue", Func_AutoQueue), state)
end)
Toggles.AutoCrate:OnChanged(function(state)
    Thread("AutoCrate", SafeLoop("AutoCrate", Func_AutoCrate), state)
end)

do
    SafeConnect("Litter", function()
        return Remotes.Litter and Remotes.Litter.OnClientEvent
    end, function(op, sid, data)
        if op == "Start" then
            Shared.LitterSid = sid
            table.clear(Shared.LitterDone)
            task.spawn(function()
                task.wait(0.6)
                for i = 1, 5 do
                    if Shared.LitterSid ~= sid then break end
                    if not Toggles.AutoChores.Value then
                        if Remotes.Litter then
                            Remotes.Litter:FireServer("Cancel", sid)
                        end
                        break
                    end
                    if not Shared.LitterDone[i] then
                        local bag = GetObject(Plr, "PlayerGui.LitterCleaningGui.Panel.Board.Bag")
                        if bag then
                            Remotes.Litter:FireServer("Grab", sid, i)
                            task.wait(0.2)
                            Remotes.Litter:FireServer("Drop", sid, i, bag.Position.X.Scale + bag.Size.X.Scale * 0.5, bag.Position.Y.Scale + bag.Size.Y.Scale * 0.5)
                            task.wait(0.2)
                        end
                    end
                end
            end)
        elseif op == "Retry" and sid == Shared.LitterSid then
            task.spawn(function()
                if Toggles.AutoChores.Value and Remotes.Litter and type(data) == "number" then
                    local bag = GetObject(Plr, "PlayerGui.LitterCleaningGui.Panel.Board.Bag")
                    if bag then
                        Remotes.Litter:FireServer("Grab", sid, data)
                        task.wait(0.2)
                        Remotes.Litter:FireServer("Drop", sid, data, bag.Position.X.Scale + bag.Size.X.Scale * 0.5, bag.Position.Y.Scale + bag.Size.Y.Scale * 0.5)
                    end
                end
            end)
        elseif op == "Collected" and sid == Shared.LitterSid and type(data) == "table" then
            Shared.LitterDone[data.index] = true
        elseif (op == "Win" or op == "End") and sid == Shared.LitterSid then
            Shared.LitterSid = nil
            table.clear(Shared.LitterDone)
        end
    end)
end
ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
ThemeManager:SetFolder("Yuri")
SaveManager:SetFolder("Yuri/CatSitting")
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
