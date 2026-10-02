local NetRemotes = RS:WaitForChild("Packages"):WaitForChild("_Index"):WaitForChild("leifstout_networker@0.3.1"):WaitForChild("networker"):WaitForChild("_remotes")
Remotes.CombatEvent = NetRemotes:WaitForChild("Combat"):WaitForChild("RemoteEvent")
Remotes.AscensionFunc = NetRemotes:WaitForChild("Ascension"):WaitForChild("RemoteFunction")
Remotes.EvolutionFunc = NetRemotes:WaitForChild("Evolution"):WaitForChild("RemoteFunction")
Remotes.ShopFunc = NetRemotes:WaitForChild("Shop"):WaitForChild("RemoteFunction")
Remotes.RollFunc = NetRemotes:WaitForChild("Roll"):WaitForChild("RemoteFunction")
Remotes.RebirthFunc = NetRemotes:WaitForChild("Rebirth"):WaitForChild("RemoteFunction")
local CombatClient = nil
local PlayerDataClient = nil
do
    local okS, SourceRoot = pcall(function() return RS:WaitForChild("Source") end)
    if okS and SourceRoot then
        local okC, modC = pcall(function()
            return require(SourceRoot:WaitForChild("Features"):WaitForChild("Combat"):WaitForChild("CombatClient"))
        end)
        if okC then CombatClient = modC end
        local okP, modP = pcall(function()
            return require(SourceRoot:WaitForChild("Features"):WaitForChild("PlayerData"):WaitForChild("PlayerDataClient"))
        end)
        if okP then PlayerDataClient = modP end
    end
end
local EnemyUids = {}
local function GetEnemies()
    EnemyUids = {}
    local list = {}
    if CombatClient and CombatClient.getEnemyModels then
        local ok, models = pcall(function() return CombatClient:getEnemyModels() end)
        if ok and type(models) == "table" then
            for uid, entry in pairs(models) do
                local m = entry and entry.model
                if m and m.Parent then
                    local okPart, isBase = pcall(function() return m:IsA("BasePart") end)
                    if okPart and isBase then
                        EnemyUids[m] = uid
                        list[#list + 1] = m
                    end
                end
            end
        end
    end
    return list
end
local function GetSwordUid()
    if PlayerDataClient and PlayerDataClient.get then
        local ok, data = pcall(function() return PlayerDataClient:get() end)
        if ok and type(data) == "table" and type(data.equipped) == "table" then
            for _, uid in pairs(data.equipped) do
                return uid
            end
        end
    end
    return nil
end
local function Func_AutoAttack()
    while Toggles.AutoAttack.Value do
        local ok, err = pcall(function()
            local char = GetCharacter()
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            local swordUid = GetSwordUid()
            if hrp and swordUid then
                local target = GetNearest(GetEnemies())
                local targetUid = target and EnemyUids[target] or nil
                Remotes.CombatEvent:FireServer("requestHit", swordUid, targetUid, hrp.Position)
            end
        end)
        if not ok then notyuri("Auto Attack error: " .. tostring(err)) end
        task.wait(0.5)
    end
end
local function Func_AutoRoll()
    while Toggles.AutoRoll.Value do
        local ok, err = pcall(function()
            SafeInvoke(Remotes.RollFunc, true, "roll")
        end)
        if not ok then notyuri("Auto Roll error: " .. tostring(err)) end
        task.wait(1)
    end
end
local function Func_AutoRebirth()
    while Toggles.AutoRebirth.Value do
        local ok, err = pcall(function()
            SafeInvoke(Remotes.RebirthFunc, true, "requestRebirth")
        end)
        if not ok then notyuri("Auto Rebirth error: " .. tostring(err)) end
        task.wait(30)
    end
end
local function Func_AutoAscend()
    while Toggles.AutoAscend.Value do
        local ok, err = pcall(function()
            SafeInvoke(Remotes.AscensionFunc, true, "ascend", nil)
        end)
        if not ok then notyuri("Auto Ascend error: " .. tostring(err)) end
        task.wait(30)
    end
end
local function Func_AutoEvolve()
    while Toggles.AutoEvolve.Value do
        local ok, err = pcall(function()
            SafeInvoke(Remotes.EvolutionFunc, true, "evolve", nil)
        end)
        if not ok then notyuri("Auto Evolve error: " .. tostring(err)) end
        task.wait(30)
    end
end
local function Func_AutoRestock()
    while Toggles.AutoRestock.Value do
        local ok, err = pcall(function()
            SafeInvoke(Remotes.ShopFunc, true, "restock")
        end)
        if not ok then notyuri("Auto Restock error: " .. tostring(err)) end
        task.wait(60)
    end
end
TB_Tabs.Autofarm.T1:AddDivider()
TB_Tabs.Autofarm.T1:AddToggle("AutoAttack", { Text = "Auto Attack", Default = false })
Toggles.AutoAttack:OnChanged(function(state)
    Thread("AutoAttack", SafeLoop("Auto Attack", Func_AutoAttack), state)
end)
TB_Tabs.Autofarm.T1:AddDivider()
TB_Tabs.Autofarm.T1:AddToggle("AutoRoll", { Text = "Auto Roll", Default = false })
Toggles.AutoRoll:OnChanged(function(state)
    Thread("AutoRoll", SafeLoop("Auto Roll", Func_AutoRoll), state)
end)
TB_Tabs.Autofarm.T1:AddToggle("AutoRebirth", { Text = "Auto Rebirth", Default = false })
Toggles.AutoRebirth:OnChanged(function(state)
    Thread("AutoRebirth", SafeLoop("Auto Rebirth", Func_AutoRebirth), state)
end)
TB_Tabs.Autofarm.T1:AddDivider()
TB_Tabs.Autofarm.T1:AddToggle("AutoAscend", { Text = "Auto Ascend", Default = false })
Toggles.AutoAscend:OnChanged(function(state)
    Thread("AutoAscend", SafeLoop("Auto Ascend", Func_AutoAscend), state)
end)
TB_Tabs.Autofarm.T1:AddToggle("AutoEvolve", { Text = "Auto Evolve", Default = false })
Toggles.AutoEvolve:OnChanged(function(state)
    Thread("AutoEvolve", SafeLoop("Auto Evolve", Func_AutoEvolve), state)
end)
TB_Tabs.Autofarm.T1:AddToggle("AutoRestock", { Text = "Auto Restock", Default = false })
Toggles.AutoRestock:OnChanged(function(state)
    Thread("AutoRestock", SafeLoop("Auto Restock", Func_AutoRestock), state)
end)
