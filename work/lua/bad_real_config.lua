-- y u r i

local tbl1 = {}
tbl1[2] = { cost = 8000, wave = 8 }
tbl1[3] = { cost = 30000, wave = 15 }
local tbl2 = {
	CELL = 6,
	COLS = 17,
	ROWS = 16,
	ENTRY_COL = 8,
	LOOT_TIME = 1.5,
	FLOOR_RISE = 24,
	FLOOR_DEPTH = 0,
	MAX_FLOORS = 3,
	FLOOR_TOP = 1.2,
	PIECE_H = 0.4,
	WALL_H = 3.2,
	GAP_COST = 7,
	PLOT_COUNT = 6,
	PLOT_SPACING_X = 124,
	ROAD_HALF = 26,
	STAND_DEPTH = 34,
	TICK = 0.1,
	NET_RATE = 0.2,
	SUBSCRIBE_RADIUS = 150,
	WidthLevels = {
		{ min = 5, max = 11, rows = 10, cost = 0, wave = 0 },
		{ min = 4, max = 12, rows = 11, cost = 400, wave = 2 },
		{ min = 3, max = 13, rows = 12, cost = 900, wave = 4 },
		{ min = 2, max = 14, rows = 13, cost = 1800, wave = 6 },
		{ min = 1, max = 15, rows = 14, cost = 3500, wave = 9 },
		{ min = 0, max = 16, rows = 16, cost = 6000, wave = 12 },
	},
	FloorUnlocks = tbl1,
}

tbl2.START_GOLD = 400
tbl2.START_SOULS = 5
tbl2.CORE_HP = 100
tbl2.MAX_LEVEL = 3
tbl2.SPAWN_INTERVAL = 1.1
tbl2.BASE_POP = 5
tbl2.FRIEND_BOOST = 0.1
tbl2.FRIEND_BOOST_MAX = 0.5
local tbl3 = { id = "Common", color = Color3.fromRGB(200, 200, 200), weight = 50 }
local tbl4 = { id = "Uncommon", color = Color3.fromRGB(90, 230, 110), weight = 26 }
local tbl5 = { id = "Rare", color = Color3.fromRGB(70, 160, 255), weight = 14 }
local tbl6 = { id = "Epic", color = Color3.fromRGB(190, 100, 255), weight = 7 }
local tbl7 = { id = "Legendary", color = Color3.fromRGB(255, 205, 40), weight = 2.5 }
local tbl8 = { id = "Mythic", color = Color3.fromRGB(255, 110, 200), weight = 0.4 }
local tbl9 = { id = "Secret", color = Color3.fromRGB(255, 50, 60), weight = 0.1 }
local tbl10 = { id = "Divine", color = Color3.fromRGB(70, 245, 225), weight = 0.02, unitsOnly = true }
tbl2.Rarities = { tbl3, tbl4, tbl5, tbl6, tbl7, tbl8, tbl9, tbl10 }
tbl2.RarityIndex = {}
tbl2.RarityColor = {}
for k1, v1 in ipairs(tbl2.Rarities) do
	tbl2.RarityIndex[v1.id] = k1
	tbl9 = v1.color
	tbl2.RarityColor[v1.id] = tbl9
end

tbl3 = { name = "BUILDINGS", currency = "gold", cd = 0.9, color = Color3.fromRGB(80, 170, 255) }
tbl1 = { Buildings = tbl3 }
tbl3 = { name = "UNITS", currency = "souls", cd = 0.9, color = Color3.fromRGB(255, 80, 200) }
tbl1.Monsters = tbl3
tbl2.Rolls = tbl1
tbl2.Pity = {
	{ id = "Legendary", n = 80 },
	{ id = "Mythic", n = 160 },
	{ id = "Secret", n = 300 },
	{ id = "Divine", n = 2000 },
}

tbl2.BuildPrice = {
	Common = 60,
	Uncommon = 150,
	Rare = 400,
	Epic = 1000,
	Legendary = 2800,
	Mythic = 8000,
	Secret = 25000,
}

tbl2.UnitPrice = {
	Common = 3,
	Uncommon = 20,
	Rare = 500,
	Epic = 2000,
	Legendary = 5000,
	Mythic = 10000,
	Secret = 20000,
	Divine = 100000,
}

tbl2.UnitPriceById = {
	Skeleton = 3,
	Slime = 3,
	Goblin = 20,
	Archer = 60,
	GraveSentinel = 100,
	Knight = 500,
	Mage = 750,
	EmberDrake = 1000,
	Necromancer = 2000,
	Golem = 2750,
	HexArcher = 3500,
	EliteKnight = 4250,
	FrostDrake = 5000,
	SkeletonKing = 5000,
	RoyalKnight = 7500,
	StormDrake = 10000,
	Lich = 10000,
	DreadKnight = 20000,
	Mimic = 25000,
}

tbl2.UnitPop = {
	Common = 1,
	Uncommon = 1,
	Rare = 2,
	Epic = 2,
	Legendary = 3,
	Mythic = 4,
	Secret = 4,
	Divine = 5,
}

tbl2.LuckPct = function(arg1, arg2, arg3)
	return math.round((((math.min(60, math.floor((arg1 or 0) / 2) + 1) + math.max(0, arg2 or 0)) / 100 + 1) * math.max(1, arg3 or 1) - 1) * 1000000) / 10000
end

tbl1 = {}
tbl2.Weapons = tbl1
tbl1.IronSword = {
	id = "IronSword",
	name = "Iron Sword",
	rarity = "Common",
	class = "sword",
	dmg = 12,
	lib = "Wpn_IronSword",
}

tbl1.RustyDagger = {
	id = "RustyDagger",
	name = "Rusty Dagger",
	rarity = "Common",
	class = "dagger",
	dmg = 10,
	lib = "Wpn_RustyDagger",
}

tbl1.SpikedClub = {
	id = "SpikedClub",
	name = "Spiked Club",
	rarity = "Common",
	class = "mace",
	dmg = 13,
	lib = "Wpn_SpikedClub",
}

tbl1.HuntingBow = {
	id = "HuntingBow",
	name = "Hunting Bow",
	rarity = "Common",
	class = "bow",
	dmg = 11,
	lib = "Wpn_HuntingBow",
}

tbl4 = { orb = Color3.fromRGB(124, 255, 90) }
local tbl11 = {
	id = "OakStaff",
	name = "Oak Staff",
	rarity = "Common",
	class = "staff",
	dmg = 11,
	lib = "Wpn_OakStaff",
}

if tbl4 then
	for k2, v2 in pairs(tbl4) do
		tbl11[k2] = v2
	end
end

tbl1.OakStaff = tbl11
tbl1.Pitchfork = {
	id = "Pitchfork",
	name = "Farmer's Pitchfork",
	rarity = "Common",
	class = "polearm",
	dmg = 12,
	lib = "Wpn_Pitchfork",
}

tbl1.SteelBroadsword = {
	id = "SteelBroadsword",
	name = "Steel Broadsword",
	rarity = "Uncommon",
	class = "sword",
	dmg = 20,
	lib = "Wpn_SteelBroadsword",
}

tbl1.Hatchet = {
	id = "Hatchet",
	name = "Woodsman Axe",
	rarity = "Uncommon",
	class = "axe",
	dmg = 22,
	lib = "Wpn_Hatchet",
}

tbl1.GuardSpear = {
	id = "GuardSpear",
	name = "Guard Spear",
	rarity = "Uncommon",
	class = "polearm",
	dmg = 21,
	lib = "Wpn_GuardSpear",
}

tbl4 = { orb = Color3.fromRGB(255, 122, 30) }
tbl11 = {
	id = "EmberStaff",
	name = "Ember Staff",
	rarity = "Uncommon",
	class = "staff",
	dmg = 22,
	lib = "Wpn_EmberStaff",
}

local var1
local var2
if tbl4 then
	for k3, v3 in pairs(tbl4) do
		tbl11[k3] = v3
	end
end

tbl1.EmberStaff = tbl11
tbl1.ShortBow = {
	id = "ShortBow",
	name = "Goblin Shortbow",
	rarity = "Uncommon",
	class = "bow",
	dmg = 19,
	lib = "Wpn_ShortBow",
}

tbl1.Longsword = {
	id = "Longsword",
	name = "Knight's Longsword",
	rarity = "Rare",
	class = "sword",
	dmg = 34,
	lib = "Wpn_Longsword",
}

tbl1.BattleAxe = {
	id = "BattleAxe",
	name = "Bearded Battleaxe",
	rarity = "Rare",
	class = "great",
	dmg = 40,
	lib = "Wpn_BattleAxe",
}

tbl1.Halberd = {
	id = "Halberd",
	name = "Iron Halberd",
	rarity = "Rare",
	class = "halberd",
	dmg = 38,
	lib = "Wpn_Halberd",
}

tbl4 = { orb = Color3.fromRGB(143, 227, 255) }
tbl11 = {
	id = "FrostStaff",
	name = "Frost Staff",
	rarity = "Rare",
	class = "staff",
	dmg = 36,
	lib = "Wpn_FrostStaff",
}

local var3
local var4
if tbl4 then
	for k4, v4 in pairs(tbl4) do
		tbl11[k4] = v4
	end
end

tbl1.FrostStaff = tbl11
tbl1.ViperFang = {
	id = "ViperFang",
	name = "Viper Fang",
	rarity = "Rare",
	class = "dagger",
	dmg = 32,
	lib = "Wpn_ViperFang",
}

tbl4 = { orb = Color3.fromRGB(255, 240, 160) }
tbl11 = {
	id = "HolyScepter",
	name = "Holy Scepter",
	rarity = "Rare",
	class = "staff",
	dmg = 35,
	lib = "Wpn_HolyScepter",
}

local var5
local var6
if tbl4 then
	for k5, v5 in pairs(tbl4) do
		tbl11[k5] = v5
	end
end

tbl1.HolyScepter = tbl11
tbl1.Greatsword = {
	id = "Greatsword",
	name = "Knight Greatsword",
	rarity = "Epic",
	class = "great",
	dmg = 60,
	lib = "Wpn_Greatsword",
}

tbl1.Katana = {
	id = "Katana",
	name = "Moonlit Katana",
	rarity = "Epic",
	class = "katana",
	dmg = 58,
	lib = "Wpn_Katana",
}

tbl1.Morningstar = {
	id = "Morningstar",
	name = "Starfall Morningstar",
	rarity = "Epic",
	class = "mace",
	dmg = 62,
	lib = "Wpn_Morningstar",
}

tbl4 = { orb = Color3.fromRGB(124, 255, 90) }
tbl11 = {
	id = "SkullStaff",
	name = "Bone Staff",
	rarity = "Epic",
	class = "staff",
	dmg = 55,
	lib = "Wpn_SkullStaff",
}

local var7
local var8
if tbl4 then
	for k6, v6 in pairs(tbl4) do
		tbl11[k6] = v6
	end
end

tbl1.SkullStaff = tbl11
tbl1.ElvenBow = {
	id = "ElvenBow",
	name = "Elven Longbow",
	rarity = "Epic",
	class = "bow",
	dmg = 56,
	lib = "Wpn_ElvenBow",
}

tbl1.WarMaul = {
	id = "WarMaul",
	name = "Thunder Maul",
	rarity = "Legendary",
	class = "great",
	dmg = 110,
	lib = "Wpn_WarMaul",
}

tbl1.SpectralGlaive = {
	id = "SpectralGlaive",
	name = "Spectral Glaive",
	rarity = "Legendary",
	class = "halberd",
	dmg = 105,
	lib = "Wpn_SpectralGlaive",
}

tbl1.GraveScythe = {
	id = "GraveScythe",
	name = "Grave Scythe",
	rarity = "Legendary",
	class = "scythe",
	dmg = 115,
	lib = "Wpn_GraveScythe",
}

tbl1.CrimsonReaver = {
	id = "CrimsonReaver",
	name = "Crimson Reaver",
	rarity = "Legendary",
	class = "great",
	dmg = 120,
	lib = "Wpn_CrimsonReaver",
}

tbl1.Frostbite = {
	id = "Frostbite",
	name = "Frostbite Greatsword",
	rarity = "Mythic",
	class = "great",
	dmg = 220,
	lib = "Wpn_Frostbite",
}

tbl1.OniKanabo = {
	id = "OniKanabo",
	name = "Oni Kanabo",
	rarity = "Mythic",
	class = "great",
	dmg = 230,
	lib = "Wpn_OniKanabo",
}

tbl1.DragonSpear = {
	id = "DragonSpear",
	name = "Dragonbone Spear",
	rarity = "Mythic",
	class = "polearm",
	dmg = 210,
	lib = "Wpn_DragonSpear",
}

tbl4 = { orb = Color3.fromRGB(224, 112, 255) }
tbl11 = {
	id = "VoidStaff",
	name = "Void Staff",
	rarity = "Mythic",
	class = "staff",
	dmg = 200,
	lib = "Wpn_VoidStaff",
}

local var9
local var10
if tbl4 then
	for k7, v7 in pairs(tbl4) do
		tbl11[k7] = v7
	end
end

tbl1.VoidStaff = tbl11
tbl1.Kingsblade = {
	id = "Kingsblade",
	name = "Kingsblade",
	rarity = "Secret",
	class = "great",
	dmg = 450,
	lib = "Wpn_Kingsblade",
}

tbl1.SoulReaper = {
	id = "SoulReaper",
	name = "Soul Reaper",
	rarity = "Secret",
	class = "scythe",
	dmg = 480,
	lib = "Wpn_SoulReaper",
}

tbl1.CelestialBow = {
	id = "CelestialBow",
	name = "Celestial Bow",
	rarity = "Secret",
	class = "bow",
	dmg = 420,
	lib = "Wpn_CelestialBow",
}

tbl1.BoneClaws = {
	id = "BoneClaws",
	name = "Bone Claws",
	rarity = "Common",
	class = "dagger",
	dmg = 13,
	lib = "Wpn_BoneClaws",
}

tbl1.CrystalAxe = {
	id = "CrystalAxe",
	name = "Crystal Axe",
	rarity = "Uncommon",
	class = "axe",
	dmg = 23,
	lib = "Wpn_CrystalAxe",
}

tbl1.Hellfork = {
	id = "Hellfork",
	name = "Hellfork",
	rarity = "Uncommon",
	class = "polearm",
	dmg = 22,
	lib = "Wpn_Hellfork",
}

tbl1.VenomDagger = {
	id = "VenomDagger",
	name = "Venom Fang",
	rarity = "Rare",
	class = "dagger",
	dmg = 33,
	lib = "Wpn_VenomDagger",
}

tbl1.GlacierSpear = {
	id = "GlacierSpear",
	name = "Glacier Spear",
	rarity = "Rare",
	class = "polearm",
	dmg = 37,
	lib = "Wpn_GlacierSpear",
}

tbl1.BloodRapier = {
	id = "BloodRapier",
	name = "Blood Rapier",
	rarity = "Epic",
	class = "sword",
	dmg = 57,
	lib = "Wpn_BloodRapier",
}

tbl1.MagmaHammer = {
	id = "MagmaHammer",
	name = "Magma Hammer",
	rarity = "Epic",
	class = "mace",
	dmg = 63,
	lib = "Wpn_MagmaHammer",
}

tbl1.StormBow = {
	id = "StormBow",
	name = "Storm Bow",
	rarity = "Legendary",
	class = "bow",
	dmg = 108,
	lib = "Wpn_StormBow",
}

tbl1.HellfireCleaver = {
	id = "HellfireCleaver",
	name = "Hellfire Cleaver",
	rarity = "Legendary",
	class = "great",
	dmg = 118,
	lib = "Wpn_HellfireCleaver",
}

tbl1.TempestKatana = {
	id = "TempestKatana",
	name = "Tempest Katana",
	rarity = "Mythic",
	class = "katana",
	dmg = 215,
	lib = "Wpn_TempestKatana",
}

tbl7 = 120
tbl4 = { orb = Color3.fromRGB(230, tbl7, 255) }
tbl11 = {
	id = "ArcaneStaff",
	name = "Arcane Orb Staff",
	rarity = "Mythic",
	class = "staff",
	dmg = 205,
	lib = "Wpn_ArcaneStaff",
}

local var11
local var12
if tbl4 then
	for k8, v8 in pairs(tbl4) do
		tbl11[k8] = v8
	end
end

tbl1.ArcaneStaff = tbl11
tbl1.AbyssalScythe = {
	id = "AbyssalScythe",
	name = "Abyssal Scythe",
	rarity = "Secret",
	class = "scythe",
	dmg = 470,
	lib = "Wpn_AbyssalScythe",
}

tbl4 = { exclusive = true, bonus = 0.35 }
tbl11 = {
	id = "BloodmoonReaver",
	name = "Bloodmoon Reaver",
	rarity = "Secret",
	class = "great",
	dmg = 500,
	lib = "Wpn_BloodmoonReaver",
}

local var13
local var14
if tbl4 then
	for k9, v9 in pairs(tbl4) do
		tbl11[k9] = v9
	end
end

tbl1.BloodmoonReaver = tbl11
tbl4 = { exclusive = true, bonus = 0.12, labyrinth = "hollow" }
tbl11 = {
	id = "Hollowfang",
	name = "Hollowfang",
	rarity = "Legendary",
	class = "dagger",
	dmg = 70,
	lib = "Wpn_Hollowfang",
}

local var15
local var16
if tbl4 then
	for k10, v10 in pairs(tbl4) do
		tbl11[k10] = v10
	end
end

tbl1.Hollowfang = tbl11
tbl4 = { exclusive = true, bonus = 0.25, labyrinth = "crimson" }
tbl11 = {
	id = "CrimsonOath",
	name = "Crimson Oath",
	rarity = "Mythic",
	class = "great",
	dmg = 260,
	lib = "Wpn_CrimsonOath",
}

local var17
local var18
if tbl4 then
	for k11, v11 in pairs(tbl4) do
		tbl11[k11] = v11
	end
end

tbl1.CrimsonOath = tbl11
tbl4 = { exclusive = true, bonus = 0.4, labyrinth = "void" }
tbl11 = {
	id = "VoidheartScythe",
	name = "Voidheart Scythe",
	rarity = "Secret",
	class = "scythe",
	dmg = 560,
	lib = "Wpn_VoidheartScythe",
}

