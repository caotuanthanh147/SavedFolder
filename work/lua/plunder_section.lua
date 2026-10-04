local realRS = game:GetService("ReplicatedStorage")

Shared.Plunder = {
    Modules = nil,
    Memo = { Searched = {} },
}

local function ResolveModules()
    local M = {}
    M.TE = GetSafeModule(GetObject(realRS, "Shared.Core"), "TEvent")
    M.Value = GetSafeModule(GetObject(realRS, "Shared.Core"), "Value")
    M.Registry = GetSafeModule(GetObject(realRS, "Client.System.WorldItem"), "Registry")
    M.CState = GetSafeModule(GetObject(realRS, "Client.Core"), "ContainerState")
    M.WI = GetSafeModule(GetObject(realRS, "Shared.Features"), "WorldItem")
    M.PickPoint = GetSafeModule(GetObject(realRS, "Shared.Features.WorldItem"), "PickupPoint")
    M.Extract = GetSafeModule(GetObject(realRS, "Shared.Features"), "Extract")
    M.Interact = GetSafeModule(GetObject(realRS, "Shared.Features"), "Interactable")
    M.CRules = GetSafeModule(GetObject(realRS, "Shared.Features.Container"), "Rules")
    M.Gloves = GetSafeModule(GetObject(realRS, "Shared.Features"), "Gloves")
    if M.TE and M.Value and M.Registry and M.CState and M.WI and M.PickPoint and M.Extract and M.Interact and M.CRules and M.Gloves then
        Shared.Plunder.Modules = M
        return true
    end
    return false
end

local function GetModules()
    return Shared.Plunder.Modules or (ResolveModules() and Shared.Plunder.Modules)
end

local function GetRoot()
    local char = GetCharacter()
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    return hrp
end

local function Func_AutoPickup()
    while Toggles.AutoPickup.Value do
        local ok, err = pcall(function()
            local M = GetModules()
            local hrp = GetRoot()
            if not M or not hrp then return end
            local cam = workspace.CurrentCamera
            local camPos = cam and cam.CFrame.Position or hrp.Position
            local remote = M.TE.Remote.new("ToolPickupAction")
            for _, rec in pairs(M.Registry.GetVisible()) do
                local root = rec and rec.localRoot
                if root and root.Parent and not rec.hidden then
                    local cf, size = M.WI.GetBox(root)
                    if cf and not M.WI.OutOfRange(cf.Position, hrp.Position) then
                        remote:FireServer("pickup", rec, camPos, M.PickPoint.Encode(cf, size, cf.Position))
                    end
                end
            end
        end)
        if not ok then notyuri("AutoPickup", err) end
        task.wait(0.4)
    end
end

local function Func_AutoSearch()
    while Toggles.AutoSearch.Value do
        local ok, err = pcall(function()
            local M = GetModules()
            local hrp = GetRoot()
            if not M or not hrp then return end
            local searched = Shared.Plunder.Memo.Searched
            for _, inst in ipairs(Services.CollectionService:GetTagged(M.Interact.TAG)) do
                local prompt = inst:FindFirstChildWhichIsA("ProximityPrompt", true)
                if prompt and prompt.Parent then
                    local cid = prompt:GetAttribute(M.CRules.CID_ATTR)
                    if type(cid) == "string" and not searched[cid] then
                        local root = inst:IsA("BasePart") and inst or (inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart"))
                        if root and (root.Position - hrp.Position).Magnitude <= (prompt.MaxActivationDistance or 10) then
                            M.CState.Act({ op = "open", cid = cid })
                            task.wait(0.5)
                            M.CState.Act({ op = "takebest", cid = cid })
                            searched[cid] = true
                        end
                    end
                end
            end
        end)
        if not ok then notyuri("AutoSearch", err) end
        task.wait(1)
    end
end

local function Func_AutoExtract()
    while Toggles.AutoExtract.Value do
        local ok, err = pcall(function()
            local M = GetModules()
            local hrp = GetRoot()
            if not M or not hrp then return end
            for _, prompt in ipairs(Services.CollectionService:GetTagged(M.Extract.TAG)) do
                if prompt:IsA("ProximityPrompt") and prompt.Parent then
                    if not M.Extract.IsDisabled(prompt) and not M.Extract.IsDisabled(prompt.Parent) then
                        local root = prompt.Parent:IsA("BasePart") and prompt.Parent or (prompt.Parent.PrimaryPart or prompt.Parent:FindFirstChildWhichIsA("BasePart"))
                        if root and (root.Position - hrp.Position).Magnitude <= (prompt.MaxActivationDistance or 10) then
                            M.TE.FireRemote("ExtractHold", true)
                            task.wait(M.Extract.HoldSecondsOf(prompt))
                            M.TE.FireRemote("ExtractHold", "done")
                            return
                        end
                    end
                end
            end
        end)
        if not ok then notyuri("AutoExtract", err) end
        task.wait(1)
    end
end

local function Func_AutoRoll()
    while Toggles.AutoRoll.Value do
        local ok, err = pcall(function()
            local M = GetModules()
            if not M then return end
            M.TE.FireRemote(M.Gloves.Net.ACT, { op = M.Gloves.Net.Op.ROLL })
        end)
        if not ok then notyuri("AutoRoll", err) end
        task.wait(1)
    end
end

task.spawn(function()
    while not Library.Unloaded do
        local M = GetModules()
        if M then
            SafeConnect("PlunderResult", function()
                return M.TE.Remote.new("MatchResultShow").OnClientEvent
            end, function()
                if Toggles.AutoRequeue and Toggles.AutoRequeue.Value then
                    task.wait(1.5)
                    M.TE.FireRemote("MatchResultChoice", "lobby")
                end
            end)
            M.TE.OnRemote("ReconnectOffer", function()
                if Toggles.AutoRequeue and Toggles.AutoRequeue.Value then
                    task.wait(1)
                    M.TE.FireRemote("ReconnectChoice", "return")
                end
            end)
            SafeConnect("PlunderInGame", function()
                return M.Value.InGame.Changed
            end, function()
                Shared.Plunder.Memo.Searched = {}
            end)
            return
        end
        task.wait(1)
    end
end)

TB_Tabs.Autofarm.T1:AddToggle("AutoPickup", { Text = "Auto Pickup" })
TB_Tabs.Autofarm.T1:AddToggle("AutoSearch", { Text = "Auto Search + Take Best" })
TB_Tabs.Autofarm.T1:AddToggle("AutoExtract", { Text = "Auto Extract" })
TB_Tabs.Autofarm.T1:AddToggle("AutoRoll", { Text = "Auto Roll Gloves" })
TB_Tabs.Autofarm.T1:AddToggle("AutoRequeue", { Text = "Auto Requeue" })

Toggles.AutoPickup:OnChanged(function(state)
    Thread("AutoPickup", SafeLoop("AutoPickup", Func_AutoPickup), state)
end)
Toggles.AutoSearch:OnChanged(function(state)
    Thread("AutoSearch", SafeLoop("AutoSearch", Func_AutoSearch), state)
end)
Toggles.AutoExtract:OnChanged(function(state)
    Thread("AutoExtract", SafeLoop("AutoExtract", Func_AutoExtract), state)
end)
Toggles.AutoRoll:OnChanged(function(state)
    Thread("AutoRoll", SafeLoop("AutoRoll", Func_AutoRoll), state)
end)
