local PoolRemote = RS:WaitForChild("Remotes"):WaitForChild("Pool")
local DailyRemote = RS:WaitForChild("Remotes"):WaitForChild("DailyReward")
local SpinRemote = RS:WaitForChild("Remotes"):WaitForChild("SpinWheel")
local EventsRemote = RS:WaitForChild("Remotes"):WaitForChild("Events")
local function Func_AutoQueue()
    while Toggles.AutoQueue.Value do
        local ok, err = pcall(function()
            PoolRemote:FireServer("Queue", "Brazil")
        end)
        if not ok then notyuri("Auto Queue error: " .. tostring(err)) end
        task.wait(10)
    end
end
local function Func_AutoDailyClaim()
    while Toggles.AutoDailyClaim.Value do
        local ok, err = pcall(function()
            DailyRemote:FireServer("DailyClaim")
        end)
        if not ok then notyuri("Auto Daily Claim error: " .. tostring(err)) end
        task.wait(60)
    end
end
local function Func_AutoSpinWheel()
    while Toggles.AutoSpinWheel.Value do
        local ok, err = pcall(function()
            SpinRemote:FireServer("SpinWheel")
        end)
        if not ok then notyuri("Auto Spin Wheel error: " .. tostring(err)) end
        task.wait(60)
    end
end
local function Func_AutoEventQuests()
    while Toggles.AutoEventQuests.Value do
        local ok, err = pcall(function()
            EventsRemote:FireServer("EventQuestClaimAll")
        end)
        if not ok then notyuri("Auto Event Quests error: " .. tostring(err)) end
        task.wait(60)
    end
end
TB_Tabs.Autofarm.T1:AddDivider()
TB_Tabs.Autofarm.T1:AddToggle("AutoQueue", { Text = "Auto Queue", Default = false })
Toggles.AutoQueue:OnChanged(function(state)
    Thread("AutoQueue", SafeLoop("Auto Queue", Func_AutoQueue), state)
end)
TB_Tabs.Autofarm.T1:AddDivider()
TB_Tabs.Autofarm.T1:AddToggle("AutoDailyClaim", { Text = "Auto Daily Claim", Default = false })
Toggles.AutoDailyClaim:OnChanged(function(state)
    Thread("AutoDailyClaim", SafeLoop("Auto Daily Claim", Func_AutoDailyClaim), state)
end)
TB_Tabs.Autofarm.T1:AddToggle("AutoSpinWheel", { Text = "Auto Spin Wheel", Default = false })
Toggles.AutoSpinWheel:OnChanged(function(state)
    Thread("AutoSpinWheel", SafeLoop("Auto Spin Wheel", Func_AutoSpinWheel), state)
end)
TB_Tabs.Autofarm.T1:AddToggle("AutoEventQuests", { Text = "Auto Event Quests", Default = false })
Toggles.AutoEventQuests:OnChanged(function(state)
    Thread("AutoEventQuests", SafeLoop("Auto Event Quests", Func_AutoEventQuests), state)
end)
