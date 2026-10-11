-- y u r i

local var1 = require(script.Parent.Config)
local var2 = var1.COLS
local var3 = var1.CELL
local tbl1 = {
	key = function(arg1, arg2)
		return arg1 .. "," .. arg2
	end,
	unkey = function(arg1)
		local var1, var2 = string.match(arg1, "(-?%d+),(-?%d+)")
		return tonumber(var1), (tonumber(var2))
	end,
	floorY = function(arg1)
		return var1.FLOOR_TOP + (arg1 - 1) * var1.FLOOR_RISE
	end,
	floorZ = function(_)
		return 0
	end,
}

local var4 = var1.ROWS
tbl1.cellLocal = function(arg1, arg2, arg3)
	return (Vector3.new((arg2 - (var2 - 1) / 2) * var3, tbl1.floorY(arg1), (arg3 - (var4 - 1) / 2) * var3))
end

tbl1.entryLocal = function(_)
	return (Vector3.new((var1.ENTRY_COL - (var2 - 1) / 2) * var3, tbl1.floorY(1), -var4 * var3 / 2 - 3))
end

tbl1.spawnLocal = function()
	return tbl1.entryLocal(1) + Vector3.new(0, 0, -12)
end

tbl1.localToCell = function(_, arg2)
	return arg2.X / var3 + (var2 - 1) / 2, arg2.Z / var3 + (var4 - 1) / 2
end

tbl1.level = function(arg1)
	local var2 = var1.WidthLevels[arg1.w or 1]
	return var2 or var1.WidthLevels[1]
end

tbl1.widthRange = function(arg1)
	local var1 = tbl1.level(arg1)
	return var1.min, var1.max
end

tbl1.inBounds = function(arg1, arg2, arg3)
	local var1 = tbl1.level(arg1)
	local bool2 = false
	if var1.min <= arg2 then
		bool2 = false
		if arg2 <= var1.max then
			bool2 = false
			if 0 <= arg3 then
				bool2 = arg3 < var1.rows
			end
		end
	end

	return bool2
end

