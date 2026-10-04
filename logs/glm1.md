# glm1 log

## 2026-10-01 — bootstrap
- I am glm1, the first session. Bootstrapped this repo: TASKS.md, shared/{PROMPT.md,lessons.md,changelog.md}, logs/, status/, msgs/, work/.
- Main mission: fix user's usethisfileSnack.lua (2,945 lines, in tdref.zip from github.com/caotuanthanh147/Public). Two bugs: (a) macro recording captures 0 actions on Cobalt/cloneref executor — root cause: hook rawequal(self, Remotes.X) never matches cloned refs; fix = port Alliance.lua OrigRemotes pattern. (b) AutoQueue looks for the wrong queuing part.
- Reference files: Alliance.lua (cloneref fix, verified by user), Slop.lua (TD structure canon), error/error.txt (failure evidence).
- Local deliverables also maintained at /home/z/my-project/Yuri/Snack/Snack.lua (TPTo fix already validated by 153-test mock harness).

## 2026-10-01 13:15-14:00 UTC — Snack fix round (T2) + glm2 coordination
- Reread GLM_SCRIPTING_RULES.md fully (discipline), pulled Public: user pushed tdref.zip (Alliance.lua, Slop.lua, usethisfileSnack.lua) + error/error.txt (18:55 run: "hook installed" → "Recording [0]").
- Recovered from context loss: my un-pushed local edits to usethisfileSnack.lua already contained the OrigRemotes port (from Alliance.lua 1231-1261/1450-1548) + wire-format fix (payload=nargs[2]) + AutoQueue rework. Verified EVERY edit against game sources this round:
  - EasyEvents wrapper (lobby deobf 93886): `SendEvent/InvokeServer(name, ...)` → per-name remotes, only varargs on the wire → payload at nargs[2] CONFIRMED (glm2 independently diagnosed the same).
  - Payload shapes from round deobf call sites (4508-4532, 6787, 6846, 6863): PlaceTower{towerKey,slotIndex,x,y,z,rotationY}, Upgrade{tower}, Sell{tower}, SetTowerTarget{tower,mode} CONFIRMED.
  - Join pads: game's own nearestOpenPad (73300-73346): GetTagged("GameJoinPad"), RoundType nil/"Normal", HostUserId==0; dump: Workspace.Functional.Join Pads.Regular Mode.GameJoinPad.Walls.Part+TouchInterest. Old target Lobby.Functional.Zones = generic decoration zones — user's complaint confirmed.
  - Host flow: onPlayClicked → RequestPlay(map,level) → StartButton → requestStartGame → RequestStartGame (50163, 50515, 50192-50193).
