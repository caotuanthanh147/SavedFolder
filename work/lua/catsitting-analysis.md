# 7 Days Cat-Sitting — analysis (CS1, glm1, 2026-10-10)

Two-place round, Public 261c46e. Places:
- `cat/7 Days Cat-Sitting` — LOBBY/menu place (deobf 1688 lines): EndingsGui catalog,
  CatShop (cash + ROBUX cards), crate, TeleportPod → game, leaderstats.Cash.
- `cat/7 Days Cat-Sitting (GAME)` — GAMEPLAY place (deobf 3786 lines): the house,
  cat care chores, litter minigame, laser play, phone camera (anomaly photos),
  anomaly survival loop (workspace-attribute oracle), endings + return-to-lobby.
- `cat/videotranscript.txt` — user-supplied gameplay guide (night loop + anomaly
  responses). Used as the FEATURE-INTENT reference (which responses exist), never
  as a wire source (Rule 2 — every wire below is deobf-verified at its call site).

Genre: single-player anomaly-survival chore loop. No reference script, no
Template in folder → standard autofarm ONLY (ONBOARDING §3) on canonical
Template.lua (945 lines, 4f0e766). **User clean-coding directive this round
(verbatim intent): no EnsureModules/PopulateRemotes/ConnectListeners wrapper
functions — inline `Root and GetObject(Root, "A.B")` tables + direct
`SafeConnect(key, function() return ev.OnClientEvent end, handler)`.**

## 1. Remote map (all verified at call sites in the deobfs)

### GAME place (client→server)
| Remote | Wire (exact call-site shape) | Line |
|---|---|---|
| `RS.Cat.Pet` RE | `FireServer()` — client gates: raycast 40 studs hits workspace.Cat descendant, 0.35s local cooldown | L1289 |
| `RS.Cat.Stare` RE | `FireServer(accumSeconds)` — every 0.4s while CreepyHead attr true + within 40 studs + LOS + facing (angle < 0.244 rad); CreepyStare attr = fill 0..1 | L1951 |
| `RS.Meal.Eat` RE | `FireServer()` — on Tool.Activated where tool attrs Meal=true AND Hot=true | L1087 |
| `RS.Laser.Point` RE | `FireServer(Vector3 pos, true)` at ≥0.05s while Laser-attr tool in character; `FireServer(nil, false)` on stop/unequip | L954/985/1003/1027 |
| `RS.Phone.Photo` RE | `FireServer(cameraCFrame, raycastInstanceOrNil)` — Snap: 60-stud ray from camera LookVector (excl. character); CFrame = workspace.CurrentCamera.CFrame | L2319 |
| `RS.Phone.Reply` RE | `FireServer(messageText)` — phone chat send | L573 |
| `RS.Tutorial.Skip` RE | `FireServer("Vote"/"Unvote")` — the skip-vote UI button (CORRECTED by main-agent cross-check L1162+L1171; originally garbled as bare one-shot) | L1171 |
| `RS.LitterCleaning.Event` RE | `FireServer("Grab", sessionId, index)` / `("Drop", sessionId, index, xScale, yScale)` (inside-bag coords) / `("AbortDrag", sessionId)` / `("Cancel", sessionId)` | L2841/2803/2816/2822 |
| `RS.Ending.Lobby` RE | `FireServer()` — return-to-lobby button (one-shot UI) | L1494 |
| `RS.Ending.Revive` RE | `FireServer()` — one-shot UI | L1499 |
| `RS.Ending.Vote` RE | `FireServer(bool)` — CANCEL/RESTART button state (CORRECTED by main-agent cross-check: var14=RS.Ending.Vote L1480, fired with bool1 L1488; my original row had the Tutorial.Skip args on this remote) | L1488 |

