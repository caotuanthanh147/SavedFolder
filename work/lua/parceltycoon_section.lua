local ClientFolder = GetObject(Plr, "PlayerScripts.Client")
local SharedFolder = GetObject(RS, "Shared")
local ConfigFolder = SharedFolder and GetObject(SharedFolder, "Config") or nil
local M = {
    Store = ClientFolder and GetSafeModule(ClientFolder, "Store") or nil,
    Predictor = ClientFolder and GetSafeModule(GetObject(ClientFolder, "Packing"), "Predictor") or nil,
    Solver = SharedFolder and GetSafeModule(SharedFolder, "Solver") or nil,
    DemoPlan = SharedFolder and GetSafeModule(SharedFolder, "DemoPlan") or nil,
    Handling = SharedFolder and GetSafeModule(SharedFolder, "Handling") or nil,
    Wheel = SharedFolder and GetSafeModule(SharedFolder, "HalloweenWheel") or nil,
    Boxes = ConfigFolder and GetSafeModule(ConfigFolder, "Boxes") or nil,
    Pads = ConfigFolder and GetSafeModule(ConfigFolder, "Pads") or nil,
    StaffCfg = ConfigFolder and GetSafeModule(ConfigFolder, "Staff") or nil,
}
Shared.Memo = { Pads = {} }

local function Plot()
    local index = Plr:GetAttribute("PlotIndex")
    local plots = index and workspace:FindFirstChild("Plots") or nil
    return plots and plots:FindFirstChild("Plot" .. index) or nil
end

local function PackStep()
    local predictor = M.Predictor
    local store = M.Store
    if not (predictor and store and store.station) then
        return
    end
    local st = predictor.server or store.station
    local sim = predictor.sim
    if st.orderId and st.order and sim then
        if not sim.boxChosen then
            local unlocked = st.unlockedBoxes or {}
            for _, boxId in ipairs(st.order.boxes or {}) do
                if unlocked[boxId] and M.Boxes and M.Solver then
                    local def = M.Boxes.get(boxId)
                    local sol = def and M.Solver.solve(def, st.order.items, { perfect = true }) or nil
                    if sol and sol.ok then
                        predictor.request("Box", { boxId = boxId })
                        return
                    end
                end
            end
            return
        end
        if not sim.folded then
            predictor.request("Fold", {})
            return
        end
        local pack = sim.pack
        local sol = M.Solver and M.Solver.solve(pack.box, pack.order.items, { perfect = true }) or nil
        if not (sol and sol.ok) then
            return
        end
        if M.DemoPlan then
            for _, uid in ipairs(M.DemoPlan.order(sol.placed)) do
                if not pack.placed[uid] then
                    local spot = sol.placed[uid]
                    predictor.request("Place", { uid = uid, x = spot.x, z = spot.z, o = spot.o })
                    return
                end
            end
        end
        for uid, item in pairs(pack.order.byUid) do
            if item.fragile and pack.placed[uid] and not pack.wrapped[uid] then
                predictor.request("Wrap", { uid = uid, on = true })
                return
            end
        end
        if not pack.filled and not pack.box.pet then
            if predictor.request("Fill", { on = true }) == nil then
                return
            end
        end
        local cart = st.cart
        if not st.chute and cart and cart.max <= (cart.count or 0) then
            store.send("cart", { op = "take" })
            return
        end
        local ids = {}
        for _, item in ipairs(pack.order.items) do
            table.insert(ids, item.id)
        end
        local stamps = M.Handling and M.Handling.needsFor(ids) or { "standard" }
        predictor.request("Seal", { stamps = stamps, stamp = stamps[1] })
        return
    end
    local carrying = st.carrying or {}
    if #carrying > 0 then
        local plot = Plot()
        local mat = plot and (plot:FindFirstChild("FreightMat", true) or plot:FindFirstChild("DropMat", true)) or nil
        if mat then
            TPTo(mat)
        end
        return
    end
    if (st.cart and st.cart.count or 0) > 0 and not st.chute then
        store.send("cart", { op = "take" })
        return
    end
    local best = nil
    for _, slip in ipairs(st.board or {}) do
        if not best or (slip.reward or 0) > (best.reward or 0) then
            best = slip
        end
    end
    if best then
        predictor.request("Take", { ticketId = best.orderId })
    end
end

