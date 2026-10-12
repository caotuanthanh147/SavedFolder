--- ReplicatedStorage.Meeting.CareerConfig [ModuleScript]
-- y u r i

local tbl1 = {
	Ranks = {
		{ Name = "Intern", Exp = 0, TaskPay = 50, EndMult = 1, Bonus = 0 },
		{ Name = "Junior Employee", Exp = 100, TaskPay = 55, EndMult = 1.05, Bonus = 25 },
		{ Name = "Employee", Exp = 300, TaskPay = 60, EndMult = 1.1, Bonus = 50 },
		{ Name = "Senior Employee", Exp = 700, TaskPay = 65, EndMult = 1.15, Bonus = 75 },
		{ Name = "Team Lead", Exp = 1500, TaskPay = 70, EndMult = 1.25, Bonus = 100 },
		{ Name = "Manager", Exp = 3000, TaskPay = 75, EndMult = 1.35, Bonus = 150 },
		{ Name = "Director", Exp = 6000, TaskPay = 80, EndMult = 1.5, Bonus = 200 },
		{ Name = "Vice President", Exp = 10000, TaskPay = 90, EndMult = 1.65, Bonus = 300 },
		{ Name = "CEO", Exp = 20000, TaskPay = 100, EndMult = 2, Bonus = 500 },
	},
	RookieShield = { 0.85, 0.92 },
	Exp = { Task = 10, Survive = 15, RollCall = 5, Printer = 5, Quiz = 5, Hack = 5, PerTenWork = 1 },
}

tbl1.RankIndex = function(arg1)
	arg1 = tonumber(arg1) or 0
	local num1 = 1
	for k1, v1 in ipairs(tbl1.Ranks) do
		if v1.Exp > arg1 then
			continue
		end

		num1 = k1
	end

	return num1
end

tbl1.Rank = function(arg1)
	return tbl1.Ranks[tbl1.RankIndex(arg1)]
end

tbl1.Progress = function(arg1)
	arg1 = tonumber(arg1) or 0
	local var1 = tbl1.RankIndex(arg1)
	local var4 = tbl1.Ranks[var1 + 1]
	local var5 = tbl1.Ranks[var1]
	if not var4 then
		return 1, arg1 - var5.Exp, nil
	end

	return math.clamp((arg1 - var5.Exp) / (var4.Exp - var5.Exp), 0, 1), arg1 - var5.Exp, var4.Exp - var5.Exp
end

tbl1.PaperBaseCooldown = 20
tbl1.PaperUpgrades = {
	{ Name = "Graphing Paper", Cooldown = 16, Price = 300, Rank = 2 },
	{ Name = "Coloring Paper", Cooldown = 13, Price = 750, Rank = 3 },
	{ Name = "Tinfoil", Cooldown = 10, Price = 1800, Rank = 4 },
	{ Name = "Rock", Cooldown = 7, Price = 4000, Rank = 5 },
}

tbl1.PaperCooldown = function(arg1)
	arg1 = math.clamp(math.floor(tonumber(arg1) or 0), 0, #tbl1.PaperUpgrades)
	return arg1 == 0 and tbl1.PaperBaseCooldown or tbl1.PaperUpgrades[arg1].Cooldown
end

tbl1.PhoneBaseSend = 6
tbl1.PhoneBaseCooldown = 20
tbl1.PhoneUpgrades = {
	{ Name = "Fresh Batteries", Send = 5, Cooldown = 17, Price = 200, Rank = 2 },
	{ Name = "T9 Texting", Send = 4, Cooldown = 14, Price = 500, Rank = 3 },
	{ Name = "Speed Dial", Send = 3, Cooldown = 11, Price = 1200, Rank = 4 },
	{ Name = "Unlimited Texts", Send = 2, Cooldown = 8, Price = 3000, Rank = 5 },
}

tbl1.PhoneCooldown = function(arg1)
	arg1 = math.clamp(math.floor(tonumber(arg1) or 0), 0, #tbl1.PhoneUpgrades)
	return arg1 == 0 and tbl1.PhoneBaseCooldown or tbl1.PhoneUpgrades[arg1].Cooldown
end

tbl1.PhoneSend = function(arg1)
	arg1 = math.clamp(math.floor(tonumber(arg1) or 0), 0, #tbl1.PhoneUpgrades)
	return arg1 == 0 and tbl1.PhoneBaseSend or tbl1.PhoneUpgrades[arg1].Send
end

tbl1.Playtime = {
	{ Minutes = 2, Bobux = 15 },
	{ Minutes = 5, Bobux = 25 },
	{ Minutes = 15, Bobux = 50 },
	{ Minutes = 30, Bobux = 80 },
	{ Minutes = 60, Bobux = 130 },
}

return tbl1

--- ReplicatedStorage.Meeting.RestartTimeline [ModuleScript]
