local MFolder = RS:FindFirstChild("Meeting") or RS:WaitForChild("Meeting", 15)
local RFolder = MFolder and MFolder:FindFirstChild("Remotes")
for _, Name in ipairs({ "GetState", "StateUpdated", "SubmitEmail", "SetLaptopView", "JoinMeeting", "DismissScam", "SmackLaptop", "InterruptAction", "UseRelaxItem", "ThrowPaper", "OfficeEvent", "OfficeEventAction", "BossQuiz", "BossQuizAnswer", "HackAction", "HackUpdate", "BuyUpgrade", "ClaimPlaytime", "AlienAction", "HwAction", "VerityAction", "VerityCue", "LaptopFightAction", "LaptopFightCue" }) do
    Remotes[Name] = RFolder and RFolder:FindFirstChild(Name)
end
Shared.ME = {}
Shared.Seen = { Ads = {}, Quiz = {}, Claimed = {}, Upgraded = {} }
Shared.HackGen = 0
Shared.HackAt = 0
Shared.HackViewAt = 0
Shared.HackUntil = 0
Shared.SubmitAt = 0
Shared.Slack = 0
Shared.SmackAt = 0
Shared.RelaxAt = 0
Shared.RollCall = nil
Shared.Printer = nil
Shared.Dance = nil
Shared.DanceMe = false
Shared.Vty = { Path = nil, NextAt = 0 }
Shared.LF = { Active = false, EndsAt = 0, SwingAt = 0 }
Shared.War = { Fire = 0, Warn = nil, HwFire = 0, HwWarn = nil, HwQte = nil }
Shared.Compliments = {
    ["You, sir!"] = true,
    ["Obviously, sir!"] = true,
    ["10/10, stunning!"] = true,
    ["You do, boss!"] = true,
    ["Perfect as always!"] = true,
    ["You, the legend!"] = true,
    ["Best one ever!"] = true,
    ["A total genius!"] = true,
    ["You are, sir!"] = true,
    ["You should be KING!"] = true,
    ["They're amazing!"] = true,
    ["¡Usted, señor!"] = true,
    ["¡Obviamente, señor!"] = true,
    ["¡10/10, preciosa!"] = true,
    ["¡Usted, jefe!"] = true,
    ["¡Perfecto como siempre!"] = true,
    ["¡Usted, la leyenda!"] = true,
    ["¡La mejor de todas!"] = true,
    ["¡Un genio total!"] = true,
    ["¡Debería ser REY!"] = true,
    ["¡Son increíbles!"] = true,
}

local function Func_AutoJoin()
    while Toggles.AutoJoin.Value do
        local ok, err = pcall(function()
            if Remotes.JoinMeeting and MFolder and Plr:GetAttribute("MeetingJoined") ~= true and Plr:GetAttribute("ReturnToMenu") ~= true and Plr:GetAttribute("DayOffIn") ~= true and MFolder:GetAttribute("DayOff") ~= true then
                local Phase = MFolder:GetAttribute("RoundPhase")
                if Phase == "Countdown" or MFolder:GetAttribute("RoundActive") == true then
                    Remotes.JoinMeeting:FireServer()
                end
            end
        end)
        if not ok then notyuri("AutoJoin", err) end
        task.wait(2)
    end
end

