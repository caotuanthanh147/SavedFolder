local realRS = game:GetService("ReplicatedStorage")
local SmashFolder = realRS:FindFirstChild("Smash")
local CoreFolder = SmashFolder and SmashFolder:FindFirstChild("Core")

Shared.Modules = nil
Shared.Adapter = nil
Shared.Callbacks = nil
Shared.Fire = { Points = {}, Index = 1, Waiting = false }
Shared.Specs = { Table = nil, Backup = nil, Zeroed = false }
Shared.Earn = { At = 0, Wired = false }
Shared.Reset = { At = 0 }

local GetUpvalues = missing("function", getupvalues, missing("function", get_up_values, nil))

local function ResolveModules()
    local M = {}
    M.Config = SmashFolder and GetSafeModule(SmashFolder, "Config") or nil
    M.Economy = CoreFolder and GetSafeModule(CoreFolder, "Economy") or nil
    M.Cooldowns = CoreFolder and GetSafeModule(CoreFolder, "Cooldowns") or nil
    M.Destruction = CoreFolder and GetSafeModule(CoreFolder, "Destruction") or nil
    M.Challenges = CoreFolder and GetSafeModule(CoreFolder, "Challenges") or nil
    M.UI = CoreFolder and GetSafeModule(CoreFolder, "UI") or nil
    M.Input = CoreFolder and GetSafeModule(CoreFolder, "Input") or nil
    return M
end
Shared.Modules = ResolveModules()

local function FindUpvalue(fn, check)
    if not fn or not GetUpvalues then
        return nil
    end
    local ok, ups = pcall(GetUpvalues, fn)
    if not ok or type(ups) ~= "table" then
        return nil
    end
    for _, value in pairs(ups) do
        if check(value) then
            return value
        end
    end
    return nil
end

local function GetAdapter()
    local M = Shared.Modules
    return FindUpvalue(M.Input and M.Input.start, function(v)
        return type(v) == "table"
            and type(v.call) == "function"
            and type(v.getWeapon) == "function"
            and type(v.pick) == "function"
    end)
end

local function GetCallbacks()
    local M = Shared.Modules
    return FindUpvalue(M.UI and M.UI.build, function(v)
        return type(v) == "table"
            and type(v.onSelect) == "function"
            and type(v.onReset) == "function"
    end)
end

local function GetSpecs()
    local M = Shared.Modules
    return FindUpvalue(M.Cooldowns and M.Cooldowns.spec, function(v)
        return type(v) == "table"
            and type(v.Nuke) == "table"
            and type(v.Nuke.t) == "number"
            and type(v.Meteor) == "table"
    end)
end

local function TrackEarn()
    local M = Shared.Modules
    if Shared.Earn.Wired then
        return
    end
    if not (M.Economy and M.Economy.onChanged) then
        return
    end
    Shared.Earn.Wired = true
    M.Economy.onChanged(function(_, delta)
        if type(delta) == "number" and delta > 0 then
            Shared.Earn.At = os.clock()
        end
    end)
end
TrackEarn()

local function BuildFirePoints()
    local M = Shared.Modules
    local cfg = M.Config
    local half = (cfg and cfg.CITY_HALF) or 440
    local groundY = (cfg and cfg.GROUND_Y) or 0
    local points = {}
    for _, z in ipairs({ -120, -40, 40, 120 }) do
        local x = -half + 65
        while x <= half - 65 do
            table.insert(points, Vector3.new(x, groundY, z))
            x = x + 125
        end
    end
    return points
end

local function Func_AutoFire()
    while Toggles.AutoFire.Value do
        local ok, err = pcall(function()
            local M = Shared.Modules
            if not Shared.Adapter then
                Shared.Adapter = GetAdapter()
            end
            local adapter = Shared.Adapter
            if not adapter then
                return
            end
            local weaponId = Options.AutoFireWeapon.Value
            if type(weaponId) ~= "string" then
                return
            end
            if not (M.Economy and M.Economy.owns and M.Economy.owns("weapon", weaponId)) then
                if not Shared.Fire.Waiting then
                    Shared.Fire.Waiting = true
                    Library:Notify("Waiting for weapon: " .. weaponId, 4)
                end
                return
            end
            Shared.Fire.Waiting = false
            if not Shared.Callbacks then
                Shared.Callbacks = GetCallbacks()
            end
            if Shared.Callbacks then
                Shared.Callbacks.onSelect(weaponId)
            end
            if Toggles.AutoCityReset.Value and M.Destruction then
                local stats = M.Destruction.getStats and M.Destruction.getStats()
                if type(stats) == "table" and stats.destroyed >= 0.97 then
                    return
                end
            end
            if #Shared.Fire.Points == 0 then
                Shared.Fire.Points = BuildFirePoints()
            end
            local points = Shared.Fire.Points
            if Shared.Fire.Index > #points then
                Shared.Fire.Index = 1
            end
            local pos = points[Shared.Fire.Index]
            Shared.Fire.Index = Shared.Fire.Index + 1
            adapter.call("onTap", pos)
        end)
        if not ok then
            notyuri("AutoFire", err)
        end
        task.wait(Options.AutoFireDelay.Value)
    end
