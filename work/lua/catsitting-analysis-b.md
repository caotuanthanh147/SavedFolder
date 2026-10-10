# 7 Days Cat-Sitting — analysis (CS1)

Source: Public 261c46e (2026-10-10) — `cat/7 Days Cat-Sitting (GAME)/` (deobf 3,786 + dump 9,368)
+ `cat/7 Days Cat-Sitting/` (deobf 1,689 + dump 17,781) + `cat/videotranscript.txt`
(user-supplied mechanics walkthrough: "the game is kinda complicated so I'll put this
here just to be sure"). User order: plain "next game" — standard autofarm, no
genre-specific tooling. One experience, two places; one script with place detection,
delivered to both folders (Plunder precedent: same file MD5-identical in both).

## Places

- GAME place (house): `workspace.House` + `workspace.Neighborhood` + `workspace.Cat`.
- Lobby place: `workspace.Lobby` (CatShop counter prompt + TeleportPod party entry).
- Detection: `workspace:FindFirstChild("House")` vs `workspace:FindFirstChild("Lobby")`.

## Wire census (verified at client call sites)

### GAME place (all RemoteEvents, direct, no wrapper layer)

| Remote | Client call site | Shape |
|---|---|---|
| Phone.Reply | L574 `var16.Reply:FireServer(arg1)` | `(message: string)` — owner chat |
| Phone.Photo | L2341 `var11:FireServer(var5, var1)` | `(cameraCFrame, raycastHitInstance)` — CameraController.Snap; ray 60 studs from camera, 0.3s after shutter |
| Meal.Eat | L1088 `str2:FireServer()` | `()` — fired from Tool.Activated when tool has attrs Meal+Hot (L1082-1089) |
| Tutorial.Skip | L1171 | `("Vote"\|"Unvote")` |
| Cat.Pet | L1297 `tbl1:FireServer()` | `()` — input gate: raycast 40 studs hit descendant of workspace.Cat, CLIENT cooldown 0.35s (L1291-1296) |
| Cat.Stare | L1956 `tbl1:FireServer(track)` | `(accumulatedSeconds: number)` — CLIENT-computed stare time, batched ≥0.4s (L1951-1959); stare UI gated by workspace attrs CreepyHead/CreepyStare (L1932, L1962) |
| Laser.Point | L954/985/1003/1027 | `(Vector3\|nil, bool)` — laser dot position ≥0.05s interval while Laser tool held (L983-986); nil+false = stop; tool detected via `Tool:GetAttribute("Laser")` (L1008) |
| LitterCleaning.Event | L2812/2816/2822/2841/2931/2981 | `("Grab", sessionId, index)` / `("Drop", sessionId, index, x, y)` / `("AbortDrag", sessionId)` / `("Cancel", sessionId)`; session id from server "Start" (L2954); in-bag = bag rect vs drop position (client computes inside(); server confirms "Collected" per index with found count) |
| Ending.Vote | L1488 | `(bool)` — restart vote |
| Ending.Lobby | L1494 | `()` |
| Ending.Revive | L1499 | `()` |

### GAME place server→client (state channels, not fired by us)

Night.Event ("Cut"/"Sleep"/"Night n"/"Wake"), Night.Attack/Cutscene/Jumpscare/Shake/Run,
Objective.Set (task banner text), Phone.Message/Typing, MailTask.Effects ("Sound"/"Collect"),
Meal.Audio, FeedingAudio.Event, Tutorial.Skip count, Ending.Show/Voters/Hide,
LitterCleaning.Event ("Start"/"Retry"/"Collected"/"Win"/"End").

### Lobby place (RemoteFunctions)

| Remote | Call site | Shape |
|---|---|---|
| Shop.GetState | L598 `pcall(tbl1.GetState.InvokeServer, tbl1.GetState)` | `() -> state {cash, owned, equipped}` |
| Shop.Buy | L515 | `(variantName) -> (ok, state)` |
| Shop.Equip | L509 | `(variantName) -> (ok, state)` |
| Shop.OpenCrate | L755 | `() -> {ok, reason?, state, reel}` — reel is SERVER-authored display sequence; result.state updated incl. on failure |
| Shop.CrateInfo | dump L515 (no call site in deobf — UI reads via crate cards) | info-only, not wired |
| Endings.Get | L160 | `() -> endings map` (display) |

## World model (GAME place) — prompt inventory (all ProximityPrompt, Room attrs)

- Sleep: `House.Parts.Bedroom.Mattress.SleepPromptAttachment.SleepPrompt`
- Litter: `House.Parts.Laundry.LitterBox.LitterInteraction.CleanLitterPrompt` (starts minigame → Grab/Drop wires)
- Feed: `House.Important.Kitchen.Cabinets.Base_N1.CatFoodCan...TakePrompt` + `House.Important.Kitchen.FoodBowl.Food Bowl.Cylinder.FillPromptAttachment.FillPrompt`
- Eat: `Kitchen.Fridge.TVDinner.Tray.TakePromptAttachment.TakePrompt` → `Kitchen.Cabinets.Microwave.Carcass.Turntable.CookPromptAttachment.CookPrompt` (cook) → Meal.Eat remote on the held hot-meal tool
- Mail: `Neighborhood.Parts.PetsitFrontYard.Mailbox.Body.MailPromptAttachment.MailboxPrompt`
- Lock: `Important.Doors.Front Door.Leaf.Deadbolt.LockPromptAttachment.LockPrompt` (+ UnlockPrompt)
- ToiletFace counter: `Bathroom.Toilet.Flush.Lever.FlushPromptAttachment.FlushPrompt`
- Catzilla counter: `LivingRoom.TV.Screen.TogglePromptAttachment.TogglePrompt`
- VoidOutside counter: 8× `Parts.InteriorLayout.Curtains.*.BlindsPromptAnchor.BlindsPrompt` (01–08)
- Grandma-dark counter: 7× `Important.RoomLighting.Switches.*Switch.Faceplate.Interaction.LightSwitchPrompt` (Bathroom, Bedroom, BedroomHall, LivingRoom, EntryHall, Kitchen, Laundry); room light state readable from `RoomLighting.Rooms.<Room>` children `.Enabled`
- Laser tool: tools detected by `Tool:GetAttribute("Laser")` in character (L1008); spawn template `RS.Laser.Laser Pointer`
- Doors OpenClosePrompt ×4 (avoid FakeDoor: no auto door interaction at all)

Room gating: PhoneRunner L791-877 toggles every tracked prompt's MaxActivationDistance to 0
when the player is in a different room (captured dist otherwise). fireproximityprompt ignores
distance, but FirePP's own teleport check (`> MaxActivationDistance`) still routes through
TPTo — game's own flow preserved.

## State machine (workspace attributes — server-owned, read-only for the client)

Chore flags: Chore_Eat / Chore_Feed / Chore_Litter / Chore_Lock / Chore_Mail / Chore_Play.
Anomaly flags: Catzilla, CreepyHead, FakeDoor, Grandma, Misplaced, Seeker, SmilingMan,
StalkerInBedroom, ToiletFace, VoidOutside, WindowMonster. Progress/state: Night,
PerfectRun, PetCount, CreepyStare (0–1 progress for the stare UI), HostUserId,
CatSelectionComplete, SelectedCatVariant. Threat_* = per-anomaly selection weights.
All attr writes in the deobf are on instances server-side of replication (workspace,
prompt Room attrs, tool Meal/Hot/Laser attrs set by server) — the flags are the
game's public state board and our loop sensors.

## ESC — exploit surface beyond remotes (§26 census)

- **26.1 Attributes**: NEGATIVE for forgery — every client-visible SetAttribute in the
  deobf writes GUI-local state (L415-427 badge) or reads server-owned flags; no
  server-read client-writable attribute found. Positives for sensing: the workspace
  attr board above drives AutoChores/AutoAnomaly.
- **26.2 Save/persistence**: UNVERIFIABLE from dump (no server scripts; zero DataStore
  refs anywhere in either dump). Lobby shop state is server-owned (GetState RF);
  OpenCrate reel is server-computed — no client slot-pick (gacha is server-side).
  Phone.Reply strings show no persistence path. Documented-negative.
- **26.3 Mutable client-trusted tables**: NEGATIVE — RS.CatSkins catalog read for
  display only; RoomBounds Min/Max attrs read-only; no client-gated config table.
- **26.4 No-cooldown module hooks**: POSITIVE (wired): Cat.Pet's 0.35s cooldown
  (L1291-1296), Litter pick 0.2s (L2833), Laser 0.05s rate (L983) are ALL client-side
  only — our loops fire the remotes directly (the game's own wires, no fabricated args).
- **26.5 Numeric injection**: POSITIVE (wired): Cat.Stare:FireServer(track) carries a
  CLIENT-computed accumulated duration — the stare task completes by staring ~N seconds;
  AutoAnomaly fires the full progress value directly (polarity: server adds track to
  progress; any positive ≥ remaining completes it). Laser.Point position and Litter
  Drop x/y are also client-authored numerics — documented, NOT wired (Play chore needs
  real dot movement; litter Collected is server-confirmed).
- **26.6 \255 / Instance injection**: NEGATIVE (documented): no client string that
  persists — Phone.Reply is chat display; no save pipeline visible.
- **26.7 Ownership/replication**: standard character physics; TPTo for chore movement;
  laser dot positions replicate serverward by design (that IS the mechanic).

## Feature set (Rule 11 filter)

GAME place: **AutoChores** (feed→fill, take→cook→eat, mail, lock, litter minigame via
Grab/Drop, driven by Chore_* flags), **AutoPlay** (equip Laser tool, move dot near cat —
small back-and-forth arc, never circling the cat: black-hole ending is over-spin),
**AutoPet** (direct Cat.Pet loop — bypasses the client cooldown legitimately),
**AutoSleep** (bed prompt when chores are complete → next night),
**AutoAnomaly** (attr-flag driven: CreepyHead→Cat.Stare full progress (26.5),
ToiletFace→Flush, Catzilla→TV, VoidOutside→all Blinds, Grandma→lights off,
SmilingMan/WindowMonster/Stalker/Seeker→Phone.Photo aimed at the workspace clone;
FakeDoor intentionally untouched — counter-anomaly). Lobby place: **AutoCrate**
(OpenCrate invoke loop, server cash-gated). No stats labels, no teleport tab (small
map), plain ids, elements on TB_Tabs.Autofarm.T1, inline resolution, zero comments.

## Unverified / open

- Server-side validation depth of Photo(cframe, instance), Stare(track), Pet rate:
  dump carries no server scripts. Build uses faithful flows (teleport near + aim
  before Photo; single Stare completion fire; pet at a human-ish 0.5s pace).
- Misplaced anomaly: which instance is displaced is server knowledge — AutoAnomaly
  handles photo-able clones only; misplaced/photo-at-distance stays manual.
- Laser Play completion condition (server-side chase tracking) — AutoPlay moves the
  dot through a short arc near the cat and lets the server's own chase logic score it.

## Cross-check vs glm1's catsitting-analysis.md (origin, 03:53Z)

Independently arrived at the same wire table/world model/ESC verdicts — both
censuses verified every call site separately. Corrections to glm1's table
(verified at the lines):
- Tutorial.Skip carries `("Vote"|"Unvote")` (L1162 resolution + L1171 call), NOT
  bare `()` — glm1's row garbled it and duplicated the line cite.
- Ending.Vote carries `(bool)` (var14 = RS.Ending.Vote, L1480/L1488), NOT
  "Vote"/"Unvote" (that's Tutorial.Skip's shape).
- Light switches: 7 (Bathroom, Bedroom, BedroomHall, LivingRoom, EntryHall,
  Kitchen, Laundry) — dump lists 14 because the world is dumped twice; glm1
  counted 8. Curtains: 8 ✓ (16 dumped).
- Laser pointer takeable instance: `Workspace.House.Important.LivingRoom.
  LaserPointer.Body.TakePromptAttachment.TakePrompt` (RS.Laser.LaserPointer is
  the unparented template model; PointerSpawn attr on RS.Laser = spawn CFrame).
Adopted from glm1's plan (better than mine): AutoQueue (lobby TeleportPod
TP+FireTI), AutoSleep's fail-safe gate (all chores true AND all anomaly flags
false), Misplaced photo sweep (candidates until flag flips), microwave
door→cook sequence, GetAttributeChangedSignal listeners via SafeConnect for
anomaly flags. My §26.5 wiring stands (Cat.Stare client-authored seconds —
bounded 5s batches per 0.4s tick, not inf/NaN: no reason to break a number
that already trusts us).
