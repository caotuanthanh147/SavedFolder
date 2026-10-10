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
local Remotes = {
    Pet = GetObject(RS, "Cat.Pet"),
    Stare = GetObject(RS, "Cat.Stare"),
    Eat = GetObject(RS, "Meal.Eat"),
    Laser = GetObject(RS, "Laser.Point"),
    Photo = GetObject(RS, "Phone.Photo"),
    Litter = GetObject(RS, "LitterCleaning.Event"),
    GetState = GetObject(RS, "Shop.GetState"),
    OpenCrate = GetObject(RS, "Shop.OpenCrate"),
}

local CHORE_INTERVAL = 30
local LASER_PLAY_SECONDS = 20
local CHORES = { "Feed", "Eat", "Litter", "Mail", "Play", "Lock" }
local ANOMALIES = { "Catzilla", "CreepyHead", "FakeDoor", "Grandma", "Misplaced", "Seeker", "SmilingMan", "StalkerInBedroom", "ToiletFace", "VoidOutside", "WindowMonster" }
local LIGHT_SWITCHES = {
    "House.Important.RoomLighting.Switches.BathroomSwitch",
    "House.Important.RoomLighting.Switches.BedroomHallSwitch",
    "House.Important.RoomLighting.Switches.BedroomSwitch",
    "House.Important.RoomLighting.Switches.EntryHallSwitch",
    "House.Important.RoomLighting.Switches.KitchenSwitch",
    "House.Important.RoomLighting.Switches.LaundrySwitch",
    "House.Important.RoomLighting.Switches.LivingRoomSwitch",
}
local BLINDS = {
    "House.Parts.InteriorLayout.Curtains.01_BathroomBack_Glass",
    "House.Parts.InteriorLayout.Curtains.02_BedroomBack_Glass",
    "House.Parts.InteriorLayout.Curtains.03_East_Glass",
    "House.Parts.InteriorLayout.Curtains.04_Front_Glass",
    "House.Parts.InteriorLayout.Curtains.05_Front_Glass",
    "House.Parts.InteriorLayout.Curtains.06_UtilityBack_Glass",
    "House.Parts.InteriorLayout.Curtains.07_West_Glass",
    "House.Parts.InteriorLayout.Curtains.08_West_Glass",
}

Shared.Litter = { Session = nil, Collected = {}, Won = false }

local function Attr(name)
    return workspace:GetAttribute(name)
end

local function FirePrompt(path)
    FirePP(GetObject(workspace, path), true)
end

local function BagSpot()
    local bag = GetObject(Plr, "PlayerGui.LitterCleaningGui.Panel.Board.Bag")
    if not bag then
        return 0.5, 0.5
    end
    return bag.Position.X.Scale + bag.Size.X.Scale / 2, bag.Position.Y.Scale + bag.Size.Y.Scale / 2
end

local function SleepReady()
    for _, name in ipairs(CHORES) do
        if Attr("Chore_" .. name) ~= true then
            return false
        end
    end
    for _, name in ipairs(ANOMALIES) do
        if Attr(name) == true then
            return false
        end
    end
    return true
end