### GAME place (server→client, state/visuals — listeners, never fired by us)
| Remote | Events | Line |
|---|---|---|
| `RS.Night.Event` | "Cut" / "Sleep" / "Night" (nightNum) / "Wake" | L1113 |
| `RS.Night.Attack` | "Start" (camera shake) | L1604 |
| `RS.Night.Cutscene` | "Bed" (camCFrame, lookAt) | L1624 |
| `RS.Night.Jumpscare` | (name, duration, variant) — clones RS.Jumpscares[name] | L1766 |
| `RS.Night.Shake`/`RS.Night.Run` | visuals | L1969/1994 |
| `RS.Objective.Set` | `Set(text)` — objective banner text, "" clears | L2695 |
| `RS.LitterCleaning.Event` | "Start"(sessionId) → "Retry"(sid, index) → "Collected"(sid, {index=, found=}) → "Win"/"End"(sid, msg) | L2947+ |
| `RS.Phone.Message`/`Typing` | incoming NPC texts / typing dots | L758/767 |
| `RS.MailTask.Effects` | "Sound"(name, part) / "Collect"(cframe, part) | L3289 |
| `RS.FeadingAudio.Event` | "Pickup"/"Fill"(part) | L3138 |
| `RS.Meal.Audio` | meal sounds | L3360+ |

### LOBBY place (RemoteFunctions)
| Remote | Wire | Line (lobby deobf) |
|---|---|---|
| `RS.Shop.GetState` RF | `InvokeServer()` → state table {cash, owned, equipped} | L598 |
| `RS.Shop.Buy` RF | `InvokeServer(itemId)` → (ok, reason, state) — one-click UI, REMOVE | L515 |
| `RS.Shop.Equip` RF | `InvokeServer(itemId)` → (ok, state) — one-click UI, REMOVE | L509 |
| `RS.Shop.OpenCrate` RF | `InvokeServer()` → {ok, reason, state, reel}; client cost gate `state.cash < 10` (CrateInfo never invoked by the game — var32 nil → default 10) | L755/735 |
| `RS.Shop.CrateInfo` RF | never called by the game client (var32 stays nil, cost falls back to 10) — mirror: do not call | L666-673 |
| `RS.Endings.Get` RF | `InvokeServer()` → endings catalog (display only) | L160 |

## 2. World model (GAME place — dump-verified paths)

- Cat: `workspace.Cat` (Model; attrs AIState/AIEnabled/Hold; CreepyCatHead child
  appears when CreepyHead anomaly active).
- House prompts (all under `workspace.House.*`, ProximityPrompt instances,
  48 total — key ones):
  - Feed: `Important.Kitchen.Cabinets.Base_N1.CatFoodCan.CanBody.TakePrompt` (TakePrompt),
    `Important.Kitchen.FoodBowl.Food Bowl.Cylinder.FillPrompt` (FillPrompt)
  - Eat: `Important.Kitchen.Fridge.TVDinner.Tray.TakePrompt`,
    `Important.Kitchen.Cabinets.Microwave.Door.Leaf.Panel.OpenClosePrompt`,
    `Important.Kitchen.Cabinets.Microwave.Carcass.Turntable.CookPrompt`
  - Litter: `Parts.Laundry.LitterBox.LitterInteraction.CleanLitterPrompt`
  - Mail: `Neighborhood.Parts.PetsitFrontYard.Mailbox.Body.MailboxPrompt`;
    lock: `Important.Doors.Front Door.Leaf.Deadbolt.LockPrompt` (+ UnlockPrompt sibling)
  - Sleep: `Parts.Bedroom.Mattress.SleepPrompt`
  - Laser: `Important.LivingRoom.LaserPointer.Body.TakePrompt`
  - Anomaly responses: 8× `Important.RoomLighting.Switches.*.Faceplate.Interaction.LightSwitchPrompt`,
    8× `Parts.InteriorLayout.Curtains.*.BlindsPrompt`, `Important.LivingRoom.TV.Screen.TogglePrompt`,
    `Important.Bathroom.Toilet.Flush.Lever.FlushPrompt`