end

local function Func_AutoCityReset()
    while Toggles.AutoCityReset.Value do
        local ok, err = pcall(function()
            local M = Shared.Modules
            if not (M.Destruction and M.Destruction.getStats) then
                return
            end
            if not Shared.Callbacks then
                Shared.Callbacks = GetCallbacks()
            end
            local callbacks = Shared.Callbacks
            if not callbacks then
                return
            end
            local stats = M.Destruction.getStats()
            if type(stats) ~= "table" then
                return
            end
            local now = os.clock()
            if now - Shared.Reset.At < 5 then
                return
            end
            local threshold = Options.AutoCityPct.Value / 100
            if stats.destroyed >= threshold then
                Shared.Reset.At = now
                callbacks.onReset()
                return
            end
            if stats.destroyed > 0.1 and Shared.Earn.At > 0 and now - Shared.Earn.At > 12 then
                Shared.Reset.At = now
                Shared.Earn.At = now
                callbacks.onReset()
            end
        end)
        if not ok then
            notyuri("AutoCityReset", err)
        end
        task.wait(1)
    end
end

local function Func_AutoBuy()
    while Toggles.AutoBuy.Value do
        local ok, err = pcall(function()
            local M = Shared.Modules
            local eco = M.Economy
            local cfg = M.Config
            if not (eco and cfg and cfg.SHOP) then
                return
            end
            for _, kind in ipairs({ "weapon", "map" }) do
                local source = kind == "weapon" and cfg.SHOP.WEAPONS or cfg.SHOP.MAPS
                if type(source) == "table" then
                    local list = {}
                    for id in pairs(source) do
                        if not eco.owns(kind, id) then
                            table.insert(list, { id = id, price = eco.price(kind, id) })
                        end
                    end
                    table.sort(list, function(a, b)
                        return a.price < b.price
                    end)
                    local target = list[1]
                    if target and eco.canAfford(kind, target.id) then
                        eco.buy(kind, target.id)
                    end
                end
            end
        end)
        if not ok then
            notyuri("AutoBuy", err)
        end
        task.wait(5)
    end
end

local function Func_AutoClaim()
    while Toggles.AutoClaim.Value do
        local ok, err = pcall(function()
            local M = Shared.Modules
            local ch = M.Challenges
            local eco = M.Economy
            if not (ch and eco and eco.loaded and type(eco.loaded()) == "table") then
                return
            end
            if ch.daily and ch.claimDaily then
                local daily = ch.daily()
                if type(daily) == "table" and daily.claimed == false then
                    ch.claimDaily()
                end
            end
            if ch.challenges and ch.claimChallenge then
                local info = ch.challenges()
                if type(info) == "table" and type(info.list) == "table" then
                    for _, entry in ipairs(info.list) do
                        if entry.done and not entry.claimed then
                            ch.claimChallenge(entry.i)
                        end
                    end
                end
            end
        end)
        if not ok then
            notyuri("AutoClaim", err)
        end
        task.wait(30)
    end
end

local function ApplyNoCooldown(state)
    local M = Shared.Modules
    if not (M.Cooldowns and M.Cooldowns.spec and GetUpvalues) then
        if state then
            Library:Notify("NoCooldown unsupported on this executor", 4)
            Toggles.NoCooldown:SetValue(false)
        end
        return
    end
    if state then
        if Shared.Specs.Zeroed then
            return
        end
        if not Shared.Specs.Table then
            Shared.Specs.Table = GetSpecs()
        end
        local specs = Shared.Specs.Table
        if not specs then
            Library:Notify("Cooldown specs not found", 4)
            Toggles.NoCooldown:SetValue(false)
            return
        end
        local backup = {}
        for id, spec in pairs(specs) do
            if type(spec) == "table" and type(spec.t) == "number" then
                backup[id] = spec.t
                spec.t = 0
            end
        end
        Shared.Specs.Backup = backup
        Shared.Specs.Zeroed = true
    else
        if not Shared.Specs.Zeroed then
            return
        end
        local specs = Shared.Specs.Table
        for id, t in pairs(Shared.Specs.Backup) do
            local spec = specs[id]
            if type(spec) == "table" then
                spec.t = t
            end
        end
        Shared.Specs.Backup = {}
        Shared.Specs.Zeroed = false
    end
