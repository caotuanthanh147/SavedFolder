# DGF1 — Don't Get Fired At Work! 🧳 [LIMITED SKIN EVENT! ] — analysis

Public 0792e4c (force-push #5, folder mode). Files: [Deob].lua 71,851 lines
(MD5 35e41dbf) + game_dump.txt 37,655 lines (5ad359ee). No Template.lua in the
upload — but the user pushed a NEW canonical Template.lua to SavedFolder
(e4ea30a, 945→962 lines): `Plr` is now a lazy LocalPlayer proxy (resolves at
access time; the ONLY diff vs 945, at L37-54). Synced to Yuri/Template.lua
(md5 46b86ff6). Game-section boundary: insert after new L890 (the
`if Toggles.AntiAFK.Value then RunAntiAFK() end` line), before
`local MenuGroup` (L891). NOTE: never compare a Player instance to `Plr`
(identity fails through the proxy) and never pass `Plr` where the instance is
required — read fields (`Plr.UserId`) or use `Players.LocalPlayer`.

## Game model (deobf-verified)

Round-based office survival. `ReplicatedStorage.Meeting` is the namespace;
round state on Meeting attrs (RoundPhase Countdown/Intro/Active, RoundActive,
CountdownEndsAt, RoundEndsAt, WorkStartsAt, RoundIntro, DayOff, GameMode,
OfficeEvent, PaperFightStartsAt/EndsAt, BossMood NORMAL/AGITATED/FIRE,
FireStartsAt, WarBlue/WarRed, HwPhase, AlienPhase etc.), per-player state on
player attrs (MeetingJoined, ReturnToMenu, LaptopView, WorkProgress, Bobux,
Rank, Exp, DaysNotFired, SeatName, WarTeam, EventLock, Ghost, DayOffIn,
PlaytimeStart, PlaytimeClaimed bitmask, EconomyReady, PaperLevel, PhoneLevel,
OwnedSkins, OwnedThrowSkins, HackReadyAt, PhoneState/PhoneReadyAt,
PaperReadyAt, MeetingEliminated, FiredReason, Pressure via state push not
attr), boss state on workspace.Boss attrs (BossState
INTRO_WALK/INTRO_ADDRESS/PATROLLING/BEHIND_PLAYER/FULL_SCAN/PRESENTATION_SCAN/
PRESENTING/CATCHING/EVENT/OUTRO_ADDRESS/LEAVING, WatchedUserId, PleasedUntil).

Core loop (Tutorial L6160-6240, the game's own How-to-Play):
- Join the meeting (JoinMeeting) → sit → work emails on the Win95 laptop
  (SubmitEmail Token+"APPROVE"/"DELETE"/"FORWARD"/"WRITE") → WorkProgress
  (100% = task pay 50 Bobux × rank mult, then a new batch), correct-streak
  combos every 5, wrong = stress+break. Email state: {Token, Kind, From,
  Subject, Text, IsScam, Reply/ReplyES, TimeTotal, TimeLeft}.
- Classification (the game's own UI hint fn HighlightActions L1889-1903 +
  Tutorial answer table L26230-26250): IsScam → DELETE (checked FIRST — scam
  bodies contain "APPROVE"); words approv/aprob/aprueb/apru → APPROVE;
  forward/reenv → FORWARD; Kind=="WRITE" → WRITE. State field IsScam is
  client-visible (the "[!] This message looks suspicious" banner renders from
  it, L3698).
- Stress (Pressure, state push): builds idle (faster when boss watching), 100%
  = pass out. Answers lower it; Butter Squishy tool −8/7s (UseRelaxItem);
  Old Phone text −20 (PhoneAction open/send — boss-visible, left manual).
- Fired reasons (CameraController L1686-1719): Quiz (didn't compliment),
  Phone (texting), Ads (scam ads open), RollCall (didn't answer), Paper
  (throwing outside fight), Squishy, Hack (boss behind you), Call (ringing),
  Printer (didn't fix), Slacking, Snitch. Tutorial L6198: paper/phone/squishy
  = "spotted from ANYWHERE he can see you"; ads/hack/call = "only when he's
  standing right BEHIND you (THE BOSS IS WATCHING YOU)".
- Mid-meeting events: RollCall (OfficeEvent "RollCallAsk" {Id,EndsAt} →
  OfficeEventAction("here",Id) within 3s), Printer ("PrinterKick" {Id,
  StartsAt, EndsAt, Need≈16} → ("kick",Id)×Need), Dance ("DancePicked"
  {Victim,Boss,UserId} → ("dance",Id) during window), BossQuiz (BossQuiz
  {Id,Question,Options[3],EndsAt,ReadyAt} → BossQuizAnswer(Id, i)), Hack.exe
  (HackAction "start"/"tap",Id,Round,dir,servertime/"cancel",Id + HackUpdate
  "active" {Id,Role,Other,EndsAt,Progress,Phase,Round,Rounds,ReadyAt,
  RoundStart,RoundEnd,IntroEnd,Chart,Last,Local} — steal 20-30% work),
  interrupts in the state push (Interrupt {Id,Kind}: Call → decline fast,
  Update → spam click), scam ads (ScamAds [{Id,Image}] → DismissScam(Id)),
  laptop crash (LaptopBroken + SmacksLeft → SmackLaptop ×, 0.25s gate).
- Paper windows (PaperThrow tbl6() L10642-10688, the game's own gate): fight
  window OfficeEvent=="PaperFight" ∧ StartsAt≤now<EndsAt (unlimited throws,
  war teams WarBlue/WarRed, target = other team, SeatName set), or pre-meeting
  RoundPhase=="Countdown" ∧ CountdownEndsAt−now>5 (free-for-all). Outside:
  owned-paper cooldown (PaperReadyAt) — left manual (fire risk).
- Random event games: OLD COMPUTER ATTACK (AlienAction "fire" argless at
  AlienConfig.FireInterval 0.085 while AlienPhase Fight/Finale, not dodging
  (AlienDodgeAt fresh <DodgeSeconds 2.4) nor zapped (AlienZappedUntil);
  "shield" on warn change (AlienWarnId) — same in HalloweenEventUI via
  HwAction/HwCue/HwShots with Hw* attrs, gates identical L36013-36110/45930-
  46040), Verity (VerityCue phases; "Fight" payload {Seed,StartAt,Hover,Min,
  Max} → VerityPath.new (require-able RS module, L39846) → VerityAction
  ("throw", headPos, dir) at ThrowRate 0.28 with the game's own lead:
  path:Pos(now+dist/BallSpeed) + (dist/BallSpeed)²*6 lift, L39083-39134),
  LaptopFight (LaptopFightCue "Fight" {EndsAt} → LaptopFightAction("swing")
  at SwingCooldown 0.55 then after HitDelay 0.16 ("hit", ≤4 nearest models)
  — targets: other players with attr LaptopFighter + workspace.LaptopFight
  Dummies children, HRP within HitboxRadius+1 (4.2+1) of my forward point
  (HitboxForward 3) or 2.2 of me, |ΔY|≤HitboxHeight 5, sorted by dist, ≤4,
  L56900-56962).
- Economy: Bobux (player attr), CareerConfig (RS module, require-able): Ranks
  Intern→CEO (TaskPay 50→100, EndMult 1→2), PaperUpgrades/PhoneUpgrades
  ladders (BuyUpgrade(Kind) with Kind ∈ {"Paper","Phone"}, level = attr
  PaperLevel/PhoneLevel, price Rank-gated server-side), Playtime tiers 2/5/15/
  30/60 min = 15/25/50/80/130 Bobux (ClaimPlaytime(index), claimed = bitmask
  attr PlaytimeClaimed, PlaytimeStart attr; CareerUI L30103-30160 mirror).
- Halloween quest event (HalloweenQuestConfig): 4 tasks (500 paper throws,
  40 hacks, 50 rounds, 1 halloween event) → Coffin skin (SkinAction
  "Equip"/"Buy" — one-shot UI, left manual). Quest progress rides the normal
  wires (throw/hack/rounds) — no extra wire needed.
- BossQuiz answer key: Lang translation table L14550-14598 lists the full
  English Q&A set; the correct option is always the compliment — 12 verified
  strings: "You, sir!" / "Obviously, sir!" / "10/10, stunning!" /
  "You do, boss!" / "Perfect as always!" / "You, the legend!" /
  "Best one ever!" / "A total genius!" / "You are, sir!" /
  "You should be KING!" / "They're amazing!" (+coffee/Who-are-you options
  untranslated → unmatched questions are SKIPPED, never guessed).

## Wire table (all verified at call sites)

| Remote | Class | Wire | Call sites |
|---|---|---|---|
| JoinMeeting | RE | :FireServer() | L6408 (menu Join button) |
| GetState | RF | :InvokeServer() → state table | L4343 |
| StateUpdated | RE | OnClientEvent(state) → full state push | L4334 |
| SubmitEmail | RE | :FireServer(Token, "APPROVE"/"DELETE"/"FORWARD"/"WRITE") | L4101, L2330 |
| SetLaptopView | RE | :FireServer(bool) | L4072 (requestView; game's own submit gate requires LaptopView==true L4088) |
| DismissScam | RE | :FireServer(adId) | L4109 |
| UseRelaxItem | RE | :FireServer(toolInstance) | L4360 (ButterSquishy tool attr MeetingRelaxItem) |
| SmackLaptop | RE | :FireServer() ×SmacksLeft (0.25s gate) | L2605 |
| InterruptAction | RE | :FireServer(intId, "click"/"decline") | L2674/2773/2799 |
| ThrowPaper | RE | :FireServer(targetPlayerOrCharacter) | L10719 (aim = looked-at player) |
| OfficeEventAction | RE | :FireServer("here"/"kick"/"dance", eventId) | L23170/23311/33329 |
| OfficeEvent | RE | OnClientEvent(kind, payload): Say/Here/RollCallAsk{Id,EndsAt}/RollCallResult/CalledOut/PrinterPicked/PrinterWalk/PrinterArrived/PrinterKick{Id,StartsAt,EndsAt,Need}/…/DancePicked{Victim,Boss,UserId}/EventEnd | L23091+ (OfficeEventsUI), L33201+ (DanceEventUI) |
| BossQuiz | RE | OnClientEvent({Id,Question,Options,EndsAt,ReadyAt} or {Id,Result="pass"}) | L16955 |
| BossQuizAnswer | RE | :FireServer(Id, optionIndex) | L16922 |
| HackAction | RE | :FireServer("start") / ("tap", Id, Round, dir, servertime) / ("cancel", Id) | L17400/18640/18728 |
| HackUpdate | RE | OnClientEvent({State=scan/scanfail/recovered/tap/opptap/active/…}) | L22623 |
| BuyUpgrade | RE | :FireServer("Paper"/"Phone") | L28757 |
| UpgradeResult | RE | OnClientEvent | (shop ack) |
| ClaimPlaytime | RE | :FireServer(tierIndex 1-5) | L29927/30306 |
| PlaytimeResult | RE | OnClientEvent(id) | L29935 |
| AlienAction | RE | :FireServer("fire") / ("shield") — argless | L36046/36097 |
| AlienCue | RE | OnClientEvent(kind, payload) Line/Team/Attack/… | L36201+ |
| HwAction | RE | :FireServer("fire") / ("shield") — argless | L45967/46037 |
| HwCue | RE | OnClientEvent Line/… | L45233 |
| VerityAction | RE | :FireServer("throw", headPos, dirUnit) | L39133 |
| VerityCue | RE | OnClientEvent(kind, payload): End/Throw{Char,From,Dir,Dist,Hit}/Dodge{T0,Dir,Amp}/Hit{HP,Pos,By}/BarLost/…/generic phase set; "Fight" payload {Seed,StartAt,Hover,Min,Max} builds VerityPath | L38731+/39846 |
| LaptopFightCue | RE | OnClientEvent(kind, payload): End/Pay{Work,Hits}/Swing{UserId,Char}/Break/Hit/Wait/Meeting/Leave/FreeForAll/Fight{EndsAt}/King{UserId,Char} | L57383 |
| LaptopFightAction | RE | :FireServer("swing") / ("hit", {≤4 models}) | L56897/56962 |
| RoundCue | RE | OnClientEvent("Alarm"/"HammerImpact") | L7650 |

### Rule 11 REMOVE list (verified useless/dev/one-shot/ROBUX)
- AdminAction/AdminOpen/AdminResult (admin-only, AdminClient L12151+)
- StudioTestPanel wires (dev ForceMode/HwTestStart/Trigger/StartNow/EndNow/
  Short/Cooldowns, L32901+; remote likely fires only in Studio)
- BuyButter/BuyPaper/BuyPhone/ShopResult (manual one-shot shop purchases)
- SkinAction/SkinResult (Equip/Buy one-shot UI incl. "Coffin" quest skin)
- GroupAction/GroupResult "check"/"seen" (one-shot group-join claim,
  GroupRewardClaimed attr)
- AdAction "watch" (manual rewarded-ad flow, prompts a product purchase)
- ResetCharacter (one-shot chair reset)
- LookDirection (UnreliableRemoteEvent, cosmetic head replication L13918)
- ServerHop/ServerHopFailed (template has its own Serverhop)
- PhoneAction "open"/"send"/"close" (Old Phone stress text — boss-visible
  same class as squishy but multi-wire; left manual, documented)
- DeviceInfo/GlobalAnnouncement/HackFx/BobuxResult/BossAnnouncement/
  CaughtCinematic/StressCinematic/DayOff* (server→client display /
  DayOff party minigames — FindButtonPress needs a live raycast click,
  PaperToss "throw" direction + HotCoffee/MusicalChairs are physical
  party games, all reward 25 Bobux split; left manual)
- PlayerPresentation "Vote"/"Aim" (presentation pointers — chat/social
  activity, no automation value)

## ESC — exploit surface beyond remotes (§26)

- **26.1 Attributes**: census done (71 MeetingJoined … 4 MeetingEliminated).
  All gameplay attrs are SERVER-SET and client-READ (RoundPhase, WorkProgress,
  Bobux, BossState, WatchedUserId, Playtime*, HackReadyAt, WarTeam…). No
  client-writable attribute feeds a server reader anywhere in the client dump
  (the only SetAttribute calls are on client-local UI/sound instances, e.g.
  "Stamp"/"P"/BevelThickness + the tutorial's local mock state). NEGATIVE —
  no forge vector.
- **26.2 Save/persistence**: no DataStore API in the client dump (server-side
  only). Client-authoritative stat-sync: NONE — all currency/work flows
  server-side through SubmitEmail/ClaimPlaytime/BuyUpgrade acks. NEGATIVE —
  nothing to inject; the playtime claim is server-elapsed (PlaytimeStart
  server timestamp, not client-reported).
- **26.3 Mutable client-trusted tables**: RS modules ARE require-able and
  mutable locally (CareerConfig/HackRhythm/VerityPath/DayOffConfig…) but
  every server decision (pay, prices, grades, rewards) is computed
  server-side from its own copies — the client tables only render UI.
  Mutating e.g. CareerConfig.Playtime locally changes only the display.
  NEGATIVE — display-only, no server reads them back.
- **26.4 Module hooking / no-cooldown**: client-side cooldown gates exist
  (smack 0.25s, squishy 7s, paper PaperReadyAt, hack HackReadyAt, fire
  interval 0.085) but ALL are re-checked server-side (attrs are server-set
  timestamps: PaperReadyAt/HackReadyAt/PhoneReadyAt replicate FROM the
  server; firing early is rejected/dropped). The rate gates we port are the
  game's own client rates. No bypass found — the remotespace is fully
  server-authoritative. NEGATIVE.
- **26.5 Numeric injection**: numeric args in wires: quiz option index (int,
  graded against server key), hack tap servertime (float — timing judged by
  |Δ|, NaN makes every comparison false → auto-Miss at best, no gain),
  playtime tier index (int, bitmask-checked), upgrade Kind (string enum).
  No price/amount field is client-supplied anywhere. NEGATIVE.
- **26.6 Byte/Instance injection**: no client-supplied string persists
  verbatim (email answers are enum strings; no chat-persisted fields in the
  client dump). NEGATIVE.
- **26.7 Ownership/replication exceptions**: standard character physics only;
  the game does not gate rewards on character position (all minigame wires
  are remote-driven with server-side geometry checks — the laptop-fight hit
  list is re-validated server-side per LaptopFightConfig bounds). ThrowPaper
  target + Verity throw dir are client args but server-validated
  (HitRadius/aim checks per configs). NEGATIVE beyond the normal TP/aim
  quality-of-life.
- **Net read**: this game is a cleanly server-authoritative design; the
  exploit surface IS the automation surface — fast correct answers, event
  responses inside their windows, and rhythm-perfect taps. The build wires
  exactly that.

## Build design (DGF1)

Folder: Yuri/DontGetFired/DontGetFired.lua → delivered as
"Don't Get Fired At Work! 🧳 [LIMITED SKIN EVENT! ]/Don't Get Fired At Work!
🧳 [LIMITED SKIN EVENT! ].lua" (folder-mode convention).

16 toggles + RelaxAt slider on TB_Tabs.Autofarm.T1, divider-clustered
(Core / Events / Extras / Event Games), plain ids, zero comments, inline
pcall steps, one code path (no place branching — features no-op when their
state is absent):

Core: AutoJoin (JoinMeeting when a round is running ∧ MeetingJoined~=true ∧
not ReturnToMenu/DayOff, 2s retry), AutoWork (state mirror via GetState +
StateUpdated listener; per email: SetLaptopView(true) → SubmitEmail(Token,
classify(Email)) at the game's own 0.8s rate → SetLaptopView(false) when
inbox empties; skip while Recovering or boss PRESENTING; classification =
IsScam→DELETE else word-prefixes approv/aprob/aprueb/apru→APPROVE,
forward/reenv→FORWARD, Kind=="WRITE"→WRITE, else skip+Notify), AutoSmack
(0.25s × SmacksLeft), AutoAds (new ScamAds ids → DismissScam, 0.2s stagger),
AutoInterrupt (Call→"decline" once; Update→"click" every 0.1s while the
interrupt id persists).

Events: AutoEvents (RollCallAsk→("here",Id) immediate; PrinterKick→("kick",
Id) at 0.05s until local count ≥ Need ∧ window; DancePicked∧UserId==mine→
("dance",Id) at 0.2s inside [StartsAt,EndsAt]), AutoQuiz (exact compliment
match → BossQuizAnswer(Id,i) when ReadyAt≤now; unmatched → skip), AutoHack
("start" when HackReadyAt≤now ∧ not boss-behind-me ∧ not late-locked; on
active Chart schedule per-note taps at RoundStart+note.t firing
("tap",Id,Round,note.d,RoundStart+note.t) — |Δ|=0 ≤ PERFECT 0.09; Local
charts excluded), AutoPaper (fight windows per the game's own tbl6(): Paper
Fight event window → nearest other-WarTeam seated player with Head, or
Countdown>5s window → nearest other joined player; 0.3s rate in-window,
unlimited per the game).

Extras: AutoRelax (Pressure ≥ RelaxAt ∧ ButterSquishy tool in backpack/
character ∧ boss distracted (absent/LEAVING or BEHIND_PLAYER on someone
else) → UseRelaxItem(tool), 7s per squeeze), AutoClaim (CareerConfig.
Playtime tiers, elapsed ≥ tier ∧ bit clear in PlaytimeClaimed →
ClaimPlaytime(k), one-shot memo), AutoUpgrade (cheapest next of
Paper/Phone ladders when Bobux ≥ price ∧ level < max ∧ Rank attr ≥ tier
Rank, one-shot memo per level).

Event Games: AutoAlien (AlienPhase Fight/Finale ∧ not dodging/zapped →
"fire" at FireInterval 0.085; AlienWarnId change → "shield" once per id),
AutoHalloween (same shape on Hw attrs), AutoVerity (Fight phase payload →
VerityPath mirror → ("throw", head+0.2, lead dir) at ThrowRate 0.28; Dodge
cue → path:AddDodge), AutoLaptopFight (Fight cue → "swing" at 0.55, after
0.16 "hit" with the ≤4 nearest valid targets ported verbatim from the
game's own hitbox check).

All features read state from the Shared mirror (Shared.ME = the last
state push; Shared.Boss = workspace.Boss attrs read live; cue-driven
features via SafeConnect listeners registered after PopulateRemotes).
