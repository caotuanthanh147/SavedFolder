local KnitServices = RS:WaitForChild("Packages"):WaitForChild("_Index"):WaitForChild("sleitnick_knit@1.7.0"):WaitForChild("knit"):WaitForChild("Services")
Remotes.SellAllFunc = KnitServices:WaitForChild("InventoryService"):WaitForChild("RF"):WaitForChild("SellAll")
Remotes.CollectCashFunc = KnitServices:WaitForChild("AnimalService"):WaitForChild("RF"):WaitForChild("CollectOfflineCash")
Remotes.SpinWheelFunc = KnitServices:WaitForChild("SpinWheelService"):WaitForChild("RF"):WaitForChild("SpinWheel")
Remotes.ClaimDailyFunc = KnitServices:WaitForChild("DailyRewardService"):WaitForChild("RF"):WaitForChild("ClaimReward")
Remotes.RebirthFunc = KnitServices:WaitForChild("RebirthService"):WaitForChild("RF"):WaitForChild("Rebirth")
local function Func_AutoCollect()
    while Toggles.AutoCollect.Value do
        local ok, err = pcall(function()
            local char = GetCharacter()
            if char then
                local folder = workspace:FindFirstChild("CollectEventPickups")
                if folder then
                    local target = GetNearest(folder:GetChildren())
                    if target then
                        TPTo(target, Vector3.new(0, 3, 0))
                    end
                end
            end
        end)
        if not ok then notyuri("Auto Collect error: " .. tostring(err)) end
        task.wait(0.3)
    end
end
local function Func_AutoSellAll()
    while Toggles.AutoSellAll.Value do
        local ok, err = pcall(function()
            SafeInvoke(Remotes.SellAllFunc, true)
        end)
        if not ok then notyuri("Auto Sell All error: " .. tostring(err)) end
        task.wait(30)
    end
end
local function Func_AutoCollectCash()
    while Toggles.AutoCollectCash.Value do
        local ok, err = pcall(function()
            SafeInvoke(Remotes.CollectCashFunc, true)
        end)
        if not ok then notyuri("Auto Collect Cash error: " .. tostring(err)) end
        task.wait(60)
    end
end
local function Func_AutoSpinWheel()
    while Toggles.AutoSpinWheel.Value do
        local ok, err = pcall(function()
            SafeInvoke(Remotes.SpinWheelFunc, true)
        end)
        if not ok then notyuri("Auto Spin Wheel error: " .. tostring(err)) end
        task.wait(60)
    end
end
local function Func_AutoClaimDaily()
    while Toggles.AutoClaimDaily.Value do
        local ok, err = pcall(function()
            SafeInvoke(Remotes.ClaimDailyFunc, true, 1)
        end)
        if not ok then notyuri("Auto Claim Daily error: " .. tostring(err)) end
        task.wait(60)
    end
end
local function Func_AutoRebirth()
    while Toggles.AutoRebirth.Value do
        local ok, err = pcall(function()
            SafeInvoke(Remotes.RebirthFunc, true)
        end)
        if not ok then notyuri("Auto Rebirth error: " .. tostring(err)) end
        task.wait(60)
    end
end
TB_Tabs.Autofarm.T1:AddDivider()
TB_Tabs.Autofarm.T1:AddToggle("AutoCollect", { Text = "Auto Collect", Default = false })
Toggles.AutoCollect:OnChanged(function(state)
    Thread("AutoCollect", SafeLoop("Auto Collect", Func_AutoCollect), state)
end)
TB_Tabs.Autofarm.T1:AddDivider()
TB_Tabs.Autofarm.T1:AddToggle("AutoSellAll", { Text = "Auto Sell All", Default = false })
Toggles.AutoSellAll:OnChanged(function(state)
    Thread("AutoSellAll", SafeLoop("Auto Sell All", Func_AutoSellAll), state)
end)
TB_Tabs.Autofarm.T1:AddToggle("AutoCollectCash", { Text = "Auto Collect Cash", Default = false })
Toggles.AutoCollectCash:OnChanged(function(state)
    Thread("AutoCollectCash", SafeLoop("Auto Collect Cash", Func_AutoCollectCash), state)
end)
TB_Tabs.Autofarm.T1:AddToggle("AutoSpinWheel", { Text = "Auto Spin Wheel", Default = false })
Toggles.AutoSpinWheel:OnChanged(function(state)
    Thread("AutoSpinWheel", SafeLoop("Auto Spin Wheel", Func_AutoSpinWheel), state)
end)
TB_Tabs.Autofarm.T1:AddToggle("AutoClaimDaily", { Text = "Auto Claim Daily", Default = false })
Toggles.AutoClaimDaily:OnChanged(function(state)
    Thread("AutoClaimDaily", SafeLoop("Auto Claim Daily", Func_AutoClaimDaily), state)
end)
TB_Tabs.Autofarm.T1:AddToggle("AutoRebirth", { Text = "Auto Rebirth", Default = false })
Toggles.AutoRebirth:OnChanged(function(state)
    Thread("AutoRebirth", SafeLoop("Auto Rebirth", Func_AutoRebirth), state)
end)