local var19
local var20
if tbl4 then
	for k12, v12 in pairs(tbl4) do
		tbl11[k12] = v12
	end
end

tbl1.VoidheartScythe = tbl11
tbl4 = { exclusive = true, bonus = 0.1, labyrinth = "labyrinth" }
tbl11 = {
	id = "Briarthorn",
	name = "Briarthorn",
	rarity = "Epic",
	class = "sword",
	dmg = 64,
	lib = "Wpn_Briarthorn",
}

local var21
local var22
if tbl4 then
	for k13, v13 in pairs(tbl4) do
		tbl11[k13] = v13
	end
end

tbl1.Briarthorn = tbl11
tbl4 = { exclusive = true, bonus = 0.16, labyrinth = "labyrinth" }
tbl11 = {
	id = "JadewindGlaive",
	name = "Jadewind Glaive",
	rarity = "Legendary",
	class = "halberd",
	dmg = 112,
	lib = "Wpn_JadewindGlaive",
}

local var23
local var24
if tbl4 then
	for k14, v14 in pairs(tbl4) do
		tbl11[k14] = v14
	end
end

tbl1.JadewindGlaive = tbl11
tbl4 = { exclusive = true, bonus = 0.28, labyrinth = "labyrinth" }
tbl11 = {
	id = "EmberforgeMaul",
	name = "Emberforge Maul",
	rarity = "Mythic",
	class = "mace",
	dmg = 240,
	lib = "Wpn_EmberforgeMaul",
}

local var25
local var26
if tbl4 then
	for k15, v15 in pairs(tbl4) do
		tbl11[k15] = v15
	end
end

tbl1.EmberforgeMaul = tbl11
tbl4 = { exclusive = true, bonus = 0.5, labyrinth = "labyrinth" }
tbl11 = {
	id = "EclipseEdge",
	name = "Eclipse Edge",
	rarity = "Divine",
	class = "katana",
	dmg = 640,
	lib = "Wpn_EclipseEdge",
}

local var27
local var28
if tbl4 then
	for k16, v16 in pairs(tbl4) do
		tbl11[k16] = v16
	end
end

tbl1.EclipseEdge = tbl11
tbl4 = { exclusive = true, bonus = 0.6, labyrinth = "labyrinth" }
tbl11 = {
	id = "Worldsunder",
	name = "Worldsunder",
	rarity = "Divine",
	class = "great",
	dmg = 820,
	lib = "Wpn_Worldsunder",
}

if tbl4 then
	for k17, v17 in pairs(tbl4) do
		tbl11[k17] = v17
	end
end

tbl1.Worldsunder = tbl11
tbl2.ExclusiveWeapons = { BloodmoonReaver = { passId = 1998639822, price = 399, bonus = 0.35 } }
tbl2.WeaponDamage = function(arg1, arg2)
	local var2 = tbl2.Weapons[arg2]
	if not var2 then
		return 0
	end

	if var2.exclusive then
		local var3 = (tbl2.Weapons[tbl2.StarterWeapon] or var2).dmg
		for k1, v1 in pairs(arg1 and arg1.weapons or {}) do
			local var4 = v1
			var4 = var4 and tbl2.Weapons[k1]
			if not var4 then
				goto L18
			end

			if var4.exclusive then
				goto L18
			end

			if var3 >= var4.dmg then
				goto L18
			end

			var3 = var4.dmg
		::L18:: end

		return (math.max(var2.dmg, (math.floor(var3 * (1 + (var2.bonus or 0.35)) + 0.5))))
	end

	return var2.dmg
end

tbl2.WeaponOrder = {}
for k18 in pairs(tbl1) do
	table.insert(tbl2.WeaponOrder, k18)
end

table.sort(tbl2.WeaponOrder, function(arg1, arg2)
	local var3 = tbl2.RarityIndex[tbl1[arg1].rarity]
	local var4 = tbl2.RarityIndex[tbl1[arg2].rarity]
	if var3 ~= var4 then
		return var3 < var4
	end

	return tbl1[arg1].dmg < tbl1[arg2].dmg
end)

tbl2.StarterWeapon = "IronSword"
tbl2.WEAPON_DROP = 0
tbl2.WEAPON_DROP_BOSS = 0
tbl2.WeaponPrice = {
	Common = 150,
	Uncommon = 600,
	Rare = 2500,
	Epic = 25000,
	Legendary = 250000,
	Mythic = 3000000,
	Secret = 30000000,
	Divine = 300000000,
}

tbl4 = {}
for k19, v18 in pairs(tbl1) do
	local var30 = tbl4[v18.rarity]
	if not var30 then
		var30 = { min = v18.dmg, max = v18.dmg }
		tbl4[v18.rarity] = var30
	end

	local var31 = math.min(var30.min, v18.dmg)
	var30.min = var31
	var31 = math.max(var30.max, v18.dmg)
	var30.max = var31
end

for k20, v19 in pairs(tbl1) do
	local var32 = tbl4[v19.rarity]
	local var33 = var32.min < var32.max and (v19.dmg - var32.min) / (var32.max - var32.min) or 0.5
	local var34 = (function() if 100000 <= tbl2.WeaponPrice[v19.rarity] then return 10000 else return 10 end end)()
	v19.price = math.floor(tbl2.WeaponPrice[v19.rarity] * (0.8 + 0.4 * var33) / var34 + 0.5) * var34
end

tbl2.GetWeaponPrice = function(arg1)
	local var1 = tbl1[arg1]
	assert(var1, "Unknown weapon: " .. tostring(arg1))
	return var1.price
end

tbl2.CHECKPOINT_EVERY = 10
tbl2.TwoHanded = { great = true, katana = true, polearm = true, halberd = true, scythe = true, bow = true }
tbl11 = {}
tbl2.Items = tbl11
tbl11.WoodFloor = {
	kind = "floor",
	cat = "Buildings",
	sub = "Rooms",
	name = "Wooden Floor",
	rarity = "Common",
	roll = 24,
	order = 1,
	edges = {},
	wood = true,
	desc = "A plain wooden floor with no walls. Connect rooms or make a 2 x 2 area for a drake.",
}

tbl11.YellowCorridor = {
	kind = "floor",
	cat = "Buildings",
	sub = "Corridors",
	name = "Stone Corridor",
	rarity = "Common",
	roll = 20,
	order = 2,
	edges = { 2, 4 },
	lib = "Pc_Corridor",
	desc = "A straight corridor with stone walls on both sides. Rotate with R.",
}

tbl11.CorridorCorner = {
	kind = "floor",
	cat = "Buildings",
	sub = "Corridors",
	name = "Curved Corridor",
	rarity = "Common",
	roll = 16,
	order = 3,
	edges = { 1, 2 },
	lib = "Pc_CorridorCorner",
	desc = "A corridor that curves around a corner.",
}

tbl11.CorridorT = {
	kind = "floor",
	cat = "Buildings",
	sub = "Corridors",
	name = "Corridor Junction",
	rarity = "Uncommon",
	roll = 12,
	order = 4,
	edges = { 1 },
	lib = "Pc_CorridorT",
	desc = "T-junction: walled on one side only.",
}

tbl11.Crossroads = {
	kind = "floor",
	cat = "Buildings",
	sub = "Corridors",
	name = "Crossroads",
	rarity = "Uncommon",
	roll = 10,
	order = 5,
	edges = {},
	lib = "Pc_Crossroads",
	desc = "Open four-way crossing with stone pillars in the corners.",
}

tbl11.CorridorEnd = {
	kind = "floor",
	cat = "Buildings",
	sub = "Corridors",
	name = "Dead End",
	rarity = "Uncommon",
	roll = 10,
	order = 6,
	edges = { 1, 2, 4 },
	lib = "Pc_CorridorEnd",
	desc = "A walled dead end. Perfect for hiding a Treasure Room.",
}

tbl11.TreasureRoom = {
	kind = "floor",
	cat = "Buildings",
	sub = "Rooms",
	name = "Treasure Room",
	rarity = "Uncommon",
	roll = 5,
	order = 10,
	edges = {},
	lib = "Rm_TreasureRoom",
	buff = { gold = 1.5 },
	desc = "BAIT! Most adventurers detour to loot it, even down dead ends (greedy ones always do). Kills here drop +50% Coins.",
}

tbl11.TrapRoom = {
	kind = "floor",
	cat = "Buildings",
	sub = "Rooms",
	name = "Trap Room",
	rarity = "Uncommon",
	roll = 8,
	order = 11,
	edges = {},
	lib = "Rm_TrapRoom",
	buff = { trapCd = 0.8 },
	desc = "Traps placed here recharge 20% faster.",
}

tbl11.MonsterDen = {
	kind = "floor",
	cat = "Buildings",
	sub = "Rooms",
	name = "Monster Den",
	rarity = "Rare",
	roll = 6,
	order = 12,
	edges = {},
	lib = "Rm_MonsterDen",
	buff = { monsterHp = 1.3 },
	desc = "Units placed here get +30% health.",
}

tbl11.Armory = {
	kind = "floor",
	cat = "Buildings",
	sub = "Rooms",
	name = "Armory",
	rarity = "Rare",
	roll = 6,
	order = 13,
	edges = {},
	lib = "Rm_Armory",
	buff = { physical = 1.25 },
	desc = "Physical units & traps here deal +25% damage.",
}

tbl11.Graveyard = {
	kind = "floor",
	cat = "Buildings",
	sub = "Rooms",
	name = "Graveyard",
	rarity = "Epic",
	roll = 5,
	order = 14,
	edges = {},
	lib = "Rm_Graveyard",
	buff = { undead = 1.35 },
	desc = "Undead units here deal +35% damage.",
}

tbl11.LavaChamber = {
	kind = "floor",
	cat = "Buildings",
	sub = "Rooms",
	name = "Lava Chamber",
	rarity = "Legendary",
	roll = 4,
	order = 15,
	edges = {},
	lib = "Rm_LavaChamber",
	buff = { fire = 1.5 },
	desc = "Fire traps & fire units here deal +50% damage.",
}

tbl11.BossRoom = {
	kind = "floor",
	cat = "Buildings",
	sub = "Rooms",
	name = "Boss Room",
	rarity = "Mythic",
	roll = 3,
	order = 16,
	edges = {},
	lib = "Rm_BossRoom",
	buff = { boss = 1.5 },
	desc = "Boss units here get +50% damage and health.",
}

tbl11.CrystalHall = {
	kind = "floor",
	cat = "Buildings",
	sub = "Rooms",
	name = "Crystal Hall",
	rarity = "Secret",
	roll = 3,
	order = 17,
	edges = {},
	lib = "Rm_CrystalHall",
	buff = { gold = 2, trapCd = 0.75 },
	desc = "SECRET. Double Coins from kills and faster traps.",
}

tbl11.StoneWall = {
	kind = "block",
	cat = "Buildings",
	sub = "Walls",
	name = "Stone Wall",
	rarity = "Common",
	roll = 20,
	order = 20,
	lib = "Pc_StoneWall",
	desc = "Solid stone block. Seal off shortcuts so adventurers must follow your corridors.",
}

tbl11.WoodWall = {
	kind = "block",
	cat = "Buildings",
	sub = "Walls",
	name = "Wooden Barricade",
	rarity = "Common",
	roll = 20,
	order = 21,
	wood = true,
	lib = "Pc_WoodWall",
	desc = "Cheap wall. Careful: Rogues slip right through wooden walls!",
}

tbl11.CurvedWall = {
	kind = "block",
	cat = "Buildings",
	sub = "Walls",
	name = "Curved Wall",
	rarity = "Uncommon",
	roll = 12,
	order = 22,
	lib = "Pc_CurvedWall",
	desc = "A rounded stone corner. Rotate with R.",
}

tbl11.SpikeTrap = {
	kind = "trap",
	cat = "Buildings",
	sub = "Traps",
	name = "Spike Trap",
	rarity = "Common",
	roll = 5,
	order = 30,
	value = 40,
	trap = { mode = "tile", dmg = 18, cd = 1.1, dtype = "physical" },
	desc = "Stabs every adventurer standing on it.",
}

tbl11.SlowTrap = {
	kind = "trap",
	cat = "Buildings",
	sub = "Traps",
	name = "Tar Pit",
	rarity = "Common",
	roll = 5,
	order = 31,
	value = 50,
	trap = { mode = "aura", slow = 0.5, slowDur = 1.2 },
	desc = "Sticky tar slows adventurers by 50%.",
}

tbl11.ArrowTrap = {
	kind = "trap",
	cat = "Buildings",
	sub = "Traps",
	name = "Arrow Trap",
	rarity = "Uncommon",
	roll = 4,
	order = 32,
	value = 70,
	trap = { mode = "line", dmg = 11, cd = 0.8, len = 3, dtype = "physical" },
	desc = "Fires arrows the way it faces (3 tiles). Rotate it!",
}

tbl11.BearTrap = {
	kind = "trap",
	cat = "Buildings",
	sub = "Traps",
	name = "Bear Trap",
	rarity = "Uncommon",
	roll = 4,
	order = 33,
	value = 60,
	trap = { mode = "tile", dmg = 25, cd = 6, root = 2.5, dtype = "physical", single = true },
	desc = "Snaps shut, rooting one adventurer.",
}

tbl11.FireTrap = {
	kind = "trap",
	cat = "Buildings",
	sub = "Traps",
	name = "Fire Trap",
	rarity = "Rare",
	roll = 3,
	order = 34,
	value = 85,
	trap = { mode = "tile", dmg = 8, cd = 2.2, burn = 9, burnDur = 3, dtype = "fire" },
	desc = "Blasts fire. Combo: Oil Trap!",
}

tbl11.OilTrap = {
	kind = "trap",
	cat = "Buildings",
	sub = "Traps",
	name = "Oil Trap",
	rarity = "Rare",
	roll = 3,
	order = 35,
	value = 45,
	trap = { mode = "aura", oil = 5 },
	desc = "Oiled adventurers take +75% FIRE damage.",
}

tbl11.PoisonTrap = {
	kind = "trap",
	cat = "Buildings",
	sub = "Traps",
	name = "Poison Trap",
	rarity = "Epic",
	roll = 3,
	order = 36,
	value = 75,
	trap = { mode = "tile", dmg = 0, cd = 1.6, poison = 7, poisonDur = 4, dtype = "poison" },
	desc = "Poison cloud. Combo: Slimes!",
}

tbl11.SawTrap = {
	kind = "trap",
	cat = "Buildings",
	sub = "Traps",
	name = "Saw Trap",
	rarity = "Epic",
	roll = 2,
	order = 37,
	value = 110,
	trap = { mode = "tile", dmg = 6, cd = 0.3, dtype = "physical" },
	desc = "A spinning saw that shreds anything on its tile.",
}

tbl11.FallingRocks = {
	kind = "trap",
	cat = "Buildings",
	sub = "Traps",
	name = "Falling Rocks",
	rarity = "Legendary",
	roll = 2,
	order = 38,
	value = 140,
	trap = { mode = "tile", dmg = 45, cd = 6, area = 1, dtype = "physical" },
	desc = "Drops boulders on a 3x3 area.",
}

tbl11.WoodDoor = {
	kind = "utility",
	cat = "Buildings",
	sub = "Decor",
	name = "Wooden Door",
	rarity = "Uncommon",
	roll = 3,
	order = 40,
	value = 35,
	util = { door = 150 },
	desc = "Adventurers must smash through it. Put traps in front!",
}

tbl11.IronGate = {
	kind = "utility",
	cat = "Buildings",
	sub = "Decor",
	name = "Iron Gate",
	rarity = "Rare",
	roll = 2,
	order = 41,
	value = 130,
	util = { door = 500 },
	desc = "A heavy gate that stalls adventurers for a long time.",
}

tbl11.Torch = {
	kind = "utility",
	cat = "Buildings",
	sub = "Decor",
	name = "Brazier",
	rarity = "Common",
	roll = 8,
	order = 42,
	value = 20,
	util = { deco = true },
	desc = "Decoration. Lights up at night.",
}

tbl11.Crystal = {
	kind = "special",
	cat = "Special",
	name = "Dungeon Crystal",
	order = 90,
	desc = "Adventurers want to reach it. Move it with the Hammer to make their trip longer!",
}

tbl11.Stairs = {
	kind = "special",
	cat = "Special",
	name = "Stairs Up",
	order = 91,
	desc = "Adventurers climb to the next floor here. Move it with the Hammer.",
}

tbl11.Skeleton = {
	kind = "monster",
	cat = "Monsters",
	name = "Skeleton Warrior",
	order = 1,
	rarity = "Common",
	value = 50,
	pack = "Zombie",
	weapon = "IronSword",
	shield = "Round",
	ability = { name = "Heavy Slash", desc = "Every 4th hit deals 200% damage." },
	mon = {
		hp = 70,
		dmg = 9,
		cd = 1,
		range = 1.4,
		attack = "melee",
		block = 1,
		heavy = 4,
		tags = { undead = true, physical = true },
	},
	desc = "Melee fighter. Holds back 1 adventurer. Undead.",
}

tbl11.Slime = {
	kind = "monster",
	cat = "Monsters",
	name = "Slime",
	order = 2,
	rarity = "Common",
	value = 45,
	ability = { name = "Sticky Goo", desc = "Hits slow adventurers by 40%. Holds back 2." },
	mon = {
		hp = 110,
		dmg = 5,
		cd = 1.2,
		range = 1.4,
		attack = "melee",
		block = 2,
		slowOnHit = 0.4,
		tags = { slime = true },
	},
	desc = "Sticky tank that slows what it hits.",
}

tbl11.Goblin = {
	kind = "monster",
	cat = "Monsters",
	name = "Goblin Stabber",
	order = 3,
	rarity = "Uncommon",
	value = 65,
	pack = "Werewolf",
	weapon = "RustyDagger",
	dual = true,
	ability = { name = "Frenzy", desc = "Stabs twice as fast as anyone else." },
	mon = {
		hp = 60,
		dmg = 5,
		cd = 0.45,
		range = 1.4,
		attack = "melee",
		block = 1,
		tags = { physical = true },
	},
	desc = "Frantic stabber with a very fast attack.",
}