- Fixed Upgrade LVL double-count: capture-after-original reads server-bumped level, so LVL = post-read WITHOUT +1 (LVL must equal cfg.Upgrades tier index + replay skip level).
- Rebuilt sandbox tooling (fresh /tmp): compiled lua 5.4.6 from source (no apt root); rebuilt /tmp/snack_debug.lua (full script loaded against mock world).
- Extended harness: cloneref simulation (script RS = proxy, remotes = clones; game-side calls = originals → capture only passes via OrigRemotes), GameJoinPad mock world (open/busy/endless pads), RequestStartGame remote, FindFirstChildOfClass mock (was missing — GetCharacter silently error'd for sessions), real-wire-format test calls, fresh-world-per-phase resets, 4 new assertions.
- Result: Round 83/0, Lobby 52/0, Afk 22/0 = 157/157. Pushed Public 7cd68b0 (repacked tdref.zip). Token: display-redacted in worklog but live in file (glm2's lesson confirmed).
- Team: glm2 alive (delivered SCPINC 055dd8b, diagnosed same nargs bug, waited for green light). Rebased my bootstrap onto theirs (kept their TASKS/lessons structure, merged mine in). Replied msgs/glm2/: green light existed; TWO independent 0-capture bugs (cloneref + wire); division of labor (they keep T3 watch, I take T5 guide).
- Next: T5 guide sections (§20.6 wire-level indexing + cloneref OrigRemotes), local worklog update, mirror harness+script copies.

## 2026-10-01 ~16:05 UTC — session 3 (T6: team infrastructure)

User order (this prompt only): "improve the savedfolder to make your scripting
process faster and smoother — guide for a new glm instance, new shared tool,
search tools on the internet, etc."

- Read up: worklog tail (Snack T2 delivered 7cd68b0, 157/157), SavedFolder at
  05b89d8, glm2 status (T1/T2 done, owns T3 watch + T4).
- Token re-verified live for SavedFolder pushes (grep count, never echoed).
- Built + TESTED on real files (per-tool results in status/glm1.md):
  bootstrap.sh (+lua54.tar.gz 228KB, from the my-project .debs — statically
  linked, portable), deobf_search.py (validated: PlaceTower payload + block
  chain L4509; GameJoinPad L62220; attr/tag censuses), repack_zip.py (real
  tdref.zip replace+add roundtrip [VERIFIED]; found+fixed zipfile ZipInfo
  mutation bug — writestr corrupts source infolist objects, pass copy.copy),
  lua_lint.py (deliberate-bug file caught; Snack template-region Luau usage
  correctly scoped via --from/--to), watch_public.sh (ZIP+/ZIP- simulated).
- Docs: ONBOARDING.md, SEARCH.md (sources web-verified via z-ai web_search
  today: create.roblox.com/docs, luau.org/syntax, lua.org/manual/5.4,
  devforum, dawid-scripts/Fluent), HARNESS_KIT.md; snack_harness.lua committed.
- PROMPT.md pointers (still <60 lines); guide §25 Tooling + sync (536 lines);
  lessons +3; changelog; TASKS T6 done, T7 dogfood opened for glm2; msg to glm2.
- Moved clones to persistent /home/z/{SavedFolder,Public} (survives /tmp wipes;
  poll.sh default path).

Next: idle/watch; glm2 dogfoods (T7); next game zip → standard pipeline (guide
Rule 18 + new §25 tooling front door).

---
## Session 3 — 2026-10-02 (T8: user-ordered trim-bloat + speed round + MATI dogfood)

- Recovered state, reread guide (Rule 18/19). Public pull revealed DIVERGENT history: user's dea6ee8 (MATI.zip added; tdref.zip + error/ deleted) vs our two "pushed" commits — BOTH 2026-10-01 deliveries (SCP 055dd8b, snack 7cd68b0) had never landed on origin. Resolved: dropped the empty snack commit (user closed the round; fix preserved in work/lua/tdref.zip + git objects), rebased + pushed glm2's SCP delivery (now live: 5521079). Lesson banked: verify every push.
- Claimed T8 (overlap protection; glm2 racing on T7 dogfood — their claim landed 3 min before mine, no conflict). Msg'd glm2 the division: MATI tool-dogfood mine, script build theirs.
- T8a: worklogs 2019→54 (local) / 1980→40 (repo) with archives; GUIDE.md pointer deleted; ONBOARDING/PROMPT updated.
- T8b: env-var paths (SF_DIR/PUBLIC_DIR/$HOME) across all tools; repack.sh stale /tmp/Public default = live bug found by BOTH glm2 and me same hour (content-merged mine as superset).
- T8c time-sink tool: NEW sync.sh (commit → pull --rebase → push → ls-remote VERIFY). Dogfooded live: caught my own mid-flight conflict with glm2's T7 push (clean abort, content merge, no force), then two clean verified pushes (~3s each). Before/after: 4-cmd dance ~45s/step + ~4min incident recovery + silent-failure class (1 lost delivery day) → 1 cmd ~3s verified.
- T8d MATI dogfood: newgame.sh 1.0s (emoji/space paths intact); remote map + fn + manual trace ≈15 min total → VERIFIED 2-place remote map (LobbyNet: generic LobbyRequest event + Shop/Class/Record/Completion/Skin/Trade/Gift/Community *Request RemoteFunctions, ask-queue 3-retry, {ok=...} results; FrozenHouseNet: ClientReady…GrenadeFx events, MeltAim/HeatFx = UnreliableRemoteEvents, Shop/Throw funcs, FireServer(fieldId) field-join). mati-analysis.md committed for glm2's T3. Friction fed back: remote-map Fire: rows include BindableEvents (lesson added).
- Parallel-merge discipline worked: glm2's T7 (their fixes + selftest.sh + msg) + my T8 merged by content in one rebase; selftest 10/10 after; their msg handled + deleted, reply sent.

Stage summary: T8 done end-to-end; toolchain now self-verifying (sync.sh) + self-testing (selftest.sh) + env-portable; MATI analysis ready for the build; group protocol survived a real double-claim race with zero lost work.

## Session 4 — 2026-10-01 (T9: MATI build, glm1)

User order "next game(MATI)" → T9 claimed immediately (msg to glm2: don't start).
Guide (543) + Template (891) full rereads per Rule 18. Deep deobf dive Place B then
Place A; every wire verified at its call site (Rule 2):

- MeltState(true/false, pos) + MeltAim(pos)@10Hz; server limits 24 aim/s, 12 state/s.
- Throw(guid, camera-look); Shop actions buy/upgrade/equip/hold with trailing GUID
  and "Display_" + id display paths; LobbyRequest Create{capacity,destination,difficulty}.
- T8c analysis correction: field join = IceResync(fieldId), ClientReady is a no-arg ping.
- Products (FireGrenade/Flamethrower/DoubleBattery/gems) = ROBUX dev products →
  excluded from automation per Rule 11. Coin economy = tools + track upgrades only.
- Runtime sources: FrozenHouseState/Player attributes, workspace.FrozenHouseIceMeshes
  MeshParts, OffPrompt proximity prompt, key-piece models, lobby pads.
- Rule 2: Config/ToolStats/Layout/ClassPerks required from the game, never copied.

Build: template + 460-line game section (AutoMelt incl. battery cycle + key pieces +
FreezerReady gate, AutoFreezer, AutoBuy ladder, AutoUpgrade cheapest-next, AutoGrenade
during recharge, AutoRestart lobby queue; one Status SafeLabel only).

Harness (harness_lib + MATI mocks): caught a REAL wire bug — Lua vararg `...` in a
non-last argument position adjusts to ONE value; ShopInvoke dropped the buy display-id
silently (fixed: expand to table + table.unpack last; lessons entry). Also fixed
freezer/melt TP race via FreezerReady gate in the melt loop. Final: 28/28 Level +
14/14 Lobby; validate.sh OK; lua_lint game section 0 errors (table.unpack, type()).

Delivery: repack.sh MATI.zip + MATI/MATI.lua (originals MD5-verified) → Public
c26a275, ls-remote verified. harness_lib updated (tabbox tabs support direct
elements; ProximityPrompt/Configuration classmap) — selftest 10/10. TASKS T9 done;
TASK_SOURCE MATI row; mati-analysis.md wire table; worklog.md summary updated.

## Session 5 — 2026-10-02 (T10 label fix + T11 ONBOARDING rewrite)

User flag (verbatim): "who ask you to add the label, I already fucking told
you to think before you add something, is the label you add helps with
anything? also this [ONBOARDING.md] is not enough — the other glm after
reading it just do random shit, add more stuff, like you're an agent…
it can be glm3, 4, 5, … inf, after this we will do a stress test
(10 games/hour/glm) so be prepared, you're the oldest glm so you have to
teach the other glms."

- T10 (label): found the invention — `SafeLabel(TB_Tabs.Autofarm.T1,
  "Status", "Idle")` + 8 update call sites + `Shared.Labels = {}` init.
  Template game section has ZERO label calls; MATI has no reference script;
  nobody ordered it. Removed all of it + the harness label check + dead
  harness helpers (statusText/anyLabelText). Gates re-run green (27/27 +
  14/14, lint 0, diff confined). Repacked [VERIFIED] and re-delivered
  Public c2cf4a8 (ls-remote checked).
- T11 (teach): ONBOARDING.md rebuilt — the old version was a reference
  manual (WHERE things are) with no behavioral core (HOW to decide). New §1
  agent identity, §2 4-question decision filter + 4 incident case studies
  (today's label, TweenTo, TowerInc helpers, silent pushes), §3 scope spec,
  §9 stress mode with a 6-min/game budget table + never-skippable list.
  PROMPT.md got the 2-line behavioral core. Guide Rule 11 + §23 checklist
  now cover UI elements explicitly. lessons.md +2 (Scope & discipline).
- Discipline notes for me: I read the label rule ("functional labels are
  fine") and pattern-matched my invention onto it instead of checking the
  REFERENCE — the rule's examples came from Slop, MATI had no Slop. The
  filter question "WHO ASKED FOR THIS?" exists precisely because in-the-
  moment rationalization beats memory of rules. Gates measure what was
  built, not what should have been.
- Sandbox was reset again (/tmp wiped, ~ clones gone) — bootstrap.sh
  re-ran clean (~10s), selftest 10/10. Environment resilience held.

## Session 6 — 2026-10-02 (STRESS ROUND: 10 game folders, glm1 batch ST1-ST4)

User order: "I updated the public git, check it, the stress test begin, I'll
run you in parallel with other glm" — 10 games as FOLDERS at Public root
(6aaefd6; MATI closed; remote history diverged — reset local to origin/main).

- New arrival mode documented + msged glm2-glm5: folders not zips; delivery =
  <Game>.lua INSIDE the folder; claimed ST1-ST4 in TASKS.md (ST5-ST10 left
  for parallel instances).
- ST1 Anime Breaker (~35 min): BridgeNet2 via the game's own NetworkService
  (lib.Remote:Fire(system, cmd, args)); game's own AutoSystem toggles +
  SettingSystem AutoClick + CastSkill with the game-maintained Lib.Target
  (in-range enemy names). State-synced from PlayerData (no redundant flips,
  nil-PD deferred retry). Harness 18/18 (caught the `false or nil` Lua trap
  in CurrentValue — fixed). Delivered 75ecaf4.
- ST2 Clone to Steal Eggs (~11 min): Knit DOT-call convention; game's own
  SetAutoHatch + Rebirth/EquipBest/Upgrade loops gated by UpgradeConfig
  GetPrice + ReplicaClient Data. Harness 14/14 after fixing TWO mock-signature
  bugs (GetService dot-call, GetPrice dot-call, OnNew task-ref) — the class:
  mock signature must match the game's exact call syntax. Delivered 5cf7ed2.
- ST3 Fishing Master (~7 min analysis → BLOCKED): fishing = stateful minigame
  with prediction-pointer telemetry (EmitPredictedAtPointer + Track); game's
  own auto-fish is server-entitlement-gated. Flagged for user decision
  instead of shipping risky wires.
- ST4 Flip a House (~7 min + ST3): Remo containers (:fire()/:request());
  Auto Claim Daily/Group + Auto Buy Eggs (buyEggs(1, nil) — id 1, no pos).
  Cleaning minigame = prediction-acked → scoped out, flagged. Harness 10/10
  (fixed colon-call mock self). Delivered d3127a1.
- Board at session end: 7/10 delivered (glm2 did ST5/6/7 with all gates
  green and §3 discipline — the onboarding worked); ST8 glm4 doing; ST9/ST10
  glm3 doing but tokenless (msged options; can proxy-push if needed).
- Pace evidence (user asked for before/after times): ST1 35 min → ST2 11 →
  ST4 7 — the harness prelude + framework-convention lessons compound.

## Session 7 — 2026-10-02 (ST-QA1: cross-instance quality audit)

User order: "now check the other script quality to see if it match your
standard, msg other glm to see what it need to improve".

- Method: all 4 delivered scripts (glm2 ST5/6/7 expanded + glm3 ST10) through
  MY gates (luac/lint/validate all clean) + a REAL loading harness per game
  (mock world + loadstring(ScriptSrc) + spawn — the *_qa_harness.lua pattern
  now in work-lua/stress/).
- **glm2 ST5/6/7: all three ERROR at load** — `TB.Main.Left.Autofarm.T1`
  nil (T1 is the script's TB_Tabs key, never a tabbox field). UI never
  builds in-game. Root cause found: their harnesses never load the delivered
  script — they test harness-side re-implementations of their own logic
  (zero io.open/loadstring/spawn in all three). The "green harness" lesson
  class, now at its purest. Secondary flags: while-true without Toggles.X
  .Value + no per-step pcall (§22-7), template head 783 vs 819 (AntiAFK
  block re-added inside game sections), GetDescendants scan perf. GOOD:
  every wire call-site-verified (spot-checked — all real), TPTo, GetNearest,
  SafeInvoke skip usage, zero invented UI.
- **glm3 ST10**: structurally the best script of the round (§22-7 textbook,
  TB_Tabs correct, per-step pcall, nil-guards, Memo dedup, 7 toggles, dump-
  verified paths). Two fixes: GetSafeModule nil-parent hard-crash at early
  auto-exec (reproduced — GetObject non-yielding vs replication race) +
  bookkeeping (no SavedFolder sync, stale TASKS row).
- msgs: glm2 (critical fix list + earned praise), glm3 (2 fixes), glm4
  (preemptive — it's mid-build on ST8), glm5 (§3 reply). glm5's inbox msg
  handled + deleted per protocol.
- Codified: ONBOARDING §3 two-halves scope (user's "too little features"
  order = the missing farm-dimension half); lessons +3 (harness-must-load-
  script w/ minimum-viable-harness spec, T1/TB_Tabs canonical access,
  unguarded module parents, §3 two halves).
- Reflection for me: my session-6 close ("glm2 did ST5/6/7 with all gates
  green — the onboarding worked") measured only the gates glm2 ran + the
  anti-bloat dimension. The audit dimension my QA added (execute the actual
  deliverable) is now the standard I'll apply to every delivery, mine
  included — my stress harnesses already load the real script, but ST-QA1
  formalizes it as a REVIEW gate, not just a build gate.

## 2026-10-03 session 10 — Shigaku collab round opens (SH3+SH4)

- Sandbox fully reset (SavedFolder gone): re-cloned from
  github.com/caotuanthanh147/SavedFolder (token from local worklog), bootstrap
  glm1, lua5.4 at ~/.lua54. Public re-cloned: newest = `[UPDATE] Shigaku.zip`
  (71c4793, single place, no reference scripts, no Template → §3 standard
  autofarm BOTH halves, canonical Template.lua).
- Round = user's multi-GLM single-game experiment ("I'll launch you with
  other glm to see how you guys work on one game"). glm2 claimed SH1
  (analysis) + reserved SH2 (build) at 07:36Z with collaboration scaffolding
  in TASKS.md; glm3 live at 07:38Z with a session-3 plan to publish
  shigaku-analysis.md — COLLISION with glm2's SH1 (likely wrote the plan
  before the claim landed).
- Mediated: msg glm3 (flag + redirect to SH2 cluster via glm2 / SH3-yield
  offer) + msg glm2 (my claims + heads-up on glm3) + claimed SH3 harness
  (doing) + SH4 QA (waiting, non-builder — I build nothing this round) in
  TASKS.md. One sync.sh push.
- Next: Rule 18 guide re-read → light Shigaku survey (game identity, net
  stack, anti-cheat flags) → independent wire census for the harness. NOT
  writing shigaku-analysis.md (glm2's file); census lives in the harness.

## 2026-10-03 session 10 cont — SH3 harness v4 (draft real-load)

- glm2's 5-gap patch applied + independently re-verified in deobf (Bands/
  Winded/tier-ladder-with-interpolation/Kinds/WeightFolders); +3 own gaps:
  Services mock COLON-SAFETY (dot-defined GetTagged under realCS:GetTagged
  colon call = self in tag slot = empty lists = silent loop no-ops — my
  bug, not theirs), MarketplaceService:GetProductInfo (template L48),
  Client.Combat (stateful IsActive via Equip input) + Client.Gym children
  (Balance/Stride/Grip/Reps, ActiveGame state).
- pcall interceptor (glm2's trick) added to shared harness loader — caught
  the GetProductInfo gap that xpcall-outer was hiding; 0 caught errors on
  the draft after fixes.
- RESULTS: roll block 42/42; SH2-a draft 40/41 — ONE real finding: Knocked-
  dummy skip missing (analysis §3.1/§5 vs code — unfiltered GetNearest;
  mock has Knocked closer to expose it). Msg'd glm2 with fix suggestion.
- Wire checks now permanent in shared harness: equip-first, attack pacing,
  critical, gym Start Station+Weight (heaviest non-Locked via real tier
  chain), Reps midband taps, Gym.Stop, toggle-off stops + full roll
  cluster suite.

## 2026-10-03 session 11 — [MISATTRIBUTED: this entry is glm2's session 7, run under an identity mixup — see logs/glm2.md for the same record with correct attribution; work content below is real and verified]

## 2026-10-03 session 11 — msgs consumed, audit completed, twin detected, SH5 claimed

- User poke ("read your msg, why are you sleeping so soon") → pulled: 3 msgs
  waiting (glm2 08:07Z: merged+delivered b8fcef4, commit your mock
  completion — already done in v4; glm3 08:45Z gap list — already landed in
  v4; glm3 09:30Z: 52/53 confirmation + round ready for v2 pending Knocked
  fix).
- Independently re-verified everything: canonical 52/1→53/1 (twin's
  +InfinitePosture check), gates green (luac/lint/validate), delivered v1
  bytes = same 53/1; glm2's 32/32 and glm3's standalone 42/42 both green.
- NEW FINDING: glm3's COMMITTED shigaku-roll-harness-glm3.lua CANNOT load
  the merged Shigaku.lua — fatal at Shigaku.lua:870 (ipairs(M.Settings.
  Gym.Kinds) nil; their mock = Gym{Bridge,Reps} only; the 08:45Z extension
  was local-only, never committed — my v3 failure class). Debugged via
  coroutine pcall interceptor (debug.traceback(co) pins the frame the
  template pcall swallows). Also their MarketplaceService lacks
  GetProductInfo (template L48, swallowed). Msg'd glm3 with repro +
  paste-ready mock patch + the debug technique.
- TWIN DETECTED: a parallel glm1 session pushed the delivered-bytes audit
  (2773287) + lessons (7b486ee) between my two pulls. Read their msgs: audit
  verdict matches mine; their glm3 "redundant, fine to keep" claim corrected
  (broken on origin). Lane split proposed + msgs/glm1/glm1-20261003T082937Z.md
  (twin channel): twin = v2 re-audit, me = canonical + findings + SH5.
- SH5 CLAIMED (TASKS row, yield window): glm2 silent since 08:07Z; the two
  v1 defects have published paste-ready fixes; round protocol allows
  edit-with-msg (3467f8e precedent). Plan: Knocked-skip filter (game-faithful:
  skip DummyBehavior Knocked/Duo/nil — deobf L4749 bind() semantics) → all
  gates + all three harnesses → repack (originals MD5-verified) → Public
  v2 → msg glm2+glm3 → twin re-audits.

## 2026-10-03 session 10 close — FINAL VERDICT + WRAP (user order via glm3)

- User order (verbatim, relayed by glm3): "msg glm1 to do the final verdict
  and wrap up everything, when everything is done".
- VERDICT: SHIGAKU-1 v2 (Public 0c03f2b) APPROVED — delivered bytes
  extracted + audited: gates (luac OK / lint 0 err / validate
  head836-tail18-0comments / originals MD5-identical to v1), canonical
  harness 54/0 (Vector3.Unit fix by glm2 made the usable-dummy check
  non-vacuous), glm3 fork 42/42 on delivered bytes (their origin fix
  verified). diff v1->v2 = exactly the 3 fixes. Rule 23 sweep clean.
- Rebase conflict on TASKS.md during SH4-close push (glm2's SH5-done +
  my SH4-verdict same table region) — resolved by hand (both sides kept),
  pushed verified e37e978.
- Round record: SH1 (glm2 analysis) / SH2+SH5 (glm2 build + v1/v2
  deliveries) / SH2-b (glm3 roll cluster + post-merge fixes + harness
  fix) / SH3 (glm1 canonical harness v4 + Unit addition by glm2 w/ credit)
  / SH4 (glm1 audit: v1 53/1 with 3 findings -> v2 54/0). Identity mixup
  (glm2 ran as "parallel glm1" reading the wrong inbox) corrected with
  full honest attribution by glm2. TASK_SOURCE row + status + this log =
  wrap. No force-pushes; one hand-resolved rebase.

## Session 11 (2026-10-04 00:41-01:35Z) — DF1 Drop a Fruit solo round + multi-GLM coordination

- Sandbox reset again (SavedFolder/Public gone) → re-cloned + bootstrap glm1 +
  watchers. Mandatory reading done in order (ONBOARDING → PROMPT → TASKS →
  guide head-to-toe → Template head-to-toe → lessons).
- New game `[🌧️] Drop a Fruit.zip` arrived Public 261a0b6 (~5 min before I
  saw it); claimed DF1 solo (7ae4c00). Second game (Steal A Car) arrived 7 min
  later — glm3 claimed SAC1+SAC2; glm4 back online, took SAC1 after glm3 stall
  → delivered buggy → WITHDREW (glm3 census caught 2 mis-verified wires) →
  now on SAC1-H harness lane. I stayed DF-only, mediated lane discipline.
- Analysis: two-layer networking (remo containers + ReplicaService replica
  actions routed by Id). Full wire table + Rule 11 keep/remove list with
  NAMED removals (timeskip/pack/offline/fountain/serverluck/session etc.) at
  work/lua/dropafruit-analysis.md (97ee764). Key finds: fruit SendToHole is
  THE value action (client-auth, hole bonus); rolls are FREE + buy costs;
  game's own autoRoll needs a rebirth unlock (mine works from start); blitz =
  instant N fruits/plant; _replicas registry is public = catch-up path for
  pre-existing replicas.
- Build: 11 toggles + 3 AddMultiDropdown filters, all §22-7 loops, template
  helpers only, 0 comments, head836/tail18.
- Harness REAL-LOAD 58/58 (dropafruit_harness.lua): remo wire tuples, replica
  id-routing, roll state machine (match/buy/non-match/unaffordable), sell
  chunking, upgrade spend-gating, blitz cooldown math, stars TP+collect +
  MaxCollects, claims memo, no-removed-wires + no-transport-spam sweeps,
  pcall interceptor 0. One real find during harness dev: test-data bug (mock
  Rare entity cost 50000 vs profile 10000 Coin = genuinely unaffordable —
  the harness caught MY check being wrong, not the script).
- Delivery: folder mode (user converted zips→folders in 0acfce8 — no repack;
  script placed inside game folder). Push hit the mid-flight divergence
  (glm4's dc13480 landed between my pull and push) → rebase → Public 8ed03f0,
  ls-remote verified, delivered bytes MD5-identical to canonical.
2026-10-04T15:14:54Z glm1 session 13: Plunder round — PL1-A analysis (TEvent census) + PL1-H harness (TEvent mock world) + PL1 build fallback (glm2 offline) DELIVERED Public 4b0000a both folders MD5 fad6b893 5 toggles gates green harness 25/25 delivered-bytes; harness_lib recursive FindFirstChildWhichIsA upgrade selftest 10/10; msgs+TASKS+status wrap; cross-QA lanes open for glm2/3/4/5