local ChoreFlows = {
    Feed = function()
        FirePrompt("House.Important.Kitchen.Cabinets.Base_N1.CatFoodCan.CanBody.TakePromptAttachment.TakePrompt")
        task.wait(0.4)
        FirePrompt("House.Important.Kitchen.FoodBowl.Food Bowl.Cylinder.FillPromptAttachment.FillPrompt")
    end,
    Eat = function()
        FirePrompt("House.Important.Kitchen.Fridge.TVDinner.Tray.TakePromptAttachment.TakePrompt")
        task.wait(0.5)
        local bp = Plr:FindFirstChild("Backpack")
        local char = GetCharacter()
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if bp and hum then
            for _, t in ipairs(bp:GetChildren()) do
                if t:IsA("Tool") and t:GetAttribute("Meal") then
                    hum:EquipTool(t)
                    break
                end
            end
        end
        task.wait(0.3)
        FirePrompt("House.Important.Kitchen.Cabinets.Microwave.Carcass.Turntable.CookPromptAttachment.CookPrompt")
        task.wait(10)
        FirePrompt("House.Important.Kitchen.Cabinets.Microwave.Carcass.Turntable.CookPromptAttachment.CookPrompt")
        task.wait(1)
        if bp and hum then
            for _, t in ipairs(bp:GetChildren()) do
                if t:IsA("Tool") and t:GetAttribute("Meal") and t:GetAttribute("Hot") then
                    hum:EquipTool(t)
                    task.wait(0.3)
                    if Remotes.Eat then
                        Remotes.Eat:FireServer()
                    end
                    break
                end
            end
        end
    end,
    Litter = function()
        FirePrompt("House.Parts.Laundry.LitterBox.LitterInteraction.CleanLitterPrompt")
    end,
    Mail = function()
        FirePrompt("Neighborhood.Parts.PetsitFrontYard.Mailbox.Body.MailboxPromptAttachment.MailboxPrompt")
    end,
    Play = function()
        FirePrompt("House.Important.LivingRoom.LaserPointer.Body.TakePromptAttachment.TakePrompt")
        task.wait(0.5)
        local bp = Plr:FindFirstChild("Backpack")
        local char = GetCharacter()
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local cat = workspace:FindFirstChild("Cat")
        local anchor = cat and (cat.PrimaryPart or cat:FindFirstChildWhichIsA("BasePart"))
        if bp and hum and anchor then
            for _, t in ipairs(bp:GetChildren()) do
                if t:IsA("Tool") and t:GetAttribute("Laser") then
                    hum:EquipTool(t)
                    break
                end
            end
            task.wait(0.3)
            local deadline = os.clock() + LASER_PLAY_SECONDS
            while os.clock() < deadline and Attr("Chore_Play") ~= true do
                if Remotes.Laser then
                    Remotes.Laser:FireServer(anchor.Position + Vector3.new(math.random(-6, 6), -1.5, math.random(-6, 6)), true)
                end
                task.wait(0.12)
            end
            if Remotes.Laser then
                Remotes.Laser:FireServer(nil, false)
            end
            hum:UnequipTools()
        end
    end,
    Lock = function()
        local door = GetObject(workspace, "House.Important.Doors.Front Door")
        if door and door:GetAttribute("Locked") ~= true then
            FirePrompt("House.Important.Doors.Front Door.Leaf.Deadbolt.LockPromptAttachment.LockPrompt")
        end
    end,
}

local function StepChores()
    if not workspace:FindFirstChild("House") then
        return
    end
    for _, name in ipairs(CHORES) do
        if Attr("Chore_" .. name) ~= true then
            ChoreFlows[name]()
            task.wait(0.4)
        end
    end
end

local function Func_AutoChores()
    while Toggles.AutoChores.Value do
        local ok, err = pcall(StepChores)
        if not ok then
            notyuri("AutoChores", err)
        end
        task.wait(CHORE_INTERVAL)
    end
end

local function Func_AutoPet()
    while Toggles.AutoPet.Value do
        local ok, err = pcall(function()
            local cat = workspace:FindFirstChild("Cat")
            local char = GetCharacter()
            if cat and char and Remotes.Pet then
                local part = cat.PrimaryPart or cat:FindFirstChildWhichIsA("BasePart")
                if part and (part.Position - char.HumanoidRootPart.Position).Magnitude <= 40 then
                    Remotes.Pet:FireServer()
                end
            end
        end)
        if not ok then
            notyuri("AutoPet", err)
        end
        task.wait(0.4)
    end
end

local function Func_AutoSleep()
    while Toggles.AutoSleep.Value do
        local ok, err = pcall(function()
            if not workspace:FindFirstChild("House") or not SleepReady() then
                return
            end
            local fridgeDoor = GetObject(workspace, "House.Important.Kitchen.Fridge.FridgeDoor")
            if fridgeDoor and fridgeDoor:GetAttribute("Open") == true then
                FirePrompt("House.Important.Kitchen.Fridge.FridgeDoor.Leaf.Panel.OpenClosePromptAttachment.OpenClosePrompt")
                task.wait(0.4)
            end
            FirePrompt("House.Parts.Bedroom.Mattress.SleepPromptAttachment.SleepPrompt")
        end)
        if not ok then
            notyuri("AutoSleep", err)
        end
        task.wait(10)
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
            notyuri("AutoQueue", err)
        end
        task.wait(3)
    end
end

local function Func_AutoOpenCrate()
    while Toggles.AutoOpenCrate.Value do
        local ok, err = pcall(function()
            if not (Remotes.GetState and Remotes.OpenCrate) then
                return
            end
            local state = SafeInvoke(Remotes.GetState)
            if type(state) ~= "table" or type(state.cash) ~= "number" then
                return
            end
            while state.cash >= 10 do
                local result = SafeInvoke(Remotes.OpenCrate)
                if type(result) ~= "table" or not result.ok then
                    break
                end
                if type(result.state) == "table" and type(result.state.cash) == "number" then
                    state = result.state
                end
                task.wait(0.5)
            end
        end)
        if not ok then
            notyuri("AutoOpenCrate", err)
        end
        task.wait(5)
    end