local function BuyStep()
    local store = M.Store
    local profile = store and store.profile
    if not (profile and type(profile.pads) == "table" and type(M.Pads) == "table") then
        return
    end
    local best = nil
    for _, pad in ipairs(M.Pads) do
        if type(pad) == "table" and pad.id and pad.cost and not profile.pads[pad.id] and not Shared.Memo.Pads[pad.id] then
            local ready = true
            for _, need in ipairs(pad.after or {}) do
                if not profile.pads[need] then
                    ready = false
                    break
                end
            end
            if ready and (not best or pad.cost < best.cost) then
                best = pad
            end
        end
    end
    if best and best.cost <= (profile.cash or 0) then
        local plot = Plot()
        local padModel = plot and plot:FindFirstChild("Pad_" .. best.id, true) or nil
        if padModel then
            Shared.Memo.Pads[best.id] = true
            TPTo(padModel)
            M.Store.send("purchase", { kind = "padOffer", pad = best.id, buy = true })
        end
    end
end

local function SpinStep()
    local store = M.Store
    local profile = store and store.profile
    if not (profile and type(profile.halloween) == "table" and M.Wheel) then
        return
    end
    if M.Wheel.ready(profile.halloween.wheel or {}) then
        local plot = Plot()
        local pumpkin = plot and plot:FindFirstChild("MagicPumpkin", true) or nil
        if pumpkin then
            TPTo(pumpkin)
        end
        store.send("halloweenSpin", {})
    end
end

local function TrainStep()
    local store = M.Store
    local profile = store and store.profile
    local staff = store and store.staff
    if not (profile and type(staff) == "table" and M.StaffCfg) then
        return
    end
    local bestCost = nil
    local bestId = nil
    local bestStat = nil
    for _, member in pairs(staff) do
        if type(member) == "table" and member.id and type(member.stats) == "table" then
            for stat, level in pairs(member.stats) do
                if type(level) == "number" and level < 5 then
                    local cost = M.StaffCfg.trainCost(member, stat)
                    if cost and (not bestCost or cost < bestCost) then
                        bestCost = cost
                        bestId = member.id
                        bestStat = stat
                    end
                end
            end
        end
    end
    if bestId and bestCost <= (profile.cash or 0) then
        store.send("staff", { op = "train", id = bestId, stat = bestStat })
    end
end

local function Func_AutoPack()
    while Toggles.AutoPack.Value do
        local ok, err = pcall(PackStep)
        if not ok then
            notyuri("AutoPack", err)
        end
        task.wait(Options.PackDelay.Value)
    end
end

local function Func_AutoBuyPads()
    while Toggles.AutoBuyPads.Value do
        local ok, err = pcall(BuyStep)
        if not ok then
            notyuri("AutoBuyPads", err)
        end
        task.wait(2)
    end
end

local function Func_AutoSpin()
    while Toggles.AutoSpin.Value do
        local ok, err = pcall(SpinStep)
        if not ok then
            notyuri("AutoSpin", err)
        end
        task.wait(5)
    end
end

local function Func_AutoTrain()
    while Toggles.AutoTrain.Value do
        local ok, err = pcall(TrainStep)
        if not ok then
            notyuri("AutoTrain", err)
        end
        task.wait(2)
    end
end

TB_Tabs.Autofarm.T1:AddToggle("AutoPack", { Text = "Auto Pack" })
TB_Tabs.Autofarm.T1:AddSlider("PackDelay", {
    Text = "Pack Delay",
    Default = 0.4,
    Min = 0.3,
    Max = 1.5,
    Rounding = 1,
    Suffix = "s",
})
TB_Tabs.Autofarm.T1:AddDivider()
TB_Tabs.Autofarm.T1:AddToggle("AutoBuyPads", { Text = "Auto Buy Pads" })
TB_Tabs.Autofarm.T1:AddDivider()
TB_Tabs.Autofarm.T1:AddToggle("AutoSpin", { Text = "Auto Spin" })
TB_Tabs.Autofarm.T1:AddDivider()
TB_Tabs.Autofarm.T1:AddToggle("AutoTrain", { Text = "Auto Train Staff" })

Toggles.AutoPack:OnChanged(function(state)
    Thread("AutoPack", SafeLoop("AutoPack", Func_AutoPack), state)
end)
Toggles.AutoBuyPads:OnChanged(function(state)
    Thread("AutoBuyPads", SafeLoop("AutoBuyPads", Func_AutoBuyPads), state)
end)
Toggles.AutoSpin:OnChanged(function(state)
    Thread("AutoSpin", SafeLoop("AutoSpin", Func_AutoSpin), state)
end)
Toggles.AutoTrain:OnChanged(function(state)
    Thread("AutoTrain", SafeLoop("AutoTrain", Func_AutoTrain), state)
end)
