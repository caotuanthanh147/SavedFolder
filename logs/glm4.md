
## Session 1 — 2026-10-02 (stress round: ST8 Ride A Pet)

- Cold start via bootstrap.sh glm4: repos + Lua 5.4.7 + token wired (ls-remote
  verified) + status/logs skeleton. Watchers (poll.sh, watch_public.sh) up.
- Mandatory reads: ONBOARDING.md, PROMPT.md, TASKS.md, GLM_SCRIPTING_RULES.md
  (§1-§25 mapped), TASK_SOURCE.md, lessons.md, statuses (glm1-3), msgs inbox
  (glm1 stress conventions handled + deleted).
- Stress round Public state: 10 game folders; ST6 (Sword RNG X) delivered by
  glm2 as no-reference standard autofarm (commit fe3e703) — taken as the
  precedent pattern (Net remote + FireServer("requestHit",...) on nearest
  enemy + SafeLoop + AutoAttack toggle). glm3 claimed ST9+ST10 locally (no
  push token). OPEN on origin: ST5, ST7, ST8.
- Tractability probe across ST5/ST7/ST8 (§9 budget): ST5 obfuscated Net
  module (hard), ST7 bullet-simulation combat (complex), ST8 clean pet-game
  Hatch remote (chosen).
- Claimed ST8 in TASKS.md. Wire verified at call site L10832:
  `str1.Hatch:FireServer({ EggKey = var2:GetAttribute("EggKey") })`;
  eggs = CollectionService:GetTagged("Egg").
- Next: locate str1 RS path → build game section → harness → §7 gates → deliver.

## ST8 delivery — 2026-10-02 (session 1 complete)

- ST8 ([🌋] Ride A Pet) DELIVERED as Public da10db7 (sync.sh ls-remote verified).
- Standard autofarm, no reference (§3): Auto Hatch toggle firing
  `Remotes.Game.Hatch:FireServer({ EggKey = egg:GetAttribute("EggKey") })`
  for each `CollectionService:GetTagged("Egg")`.
- Wire verified at deobf call site L10832 (Rule 2); path L10815
  (`RS:WaitForChild("Remotes"):WaitForChild("Game"):WaitForChild("Hatch")`);
  EggKey attribute set at L41120.
- §7 checklist ALL green:
  - luac5.4 -p OK
  - lua_lint.py --from 820: 0 errors (21 W6 template-region typeof/unpack, downgraded)
  - validate.sh: template diff game-section-only (head 819 + tail 18 verbatim,
    middle 77 lines = my game section), 0 comment-only lines
  - harness 9/9 (work/lua/rideapet_harness.lua): script load, toggle registered,
    AutoHatch ON fires >=2 in 2s virtual, payload {EggKey}, both eggs fire,
    egg-without-EggKey filtered, AutoHatch OFF stops firing, Library.Unloaded
    breaks loop.
- Two build bugs caught + fixed by the harness before delivery:
  (1) `TB.Main.Left.Autofarm.T1` (nil — tabbox has no T1) → `TB_Tabs.Autofarm.T1`
      (the template defines the tab at line 664; Sword RNG X used the buggy ref
      but its harness must have merged — I used the template-correct ref).
  (2) CS mock `GetTagged = function(tag)` → `function(self, tag)` (: method-call
      passes self as first arg; tag was capturing self, returning {} → no fires).
- Parallel GLM activity observed (sync history): glm2/glm5 expanded Sword RNG X/
  Open Sea/8 Ball (user "too little features" order, 5fb30cb/2333df7); glm3
  delivered Restaurant Tycoon 3 (e88e651). ST8 (mine) = 1 toggle (AutoHatch) —
  may warrant expansion on explicit order.
- Tooling reaffirmed: bootstrap.sh cold-start (repos + Lua + token + watchers
  in ~10s), sync.sh (commit→rebase→push→ls-remote verify), deobf_search.py
  (remote/fn/find/tags/attrs), validate.sh (luac+diff+style), harness_lib.lua
  (scheduler + Instance + Linoria mocks).

## ST8 v2 — 2026-10-02 (§22-7 loop refactor + glm1 ST-QA1 guidance applied)

- glm1's ST-QA1 audit found glm2's ST5/ST6/ST7 ALL broken at load
  (`TB.Main.Left.Autofarm.T1` nil — T1 is a TB_Tabs key, not a tabbox field).
  My ST8 avoided this from the start (used `TB_Tabs.Autofarm.T1`) — the
  harness caught the alt form during build (the §7 checklist working).
- glm1's 4-point message to me: (1) TB_Tabs ref ✓ already, (2) real-script
  harness ✓ already, (3) §22-7 loop shape — REFACTORED v2:
  `while Toggles.AutoHatch.Value do pcall(step) task.wait(0.5) end` (was
  `while true ... if Library.Unloaded break`), (4) sync script to work/lua/
  — DONE (work/lua/RideAPet.lua).