tbl11.Archer = {
	kind = "monster",
	cat = "Monsters",
	name = "Goblin Archer",
	order = 4,
	rarity = "Uncommon",
	value = 90,
	pack = "Ninja",
	weapon = "ShortBow",
	ability = { name = "Volley", desc = "Shoots adventurers from 3.5 tiles away." },
	mon = {
		hp = 45,
		dmg = 9,
		cd = 0.9,
		range = 3.5,
		attack = "ranged",
		block = 0,
		tags = { physical = true },
	},
	desc = "Long-range damage. Place beside Tar Pits!",
}

tbl11.Knight = {
	kind = "monster",
	cat = "Monsters",
	name = "Dark Knight",
	order = 5,
	rarity = "Rare",
	value = 150,
	pack = "Knight",
	weapon = "Greatsword",
	ability = { name = "Iron Wall", desc = "Armored bruiser that holds back 2 adventurers." },
	mon = {
		hp = 240,
		dmg = 15,
		cd = 1.1,
		range = 1.4,
		attack = "melee",
		block = 2,
		tags = { physical = true },
	},
	desc = "Armored bruiser. Holds 2 adventurers.",
}

tbl11.Mage = {
	kind = "monster",
	cat = "Monsters",
	name = "Fire Mage",
	order = 6,
	rarity = "Rare",
	value = 170,
	pack = "Mage",
	weapon = "EmberStaff",
	ability = { name = "Fireball", desc = "Throws fireballs that hit whole groups." },
	mon = {
		hp = 50,
		dmg = 14,
		cd = 2,
		range = 3.2,
		attack = "aoe",
		splash = 1.3,
		block = 0,
		dtype = "magic",
		tags = { fire = true },
	},
	desc = "Throws fireballs that hit groups.",
}

tbl11.Necromancer = {
	kind = "monster",
	cat = "Monsters",
	name = "Necromancer",
	order = 7,
	rarity = "Epic",
	value = 260,
	pack = "Vampire",
	weapon = "SkullStaff",
	ability = {
		name = "Raise Dead",
		desc = "Summons skeleton minions. Undead nearby deal +25% damage.",
	},
	mon = {
		hp = 70,
		dmg = 8,
		cd = 1.4,
		range = 3,
		attack = "ranged",
		block = 0,
		dtype = "magic",
		summon = 9,
		aura = { undead = 1.25, radius = 3 },
		tags = { undead = true },
	},
	desc = "Raises Skeleton minions. Undead nearby deal +25% damage.",
}

tbl11.Golem = {
	kind = "monster",
	cat = "Monsters",
	name = "Stone Golem",
	order = 8,
	rarity = "Epic",
	value = 260,
	ability = { name = "Bulwark", desc = "A wall of stone that holds back 4 adventurers." },
	mon = {
		hp = 700,
		dmg = 12,
		cd = 1.6,
		range = 1.4,
		attack = "melee",
		block = 4,
		tags = { physical = true },
	},
	desc = "Huge wall of stone. Holds back 4 adventurers.",
}

tbl11.SkeletonKing = {
	kind = "monster",
	cat = "Monsters",
	name = "Skeleton King",
	order = 9,
	rarity = "Legendary",
	value = 600,
	pack = "Knight",
	weapon = "CrimsonReaver",
	ability = { name = "Royal Cleave", desc = "Every swing hits all nearby adventurers." },
	mon = {
		hp = 600,
		dmg = 30,
		cd = 1.3,
		range = 1.6,
		attack = "melee",
		cleave = true,
		block = 3,
		boss = true,
		aura = { undead = 1.2, radius = 3 },
		tags = { undead = true, physical = true },
	},
	desc = "Dungeon boss. Cleaves all nearby adventurers.",
}

tbl11.Lich = {
	kind = "monster",
	cat = "Monsters",
	name = "Lich Lord",
	order = 10,
	rarity = "Mythic",
	value = 1200,
	pack = "Levitation",
	weapon = "FrostStaff",
	ability = { name = "Frost Nova", desc = "Frost blasts, skeleton minions and an undead aura." },
	mon = {
		hp = 950,
		dmg = 54,
		cd = 1.8,
		range = 3.6,
		attack = "aoe",
		splash = 1.5,
		block = 0,
		dtype = "magic",
		summon = 7,
		boss = true,
		aura = { undead = 1.3, radius = 4 },
		tags = { undead = true },
	},
	desc = "Mythic boss. Frost blasts, minions and an undead aura.",
}

tbl11.Mimic = {
	kind = "monster",
	cat = "Monsters",
	name = "Mimic",
	order = 11,
	rarity = "Secret",
	value = 2000,
	ability = { name = "Hoard King", desc = "Adventurers it kills drop 4x Coins. Holds back 4." },
	mon = {
		hp = 2000,
		dmg = 125,
		cd = 1.7,
		range = 1.6,
		attack = "melee",
		block = 4,
		goldMult = 4,
		tags = { physical = true },
	},
	desc = "SECRET. The king of all treasure chests. Its kills drop 4x Coins.",
}

tbl11.EmberDrake = {
	kind = "monster",
	cat = "Monsters",
	name = "Ember Drake",
	order = 12,
	rarity = "Rare",
	value = 220,
	dragon = true,
	ability = {
		name = "Fire Breath",
		desc = "Breathes fireballs into groups. Boosted by a Dragon Nest.",
	},
	mon = {
		hp = 150,
		dmg = 19,
		cd = 1.8,
		range = 3,
		attack = "aoe",
		splash = 1,
		block = 0,
		dtype = "fire",
		tags = { fire = true },
	},
	desc = "Studded fire dragon.",
}

tbl11.FrostDrake = {
	kind = "monster",
	cat = "Monsters",
	name = "Frost Drake",
	order = 13,
	rarity = "Epic",
	value = 380,
	dragon = true,
	ability = { name = "Frost Bolt", desc = "Icy bolts slow adventurers by 50%." },
	mon = {
		hp = 210,
		dmg = 22,
		cd = 1.65,
		range = 3.5,
		attack = "ranged",
		slowOnHit = 0.5,
		block = 0,
		dtype = "magic",
		tags = { dragon = true },
	},
	desc = "Ice dragon.",
}

tbl11.StormDrake = {
	kind = "monster",
	cat = "Monsters",
	name = "Storm Drake",
	order = 14,
	rarity = "Legendary",
	value = 750,
	dragon = true,
	ability = { name = "Ball Lightning", desc = "A lightning orb strikes clustered adventurers." },
	mon = {
		hp = 380,
		dmg = 38,
		cd = 1.55,
		range = 3.7,
		attack = "aoe",
		splash = 1.5,
		block = 0,
		dtype = "magic",
		tags = { dragon = true },
	},
	desc = "Storm dragon.",
}

tbl11.GraveSentinel = {
	kind = "monster",
	cat = "Monsters",
	name = "Grave Sentinel",
	order = 15,
	rarity = "Uncommon",
	value = 115,
	pack = "Knight",
	weapon = "Halberd",
	ability = { name = "Hold the Line", desc = "A halberd guard that holds back 2 adventurers." },
	mon = {
		hp = 170,
		dmg = 11,
		cd = 1.25,
		range = 1.6,
		attack = "melee",
		block = 2,
		tags = { undead = true, physical = true },
	},
	desc = "A polearm guard that holds two adventurers.",
}

tbl11.HexArcher = {
	kind = "monster",
	cat = "Monsters",
	name = "Hex Archer",
	order = 16,
	rarity = "Epic",
	value = 290,
	pack = "Vampire",
	weapon = "ElvenBow",
	ability = { name = "Cursed Arrow", desc = "Long-range cursed arrows (4.2 tiles)." },
	mon = {
		hp = 90,
		dmg = 24,
		cd = 1.4,
		range = 4.2,
		attack = "ranged",
		block = 0,
		dtype = "magic",
		tags = { undead = true },
	},
	desc = "A robed archer with long-range cursed arrows.",
}

tbl11.EliteKnight = {
	kind = "monster",
	cat = "Monsters",
	name = "Elite Knight",
	order = 17,
	rarity = "Epic",
	value = 320,
	pack = "Knight",
	weapon = "Morningstar",
	shield = "Heater",
	ability = { name = "Crushing Blows", desc = "Every 3rd mace hit deals 200% damage. Holds back 3." },
	mon = {
		hp = 460,
		dmg = 18,
		cd = 1.1,
		range = 1.5,
		attack = "melee",
		block = 3,
		heavy = 3,
		tags = { physical = true },
	},
	desc = "A veteran in horned plate armor with a spiked mace. Holds 3 adventurers.",
}

tbl11.RoyalKnight = {
	kind = "monster",
	cat = "Monsters",
	name = "Royal Knight",
	order = 18,
	rarity = "Legendary",
	value = 720,
	pack = "Knight",
	weapon = "Longsword",
	shield = "Heater",
	ability = { name = "Royal Command", desc = "Nearby physical units deal +20% damage. Holds back 3." },
	mon = {
		hp = 680,
		dmg = 26,
		cd = 1.05,
		range = 1.6,
		attack = "melee",
		block = 3,
		aura = { physical = 1.2, radius = 3 },
		tags = { physical = true },
	},
	desc = "The king's own guard in gilded plate. Inspires the units around it.",
}

tbl11.DreadKnight = {
	kind = "monster",
	cat = "Monsters",
	name = "Dread Knight",
	order = 19,
	rarity = "Mythic",
	value = 1500,
	pack = "Knight",
	weapon = "WarMaul",
	ability = {
		name = "Dread Cleave",
		desc = "Every swing hits all nearby adventurers and slows them 30%. Holds back 4.",
	},
	mon = {
		hp = 950,
		dmg = 42,
		cd = 1.35,
		range = 1.7,
		attack = "melee",
		cleave = true,
		block = 4,
		slowOnHit = 0.3,
		tags = { physical = true, undead = true },
	},
	desc = "Cursed black-and-crimson plate with great horns. Cleaves and slows.",
}

tbl11.ArrowTower = {
	kind = "trap",
	cat = "Buildings",
	sub = "Towers",
	name = "Ballista Tower",
	order = 43,
	rarity = "Rare",
	value = 170,
	roll = 2,
	trap = { mode = "line", dmg = 30, cd = 1.4, len = 5, dtype = "physical" },
	desc = "Stone watchtower with a ballista. Shoots down a 5-tile lane; rotate to aim.",
}

tbl11.FrostObelisk = {
	kind = "trap",
	cat = "Buildings",
	sub = "Towers",
	name = "Frost Obelisk",
	order = 44,
	rarity = "Epic",
	value = 240,
	roll = 2,
	trap = { mode = "line", dmg = 20, cd = 1.5, len = 4, dtype = "magic", root = 0.65 },
	desc = "A crystal tower that briefly freezes targets along a 4-tile lane.",
}

tbl11.FlameSpire = {
	kind = "trap",
	cat = "Buildings",
	sub = "Towers",
	name = "Flame Spire",
	order = 45,
	rarity = "Legendary",
	value = 350,
	roll = 1,
	trap = { mode = "line", dmg = 42, cd = 2.2, len = 4, dtype = "fire", burn = 8, burnDur = 3 },
	desc = "A brazier tower that launches fire down a lane. Combines with Oil Traps.",
}

tbl11.DragonNest = {
	kind = "floor",
	cat = "Buildings",
	sub = "Rooms",
	name = "Dragon Nest",
	order = 18,
	rarity = "Rare",
	value = 120,
	roll = 4,
	edges = {},
	buff = { monsterHp = 1.3, fire = 1.25 },
	desc = "A stone nest with dragon eggs. Occupants get +30% health; fire attacks gain +25% damage.",
}

tbl11.SpikedBarricade = {
	kind = "utility",
	cat = "Buildings",
	sub = "Decor",
	name = "Spiked Barricade",
	order = 46,
	rarity = "Uncommon",
	value = 80,
	roll = 3,
	util = { door = 280 },
	desc = "Sharpened timber stakes hold adventurers until they break through.",
}

local str1 = "FrostDrake"
for k21, v20 in ipairs({ "EmberDrake", str1, "StormDrake" }) do
	tbl11[v20].footprint = { 2, 2 }
	tbl11[v20].modelScale = 1.45
	local var35 = tbl11[v20]
	local var36 = var35.desc .. " Occupies a 2 x 2 area of open dungeon floor."
	var35.desc = var36
end

local str2 = "DuskBat"
local tbl12 = {
	SewerRat = {
		name = "Sewer Rat",
		rarity = "Common",
		price = 3,
		hp = 48,
		dmg = 7,
		cd = 0.65,
		range = 1.3,
		attack = "melee",
		block = 1,
		scale = 1,
		footprint = { 1, 1 },
		desc = "A quick biting defender. Holds back 1 adventurer.",
	},
	DuskBat = {
		name = "Dusk Bat",
		rarity = "Uncommon",
		price = 45,
		hp = 55,
		dmg = 10,
		cd = 0.8,
		range = 2.6,
		attack = "ranged",
		block = 0,
		scale = 1,
		footprint = { 1, 1 },
		desc = "A hovering bat that strikes adventurers from range.",
	},
	WidowSpider = {
		name = "Widow Spider",
		rarity = "Rare",
		price = 850,
		hp = 220,
		dmg = 18,
		cd = 1.05,
		range = 1.6,
		attack = "melee",
		block = 2,
		slow = 0.35,
		scale = 1,
		footprint = { 2, 2 },
		desc = "Web-coated bites slow targets by 35%. Occupies 2 x 2 tiles.",
	},
	SporeShaman = {
		name = "Spore Shaman",
		rarity = "Rare",
		price = 950,
		hp = 110,
		dmg = 20,
		cd = 1.8,
		range = 3.2,
		attack = "aoe",
		splash = 1.2,
		dtype = "magic",
		block = 0,
		scale = 1,
		footprint = { 1, 1 },
		desc = "Casts bursting spores that damage nearby adventurers.",
	},
	AmethystGolem = {
		name = "Amethyst Golem",
		rarity = "Epic",
		price = 4500,
		hp = 1050,
		dmg = 30,
		cd = 1.8,
		range = 1.8,
		attack = "melee",
		block = 4,
		cleave = true,
		scale = 1,
		footprint = { 2, 2 },
		desc = "A crystal guardian with sweeping punches. Holds back 4. Occupies 2 x 2 tiles.",
	},
	Ironhorn = {
		name = "Ironhorn Minotaur",
		rarity = "Legendary",
		price = 9000,
		hp = 920,
		dmg = 46,
		cd = 1.4,
		range = 1.9,
		attack = "melee",
		block = 4,
		cleave = true,
		heavy = 4,
		scale = 1,
		footprint = { 2, 2 },
		desc = "Axe cleaves hit multiple foes; every 4th hit deals double damage. Occupies 2 x 2 tiles.",
	},
	FrostwingDrake = {
		name = "Frostwing Drake",
		rarity = "Mythic",
		price = 18000,
		hp = 900,
		dmg = 62,
		cd = 1.7,
		range = 4.2,
		attack = "aoe",
		splash = 1.7,
		dtype = "magic",
		block = 0,
		slow = 0.5,
		scale = 1,
		footprint = { 3, 2 },
		dragon = true,
		desc = "Frost breath chills groups of adventurers by 50%. Occupies 3 x 2 tiles.",
	},
	AbyssalDragon = {
		name = "Abyssal Dragon",
		rarity = "Secret",
		price = 30000,
		hp = 1650,
		dmg = 108,
		cd = 2.2,
		range = 4.5,
		attack = "aoe",
		splash = 2,
		dtype = "magic",
		block = 0,
		scale = 1,
		footprint = { 3, 3 },
		dragon = true,
		desc = "Devastating abyssal breath blasts a wide area. Occupies 3 x 3 tiles.",
	},
}

local num1 = 50
for k22, v21 in ipairs({
	"SewerRat",
	str2,
	"WidowSpider",
	"SporeShaman",
	"AmethystGolem",
	"Ironhorn",
	"FrostwingDrake",
	"AbyssalDragon",
}) do

	local var37 = tbl12[v21]
	num1 = num1 + 1
	local tbl13 = {
		kind = "monster",
		cat = "Monsters",
		name = var37.name,
		order = num1,
		rarity = var37.rarity,
		value = var37.price,
		modelScale = var37.scale,
		footprint = var37.footprint,
		dragon = var37.dragon,
		creature = true,
		desc = var37.desc,
	}

	local tbl14 = {}
	local var38
	if var37.attack == "aoe" then
		var38 = "Area Attack"
	else
		if var37.cleave then
			var38 = "Cleave"
		else
			var38 = (function() if var37.slow then return "Slowing Bite" else return "Natural Fighter" end end)()
		end
	end

	tbl14.name = var38
	tbl14.desc = var37.desc
	tbl13.ability = tbl14
	tbl13.mon = {
		hp = var37.hp,
		dmg = var37.dmg,
		cd = var37.cd,
		range = var37.range,
		attack = var37.attack,
		block = var37.block,
		splash = var37.splash,
		dtype = var37.dtype,
		slowOnHit = var37.slow,
		cleave = var37.cleave,
		heavy = var37.heavy,
		tags = { physical = var37.dtype == nil, dragon = var37.dragon == true },
	}

	tbl11[v21] = tbl13
	tbl2.UnitPriceById[v21] = var37.price
end

local tbl15 = {
	"MagmaElemental",
	{
		name = "Magma Elemental",
		rarity = "Rare",
		value = 240,
		creature = true,
		footprint = { 1, 1 },
		price = 950,
		ability = { name = "Lava Burst", desc = "Hurls molten rock that splashes nearby adventurers." },
		mon = {
			hp = 280,
			dmg = 21,
			cd = 1.7,
			range = 3,
			attack = "aoe",
			splash = 1.3,
			dtype = "magic",
			block = 1,
			tags = { fire = true },
		},
		desc = "Living rock and lava. Molten blasts splash nearby adventurers.",
	},
}

