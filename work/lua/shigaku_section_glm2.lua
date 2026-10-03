local realRS = game:GetService("ReplicatedStorage")
local realPlayers = game:GetService("Players")
local realCS = game:GetService("CollectionService")
local realPlr = realPlayers.LocalPlayer

local function ResolveModules()
    local M = {}
    M.Settings = GetSafeModule(GetObject(realRS, "Shared.Modules.Global.Libraries"), "Game_Settings")
    M.Muscle = GetSafeModule(GetObject(realRS, "Shared.Modules.Shared"), "Muscle")
    M.GymWeights = GetSafeModule(GetObject(realRS, "Shared.Modules.Shared"), "GymWeights")
    M.BridgeNet2 = GetSafeModule(GetObject(realRS, "Packages"), "BridgeNet2")
    local clientScripts = realPlr and realPlr:FindFirstChild("PlayerScripts") and realPlr.PlayerScripts:FindFirstChild("Client")
    if clientScripts then
        M.Input = GetSafeModule(clientScripts, "Input")
        M.Combat = GetSafeModule(clientScripts, "Combat")
        M.Data = GetSafeModule(clientScripts, "Data")
        local gymScript = clientScripts:FindFirstChild("Gym")
        M.Gym = GetSafeModule(clientScripts, "Gym")
        if gymScript then
            M.Balance = GetSafeModule(gymScript, "Balance")
            M.Stride = GetSafeModule(gymScript, "Stride")
            M.Grip = GetSafeModule(gymScript, "Grip")
            M.Reps = GetSafeModule(gymScript, "Reps")
        end
    end
    if M.Input and M.Settings and M.BridgeNet2 and M.Settings.Gym then
        Shared.Modules = M
        if not Remotes.Gym then
            Remotes.Gym = M.BridgeNet2.ReferenceBridge(M.Settings.Gym.Bridge)
        end
        local values = {}
        for _, kind in ipairs(M.Settings.Gym.Kinds) do
            table.insert(values, kind.Label or kind.Lift)
        end
        if #values > 0 and Options.GymKind then
            Options.GymKind:SetValues(values)
            if not Options.GymKind.Value then
                Options.GymKind:SetValue(values[1])
            end
        end
    end
    return M
end

local function GymKindByLabel()
    local map = {}
    local M = Shared.Modules
    if M and M.Settings and M.Settings.Gym then
        for _, kind in ipairs(M.Settings.Gym.Kinds) do
            map[kind.Label or kind.Lift] = kind
        end
    end
    return map
end

local function GymActiveGame()
    local M = Shared.Modules
    if not M then
        return nil
    end
    if M.Balance and M.Balance.Active() then
        return "Balance"
    end
    if M.Grip and M.Grip.Active() then
        return "Grip"
    end
    if M.Stride and M.Stride.Active() then
        return "Stride"
    end
    if M.Reps and M.Reps.Active() then
        return "Reps"
    end
    return nil
end

local function GymTapStep()
    local M = Shared.Modules
    local Input = M and M.Input
    if not Input then
        return false
    end
    local active = GymActiveGame()
    local now = os.clock()
    if active == "Balance" then
        local tilt = M.Balance.Tilt()
        if math.abs(tilt) > 0.15 and now - (Shared.GymBalanceTap or 0) > 0.2 then
            Shared.GymBalanceTap = now
            if tilt > 0 then
                Input.Fire("Gym.LeanLeft", true)
            else
                Input.Fire("Gym.LeanRight", true)
            end
        end
        return true
    end
    if active == "Grip" then
        local window = M.Grip.Window()
        if M.Grip.Hand(-1) <= window and not M.Grip.Locked(-1) then
            Input.Fire("Gym.LeanLeft", true)
        end
        if M.Grip.Hand(1) <= window and not M.Grip.Locked(1) then
            Input.Fire("Gym.LeanRight", true)
        end
        return true
    end
    if active == "Stride" then
        if now - (Shared.GymStrideTap or 0) > 0.4 then
            Shared.GymStrideTap = now
            Shared.GymStrideSide = -(Shared.GymStrideSide or 1)
            if Shared.GymStrideSide < 0 then
                Input.Fire("Gym.LeanLeft", true)
            else
                Input.Fire("Gym.LeanRight", true)
            end
        end
        return true
    end
    if active == "Reps" then
        local reps = M.Settings and M.Settings.Gym and M.Settings.Gym.Reps
        local interval = reps and 2 / (reps.BandLow + reps.BandHigh) or 0.625
        if now - (Shared.GymRepsTap or 0) >= interval then
            Shared.GymRepsTap = now
            Input.Fire("Gym.LeanLeft", true)
        end
        return true
    end
    return false
end

