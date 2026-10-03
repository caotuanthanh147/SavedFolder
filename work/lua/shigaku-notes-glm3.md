# Shigaku notes — glm3 supplement to shigaku-analysis.md (SH1, glm2)

My independent census ran in parallel with glm2's SH1 (collision mediated by
glm1 07:42Z — accepted: glm2's file is canonical). This file = ONLY my
additions/corrections. Wire rows that duplicate glm2's table are omitted.
Everything below verified at deobf call sites by glm3, session 3.

## 1. Full bridge census (65 — glm2 said ~60)

From `Bridge = "..."` across Game_Settings (lines 168449-172200):
Archery.Match/Sync, Bank.Action, Basketball.Action/Match/Sync, Bee.Exam,
Board.Action, Boxing.Match, Carry.Sync, Chair.Sync, Chalk.Sync, Chamber.Action,
Character.Action/Reject, Chess.Sync, Clap.Game, Clock.Sync, Codes.Action,
Combat.Sync, CombatTag.Apology/Sync/Test, Dekopin.Duel, Dodgeball.Sync,
Donations.Action, Door.Sync, Emotes.Duo/Fx, Falls.Impact, Gangs.Public,
Gifts.Action, Grapple.Sync, Grip.Sync, GroupReward.Action, Gym.Sync,
HeadLook.Update, Hygiene.Sweat, Knock.Sync, Knockoff.Sync, LaunchBonus.Action,
Locker.Sync, Maim.Sync, Music.Action, News.Sync, Nico.Action, Phone.Sync,
Policy.Sync, Prefs.Action, Ragdoll.Sync, Rhythm.Band, ServerOps.Action,
Servers.Action, Soccer.Sync, Spending.Action, Storage.Sync, Students.Speak,
TrashBin.Sync, Uno.Table, Vending.Action, Volleyball.Match/Sync, Wardrobe.Sync,
Weapons.Sync, Zodiac.Exam.

## 2. Wires glm2's table doesn't cover

### TrashBin.Sync (Client.TrashBin L141834; config L170062)
- `{T="Take", Bin=<ProximityPrompt>}` — L142392/142439. Prompts named
  "TrashBinPrompt" under models tagged "TrashBin" (CollectionService), prompt
  dist 8, 0.35s debounce, one at a time (HoldingTag "HoldingBin" on char).
- `{T="Throw", At=<Vector3>}` — L142333 (client sets HRP CFrame to face At
  first; ThrowCooldown 1.2s, Range 40). `{T="Drop"}` — L142344.
- Candidate "Auto Trash Run" job loop (Take→carry→Throw at a trash can) —
  NOT claimed by anyone; open if the user wants economy farming.

### One-shot claims (recorded for completeness; glm2 Rule 11 REMOVE concurred)
- GroupReward.Action `{Action="Claim"}` L153742 (client gates via own
  Claimed()).
- LaunchBonus.Action `{Action="Claim"}` L154279.
- Vending.Action `{Action="Buy", Drink=id}` L49973, `{Action="PutDown"}` L49712.

## 3. Client-authoritative exploit: Posture (combat stamina/guard)

`PlayerScripts.Client.Posture` (L18536) is fully client-side:
`Posture.Get/Add/Reduce/Sync(n)/GetMax()` — `Sync(n)` sets the value
directly. Sprint drains it client-side (Client.Sprint L4790 Heartbeat loop);
blocking/parry costs are client-composed. "Infinite Posture" toggle =
loop `Posture.Sync(Posture.GetMax())` on the game's own module — infinite
sprint + infinite guard resource. NOT in glm2's SH2 plan; offered to glm2
(SH2 host) in msg — their call whether it fits the round's scope.

## 4. Combat wire deep-dive (agrees with glm2; extra detail)

- Swing `Id` = LOCAL incrementing counter (num8, L6291-6293), not target id.
- Hit `Charge` = `ChargeTime()` (Charge module L7504): blackFlash anim
  "Impact" keyframe time, else `Game_Settings.Combat.BlackFlash.ChargeTime`
  (0.45) — a constant for practical purposes; included in every Hit fire.
- The Predict cache (L5270s) is client-side hitstop feel only, NOT in the
  wire — raw Hit fires without predictions are wire-identical to the game's.
- Target filter before Hit fire: seated chess players skipped (L5236-5247,
  `Chess.Attributes.Seated` on the player).
- Style constants (Styles table L168633, assigned to Combat.Styles L168791):
  Basic {StringLength=4, SwingDuration=0.45, HitDelay=0.245, AttackDebounce=
  0.38, ComboWindow=2, HitRange=7, HitAngle=0.6}, Karate {0.38/0.2, HitRange
  7?…}, per-style HitRange/HitAngle feed `Hitbox.Query(hrp, {Range, Angle})`.
- glm2's Auto Attack via `Input.Fire("Combat.Attack")` is the better strategy
  than my raw-wire draft (game composes its own wires — max fidelity). My
  raw-wire table above stays as documentation/backup.

## 5. Rule 11 concurrence

I originally kept GroupReward/LaunchBonus claims (ST4 precedent) and Auto
Attend (enter-world from SlotSelect, L96225/96554 — one button, spawn-time
only). glm2's stricter reading (one-shot UI = REMOVE) is correct per the
§3-codified standard-autofarm scope — concurred, both dropped from my plan.
My cluster: Auto Roll (accepted from glm2's split offer).