local tbl16 = {
	"FrostRevenant",
	{
		name = "Frost Revenant",
		rarity = "Rare",
		value = 260,
		pack = "Knight",
		weapon = "GlacierSpear",
		price = 1100,
		ability = { name = "Frozen Spear", desc = "Spear hits slow adventurers by 30%. Holds back 2." },
		mon = {
			hp = 300,
			dmg = 20,
			cd = 1.15,
			range = 1.9,
			attack = "melee",
			block = 2,
			slowOnHit = 0.3,
			tags = { undead = true, physical = true },
		},
		desc = "A knight frozen in cursed ice. Spear hits slow adventurers by 30%.",
	},
}

for k23, v22 in ipairs({
	{
		"BoneGhoul",
		{
			name = "Bone Ghoul",
			rarity = "Common",
			value = 22,
			pack = "Zombie",
			weapon = "BoneClaws",
			dual = true,
			price = 4,
			ability = { name = "Frenzy", desc = "Rakes adventurers with fast twin claws." },
			mon = {
				hp = 85,
				dmg = 8,
				cd = 0.85,
				range = 1.4,
				attack = "melee",
				block = 1,
				tags = { undead = true, physical = true },
			},
			desc = "A starving ghoul with bone claws. Fast twin strikes. Undead.",
		},
	},
	{
		"ImpTrickster",
		{
			name = "Imp Trickster",
			rarity = "Uncommon",
			value = 70,
			pack = "Werewolf",
			weapon = "Hellfork",
			modelScale = 0.62,
			price = 45,
			ability = { name = "Hot Pokes", desc = "Every 4th jab deals double damage." },
			mon = {
				hp = 70,
				dmg = 12,
				cd = 0.8,
				range = 1.7,
				attack = "melee",
				block = 1,
				heavy = 4,
				tags = { physical = true },
			},
			desc = "A cackling little demon with a red-hot fork. Every 4th jab deals double damage.",
		},
	},
	{
		"DireWolf",
		{
			name = "Dire Wolf",
			rarity = "Uncommon",
			value = 75,
			creature = true,
			footprint = { 1, 1 },
			price = 50,
			ability = { name = "Pack Hunter", desc = "Quick bites. Holds back 2 adventurers." },
			mon = {
				hp = 130,
				dmg = 11,
				cd = 0.7,
				range = 1.4,
				attack = "melee",
				block = 2,
				tags = { physical = true },
			},
			desc = "A snarling cave wolf with quick bites. Holds back 2 adventurers.",
		},
	},
	tbl15,
	tbl16,
	{
		"VampireLord",
		{
			name = "Vampire Lord",
			rarity = "Epic",
			value = 380,
			pack = "Vampire",
			weapon = "BloodRapier",
			price = 4200,
			ability = { name = "Blood Pact", desc = "Nearby undead deal +25% damage. Holds back 2." },
			mon = {
				hp = 420,
				dmg = 36,
				cd = 1.05,
				range = 1.6,
				attack = "melee",
				block = 2,
				aura = { undead = 1.25, radius = 3 },
				tags = { undead = true, physical = true },
			},
			desc = "An ancient noble of the night. Nearby undead deal +25% damage.",
		},
	},
	{
		"SwampTroll",
		{
			name = "Swamp Troll",
			rarity = "Epic",
			value = 420,
			creature = true,
			footprint = { 2, 2 },
			price = 4800,
			ability = { name = "Club Sweep", desc = "Club swings hit every nearby adventurer. Holds back 5." },
			mon = {
				hp = 1300,
				dmg = 30,
				cd = 1.75,
				range = 2,
				attack = "melee",
				block = 5,
				cleave = true,
				tags = { physical = true },
			},
			desc = "A huge mossy brute. Club sweeps hit all nearby foes and it holds back 5. Occupies 2 x 2 tiles.",
		},
	},
	{
		"InfernalWarlord",
		{
			name = "Infernal Warlord",
			rarity = "Legendary",
			value = 850,
			pack = "Knight",
			weapon = "HellfireCleaver",
			modelScale = 1,
			price = 9800,
			ability = {
				name = "Hellfire Cleave",
				desc = "Cleaves every nearby adventurer; every 3rd swing deals double damage.",
			},
			mon = {
				hp = 1050,
				dmg = 56,
				cd = 1.3,
				range = 1.9,
				attack = "melee",
				block = 3,
				cleave = true,
				heavy = 3,
				tags = { physical = true, fire = true },
			},
			desc = "A towering demon general. Cleaves all nearby foes; every 3rd swing deals double damage.",
		},
	},
	{
		"VenomHydra",
		{
			name = "Venom Hydra",
			rarity = "Mythic",
			value = 1400,
			creature = true,
			footprint = { 2, 2 },
			price = 19500,
			ability = {
				name = "Triple Venom",
				desc = "Three heads spit venom that splashes and slows adventurers by 25%.",
			},
			mon = {
				hp = 1150,
				dmg = 68,
				cd = 1.8,
				range = 4,
				attack = "aoe",
				splash = 1.8,
				dtype = "magic",
				block = 1,
				slowOnHit = 0.25,
				tags = {},
			},
			desc = "Three heads spit splashing venom that slows adventurers by 25%. Occupies 2 x 2 tiles.",
		},
	},
	{
		"VoidReaper",
		{
			name = "Void Reaper",
			rarity = "Secret",
			value = 2400,
			pack = "Levitation",
			weapon = "AbyssalScythe",
			modelScale = 1,
			price = 32000,
			ability = {
				name = "Abyssal Harvest",
				desc = "Void sweeps blast a wide area. Nearby undead deal +30% damage.",
			},
			mon = {
				hp = 1500,
				dmg = 125,
				cd = 1.9,
				range = 3.3,
				attack = "aoe",
				splash = 1.6,
				dtype = "magic",
				block = 2,
				aura = { undead = 1.3, radius = 4 },
				boss = true,
				tags = { undead = true },
			},
			desc = "SECRET. A reaper from beyond the dungeon. Void sweeps blast wide areas; undead nearby deal +30% damage.",
		},
	},
}) do

	local var39 = v22[2]
	var39.kind = "monster"
	var39.cat = "Monsters"
	var39.order = 60 + k23
	local var40 = v22[1]
	tbl2.UnitPriceById[var40] = var39.price
	var39.price = nil
	tbl11[var40] = var39
end

tbl11.PotionShop = {
	kind = "floor",
	cat = "Buildings",
	sub = "Rooms",
	name = "Potion Shop",
	rarity = "Rare",
	roll = 2,
	order = 12,
	edges = {},
	value = 160,
	shop = { stop = 2, heal = 0.15, gold = 1.5, chance = 0.7, maxBuys = 2 },
	desc = "Adventurers walking through may stop for 2s to buy a potion. Every sale pays you Coins, but the potion heals them 15%. Each adventurer buys at most 2 potions.",
}

tbl11.Healer = {
	kind = "monster",
	cat = "Monsters",
	name = "Grove Healer",
	order = 71,
	rarity = "Rare",
	value = 230,
	creature = true,
	footprint = { 1, 1 },
	modelScale = 1,
	ability = {
		name = "Mending Light",
		desc = "Every 3s heals the most hurt unit within 3 tiles for 12% of its health.",
	},
	mon = {
		hp = 180,
		dmg = 8,
		cd = 1.6,
		range = 3,
		attack = "ranged",
		dtype = "magic",
		block = 0,
		heal = { amt = 0.12, cd = 3, radius = 3 },
		tags = { support = true },
	},
	desc = "Support. Every 3s heals the most hurt unit within 3 tiles for 12% of its health.",
}

tbl11.BriarWolf = {
	kind = "monster",
	cat = "Monsters",
	name = "Briar Wolf",
	order = 92,
	rarity = "Epic",
	value = 480,
	price = 5200,
	creature = true,
	labOnly = true,
	footprint = { 1, 1 },
	modelScale = 1,
	ability = {
		name = "Thorn Pounce",
		desc = "Quick bites; every 4th bite deals double damage. Labyrinth exclusive.",
	},
	mon = {
		hp = 980,
		dmg = 34,
		cd = 1,
		range = 1.6,
		attack = "melee",
		heavy = 4,
		block = 2,
		tags = { physical = true },
	},
	desc = "LABYRINTH. A mossy wolf grown through with thorns. Quick bites; every 4th one hits twice as hard.",
}

tbl11.JadeBasilisk = {
	kind = "monster",
	cat = "Monsters",
	name = "Jade Basilisk",
	order = 93,
	rarity = "Legendary",
	value = 1100,
	price = 11000,
	creature = true,
	labOnly = true,
	footprint = { 2, 2 },
	modelScale = 0.9,
	ability = {
		name = "Jade Venom",
		desc = "Spits venom that splashes a small area and slows adventurers by 30%. Labyrinth exclusive.",
	},
	mon = {
		hp = 1250,
		dmg = 62,
		cd = 1.6,
		range = 3.6,
		attack = "aoe",
		splash = 1.4,
		dtype = "magic",
		slowOnHit = 0.3,
		block = 2,
		tags = {},
	},
	desc = "LABYRINTH. A jade lizard king with a golden crown. Splashing venom slows adventurers. Occupies 2 x 2 tiles.",
}

tbl11.CinderColossus = {
	kind = "monster",
	cat = "Monsters",
	name = "Cinder Colossus",
	order = 94,
	rarity = "Mythic",
	value = 1800,
	price = 22000,
	creature = true,
	labOnly = true,
	footprint = { 2, 2 },
	modelScale = 0.8,
	ability = {
		name = "Magma Slam",
		desc = "Slams cleave every nearby adventurer; every 3rd slam deals double fire damage. Holds back 6.",
	},
	mon = {
		hp = 2400,
		dmg = 78,
		cleave = true,
		heavy = 3,
		cd = 1.7,
		range = 2.2,
		attack = "melee",
		block = 6,
		tags = { fire = true, physical = true },
	},
	desc = "LABYRINTH. An obsidian giant with a molten heart. Cleaves every nearby foe. Occupies 2 x 2 tiles.",
}

tbl11.EclipseArchon = {
	kind = "monster",
	cat = "Monsters",
	name = "Eclipse Archon",
	order = 95,
	rarity = "Divine",
	value = 7000,
	price = 100000,
	creature = true,
	labOnly = true,
	footprint = { 2, 2 },
	modelScale = 0.85,
	ability = {
		name = "Black Sun",
		desc = "An eclipse blasts a huge area and slows adventurers by 35%. Divine.",
	},
	mon = {
		hp = 4800,
		dmg = 330,
		cd = 1.8,
		range = 4.4,
		attack = "aoe",
		splash = 2.2,
		dtype = "magic",
		slowOnHit = 0.35,
		block = 3,
		boss = true,
		tags = { holy = true },
	},
	desc = "DIVINE. A floating knight of the black sun. Only found deep in the Labyrinth (Nightmare and Abyssal). Occupies 2 x 2 tiles.",
}

tbl11.Bard = {
	kind = "monster",
	cat = "Monsters",
	name = "Battle Bard",
	order = 72,
	rarity = "Epic",
	value = 400,
	creature = true,
	footprint = { 1, 1 },
	modelScale = 1,
	ability = {
		name = "War Drums",
		desc = "Units within 2.5 tiles attack 25% faster. Bards do not stack with each other.",
	},
	mon = {
		hp = 320,
		dmg = 10,
		cd = 1.2,
		range = 1.5,
		attack = "melee",
		block = 1,
		haste = { mult = 1.25, radius = 2.5 },
		tags = { physical = true, support = true },
	},
	desc = "Support. Beats a war drum: units within 2.5 tiles attack 25% faster. Holds back 1.",
}

tbl2.UnitPriceById.Healer = 1000
tbl2.UnitPriceById.Bard = 4200
tbl11.BannerGoblin = {
	kind = "monster",
	cat = "Monsters",
	name = "Banner Goblin",
	order = 73,
	rarity = "Rare",
	value = 150,
	creature = true,
	footprint = { 1, 1 },
	modelScale = 0.95,
	ability = {
		name = "Rally Banner",
		desc = "Does not attack. Units and traps within 2 tiles deal +15% damage.",
	},
	mon = {
		hp = 380,
		dmg = 0,
		cd = 1,
		range = 1,
		attack = "none",
		block = 1,
		support = { radius = 2, dmg = 1.15, trapDmg = 1.15, color = "FF5A4A" },
		tags = { support = true },
	},
	desc = "SUPPORT. Waves a war banner instead of fighting: units and traps within 2 tiles deal +15% damage. Holds back 1.",
}

tbl11.RuneSage = {
	kind = "monster",
	cat = "Monsters",
	name = "Rune Sage",
	order = 74,
	rarity = "Legendary",
	value = 1500,
	creature = true,
	footprint = { 1, 1 },
	modelScale = 0.95,
	ability = {
		name = "Runes of Haste",
		desc = "Does not attack. Units within 2.5 tiles deal +20% damage and attack 15% faster; traps there recharge 15% faster.",
	},
	mon = {
		hp = 650,
		dmg = 0,
		cd = 1,
		range = 1,
		attack = "none",
		block = 1,
		support = { radius = 2.5, dmg = 1.2, haste = 1.15, trapCd = 0.85, color = "62D8FF" },
		tags = { support = true },
	},
	desc = "SUPPORT. Channels runes instead of fighting: units within 2.5 tiles deal +20% damage and attack 15% faster, traps there recharge 15% faster. Holds back 1.",
}

local num2 = 1
tbl11.SpiritTotem = {
	kind = "monster",
	cat = "Monsters",
	name = "Spirit Totem",
	order = 75,
	rarity = "Mythic",
	value = 5000,
	creature = true,
	footprint = { 1, num2 },
	modelScale = 0.9,
	ability = {
		name = "Ancestor Spirits",
		desc = "Does not attack. Units within 3 tiles deal +30% damage and get +25% health; traps there deal +25% damage.",
	},
	mon = {
		hp = 1600,
		dmg = 0,
		cd = 1,
		range = 1,
		attack = "none",
		block = 2,
		support = { radius = 3, dmg = 1.3, hp = 1.25, trapDmg = 1.25, color = "3FF2D0" },
		tags = { support = true },
	},
	desc = "SUPPORT. A floating spirit totem that never attacks: units within 3 tiles deal +30% damage and get +25% health, traps there deal +25% damage. Holds back 2.",
}

tbl2.UnitPriceById.BannerGoblin = 1200
tbl2.UnitPriceById.RuneSage = 18000
tbl2.UnitPriceById.SpiritTotem = 60000
tbl11.LifeSpring = {
	kind = "floor",
	cat = "Buildings",
	sub = "Rooms",
	name = "Life Spring",
	rarity = "Rare",
	roll = 6,
	order = 17.1,
	edges = {},
	room = true,
	noObjects = true,
	shrine = { hp = 1.1 },
	desc = "SHRINE. Units on the 8 tiles around it get +10% health. Nothing can be placed on a shrine.",
}

tbl11.WarShrine = {
	kind = "floor",
	cat = "Buildings",
	sub = "Rooms",
	name = "War Shrine",
	rarity = "Epic",
	roll = 5,
	order = 17.2,
	edges = {},
	room = true,
	noObjects = true,
	shrine = { dmg = 1.2, trapDmg = 1.2 },
	desc = "SHRINE. Units and traps on the 8 tiles around it deal +20% damage. Nothing can be placed on a shrine.",
}

tbl11.RuneObelisk = {
	kind = "floor",
	cat = "Buildings",
	sub = "Rooms",
	name = "Rune Obelisk",
	rarity = "Legendary",
	roll = 4,
	order = 17.3,
	edges = {},
	room = true,
	noObjects = true,
	shrine = { haste = 1.15, trapCd = 0.8 },
	desc = "SHRINE. Units on the 8 tiles around it attack 15% faster and traps there recharge 20% faster. Nothing can be placed on a shrine.",
}

tbl11.DragonAltar = {
	kind = "floor",
	cat = "Buildings",
	sub = "Rooms",
	name = "Dragon Altar",
	rarity = "Mythic",
	roll = 3,
	order = 17.4,
	edges = {},
	room = true,
	noObjects = true,
	shrine = { dmg = 1.3, trapDmg = 1.3, hp = 1.2 },
	desc = "SHRINE. Units and traps on the 8 tiles around it deal +30% damage, units get +20% health. Nothing can be placed on a shrine.",
}

tbl2.MonsterScale = function(arg1)
	return arg1 and arg1.modelScale or 0.8
end

tbl2.RollDisplaySize = function(arg1)
	if arg1 and arg1.dragon then
		return 9.5
	end

	if arg1 and arg1.kind == "monster" then
		return 7.5
	end

	return 6.5
end

for k24, v23 in pairs(tbl11) do
	v23.id = k24
	local var41 = v23.value
	v23.value = var41 or 30
	v23.cost = 0
	if v23.kind == "monster" then
		v23.pop = tbl2.UnitPop[v23.rarity] or 1
		var41 = tbl2.UnitPriceById[k24]
		v23.price = var41 or (tbl2.UnitPrice[v23.rarity] or 3)
		if v23.mon.attack == "melee" then
			var41 = "Melee"
		else
			var41 = (function() if v23.mon.dtype == "magic" then return "Magic" else return "Ranged" end end)()
		end

		v23.range = var41
	else
		if not v23.rarity then
			goto L25
		end

		v23.price = tbl2.BuildPrice[v23.rarity] or 60
	end
::L25:: end

tbl2.OfferPrice = function(arg1, arg2)
	local var1 = tbl11[arg1]
	return (math.max(1, (math.floor((var1 and var1.price or 1) * (1 - (arg2 or 0)) + 0.5))))
end

tbl2.SummonPrice = function(arg1)
	local var1 = tbl11[arg1]
	local var2 = arg1
	return var1 and var1.value or 50, tbl2.OfferPrice(var2)
end

tbl2.IsWalkPiece = function(arg1)
	local bool2 = false
	if arg1 ~= nil then
		bool2 = true
		if arg1.kind ~= "floor" then
			bool2 = arg1.kind == "special"
		end
	end

	return bool2
end

tbl2.Minion = {
	id = "Minion",
	name = "Skeleton Minion",
	pack = "Zombie",
	weapon = "RustyDagger",
	mon = {
		hp = 40,
		dmg = 6,
		cd = 1,
		range = 1.4,
		attack = "melee",
		block = 1,
		tags = { undead = true, physical = true },
	},
	life = 14,
}