local function GymStartSession()
    local M = Shared.Modules
    if not (M and M.Input and M.Settings and M.Muscle and M.GymWeights and Remotes.Gym) then
        return false
    end
    local char = GetCharacter()
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then
        return false
    end
    if char:GetAttribute(M.Settings.Gym.WindedAttribute) then
        return false
    end
    local kind = GymKindByLabel()[Options.GymKind.Value]
    if not kind then
        return false
    end
    local station = GetNearest(realCS:GetTagged(kind.Tag))
    if not station then
        return false
    end
    local stand = station:IsA("Model") and (station.PrimaryPart or station:FindFirstChildWhichIsA("BasePart")) or station
    if stand and stand:IsA("BasePart") then
        TPTo(stand)
    end
    local weightId = nil
    if kind.WeightFolder then
        local seconds = (M.Data and M.Data.Get({ M.Settings.Zones.Workout.SecondsField })) or 0
        local capacity = M.Muscle.Capacity(seconds) * (kind.CapacityScale or 1)
        for _, w in ipairs(M.GymWeights.List(kind.WeightFolder)) do
            if M.Muscle.Band(M.Muscle.Ratio(w.Weight, capacity)) ~= "Locked" then
                weightId = w.Name
            end
        end
    elseif kind.Speeds then
        local fastest = nil
        for _, s in ipairs(kind.Speeds) do
            if not fastest or (tonumber(s.Effort) or 0) > (tonumber(fastest.Effort) or 0) then
                fastest = s
            end
        end
        weightId = fastest and fastest.Id
    end
    if not weightId then
        return false
    end
    Remotes.Gym:Fire({ T = "Start", Station = station, Weight = weightId })
    return true
end

local function Func_AutoAttack()
    while Toggles.AutoAttack.Value do
        local ok, err = pcall(function()
            if not Shared.Modules then
                ResolveModules()
            end
            local M = Shared.Modules
            if not (M and M.Input and M.Combat) then
                return
            end
            local char = GetCharacter()
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if not hrp then
                return
            end
            local dummy = GetNearest(realCS:GetTagged("CombatDummy"))
            if not dummy then
                return
            end
            local dpart = dummy:FindFirstChild("HumanoidRootPart")
            if not dpart and dummy:IsA("Model") then
                dpart = dummy.PrimaryPart or dummy:FindFirstChildWhichIsA("BasePart")
            end
            if not dpart or not dpart:IsA("BasePart") then
                return
            end
            local flat = Vector3.new(hrp.Position.X - dpart.Position.X, 0, hrp.Position.Z - dpart.Position.Z)
            local dist = flat.Magnitude
            if dist > 5 then
                local away = dist > 0.5 and flat.Unit or Vector3.new(0, 0, 1)
                hrp.CFrame = CFrame.lookAt(Vector3.new(dpart.Position.X + away.X * 4, hrp.Position.Y, dpart.Position.Z + away.Z * 4), Vector3.new(dpart.Position.X, hrp.Position.Y, dpart.Position.Z))
            elseif dist > 0.5 then
                hrp.CFrame = CFrame.lookAt(hrp.Position, Vector3.new(dpart.Position.X, hrp.Position.Y, dpart.Position.Z))
            end
            if not M.Combat.IsActive() then
                M.Input.Fire("Combat.Equip", true)
                return
            end
            M.Input.Fire("Combat.Attack", true)
            M.Input.Fire("Combat.Attack")
            M.Input.Fire("Combat.Critical", true)
        end)
        if not ok then
            notyuri("AutoAttack:", err)
        end
        task.wait(0.2)
    end
end

local function Func_AutoGym()
    while Toggles.AutoGym.Value do
        local ok, err = pcall(function()
            if not Shared.Modules then
                ResolveModules()
            end
            local M = Shared.Modules
            if not (M and M.Input) then
                return
            end
            if GymTapStep() then
                Shared.GymStartAt = nil
                return
            end
            if Shared.GymStartAt and os.clock() - Shared.GymStartAt < 8 then
                return
            end
            if GymStartSession() then
                Shared.GymStartAt = os.clock()
            end
        end)
        if not ok then
            notyuri("AutoGym:", err)
        end
        task.wait(0.1)
    end
end

ResolveModules()
local gymValues = {}
do
    local M = Shared.Modules
    if M and M.Settings and M.Settings.Gym then
        for _, kind in ipairs(M.Settings.Gym.Kinds) do
            table.insert(gymValues, kind.Label or kind.Lift)
        end
    end
end
TB_Tabs.Autofarm.T1:AddToggle("AutoAttack", { Text = "Auto Attack" })
TB_Tabs.Autofarm.T1:AddDivider()
TB_Tabs.Autofarm.T1:AddDropdown("GymKind", {
    Text = "Gym Station",
    Values = gymValues,
    Default = gymValues[1],
})
TB_Tabs.Autofarm.T1:AddToggle("AutoGym", { Text = "Auto Gym" })

Thread("Resolve", function()
    while not Shared.Modules and not Library.Unloaded do
        ResolveModules()
        if Shared.Modules then
            break
        end
        task.wait(1)
    end
end, true)

Toggles.AutoAttack:OnChanged(function(state)
    Thread("AutoAttack", SafeLoop("AutoAttack", Func_AutoAttack), state)
end)
Toggles.AutoGym:OnChanged(function(state)
    Thread("AutoGym", SafeLoop("AutoGym", Func_AutoGym), state)
    if not state then
        pcall(function()
            if Shared.Modules and Shared.Modules.Input then
                Shared.Modules.Input.Fire("Gym.Stop", true)
            end
        end)
    end
end)
