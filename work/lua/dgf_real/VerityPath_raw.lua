--- ReplicatedStorage.Meeting.VerityPath [ModuleScript]
-- y u r i

local tbl1 = {}
tbl1.__index = tbl1
tbl1.new = function(arg1, arg2, arg3, arg4, arg5)
	local var1 = Random.new(arg1)
	local var2 = setmetatable({}, tbl1)
	var2.startAt = arg2
	var2.from = arg3
	var2.min = arg4
	var2.max = arg5
	var2.c = (arg4 + arg5) / 2
	var2.half = (arg5 - arg4) / 2
	var2.p = {}
	for i1 = 1, 8 do
		var2.p[i1] = var1:NextNumber(0, 6.2831853071795862)
	end

	local num1 = 1.9
	local num2 = 2.3
	local tbl2 = {
		var1:NextNumber(0.32, 0.42),
		var1:NextNumber(1, 1.25),
		var1:NextNumber(0.24, 0.32),
		var1:NextNumber(0.85, 1),
		var1:NextNumber(0.7, 0.9),
		var1:NextNumber(num1, num2),
	}

	var2.w = tbl2
	var2.dodges = {}
	return var2
end

tbl1.Base = function(arg1, arg2)
	local var1 = arg1.c
	local var2 = arg1.half
	local var3 = arg1.w
	local var4 = arg1.p
	local var5 = math.clamp(arg2 / 2, 0, 1)
	local var6 = var5 * var5 * (3 - 2 * var5)
	local var7 = Vector3.new(var1.X + var2.X * (math.sin(var3[1] * arg2 + var4[1]) * 0.8 + math.sin(var3[2] * arg2 + var4[2]) * 0.2), var1.Y + var2.Y * (math.sin(var3[5] * arg2 + var4[5]) * 0.65 + math.sin(var3[6] * arg2 + var4[6]) * 0.25), var1.Z + var2.Z * (math.sin(var3[3] * arg2 + var4[3]) * 0.82 + math.sin(var3[4] * arg2 + var4[4]) * 0.18))
	local var8 = var6
	return arg1.from:Lerp(var7, var8)
end

tbl1.AddDodge = function(arg1, arg2, arg3, arg4)
	table.insert(arg1.dodges, { t0 = arg2, dir = arg3, amp = arg4 })
end

tbl1.Pos = function(arg1, arg2)
	local var1 = arg1:Base((math.max(0, arg2 - arg1.startAt)))
	for k1, v1 in ipairs(arg1.dodges) do
		local var2 = arg2 - v1.t0
		if 0 >= var2 or var2 >= 4 then
			continue
		end

		var1 = var1 + v1.dir * v1.amp * (1 - math.exp(-var2 / 0.09)) * math.exp(-var2 / 1.4)
	end

	return (Vector3.new(math.clamp(var1.X, arg1.min.X - 2, arg1.max.X + 2), math.clamp(var1.Y, arg1.min.Y - 1, arg1.max.Y + 1), (math.clamp(var1.Z, arg1.min.Z - 2, arg1.max.Z + 2))))
end

tbl1.Vel = function(arg1, arg2)
	return (arg1:Pos(arg2 + 0.05) - arg1:Pos(arg2 - 0.05)) / 0.1
end

return tbl1

--- ReplicatedStorage.Meeting.ShopConfig [ModuleScript]