tbl2.UpgradeCost = function(arg1, arg2)
	return (math.floor(arg1.value * 0.9 * arg2))
end

tbl2.LevelMult = function(arg1)
	return (arg1 - 1) * 0.45 + 1
end

tbl2.UNIT_MAX_LEVEL = 10
tbl2.UNIT_MAX_STARS = 5
tbl2.STAR_COPIES = 3
tbl2.UnitXPNeed = function(arg1)
	return (math.floor(arg1 ^ 1.35 * 100))
end

tbl2.UnitLevelCost = function(arg1, arg2)
	return (math.max(1, (math.floor((arg1.price or 1) * (arg2 * 0.9 + 0.8)))))
end

tbl2.UnitMult = function(arg1, arg2)
	return (1 + ((arg1 or 1) - 1) * 0.18) * (1 + (arg2 or 0) * 0.2)
end

tbl2.UnitPower = function(arg1, arg2, arg3)
	local var1 = arg1.mon
	local var2 = var1.dmg / var1.cd
	local var4 = var2 * ((function() if var1.cleave then return 2 else return 1 end end)())
	var2 = (var4 * ((function() if var1.splash then return 1.6 else return 1 end end)()) * 12 + var1.hp * 0.5 + var1.block * 25) * tbl2.UnitMult(arg2, arg3)
	return (math.floor(var2))
end

tbl2.StarterInventory = { SpikeTrap = 3 }
tbl2.StarterMonsters = {}
tbl2.Skills = { {
	id = "Heart",
	q = 0,
	r = 0,
	name = "Dungeon Heart",
	cost = 0,
	icon = "Crown",
	desc = "The heart of your power. Every path starts here.",
	title = "Dungeon Upgrades",
} }

local tbl17 = { 300, 1200, 4000, 12000, 35000, 90000 }
local num3 = 0
local str3 = "spine"
local function describe(arg1)
	local var3, var4 = next(arg1)
	if var3 == nil then
		return ""
	end

	if var3 == "pop" then
		return "+" .. var4 .. " unit population."
	end

	if var3 == "crystal" then
		return "+" .. var4 .. " Crystal health."
	end

	if var3 == "luck" then
		return "+" .. var4 .. "% roll luck on both stands."
	end

	if var3 == "walk" then
		return "+" .. var4 .. " walk speed."
	end

	if var3 == "offlineHours" then
		return "Store " .. var4 .. " more hours of offline earnings."
	end

	if var3 == "auto" then
		return "Unlocks AUTO: the next wave starts by itself after a win."
	end

	if var3 == "speed" then
		return "Unlocks 2x wave speed."
	end

	if var3 == "mutLuck" then
		return "+" .. math.round(var4 * 100) .. "% chance to roll mutated units."
	end

	if var3 == "mutPower" then
		return "+" .. math.round(var4 * 100) .. "% health and damage for mutated units."
	end

	local var5 = ({
		gold = "Coins from every source",
		souls = "Dark Souls from kills",
		unitDmg = "damage for all your units",
		unitHp = "health for all your units",
		trapDmg = "trap damage",
		heroDmg = "damage with your own weapon",
		discount = "off every stand offer",
		offline = "offline earnings",
		drop = "weapon drop chance",
		bossDmg = "damage against bosses",
		waveGold = "Coins for every wave you clear",
	})[var3] or var3

	return ((function() if var3 == "discount" then return "" else return "+" end end)()) .. math.round(var4 * 100) .. "% " .. var5 .. "."
end

var38 = {}
var38[3] = {
	early = { "MutSense1", "Mutation Sense I", "Clover", { mutLuck = 0.1 } },
	right = { "MutSense2", "Mutation Sense II", "Clover", { mutLuck = 0.15 } },
	left = { "MutSense3", "Mutation Sense III", "Clover", { mutLuck = 0.25 } },
}

local str4 = "Mutant Might III"
local str5 = "SkullSword"
var38[4] = {
	early = { "MutMight1", "Mutant Might I", "SkullSword", { mutPower = 0.1 } },
	right = { "MutMight2", "Mutant Might II", "SkullSword", { mutPower = 0.15 } },
	left = { "MutMight3", str4, str5, { mutPower = 0.25 } },
}

local tbl18 = { { 0, -1 }, { 1, -1 }, { 1, 0 }, { 0, 1 }, { -1, 1 }, { -1, 0 } }
local function add(arg1, arg2, arg3, arg4, arg5)
	local var1 = arg1[5]
	local tbl1 = {
		id = arg1[1],
		name = arg1[2],
		icon = arg1[3],
		fx = arg1[4],
		q = arg2,
		r = arg3,
		parent = arg4,
		cost = var1 or tbl17[arg5],
		fixedCost = arg1[5] ~= nil,
	}

	tbl1.arm = num3
	tbl1.side = str3
	tbl1.desc = describe(tbl1.fx)
	table.insert(tbl2.Skills, tbl1)
	return tbl1.id
end

for k25, v24 in ipairs({
	{
		spine = {
			{ "Auto", "Auto Battle", "Swords", { auto = true }, 350 },
			{ "Rally", "Battle Cry", "Swords", { unitDmg = 0.1 } },
			{ "Hero1", "Hero Strength I", "Sword", { heroDmg = 0.25 } },
			{ "Hero2", "Hero Strength II", "Sword", { heroDmg = 0.5 } },
			{ "Hero3", "Champion's Might", "Crown", { heroDmg = 1 } },
		},
		right = {
			{ "Boots", "Swift Boots", "Boots", { walk = 4 } },
			{ "Boots2", "Windwalker", "Boots", { walk = 4 } },
			{ "Boss1", "Boss Slayer I", "SkullSword", { bossDmg = 0.15 } },
			{ "Boss2", "Boss Slayer II", "SkullSword", { bossDmg = 0.3 } },
		},
		left = {
			{ "Hero4", "Duelist", "Sword", { heroDmg = 0.25 } },
			{ "Hero5", "Berserker", "Swords", { heroDmg = 0.35 } },
			{ "Loot1", "Loot Finder I", "Chest", { drop = 0.25 } },
			{ "Hero6", "Weapon Master", "Sword", { heroDmg = 0.75 } },
		},
	},
	{
		spine = {
			{ "Gold1", "Gold Rush I", "Coin", { gold = 0.1 } },
			{ "Gold2", "Gold Rush II", "Coin", { gold = 0.15 } },
			{ "Treasure", "Treasure Hunter", "Chest", { gold = 0.2 } },
			{ "Gold3", "Golden Touch", "Coin", { gold = 0.25 } },
			{ "Gold4", "Midas Crown", "Crown", { gold = 0.4 } },
		},
		right = {
			{ "Bargain", "Bargain Hunter", "Lock", { discount = 0.1 } },
			{ "Bargain2", "Master Haggler", "Lock", { discount = 0.1 } },
			{ "Bounty1", "Wave Bounty I", "Coin", { waveGold = 0.25 } },
			{ "Bounty2", "Wave Bounty II", "Chest", { waveGold = 0.5 } },
		},
		left = {
			{ "Offline1", "Sleeping Treasury I", "Chest", { offline = 0.25 } },
			{ "Offline2", "Sleeping Treasury II", "Chest", { offline = 0.5 } },
			{ "OfflineHours1", "Longer Rest", "Chest", { offlineHours = 2 } },
			{ "OfflineHours2", "Deep Slumber", "Chest", { offlineHours = 4 } },
		},
	},
	{
		spine = {
			{ "Soul1", "Soul Harvest I", "Soul", { souls = 0.15 } },
			{ "Luck1", "Lucky Charm I", "Clover", { luck = 1 } },
			{ "Soul2", "Soul Harvest II", "Soul", { souls = 0.25 } },
			{ "Luck2", "Lucky Charm II", "Clover", { luck = 2 } },
			{ "Soul3", "Soul Reaper", "Soul", { souls = 0.4 } },
		},
		right = {
			{ "Luck3", "Four-Leaf Clover", "Clover", { luck = 1 } },
			{ "Luck4", "Rainbow Luck", "Clover", { luck = 3 } },
			{ "Soul4", "Soul Siphon", "Soul", { souls = 0.2 } },
			{ "Luck5", "Fortune's Favor", "Clover", { luck = 3 } },
		},
		left = {
			{ "Loot2", "Grave Robber", "Chest", { drop = 0.25 } },
			{ "Soul5", "Dark Pact", "Soul", { souls = 0.2 } },
			{ "Loot3", "Relic Hunter", "Chest", { drop = 0.5 } },
			{ "Soul6", "Soul Well", "Soul", { souls = 0.3 } },
		},
	},
	{
		spine = {
			{ "Dmg1", "Unit Damage I", "SkullSword", { unitDmg = 0.1 } },
			{ "Dmg2", "Unit Damage II", "SkullSword", { unitDmg = 0.15 } },
			{ "Dmg3", "Unit Damage III", "SkullSword", { unitDmg = 0.2 } },
			{ "Dmg4", "Unit Damage IV", "SkullSword", { unitDmg = 0.25 } },
			{ "Dmg5", "Warlord", "Crown", { unitDmg = 0.5 } },
		},
		right = {
			{ "Crystal1", "Crystal Ward I", "Gem", { crystal = 25 } },
			{ "Crystal2", "Crystal Ward II", "Gem", { crystal = 50 } },
			{ "Crystal3", "Crystal Ward III", "Gem", { crystal = 100 } },
			{ "Crystal4", "Crystal Bastion", "Gem", { crystal = 200 } },
		},
		left = {
			{ "Boss3", "Giant Killer", "SkullSword", { bossDmg = 0.2 } },
			{ "Boss4", "Executioner", "SkullSword", { bossDmg = 0.3 } },
			{ "Dmg6", "Bloodlust", "Swords", { unitDmg = 0.2 } },
			{ "Dmg7", "Rampage", "Swords", { unitDmg = 0.3 } },
		},
	},
	{
		spine = {
			{ "Pop1", "Population I", "Pop", { pop = 5 } },
			{ "Pop2", "Population II", "Pop", { pop = 10 } },
			{ "Pop3", "Population III", "Pop", { pop = 15 } },
			{ "Pop4", "Population IV", "Pop", { pop = 25 } },
			{ "Pop5", "Population V", "Crown", { pop = 40 } },
		},
		right = {
			{ "Hp1", "Unit Health I", "Heart", { unitHp = 0.1 } },
			{ "Hp2", "Unit Health II", "Heart", { unitHp = 0.15 } },
			{ "Hp3", "Unit Health III", "Heart", { unitHp = 0.2 } },
			{ "Hp4", "Unit Health IV", "Heart", { unitHp = 0.3 } },
		},
		left = {
			{ "Pop6", "Barracks", "Pop", { pop = 20 } },
			{ "Pop7", "War Camp", "Pop", { pop = 30 } },
			{ "Pop8", "Legion", "Pop", { pop = 50 } },
			{ "Pop9", "Endless Horde", "Crown", { pop = 100 } },
		},
	},
	{
		spine = {
			{ "Trap1", "Trap Mastery I", "Potion", { trapDmg = 0.1 } },
			{ "Trap2", "Trap Mastery II", "Potion", { trapDmg = 0.15 } },
			{ "Trap3", "Trap Mastery III", "Potion", { trapDmg = 0.2 } },
			{ "Trap4", "Trap Mastery IV", "Potion", { trapDmg = 0.25 } },
			{ "Trap5", "Trap Lord", "Crown", { trapDmg = 0.5 } },
		},
		right = {
			{ "Hp5", "Iron Hide I", "Heart", { unitHp = 0.15 } },
			{ "Hp6", "Iron Hide II", "Heart", { unitHp = 0.2 } },
			{ "Hp7", "Stoneskin", "Heart", { unitHp = 0.25 } },
			{ "Hp8", "Undying", "Heart", { unitHp = 0.4 } },
		},
		left = {
			{ "Crystal5", "Crystal Heart", "Gem", { crystal = 100 } },
			{ "Trap6", "Spiked Walls", "Potion", { trapDmg = 0.3 } },
			{ "Trap7", "Death Maze", "Potion", { trapDmg = 0.4 } },
			{ "Crystal6", "Crystal Fortress", "Gem", { crystal = 150 } },
		},
	},
}) do

	num3 = k25
	str3 = "spine"
	local var42 = tbl18[k25]
	local var43 = tbl18[k25 % 6 + 1]
	local var44 = tbl18[(k25 - 2) % 6 + 1]
	local tbl19 = {}
	for i1 = 1, 5 do
		local var45 = add
		local var46 = v24.spine[i1]
		local var47 = var42[1] * i1
		local var48 = var42[2] * i1
		var45 = var45(var46, var47, var48, (function() if i1 == 1 then return "Heart" else return tbl19[i1 - 1] end end)(), i1)
		tbl19[i1] = var45
	end

	local var49 = v24.right
	local var50 = v24.left
	for k26, v25 in ipairs({ var49, var50 }) do
		local var51 = k26 == 1 and var43 or var44
		add(v25[2], var42[1] * 3 + var51[1] * 2, var42[2] * 3 + var51[2] * 2, add(v25[1], var42[1] * 3 + var51[1] * 1, var42[2] * 3 + var51[2] * 1, tbl19[3], 4), 5)
		add(v25[4], var42[1] * 5 + var51[1] * 1, var42[2] * 5 + var51[2] * 1, tbl19[5], 6)
		local var52 = var38[k25]
		if not var52 then
			goto L28
		end

		str3 = "mutation"
		local function at(arg1, arg2)
			return var42[1] * arg1 + var51[1] * arg2, var42[2] * arg1 + var51[2] * arg2
		end

		local var53 = add(v25[3], var42[1] * 4 + var51[1] * 1, var42[2] * 4 + var51[2] * 1, tbl19[4], 5)
		if k26 == 1 then
			add(var52.early, var42[1] * 2 + var51[1] * 1, var42[2] * 2 + var51[2] * 1, tbl19[2], 3)
		end

		add(k26 == 1 and var52.right or var52.left, var42[1] * 4 + var51[1] * 2, var42[2] * 4 + var51[2] * 2, var53, 6)
	::L28:: end
end

add({ "Speed2x", "Battle Speed", "Boots", { speed = true }, 1000 }, tbl18[1][1] + tbl18[2][1], tbl18[1][2] + tbl18[2][2], "Auto", 2)
add({ "Speed3x", "3x Battle Speed", "Boots", {}, 0 }, tbl18[1][1] + tbl18[2][1] + 1, tbl18[1][2] + tbl18[2][2] - 1, "Speed2x", 3)
local var54 = tbl2.Skills[#tbl2.Skills]
var54.pass = "BattleSpeed"
var54.desc = "Unlocks 3x wave speed. Bought with Robux (the 3x Battle Speed game pass)."
tbl2.SkillById = {}
str3 = "right"
for k27, v26 in ipairs(tbl2.Skills) do
	tbl2.SkillById[v26.id] = v26
end

str3 = { 1, -1 }
add = { -1, 1 }
tbl18 = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, str3, add }
tbl2.SkillNeighbours = function(arg1)
	local tbl1 = {}
	for k1, v1 in ipairs(tbl18) do
		for k2, v2 in ipairs(tbl2.Skills) do
			if v2.q ~= arg1.q + v1[1] then
				goto L31
			end

			if v2.r ~= arg1.r + v1[2] then
				goto L31
			end

			table.insert(tbl1, v2)
		::L31:: end
	end

	return tbl1
end

tbl2.SkillBuyable = function(arg1, arg2)
	if arg1[arg2.id] then
		return false
	end

	if arg2.parent then
		local bool1 = true
		if arg1[arg2.parent] ~= true then
			bool1 = arg2.parent == "Heart"
		end

		return bool1
	end

	local var1 = arg2
	for k1, v1 in ipairs(tbl2.SkillNeighbours(var1)) do
		if not arg1[v1.id] then
			goto L32
		end

		do return true
	 end ::L32:: end

	return false
end

tbl2.SkillChildren = function(arg1)
	local tbl1 = {}
	for k1, v1 in ipairs(tbl2.Skills) do
		if v1.parent ~= arg1.id then
			goto L33
		end

		table.insert(tbl1, v1)
	::L33:: end

	return tbl1
end

tbl2.SkillFx = function(arg1)
	local var1 = arg1
	local tbl1 = {
		gold = 0,
		souls = 0,
		unitHp = 0,
		unitDmg = 0,
		trapDmg = 0,
		pop = 0,
		luck = 0,
		crystal = 0,
		heroDmg = 0,
		walk = 0,
		drop = 0,
		discount = 0,
		bossDmg = 0,
		waveGold = 0,
	}

	for k1 in pairs(var1 or {}) do
		local var2 = tbl2.SkillById[k1]
		if not var2 then
			goto L34
		end

		if not var2.fx then
			goto L34
		end

		for k2, v1 in pairs(var2.fx) do
			if type(v1) == "number" then
				local var3 = (tbl1[k2] or 0) + v1
				tbl1[k2] = var3
			else
				tbl1[k2] = v1
			end
		end
	::L34:: end

	return tbl1
end

tbl17 = {}
tbl2.Enemies = tbl17
tbl17.Peasant = {
	name = "Adventurer",
	hp = 32,
	speed = 9,
	dmg = 4,
	cd = 1,
	core = 5,
	gold = 5,
	souls = 1,
	route = "greedy",
	pack = "Cartoony",
	weapon = "Pitchfork",
}

tbl17.Swordsman = {
	name = "Swordsman",
	hp = 60,
	speed = 8.5,
	dmg = 7,
	cd = 1,
	core = 8,
	gold = 8,
	souls = 1,
	pack = "Stylish",
	weapon = "IronSword",
	shield = "Round",
}

tbl17.Ranger = {
	name = "Ranger",
	hp = 42,
	speed = 9,
	dmg = 6,
	cd = 1.5,
	core = 6,
	gold = 9,
	souls = 1,
	ranged = 3,
	route = "greedy",
	pack = "Ninja",
	weapon = "HuntingBow",
}

tbl17.Knight = {
	name = "Knight",
	hp = 120,
	speed = 6.5,
	dmg = 10,
	cd = 1.2,
	core = 12,
	gold = 14,
	souls = 2,
	armor = 0.5,
	pack = "Knight",
	weapon = "Longsword",
	shield = "Heater",
}