end

SafeConnect("Litter", function()
    return Remotes.Litter and Remotes.Litter.OnClientEvent
end, function(action, sid, data)
    if action == "Start" then
        Shared.Litter.Session = sid
        Shared.Litter.Collected = {}
        Shared.Litter.Won = false
        Thread("LitterDrive", function()
            local deadline = os.clock() + 60
            while os.clock() < deadline and Shared.Litter.Session == sid and not Shared.Litter.Won do
                local bx, by = BagSpot()
                for i = 1, 5 do
                    if Shared.Litter.Session ~= sid or Shared.Litter.Won then
                        break
                    end
                    if not Shared.Litter.Collected[i] then
                        if Remotes.Litter then
                            Remotes.Litter:FireServer("Grab", sid, i)
                            task.wait(0.15)
                            if Shared.Litter.Session == sid and not Shared.Litter.Won then
                                Remotes.Litter:FireServer("Drop", sid, i, bx, by)
                            end
                            task.wait(0.3)
                        end
                    end
                end
                task.wait(0.5)
            end
        end, true)
    elseif action == "Collected" then
        if type(data) == "table" and data.index then
            Shared.Litter.Collected[data.index] = true
        end
    elseif action == "Win" or action == "End" then
        if Shared.Litter.Session == sid then
            Shared.Litter.Won = true
            Shared.Litter.Session = nil
        end
    end
end)

SafeConnect("Grandma", function()
    return workspace:GetAttributeChangedSignal("Grandma")
end, function()
    if not (Toggles.AutoAnomalies.Value and Attr("Grandma") == true) then
        return
    end
    task.spawn(function()
        for _, path in ipairs(LIGHT_SWITCHES) do
            local model = GetObject(workspace, path)
            if model and model:GetAttribute("On") == true then
                FirePrompt(path .. ".Faceplate.Interaction.LightSwitchPrompt")
                task.wait(0.1)
            end
        end
    end)
end)

SafeConnect("VoidOutside", function()
    return workspace:GetAttributeChangedSignal("VoidOutside")
end, function()
    if not (Toggles.AutoAnomalies.Value and Attr("VoidOutside") == true) then
        return
    end
    task.spawn(function()
        for _, path in ipairs(BLINDS) do
            local model = GetObject(workspace, path)
            if model and model:GetAttribute("BlindsClosed") ~= true then
                FirePrompt(path .. ".BlindsPromptAnchor.BlindsPrompt")
                task.wait(0.1)
            end
        end
    end)
end)

SafeConnect("Catzilla", function()
    return workspace:GetAttributeChangedSignal("Catzilla")
end, function()
    if not (Toggles.AutoAnomalies.Value and Attr("Catzilla") == true) then
        return
    end
    task.spawn(function()
        local tv = GetObject(workspace, "House.Important.LivingRoom.TV")
        if tv and tv:GetAttribute("On") ~= true then
            FirePrompt("House.Important.LivingRoom.TV.Screen.TogglePromptAttachment.TogglePrompt")
        end
    end)
end)

SafeConnect("ToiletFace", function()
    return workspace:GetAttributeChangedSignal("ToiletFace")
end, function()
    if not (Toggles.AutoAnomalies.Value and Attr("ToiletFace") == true) then
        return
    end
    task.spawn(function()
        FirePrompt("House.Important.Bathroom.Toilet.Flush.Lever.FlushPromptAttachment.FlushPrompt")
    end)
end)

SafeConnect("CreepyHead", function()
    return workspace:GetAttributeChangedSignal("CreepyHead")
end, function()
    if not (Toggles.AutoAnomalies.Value and Attr("CreepyHead") == true) then
        return
    end
    Thread("CreepyStare", function()
        while Toggles.AutoAnomalies.Value and Attr("CreepyHead") == true do
            local cat = workspace:FindFirstChild("Cat")
            local head = cat and cat:FindFirstChild("CreepyCatHead")
            local hp = head and (head.PrimaryPart or head:FindFirstChildWhichIsA("BasePart"))
            if hp then
                TPTo(hp, Vector3.new(0, 0, 15))
                if Remotes.Stare then
                    Remotes.Stare:FireServer(0.4)
                end
            end
            task.wait(0.4)
        end
    end, true)
end)