local function Func_AutoWork()
    while Toggles.AutoWork.Value do
        local ok, err = pcall(function()
            local S = Shared.ME
            local R = S.AnswerResult
            if type(R) == "table" and R.Id ~= Shared.Seen.Result then
                Shared.Seen.Result = R.Id
                if R.Correct == false then
                    Library:Notify("Wrong answer, expected " .. tostring(R.Right), 4)
                end
            end
            local Event = MFolder and MFolder:GetAttribute("OfficeEvent")
            local Blocked = Plr:GetAttribute("DayOffIn") == true or Event == "PlayerPresentation" or Event == "LaptopFight" or Event == "DayOff"
            if S.Ready and S.Email and not S.Recovering and not S.LaptopBroken and not Blocked then
                if S.LaptopView ~= true and os.clock() - Shared.Slack > 0.3 then
                    Shared.Slack = os.clock()
                    Remotes.SetLaptopView:FireServer(true)
                    return
                end
                if os.clock() - Shared.SubmitAt < 0.8 then return end
                local E = S.Email
                local Choice = nil
                if E.IsScam then
                    Choice = "DELETE"
                elseif E.Kind == "WRITE" then
                    Choice = "WRITE"
                else
                    for Word in string.gmatch(string.lower(tostring(E.Text or "")), "[%a\128-\255]+") do
                        if Word:sub(1, 6) == "approv" or Word:sub(1, 5) == "aprob" or Word:sub(1, 6) == "aprueb" or Word:sub(1, 4) == "apru" then
                            Choice = "APPROVE"
                            break
                        end
                        if Word:sub(1, 7) == "forward" or Word:sub(1, 5) == "reenv" then
                            Choice = "FORWARD"
                            break
                        end
                    end
                end
                if Choice then
                    Shared.SubmitAt = os.clock()
                    Remotes.SubmitEmail:FireServer(E.Token, Choice)
                elseif Shared.SkipToken ~= E.Token then
                    Shared.SkipToken = E.Token
                    Library:Notify("Unrecognized email, skipping: " .. tostring(E.Subject), 5)
                end
            elseif S.LaptopView == true and not S.Email and os.clock() - Shared.HackViewAt > 4 then
                Remotes.SetLaptopView:FireServer(false)
            end
        end)
        if not ok then notyuri("AutoWork", err) end
        task.wait(0.25)
    end
end

local function Func_AutoSmack()
    while Toggles.AutoSmack.Value do
        local ok, err = pcall(function()
            local S = Shared.ME
            if S.LaptopBroken and (S.SmacksLeft or 0) > 0 and os.clock() - Shared.SmackAt > 0.25 then
                Shared.SmackAt = os.clock()
                Remotes.SmackLaptop:FireServer()
            end
        end)
        if not ok then notyuri("AutoSmack", err) end
        task.wait(0.1)
    end
end

local function Func_AutoAds()
    while Toggles.AutoAds.Value do
        local ok, err = pcall(function()
            local Ads = Shared.ME.ScamAds
            if type(Ads) == "table" then
                for _, Ad in ipairs(Ads) do
                    if type(Ad) == "table" and Ad.Id and not Shared.Seen.Ads[Ad.Id] then
                        Shared.Seen.Ads[Ad.Id] = true
                        Remotes.DismissScam:FireServer(Ad.Id)
                        task.wait(0.2)
                    end
                end
            end
        end)
        if not ok then notyuri("AutoAds", err) end
        task.wait(0.25)
    end
end

local function Func_AutoInterrupt()
    while Toggles.AutoInterrupt.Value do
        local ok, err = pcall(function()
            local I = Shared.ME.Interrupt
            if type(I) == "table" and I.Id then
                if I.Id ~= Shared.Seen.Interrupt then
                    Shared.Seen.Interrupt = I.Id
                    if I.Kind == "Call" then
                        Remotes.InterruptAction:FireServer(I.Id, "decline")
                        return
                    end
                end
                if I.Kind == "Update" then
                    Remotes.InterruptAction:FireServer(I.Id, "click")
                    task.wait(0.1)
                end
            end
        end)
        if not ok then notyuri("AutoInterrupt", err) end
        task.wait(0.1)
    end
end

local function Func_AutoEvents()
    while Toggles.AutoEvents.Value do
        local ok, err = pcall(function()
            local RC = Shared.RollCall
            if RC and RC.Id and not RC.Done then
                RC.Done = true
                Remotes.OfficeEventAction:FireServer("here", RC.Id)
            end
            local P = Shared.Printer
            if P and P.Id and P.Count < P.Need then
                local T = workspace:GetServerTimeNow()
                if P.StartsAt <= T and T <= P.EndsAt then
                    P.Count = P.Count + 1
                    Remotes.OfficeEventAction:FireServer("kick", P.Id)
                    task.wait(0.05)
                end
            end
            local D = Shared.Dance
            if D and D.Id and Shared.DanceMe and D.Count < D.Need then
                local T = workspace:GetServerTimeNow()
                if D.StartsAt - 0.15 <= T and T <= D.EndsAt then
                    D.Count = D.Count + 1
                    Remotes.OfficeEventAction:FireServer("dance", D.Id)
                    task.wait(0.15)
                end
            end
        end)
        if not ok then notyuri("AutoEvents", err) end
        task.wait(0.05)
    end
