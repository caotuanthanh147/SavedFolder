local BADFolder = RS:FindFirstChild("BAD") or RS:WaitForChild("BAD", 15)
local Config = BADFolder and GetSafeModule(BADFolder, "Config")
local GridUtil = BADFolder and GetSafeModule(BADFolder, "GridUtil")
local RemotesFolder = BADFolder and (BADFolder:FindFirstChild("Remotes") or BADFolder:WaitForChild("Remotes", 15))
Remotes.Action = RemotesFolder and RemotesFolder:FindFirstChild("Action")
Remotes.Build = RemotesFolder and RemotesFolder:FindFirstChild("Build")
Remotes.RollControls = RemotesFolder and RemotesFolder:FindFirstChild("RollControls")
Remotes.LabQ = RemotesFolder and RemotesFolder:FindFirstChild("LabQ")
Shared.RollActive = { Buildings = false, Monsters = false }

local function PlotFolder(index)
    local plots = index and workspace:FindFirstChild("Plots") or nil
    return plots and plots:FindFirstChild("Plot" .. index) or nil
end

local function PlotData(index)
    local folder = PlotFolder(index)
    local state = folder and folder:FindFirstChild("State") or nil
    if not (state and state.Value ~= "") then
        return nil
    end
    local ok, data = pcall(HttpService.JSONDecode, HttpService, state.Value)
    if ok and type(data) == "table" and type(data.floors) == "table" then
        return data
    end
    return nil
end

local function CountOf(id)
    local def = Config and Config.Items[id] or nil
    if not def then
        return 0
    end
    local raw = Plr:GetAttribute(def.kind == "monster" and "Mons" or "Inv")
    if type(raw) ~= "string" then
        return 0
    end
    local ok, bag = pcall(HttpService.JSONDecode, HttpService, raw)
    return ok and type(bag) == "table" and bag[id] or 0
end

local BuildsFolder = "Yuri/BuildADungeon/Builds"
local MatLabel = nil
local BuildSources = {}

