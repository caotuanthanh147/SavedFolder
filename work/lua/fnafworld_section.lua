local realRS = game:GetService("ReplicatedStorage")

Shared.FnafWorld = {
    Modules = nil,
    LastPanelAt = 0,
}

local function ResolveModules()
    local M = {}
    M.Bytes = GetSafeModule(realRS, "FnafWorldByteInventory")
    M.Prog = GetSafeModule(realRS, "FnafWorldProgression")
    M.Save = GetSafeModule(realRS, "FnafWorldSaveClient")
    M.Overworld = GetSafeModule(realRS, "FnafWorldOverworld")
    if M.Bytes and M.Prog and M.Save and M.Overworld then
        Shared.FnafWorld.Modules = M
        return true
    end
    return false
end

local function GetModules()
    return Shared.FnafWorld.Modules or (ResolveModules() and Shared.FnafWorld.Modules)
end

local function GetGui(name)
    local pg = Plr:FindFirstChild("PlayerGui")
    return pg and pg:FindFirstChild(name) or nil
end

local function GetBattleGui()
    local gui = GetGui("FnafWorldBattle")
    if gui and gui.Enabled then
        return gui
    end
    return nil
end

local function GetWorldFolder(name)
    local map = workspace:FindFirstChild("Map")
    return map and map:FindFirstChild(name) or nil
end

local function PartyLow(gui, prog)
    for i = 1, 4 do
        local bar = gui:FindFirstChild("HPBar" .. i)
        local text = bar and bar:FindFirstChild("HPText")
        local side = GetObject(gui, "PartySide.Character" .. i)
        local name = side and side:GetAttribute("CharacterName")
        if text and name then
            local hp = tonumber(text.Text)
            local data = hp and prog.Get(Plr, name)
            if data and hp > 0 and hp < data.maxHP * 0.4 then
                return true
            end
        end
    end
    return false
end

local function PickMoveSlot(gui, wantHeal, hasBoss)
    local panel = GetObject(gui, "MovePanel")
    local char = panel and panel:GetAttribute("ActiveCharacter")
    if not char then
        return 1
    end
    local controller = gui:FindFirstChild("BattleController")
    local moveData = controller and GetSafeModule(controller, "BattleMoveButtonData")
    local configs = moveData and moveData.Characters and moveData.Characters[char]
    if not configs then
        return 1
    end
    local order
    if wantHeal then
        order = { healAll = 1, healAndDamageAll = 2, regen = 3 }
    elseif hasBoss then
        order = { allDamage = 1, singleDamage = 2, healAndDamageAll = 3 }
    else
        order = { instantDefeat = 1, allDamage = 2, singleDamage = 3, healAndDamageAll = 4 }
    end
    local slot, rank = 1, math.huge
    for i, config in ipairs(configs) do
        local r = math.huge
        if config.enabled ~= false and order[config.effect] then
            r = order[config.effect]
        end
        if r < rank then
            rank, slot = r, i
        end
    end
    return slot
end

local function PredictSwimX(pos, dir, speed, minX, maxX, dt)
    local remaining = speed * dt
    while remaining > 0 do
        local target = dir > 0 and maxX or minX
        local toGo = math.abs(target - pos)
        if toGo > remaining then
            pos = pos + dir * remaining
            remaining = 0
        else
            pos = target
            remaining = remaining - toGo
            dir = -dir
        end
    end
    return pos
end

local function PickFishTarget(gui)
    local pearl = gui:FindFirstChild("Pearl")
    if pearl and pearl:IsA("ImageLabel") and pearl.Visible then
        return pearl
    end
    local layer = gui:FindFirstChild("FishLayer")
    if not layer then
        return nil
    end
    local values = { Orange = 1, Green = 2, Purple = 5, Blue = 10, Pink = 20, Yellow = 50 }
    local best, bestValue
    for _, fish in ipairs(layer:GetChildren()) do
        if fish:IsA("ImageLabel") and fish.Visible and fish.Name:match("Fish_%d+$") then
            local value = values[fish:GetAttribute("FishColor") or ""]
            if value and (not bestValue or value > bestValue) then
                best, bestValue = fish, value
            end
        end
    end
    return best
end

