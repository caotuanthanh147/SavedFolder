-- y u r i

local tbl1 = {}
tbl1[2] = { souls = 2500, robux = 99 }
tbl1[3] = { souls = 10000, robux = 249 }
local tbl2 = { Tiers = tbl1 }
local tbl3 = {}
tbl3[2] = { key = "BuildingDoubleRoll", id = 1998500777 }
tbl3[3] = { key = "BuildingTripleRoll", id = 1998116721 }
tbl1 = { Buildings = tbl3 }
tbl3 = {}
tbl3[2] = { key = "UnitDoubleRoll", id = 1999154701 }
tbl3[3] = { key = "UnitTripleRoll", id = 1998518729 }
tbl1.Monsters = tbl3
tbl2.Passes = tbl1
tbl2.Tier = function(arg1, arg2)
	local var1 = type(arg1.rollUpgrades) == "table" and arg1.rollUpgrades[arg2] or 1
	if type(var1) == "number" then
		if var1 ~= 2 then
			local var2 = var1 == 3 and var1 or 1
		end

		local var3 = var1
		var3 = var3 or 1
	end

	local var4 = tbl2.Passes
	local var5 = var4[arg2]
	local num1 = 1
	for k1, v1 in pairs(var5 or {}) do
		if not arg1.passes then
			goto L1
		end

		if arg1.passes[v1.key] ~= true then
			goto L1
		end

		num1 = math.max(num1, k1)
	::L1:: end

	return num1
end

return tbl2