- Litter UI: `PlayerGui.LitterCleaningGui.Panel.Board.Bag` (Bag frame → inside()
  checks Position/Size scales) — Drop coords = bag-area scale coords.
- Chore marker: `RS.Tutorial.ChoreMarkerState.Target` (ObjectValue — server sets
  the current chore's target instance; the game's own waypoint oracle).
- Laser dots: `workspace.LaserDots.<userid>` per player; own dot hidden locally.
- Lobby: `workspace.Lobby.Important.TeleportPod` (Floor/GlowEdge×4/ExitPart/Zone);
  `workspace.Lobby.Parts.CatShop` (+CatShopPrompt on CounterTop).

## 3. ESC census (§26 — the standing directive)

- **§26.1 Attributes — HEADLINE FINDING: the workspace attribute block is a
  complete server-state oracle.** `workspace:GetAttribute` exposes: 6 chore flags
  (Chore_Eat/Feed/Litter/Lock/Mail/Play), 11 anomaly flags (Catzilla, CreepyHead,
  FakeDoor, Grandma, Misplaced, Seeker, SmilingMan, StalkerInBedroom, ToiletFace,
  VoidOutside, WindowMonster), PetCount (number), Night (number), CreepyStare
  (0..1 fill), PerfectRun, TutorialDone, SelectedCatVariant, Threat_* levels,
  HostUserId, CatSelectionComplete (dump L193-232; client reads TutorialDone at
  deobf L2026, CreepyHead L1932, CreepyStare L1962 — the rest are server-set,
  client-readable). Read-only for us (workspace attrs do not replicate
  client→server) → WIRED as the gating oracle for every Auto feature (chore
  completion checks, anomaly-response triggers, sleep gating). This is the FNAF
  miss corrected: the attribute layer is the backbone of this build.
- **§26.1 tool attrs**: Laser / Meal / Hot on Tools (client reads L1008/1083).
  Client SetAttribute on backpack/character tools does not replicate (server
  owns the instances) → forging Hot on a cold meal NOT viable; checked, not wired.
- **§26.2 Save system**: no DataStore calls client-side (server source not in
  dump). Shop state is server-authoritative via GetState/OpenCrate returns
  (cash/owned/equipped validated server-side — OpenCrate returns
  {ok=false, reason="cash"}). leaderstats.Cash IntValue = server-owned display.
  No client-authoritative stat-sync wire exists → checked, none.
- **§26.3 Mutable client-trusted tables**: only client modules are
  PromptPolicy.Policy (forces ClickablePrompt=false — UI-only, no economy) and
  CatAnimationTracks (data). No Prices/Cooldowns/Rates config tables → checked, none.
- **§26.4 Module hooks / cooldowns**: Cat.Pet 0.35s and Laser.Point 0.05s
  throttles are CLIENT-side locals (tbl2/num1 gates) — our features fire the
  remotes directly at the game's own cadence or slower (Pet 0.4s, Laser 0.1s);
  no hookfunction needed. Photo has no client cooldown. → direct-fire = the bypass.
- **§26.5 Numeric injection**: Cat.Stare(seconds) and Laser.Point(Vector3) are
  numeric; no economy/reward arithmetic visible on them → NaN probes not wired
  (no payoff surface; document-only). OpenCrate takes no args.
- **§26.6 \255 rollback**: the only client-supplied persisting string is
  Phone.Reply(text) — single-player NPC chat; no evidence of persistence
  (server source absent) → candidate documented, NOT wired (Reply is a UI-mirror
  feature, Rule 11 REMOVE anyway).
- **§26.7 Ownership/replication**: all movement via template TPTo (instant) on
  prompts (FirePP teleports when out of range) — standard. No reward gates on
  owned-part attrs found.

## 4. Feature plan (Rule 11 filter applied)