local function StepFishing(gui)
    local boat = gui:FindFirstChild("FreddyBoatImage")
    local drop = gui:FindFirstChild("DropButton")
    if not boat or not drop then
        return
    end
    local target = PickFishTarget(gui)
    if not target then
        return
    end
    local plunger = boat:FindFirstChild("Plunger")
    if not plunger then
        return
    end
    local prefix = target.Name == "Pearl" and "Pearl" or "Swim"
    local pos = target.Position.X.Scale
    local dir = (target:GetAttribute(prefix .. "Direction") or target:GetAttribute("FishDirection")) == "Right" and 1 or -1
    local speed = tonumber(target:GetAttribute(prefix .. "Speed")) or 0.1
    local minX = tonumber(target:GetAttribute(prefix .. "MinX")) or 0.05
    local maxX = tonumber(target:GetAttribute(prefix .. "MaxX")) or 0.95
    local guiH = gui.AbsoluteSize.Y
    local dropTime = tonumber(gui:GetAttribute("DropSpeed")) or 0.55
    local descent = (tonumber(gui:GetAttribute("DropDistanceScaleY")) or 0.86) * guiH
    local startY = plunger.AbsolutePosition.Y + plunger.AbsoluteSize.Y
    local crossY = target.AbsolutePosition.Y + target.AbsoluteSize.Y * 0.5
    local tCross = dropTime * math.clamp((crossY - startY) / math.max(1, descent), 0, 1)
    local aim = PredictSwimX(pos, dir, speed, minX, maxX, tCross)
    local left = tonumber(gui:GetAttribute("BoatLeftX")) or 0.06
    local right = tonumber(gui:GetAttribute("BoatRightX")) or 0.94
    aim = math.clamp(aim, left, right)
    boat.Position = UDim2.new(aim, boat.Position.X.Offset, boat.Position.Y.Scale, boat.Position.Y.Offset)
    fire_event(drop.Activated)
end

local function Func_AutoBattle()
    while Toggles.AutoBattle.Value do
        local ok, err = pcall(function()
            local gui = GetBattleGui()
            if not gui then
                local title = GetGui("FnafWorldTitleScreen")
                if title and title.Enabled and title:GetAttribute("OpenAsOverworldParty") then
                    local done = GetObject(title, "SaveScreen.DoneButton")
                    if done then
                        fire_event(done.Activated)
                    end
                end
                return
            end
            local panel = gui:FindFirstChild("MovePanel")
            if panel and panel.Visible then
                Shared.FnafWorld.LastPanelAt = os.clock()
                local M = GetModules()
                local bossBar = gui:FindFirstChild("BossHPBar")
                local wantHeal = M and PartyLow(gui, M.Prog) or false
                local hasBoss = bossBar ~= nil and bossBar.Visible == true
                local slot = PickMoveSlot(gui, wantHeal, hasBoss)
                local button = panel:FindFirstChild("Move" .. slot .. "Button")
                if button then
                    fire_event(button.Activated)
                end
            else
                local switch = gui:FindFirstChild("SwitchButton")
                if switch and switch.Visible and os.clock() - Shared.FnafWorld.LastPanelAt > 2 then
                    fire_event(switch.Activated)
                    Shared.FnafWorld.LastPanelAt = os.clock()
                end
            end
        end)
        if not ok then notyuri("AutoBattle", err) end
        task.wait(0.15)
    end
end

local function Func_AutoBoss()
    while Toggles.AutoBoss.Value do
        local ok, err = pcall(function()
            if GetBattleGui() then
                return
            end
            local M = GetModules()
            local bosses = GetWorldFolder("Bosses")
            if not M or not bosses then
                return
            end
            local target = GetNearest(bosses:GetChildren(), function(boss)
                if not boss:FindFirstChild("CollisionBlocker") then
                    return false
                end
                if boss:GetAttribute("DefeatedLocally") == true then
                    return false
                end
                return M.Overworld.CanInteractOnLayer(Plr, boss:GetAttribute("SourceLayer"))
            end)
            if target then
                TPTo(target:FindFirstChild("CollisionBlocker"))
            end
        end)
        if not ok then notyuri("AutoBoss", err) end
        task.wait(1)
    end
end

local function Func_AutoChest()
    while Toggles.AutoChest.Value do
        local ok, err = pcall(function()
            if GetBattleGui() then
                return
            end
            local M = GetModules()
            local chests = GetWorldFolder("TokenChests")
            if not M or not chests then
                return
            end
            local target = GetNearest(chests:GetChildren(), function(chest)
                local box = chest:FindFirstChild("CollisionBlocker")
                if not box or not box.CanTouch then
                    return false
                end
                return M.Overworld.CanInteractOnLayer(Plr, chest:GetAttribute("SourceLayer"))
            end)
            if target then
                TPTo(target:FindFirstChild("CollisionBlocker"))
            end
        end)
        if not ok then notyuri("AutoChest", err) end
        task.wait(2)
    end
