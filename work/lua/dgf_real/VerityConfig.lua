--- ReplicatedStorage.Meeting.VerityConfig [ModuleScript]
-- y u r i

return {
	EventName = "Assistant or Foe..?",
	Chance = 0.25,
	Reward = 50,
	Scale = 1.6,
	Bars = 3,
	BarBase = 16,
	BarPerPlayer = 7,
	ThrowRate = 0.28,
	BallSpeed = 75,
	HitRadius = 1.25,
	FightMax = 110,
	BotThrowEvery = { 3.2, 5.5 },
	BotAccuracy = 0.35,
	Sounds = {
		Behind = "137768546968340",
		Smash1 = "98163403305703",
		Smash2 = "86082105011342",
		Scan = "88527024141396",
		Reply = "131656913143826",
		Bar1 = "98952060135629",
		Bar2 = "120926816715633",
		LastBar = "92440037194524",
		Window = "98170630880282",
		FightMusic = "82279754681950",
	},
	Lines = {
		Noise = { Text = "Y'all hear that noise?", Face = 8 },
		Boys = { Text = "BOYS...", Face = 4 },
		Order = { Text = "GET VERITY OUT OF MY GAME!!!", Face = 3 },
		OwnGame = { Text = "He need to go back to his own game...", Face = 10 },
		Anyways = { Text = "anyways...", Face = 1 },
		BackToWork = { Text = "BACK TO WORK", Face = 3 },
	},
	ScreenName = "Presentation Screen",
	HoleSize = Vector3.new(12, 10.5, 7),
	HoverOffset = Vector3.new(0, 1.2, 14),
	FlightMin = Vector3.new(34, 59.5, -38),
	FlightMax = Vector3.new(66, 65.2, 10),
	WindowName = "Window (Facing the outside of building)",
}

--- ReplicatedStorage.Meeting.VerityPath [ModuleScript]
