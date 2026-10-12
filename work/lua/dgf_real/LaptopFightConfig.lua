--- ReplicatedStorage.Meeting.LaptopFightConfig [ModuleScript]
-- y u r i

return {
	FightSeconds = 35,
	SwingCooldown = 0.55,
	HitDelay = 0.16,
	Reach = 6.5,
	LagSlack = 4,
	HitboxForward = 3,
	HitboxRadius = 4.2,
	HitboxHeight = 5,
	Arc = 0.15,
	Invincible = 0.45,
	Knockback = 34,
	KnockUp = 20,
	WalkSpeed = 16,
	BreakHits = 3,
	BreakWindow = 3,
	BreakImmune = 1.8,
	BreakShove = 9,
	BreakSpeed = 26,
	BreakBoost = 1.4,
	Reward = 50,
	WorkBase = 2,
	WorkTop = 13,
	WorkCurve = 0.75,
	StudioDummies = 4,
	StudioDummiesFightBack = true,
	BoundsMin = Vector3.new(31, 0, -40),
	BoundsMax = Vector3.new(70.5, 0, 13.5),
	Anims = {
		Hold = "117872106113246",
		Swing = "96194094042524",
		Hurt = "112909200130146",
		King = "136088500505792",
	},
	Sounds = {
		Swing = "140527314975641",
		King = "127039883737564",
		Hits = { "82708037443413", "139520673393967", "140604838213617", "109681634329245" },
	},
	Lines = {
		Wait = { Text = "WAIT!", Face = 3, Big = true, Seconds = 1.8 },
		Meeting = { Text = "I have a meeting... I'll be back.", Face = 1, Big = false, Seconds = 3 },
		What = { Text = "what the...", Face = 4, Big = false, Seconds = 2.2 },
		Seats = { Text = "GET BACK TO YOUR SEATS!", Face = 3, Big = true, Seconds = 2.6 },
	},
}

--- ReplicatedStorage.Meeting.DayOffConfig [ModuleScript]