end

local function Func_AutoFish()
    while Toggles.AutoFish.Value do
        local fast = false
        local ok, err = pcall(function()
            if GetBattleGui() then
                return
            end
            local gui = GetGui("FnafWorldDeedeeMinigame")
            if gui and gui.Enabled then
                if not gui:GetAttribute("MinigamePaused") then
                    StepFishing(gui)
                    fast = true
                end
                return
            end
            if os.time() < (tonumber(Plr:GetAttribute("DeedeeReturnAt")) or 0) then
                return
            end
            local shop = GetGui("FnafWorldDeedeeShopKeeper")
            if shop and shop.Enabled then
                local play = shop:FindFirstChild("FishingPlayHitButton")
                if play and play.Visible then
                    fire_event(play.Activated)
                end
                return
            end
            local npcs = GetWorldFolder("NPCS")
            local npc = npcs and npcs:FindFirstChild("DeedeeShopKeeper")
            local blocker = npc and npc:FindFirstChild("CollisionBlocker")
            if blocker then
                TPTo(blocker)
            end
        end)
        if not ok then notyuri("AutoFish", err) end
        task.wait(fast and 0.06 or 0.4)
    end
end

local function Func_AutoBuyByte()
    while Toggles.AutoBuyByte.Value do
        local ok, err = pcall(function()
            local M = GetModules()
            if not M then
                return
            end
            local name = Options.BuyByte and Options.BuyByte.Value
            if not name or name == "" then
                return
            end
            if M.Bytes.Owns(Plr, name) then
                return
            end
            local price = M.Bytes.Prices[name]
            local tokens = tonumber(Plr:GetAttribute("FazTokens")) or 0
            if price and tokens >= price then
                local bought = M.Bytes.Purchase(Plr, name)
                if bought and M.Save.HasActiveSlot() then
                    task.spawn(M.Save.AutoSave)
                end
            end
        end)
        if not ok then notyuri("AutoBuyByte", err) end
        task.wait(2)
    end
end

local T1 = TB_Tabs.Autofarm.T1
T1:AddToggle("AutoBattle", { Text = "Auto Battle" })
T1:AddDivider()
T1:AddToggle("AutoBoss", { Text = "Auto Boss" })
T1:AddToggle("AutoChest", { Text = "Auto Chest" })
T1:AddDivider()
T1:AddToggle("AutoFish", { Text = "Auto Fish" })
T1:AddDivider()
T1:AddToggle("AutoBuyByte", { Text = "Auto Buy Byte" })
local byteValues = {}
do
    local M = GetModules()
    if M then
        local seen = {}
        local keepers = { "LolbitShopKeeper", "LolbitShopKeeper2", "LolbitShopKeeper3", "LolbitShopKeeper4", "LolbitShopKeeper5", "LolbitShopKeeper6", "LolbitShopKeeper7" }
        for _, keeper in ipairs(keepers) do
            local stock = M.Bytes.ShopStock[keeper]
            if stock then
                for _, name in ipairs(stock) do
                    if not seen[name] and M.Bytes.Prices[name] then
                        seen[name] = true
                        table.insert(byteValues, name)
                    end
                end
            end
        end
    end
end
Options.BuyByte = T1:AddDropdown("BuyByte", {
    Text = "Byte",
    Values = byteValues,
    Default = byteValues[1],
})

Toggles.AutoBattle:OnChanged(function(state)
    Thread("AutoBattle", SafeLoop("AutoBattle", Func_AutoBattle), state)
end)
Toggles.AutoBoss:OnChanged(function(state)
    Thread("AutoBoss", SafeLoop("AutoBoss", Func_AutoBoss), state)
end)
Toggles.AutoChest:OnChanged(function(state)
    Thread("AutoChest", SafeLoop("AutoChest", Func_AutoChest), state)
end)
Toggles.AutoFish:OnChanged(function(state)
    Thread("AutoFish", SafeLoop("AutoFish", Func_AutoFish), state)
end)
Toggles.AutoBuyByte:OnChanged(function(state)
    Thread("AutoBuyByte", SafeLoop("AutoBuyByte", Func_AutoBuyByte), state)
end)