end

local function Func_AutoHack()
    while Toggles.AutoHack.Value do
        local ok, err = pcall(function()
            if not Remotes.HackAction then return end
            local Boss = workspace:FindFirstChild("Boss")
            if Boss and Boss:GetAttribute("BossState") == "BEHIND_PLAYER" and Boss:GetAttribute("WatchedUserId") == Plr.UserId then return end
            if (Plr:GetAttribute("HackReadyAt") or 0) > workspace:GetServerTimeNow() then return end
            if MFolder then
                local Ends = MFolder:GetAttribute("RoundEndsAt")
                if Ends ~= nil and MFolder:GetAttribute("DayOff") ~= true and Ends - 60 <= workspace:GetServerTimeNow() then return end
            end
            if workspace:GetServerTimeNow() < Shared.HackUntil + 0.5 then return end
            if os.clock() - Shared.HackAt < 3 then return end
            Shared.HackAt = os.clock()
            if Shared.ME.LaptopView ~= true then
                Shared.HackViewAt = os.clock()
                Remotes.SetLaptopView:FireServer(true)
            else
                Remotes.HackAction:FireServer("start")
            end
        end)
        if not ok then notyuri("AutoHack", err) end
        task.wait(0.5)
    end
end

local function Func_AutoPaper()
    while Toggles.AutoPaper.Value do
        local ok, err = pcall(function()
            if not Remotes.ThrowPaper then return end
            if Plr:GetAttribute("MeetingJoined") ~= true or Plr:GetAttribute("LaptopView") == true or Plr:GetAttribute("EventLock") == true then return end
            local T = workspace:GetServerTimeNow()
            local War = false
            local Window = false
            if MFolder then
                if MFolder:GetAttribute("OfficeEvent") == "PaperFight" then
                    War = true
                    Window = (MFolder:GetAttribute("PaperFightStartsAt") or math.huge) <= T and T < (MFolder:GetAttribute("PaperFightEndsAt") or 0)
                end
                if not Window and MFolder:GetAttribute("RoundPhase") == "Countdown" then
                    Window = 5 < (MFolder:GetAttribute("CountdownEndsAt") or 0) - T
                end
            end
            if not Window then return end
            if War and Plr:GetAttribute("SeatName") == nil then return end
            local Char = GetCharacter()
            local Hum = Char and Char:FindFirstChildOfClass("Humanoid")
            local Held = Char and Char:FindFirstChildOfClass("Tool")
            if not (Held and Held:GetAttribute("MeetingPaper") == true) then
                local Pack = Plr:FindFirstChild("Backpack")
                for _, Tool in ipairs(Pack and Pack:GetChildren() or {}) do
                    if Tool:IsA("Tool") and Tool:GetAttribute("MeetingPaper") == true and Hum then
                        Hum:EquipTool(Tool)
                        break
                    end
                end
                return
            end
            local Root = Char:FindFirstChild("HumanoidRootPart")
            if not Root then return end
            local MyTeam = War and Plr:GetAttribute("WarTeam") or nil
            local Best, BestDist = nil, 90
            for _, P in ipairs(Players:GetPlayers()) do
                if P ~= Players.LocalPlayer and P:GetAttribute("SeatName") and P:GetAttribute("MeetingJoined") == true and (MyTeam == nil or (P:GetAttribute("WarTeam") ~= nil and P:GetAttribute("WarTeam") ~= MyTeam)) then
                    local Head = P.Character and P.Character:FindFirstChild("Head")
                    if Head then
                        local Dist = (Head.Position - Root.Position).Magnitude
                        if Dist < BestDist then
                            Best, BestDist = P, Dist
                        end
                    end
                end
            end
            for _, M in ipairs(workspace:GetChildren()) do
                if M:GetAttribute("MeetingDummy") and (MyTeam == nil or (M:GetAttribute("WarTeam") ~= nil and M:GetAttribute("WarTeam") ~= MyTeam)) then
                    local Head = M:FindFirstChild("Head")
                    if Head then
                        local Dist = (Head.Position - Root.Position).Magnitude
                        if Dist < BestDist then
                            Best, BestDist = M, Dist
                        end
                    end
                end
            end
            if Best then
                Remotes.ThrowPaper:FireServer(Best)
            end
        end)
        if not ok then notyuri("AutoPaper", err) end
        task.wait(0.3)
    end
