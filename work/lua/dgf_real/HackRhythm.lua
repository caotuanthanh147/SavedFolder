--- ReplicatedStorage.Meeting.HackRhythm [ModuleScript]
-- y u r i

local tbl1 = {
	DIRS = { "Up", "Left", "Right", "Down" },
	MISS_WIN = 0.32,
	PERFECT = 0.09,
	GOOD = 0.22,
	POINTS = { Perfect = 2, Good = 1, Miss = 0 },
	SWING = 30,
}

tbl1.Chart = function(arg1, arg2, arg3)
	local var1 = arg3
	arg3 = var1 or {}
	var1 = arg3.easy == true
	local var2 = var1 and 2 + arg2 or 3 + arg2
	local var3 = var1 and 1.5 - 0.06 * (arg2 - 1) or 1.4 - 0.1 * (arg2 - 1)
	local var4 = (function() if var1 then return 0.8 else return 0.72 - 0.05 * (arg2 - 1) end end)()
	local var5 = (function() if var1 then return 0.55 else return math.max(0.36, 0.5 - 0.035 * (arg2 - 1)) end end)()
	local tbl2 = {}
	local var6 = var3 + 0.1
	local var7 = nil
	local num1 = 0
	for i1 = 1, var2 do
		local var8 = nil
		repeat
			var8 = tbl1.DIRS[arg1:NextInteger(1, 4)]
		until var8 ~= var7 or 2 > num1

		tbl2[i1] = { d = var8, t = var6 }
		var6 = var6 + arg1:NextNumber(var5, var4)
		local var9 = var8
		num1 = (function() if var8 == var7 then return num1 + 1 else return 1 end end)()
	end

	local var10 = arg3.scale or 1
	local var11 = tbl1.GOOD * var10
	local var12 = math.max(tbl1.MISS_WIN, var11 + 0.08)
	local tbl3 = {
		notes = tbl2,
		travel = var3,
		perfect = tbl1.PERFECT * var10,
		good = var11,
		missWin = var12,
		window = tbl2[#tbl2].t + var12 + 0.05,
	}

	local var13
	if arg2 <= 1 then
		var13 = "EASY"
	else
		if arg2 <= 2 then
			var13 = "NORMAL"
		elseif arg2 <= 4 then
			var13 = "HARD"
		else
			var13 = "INSANE"
		end
	end

	tbl3.level = var13
	return tbl3
end

tbl1.NewState = function()
	return { res = {}, strays = 0, combo = 0, best = 0 }
end

tbl1.Judge = function(arg1, arg2, arg3, arg4)
	local var1 = arg1.missWin
	local var2 = nil
	var1 = var1 or tbl1.MISS_WIN
	for k1, v1 in ipairs(arg1.notes) do
		if arg2.res[k1] then
			goto L3
		end

		local var3 = math.abs(arg4 - v1.t)
		if var3 > var1 then
			goto L3
		end

		var2 = k1
		var1 = var3
	::L3:: end

	if not var2 then
		local var4 = arg2.strays + 1
		arg2.strays = var4
		return nil, "Stray"
	end

	local var6 = nil
	if arg3 ~= arg1.notes[var2].d then
		var6 = "Miss"
	else
		if var1 <= arg1.perfect then
			var6 = "Perfect"
		else
			var6 = (function() if var1 <= arg1.good then return "Good" else return "Miss" end end)()
		end
	end

	arg2.res[var2] = var6
	if var6 == "Miss" then
		arg2.combo = 0
	else
		local var7 = arg2.combo + 1
		arg2.combo = var7
		var7 = math.max(arg2.best, arg2.combo)
		arg2.best = var7
	end

	return var2, var6
end

tbl1.Expire = function(arg1, arg2, arg3)
	local tbl2 = {}
	for k1, v1 in ipairs(arg1.notes) do
		if arg2.res[k1] then
			goto L4
		end

		local var1 = arg1.missWin
		if v1.t + (var1 or tbl1.MISS_WIN) >= arg3 then
			goto L4
		end

		arg2.res[k1] = "Miss"
		arg2.combo = 0
		table.insert(tbl2, k1)
	::L4:: end

	return tbl2
end

tbl1.AllJudged = function(arg1, arg2)
	for k1 in ipairs(arg1.notes) do
		if arg2.res[k1] then
			goto L5
		end

		do return false
	 end ::L5:: end

	return true
end

tbl1.Accuracy = function(arg1, arg2)
	local num1 = 0
	for k1 in ipairs(arg1.notes) do
		num1 = num1 + tbl1.POINTS[arg2.res[k1] or "Miss"]
	end

	return (math.clamp(math.max(0, num1 - 0.5 * arg2.strays) / (#arg1.notes * 2), 0, 1))
end

tbl1.Bucket = function(arg1)
	if 0.85 <= arg1 then
		return "Perfect"
	end

	if 0.45 <= arg1 then
		return "Good"
	end

	return "Miss"
end

tbl1.Resolve = function(arg1, arg2)
	local var3 = tbl1.Bucket(arg1)
	local var4 = tbl1.Bucket(arg2)
	local var5 = math.floor((arg1 - arg2) * tbl1.SWING + 0.5)
	local tbl2 = { Perfect = "Good", Good = "Miss", Miss = "Miss" }
	if var3 == var4 then
		if 0.12 < math.abs(arg1 - arg2) then
			if arg2 < arg1 then
				var4 = tbl2[var4]
			else
				var3 = tbl2[var3]
			end

			if var3 == var4 then
				if arg2 < arg1 then
					return var5, "Good", "Miss"
				end

				var3 = "Miss"
				var4 = "Good"
			end
		end
	end

	return var5, var3, var4
end

return tbl1

--- ReplicatedStorage.Meeting.HackHeadImage [ModuleScript]