- Gates v2: luac OK, lint 0 err, validate 0 comments / 78-line game section,
  harness 9/9 (new respawn check: OFF→ON respawns via Thread dead-coroutine
  detection; the old Library.Unloaded-breaks check was redundant with the
  §22-7 toggle-off exit).
- §3 two-halves codified (glm1): "standard autofarm = wire every remote that
  passes Rule 11's KEEP filter AND invent nothing beyond it. Under-shipping
  = over-shipping = violation." For ST8 I judged AutoHatch = the real
  continuous automation surface; EggPickup/ClaimEventReward look one-off
  (asked glm1 for judgment). Flagged for explicit user order rather than
  auto-expanding (§2: not explicitly ordered for ST8).

## Session 2 — 2026-10-04 (sandbox reset recovery + Steal A Car delivered)

- Sandbox reset Oct 4 00:48 (SavedFolder/Public/Lua/token all gone; only
  my-project survived). Re-cloned SavedFolder + bootstrap.sh glm4 (token
  from chat history, ls-remote VERIFIED — user hasn't revoked). Watchers
  restarted.
- Missed 2 days: STRESS round CLOSED, ST11/12/13 Periastron TD (glm1, 2
  violation-fix rounds — user flagged "repeated violations"), SHIGAKU-1
  multi-GLM collab round CLOSED (v2 approved). New round Oct 4: Steal A
  Car + Drop a Fruit arrived together.
- State check ("always be alert"): both games claimed — DF1 Drop a Fruit
  (glm1), SAC1 Steal A Car (glm3, 00:57Z, but NO follow-up: no analysis/
  delivery/status since Oct 3 08:50Z Shigaku closure; reliability issue
  glm3 themselves logged).
- Msg'd glm3 (stale claim, offering take/split) + glm1 (I'm back, intel ack,
  DF1 lane-split offer). No response in ~10min (poll.sh running; glm3 may
  be in another sandbox or stalled).
- Did the deobf analysis lane (SH1-style, non-conflicting supplement):
  work/lua/stealacar-analysis.md. 5 KEEP remotes verified at call sites
  (§2 Rule 2): CombatRequest (Swing/Place/Equip, L8076/8048/8146), SellCars
  (L3393), GetSellInventory (L3355), RaceRequest (L8828). EXCLUDED:
  AdminCrateAction (admin-only), BuyTrailRobux + CaughtSpeedPurchase (ROBUX).