SafeConnect("SmilingMan", function()
    return workspace:GetAttributeChangedSignal("SmilingMan")
end, function()
    if not (Toggles.AutoPhoto.Value and Attr("SmilingMan") == true) then
        return
    end
    Thread("PhotoSmilingMan", function()
        while Toggles.AutoPhoto.Value and Attr("SmilingMan") == true do
            local model = workspace:FindFirstChild("SmilingMan")
            local part = model and (model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true))
            if part and Remotes.Photo then
                local char = GetCharacter()
                local base = char and char.HumanoidRootPart.Position or part.Position + Vector3.new(12, 2, 0)
                local dir = base - part.Position
                local dist = dir.Magnitude
                local eye = part.Position + (dist >= 0.01 and dir * (12 / dist) or Vector3.new(12, 2, 0))
                TPTo(CFrame.new(eye))
                Remotes.Photo:FireServer(CFrame.lookAt(eye, part.Position), part)
            end
            task.wait(1)
        end
    end, true)
end)

SafeConnect("Misplaced", function()
    return workspace:GetAttributeChangedSignal("Misplaced")
end, function()
    if not (Toggles.AutoPhoto.Value and Attr("Misplaced") == true) then
        return
    end
    Thread("PhotoMisplaced", function()
        local shot = {}
        while Toggles.AutoPhoto.Value and Attr("Misplaced") == true do
            local house = workspace:FindFirstChild("House")
            if house then
                for _, rootName in ipairs({ "Important", "Parts" }) do
                    local root = house:FindFirstChild(rootName)
                    if root then
                        for _, room in ipairs(root:GetChildren()) do
                            for _, item in ipairs(room:GetChildren()) do
                                if item:IsA("Model") and not shot[item] and Attr("Misplaced") == true then
                                    local part = item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart", true)
                                    if part and Remotes.Photo then
                                        shot[item] = true
                                        local char = GetCharacter()
                                        local base = char and char.HumanoidRootPart.Position or part.Position + Vector3.new(10, 2, 0)
                                        local dir = base - part.Position
                                        local dist = dir.Magnitude
                                        local eye = part.Position + (dist >= 0.01 and dir * (10 / dist) or Vector3.new(10, 2, 0))
                                        TPTo(CFrame.new(eye))
                                        Remotes.Photo:FireServer(CFrame.lookAt(eye, part.Position), part)
                                        task.wait(0.4)
                                    end
                                end
                            end
                        end
                    end
                    if Attr("Misplaced") ~= true then
                        return
                    end
                end
            end
            task.wait(10)
        end
    end, true)
end)

TB_Tabs.Autofarm.T1:AddDivider()
TB_Tabs.Autofarm.T1:AddToggle("AutoChores", { Text = "Auto Chores" })
TB_Tabs.Autofarm.T1:AddToggle("AutoPet", { Text = "Auto Pet" })
TB_Tabs.Autofarm.T1:AddToggle("AutoAnomalies", { Text = "Auto Anomalies" })
TB_Tabs.Autofarm.T1:AddToggle("AutoPhoto", { Text = "Auto Photo" })
TB_Tabs.Autofarm.T1:AddToggle("AutoSleep", { Text = "Auto Sleep" })
TB_Tabs.Autofarm.T1:AddDivider()
TB_Tabs.Autofarm.T1:AddToggle("AutoQueue", { Text = "Auto Queue" })
TB_Tabs.Autofarm.T1:AddToggle("AutoOpenCrate", { Text = "Auto Open Crate" })

Toggles.AutoChores:OnChanged(function(state)
    if not state and Shared.Litter.Session and Remotes.Litter then
        Remotes.Litter:FireServer("Cancel", Shared.Litter.Session)
    end
    Thread("AutoChores", SafeLoop("AutoChores", Func_AutoChores), state)
end)
Toggles.AutoPet:OnChanged(function(state)
    Thread("AutoPet", SafeLoop("AutoPet", Func_AutoPet), state)
end)
Toggles.AutoSleep:OnChanged(function(state)
    Thread("AutoSleep", SafeLoop("AutoSleep", Func_AutoSleep), state)
end)
Toggles.AutoQueue:OnChanged(function(state)
    Thread("AutoQueue", SafeLoop("AutoQueue", Func_AutoQueue), state)
end)
Toggles.AutoOpenCrate:OnChanged(function(state)
    Thread("AutoOpenCrate", SafeLoop("AutoOpenCrate", Func_AutoOpenCrate), state)
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