end

local function Func_AutoRelax()
    while Toggles.AutoRelax.Value do
        local ok, err = pcall(function()
            if (Shared.ME.Pressure or 0) < Options.RelaxAt.Value then return end
            if os.clock() - Shared.RelaxAt < 7 then return end
            local Boss = workspace:FindFirstChild("Boss")
            local State = Boss and Boss:GetAttribute("BossState")
            if not (Boss == nil or State == "LEAVING" or (State == "BEHIND_PLAYER" and Boss:GetAttribute("WatchedUserId") ~= Plr.UserId)) then return end
            local Char = Plr.Character
            local Held = Char and Char:FindFirstChildOfClass("Tool")
            if Held and Held:GetAttribute("MeetingRelaxItem") == "ButterSquishy" then
                Shared.RelaxAt = os.clock()
                Remotes.UseRelaxItem:FireServer(Held)
            else
                local Hum = Char and Char:FindFirstChildOfClass("Humanoid")
                local Pack = Plr:FindFirstChild("Backpack")
                for _, Tool in ipairs(Pack and Pack:GetChildren() or {}) do
                    if Tool:IsA("Tool") and Tool:GetAttribute("MeetingRelaxItem") == "ButterSquishy" and Hum then
                        Hum:EquipTool(Tool)
                        break
                    end
                end
            end
        end)
        if not ok then notyuri("AutoRelax", err) end
        task.wait(1)
    end
end

local function Func_AutoClaim()
    while Toggles.AutoClaim.Value do
        local ok, err = pcall(function()
            local Cfg = GetSafeModule(MFolder, "CareerConfig")
            local Start = Plr:GetAttribute("PlaytimeStart")
            if not (Cfg and Remotes.ClaimPlaytime and Start and Plr:GetAttribute("EconomyReady")) then return end
            local Elapsed = workspace:GetServerTimeNow() - Start
            local Claimed = Plr:GetAttribute("PlaytimeClaimed") or 0
            for K, Tier in ipairs(Cfg.Playtime) do
                if Elapsed >= Tier.Minutes * 60 and math.floor(Claimed / 2 ^ (K - 1)) % 2 ~= 1 and not Shared.Seen.Claimed[K] then
                    Shared.Seen.Claimed[K] = true
                    Remotes.ClaimPlaytime:FireServer(K)
                end
            end
        end)
        if not ok then notyuri("AutoClaim", err) end
        task.wait(5)
    end
end

local function Func_AutoUpgrade()
    while Toggles.AutoUpgrade.Value do
        local ok, err = pcall(function()
            local Cfg = GetSafeModule(MFolder, "CareerConfig")
            if not (Cfg and Remotes.BuyUpgrade) then return end
            local Rank = Plr:GetAttribute("Rank") or Cfg.RankIndex(Plr:GetAttribute("Exp") or 0)
            local Bobux = Plr:GetAttribute("Bobux") or 0
            local Best = nil
            for _, Track in ipairs({ { "Paper", Cfg.PaperUpgrades, "PaperLevel" }, { "Phone", Cfg.PhoneUpgrades, "PhoneLevel" } }) do
                local Next = Track[2][(Plr:GetAttribute(Track[3]) or 0) + 1]
                if Next and Bobux >= Next.Price and (not Next.Rank or Next.Rank <= Rank) and not Shared.Seen.Upgraded[Track[1] .. (Plr:GetAttribute(Track[3]) or 0)] then
                    if not Best or Next.Price < Best[2].Price then
                        Best = { Track[1], Next, Track[1] .. (Plr:GetAttribute(Track[3]) or 0) }
                    end
                end
            end
            if Best then
                Shared.Seen.Upgraded[Best[3]] = true
                Remotes.BuyUpgrade:FireServer(Best[1])
            end
        end)
        if not ok then notyuri("AutoUpgrade", err) end
        task.wait(5)
    end
end