tbl17.Wizard = {
	name = "Wizard",
	hp = 55,
	speed = 8,
	dmg = 9,
	cd = 2.4,
	core = 10,
	gold = 14,
	souls = 2,
	ranged = 3,
	splash = 1.2,
	magicRes = 0.6,
	fireRes = 0.6,
	pack = "Mage",
	weapon = "FrostStaff",
}

tbl17.Cleric = {
	name = "Healer",
	hp = 60,
	speed = 8,
	dmg = 3,
	cd = 1,
	core = 6,
	gold = 15,
	souls = 2,
	heal = 0.12,
	healCd = 3,
	healRange = 2.5,
	pack = "Levitation",
	weapon = "HolyScepter",
}

tbl17.Rogue = {
	name = "Rogue",
	hp = 48,
	speed = 13,
	dmg = 6,
	cd = 0.7,
	core = 10,
	gold = 15,
	souls = 2,
	unblockable = true,
	disable = 4,
	disableCd = 6,
	route = "rogue",
	pack = "Ninja",
	weapon = "ViperFang",
	dual = true,
}

tbl17.Captain = {
	name = "Captain Brutus",
	hp = 520,
	speed = 6,
	dmg = 16,
	cd = 1.2,
	core = 40,
	gold = 120,
	souls = 25,
	armor = 0.7,
	boss = true,
	scale = 1.35,
	route = "greedy",
	pack = "Pirate",
	weapon = "BattleAxe",
}

tbl17.Paladin = {
	name = "Sir Paladin",
	hp = 1050,
	speed = 5.5,
	dmg = 18,
	cd = 1.2,
	core = 60,
	gold = 300,
	souls = 40,
	armor = 0.7,
	boss = true,
	scale = 1.45,
	pack = "Superhero",
	weapon = "Morningstar",
	shield = "Heater",
}

tbl17.Archmage = {
	name = "Archmage Vex",
	hp = 1300,
	speed = 6,
	dmg = 20,
	cd = 2,
	core = 60,
	gold = 400,
	souls = 40,
	ranged = 3.5,
	splash = 1.6,
	magicRes = 0.4,
	fireRes = 0.4,
	boss = true,
	scale = 1.45,
	pack = "Levitation",
	weapon = "VoidStaff",
}

tbl17.HeroKing = {
	name = "The Hero King",
	hp = 4000,
	speed = 5,
	dmg = 35,
	cd = 1.1,
	core = 100,
	gold = 900,
	souls = 80,
	armor = 0.5,
	unblockable = false,
	heal = 0.04,
	healCd = 5,
	healRange = 3,
	boss = true,
	scale = 1.6,
	pack = "Superhero",
	weapon = "Kingsblade",
}

tbl17.Thane = {
	name = "Thane Ironbeard",
	hp = 1100,
	speed = 5,
	dmg = 20,
	cd = 1.3,
	core = 60,
	gold = 260,
	souls = 35,
	armor = 0.55,
	boss = true,
	scale = 1.4,
	pack = "Knight",
	weapon = "RuneHammer",
}

tbl17.Alchemist = {
	name = "Grimwald the Alchemist",
	hp = 1000,
	speed = 6,
	dmg = 18,
	cd = 2.2,
	core = 55,
	gold = 320,
	souls = 40,
	ranged = 3.6,
	splash = 1.8,
	fireRes = 0.5,
	boss = true,
	scale = 1.4,
	pack = "Mage",
	weapon = "AlchemyStaff",
}

tbl17.Beastmaster = {
	name = "Rhogar the Beastmaster",
	hp = 1500,
	speed = 7.5,
	dmg = 26,
	cd = 0.9,
	core = 70,
	gold = 380,
	souls = 45,
	armor = 0.8,
	boss = true,
	scale = 1.5,
	pack = "Werewolf",
	weapon = "FangAxe",
	dual = true,
}

tbl17.Lightbringer = {
	name = "Seraphine the Lightbringer",
	hp = 1200,
	speed = 6,
	dmg = 18,
	cd = 1.2,
	core = 60,
	gold = 360,
	souls = 45,
	magicRes = 0.6,
	heal = 0.08,
	healCd = 4,
	healRange = 3.5,
	boss = true,
	scale = 1.45,
	pack = "Levitation",
	weapon = "SunLance",
}

for k28, v27 in pairs(tbl17) do
	v27.id = k28
	var38 = v27.speed * 0.6
	v27.speed = var38
end

tbl2.EnemyIntro = {
	{ id = "Peasant", wave = 1 },
	{ id = "Swordsman", wave = 2 },
	{ id = "Ranger", wave = 4 },
	{ id = "Knight", wave = 6 },
	{ id = "Wizard", wave = 8 },
	{ id = "Cleric", wave = 11 },
	{ id = "Rogue", wave = 13 },
}

tbl2.Bosses = {
	"Captain",
	"Thane",
	"Paladin",
	"Alchemist",
	"Archmage",
	"Beastmaster",
	"Lightbringer",
	"HeroKing",
}

tbl2.BeginnerWaves = {
	{ count = 4, hp = 0.8, damage = 0.75, spawn = 1.2 },
	{ count = 6, hp = 0.85, damage = 0.8, spawn = 1.15 },
	{ count = 7, hp = 0.9, damage = 0.85, spawn = 1.1 },
	{ count = 9, hp = 0.95, damage = 0.9, spawn = 1.05 },
	{ count = 10, hp = 1, damage = 0.95, spawn = 1 },
}