local function PlotList()
    local list = {}
    local plots = workspace:FindFirstChild("Plots")
    if plots then
        for _, model in ipairs(plots:GetChildren()) do
            local idx = model:GetAttribute("PlotIndex")
            if idx then
                local data = PlotData(idx)
                if data and data.owner and data.owner ~= 0 then
                    list[#list + 1] = { index = idx, name = data.name or ("Plot" .. idx), mine = data.owner == Plr.UserId }
                end
            end
        end
    end
    table.sort(list, function(a, b)
        if a.mine ~= b.mine then return a.mine end
        return a.name < b.name
    end)
    return list
end

local function BlocksOfData(data)
    local blocks = {}
    for f = 1, #data.floors do
        local floor = data.floors[f]
        for k, id in pairs(floor.tiles or {}) do
            local c, r = GridUtil.unkey(k)
            blocks[#blocks + 1] = { id = id, f = f, c = c, r = r, rot = floor.trot and floor.trot[k] or 0 }
        end
    end
    for f = 1, #data.floors do
        local floor = data.floors[f]
        for k, obj in pairs(floor.objs or {}) do
            local c, r = GridUtil.unkey(k)
            blocks[#blocks + 1] = { id = obj.id, f = f, c = c, r = r, rot = obj.rot or 0 }
        end
    end
    return blocks
end

local function ListBuildFiles()
    local files = {}
    if not Support.FileIO then return files end
    pcall(function()
        if not isfolder(BuildsFolder) then return end
        for _, name in ipairs(listfiles(BuildsFolder)) do
            if name:sub(-5) == ".json" then
                local short = name:match("([^/\\]+)%.json$")
                if short then files[#files + 1] = short end
            end
        end
    end)
    table.sort(files)
    return files
end

local function SaveBuildFile(name, blocks)
    if not name or name == "" then
        Library:Notify("Enter a file name first.", 3)
        return false
    end
    if not Support.FileIO then
        Library:Notify("File IO not supported by executor.", 4)
        return false
    end
    if not blocks or #blocks == 0 then
        Library:Notify("No placed items to save.", 4)
        return false
    end
    local ok, json = pcall(function() return HttpService:JSONEncode({ version = 1, count = #blocks, blocks = blocks }) end)
    if not ok or not json then
        Library:Notify("Failed to encode build data.", 4)
        return false
    end
    local path = BuildsFolder .. "/" .. name .. ".json"
    pcall(function()
        if makefolder then pcall(makefolder, BuildsFolder) end
        writefile(path, json)
    end)
    Library:Notify("Build saved: " .. name, 4)
    return true
end

local function DecodeBuildJSON(json)
    if not json or json == "" then return nil end
    local ok, data = pcall(function() return HttpService:JSONDecode(json) end)
    if ok and type(data) == "table" and type(data.blocks) == "table" then return data end
    return nil
end

local function ReadBuildFile(name)
    if not Support.FileIO or not name or name == "" then return nil end
    local path = BuildsFolder .. "/" .. name .. ".json"
    if not isfile(path) then return nil end
    local ok, json = pcall(readfile, path)
    if not ok or type(json) ~= "string" then return nil end
    return DecodeBuildJSON(json)
end

local function RefreshBuildSources()
    if not Options.BuildSourceDropdown then return end
    local values = {}
    BuildSources = {}
    for _, entry in ipairs(PlotList()) do
        local label = (entry.mine and "[My Plot] " or "[Plot] ") .. entry.name
        values[#values + 1] = label
        BuildSources[label] = { kind = "Plot", index = entry.index }
    end
    for _, fname in ipairs(ListBuildFiles()) do
        local label = "[File] " .. fname
        values[#values + 1] = label
        BuildSources[label] = { kind = "File", name = fname }
    end
    Options.BuildSourceDropdown:SetValues(values)
end

local function LoadSelectedBuildSource()
    local sel = Options.BuildSourceDropdown and Options.BuildSourceDropdown.Value
    if not sel or sel == "" then return nil end
    local entry = BuildSources[sel]
    if not entry then return nil end
    if entry.kind == "Plot" then
        local data = PlotData(entry.index)
        if not data then return nil end
        local blocks = BlocksOfData(data)
        if #blocks == 0 then return nil end
        return { version = 1, count = #blocks, blocks = blocks }
    end
    return ReadBuildFile(entry.name)
end

local function MaterialDisplay(data)
    if not data or type(data.blocks) ~= "table" then return "No build selected." end
    local reqs = {}
    for i = 1, #data.blocks do
        local b = data.blocks[i]
        if b.id then reqs[b.id] = (reqs[b.id] or 0) + 1 end
    end
    local owned = {}
    local own = PlotData(Plr:GetAttribute("PlotIndex"))
    if own then
        for f = 1, #own.floors do
            local floor = own.floors[f]
            for _, id in pairs(floor.tiles or {}) do owned[id] = (owned[id] or 0) + 1 end
            for _, obj in pairs(floor.objs or {}) do owned[obj.id] = (owned[obj.id] or 0) + 1 end
        end
    end
    local parts = {}
    for id, need in pairs(reqs) do
        local have = (owned[id] or 0) + CountOf(id)
        if have < need then
            local def = Config and Config.Items[id] or nil
            parts[#parts + 1] = (def and def.name or id) .. " (x" .. (need - have) .. ")"
        end
    end
    table.sort(parts)
    if #parts == 0 then return "Ready (" .. #data.blocks .. " items)" end
    return "Missing: " .. table.concat(parts, ", ")
end

local function UpdateMaterialLabel()
    if MatLabel == nil then return end
    MatLabel:SetText(MaterialDisplay(LoadSelectedBuildSource()))
end

local function Func_AutoWave()
    while Toggles.AutoWave.Value do
        local ok, err = pcall(function()
            local folder = PlotFolder(Plr:GetAttribute("PlotIndex"))
            if folder and folder:GetAttribute("WaveActive") ~= true and Remotes.Action then
                Remotes.Action:FireServer("startWave")
            end
        end)
        if not ok then notyuri("AutoWave", err) end
        task.wait(2)
    end
end

local function Func_AutoRoll()
    while Toggles.AutoRoll.Value do
        local ok, err = pcall(function()
            if not (Remotes.RollControls and Config) then
                return
            end
            local want = Options.RollWhat.Value
            local kinds = {}
            if want ~= "Monsters" then kinds[#kinds + 1] = "Buildings" end
            if want ~= "Buildings" then kinds[#kinds + 1] = "Monsters" end
            local index = Plr:GetAttribute("PlotIndex")
            local map = workspace:FindFirstChild("Map")
            local rollers = map and map:FindFirstChild("Rollers") or nil
            for _, kind in ipairs(kinds) do
                if Shared.RollActive[kind] ~= true then
                    local stand = rollers and rollers:FindFirstChild("Plot" .. index .. "_" .. kind) or nil
                    if stand then
                        TPTo(stand)
                        task.wait(0.3)
                        Remotes.RollControls:InvokeServer("settings", kind, {
                            rarity = Options.RollStopAt.Value,
                            mut = "Off",
                            pity = "Off",
                            skin = "Off",
                            always = "Divine",
                            protect = "Mythic",
                            category = "All",
                            mode = "Rarity",
                        })
                        Remotes.RollControls:InvokeServer("start", kind)
                        Shared.RollActive[kind] = true
                    end
                end
            end
        end)
        if not ok then notyuri("AutoRoll", err) end
        task.wait(5)
    end
end

local function Func_AutoBuild()
    local attempted = {}
    while Toggles.AutoBuild.Value do
        local ok, err = pcall(function()
            if not (Remotes.Build and Config and GridUtil) then
                return
            end
            local index = Plr:GetAttribute("PlotIndex")
            local data = PlotData(index)
            if not (data and data.floors[1]) then
                return
            end
            local folder = PlotFolder(index)
            local char = GetCharacter()
            if folder and char then
                local hrp = char:FindFirstChild("HumanoidRootPart")
                local pivot = folder:GetPivot()
                if hrp and (hrp.Position - pivot.Position).Magnitude > 100 then
                    TPTo(folder)
                end
            end
            local floor = data.floors[1]
            local lvl = GridUtil.level(floor)
            local cells = {}
            for r = 0, lvl.rows - 1 do
                local row = {}
                for c = lvl.min, lvl.max do row[#row + 1] = c end
                if r % 2 == 1 then
                    local rev = {}
                    for i = #row, 1, -1 do rev[#rev + 1] = row[i] end
                    row = rev
                end
                for i, c in ipairs(row) do
                    cells[#cells + 1] = { c = c, r = r, turn = i == 1 or i == #row }
                end
            end
            local hasCrystal = false
            for f = 1, #data.floors do
                if GridUtil.findSpecial(data.floors[f], "Crystal") then
                    hasCrystal = true
                    break
                end
            end
            local needCrystal = not hasCrystal and #data.floors == 1
            for _, cell in ipairs(cells) do
                if not (needCrystal and cell == cells[#cells]) then
                local k = GridUtil.key(cell.c, cell.r)
                if not floor.tiles[k] and not attempted["1:" .. k] then
                    local prefs = cell.turn and { "Crossroads", "CorridorT", "CorridorEnd", "WoodFloor" } or { "YellowCorridor", "CorridorEnd", "Crossroads", "CorridorT", "WoodFloor" }
                    local pick = nil
                    for _, id in ipairs(prefs) do
                        if Config.Items[id] and CountOf(id) > 0 then
                            pick = id
                            break
                        end
                    end
                    if not pick then
                        for id, def in pairs(Config.Items) do
                            if def.kind == "floor" and CountOf(id) > 0 then
                                pick = id
                                break
                            end
                        end
                    end
                    if pick then
                        local res = Remotes.Build:InvokeServer({ action = "place", id = pick, f = 1, c = cell.c, r = cell.r, rot = pick == "YellowCorridor" and 1 or 0 })
                        if res and res.ok == false then
                            attempted["1:" .. k] = true
                        end
                        return
                    end
                end
                end
            end
            if needCrystal then
                local endCell = cells[#cells]
                if endCell then
                    local k = GridUtil.key(endCell.c, endCell.r)
                    if not floor.tiles[k] and CountOf("Crystal") > 0 and not GridUtil.isFixedCell(data, 1, endCell.c, endCell.r) then
                        floor.tiles[k] = "Crystal"
                        local path = GridUtil.buildFullPath(data, "main") ~= nil
                        floor.tiles[k] = nil
                        if path then
                            Remotes.Build:InvokeServer({ action = "place", id = "Crystal", f = 1, c = endCell.c, r = endCell.r, rot = 0 })
                        end
                        return
                    end
                end
            end
            for _, cell in ipairs(cells) do
                local k = GridUtil.key(cell.c, cell.r)
                if floor.tiles[k] and not floor.objs[k] and not attempted["1:" .. k] then
                    for id, def in pairs(Config.Items) do
                        if def.kind == "trap" and CountOf(id) > 0 then
                            local fits = GridUtil.canPlaceObject(floor, def, cell.c, cell.r, 0)
                            if fits then
                                local res = Remotes.Build:InvokeServer({ action = "place", id = id, f = 1, c = cell.c, r = cell.r, rot = 0 })
                                if res and res.ok == false then
                                    attempted["1:" .. k] = true
                                end
                                return
                            end
                        end
                    end
                end
            end
            local pop = Plr:GetAttribute("Pop") or 0
            local maxPop = Plr:GetAttribute("MaxPop") or math.huge
            if pop < maxPop then
                for _, cell in ipairs(cells) do
                    local k = GridUtil.key(cell.c, cell.r)
                    if floor.tiles[k] and not floor.objs[k] and not attempted["1:" .. k] then
                        local best, bestDef, bestPow = nil, nil, -1
                        for id, def in pairs(Config.Items) do
                            if def.kind == "monster" and CountOf(id) > 0 then
                                local power = Config.UnitPower and Config.UnitPower(def, 1, 0) or 0
                                if power > bestPow and pop + (def.pop or 1) <= maxPop then
                                    best, bestDef, bestPow = id, def, power
                                end
                            end
                        end
                        if best and GridUtil.canPlaceObject(floor, bestDef, cell.c, cell.r, 0) then
                            local res = Remotes.Build:InvokeServer({ action = "place", id = best, f = 1, c = cell.c, r = cell.r, rot = 0 })
                            if res and res.ok == false then
                                attempted["1:" .. k] = true
                            end
                            return
                        end
                    end
                end
            end
        end)
        if not ok then notyuri("AutoBuild", err) end
        task.wait(Options.PlaceDelay.Value)
    end
end

local function Func_LoadBuild()
    while Toggles.LoadBuild.Value do
        local ok, err = pcall(function()
            if not (Remotes.Build and Config and GridUtil) then
                return
            end
            local src = LoadSelectedBuildSource()
            if not src then
                Library:Notify("Select a build source first.", 3)
                return
            end
            local index = Plr:GetAttribute("PlotIndex")
            local own = PlotData(index)
            if not (own and own.floors[1]) then
                return
            end
            local folder = PlotFolder(index)
            local char = GetCharacter()
            if folder and char then
                local hrp = char:FindFirstChild("HumanoidRootPart")
                local pivot = folder:GetPivot()
                if hrp and (hrp.Position - pivot.Position).Magnitude > 100 then
                    TPTo(folder)
                end
            end
            local ownedNow = {}
            for id in pairs(Config.Items) do
                local n = CountOf(id)
                if n > 0 then ownedNow[id] = n end
            end
            local pop = Plr:GetAttribute("Pop") or 0
            local maxPop = Plr:GetAttribute("MaxPop") or math.huge
            local placed, skipped = 0, 0
            for i = 1, #src.blocks do
                if not Toggles.LoadBuild.Value then break end
                local b = src.blocks[i]
                local def = Config.Items[b.id]
                local floor = b.f >= 1 and b.f <= #own.floors and own.floors[b.f] or nil
                if not (def and floor) or def.kind == "special" then
                    skipped = skipped + 1
                elseif def.kind == "floor" then
                    local k = GridUtil.key(b.c, b.r)
                    if floor.tiles[k] or (ownedNow[b.id] or 0) <= 0 or not GridUtil.inBounds(floor, b.c, b.r) then
                        skipped = skipped + 1
                    else
                        Remotes.Build:InvokeServer({ action = "place", id = b.id, f = b.f, c = b.c, r = b.r, rot = b.rot or 0 })
                        ownedNow[b.id] = ownedNow[b.id] - 1
                        floor.tiles[k] = b.id
                        placed = placed + 1
                        task.wait(Options.PlaceDelay.Value)
                    end
                else
                    local k = GridUtil.key(b.c, b.r)
                    if floor.objs[k] or not floor.tiles[k] or (ownedNow[b.id] or 0) <= 0 then
                        skipped = skipped + 1
                    elseif def.kind == "monster" and pop + (def.pop or 1) > maxPop then
                        skipped = skipped + 1
                    elseif not GridUtil.canPlaceObject(floor, def, b.c, b.r, b.rot or 0) then
                        skipped = skipped + 1
                    else
                        Remotes.Build:InvokeServer({ action = "place", id = b.id, f = b.f, c = b.c, r = b.r, rot = b.rot or 0 })
                        ownedNow[b.id] = ownedNow[b.id] - 1
                        floor.objs[k] = { id = b.id, rot = b.rot or 0, lvl = 1 }
                        if def.kind == "monster" then pop = pop + (def.pop or 1) end
                        placed = placed + 1
                        task.wait(Options.PlaceDelay.Value)
                    end
                end
            end
            Library:Notify(("LoadBuild done: %d placed, %d skipped."):format(placed, skipped), 5)
        end)
        if not ok then notyuri("LoadBuild", err) end
        task.wait(5)
    end
end

local function Func_AutoUpgrade()
    local attempted = {}
    while Toggles.AutoUpgrade.Value do
        local ok, err = pcall(function()
            if not (Remotes.Build and Config) then
                return
            end
            local data = PlotData(Plr:GetAttribute("PlotIndex"))
            if not data then
                return
            end
            local souls = Plr:GetAttribute("DarkSouls") or 0
            local gold = Plr:GetAttribute("Gold") or 0
            local pick, pickCost, pickCur, pickF, pickK = nil, math.huge, nil, nil, nil
            for f = 1, #data.floors do
                local floor = data.floors[f]
                for k, obj in pairs(floor.objs or {}) do
                    local tag = f .. ":" .. k
                    if not attempted[tag] then
                        local def = Config.Items[obj.id]
                        if def then
                            local cost, currency = nil, nil
                            if def.mon then
                                if (obj.lvl or 1) < (Config.UNIT_MAX_LEVEL or 10) then
                                    cost = Config.UnitLevelCost({ price = Config.UnitPriceById[obj.id] or Config.UnitPrice[def.rarity] or 1 }, obj.lvl or 1)
                                    currency = "DarkSouls"
                                end
                            else
                                cost = Config.UpgradeCost(def, obj.lvl or 1)
                                currency = "Gold"
                            end
                            if cost and cost > 0 and cost < pickCost then
                                local have = currency == "DarkSouls" and souls or gold
                                if have >= cost then
                                    pick, pickCost, pickCur, pickF, pickK = obj, cost, currency, f, k
                                end
                            end
                        end
                    end
                end
            end
            if pick then
                local c, r = GridUtil.unkey(pickK)
                local res = Remotes.Build:InvokeServer({ action = "upgrade", f = pickF, c = c, r = r })
                if res and res.ok == false then
                    attempted[pickF .. ":" .. pickK] = true
                end
            end
        end)
        if not ok then notyuri("AutoUpgrade", err) end
        task.wait(2)
    end
end

local function Func_AutoExpand()
    while Toggles.AutoExpand.Value do
        local ok, err = pcall(function()
            if not (Remotes.Build and Config and GridUtil) then
                return
            end
            local data = PlotData(Plr:GetAttribute("PlotIndex"))
            if not (data and data.floors[1]) then
                return
            end
            local floor = data.floors[1]
            local nxt = Config.WidthLevels[(floor.w or 1) + 1]
            if nxt and (Plr:GetAttribute("Gold") or 0) >= nxt.cost and (Plr:GetAttribute("Wave") or 1) >= (nxt.wave or 0) then
                local folder = PlotFolder(Plr:GetAttribute("PlotIndex"))
                local char = GetCharacter()
                if folder and char then
                    local hrp = char:FindFirstChild("HumanoidRootPart")
                    local pivot = folder:GetPivot()
                    if hrp and (hrp.Position - pivot.Position).Magnitude > 100 then
                        TPTo(folder)
                    end
                end
                Remotes.Build:InvokeServer({ action = "expand", f = 1 })
            end
        end)
        if not ok then notyuri("AutoExpand", err) end
        task.wait(5)
    end
end

local function Func_AutoSkill()
    while Toggles.AutoSkill.Value do
        local ok, err = pcall(function()
            if not (Remotes.Build and Config) then
                return
            end
            local owned = {}
            local raw = Plr:GetAttribute("Skills")
            if type(raw) == "string" then
                pcall(function()
                    owned = HttpService:JSONDecode(raw) or {}
                end)
            end
            owned.Heart = true
            for _, skill in ipairs(Config.Skills) do
                if owned[skill.id] ~= true and Config.SkillBuyable(owned, skill) then
                    if (Plr:GetAttribute("DarkSouls") or 0) >= (skill.cost or 0) then
                        Remotes.Build:InvokeServer({ action = "skill", id = skill.id })
                    end
                    return
                end
            end
        end)
        if not ok then notyuri("AutoSkill", err) end
        task.wait(3)
    end
end

local function Func_AutoAttack()
    while Toggles.AutoAttack.Value do
        local ok, err = pcall(function()
            if not Remotes.Action then
                return
            end
            local char = GetCharacter()
            if not char then
                return
            end
            local hum = char:FindFirstChildOfClass("Humanoid")
            local tool = char:FindFirstChildOfClass("Tool")
            if not (tool and hum) then
                local pack = Plr:FindFirstChild("Backpack")
                local nextTool = pack and pack:FindFirstChildOfClass("Tool") or nil
                if nextTool and hum then
                    hum:EquipTool(nextTool)
                end
                return
            end
            local style = tool:GetAttribute("WeaponStyle") or "sword"
            local lab = workspace:GetAttribute("LabyrinthMode") == true
            local cds = { bow = 0.8, staff = 0.65, great = 0.7, halberd = 0.66, scythe = 0.7, katana = 0.45, dagger = 0.38 }
            local ranges = { bow = 30, staff = 24, polearm = 16, halberd = 16, scythe = 16, great = 15, katana = 15 }
            local range = ranges[style] or 13
            if lab then
                range = style == "bow" and 36 or (style == "staff" and 28 or range)
            end
            local enemies = workspace:FindFirstChild("BADEnemies")
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if not (enemies and hrp) then
                return
            end
            local best, bestDist = nil, range
            for _, model in ipairs(enemies:GetChildren()) do
                if model:IsA("Model") and (model:GetAttribute("CombatHP") or 0) > 0 then
                    local part = model:FindFirstChild("UpperTorso") or model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
                    if part then
                        local delta = part.Position - hrp.Position
                        local dist = Vector3.new(delta.X, 0, delta.Z).Magnitude
                        if math.abs(delta.Y) < 10 and dist <= bestDist then
                            best, bestDist = model, dist
                        end
                    end
                end
            end
            if best then
                local now = os.clock()
                if now - (Shared.AttackLast or 0) >= (cds[style] or 0.5) then
                    Shared.AttackLast = now
                    local part = best:FindFirstChild("UpperTorso") or best.PrimaryPart or best:FindFirstChild("HumanoidRootPart")
                    if part then
                        hrp.CFrame = CFrame.lookAt(hrp.Position, Vector3.new(part.Position.X, hrp.Position.Y, part.Position.Z))
                    end
                    Remotes.Action:FireServer("attack", lab and best:GetAttribute("LabMonster") or nil)
                end
            end
        end)
        if not ok then notyuri("AutoAttack", err) end
        task.wait(0.1)
    end
end

local function Func_AutoQueue()
    while Toggles.AutoQueue.Value do
        local ok, err = pcall(function()
            if workspace:GetAttribute("LabyrinthMode") ~= true and Remotes.LabQ then
                Remotes.LabQ:FireServer("solo", { sel = { map = "labyrinth", diff = Options.QueueDiff.Value } })
            end
        end)
        if not ok then notyuri("AutoQueue", err) end
        task.wait(10)
    end
end

do
    local notify = RemotesFolder and RemotesFolder:FindFirstChild("Notify") or nil
    SafeConnect("RollState", function()
        return notify and notify.OnClientEvent or nil
    end, function(name, payload)
        if name == "autoRollState" and type(payload) == "table" and payload.kind then
            Shared.RollActive[payload.kind] = payload.active == true
        end
    end)
end

TB_Tabs.Autofarm.T1:AddToggle("AutoWave", { Text = "Auto Wave", Default = false })
TB_Tabs.Autofarm.T1:AddToggle("AutoStart", { Text = "Auto Start (Auto skill)", Default = false })
TB_Tabs.Autofarm.T1:AddToggle("AutoSpeed", { Text = "2x Speed (Speed skill)", Default = false })
TB_Tabs.Autofarm.T1:AddDivider()
TB_Tabs.Autofarm.T1:AddToggle("AutoRoll", { Text = "Auto Roll", Default = false })
TB_Tabs.Autofarm.T1:AddDropdown("RollWhat", {
    Text = "Roll What",
    Values = { "Both", "Buildings", "Monsters" },
    Default = "Both",
})
TB_Tabs.Autofarm.T1:AddDropdown("RollStopAt", {
    Text = "Stop At",
    Values = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret", "Divine" },
    Default = "Legendary",
})
TB_Tabs.Autofarm.T1:AddDivider()
TB_Tabs.Autofarm.T1:AddToggle("AutoUpgrade", { Text = "Auto Upgrade", Default = false })
TB_Tabs.Autofarm.T1:AddToggle("AutoExpand", { Text = "Auto Expand", Default = false })
TB_Tabs.Autofarm.T1:AddToggle("AutoSkill", { Text = "Auto Skill", Default = false })
TB_Tabs.Autofarm.T1:AddDivider()
TB_Tabs.Autofarm.T1:AddToggle("AutoAttack", { Text = "Auto Attack", Default = false })
TB_Tabs.Autofarm.T1:AddToggle("AutoQueue", { Text = "Auto Queue Labyrinth", Default = false })
TB_Tabs.Autofarm.T1:AddDropdown("QueueDiff", {
    Text = "Raid Difficulty",
    Values = { "novice", "adept", "veteran", "nightmare", "abyssal" },
    Default = "novice",
})

A1:AddToggle("AutoBuild", { Text = "Auto Build", Default = false })
A1:AddSlider("PlaceDelay", {
    Text = "Place Delay",
    Default = 0.3,
    Min = 0.15,
    Max = 2,
    Rounding = 2,
    Compact = true,
})
A1:AddDivider()
A1:AddDropdown("BuildSourceDropdown", {
    Text = "Select Build to Load",
    Values = {},
    Default = "",
    Multi = false,
    Searchable = true,
    Callback = function()
        UpdateMaterialLabel()
    end,
})
MatLabel = A2:AddLabel("No build selected.", true)
A1:AddToggle("LoadBuild", { Text = "Load Build", Default = false })
A1:AddInput("BuildSaveName", {
    Text = "File Name",
    Default = "",
    Placeholder = "yuriyuri",
})
A1:AddButton({
    Text = "Save Build",
    Func = function()
        local data = PlotData(Plr:GetAttribute("PlotIndex"))
        local blocks = data and BlocksOfData(data) or nil
        if SaveBuildFile(Options.BuildSaveName and Options.BuildSaveName.Value or "", blocks) then
            RefreshBuildSources()
        end
    end,
})
A1:AddButton({
    Text = "Save Selected",
    Func = function()
        local saveName = Options.BuildSaveName and Options.BuildSaveName.Value or ""
        if not saveName or saveName == "" then
            Library:Notify("Enter a file name first.", 3)
            return
        end
        local data = LoadSelectedBuildSource()
        if not data then
            Library:Notify("Select a build source first.", 3)
            return
        end
        if SaveBuildFile(saveName, data.blocks) then
            RefreshBuildSources()
        end
    end,
})

task.spawn(function()
    task.wait(2)
    RefreshBuildSources()
end)

Toggles.AutoWave:OnChanged(function(state)
    Thread("AutoWave", Func_AutoWave, state)
end)
Toggles.AutoStart:OnChanged(function(state)
    if Remotes.Action then
        Remotes.Action:FireServer("auto")
    end
end)
Toggles.AutoSpeed:OnChanged(function(state)
    if Remotes.Action then
        Remotes.Action:FireServer("speed")
    end
end)
Toggles.AutoRoll:OnChanged(function(state)
    if not state then
        for kind in pairs(Shared.RollActive) do
            Shared.RollActive[kind] = false
        end
    end
    Thread("AutoRoll", Func_AutoRoll, state)
end)
Toggles.AutoBuild:OnChanged(function(state)
    Thread("AutoBuild", Func_AutoBuild, state)
end)
Toggles.LoadBuild:OnChanged(function(state)
    Thread("LoadBuild", Func_LoadBuild, state)
end)
Toggles.AutoUpgrade:OnChanged(function(state)
    Thread("AutoUpgrade", Func_AutoUpgrade, state)
end)
Toggles.AutoExpand:OnChanged(function(state)
    Thread("AutoExpand", Func_AutoExpand, state)
end)
Toggles.AutoSkill:OnChanged(function(state)
    Thread("AutoSkill", Func_AutoSkill, state)
end)
Toggles.AutoAttack:OnChanged(function(state)
    Thread("AutoAttack", Func_AutoAttack, state)
end)
Toggles.AutoQueue:OnChanged(function(state)
    Thread("AutoQueue", Func_AutoQueue, state)
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
SaveManager:SetFolder("Yuri/BuildADungeon")
