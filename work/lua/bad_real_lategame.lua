-- y u r i

return { Apply = function(arg1)
	local tbl1 = { [4000] = 8000, [12000] = 36000, [35000] = 140000, [90000] = 450000 }
	for k1, v1 in ipairs(arg1.Skills) do
		local var1 = tbl1[v1.cost]
		var1 = var1 or v1.cost
		v1.cost = var1
	end

	local num1 = 3500000
	local num2 = 8000000
	local tbl2 = { { 0, -1 }, { 1, -1 }, { 1, 0 }, { 0, 1 }, { -1, 1 }, { -1, 0 } }
	local tbl3 = { 250000, 600000, 1500000, num1, num2, 16000000, 30000000 }
	for k2, v2 in ipairs({
		{ "Hero3", "Champion", "Sword", "heroDmg", 0.2, "weapon damage" },
		{ "Gold4", "Treasury", "Coin", "gold", 0.08, "earned Coins" },
		{ "Soul3", "Soulcraft", "Soul", "souls", 0.1, "earned Dark Souls" },
		{ "Dmg5", "Warlord", "SkullSword", "unitDmg", 0.25, "unit damage" },
		{ "Pop5", "Endurance", "Heart", "unitHp", 0.3, "unit health" },
		{ "Trap5", "Siegecraft", "Potion", "trapDmg", 0.3, "trap damage" },
	}) do

		local var2 = v2[1]
		local var3 = tbl2[k2]
		local var4 = tbl2[k2 % 6 + 1]
		for i1 = 1, 7 do
			local var7 = "Mastery" .. k2 .. "_" .. i1
			local var8 = nil
			local var9 = nil
			if i1 == 1 then
				var8 = var3[1] * 6
				var9 = var3[2] * 6
			else
				local var10 = i1 - 2
				var8 = var3[1] * 7 + (var4[1] - var3[1]) * var10
				var9 = var3[2] * 7 + (var4[2] - var3[2]) * var10
			end

			local var11 = 6 <= i1 and v2[5] * 1.5 or v2[5]
			local tbl4 = {
				id = var7,
				name = v2[2] .. " " .. i1,
				parent = var2,
				q = var8,
				r = var9,
				cost = tbl3[i1],
				icon = v2[3],
				fx = { [v2[4]] = var11 },
				desc = "+" .. math.round(var11 * 100) .. "% " .. v2[6] .. ".",
				title = "Dungeon Mastery",
				side = "mastery",
			}

			tbl4.arm = k2
			table.insert(arg1.Skills, tbl4)
			arg1.SkillById[var7] = tbl4
			var2 = var7
		end
	end

	local tbl5 = {
		heroDmg = "weapon damage",
		bossDmg = "damage against bosses",
		gold = "earned Coins",
		waveGold = "wave Coins",
		discount = "off stand offers",
		mutLuck = "mutation chance",
		luck = "roll luck",
		souls = "earned Dark Souls",
		unitDmg = "unit damage",
		mutPower = "mutated unit health and damage",
		pop = "unit population",
		unitHp = "unit health",
		trapDmg = "trap damage",
		crystal = "Crystal health",
	}

	local num3 = 150000000
	local num4 = 220000000
	local function desc(arg1)
		local var3, var4 = next(arg1)
		if var3 == "pop" or var3 == "crystal" then
			return "+" .. var4 .. " " .. tbl5[var3] .. "."
		end

		if var3 == "luck" then
			return "+" .. var4 .. "% " .. tbl5[var3] .. "."
		end

		return ((function() if var3 == "discount" then return "" else return "+" end end)()) .. math.round(var4 * 100) .. "% " .. tbl5[var3] .. "."
	end

	local tbl6 = {
		45000000,
		70000000,
		100000000,
		num3,
		num4,
		320000000,
		460000000,
		650000000,
		900000000,
		1300000000,
	}

	for k3, v3 in ipairs({
		{
			name = "Ascended Blade",
			icon = "Sword",
			fx = { { heroDmg = 0.6 }, { bossDmg = 0.25 }, { heroDmg = 0.8 }, { bossDmg = 0.35 } },
		},
		{
			name = "Ascended Hoard",
			icon = "Coin",
			fx = { { gold = 0.12 }, { waveGold = 0.4 }, { gold = 0.15 }, { discount = 0.05 } },
		},
		{
			name = "Ascended Fate",
			icon = "Clover",
			fx = { { mutLuck = 0.15 }, { luck = 3 }, { souls = 0.12 }, { mutLuck = 0.2 } },
		},
		{
			name = "Ascended Might",
			icon = "SkullSword",
			fx = { { unitDmg = 0.25 }, { mutPower = 0.15 }, { unitDmg = 0.3 }, { mutPower = 0.2 } },
		},
		{
			name = "Ascended Legion",
			icon = "Pop",
			fx = { { pop = 20 }, { unitHp = 0.3 }, { pop = 30 }, { mutPower = 0.15 } },
		},
		{
			name = "Ascended Bastion",
			icon = "Gem",
			fx = { { trapDmg = 0.35 }, { crystal = 250 }, { trapDmg = 0.45 }, { crystal = 400 } },
		},
	}) do

		local var12 = tbl2[k3]
		local var13 = tbl2[k3 % 6 + 1]
		local var14 = "Mastery" .. k3 .. "_2"
		for i2 = 1, 10 do
			local var17 = nil
			local var18 = nil
			if i2 == 1 then
				var17 = var12[1] * 8
				var18 = var12[2] * 8
			else
				local var19 = i2 - 2
				var17 = var12[1] * 9 + (var13[1] - var12[1]) * var19
				var18 = var12[2] * 9 + (var13[2] - var12[2]) * var19
			end

			local var20 = i2 - 1
			local var21 = var20 % #v3.fx
			local var23 = table.clone(v3.fx[var21 + 1])
			if i2 == 10 then
				for k4, v4 in pairs(var23) do
					var23[k4] = v4 * 2
				end
			end

			local var24 = "Ascend" .. k3 .. "_" .. i2
			local tbl7 = {
				id = var24,
				name = v3.name .. " " .. ({ "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X" })[i2],
				parent = var14,
				q = var17,
				r = var18,
				cost = tbl6[i2],
				icon = v3.icon,
				fx = var23,
				desc = desc(var23),
				title = "Ascension",
				side = "ascension",
			}

			tbl7.arm = k3
			local var25 = arg1.Skills
			table.insert(var25, tbl7)
			arg1.SkillById[var24] = tbl7
			var14 = var24
		end
	end

	local tbl8 = { 1, 0.75, 1.4, 1.25, 1.6, 0.85 }
	local tbl9 = { spine = 1, right = 0.85, left = 1.2, mutation = 1.5, mastery = 1, ascension = 1 }
	for k5, v5 in ipairs(arg1.Skills) do
		if v5.id == "Heart" then
			goto L7
		end

		if v5.fixedCost then
			goto L7
		end

		if not v5.arm then
			goto L7
		end

		local var26 = v5.cost * (tbl8[v5.arm] or 1) * (tbl9[v5.side] or 1)
		local num5 = 0
		for k6 in v5.id:gmatch(".") do
			num5 = (num5 * 31 + string.byte(k6)) % 9973
		end

		local var27 = var26 * (num5 % 28 / 100 + 0.88)
		local var28
		if var27 < 1000 then
			var28 = math.floor(var27 / 10 + 0.5) * 10
		else
			var26 = 10 ^ (math.floor((math.log10(var27))) - 1)
			var28 = math.floor(var27 / var26 + 0.5) * var26
		end

		v5.cost = var28
	::L7:: end

	arg1.MAX_ACTIVE_ADVENTURERS = 48
	arg1.ActiveCap = function(arg1)
		arg1 = arg1 or 1
		if arg1 < 100 then
			return arg1.MAX_ACTIVE_ADVENTURERS
		end

		return (math.min(72, arg1.MAX_ACTIVE_ADVENTURERS + math.floor((arg1 - 100) / 25) * 3))
	end

	arg1.WaveEnemyCount = function(arg1)
		local var2 = arg1.BeginnerWaves[arg1]
		if var2 then
			return var2.count
		end

		return math.min(math.floor(arg1 * 1.5) + 5, 60) + math.min(60, math.max(0, (math.floor((arg1 - 30) / 20))) * 10) + math.min(60, math.max(0, (math.floor((arg1 - 150) / 50))) * 10)
	end

	arg1.WaveDamageMult = function(arg1)
		return (math.max(0, arg1 - 50) * 0.01 + 1) * (1 + math.max(0, arg1 - (arg1.DEEP_START or 500)) * (arg1.DEEP_DMG_PER_WAVE or 0.004))
	end

	local tbl10 = {
		name = "Iron Vanguard",
		hp = 210,
		speed = 4.2,
		dmg = 16,
		cd = 1.3,
		core = 15,
		gold = 23,
		souls = 3,
		armor = 0.45,
		template = "Knight",
		weapon = "Longsword",
		pack = "Knight",
		intro = 30,
		tint = Color3.fromRGB(82, 110, 145),
	}

	local tbl11 = { Vanguard = tbl10 }
	tbl10 = {
		name = "Storm Arcanist",
		hp = 135,
		speed = 4.8,
		dmg = 21,
		cd = 2.5,
		core = 14,
		gold = 27,
		souls = 3,
		ranged = 3.8,
		splash = 1.1,
		magicRes = 0.5,
		template = "Wizard",
		weapon = "VoidStaff",
		pack = "Mage",
		intro = 50,
		tint = Color3.fromRGB(84, 183, 228),
	}

	tbl11.Arcanist = tbl10
	tbl10 = {
		name = "Crimson Saboteur",
		hp = 155,
		speed = 7.2,
		dmg = 15,
		cd = 0.8,
		core = 18,
		gold = 30,
		souls = 4,
		unblockable = true,
		disable = 2.5,
		disableCd = 8,
		route = "rogue",
		template = "Rogue",
		weapon = "ViperFang",
		pack = "Ninja",
		intro = 75,
		tint = Color3.fromRGB(165, 48, 70),
	}

	tbl11.Saboteur = tbl10
	tbl10 = {
		name = "Dawn Inquisitor",
		hp = 330,
		speed = 3.9,
		dmg = 25,
		cd = 1.5,
		core = 22,
		gold = 36,
		souls = 5,
		armor = 0.7,
		magicRes = 0.75,
		template = "Paladin",
		weapon = "Morningstar",
		pack = "Superhero",
		intro = 110,
		tint = Color3.fromRGB(226, 180, 68),
	}

	tbl11.Inquisitor = tbl10
	tbl10 = {
		name = "Relic Captain",
		hp = 1800,
		speed = 3.6,
		dmg = 28,
		cd = 1.3,
		core = 50,
		gold = 240,
		souls = 30,
		armor = 0.65,
		boss = true,
		scale = 1.4,
		template = "Captain",
		weapon = "BattleAxe",
		pack = "Pirate",
		tint = Color3.fromRGB(213, 154, 45),
		encounter = true,
	}

	tbl11.RelicCaptain = tbl10
	tbl10 = {
		name = "Rift Seer",
		hp = 1500,
		speed = 4,
		dmg = 26,
		cd = 2.2,
		core = 45,
		gold = 260,
		souls = 32,
		ranged = 4,
		splash = 1.5,
		magicRes = 0.65,
		boss = true,
		scale = 1.4,
		template = "Archmage",
		weapon = "VoidStaff",
		pack = "Levitation",
		tint = Color3.fromRGB(169, 82, 230),
		encounter = true,
	}

	tbl11.RiftSeer = tbl10
	local num6 = 65
	var28 = 61
	tbl10 = {
		name = "Dread Marshal",
		hp = 2600,
		speed = 3.3,
		dmg = 34,
		cd = 1.6,
		core = 65,
		gold = 300,
		souls = 35,
		armor = 0.6,
		boss = true,
		scale = 1.5,
		template = "Paladin",
		weapon = "Morningstar",
		pack = "Superhero",
		tint = Color3.fromRGB(208, num6, var28),
		encounter = true,
	}

	tbl11.DreadMarshal = tbl10
	for k7, v6 in pairs(tbl11) do
		v6.id = k7
		arg1.Enemies[k7] = v6
	end

	local str1 = "Arcanist"
	for k8, v7 in ipairs({ "Vanguard", str1, "Saboteur", "Inquisitor" }) do
		table.insert(arg1.EnemyIntro, { id = v7, wave = tbl11[v7].intro })
	end

	local tbl12 = {
		id = "FrostWarden",
		name = "Frost Warden",
		hp = 340,
		speed = 3.8,
		dmg = 30,
		cd = 1.4,
		core = 20,
		gold = 42,
		souls = 5,
		armor = 0.65,
		magicRes = 0.6,
		template = "Knight",
		weapon = "Frostbite",
		pack = "Knight",
		intro = 150,
		tint = Color3.fromRGB(150, 220, 245),
	}

	local num7 = 200
	local tbl13 = {
		id = "PlagueDoctor",
		name = "Plague Doctor",
		hp = 400,
		speed = 4.3,
		dmg = 32,
		cd = 2.3,
		core = 18,
		gold = 46,
		souls = 5,
		ranged = 3.8,
		splash = 1.3,
		magicRes = 0.55,
		template = "Wizard",
		weapon = "SkullStaff",
		pack = "Mage",
		intro = 190,
		tint = Color3.fromRGB(110, 255, 90),
	}

	tbl10 = {
		tbl12,
		tbl13,
		{
			id = "Berserker",
			name = "Berserker",
			hp = 640,
			speed = 6,
			dmg = 46,
			cd = 1,
			core = 26,
			gold = 55,
			souls = 6,
			armor = 0.3,
			template = "Captain",
			weapon = "Hatchet",
			pack = "Pirate",
			intro = 240,
			tint = Color3.fromRGB(num7, 80, 30),
		},
	}

	for k9, v8 in ipairs(tbl10) do
		arg1.Enemies[v8.id] = v8
		table.insert(arg1.EnemyIntro, { id = v8.id, wave = v8.intro })
	end

	arg1.EncounterTypes = { "RelicCaptain", "RiftSeer", "DreadMarshal" }
	arg1.Encounter = function(arg1)
		if arg1 < 50 or arg1 % 25 ~= 0 then
			return nil
		end

		local var1 = arg1.EncounterTypes[(math.floor(arg1 / 25) - 2) % 3 + 1]
		return {
			id = var1,
			wave = arg1,
			name = arg1.Enemies[var1].name,
			gold = 1500 + arg1 * 45,
			souls = math.floor(arg1 * 0.3) + 15,
		}
	end

	arg1.NextEncounter = function(arg1)
		local var1 = math.max(50, math.ceil(arg1 / 25) * 25)
		return arg1.Encounter(var1)
	end

	arg1.BuildWave = function(arg1)
		local tbl1 = {}
		local var1 = nil
		for k1, v1 in ipairs(arg1.EnemyIntro) do
			if v1.wave > arg1 then
				goto L12
			end

			table.insert(tbl1, v1.id)
			var1 = v1
		::L12:: end

		local tbl2 = {}
		local var2 = Random.new(arg1 * 7919)
		for i1 = 1, arg1.WaveEnemyCount(arg1) do
			local var4 = nil
			if var1 and (var1.wave == arg1 and i1 % 4 == 0) then
				var4 = var1.id
			else
				var4 = (function() if i1 <= 2 then return tbl1[1] else return tbl1[math.clamp(math.floor(var2:NextNumber() ^ 0.7 * #tbl1) + 1, 1, #tbl1)] end end)()
			end

			table.insert(tbl2, var4)
		end

		local var6 = arg1.Encounter(arg1)
		if var6 then
			tbl2[#tbl2] = var6.id
		end

		local var8 = arg1.BossFor(arg1)
		if var8 then
			table.insert(tbl2, var8)
		end

		return tbl2
	end
end }