tbl2.BuildWave = function(arg1)
	local var6
	local tbl1 = {}
	local var1 = nil
	for k1, v1 in ipairs(tbl2.EnemyIntro) do
		if v1.wave > arg1 then
			goto L37
		end

		table.insert(tbl1, v1.id)
		var1 = v1
	::L37:: end

	local var3 = tbl2.BeginnerWaves[arg1]
	if var3 then
		local var5 = var3.count
		if not var5 then
			var5 = math.min(math.floor(arg1 * 1.5) + 5, 60)
		end
	end

	local tbl3 = {}
	local var7 = Random.new(arg1 * 7919)
	for i1 = 1, var6 do
		local var9 = nil
		if var1 and (var1.wave == arg1 and i1 % 2 == 0) then
			var9 = var1.id
		else
			var9 = (function() if i1 <= 2 then return tbl1[1] else return tbl1[math.clamp(math.floor(var7:NextNumber() ^ 0.7 * #tbl1) + 1, 1, #tbl1)] end end)()
		end

		table.insert(tbl3, var9)
	end

	if arg1 % 5 == 0 then
		table.insert(tbl3, tbl2.Bosses[math.clamp(math.floor(arg1 / 5 - 1) % #tbl2.Bosses + 1, 1, #tbl2.Bosses)])
	end

	return tbl3
end

tbl2.DEEP_START = 500
tbl2.DEEP_HP_GROWTH = 1.0015
tbl2.DEEP_DMG_PER_WAVE = 0.002
tbl2.DEEP2_START = 2000
tbl2.DEEP2_HP_GROWTH = 1.0002
tbl2.WaveHpMult = function(arg1)
	return ((arg1 - 1) * 0.09 + 1 + math.max(0, arg1 - 20) * 0.06 - math.max(0, arg1 - 120) * 0.03) * (tbl2.BeginnerWaves[arg1] and tbl2.BeginnerWaves[arg1].hp or 1) * tbl2.DEEP_HP_GROWTH ^ math.max(0, math.min(arg1, tbl2.DEEP2_START) - tbl2.DEEP_START) * tbl2.DEEP2_HP_GROWTH ^ math.max(0, arg1 - tbl2.DEEP2_START)
end

tbl2.WaveCoreMult = function(arg1)
	return math.max(0, arg1 - tbl2.DEEP_START) * 0.002 + 1
end

tbl2.BossHpMult = function(arg1)
	return (math.clamp((arg1 - 5) * 0.0054545454545454541 + 0.7, 0.7, 1))
end

tbl2.BossCurve = function(arg1, arg2)
	local var1 = math.clamp((arg1 - 5) / 35, 0, 1)
	local tbl1 = { hp = (var1 * 1198 + 520) * math.clamp(((arg2 and arg2.armor or 1) + (arg2 and arg2.magicRes or 1)) / 2, 0.7, 1) }
	tbl1.dmg = var1 * 10 + 16
	tbl1.core = var1 * 30 + 40
	tbl1.gold = var1 * 330 + 120
	tbl1.souls = math.floor(var1 * 25 + 25 + 0.5)
	return tbl1
end

tbl2.WaveReward = function(arg1)
	return arg1 * 22 + 60
end

tbl2.WaveSouls = function(arg1)
	return math.floor(arg1 / 2) + 1
end

tbl2.DropRarity = function(arg1, arg2)
	local var1 = arg2
	var1 = var1 or Random.new()
	local num1 = 0
	local tbl1 = {}
	for k1, v1 in ipairs(tbl2.Rarities) do
		local var2
		if v1.unitsOnly then
			var2 = 0
		else
			local var3 = arg1 / 12 + 1
			var2 = v1.weight * (1 < k1 and var3 ^ (k1 - 1) * 0.6 or 1)
		end

		tbl1[k1] = var2
		var2 = tbl1[k1]
		num1 = num1 + var2
	end

	local var4 = var1:NextNumber() * num1
	for k2, v2 in ipairs(tbl2.Rarities) do
		var4 = var4 - tbl1[k2]
		if var4 > 0 then
			goto L40
		end

		do return v2.id
	 end ::L40:: end

	return "Common"
end

tbl2.Img = {
	Coin = "rbxassetid://17324051134",
	Soul = "rbxassetid://295551041",
	Hex = "rbxassetid://1215684307",
	Clover = "rbxassetid://85467562484032",
	Crown = "rbxassetid://123102182283640",
	Skull = "rbxassetid://91989851273706",
	Sword = "rbxassetid://131020882867145",
	Backpack = "rbxassetid://28925168",
	Hammer = "rbxassetid://9345267274",
	Book = "rbxassetid://5136650212",
	Heart = "rbxassetid://1124333536",
	Lock = "rbxassetid://106863826261215",
	Chest = "rbxassetid://70813993636283",
	Bolt = "rbxassetid://13815326567",
	Gem = "rbxassetid://100722928620542",
	Boots = "rbxassetid://16706500627",
	Tree = "rbxassetid://10666510413",
	Potion = "rbxassetid://72975480129642",
	Studs = "rbxassetid://7447638591",
}

tbl2.Img.Coin = "rbxassetid://88945202816748"
tbl2.Img.Soul = "rbxassetid://74341746385429"
tbl2.Img.Crown = "rbxassetid://139488111967175"
tbl2.Img.Hammer = "rbxassetid://134050648378766"
tbl2.Img.Skull = "rbxassetid://120187784256532"
tbl2.Img.Sword = "rbxassetid://99002342877304"
tbl2.Img.Backpack = "rbxassetid://99002342877304"
tbl2.Img.Book = "rbxassetid://82903011712643"
tbl2.Img.Heart = "rbxassetid://85815682574036"
tbl2.Img.Gem = "rbxassetid://92117877485718"
tbl2.Img.Potion = "rbxassetid://129691387524211"
tbl2.Img.Home = "rbxassetid://104134659050269"
tbl2.Img.Visit = "rbxassetid://94939301102845"
tbl2.Img.Overview = "rbxassetid://82903011712643"
tbl2.Img.Clover = "rbxassetid://103785185345738"
tbl2.Img.Bolt = "rbxassetid://95028748167154"
tbl2.Img.Boots = "rbxassetid://123525663990651"
tbl2.Img.Chest = "rbxassetid://138029806642875"
tbl2.Img.Lock = "rbxassetid://97269862975907"
tbl2.Img.Title = "rbxassetid://127592650320762"
tbl2.Img.SkillAtlas = "rbxassetid://97117257354548"
tbl2.StartWave = function(arg1)
	return (math.max(1, math.floor(((tonumber(arg1) or 0) + 1) / tbl2.CHECKPOINT_EVERY) * tbl2.CHECKPOINT_EVERY))
end

tbl2.Checkpoints = function(arg1)
	local tbl1 = { 1 }
	for i1 = tbl2.CHECKPOINT_EVERY, tbl2.StartWave(arg1), tbl2.CHECKPOINT_EVERY do
		table.insert(tbl1, i1)
	end

	return tbl1
end

tbl2.ValidCheckpoint = function(arg1, arg2)
	arg2 = tonumber(arg2)
	if not arg2 or arg2 ~= math.floor(arg2) then
		return false
	end

	local bool2 = true
	if arg2 ~= 1 then
		bool2 = false
		if tbl2.CHECKPOINT_EVERY <= arg2 then
			bool2 = false
			if arg2 % tbl2.CHECKPOINT_EVERY == 0 then
				bool2 = arg2 <= tbl2.StartWave(arg1)
			end
		end
	end

	return bool2
end

tbl2.ResumeWave = function(arg1)
	local var2 = arg1.checkpoint
	if var2 ~= nil and tbl2.ValidCheckpoint(arg1.best, var2) then
		return var2
	end

	local var3 = arg1.best
	return tbl2.StartWave(var3)
end

tbl2.BossFor = function(arg1)
	if arg1 % 5 ~= 0 then
		return nil
	end

	return tbl2.Bosses[math.clamp(math.floor(arg1 / 5 - 1) % #tbl2.Bosses + 1, 1, #tbl2.Bosses)]
end

tbl2.Img.Dice = "rbxassetid://101771429151948"
tbl2.Img.Upgrade = "rbxassetid://75826644608397"
tbl2.Img.Speed = "rbxassetid://70852308771313"
tbl2.Img.Shop = "rbxassetid://6995317489"
local tbl20 = {
	key = "VIP",
	id = 1998020761,
	price = 199,
	name = "VIP",
	icon = "Crown",
	color = Color3.fromRGB(196, 152, 58),
	desc = "+20% earned Coins and +10% earned Dark Souls.",
}

local tbl21 = {
	key = "DoubleCoins",
	id = 1998848721,
	price = 199,
	name = "2x Coins",
	icon = "Coin",
	color = Color3.fromRGB(190, 142, 48),
	desc = "Doubles earned Coins, including other earning bonuses.",
}

local tbl22 = {
	key = "SoulBoost",
	id = 1997960740,
	price = 199,
	name = "2x Souls",
	icon = "Soul",
	color = Color3.fromRGB(150, 92, 190),
	desc = "Doubles earned Dark Souls, including other earning bonuses.",
}

var38 = {
	key = "ExtraPop",
	id = 1999820719,
	price = 179,
	name = "Bigger Army (+3 Pop)",
	icon = "Skull",
	color = Color3.fromRGB(70, 120, 190),
	desc = "+3 unit population in your dungeon.",
}

var54 = {
	key = "Lucky",
	id = 1998986704,
	price = 199,
	name = "2x Luck",
	icon = "Clover",
	color = Color3.fromRGB(64, 150, 92),
	desc = "2x Rare+ roll weight on both stands. Stacks with other luck; fixed summon chances stay unchanged.",
}

local tbl23 = {
	key = "BattleSpeed",
	id = 1999886693,
	price = 99,
	name = "3x Battle Speed",
	icon = "Bolt",
	color = Color3.fromRGB(56, 128, 236),
	desc = "Unlocks 3x wave speed (2x is unlocked in the Skill Tree). Toggle it any time with the SPEED button.",
}

local tbl24 = {
	tbl20,
	tbl21,
	tbl22,
	var38,
	var54,
	tbl23,
	{
		key = "HeroPower",
		id = 1998212690,
		price = 199,
		name = "2x Sword Power",
		icon = "Sword",
		color = Color3.fromRGB(176, 70, 70),
		desc = "Doubles damage dealt with your equipped weapon.",
	},
}

describe = { Passes = tbl24 }
describe.Products = {
	StarterPack = {
		id = 3714891839,
		price = 49,
		name = "Starter Pack",
		limit = 1,
		grant = { unit = "EliteKnight", gold = 7500, souls = 50 },
		desc = "Elite Knight x1 + 7,500 Coins + 50 Dark Souls",
	},
	AdvancedPack = {
		id = 3714890751,
		price = 299,
		name = "Advanced Pack",
		limit = 1,
		grant = { unit = "RoyalKnight", gold = 150000, souls = 500 },
		desc = "Royal Knight x1 + 150,000 Coins + 500 Dark Souls",
	},
	DreadPack = {
		id = 3714891182,
		price = 799,
		name = "Dread Pack",
		limit = 1,
		grant = { unit = "DreadKnight", gold = 1000000, souls = 3000 },
		desc = "Dread Knight x1 + 1,000,000 Coins + 3,000 Dark Souls",
	},
	Crate1 = { id = 0, price = 99, name = "Knight's Relic Crate", grant = { crate = 1 } },
	Crate3 = { id = 0, price = 249, name = "Knight's Relic Crate x3", grant = { crate = 3 } },
	Crate10 = { id = 0, price = 699, name = "Knight's Relic Crate x10", grant = { crate = 10 } },
	Featured1 = { id = 3716875826, price = 79, name = "Abyssal Chest", grant = { featured = 1 } },
	Featured3 = { id = 3716875874, price = 199, name = "Abyssal Chest x3", grant = { featured = 3 } },
	Featured10 = { id = 3716875919, price = 599, name = "Abyssal Chest x10", grant = { featured = 10 } },
	Featured50 = { id = 3716875962, price = 2499, name = "Abyssal Chest x50", grant = { featured = 50 } },
	FeaturedGift1 = {
		id = 0,
		via = "Featured1",
		price = 79,
		name = "Gift: Abyssal Chest",
		gift = true,
		grant = { featured = 1 },
	},
	FeaturedGift3 = {
		id = 0,
		via = "Featured3",
		price = 199,
		name = "Gift: Abyssal Chest x3",
		gift = true,
		grant = { featured = 3 },
	},
	FeaturedGift10 = {
		id = 0,
		via = "Featured10",
		price = 599,
		name = "Gift: Abyssal Chest x10",
		gift = true,
		grant = { featured = 10 },
	},
	FeaturedGift50 = {
		id = 0,
		via = "Featured50",
		price = 2499,
		name = "Gift: Abyssal Chest x50",
		gift = true,
		grant = { featured = 50 },
	},
	QuickSummon = { id = 3714891330, price = 9, name = "Quick Summon", grant = { summon = "any" } },
	LegendarySummon = {
		id = 3714891217,
		price = 240,
		name = "Legendary Summon",
		grant = { summon = "Legendary" },
	},
	ServerLuck = {
		id = 3714891381,
		price = 49,
		name = "Server Luck +10%",
		grant = { serverLuck = 900, luckLevel = 10 },
	},
	CoinBoost = {
		id = 3714890786,
		price = 19,
		name = "Coin Booster",
		grant = { boost = "coins", time = 600 },
	},
	SoulBoostPotion = {
		id = 3714891689,
		price = 19,
		name = "Soul Booster",
		grant = { boost = "souls", time = 600 },
	},
	MoraleBoost = {
		id = 3714891276,
		price = 19,
		name = "Morale Booster",
		grant = { boost = "morale", time = 600 },
	},
	LuckBoost = {
		id = 3714891250,
		price = 19,
		name = "Luck Booster",
		grant = { boost = "luck", time = 600 },
	},
	Coins1 = { id = 3714890818, price = 15, name = "+2,000 Coins", grant = { gold = 2000 } },
	Coins2 = { id = 3714890847, price = 45, name = "+10,000 Coins", grant = { gold = 10000 } },
	Coins3 = { id = 3714890879, price = 99, name = "+50,000 Coins", grant = { gold = 50000 } },
	Coins4 = { id = 3714890933, price = 349, name = "+300,000 Coins", grant = { gold = 300000 } },
	Coins5 = { id = 3714890975, price = 899, name = "+2,000,000 Coins", grant = { gold = 2000000 } },
	Souls1 = { id = 3714891717, price = 19, name = "+100 Dark Souls", grant = { souls = 100 } },
	Souls2 = { id = 3714891747, price = 49, name = "+500 Dark Souls", grant = { souls = 500 } },
	Souls3 = { id = 3714891771, price = 99, name = "+1,500 Dark Souls", grant = { souls = 1500 } },
	Souls4 = { id = 3714891798, price = 399, name = "+15,000 Dark Souls", grant = { souls = 15000 } },
	Souls5 = { id = 3714891825, price = 899, name = "+150,000 Dark Souls", grant = { souls = 150000 } },
}

describe.Crate = {
	{ id = "EliteKnight", w = 52 },
	{ id = "HexArcher", w = 30 },
	{ id = "SkeletonKing", w = 12.5 },
	{ id = "RoyalKnight", w = 5 },
	{ id = "DreadKnight", w = 0.5 },
}

describe.Featured = {
	name = "ABYSSAL CHEST",
	tag = "Limited Time!",
	unit = "Chest",
	units = "Chests",
	endsAt = 1792972800,
	rewards = {
		{ id = "VampireLord", w = 38 },
		{ id = "InfernalWarlord", w = 26 },
		{ id = "StormDrake", w = 18 },
		{ id = "FrostwingDrake", w = 11 },
		{ id = "DreadKnight", w = 5.5 },
		{ id = "Cerberus_Infernal", w = 1.4 },
		{ id = "SunDragon_Cursed", w = 0.1 },
	},
	packs = {
		{ key = "Featured50", gift = "FeaturedGift50", n = 50, was = 5959 },
		{ key = "Featured10", gift = "FeaturedGift10", n = 10 },
		{ key = "Featured3", gift = "FeaturedGift3", n = 3 },
		{ key = "Featured1", gift = "FeaturedGift1", n = 1 },
	},
}

describe.Summon = {
	Common = 20,
	Uncommon = 34,
	Rare = 30,
	Epic = 10,
	Legendary = 4.5,
	Mythic = 1.2,
	Secret = 0.3,
}

describe.LegendarySummon = { Legendary = 94.5, Mythic = 5, Secret = 0.5 }
tbl20 = {
	name = "Coin Booster",
	desc = "x2 Coins for 10 minutes.",
	icon = "Coin",
	color = Color3.fromRGB(180, 140, 50),
}

tbl24 = { coins = tbl20 }
tbl20 = {
	name = "Soul Booster",
	desc = "x2 Dark Souls for 10 minutes.",
	icon = "Soul",
	color = Color3.fromRGB(140, 80, 190),
}

tbl24.souls = tbl20
tbl20 = {
	name = "Morale Booster",
	desc = "+30% unit damage for 10 minutes.",
	icon = "Potion",
	color = Color3.fromRGB(60, 120, 200),
}

tbl24.morale = tbl20
tbl20 = {
	name = "Luck Booster",
	desc = "+5% roll luck for 10 minutes.",
	icon = "Clover",
	color = Color3.fromRGB(60, 150, 90),
}

tbl24.luck = tbl20
describe.Boosts = tbl24
tbl2.Shop = describe
tbl2.Quests = {
	{
		id = "waves",
		stat = "waves",
		name = "Wave Breaker",
		text = "Clear %d waves",
		goal = 3,
		grow = 1.6,
		gold = 300,
		souls = 2,
		icon = "Crown",
	},
	{
		id = "kills",
		stat = "kills",
		name = "Adventurer Hunter",
		text = "Defeat %d adventurers",
		goal = 30,
		grow = 1.7,
		gold = 250,
		souls = 1,
		icon = "Skull",
	},
	{
		id = "bosses",
		stat = "bosses",
		name = "Boss Slayer",
		text = "Beat %d boss waves",
		goal = 1,
		grow = 1.5,
		gold = 800,
		souls = 5,
		icon = "Sword",
	},
	{
		id = "rolls",
		stat = "rolls",
		name = "Gambler",
		text = "Roll %d times at your stands",
		goal = 10,
		grow = 1.6,
		gold = 200,
		souls = 2,
		icon = "Clover",
	},
	{
		id = "coins",
		stat = "coins",
		name = "Treasurer",
		text = "Earn %d Coins",
		goal = 2000,
		grow = 2,
		gold = 400,
		souls = 1,
		icon = "Coin",
	},
	{
		id = "play",
		stat = "playtime",
		name = "Dungeon Keeper",
		text = "Play for %d minutes",
		goal = 600,
		grow = 1.5,
		gold = 350,
		souls = 3,
		icon = "Chest",
		minutes = true,
	},
}

tbl2.QuestGoal = function(arg1, arg2)
	local var2 = arg1.goal * arg1.grow ^ arg2
	if 1000 <= var2 then
		return math.floor(var2 / 100 + 0.5) * 100
	end

	return (math.max(1, (math.floor(var2 + 0.5))))
end

tbl2.QuestReward = function(arg1, arg2)
	return math.floor(arg1.gold * (arg2 + 1) ^ 1.35 / 10 + 0.5) * 10, (math.max(1, (math.floor(arg1.souls * (arg2 * 0.6 + 1)))))
end

var38 = "Monsters"
describe = require(script.Parent.RollUpgradeConfig)
for k29, v28 in ipairs({ "Buildings", var38 }) do
	local num4 = 3
	for k30, v29 in ipairs({ 2, num4 }) do
		local var55 = describe.Passes[v28][v29]
		local var56 = tbl2.Shop.Passes
		local tbl25 = {
			key = var55.key,
			id = var55.id,
			name = ((function() if v28 == "Monsters" then return "Unit" else return "Building" end end)()) .. " " .. v29 .. "x Roll",
			price = describe.Tiers[v29].robux,
			icon = "Roll",
			color = Color3.fromRGB(83, 118, 182),
		}

		tbl25.rollKind = v28
		tbl25.rollTier = v29
		tbl25.desc = "Permanently roll " .. v29 .. " offers at once at this stand."
		table.insert(var56, tbl25)
	end
end

tbl2.BuildingPower = function(arg1, arg2)
	if not arg1 or (arg1.kind == "monster" or arg1.kind == "special") then
		return 0
	end

	local var1 = ({ Common = 1, Uncommon = 2, Rare = 4, Epic = 8, Legendary = 14, Mythic = 22, Secret = 32 })[arg1.rarity] or 1
	local var2
	if arg1.trap then
		var2 = 2.5
	else
		if arg1.buff then
			var2 = 2
		else
			var2 = (function() if arg1.util then return 1.5 else return 1 end end)()
		end
	end

	return (math.max(1, (math.floor(var1 * var2 * (1 + 0.3 * ((arg2 or 1) - 1))))))
end

tbl2.Offline = { baseHours = 8, maxHours = 16, minSeconds = 60 }
tbl2.Shop.Products.SpinPack1 = { id = 3715646612, price = 9, name = "1 Spin", grant = { tickets = 1 } }
tbl2.Shop.Products.SpinPack3 = { id = 3715646660, price = 19, name = "3 Spins", grant = { tickets = 3 } }
tbl2.Shop.Products.SpinPack5 = { id = 3715646732, price = 49, name = "5 Spins", grant = { tickets = 5 } }
tbl2.Shop.Products.Offline5 = { id = 3714891308, price = 49, name = "Offline Rewards x5", grant = { offline = 5 } }
tbl2.ServerLuckPrices = { 49, 99, 149, 199, 249, 299, 349, 399, 449, 499 }
tbl2.ServerLuckProductIds = {
	3714891381,
	3714891431,
	3714891455,
	3714891477,
	3714891510,
	3714891560,
	3714891583,
	3714891611,
	3714891626,
	3714891660,
}

for i2 = 2, 10 do
	tbl21 = i2 * 10
	local var57 = tbl21
	local str6 = "%"
	tbl2.Shop.Products["ServerLuck" .. tbl21] = {
		id = tbl2.ServerLuckProductIds[i2],
		price = tbl2.ServerLuckPrices[i2],
		name = "Server Luck +" .. var57 .. str6,
		grant = { serverLuck = 900, luckLevel = tbl21 },
	}

end

tbl2.NextServerLuck = function(arg1)
	local var2 = math.min(100, (math.max(10, (arg1 or 0) + 10)))
	return (function() if var2 == 10 then return "ServerLuck" else return "ServerLuck" .. var2 end end)(), var2
end

tbl2.QuestPotions = { waves = "coins", bosses = "morale", play = "luck" }
require(script.Parent.LateGameConfig).Apply(tbl2)
tbl2.SkinThemes = { "Frost", "Golden", "Crimson", "Sakura", "Infernal", "Abyssal" }
tbl2.SkinWeights = { Frost = 34, Golden = 24, Crimson = 18, Sakura = 13, Infernal = 8, Abyssal = 3 }
describe = { Frost = Color3.fromRGB(120, 220, 255) }
describe.Golden = Color3.fromRGB(255, 210, 63)
describe.Crimson = Color3.fromRGB(220, 40, 70)
describe.Sakura = Color3.fromRGB(255, 150, 200)
describe.Infernal = Color3.fromRGB(255, 110, 30)
describe.Abyssal = Color3.fromRGB(184, 92, 255)
tbl2.SkinColors = describe
tbl2.SkinRarity = {
	Frost = "Rare",
	Golden = "Epic",
	Crimson = "Epic",
	Sakura = "Legendary",
	Infernal = "Legendary",
	Abyssal = "Mythic",
}

tbl2.SKIN_SHARE = 0.3
tbl2.SkinsByRarity = {}
local str7 = "Crossroads"
tbl2.SkinBases = {
	"YellowCorridor",
	"CorridorCorner",
	"CorridorT",
	str7,
	"CorridorEnd",
	"WoodFloor",
	"StoneWall",
	"CurvedWall",
}

tbl2.Skins = {}
tbl2.SkinOf = {}
for k31, v30 in ipairs(tbl2.SkinBases) do
	local var58 = tbl11[v30]
	if not var58 then
		goto L45
	end

	tbl2.Skins[v30] = {}
	for k32, v31 in ipairs(tbl2.SkinThemes) do
		local var59 = v30 .. "_" .. v31
		local var60 = table.clone(var58)
		var60.id = var59
		var60.name = v31 .. " " .. var58.name
		var60.skin = v31
		var60.base = v30
		var60.cosmetic = true
		local var61 = tbl2.SkinRarity[v31]
		var60.rarity = var61 or var58.rarity
		var61 = tbl2.BuildPrice
		if var58.price and (var61[var58.rarity] and var61[var60.rarity]) then
			var60.price = math.floor(var58.price * var61[var60.rarity] / var61[var58.rarity] + 0.5)
		end

		local var62 = tbl2.SkinsByRarity[var60.rarity]
		tbl2.SkinsByRarity[var60.rarity] = var62 or {}
		table.insert(tbl2.SkinsByRarity[var60.rarity], var59)
		var60.order = (var58.order or 0) + k32 * 0.01
		var60.desc = var58.desc .. "  (" .. v31 .. " cosmetic style - works exactly like the normal piece.)"
		tbl11[var59] = var60
		tbl2.Skins[v30][v31] = var59
		tbl2.SkinOf[var59] = { base = v30, theme = v31 }
	end
::L45:: end

for k33, v32 in pairs(tbl2.SkinsByRarity) do
	table.sort(v32)
end

tbl2.RollSkinOfRarity = function(arg1, arg2)
	local var2 = tbl2.SkinsByRarity[arg1]
	if var2 then
		if #var2 ~= 0 then
			local var3 = arg2
			if tbl2.SKIN_SHARE <= (var3 or math.random()) then
				return nil
			end
		end
	end

	return var2[math.random(1, #var2)]
end

tbl2.RollSkin = function(arg1, arg2, arg3)
	local var2 = tbl2.Skins[arg1]
	if var2 then
		local var3 = arg2
		if tbl2.SKIN_CHANCE <= (var3 or math.random()) then
			return nil
		end
	end

	local num1 = 0
	for k1, v1 in ipairs(tbl2.SkinThemes) do
		local var4 = tbl2.SkinWeights[v1]
		num1 = num1 + var4
	end

	local var5 = arg3
	local var6 = (var5 or math.random()) * num1
	for k2, v2 in ipairs(tbl2.SkinThemes) do
		var6 = var6 - tbl2.SkinWeights[v2]
		if var6 > 0 then
			goto L49
		end

		do return var2[v2]
	 end ::L49:: end

	return var2[tbl2.SkinThemes[1]]
end

var54 = {
	"SunDragon",
	{
		name = "Sun Dragon",
		rarity = "Divine",
		price = 120000,
		value = 8000,
		modelScale = 0.9,
		footprint = { 3, 3 },
		ability = { name = "Solar Flare", desc = "Breathes sunfire over a huge area. Divine." },
		mon = {
			hp = 6000,
			dmg = 380,
			cd = 2.2,
			range = 5,
			attack = "aoe",
			splash = 2.4,
			dtype = "magic",
			block = 0,
			boss = true,
			tags = { fire = true, holy = true },
		},
		desc = "DIVINE. A dragon of living sunlight. Its breath burns everything in a huge area. Occupies 3 x 3 tiles.",
	},
}

describe = {
	{
		"GoblinScout",
		{
			name = "Goblin Scout",
			rarity = "Common",
			price = 5,
			value = 30,
			modelScale = 0.8,
			ability = { name = "Quick Stabs", desc = "Fast dagger jabs behind a sturdy shield." },
			mon = {
				hp = 75,
				dmg = 9,
				cd = 0.75,
				range = 1.4,
				attack = "melee",
				block = 1,
				tags = { physical = true },
			},
			desc = "A scrappy shield-and-dagger defender with quick jabs.",
		},
	},
	{
		"CinderKobold",
		{
			name = "Cinder Kobold",
			rarity = "Uncommon",
			price = 55,
			value = 80,
			modelScale = 0.8,
			ability = {
				name = "Cinder Spear",
				desc = "Long spear reach; every 3rd thrust deals double damage.",
			},
			mon = {
				hp = 95,
				dmg = 14,
				cd = 1,
				range = 2,
				attack = "melee",
				block = 1,
				heavy = 3,
				tags = { physical = true, fire = true },
			},
			desc = "A horned reptile with a long spear. Every 3rd thrust deals double damage.",
		},
	},
	{
		"BoneGuard",
		{
			name = "Bone Guard",
			rarity = "Rare",
			price = 1000,
			value = 240,
			modelScale = 0.8,
			ability = {
				name = "Shield Wall",
				desc = "A battered shield that holds back 3 adventurers. Undead.",
			},
			mon = {
				hp = 380,
				dmg = 16,
				cd = 1.2,
				range = 1.5,
				attack = "melee",
				block = 3,
				tags = { undead = true, physical = true },
			},
			desc = "A ribbed skeleton with a battered shield. Holds back 3 adventurers. Undead.",
		},
	},
	{
		"ObsidianGargoyle",
		{
			name = "Obsidian Gargoyle",
			rarity = "Epic",
			price = 4600,
			value = 400,
			modelScale = 0.78,
			footprint = { 2, 2 },
			ability = {
				name = "Stone Sweep",
				desc = "Wing and claw sweeps hit every nearby adventurer. Holds back 3.",
			},
			mon = {
				hp = 900,
				dmg = 32,
				cd = 1.6,
				range = 2.2,
				attack = "melee",
				block = 3,
				cleave = true,
				tags = { physical = true },
			},
			desc = "A carved winged guardian. Sweeps hit all nearby foes. Occupies 2 x 2 tiles.",
		},
	},
	{
		"GraveWarden",
		{
			name = "Grave Warden",
			rarity = "Legendary",
			price = 9500,
			value = 820,
			modelScale = 0.82,
			ability = {
				name = "Soul Lantern",
				desc = "Summons skeleton minions. Undead nearby deal +30% damage.",
			},
			mon = {
				hp = 520,
				dmg = 34,
				cd = 1.5,
				range = 3.4,
				attack = "ranged",
				dtype = "magic",
				block = 1,
				summon = 10,
				aura = { undead = 1.3, radius = 3.5 },
				tags = { undead = true },
			},
			desc = "A hooded summoner with a soul-flame staff. Raises minions; undead nearby deal +30% damage.",
		},
	},
	{
		"GildedMimic",
		{
			name = "Gilded Mimic",
			rarity = "Mythic",
			price = 19000,
			value = 1450,
			modelScale = 0.95,
			ability = { name = "Golden Greed", desc = "Adventurers it kills drop 2.5x Coins." },
			mon = {
				hp = 900,
				dmg = 75,
				cd = 1.8,
				range = 1.6,
				attack = "melee",
				block = 2,
				goldMult = 2.5,
				tags = { physical = true },
			},
			desc = "A golden treasure chest with fangs. Its kills drop 2.5x Coins.",
		},
	},
	{
		"FurnaceBrute",
		{
			name = "Furnace Brute",
			rarity = "Secret",
			price = 34000,
			value = 2500,
			modelScale = 0.78,
			footprint = { 2, 2 },
			ability = {
				name = "Molten Heart",
				desc = "Cleaves every nearby adventurer; every 3rd swing deals double fire damage. Holds back 5.",
			},
			mon = {
				hp = 2000,
				dmg = 120,
				cd = 2,
				range = 2.2,
				attack = "melee",
				block = 5,
				cleave = true,
				heavy = 3,
				boss = true,
				tags = { physical = true, fire = true },
			},
			desc = "SECRET. Cracked obsidian armour around a molten heart. Cleaves all nearby foes. Occupies 2 x 2 tiles.",
		},
	},
}

for k34, v33 in ipairs({
	{
		"BoneColossus",
		{
			name = "Bone Colossus",
			rarity = "Secret",
			price = 36000,
			value = 2600,
			modelScale = 0.85,
			footprint = { 2, 2 },
			ability = {
				name = "Grave Slam",
				desc = "Huge bone-club slams hit every nearby adventurer; every 2nd slam deals double damage. Holds back 6.",
			},
			mon = {
				hp = 2400,
				dmg = 120,
				cd = 2.1,
				range = 2.2,
				attack = "melee",
				block = 6,
				cleave = true,
				heavy = 2,
				boss = true,
				tags = { undead = true, physical = true },
			},
			desc = "SECRET. A towering giant of chained bones with a burning soul. Cleaves all nearby foes. Occupies 2 x 2 tiles.",
		},
	},
	{
		"BansheeQueen",
		{
			name = "Banshee Queen",
			rarity = "Secret",
			price = 33000,
			value = 2400,
			modelScale = 0.9,
			ability = {
				name = "Wail of Despair",
				desc = "Her scream blasts a wide area and slows every adventurer it hits by 40%.",
			},
			mon = {
				hp = 1300,
				dmg = 140,
				cd = 2,
				range = 4.2,
				attack = "aoe",
				splash = 1.8,
				dtype = "magic",
				block = 1,
				slowOnHit = 0.4,
				boss = true,
				tags = { undead = true },
			},
			desc = "SECRET. A ghostly queen whose wail tears through whole groups and slows them down.",
		},
	},
	{
		"Cerberus",
		{
			name = "Cerberus",
			rarity = "Secret",
			price = 40000,
			value = 2900,
			modelScale = 0.85,
			footprint = { 2, 2 },
			ability = {
				name = "Three Heads",
				desc = "Three burning bites hit every nearby adventurer; every 3rd bite deals double fire damage. Holds back 5.",
			},
			mon = {
				hp = 2600,
				dmg = 95,
				cd = 1.6,
				range = 2.2,
				attack = "melee",
				block = 5,
				cleave = true,
				heavy = 3,
				boss = true,
				tags = { physical = true, fire = true },
			},
			desc = "SECRET. The three-headed hound that guards the gates of the deep. Occupies 2 x 2 tiles.",
		},
	},
	{
		"SeraphOfRuin",
		{
			name = "Seraph of Ruin",
			rarity = "Divine",
			price = 90000,
			value = 6000,
			modelScale = 0.9,
			footprint = { 2, 2 },
			ability = { name = "Judgement", desc = "Calls holy lightning down on a wide area. Divine." },
			mon = {
				hp = 4200,
				dmg = 300,
				cd = 1.8,
				range = 4.6,
				attack = "aoe",
				splash = 2,
				dtype = "magic",
				block = 3,
				boss = true,
				tags = { holy = true },
			},
			desc = "DIVINE. A fallen angel of light and ruin. Smites whole groups with holy lightning. Occupies 2 x 2 tiles.",
		},
	},
	var54,
}) do

	table.insert(describe, v33)
end

for k35, v34 in ipairs(describe) do
	local var63 = v34[2]
	var63.kind = "monster"
	var63.cat = "Monsters"
	var63.order = 80 + k35
	var63.creature = true
	local var65 = var63.footprint
	tbl23 = v34[1]
	if not var65 then
		var65 = { 1, 1 }
	end

	var63.footprint = var65
	var63.id = tbl23
	var63.cost = 0
	local var66 = var63.rarity
	var63.pop = tbl2.UnitPop[var66] or 1
	if var63.mon.attack == "melee" then
		var65 = "Melee"
	else
		var65 = (function() if var63.mon.dtype == "magic" then return "Magic" else return "Ranged" end end)()
	end

	var63.range = var65
	tbl2.UnitPriceById[tbl23] = var63.price
	tbl11[tbl23] = var63
end

local tbl26 = {
	id = "Golden",
	name = "Golden",
	chance = 0.014285714285714285,
	mult = 3,
	price = 4,
	popAdd = 1,
	color = Color3.fromRGB(255, 196, 40),
}

tbl26.textColor = Color3.fromRGB(255, 160, 28)
local tbl27 = {
	id = "Frozen",
	name = "Frozen",
	chance = 0.002,
	mult = 4.8,
	price = 7,
	popAdd = 2,
	color = Color3.fromRGB(150, 225, 255),
}

tbl27.textColor = Color3.fromRGB(110, 210, 255)
local tbl28 = {
	id = "Infernal",
	name = "Infernal",
	chance = 0.00066666666666666664,
	mult = 7,
	price = 12,
	popAdd = 2,
	color = Color3.fromRGB(255, 110, 30),
}

tbl28.textColor = Color3.fromRGB(255, 92, 28)
local tbl29 = {
	id = "Cursed",
	name = "Cursed",
	chance = 0.00025,
	mult = 10,
	price = 20,
	popAdd = 3,
	color = Color3.fromRGB(150, 255, 110),
}

tbl23 = Color3.fromRGB(226, 72, 255)
tbl29.textColor = tbl23
tbl2.Mutations = { tbl26, tbl27, tbl28, tbl29 }
tbl29 = { id = "Cursed", n = 4000 }
tbl2.MutationPity = {
	{ id = "Golden", n = 250 },
	{ id = "Frozen", n = 1000 },
	{ id = "Infernal", n = 2000 },
	tbl29,
}

tbl2.MutationOdds = {
	Common = { Golden = 70, Frozen = 400, Infernal = 1200, Cursed = 2500 },
	Uncommon = { Golden = 40, Frozen = 180, Infernal = 500, Cursed = 1200 },
	Rare = { Golden = 30, Frozen = 150, Infernal = 400, Cursed = 1000 },
	Epic = { Golden = 15, Frozen = 75, Infernal = 200, Cursed = 500 },
	Legendary = { Golden = 10, Frozen = 50, Infernal = 140, Cursed = 350 },
	Mythic = { Golden = 6, Frozen = 18, Infernal = 50, Cursed = 120 },
	Secret = { Golden = 4, Frozen = 10, Infernal = 25, Cursed = 60 },
	Divine = { Golden = 4, Frozen = 10, Infernal = 25, Cursed = 60 },
}

tbl2.MutationChance = function(arg1, arg2)
	local var1 = arg2
	var1 = var1 and tbl2.MutationOdds[arg2]
	local var2 = var1
	var2 = var2 and var1[arg1.id]
	return var2 and 1 / var2 or arg1.chance
end

tbl2.MutationRename = { Shadow = "Frozen", Rainbow = "Infernal" }
tbl2.RenamedItems = { MossSlime = "Slime" }
tbl2.MutationById = {}
tbl2.MutationOf = {}
tbl2.Mutated = {}
local tbl30 = {}
for k36, v35 in pairs(tbl11) do
	if v35.kind ~= "monster" then
		goto L52
	end

	if v35.retired then
		goto L52
	end

	if v35.mutation then
		goto L52
	end

	table.insert(tbl30, k36)
::L52:: end

table.sort(tbl30)
for k37, v36 in ipairs(tbl2.Mutations) do
	v36.order = k37
	tbl2.MutationById[v36.id] = v36
	for k38, v37 in ipairs(tbl30) do
		local var67 = tbl11[v37]
		local var68 = table.clone(var67)
		var68.mon = table.clone(var67.mon)
		local var69 = var67.mon.tags and table.clone(var67.mon.tags) or nil
		var68.mon.tags = var69
		var68.mon.hp = math.floor(var67.mon.hp * v36.mult + 0.5)
		var68.mon.dmg = math.floor(var67.mon.dmg * v36.mult * 10 + 0.5) / 10
		local var70 = v37 .. "_" .. v36.id
		var68.id = var70
		var68.name = v36.name .. " " .. var67.name
		var68.mutation = v36.id
		var68.base = v37
		var68.pop = (var67.pop or 1) + (v36.popAdd or 0)
		local var71 = var67.value
		var68.value = math.floor((var71 or 30) * v36.price + 0.5)
		var68.price = math.floor((var67.price or 3) * v36.price + 0.5)
		var68.order = (var67.order or 0) + k37 * 0.001
		var69 = var67.desc
		var68.desc = (var69 or "") .. "  " .. string.upper(v36.name) .. " MUTATION: x" .. v36.mult .. " health and damage, costs +" .. (v36.popAdd or 0) .. " population."
		tbl11[var70] = var68
		tbl2.MutationOf[var70] = { base = v37, mutation = v36.id }
		var69 = tbl2.Mutated[v37]
		tbl2.Mutated[v37] = var69 or {}
		var69 = v36.id
		tbl2.Mutated[v37][var69] = var70
	end

	for k39, v38 in pairs(tbl2.MutationRename) do
		if v38 ~= v36.id then
			goto L55
		end

		for k40, v39 in ipairs(tbl30) do
			tbl2.RenamedItems[v39 .. "_" .. k39] = v39 .. "_" .. v38
		end
	::L55:: end
end

for k41, v40 in ipairs(tbl2.Mutations) do
	tbl2.RenamedItems["MossSlime_" .. v40.id] = "Slime_" .. v40.id
end

for k42 in pairs(tbl2.Mutated) do
	tbl2.RenamedItems[k42 .. "_Shiny"] = k42
end

tbl2.RenamedItems.MossSlime_Shiny = "Slime"
for k43, v41 in pairs(tbl2.MutationRename) do
	tbl2.RenamedItems["MossSlime_" .. k43] = "Slime_" .. v41
end

tbl2.RollMutation = function(arg1, arg2, arg3, arg4)
	local var2 = tbl2.Mutated[arg1]
	if not var2 then
		return nil
	end

	local var3 = tbl11[arg1]
	var3 = var3 and tbl11[arg1].rarity
	local var4 = math.clamp(1 + (arg2 or 0) / 200, 1, 2) * (math.max(0, arg3 or 0) + 1)
	for i1 = #tbl2.Mutations, 1, -1 do
		local var6 = tbl2.Mutations[i1]
		local num1 = 0
		if type(arg4) == "table" then
			local var7 = tonumber(arg4[var6.id])
			var7 = var7 or 0
		end

		if math.random() >= tbl2.MutationChance(var6, var3) * var4 * (math.max(num1, 0) + 1) then
			goto L60
		end

		do return var2[var6.id]
	 end ::L60:: end

	return nil
end

tbl2.UnitSellPrice = function(arg1)
	return (math.max(1, (math.floor((arg1 and arg1.price or 3) * 0.25 + 0.5))))
end

tbl2.MutationColor = function(arg1)
	local var1 = tbl2.MutationOf[arg1]
	local var2 = var1
	var2 = var2 and tbl2.MutationById[var1.mutation]
	return var2 and var2.textColor or (var2.color or nil)
end

local str8 = "#5AD2FF"
local str9 = "#7A8CFF"
tbl27 = { "#FF5A5A", "#FFA040", "#FFE45A", "#6CFF7A", str8, str9, "#D07AFF" }
tbl2.MutationWord = function(arg1)
	local var2 = tbl2.MutationById[arg1]
	if not var2 then
		return ""
	end

	if var2.rainbow then
		local tbl1 = {}
		local num1 = 0
		for k1 in var2.name:gmatch(".") do
			num1 = num1 + 1
			table.insert(tbl1, "<font color=\"" .. tbl27[(num1 - 1) % #tbl27 + 1] .. "\">" .. k1:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;") .. "</font>")
		end

		local var3 = tbl1
		return table.concat(var3)
	end

	local var4 = var2.textColor
	var4 = var4 or var2.color
	local var5 = string.format("#%02X%02X%02X", math.floor(var4.R * 255 + 0.5), math.floor(var4.G * 255 + 0.5), (math.floor(var4.B * 255 + 0.5)))
	return "<font color=\"" .. var5 .. "\">" .. var2.name:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;") .. "</font>"
end

tbl2.RichName = function(arg1)
	local var2 = tbl11[arg1]
	if not var2 then
		return (tostring(arg1):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
	end

	local var4 = tbl2.MutationOf[arg1]
	if not var4 then
		return ((var2.name or arg1):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
	end

	local var5 = tbl11[var4.base]
	return tbl2.MutationWord(var4.mutation) .. " " .. (var5 and var5.name or var2.name):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
end

tbl2.IsBoss = function(arg1)
	if type(arg1) == "string" then
		arg1 = tbl11[arg1]
	end

	local bool2 = false
	if type(arg1) == "table" then
		bool2 = false
		if arg1.kind == "monster" then
			bool2 = false
			if arg1.mon ~= nil then
				bool2 = arg1.mon.boss == true
			end
		end
	end

	return bool2
end

local tbl31 = {}
for k44, v42 in pairs(tbl11) do
	local var72 = tbl2.IsBoss(v42)
	if not var72 then
		goto L62
	end

	var72 = tbl2.MutationOf[k44]
	if var72 then
		goto L62
	end

	var72 = v42.retired
	if var72 then
		goto L62
	end

	table.insert(tbl31, v42)
::L62:: end

table.sort(tbl31, function(arg1, arg2)
	local var3 = tbl2.RarityIndex[arg1.rarity] or 0
	local var4 = tbl2.RarityIndex[arg2.rarity] or 0
	if var3 ~= var4 then
		return var3 < var4
	end

	return arg1.name < arg2.name
end)

local tbl32 = {}
for k45, v43 in ipairs(tbl31) do
	table.insert(tbl32, v43.name)
end

tbl2.BossUnitNames = tbl32
local var74 = tbl11.BossRoom
local var75
if var74 and (var74.buff and var74.buff.boss) then
	var75 = "Boss units here get +" .. math.floor((var74.buff.boss - 1) * 100 + 0.5) .. "% damage and health. Boss units: " .. table.concat(tbl32, ", ") .. " (any mutation counts)."
	var74.desc = var75
end

tbl2.BOSS_POP_EXTRA = 1
for k46, v44 in pairs(tbl11) do
	if v44.kind ~= "monster" then
		goto L64
	end

	if not tbl2.IsBoss(v44) then
		goto L64
	end

	local var76 = (v44.pop or 1) + tbl2.BOSS_POP_EXTRA
	v44.pop = var76
::L64:: end

tbl2.WeaponHitCap = {
	Common = 0.06,
	Uncommon = 0.07,
	Rare = 0.08,
	Epic = 0.09,
	Legendary = 0.1,
	Mythic = 0.12,
	Secret = 0.14,
	Divine = 0.16,
}

tbl2.WEAPON_CAP_HERO = 0.06
tbl2.WEAPON_CAP_MAX = 0.25
tbl2.WEAPON_CAP_BOSS = 0.25
tbl2.WeaponHitLimit = function(arg1, arg2, arg3, arg4, arg5)
	local var1 = math.min(tbl2.WEAPON_CAP_MAX, (tbl2.WeaponHitCap[arg1 and arg1.rarity or "Common"] or 0.06) * (1 + (arg3 or 0) * tbl2.WEAPON_CAP_HERO))
	if arg5 then
		var1 = var1 * tbl2.WEAPON_CAP_BOSS
	end

	return (math.max(arg2 or 0, var1 * (arg4 or 0)))
end

tbl2.POTION_TIME = 600
tbl2.POTION_MAX_TIME = 3600
tbl2.IndexRewardBase = {
	Common = { 150, 5 },
	Uncommon = { 300, 10 },
	Rare = { 750, 20 },
	Epic = { 1500, 40 },
	Legendary = { 4000, 90 },
	Mythic = { 10000, 200 },
	Secret = { 25000, 500 },
	Divine = { 60000, 1200 },
}

tbl2.IndexRewardMutation = { Golden = 1.5, Frozen = 2, Infernal = 3, Cursed = 4 }
tbl2.IndexRewardBuilding = 0.25
tbl2.IsIndexEntry = function(arg1)
	local var2 = tbl11[arg1]
	if not var2 or var2.retired then
		return false
	end

	if var2.kind == "monster" then
		return true
	end

	return var2.cat == "Buildings"
end

tbl2.IndexReward = function(arg1)
	if not tbl2.IsIndexEntry(arg1) then
		return nil
	end

	local var1 = tbl11[arg1]
	local var2 = tbl2.IndexRewardBase[var1.rarity]
	var2 = var2 or tbl2.IndexRewardBase.Common
	local num2 = 1
	if var1.kind ~= "monster" then
		num2 = tbl2.IndexRewardBuilding
	else
		if var1.mutation then
			num2 = tbl2.IndexRewardMutation[var1.mutation] or 1
		end
	end

	local var4 = var2[1] * num2
	local var5
	if 1000 <= var4 then
		var5 = math.floor(var4 / 50 + 0.5) * 50
	else
		var5 = (function() if 100 <= var4 then return math.floor(var4 / 5 + 0.5) * 5 else return math.max(1, (math.floor(var4 + 0.5))) end end)()
	end

	local var7 = var2[2] * num2
	if 1000 <= var7 then
		var4 = math.floor(var7 / 50 + 0.5) * 50
	else
		var4 = (function() if 100 <= var7 then return math.floor(var7 / 5 + 0.5) * 5 else return math.max(1, (math.floor(var7 + 0.5))) end end)()
	end

	return var5, var4
end

return tbl2