KEEP (genuine automation/bypass value — the game's own flows, accelerated):
1. **AutoChores** (GAME): 30s loop — for each of the 6 chores with
   `workspace:GetAttribute("Chore_X") ~= true`, run its flow; Chore attr flips
   verify completion (self-healing retries). Flows (all FirePP, server-validated):
   Feed = CatFoodCan TakePrompt → FoodBowl FillPrompt; Eat = TVDinner TakePrompt
   → Microwave door OpenClosePrompt → CookPrompt → equip Meal+Hot tool → Meal.Eat
   fire; Litter = CleanLitterPrompt → minigame responder (below); Mail =
   MailboxPrompt (outside) → Front Deadbolt LockPrompt; Play = LaserPointer
   TakePrompt → equip → Laser.Point fires near the cat until Chore_Play; Lock =
   Deadbolt LockPrompt.
2. **Litter minigame responder** (inside AutoChores): SafeConnect on
   LitterCleaning.Event OnClientEvent — "Start"(sid) → for i=1..5 (skip
   collected): Grab(sid, i) → Drop(sid, i, bagX, bagY from the live Bag frame);
   "Retry"(sid, i) → re-Grab/Drop; "Win"/"End" → done. Toggle-off → Cancel(sid).
3. **AutoPet** (GAME): 0.4s fire Cat.Pet when within 40 studs of workspace.Cat
   (PetCount attr = visible feedback; cadence mirrors the game's own 0.35s gate).
4. **AutoAnomalies** (GAME): GetAttributeChangedSignal listeners on the 11
   anomaly flags → once-per-event responses (video-mapped, deobf-path-verified):
   Grandma → fire all 8 LightSwitchPrompts (lights off); VoidOutside → all 8
   BlindsPrompts (curtains closed); Catzilla → TV TogglePrompt; ToiletFace →
   FlushPrompt; CreepyHead → TP within 40 studs of the cat head + Cat.Stare(0.4)
   cadence until CreepyHead false.
5. **AutoPhoto** (GAME): SmilingMan=true → find the cloned SmilingMan model in
   workspace → TP ~12 studs → Phone.Photo:FireServer(CFrame.lookAt(eye, target),
   its BasePart). Misplaced=true → sweep: fire Photo at each candidate furniture
   part under House.Important/House.Parts (top-level models) until Misplaced
   flips false. (Photo fires directly — the camera UI is client-side sugar.)
6. **AutoSleep** (GAME): slow loop — only when all 6 Chore attrs true AND all 11
   anomaly flags false → FirePP Mattress.SleepPrompt. Fail-safe direction:
   wrong semantics = never sleeps (manual sleep remains), never death.
7. **AutoQueue** (LOBBY): TPTo TeleportPod.Zone (engine Touched) + FireTI(Zone).
8. **AutoOpenCrate** (LOBBY): GetState → while cash >= 10 → OpenCrate
   InvokeServer (SafeInvoke), cash from result.state; stop under 10.

REMOVE (Rule 11): Shop.Buy/Equip (one-click game UI), ROBUX ProductId cards
(PromptProductPurchase), Endings.Get (display), Tutorial.Skip (one-shot),
Ending.Lobby/Revive/Vote (one-shot UI), Phone.Reply/Message/Typing (chat UI),
all Night.* server→client (visuals), MailTask/FeedingAudio/MealAudio (sounds),
CrateInfo (the game never calls it).

## 5. Assumptions & risks (documented, §2 where unsourceable)

- **Chore_X semantics** (true = done): initial state all-false at night 1 with
  all chores pending is consistent with true=done; no client read exists to
  confirm. Mitigation: flows are the game's own prompt sequences (server
  validates each); AutoSleep gates on the SAME assumption in the fail-safe
  direction (no sleep if wrong, never sleep-with-pending-chores death).
- **Litter Drop coords**: the server may validate dropped scale-coords against
  the bag area (mirroring client inside()) — we read the live Bag frame's
  Position/Size scales and drop at its center (always inside).
- **Microwave flow order** (door → cook): if the server requires the door open
  before CookPrompt accepts, the sequence retries next cycle until Chore_Eat
  flips; no permanent desync possible.
- **AutoPhoto distance**: video says keep distance from SmilingMan; we photo
  from 12 studs (inside the game's own 60-stud raycast range, outside jumpscare
  range) with a straight lookAt CFrame.
- **Threat_* attrs**: per-anomaly threat levels (night RNG weights) — read-only,
  not used.
- Both places get the SAME script (Periastron/Potato two-place precedent);
  features no-op where their world objects are absent (user's
  `Root and GetObject(...)` inline-guard pattern makes this structural).

## 6. Clean-coding commitments for this build (user directive)

- NO EnsureModules/PopulateRemotes/ConnectListeners wrappers. Remotes/Modules
  resolve inline: `local Remotes = { Pet = GetObject(RS, "Cat.Pet"), ... }` —
  guarded entries (GetObject returns nil on absent paths — the template's
  FindFirstChild walk is nil-safe by construction, matching the user's
  `Root and GetObject(Root, ...)` idiom for direct-under-RS paths where a
  missing ROOT would otherwise index nil).
- Listeners: direct `SafeConnect(key, function() return ev.OnClientEvent end,
  handler)` — one line each, no ConnectListener wrapper.
- Loops: one pcall owner (SafeLoop), Thread+OnChanged wiring, toggle-gated
  while-loops, elements-first, plain ids, 0 comments, dividers between clusters.

## 7. Harness round addendum (real bugs caught, 2026-10-10)

REAL-LOAD harness (catsitting_harness.lua, 56 checks) caught ONE REAL SCRIPT BUG
pre-delivery: **six prompt paths written without their attachment layer** —
`...CanBody.TakePrompt` instead of `...CanBody.TakePromptAttachment.TakePrompt`
(CatFoodCan, FoodBowl, TVDinner, Microwave Cook, LaserPointer, Mailbox, and the
fridge door OpenClosePrompt found in a second pass) — the paths would have
silently no-oped in-game (GetObject nil → FirePP nil-guard). Fixed against the
dump-verified list in §2; the harness now asserts every prompt path resolves +
fires. Also fixed in-section: `dir.Unit` → `dir * (12/dist)` (Unit-free math,
works everywhere).

Harness self-incidents (all §15 closure-scoping class, in MY mock code — the
guide rule exists for exactly this): PLR:FindFirstChild referencing
Backpack/PlayerGui locals declared after it; EquippedLog declared after
Hum:EquipTool; CrateCash declared after mockRemote's GetState closure (returned
cash=nil → AutoOpenCrate gate correctly refused). Plus two mock-fidelity gaps
fixed in the harness: Instance dot-access-to-children (real Roblox behavior,
added via metatable patch) and table.clear (Luau-only, shimmed).

Harness check design notes: litter "Start" sessions are server-simulated from
the CleanLitterPrompt fire (sid counter); Win auto-fires at 5 Drops per sid;
chore completion driven by test-side attribute flips (semantics assumption §5
exercised end-to-end: skip-when-true verified in both directions).

## 8. Parallel-lane cross-check (main-agent CS1-B, 2026-10-10)

CS1-B (user-direct parallel lane) delivered CatSitting.lua Public d82c55a with
an independent census; two corrections to my §1 table adopted above (verified at
their cited call sites): Tutorial.Skip carries Vote/Unvote (L1162+L1171),
Ending.Vote carries bool (L1480+L1488). Also confirmed: 7 light switches
(BedroomHall + EntryHall both Room="Hallway" — the dump double-lists the world);
both builds wire 7 correctly. Neither corrected remote is fired by my build
(both Rule 11 REMOVE — banned-wire sweep asserts zero). FW1 both-land
precedent: their CatSitting.lua + my SevenDaysCatSitting.lua coexist in the
Public folders; user picks.