local function Func_AutoAlien()
    while Toggles.AutoAlien.Value do
        local ok, err = pcall(function()
            if not (Remotes.AlienAction and MFolder) then return end
            local Phase = MFolder:GetAttribute("AlienPhase")
            if Phase ~= "Fight" and Phase ~= "Finale" then return end
            local Cfg = GetSafeModule(MFolder, "AlienConfig")
            local T = workspace:GetServerTimeNow()
            local Dodge = MFolder:GetAttribute("AlienDodgeAt")
            if not (Dodge and T - Dodge < (Cfg and Cfg.DodgeSeconds or 2.4)) and T >= (MFolder:GetAttribute("AlienZappedUntil") or 0) then
                if os.clock() - Shared.War.Fire >= (Cfg and Cfg.FireInterval or 0.085) then
                    Shared.War.Fire = os.clock()
                    Remotes.AlienAction:FireServer("fire")
                end
            end
            local Warn = MFolder:GetAttribute("AlienWarnId")
            if Warn ~= nil and Warn ~= Shared.War.Warn then
                Shared.War.Warn = Warn
                Remotes.AlienAction:FireServer("shield")
            end
        end)
        if not ok then notyuri("AutoAlien", err) end
        task.wait(0.05)
    end
end

local function Func_AutoHalloween()
    while Toggles.AutoHalloween.Value do
        local ok, err = pcall(function()
            if not (Remotes.HwAction and MFolder) then return end
            local Phase = MFolder:GetAttribute("HwPhase")
            if Phase ~= "Fight" and Phase ~= "Finale" and Phase ~= "Climax" then return end
            local Cfg = GetSafeModule(MFolder, "HalloweenConfig")
            local T = workspace:GetServerTimeNow()
            if Phase ~= "Climax" then
                local Dodge = MFolder:GetAttribute("HwDodgeAt")
                if not (Dodge and T - Dodge < (Cfg and Cfg.DodgeSeconds or 2.4)) and T >= (MFolder:GetAttribute("HwZappedUntil") or 0) then
                    if os.clock() - Shared.War.HwFire >= (Cfg and Cfg.FireInterval or 0.085) then
                        Shared.War.HwFire = os.clock()
                        Remotes.HwAction:FireServer("fire")
                    end
                end
            else
                local QKind = MFolder:GetAttribute("HwQteKind")
                local QAt = MFolder:GetAttribute("HwQteAt")
                local QEnd = MFolder:GetAttribute("HwQteEnd")
                if QKind and QAt and QEnd and QAt - 0.05 <= T and T <= QEnd then
                    if QKind == "Mash" then
                        if os.clock() - Shared.War.HwFire >= (Cfg and Cfg.FireInterval or 0.085) then
                            Shared.War.HwFire = os.clock()
                            Remotes.HwAction:FireServer("fire")
                        end
                    elseif QKind == "Dodge" and MFolder:GetAttribute("HwQteId") ~= Shared.War.HwQte then
                        Shared.War.HwQte = MFolder:GetAttribute("HwQteId")
                        Remotes.HwAction:FireServer("shield")
                    end
                end
            end
            local Warn = MFolder:GetAttribute("HwWarnId")
            if Warn ~= nil and Warn ~= Shared.War.HwWarn then
                Shared.War.HwWarn = Warn
                Remotes.HwAction:FireServer("shield")
            end
        end)
        if not ok then notyuri("AutoHalloween", err) end
        task.wait(0.05)
    end
end

local function Func_AutoVerity()
    while Toggles.AutoVerity.Value do
        local ok, err = pcall(function()
            local Path = Shared.Vty.Path
            if not (Path and Remotes.VerityAction) then return end
            if Plr:GetAttribute("MeetingJoined") ~= true or Plr:GetAttribute("ReturnToMenu") == true then return end
            if os.clock() < Shared.Vty.NextAt then return end
            local Cfg = GetSafeModule(MFolder, "VerityConfig")
            if not Cfg then return end
            local Char = GetCharacter()
            local Head = Char and Char:FindFirstChild("Head")
            if not Head then return end
            Shared.Vty.NextAt = os.clock() + Cfg.ThrowRate
            local T = workspace:GetServerTimeNow()
            local Origin = Head.Position + Vector3.new(0, 0.2, 0)
            local Cur = Path:Pos(T)
            local Eta = (Cur - Origin).Magnitude / Cfg.BallSpeed
            local Aim = Path:Pos(T + Eta) + Vector3.new(0, Eta * Eta * 6, 0)
            Remotes.VerityAction:FireServer("throw", Origin, (Aim - Origin).Unit)
        end)
        if not ok then notyuri("AutoVerity", err) end
        task.wait(0.1)
    end