end

local function AddCheatCash()
    local M = Shared.Modules
    if not (M.Economy and M.Economy.setCash and M.Economy.cash) then
        Library:Notify("Economy unavailable", 4)
        return
    end
    local amount = tonumber(Options.CheatCashAmount.Value) or 1000000
    M.Economy.setCash(M.Economy.cash() + amount)
    Library:Notify("Cash: " .. CommaFormat(M.Economy.cash()), 3)
end

local function DoUnlockAll()
    local M = Shared.Modules
    if not (M.Economy and M.Economy.unlockAll) then
        Library:Notify("Economy unavailable", 4)
        return
    end
    M.Economy.unlockAll()
    Library:Notify("All weapons and maps unlocked", 3)
end

local weaponValues = {}
do
    local cfg = Shared.Modules.Config
    if cfg and cfg.SHOP and type(cfg.SHOP.WEAPONS) == "table" then
        for id in pairs(cfg.SHOP.WEAPONS) do
            table.insert(weaponValues, id)
        end
        table.sort(weaponValues)
    end
end

TB_Tabs.Autofarm.T1:AddToggle("AutoFire", { Text = "Auto Fire" })
TB_Tabs.Autofarm.T1:AddDropdown("AutoFireWeapon", {
    Text = "Weapon",
    Values = weaponValues,
    Default = (table.find(weaponValues, "Nuke") and "Nuke") or weaponValues[1],
})
TB_Tabs.Autofarm.T1:AddSlider("AutoFireDelay", {
    Text = "Fire Delay",
    Default = 0.35,
    Min = 0.15,
    Max = 2,
    Rounding = 2,
    Suffix = "s",
})
TB_Tabs.Autofarm.T1:AddDivider()
TB_Tabs.Autofarm.T1:AddToggle("AutoCityReset", { Text = "Auto City Reset" })
TB_Tabs.Autofarm.T1:AddSlider("AutoCityPct", {
    Text = "Reset At",
    Default = 85,
    Min = 50,
    Max = 100,
    Rounding = 0,
    Suffix = "%",
})
TB_Tabs.Autofarm.T1:AddDivider()
TB_Tabs.Autofarm.T1:AddToggle("NoCooldown", { Text = "No Cooldown" })
TB_Tabs.Autofarm.T1:AddDivider()
TB_Tabs.Autofarm.T1:AddToggle("AutoBuy", { Text = "Auto Buy" })
TB_Tabs.Autofarm.T1:AddToggle("AutoClaim", { Text = "Auto Claim" })
TB_Tabs.Autofarm.T1:AddDivider()
TB_Tabs.Autofarm.T1:AddInput("CheatCashAmount", {
    Text = "Cheat Amount",
    Default = "1000000",
    Numeric = true,
})
TB_Tabs.Autofarm.T1:AddButton({ Text = "Add Cash", Func = AddCheatCash })
TB_Tabs.Autofarm.T1:AddButton({ Text = "Unlock All", Func = DoUnlockAll })

Toggles.AutoFire:OnChanged(function(state)
    Thread("AutoFire", SafeLoop("AutoFire", Func_AutoFire), state)
end)
Toggles.AutoCityReset:OnChanged(function(state)
    Thread("AutoCityReset", SafeLoop("AutoCityReset", Func_AutoCityReset), state)
end)
Toggles.NoCooldown:OnChanged(function(state)
    ApplyNoCooldown(state)
end)
Toggles.AutoBuy:OnChanged(function(state)
    Thread("AutoBuy", SafeLoop("AutoBuy", Func_AutoBuy), state)
end)
Toggles.AutoClaim:OnChanged(function(state)
    Thread("AutoClaim", SafeLoop("AutoClaim", Func_AutoClaim), state)
end)
Library:OnUnload(function()
    if Shared.Specs.Zeroed then
        ApplyNoCooldown(false)
    end
end)