tbl1.DIRS = { { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }
tbl1.rotSide = function(arg1, arg2)
	return (arg1 - 1 - (arg2 or 0)) % 4 + 1
end

local var5 = var1.Items
tbl1.piece = function(arg1, arg2)
	local var1 = arg1.tiles[arg2]
	return var1 and var5[var1] or nil, var1
end

tbl1.rotOf = function(arg1, arg2)
	return arg1.trot and arg1.trot[arg2] or 0
end

tbl1.sideWall = function(arg1, arg2, arg3, arg4)
	local var1 = tbl1.key(arg2, arg3)
	local var3 = tbl1.piece(arg1, var1)
	if not var3 or (not var3.edges) then
		return false, false
	end

	local var4 = tbl1.rotOf(arg1, var1)
	for k1, v1 in ipairs(var3.edges) do
		if tbl1.rotSide(v1, var4) ~= arg4 then
			continue
		end

		return true, var3.wood == true
	end

	return false, false
end

tbl1.tileCost = function(arg1, arg2, arg3, arg4, arg5, arg6)
	if not tbl1.inBounds(arg1, arg2, arg3) then
		return nil
	end

	local var3 = tbl1.key(arg2, arg3)
	if var3 == arg5 then
		return nil
	end

	if var3 == arg6 then
		return var1.GAP_COST
	end

	local var5 = tbl1.piece(arg1, var3)
	if not var5 then
		return var1.GAP_COST
	end

	if var5.kind == "block" then
		if arg4 and var5.wood then
			return var1.GAP_COST
		end

		return nil
	end

	return 1
end

local tbl2 = { 3, 4, 1, 2 }
tbl1.edgeOpen = function(arg1, arg2, arg3, arg4, arg5)
	local var1 = tbl1.DIRS[arg4]
	local var2, var3 = tbl1.sideWall(arg1, arg2, arg3, arg4)
	local var4, var5 = tbl1.sideWall(arg1, arg2 + var1[1], arg3 + var1[2], tbl2[arg4])
	if var2 and (not arg5 or (not var3)) then
		return false
	end

	if var4 and (not arg5 or (not var5)) then
		return false
	end

	return true
end

tbl1.isWalkable = function(arg1, arg2, arg3)
	local var2 = arg2
	local var3 = arg3
	local var4 = tbl1.piece(arg1, tbl1.key(var2, var3))
	local var5 = tbl1.inBounds(arg1, arg2, arg3)
	return var5 and var1.IsWalkPiece(var4)
end

tbl1.findSpecial = function(arg1, arg2)
	for k1, v1 in pairs(arg1.tiles) do
		if v1 ~= arg2 then
			continue
		end

		local var1 = k1
		return tbl1.unkey(var1)
	end

	return nil, nil
end

tbl1.floorStart = function(arg1, arg2)
	if arg2 == 1 then
		return var1.ENTRY_COL, 0
	end

	local var2 = arg1.floors[arg2 - 1]
	local str1 = "Stairs"
	return tbl1.findSpecial(var2, str1)
end

tbl1.floorTarget = function(arg1, arg2)
	if arg2 == (#arg1.floors) then
		local var2 = arg1.floors[arg2]
		local str2 = "Crystal"
		return tbl1.findSpecial(var2, str2)
	end

	local var3 = arg1.floors[arg2]
	local str3 = "Stairs"
	return tbl1.findSpecial(var3, str3)
end

tbl1.isFixedCell = function(arg1, arg2, arg3, arg4)
	local var3, var4 = tbl1.floorStart(arg1, arg2)
	local bool1 = false
	if var3 == arg3 then
		bool1 = var4 == arg4
	end

	return bool1
end

tbl1.dijkstra = function(arg1, arg2, arg3, arg4, arg5, arg6)
	local tbl2 = {}
	local tbl3 = {}
	if not tbl1.tileCost(arg1, arg2, arg3, arg4, arg5, arg6) then
		return tbl2, tbl3
	end

	local var1 = tbl1.key(arg2, arg3)
	tbl2[var1] = 0
	tbl3[var1] = false
	local tbl4 = { { arg2, arg3, 0 } }
	local tbl5 = {}
	while 0 < (#tbl4) do
		local num1 = 1
		local var2 = tbl4[1][3]
		for i1 = 2, #tbl4 do
			if tbl4[i1][3] >= var2 then
				continue
			end

			num1 = i1
			local var3 = tbl4[i1][3]
		end

		local var4 = table.remove(tbl4, num1)
		local var5 = var4[1]
		local var6 = var4[2]
		local var7 = tbl1.key(var5, var6)
		if tbl5[var7] then
			continue
		end

		tbl5[var7] = true
		for k1, v1 in ipairs(tbl1.DIRS) do
			local var8 = var5 + v1[1]
			local var9 = var6 + v1[2]
			local var10 = tbl1.key(var8, var9)
			if tbl5[var10] then
				continue
			end

			local var11 = tbl1.tileCost(arg1, var8, var9, arg4, arg5, arg6)
			if not var11 then
				continue
			end

			if not tbl1.edgeOpen(arg1, var5, var6, k1, arg4) then
				continue
			end

			local var13 = var4[3] + var11
			if tbl2[var10] == nil or var13 < tbl2[var10] then
				tbl2[var10] = var13
				tbl3[var10] = { var5, var6 }
				table.insert(tbl4, { var8, var9, var13 })
			end
		end
	end

	return tbl2, tbl3
end

local function trace(arg1, arg2, arg3)
	if arg1[tbl1.key(arg2, arg3)] == nil then
		return nil
	end

	local tbl2 = {}
	local tbl3 = { arg2, arg3 }
	while tbl3 do
		table.insert(tbl2, 1, tbl3)
		local var1 = arg1[tbl1.key(tbl3[1], tbl3[2])]
		tbl3 = var1
	end

	return tbl2
end

tbl1.floorPath = function(arg1, arg2, arg3, arg4, arg5)
	local var5, var6 = tbl1.floorStart(arg1, arg2)
	local var7, var8 = tbl1.floorTarget(arg1, arg2)
	local var9 = arg1.floors[arg2]
	if not var5 or (not var7) then
		return nil
	end

	local var10, var11 = tbl1.dijkstra(var9, var5, var6, arg3, arg4, arg5)
	return (trace(var11, var7, var8))
end

tbl1.floorGreedyPath = function(arg1, arg2)
	local var5, var6 = tbl1.floorStart(arg1, arg2)
	local var7, var8 = tbl1.floorTarget(arg1, arg2)
	local var9 = arg1.floors[arg2]
	if not var5 or (not var7) then
		return nil, nil
	end

	local var10, var11 = tbl1.dijkstra(var9, var5, var6)
	local var12, var13 = tbl1.dijkstra(var9, var7, var8)
	local var14 = nil
	local var15 = nil
	for k1, v1 in pairs(var9.tiles) do
		if v1 ~= "TreasureRoom" then
			continue
		end

		if not var10[k1] then
			continue
		end

		if not var12[k1] then
			continue
		end

		local var17 = var10[k1] + var12[k1]
		if not var15 or var17 < var15 then
			var14 = k1
		end

		local var18 = var17
	end

	if not var14 then
		return trace(var11, var7, var8), nil
	end

	local var19, var20 = tbl1.unkey(var14)
	local var22 = trace(var11, var19, var20)
	if not var22 then
		return nil, nil
	end

	local var23 = table.clone(var22)
	local var24 = var13[var14]
	while var24 do
		table.insert(var23, var24)
		local var25 = var13[tbl1.key(var24[1], var24[2])]
	end

	return var23, #var22
end

tbl1.findPath = function(_, _, _, _)
	return nil
end

tbl1.buildFullPath = function(arg1, arg2)
	local tbl2 = {}
	table.insert(tbl2, { pos = tbl1.spawnLocal(), f = 1, kind = "spawn" })
	table.insert(tbl2, { pos = tbl1.entryLocal(1), f = 1, kind = "entry" })
	local var2 = #arg1.floors
	for i1 = 1, var2 do
		local var7 = nil
		local var8 = nil
		if arg2 == "greedy" then
			local var9, var10 = tbl1.floorGreedyPath(arg1, i1)
			var7 = var9
			var8 = var10
		else
			var7 = tbl1.floorPath(arg1, i1, arg2 == "rogue")
		end

		if not var7 then
			return nil
		end

		local var11 = arg1.floors[i1]
		for k1, v1 in ipairs(var7) do
			local var12 = tbl1.key(v1[1], v1[2])
			local var13 = tbl1.piece(var11, var12)
			local tbl3 = {
				pos = tbl1.cellLocal(i1, v1[1], v1[2]) + Vector3.new(0, var13 and var1.PIECE_H or 0, 0),
				kind = "cell",
			}

			tbl3.f = i1
			tbl3.c = v1[1]
			tbl3.r = v1[2]
			tbl3.key = var12
			local bool2 = true
			if k1 ~= var8 then
				bool2 = nil
			end

			tbl3.loot = bool2
			bool2 = true
			if var13 ~= nil then
				bool2 = nil
			end

			tbl3.ground = bool2
			table.insert(tbl2, tbl3)
		end

		local var14
		local var15
		if i1 < var2 then
			var14 = {
				pos = tbl1.cellLocal(i1 + 1, var7[#var7][1], var7[#var7][2]) + Vector3.new(0, 0.2, 0),
				kind = "climb",
			}

			var14.f = i1 + 1
			var15 = tbl2
			table.insert(var15, var14)
		else
			tbl2[#tbl2].kind = "core"
		end
	end

	local tbl4 = { 0 }
	for i2 = 2, #tbl2 do
		local var16 = tbl4[i2 - 1] + (tbl2[i2].pos - tbl2[i2 - 1].pos).Magnitude
		tbl4[i2] = var16
	end

	return tbl2, tbl4, tbl4[#tbl4]
end

tbl1.layoutOk = function(arg1)
	local var1 = #arg1.floors
	if tbl1.findSpecial(arg1.floors[var1], "Crystal") then
		return tbl1.buildFullPath(arg1, "main") ~= nil
	end

	for i1 = 1, var1 - 1 do
		if tbl1.floorPath(arg1, i1) then
			continue
		end

		return false
	end

	return true
end

tbl1.WANDER_WEIGHTS = { TreasureRoom = 10, trap = 2, deadEnd = 3, other = 0.25 }
local function openBuiltNeighbours(arg1, arg2, arg3)
	local num1 = 0
	for k1, v1 in ipairs(tbl1.DIRS) do
		local var1 = arg2 + v1[1]
		local var2 = arg3 + v1[2]
		local var3 = tbl1.piece(arg1, tbl1.key(var1, var2))
		if not var3 then
			continue
		end

		if var3.kind == "block" then
			continue
		end

		if not tbl1.edgeOpen(arg1, arg2, arg3, k1) then
			continue
		end

		num1 = num1 + 1
	end

	return num1
end

tbl1.floorWanderPath = function(arg1, arg2, arg3)
	local var6, var7 = tbl1.floorStart(arg1, arg2)
	local var8, var9 = tbl1.floorTarget(arg1, arg2)
	local var10 = arg1.floors[arg2]
	if not var6 or (not var8) then
		return nil
	end

	local var11, var12 = tbl1.dijkstra(var10, var6, var7)
	local var14 = trace(var12, var8, var9)
	if not var14 then
		return nil
	end

	local tbl2 = {}
	for k1, v1 in ipairs(var14) do
		local var15 = v1[2]
		local var16 = tbl1.key(v1[1], var15)
		tbl2[var16] = true
	end

	local tbl3 = {}
	local tbl4 = {}
	local num1 = 1
	for k2, v2 in ipairs(var14) do
		local var17 = tbl1.key(v2[1], v2[2])
		local var18 = var10.tiles[var17]
		if not var18 then
			continue
		end

		var18 = tbl3[var17]
		if var18 then
			continue
		end

		tbl3[var17] = true
		table.insert(tbl4, v2)
	end

	while tbl4[num1] do
		local var19 = tbl4[num1][1]
		local var20 = tbl4[num1][2]
		for k3, v3 in ipairs(tbl1.DIRS) do
			local var21 = var19 + v3[1]
			local var22 = var20 + v3[2]
			local var23 = tbl1.key(var21, var22)
			local var24 = tbl1.piece(var10, var23)
			if tbl3[var23] or (not var24) then
				continue
			end

			if var24.kind == "block" then
				continue
			end

			if not tbl1.inBounds(var10, var21, var22) then
				continue
			end

			if not tbl1.edgeOpen(var10, var19, var20, k3) then
				continue
			end

			tbl3[var23] = true
			table.insert(tbl4, { var21, var22 })
		end

		num1 = num1 + 1
	end

	local var25 = tbl1.WANDER_WEIGHTS
	local tbl5 = {}
	for k4, v4 in pairs(var10.tiles) do
		local var26 = var5[v4]
		if not var26 then
			continue
		end

		if var26.kind ~= "floor" then
			continue
		end

		if not tbl3[k4] then
			continue
		end

		if not var11[k4] then
			continue
		end

		if tbl2[k4] then
			continue
		end

		local var27, var28 = tbl1.unkey(k4)
		local var30 = tbl1.objectAt(var10, var27, var28)
		local var31 = nil
		if v4 == "TreasureRoom" then
			var31 = var25.TreasureRoom
		else
			if var30 and (var5[var30.id] and var5[var30.id].kind == "trap") then
				var31 = var25.trap
			else
				var31 = if openBuiltNeighbours(var10, var27, var28) <= 1 then var25.deadEnd else var25.other
			end
		end

		table.insert(tbl5, { k = k4, c = var27, r = var28, w = var31 })
	end

	if #tbl5 == 0 then
		return var14
	end

	table.sort(tbl5, function(arg1, arg2)
		return arg1.k < arg2.k
	end)

	local num2 = 1
	local num3 = 3
	local tbl6 = {}
	for i1 = 1, math.min(#tbl5, arg3:NextInteger(num2, num3)) do
		num2 = 0
		for k5, v5 in ipairs(tbl5) do
			local var32 = v5.w
			num2 = num2 + var32
		end

		num3 = arg3:NextNumber() * num2
		local num4 = 0
		for k6, v6 in ipairs(tbl5) do
			num4 = num4 + v6.w
			if num3 > num4 then
				continue
			end

			local var33 = tbl5
			local var34 = k6
			table.insert(tbl6, table.remove(var33, var34))
			break
		end
	end

	local function build(arg1)
		local tbl2 = {}
		local function append(arg1)
			for k1, v1 in ipairs(arg1) do
				local var2 = tbl2[#tbl2]
				if not var2 or (var2[1] ~= v1[1] or var2[2] ~= v1[2]) then
					table.insert(tbl2, v1)
				end
			end
		end

		local var1 = table.clone(arg1)
		local var2 = var11
		local var3 = var12
		while 0 < (#var1) do
			local var4 = nil
			local var5 = nil
			for k1, v1 in ipairs(var1) do
				local var6 = var2[v1.k]
				if not var6 then
					continue
				end

				if not var5 or var6 < var5 then
					var4 = k1
					var5 = var6
				end
			end

			if not var4 then
				break
			end

			local var7 = table.remove(var1, var4)
			local var13 = trace(var3, var7.c, var7.r)
			if not var13 then
				break
			end

			append(var13)
			local var14 = var7.c
			local var15, var16 = tbl1.dijkstra(var10, var14, var7.r)
			local var17 = var15
			var3 = var16
		end

		local var19 = trace(var3, var8, var9)
		if not var19 then
			return nil
		end

		append(var19)
		return tbl2
	end

	while true do
		if 0 >= (#tbl6) then
			break
		end

		local var36 = build(tbl6)
		if var36 and #var36 <= #var14 * 3 + 14 then
			return var36
		end

		table.remove(tbl6)
	end

	return var14
end

tbl1.buildWanderPath = function(arg1, arg2)
	local tbl2 = {}
	table.insert(tbl2, { pos = tbl1.spawnLocal(), f = 1, kind = "spawn" })
	table.insert(tbl2, { pos = tbl1.entryLocal(1), f = 1, kind = "entry" })
	local var2 = #arg1.floors
	for i1 = 1, var2 do
		local var3 = tbl1.floorWanderPath(arg1, i1, arg2)
		var3 = var3 or tbl1.floorPath(arg1, i1)
		if not var3 then
			return nil
		end

		local var4 = arg1.floors[i1]
		local tbl3 = {}
		for k1, v1 in ipairs(var3) do
			local var5 = tbl1.key(v1[1], v1[2])
			local var6 = tbl1.piece(var4, var5)
			local bool2 = false
			if var4.tiles[var5] == "TreasureRoom" then
				bool2 = not tbl3[var5]
			end

			if bool2 then
				tbl3[var5] = true
			end

			local tbl4 = {
				pos = tbl1.cellLocal(i1, v1[1], v1[2]) + Vector3.new(0, var6 and var1.PIECE_H or 0, 0),
				kind = "cell",
			}

			tbl4.f = i1
			tbl4.c = v1[1]
			tbl4.r = v1[2]
			tbl4.key = var5
			tbl4.loot = bool2 or nil
			local bool4 = true
			if var6 ~= nil then
				bool4 = nil
			end

			tbl4.ground = bool4
			table.insert(tbl2, tbl4)
		end

		local var7
		if i1 < var2 then
			var7 = {
				pos = tbl1.cellLocal(i1 + 1, var3[#var3][1], var3[#var3][2]) + Vector3.new(0, 0.2, 0),
				kind = "climb",
			}

			var7.f = i1 + 1
			table.insert(tbl2, var7)
		else
			tbl2[#tbl2].kind = "core"
		end
	end

	local tbl5 = { 0 }
	for i2 = 2, #tbl2 do
		local var8 = tbl5[i2 - 1] + (tbl2[i2].pos - tbl2[i2 - 1].pos).Magnitude
		tbl5[i2] = var8
	end

	return tbl2, tbl5, tbl5[#tbl5]
end

tbl1.EXPLORE_WEIGHTS = { TreasureRoom = 5, room = 2.2, trap = 1.6, straight = 1.35, cover = 0.7, onPath = 0.25 }
tbl1.EXPLORE_MAX_STEPS = 140
local function explorable(arg1, arg2, arg3, arg4)
	local tbl2 = {}
	local tbl3 = {}
	local var1 = tbl1.key(arg2, arg3)
	local num1 = 1
	local var2
	if not tbl2[var1] then
		tbl2[var1] = true
		var2 = arg2
		table.insert(tbl3, { var2, arg3 })
	end

	for k1, v1 in ipairs(arg4) do
		local var3 = v1[1]
		local var4 = v1[2]
		local var5 = tbl1.key(var3, var4)
		if tbl2[var5] then
			continue
		end

		tbl2[var5] = true
		table.insert(tbl3, { var3, var4 })
	end

	while tbl3[num1] do
		var1 = tbl3[num1][1]
		local var6 = tbl3[num1][2]
		for k2, v2 in ipairs(tbl1.DIRS) do
			local var7 = var1 + v2[1]
			local var8 = var6 + v2[2]
			local var9 = var7
			local var10 = var8
			local var11 = tbl1.piece(arg1, tbl1.key(var9, var10))
			if not var11 then
				continue
			end

			if var11.kind == "block" then
				continue
			end

			if not tbl1.inBounds(arg1, var7, var8) then
				continue
			end

			if not tbl1.edgeOpen(arg1, var1, var6, k2) then
				continue
			end

			local var12 = tbl1.key(var7, var8)
			if tbl2[var12] then
				continue
			end

			tbl2[var12] = true
			table.insert(tbl3, { var7, var8 })
		end

		num1 = num1 + 1
	end

	var1 = 0
	for k3 in pairs(tbl2) do
		var1 = var1 + 1
	end

	return tbl2, var1
end

tbl1.floorExplorePath = function(arg1, arg2, arg3, arg4, arg5)
	local var6, var7 = tbl1.floorStart(arg1, arg2)
	local var8, var9 = tbl1.floorTarget(arg1, arg2)
	local var10 = arg1.floors[arg2]
	if not var6 or (not var8) then
		return nil
	end

	local var11, var12 = tbl1.dijkstra(var10, var6, var7)
	local var14 = trace(var12, var8, var9)
	if not var14 then
		return nil
	end

	local var15, var16 = explorable(var10, var6, var7, var14)
	local var17 = tbl1.key(var8, var9)
	local tbl2 = {}
	for k1, v1 in ipairs(var14) do
		local var18 = tbl1.key(v1[1], v1[2])
		tbl2[var18] = true
	end

	local tbl3 = {}
	local num1 = 0
	for k2 in pairs(var15) do
		local var19, var20 = tbl1.unkey(k2)
		local num2 = 0
		for k3, v2 in ipairs(tbl1.DIRS) do
			if not var15[tbl1.key(var19 + v2[1], var20 + v2[2])] then
				continue
			end

			if not tbl1.edgeOpen(var10, var19, var20, k3) then
				continue
			end

			num2 = num2 + 1
		end

		if 3 > num2 then
			continue
		end

		tbl3[k2] = true
		num1 = num1 + 1
	end

	if 0 < var16 and 0.45 <= num1 / var16 then
		return var14
	end

	local var21 = tbl1.dijkstra(var10, var8, var9)
	local tbl4 = {}
	for k4, v3 in ipairs(tbl1.DIRS) do
		local var22 = var8 - v3[1]
		local var23 = var9 - v3[2]
		if not var15[tbl1.key(var22, var23)] then
			continue
		end

		if not tbl1.edgeOpen(var10, var22, var23, k4) then
			continue
		end

		local var24 = tbl1.key(var22, var23)
		tbl4[var24] = true
	end

	local var25 = math.clamp(math.floor(var16 * 2 * arg4), 4, (math.min(tbl1.EXPLORE_MAX_STEPS, (math.max(10, #var14 * 2 + 4)))))
	local var26 = tbl1.key(var6, var7)
	local tbl5 = { [var26] = true }
	local var27 = tbl1.EXPLORE_WEIGHTS
	local tbl6 = { { var6, var7 } }
	var26 = { { var6, var7, 0 } }
	local num3 = 0
	while num3 < var25 and 0 < (#var26) do
		local var28 = var26[#var26]
		local var29 = var28[1]
		local var30 = var28[2]
		local var31 = var28[3]
		local tbl7 = {}
		local num4 = 0
		for k5, v4 in ipairs(tbl1.DIRS) do
			local var32 = var29 + v4[1]
			local var33 = var30 + v4[2]
			local var34 = tbl1.key(var32, var33)
			if not var15[var34] then
				continue
			end

			if tbl5[var34] or var34 == var17 then
				continue
			end

			if not tbl1.edgeOpen(var10, var29, var30, k5) then
				continue
			end

			if not tbl1.tileCost(var10, var32, var33) then
				continue
			end

			local var35 = var10.tiles[var34]
			local var36 = var35
			var36 = var36 and var5[var35]
			local num5 = 1
			if var35 == "TreasureRoom" then
				num5 = num5 * var27.TreasureRoom
			else
				if var36 and (var36.sub == "Rooms" or (var36.buff or var36.room)) then
					num5 = num5 * var27.room
				end
			end

			local var38 = tbl1.objectAt(var10, var32, var33)
			if var38 then
				if var5[var38.id] and var5[var38.id].kind == "trap" then
					num5 = num5 * var27.trap
				end
			end

			if k5 == var31 then
				num5 = num5 * var27.straight
			end

			local var40 = tbl1.key(var29, var30)
			if tbl3[var34] then
				local var41 = var21[var34]
				local var42 = var21[var40]
				if tbl3[var40] and (var21 and (var41 and (var42 and var42 <= var41))) then
					num5 = num5 * 0.12
				end
			end

			if tbl4[var34] then
				num5 = num5 * 0.08
			else
				if tbl2[var34] and (not tbl3[var34]) then
					num5 = num5 * var27.onPath
				end
			end

			num5 = arg5 and (arg5[var34] and num5 / (1 + arg5[var34] * var27.cover))
			local var43 = var32
			local tbl8 = { var43, var33, k5, num5 }
			table.insert(tbl7, tbl8)
			num4 = num4 + num5
		end

		local var44
		local var45
		local var46
		local var47
		if 0 < (#tbl7) then
			local var48 = arg3:NextNumber() * num4
			local var49 = tbl7[#tbl7]
			for k6, v5 in ipairs(tbl7) do
				var48 = var48 - v5[4]
				if var48 > 0 then
					continue
				end

				var49 = v5
				break
			end

			local var50 = tbl1.key(var49[1], var49[2])
			tbl5[var50] = true
			if arg5 then
				var46 = (arg5[var50] or 0) + 1
				arg5[var50] = var46
			end

			table.insert(var26, { var49[1], var49[2], var49[3] })
			local var51 = var49[2]
			var44 = tbl6
			table.insert(var44, { var49[1], var51 })
			var46 = tbl4[var50]
			if var46 then
				break
			end
		else
			local var52, var53 = tbl1.dijkstra(var10, var29, var30)
			local var54 = nil
			var46 = nil
			for k7 in pairs(tbl5) do
				local var55 = var52[k7]
				if not var55 then
					continue
				end

				if not var46 or var55 < var46 then
					local var56, var57 = tbl1.unkey(k7)
					for k8, v6 in ipairs(tbl1.DIRS) do
						local var58 = tbl1.key(var56 + v6[1], var57 + v6[2])
						if not var15[var58] then
							continue
						end

						if tbl5[var58] or var58 == var17 then
							continue
						end

						if not tbl1.edgeOpen(var10, var56, var57, k8) then
							continue
						end

						var54 = { var56, var57 }
						var46 = var55
						break
					end
				end
			end

			if not var54 then
				break
			end

			var44 = trace(var53, var54[1], var54[2])
			if not var44 then
				break
			end

			if var25 < var46 + num3 then
				break
			end

			for i1 = 2, #var44 do
				table.insert(tbl6, var44[i1])
			end

			num3 = num3 + math.max(0, #var44 - 2)
		end

		local tbl9 = { { var54[1], var54[2], 0 } }
		num3 = num3 + 1
	end

	local var59 = tbl6[#tbl6]
	local var60, var61 = tbl1.dijkstra(var10, var59[1], var59[2])
	local var63 = trace(var61, var8, var9)
	if not var63 then
		return var14
	end

	for i2 = 2, #var63 do
		table.insert(tbl6, var63[i2])
	end

	return tbl6
end

tbl1.buildExplorePath = function(arg1, arg2, arg3, arg4)
	local tbl2 = {}
	table.insert(tbl2, { pos = tbl1.spawnLocal(), f = 1, kind = "spawn" })
	table.insert(tbl2, { pos = tbl1.entryLocal(1), f = 1, kind = "entry" })
	local var2 = #arg1.floors
	local tbl3 = {}
	for i1 = 1, var2 do
		local var3 = arg4[i1]
		arg4[i1] = var3 or {}
		var3 = tbl1.floorExplorePath(arg1, i1, arg2, arg3, arg4[i1])
		var3 = var3 or tbl1.floorPath(arg1, i1)
		if not var3 then
			return nil
		end

		local var4 = arg1.floors[i1]
		local tbl4 = {}
		for k1, v1 in ipairs(var3) do
			local var5 = tbl1.key(v1[1], v1[2])
			local var6 = tbl1.piece(var4, var5)
			local bool2 = false
			if var4.tiles[var5] == "TreasureRoom" then
				bool2 = not tbl4[var5]
			end

			if bool2 then
				tbl4[var5] = true
			end

			table.insert(tbl3, var5)
			local tbl5 = {
				pos = tbl1.cellLocal(i1, v1[1], v1[2]) + Vector3.new(0, var6 and var1.PIECE_H or 0, 0),
				kind = "cell",
			}

			tbl5.f = i1
			tbl5.c = v1[1]
			tbl5.r = v1[2]
			tbl5.key = var5
			tbl5.loot = bool2 or nil
			local bool4 = true
			if var6 ~= nil then
				bool4 = nil
			end

			tbl5.ground = bool4
			table.insert(tbl2, tbl5)
		end

		local var7
		if i1 < var2 then
			var7 = {
				pos = tbl1.cellLocal(i1 + 1, var3[#var3][1], var3[#var3][2]) + Vector3.new(0, 0.2, 0),
				kind = "climb",
			}

			var7.f = i1 + 1
			table.insert(tbl2, var7)
		else
			tbl2[#tbl2].kind = "core"
		end
	end

	local tbl6 = { 0 }
	for i2 = 2, #tbl2 do
		local var8 = tbl6[i2 - 1] + (tbl2[i2].pos - tbl2[i2 - 1].pos).Magnitude
		tbl6[i2] = var8
	end

	local var9 = tbl3
	local str1 = "|"
	return tbl2, tbl6, tbl6[#tbl6], table.concat(var9, str1)
end

tbl1.samplePath = function(arg1, arg2, arg3, arg4)
	local var2 = arg4 or 1
	if var2 < 1 then
		var2 = 1
	end

	while var2 < #arg1 - 1 and arg2[var2 + 1] < arg3 do
		var2 = var2 + 1
	end

	while 1 < var2 and arg3 < arg2[var2] do
		var2 = var2 - 1
	end

	local var4 = arg2[math.min(var2 + 1, #arg1)] - arg2[var2]
	local var5 = arg1[var2]
	local var6 = arg1[math.min(var2 + 1, #arg1)]
	if 0 < var4 then
		local var7 = math.clamp((arg3 - arg2[var2]) / var4, 0, 1)
		var7 = var7 or 0
	end

	local var8 = var6.pos - var5.pos
	local num1 = 0
	return var5.pos:Lerp(var6.pos, num1), var2, if 0 < var8.Magnitude then var8.Unit else Vector3.new(0, 0, 1)
end

tbl1.plotCFrame = function(arg1)
	local var5 = math.ceil(var1.PLOT_COUNT / 2)
	local var6 = if arg1 <= var5 then 1 else -1
	local var7 = Vector3.new(((arg1 - 1) % var5 - (var5 - 1) / 2) * var1.PLOT_SPACING_X, 0, var6 * (var1.ROAD_HALF + 10 + var4 * var3 / 2 + 4))
	local var8 = var7
	local var9 = var7 - Vector3.new(0, 0, var6)
	return CFrame.lookAt(var8, var9)
end

tbl1.footprintSize = function(arg1, arg2)
	local var1 = arg1
	var1 = var1 and arg1.footprint
	local var4 = var1 and var1[1] or 1
	local var5 = var1 and var1[2] or 1
	if (arg2 or 0) % 2 == 1 then
		return var5, var4
	end

	return var4, var5
end

tbl1.objectAt = function(arg1, arg2, arg3, arg4)
	local var1 = tbl1.key(arg2, arg3)
	if arg1.objs[var1] and var1 ~= arg4 then
		return arg1.objs[var1], var1
	end

	for k1, v1 in pairs(arg1.objs) do
		if k1 == arg4 then
			continue
		end

		local var2, var3 = tbl1.unkey(k1)
		if var2 > arg2 then
			continue
		end

		local var4, var6 = tbl1.footprintSize(var5[v1.id], v1.rot)
		if arg2 >= var2 + var4 or var3 > arg3 then
			continue
		end

		if arg3 >= var3 + var6 then
			continue
		end

		return v1, k1
	end

	return nil, nil
end

tbl1.objectCenter = function(arg1, arg2, arg3, arg4, arg5)
	local var1, var2 = tbl1.footprintSize(arg4, arg5)
	local var3 = arg1
	local var4 = arg2 + (var1 - 1) / 2
	local var5 = arg3 + (var2 - 1) / 2
	return tbl1.cellLocal(var3, var4, var5)
end

tbl1.footprintCells = function(arg1, arg2, arg3, arg4, arg5, arg6)
	local var1, var2 = tbl1.footprintSize(arg2, arg5)
	local tbl2 = {}
	for i1 = 0, var1 - 1 do
		for i2 = 0, var2 - 1 do
			local var3 = arg3 + i1
			local var4 = arg4 + i2
			local var8 = tbl1.inBounds(arg1, var3, var4)
			if var8 then
				local var10 = var5[arg1.tiles[tbl1.key(var3, var4)]]
				local bool3 = false
				if var10 ~= nil then
					bool3 = false
					if var10.kind == "floor" then
						bool3 = not tbl1.objectAt(arg1, var3, var4, arg6)
					end
				end

				var8 = bool3
				if var8 and (i1 < var1 - 1 and (not tbl1.edgeOpen(arg1, var3, var4, 2)) or i2 < var2 - 1 and (not tbl1.edgeOpen(arg1, var3, var4, 3))) then
					var8 = false
				end
			end

			table.insert(tbl2, { c = var3, r = var4, ok = var8 })
		end
	end

	return tbl2
end

tbl1.canPlaceObject = function(arg1, arg2, arg3, arg4, arg5, arg6)
	local var1, var2 = tbl1.footprintSize(arg2, arg5)
	for i1 = 0, var1 - 1 do
		for i2 = 0, var2 - 1 do
			local var3 = arg3 + i1
			local var4 = arg4 + i2
			if not tbl1.inBounds(arg1, var3, var4) then
				return false, "The whole " .. var1 .. " x " .. var2 .. " footprint must fit inside your dungeon."
			end

			local var7 = var5[arg1.tiles[tbl1.key(var3, var4)]]
			if var7 then
				if var7.kind ~= "floor" then
					return false, 1 < var1 * var2 and "Needs a " .. var1 .. " x " .. var2 .. " area of dungeon floor." or "Place a corridor or room here first!"
				end
			end

			if var7.noObjects then
				return false, "Shrines power up the tiles around them. Nothing can be placed on a shrine."
			end

			if tbl1.objectAt(arg1, var3, var4, arg6) then
				return false, "That space is already occupied."
			end

			if i1 < var1 - 1 and (not tbl1.edgeOpen(arg1, var3, var4, 2)) or i2 < var2 - 1 and (not tbl1.edgeOpen(arg1, var3, var4, 3)) then
				return false, "Large units need open floor with no walls through their footprint."
			end
		end
	end

	return true
end

local tbl3 = { 1, 4, 3, 2 }
tbl1.laneDir = function(arg1)
	return tbl3[(arg1 or 0) % 4 + 1]
end

tbl1.trapLane = function(arg1, arg2, arg3, arg4, arg5)
	local var1 = tbl1.laneDir(arg4)
	local var2 = tbl1.DIRS[var1]
	local tbl2 = { { arg2, arg3 } }
	local var3 = arg2
	local var4 = arg3
	for i1 = 1, arg5 or 0 do
		if not arg1 then
			break
		end

		local var5 = var3 + var2[1]
		local var6 = var4 + var2[2]
		if tbl1.tileCost(arg1, var5, var6) == nil then
			break
		end

		if not tbl1.edgeOpen(arg1, var3, var4, var1) then
			break
		end

		var3 = var5
		var4 = var6
		table.insert(tbl2, { var3, var4 })
	end

	return tbl2, var1
end

return tbl1

