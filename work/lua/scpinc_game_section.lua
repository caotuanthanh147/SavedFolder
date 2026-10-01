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