end

local function Func_AutoLaptopFight()
    while Toggles.AutoLaptopFight.Value do
        local ok, err = pcall(function()
            if not (Shared.LF.Active and Remotes.LaptopFightAction) then return end
            local T = workspace:GetServerTimeNow()
            if T > Shared.LF.EndsAt then return end
            local Char = GetCharacter()
            if not (Char and Char:FindFirstChild("FightLaptop")) then return end
            if os.clock() - Shared.LF.SwingAt < 0.55 then return end
            Shared.LF.SwingAt = os.clock()
            Remotes.LaptopFightAction:FireServer("swing")
            task.wait(0.16)
            local Root = Char:FindFirstChild("HumanoidRootPart")
            local Cfg = GetSafeModule(MFolder, "LaptopFightConfig")
            if not (Root and Cfg) then return end
            local Look = Root.CFrame.LookVector
            local Flat = Vector3.new(Look.X, 0, Look.Z)
            local Fwd = Root.Position + (0.1 < Flat.Magnitude and Flat.Unit or Vector3.new(0, 0, -1)) * Cfg.HitboxForward
            local Found = {}
            local function Check(Model)
                local Part = Model and Model:FindFirstChild("HumanoidRootPart")
                if not (Part and Model ~= Char) then return end
                if Cfg.HitboxHeight < math.abs(Part.Position.Y - Root.Position.Y) then return end
                local A = Vector3.new(Part.Position.X - Fwd.X, 0, Part.Position.Z - Fwd.Z).Magnitude
                local B = Vector3.new(Part.Position.X - Root.Position.X, 0, Part.Position.Z - Root.Position.Z).Magnitude
                if A <= Cfg.HitboxRadius + 1 or B <= 2.2 then
                    table.insert(Found, { Model, B })
                end
            end
            for _, P in ipairs(Players:GetPlayers()) do
                if P ~= Players.LocalPlayer and P:GetAttribute("LaptopFighter") == true then
                    Check(P.Character)
                end
            end
            local Dummies = workspace:FindFirstChild("LaptopFightDummies")
            if Dummies then
                for _, M in ipairs(Dummies:GetChildren()) do
                    Check(M)
                end
            end
            table.sort(Found, function(A, B) return A[2] < B[2] end)
            local Hits = {}
            for I = 1, math.min(#Found, 4) do
                Hits[I] = Found[I][1]
            end
            if #Hits > 0 then
                Remotes.LaptopFightAction:FireServer("hit", Hits)
            end
        end)
        if not ok then notyuri("AutoLaptopFight", err) end
        task.wait(0.1)
    end
end

do
    SafeConnect("StateUpdated", function()
        return Remotes.StateUpdated and Remotes.StateUpdated.OnClientEvent
    end, function(S)
        if type(S) == "table" then
            Shared.ME = S
        end
    end)
    SafeConnect("OfficeEvent", function()
        return Remotes.OfficeEvent and Remotes.OfficeEvent.OnClientEvent
    end, function(Kind, Data)
        Data = type(Data) == "table" and Data or {}
        if Kind == "RollCallAsk" then
            Shared.RollCall = { Id = Data.Id, Done = false }
        elseif Kind == "PrinterKick" then
            Shared.Printer = { Id = Data.Id, StartsAt = Data.StartsAt or workspace:GetServerTimeNow(), EndsAt = Data.EndsAt or 0, Need = Data.Need or 16, Count = 0 }
        elseif Kind == "DanceStart" then
            Shared.Dance = { Id = Data.Id, StartsAt = Data.StartsAt or workspace:GetServerTimeNow(), EndsAt = Data.EndsAt or 0, Need = Data.Need or 34, Count = 0 }
        elseif Kind == "DancePicked" then
            Shared.DanceMe = Data.UserId == Plr.UserId
        elseif Kind == "RollCallResult" or Kind == "CalledOut" then
            Shared.RollCall = nil
        elseif Kind == "DanceResult" then
            Shared.Dance = nil
            Shared.DanceMe = false
        elseif Kind == "EventEnd" then
            Shared.RollCall = nil
            Shared.Printer = nil
            Shared.Dance = nil
            Shared.DanceMe = false
        end
    end)
    SafeConnect("BossQuiz", function()
        return Remotes.BossQuiz and Remotes.BossQuiz.OnClientEvent
    end, function(Q)
        if not (Toggles.AutoQuiz and Toggles.AutoQuiz.Value) then return end
        if type(Q) ~= "table" or Q.Result or Shared.Seen.Quiz[Q.Id] then return end
        if type(Q.Options) ~= "table" then return end
        for I, Opt in ipairs(Q.Options) do
            if Shared.Compliments[Opt] then
                Shared.Seen.Quiz[Q.Id] = true
                local Wait = math.max(0, (Q.ReadyAt or workspace:GetServerTimeNow()) - workspace:GetServerTimeNow()) + 0.75
                task.delay(Wait, function()
                    if Toggles.AutoQuiz.Value and workspace:GetServerTimeNow() < (Q.EndsAt or 0) then
                        Remotes.BossQuizAnswer:FireServer(Q.Id, I)
                    end
                end)
                return
            end
        end
    end)
    SafeConnect("HackUpdate", function()
        return Remotes.HackUpdate and Remotes.HackUpdate.OnClientEvent
    end, function(U)
        if type(U) ~= "table" then return end
        if type(U.RoundEnd) == "number" then
            Shared.HackUntil = U.RoundEnd
        end
        if U.State == "active" and not U.Local and type(U.Chart) == "table" and U.RoundStart and Remotes.HackAction then
            Shared.HackGen = Shared.HackGen + 1
            local Gen = Shared.HackGen
            local Id, Round, Start, Notes = U.Id, U.Round, U.RoundStart, U.Chart.notes or {}
            Thread("HackTaps", nil, false)
            Thread("HackTaps", SafeLoop("HackTaps", function()
                for _, Note in ipairs(Notes) do
                    if Shared.HackGen ~= Gen then return end
                    local Delay = Start + Note.t - workspace:GetServerTimeNow() - 0.06
                    if Delay > 0 then
                        task.wait(Delay)
                    end
                    if Shared.HackGen ~= Gen then return end
                    Remotes.HackAction:FireServer("tap", Id, Round, Note.d, Start + Note.t)
                    task.wait(0.02)
                end
            end), true)
        end
    end)
    SafeConnect("VerityCue", function()
        return Remotes.VerityCue and Remotes.VerityCue.OnClientEvent
    end, function(Kind, Data)
        if Kind == "Fight" and type(Data) == "table" then
            local Path = GetSafeModule(MFolder, "VerityPath")
            if Path then
                Shared.Vty.Path = Path.new(Data.Seed, Data.StartAt, Data.Hover, Data.Min, Data.Max)
                Shared.Vty.NextAt = 0
            end
        elseif Kind == "Dodge" and Shared.Vty.Path and type(Data) == "table" then
            Shared.Vty.Path:AddDodge(Data.T0, Data.Dir, Data.Amp)
        elseif Kind == "End" then
            Shared.Vty.Path = nil
        end
    end)
    SafeConnect("LaptopFightCue", function()
        return Remotes.LaptopFightCue and Remotes.LaptopFightCue.OnClientEvent
    end, function(Kind, Data)
        if Kind == "Fight" then
            Shared.LF.Active = true
            Shared.LF.EndsAt = (type(Data) == "table" and Data.EndsAt) or workspace:GetServerTimeNow() + 35
        elseif Kind == "End" then
            Shared.LF.Active = false
        end
    end)
    if Remotes.GetState then
        task.spawn(function()
            local Res = SafeInvoke(Remotes.GetState)
            if type(Res) == "table" then
                Shared.ME = Res
            end
        end)
    end
end

TB_Tabs.Autofarm.T1:AddToggle("AutoJoin", { Text = "Auto Join", Default = false })
TB_Tabs.Autofarm.T1:AddToggle("AutoWork", { Text = "Auto Work", Default = false })
TB_Tabs.Autofarm.T1:AddToggle("AutoSmack", { Text = "Auto Smack", Default = false })
TB_Tabs.Autofarm.T1:AddToggle("AutoAds", { Text = "Auto Dismiss Ads", Default = false })
TB_Tabs.Autofarm.T1:AddToggle("AutoInterrupt", { Text = "Auto Interrupt", Default = false })
TB_Tabs.Autofarm.T1:AddDivider()
TB_Tabs.Autofarm.T1:AddToggle("AutoEvents", { Text = "Auto Events", Default = false })
TB_Tabs.Autofarm.T1:AddToggle("AutoQuiz", { Text = "Auto Quiz", Default = false })
TB_Tabs.Autofarm.T1:AddToggle("AutoHack", { Text = "Auto Hack", Default = false })
TB_Tabs.Autofarm.T1:AddToggle("AutoPaper", { Text = "Auto Paper Fight", Default = false })
TB_Tabs.Autofarm.T1:AddDivider()
TB_Tabs.Autofarm.T1:AddToggle("AutoRelax", { Text = "Auto Relax", Default = false })
TB_Tabs.Autofarm.T1:AddSlider("RelaxAt", { Text = "Relax At", Default = 60, Min = 30, Max = 95, Rounding = 0, Compact = true })
TB_Tabs.Autofarm.T1:AddToggle("AutoClaim", { Text = "Auto Claim Playtime", Default = false })
TB_Tabs.Autofarm.T1:AddToggle("AutoUpgrade", { Text = "Auto Upgrade", Default = false })
TB_Tabs.Autofarm.T1:AddDivider()
TB_Tabs.Autofarm.T1:AddToggle("AutoAlien", { Text = "Auto Old PC", Default = false })
TB_Tabs.Autofarm.T1:AddToggle("AutoHalloween", { Text = "Auto Halloween", Default = false })
TB_Tabs.Autofarm.T1:AddToggle("AutoVerity", { Text = "Auto Verity", Default = false })
TB_Tabs.Autofarm.T1:AddToggle("AutoLaptopFight", { Text = "Auto Laptop Fight", Default = false })

Toggles.AutoJoin:OnChanged(function(state)
    Thread("AutoJoin", SafeLoop("AutoJoin", Func_AutoJoin), state)
end)
Toggles.AutoWork:OnChanged(function(state)
    Thread("AutoWork", SafeLoop("AutoWork", Func_AutoWork), state)
end)
Toggles.AutoSmack:OnChanged(function(state)
    Thread("AutoSmack", SafeLoop("AutoSmack", Func_AutoSmack), state)
end)
Toggles.AutoAds:OnChanged(function(state)
    Thread("AutoAds", SafeLoop("AutoAds", Func_AutoAds), state)
end)
Toggles.AutoInterrupt:OnChanged(function(state)
    Thread("AutoInterrupt", SafeLoop("AutoInterrupt", Func_AutoInterrupt), state)
end)
Toggles.AutoEvents:OnChanged(function(state)
    Thread("AutoEvents", SafeLoop("AutoEvents", Func_AutoEvents), state)
end)
Toggles.AutoHack:OnChanged(function(state)
    Thread("AutoHack", SafeLoop("AutoHack", Func_AutoHack), state)
end)
Toggles.AutoPaper:OnChanged(function(state)
    Thread("AutoPaper", SafeLoop("AutoPaper", Func_AutoPaper), state)
end)
Toggles.AutoRelax:OnChanged(function(state)
    Thread("AutoRelax", SafeLoop("AutoRelax", Func_AutoRelax), state)
end)
Toggles.AutoClaim:OnChanged(function(state)
    Thread("AutoClaim", SafeLoop("AutoClaim", Func_AutoClaim), state)
end)
Toggles.AutoUpgrade:OnChanged(function(state)
    Thread("AutoUpgrade", SafeLoop("AutoUpgrade", Func_AutoUpgrade), state)
end)
Toggles.AutoAlien:OnChanged(function(state)
    Thread("AutoAlien", SafeLoop("AutoAlien", Func_AutoAlien), state)
end)
Toggles.AutoHalloween:OnChanged(function(state)
    Thread("AutoHalloween", SafeLoop("AutoHalloween", Func_AutoHalloween), state)
end)
Toggles.AutoVerity:OnChanged(function(state)
    Thread("AutoVerity", SafeLoop("AutoVerity", Func_AutoVerity), state)
end)
Toggles.AutoLaptopFight:OnChanged(function(state)
    Thread("AutoLaptopFight", SafeLoop("AutoLaptopFight", Func_AutoLaptopFight), state)
end)