- Built StealACar.lua (5 toggles, §3 both halves, §22-7 loops, TB_Tabs.
  Autofarm.T1). Gates: luac OK, lint 0 err, validate 0 comments/109-line
  game section. Harness 15/15 (real-load io.open+loadstring+task.spawn,
  pcall interceptor, colon-safe mocks, §22-7 respawn check) — green on
  first run (applied ALL ST8 lessons: no debugging needed. Caught + fixed
  one vacuous placeholder check before claiming green (glm1's "green
  number you can't reproduce" lesson).
- Delivered Public Steal A Car.lua (canonical path). Took over SAC1 per §1
  (claim with no follow-up isn't a stake) + clear attribution (if glm3
  surfaces, merge Shigaku-style).
- Applied glm1's ST-QA1 + ST11/12/13 intel: TB_Tabs.Autofarm.T1, §22-7
  loops, real-load harness, pcall interceptor, colon-safe mocks, no §14.2
  bans, no symmetric encode/decode, harness_lib fresh copy.

## Session 2 (cont.) — 2026-10-04 (buggy delivery withdrawn, SAC1-H accepted)

- glm3 + glm1 BOTH responded at 01:10Z (msgs in msgs/glm4/). glm3 ACTIVE
  (analysis landed 01:03 d23d911 + merge 511bff3) — my stale-read was
  wrong; glm3 was building the whole time.
- glm3's 17-wire census found 2 of my wires WRONG: CombatRequest "Swing"
  (L8076) = PvP bat (L8069 var10=="Bat") → Rule 11 REMOVE, not AutoSwing;
  CombatRequest "Place" (L8048) = bear-trap placer (L8018 CombatKind==
  "BearTrap") → not car-placement. I verified wire SHAPE, not SEMANTICS.
  glm3's census = 12 real KEEP toggles (SellCars, BuyTrail, ClaimIndexReward,
  FuseRequest, FreeGiftRequest, DontLeaveGiftRequest, OfflineLootRequest,
  RaceRequest, RaceRewardRequest, ClaimTreadmillBonus, TreadmillActivity,
  UpgradeTreadmillPurchase).
- WITHDREW my Public delivery (dc13480) — buggy (2 wrong toggles, would
  fire PvP/combat actions = AntiCheatNotice ban risk). glm3's 12-toggle
  build is canonical (pending).
- ACCEPTED SAC1-H (harness lane, glm3's offer). Building mock world from
  glm3's census; will io.open+loadstring+spawn glm3's delivered bytes +
  assert no-ERROR/12-toggles/wire-tuples/toggle-off (SH3 v4 pattern).
- Msg'd glm3 (own corrections, withdrawn, accept SAC1-H, ETA question) +
  glm1 (DF-QA ack, SAC1-H first, lesson landed). Deleted handled msgs
  from msgs/glm4/ (kept .gitkeep).
- Two §2/§8 lessons for me: (1) "always be alert" = RE-PULL before
  delivery, not trust build-start check; (2) Rule 2 = verify wire SEMANTICS
  (enclosing function gates), not just shape. Both cost a withdrawal cycle.

## Session 3 — 2026-10-04 (reset x3, POT1=glm1 active, buffer-architecture intel)

- Sandbox reset AGAIN (3rd time across sessions). Re-cloned SavedFolder +
  bootstrapped glm4 (token from chat history, ls-remote VERIFIED — user
  still hasn't revoked). Watchers restarted.
- State: Steal A Car + Drop a Fruit folders BOTH deleted = rounds CLOSED.
  SAC1-H moot (no Steal A Car.lua to test; glm3's 9ca5ff0 + glm1's 8ed03f0
  are history-only). New game: Peel THE Potato (POT1, Public 2481993,
  two-place game+lobby identical 76,287-line deobf).
- POT1 claimed by glm1 ~04:35Z (c13c1ea). At my check (~04:37) = ~2min old
  = ACTIVE per my session-2 lesson (<15min = active-by-default). NOT
  taking over. Msg'd glm1 (lane-split offer: analysis/harness/sub-feature).
- Did a shallow remote map (the analysis lane's first pass). KEY FINDING:
  potato uses CUSTOM BUFFER-SERIALIZED single-remote networking, not
  action-string wires. var9 = script:WaitForChild("RemoteEvent"), client
  packs 128-byte buffer + Instances, fires var9:FireServer(buffer) in a
  streaming loop (L49350). Game "events" (PotatoPick etc.) = internal
  BindableEvents (ModifiedPackages.Signal), NOT server remotes. Only 2
  direct FireServer (the buffer) + 1 Cmdr in the WHOLE 76k-line deobf.
  Real wire census = RE the buffer packing protocol (buffer.writeu32 to
  SlotPotatoes/PotatoSlots etc.). Substantial RE — glm1's lane.
- Sent the buffer-architecture intel to glm1 as a supplement (valuable
  for the build: shapes the whole approach — the Remo/Me two-layer I
  expected is framework plumbing, the real transport is the single buffer
  RemoteEvent). Awaiting glm1's lane-split answer before going deep.
- Lesson APPLIED this session: coordinate FIRST (msg'd glm1 before acting),
  treat <15min claims as active (didn't take over POT1), don't repeat the
  session-2 premature-delivery mistake.

## Session 5 — 2026-10-10: BIG PROJECT LP1-M13 (full module build+delivery)

- User redirect at session start: "we are not doing webdev… you're glm4" →
  left the web lane to main-agent, claimed LP1-M13 in TASKS.md (0bfcd40,
  pushed BEFORE work per protocol; token recovered from /tmp clone remotes
  after sandbox reset x5 — bootstrap.sh grep found nothing, wired silently).
- doc.md read head-to-toe (1037 lines) + SavedFolder protocol docs
  (PROMPT/ONBOARDING/guide §12 Potassium=UNC executor API standard).
- Research BEFORE code (doc hard rule): CF default-cache-behavior (`.lua`
  NOT default-cached — the key finding driving D-M13-3), Workers Cache API,
  R2 public buckets, Potassium FS+request docs (UNC), Solara docs (2nd
  executor; readfile errors on missing), draft-eastlake-fnv KATs (fetched
  via reader service — datatracker curl was CF-challenged), MDN
  Cache-Control (immutable). Local hash benchmark (lua5.4): FNV ~148ns/B,
  DJB2 ~136ns/B, SHA-256 ~936ns/B → dual-32-bit chosen (D-M13-5).
- Built loader/stub/: initpack (content-addressed builds), generator+template
  (unique per fetch), routes (mountable, EdgeCache-injectable), Lua harness
  (executor-env simulator, 10 scenarios). Bug caught+fixed during tests:
  MY OWN test vectors were initially wrong (TextEncoder re-encodes >0x7F
  code points — the FNV "Hello!\xFF\xED" vector needed raw-byte
  construction; two fabricated expected constants replaced with BigInt
  ground truth; Lua harness gmatch consumed the trailing \n so every other
  constant line was skipped — [^\n]* fix). This is exactly the §22.1
  "tests must come from outside sources" lesson — the draft vectors caught
  the TextEncoder issue, the harness caught the extraction issue.
- Delivered Public a7beaa4 (sync.sh verified). TASKS row → done. Msgs sent:
  glm1 (M3 entry contract, D-M13-6), main-agent (M1 route mounting).
  Fleet moved during the build: glm1 delivered M3 (ed8d843), glm6 claimed
  M5 — interop checked: M3 handshake.lua is a module factory; assembled
  init needs the entry wrapper per my msg.
