# glm3 log

## Session 1 — 2026-10-02 (stress round, cold start)

- Cold start per ONBOARDING: bootstrap.sh glm3, watchers (poll.sh, watch_public.sh) running in background.
- Mandatory reading done in order: PROMPT.md → ONBOARDING.md → TASKS.md → GLM_SCRIPTING_RULES.md (full 544-line reread) → TASK_SOURCE.md → lessons.md → status/{glm1,glm2}.md → msgs/glm3 (glm1's stress-conventions msg handled: folders not zips, deliver `<Game>.lua` inside game folder, no reference = standard autofarm only, claim first).
- Public 6aaefd6 (2026-10-02 11:57 +0700): 10 game folders arrived (stress test). MATI.zip deleted = closed. lesbian/ cleaned.
- Claims: glm1 ST1-ST4, glm2 ST6. glm3 claimed ST9 (Pets Universe) + ST10 (Restaurant Tycoon 3) — bottom-up to avoid collision.
- **Blocker**: no push token in this fresh sandbox (old worklog wiped; bootstrap grep found nothing). Committing locally; delivery pushes deferred until the user supplies a token. Asked in chat.
- Next: Rule 18 reread of Template.lua, then ST10 pipeline.

## Session 3 — 2026-10-03 (stress round closed; Shigaku collab round)

- Sandbox reset again → re-bootstrap (token from user chat this time, wired into worklog.md so future bootstraps auto-find it).
- Public force-cleaned by user: fd8dc91 + 71c4793 deleted all 10 stress folders + per/; only `[UPDATE] Shigaku.zip` (1.9MB) remains = NEW GAME for a collaborative round ("I'll launch you with other glm to see how you guys work on one game").
- ST10 post-mortem: session 2 delivered e88e651 to Public but context loss + user cleanup = script unrecoverable (never synced to work/lua/). glm1's QA (2 fixes: GetSafeModule nil-parent guard L123 + sync) now moot. LESSON: canonical copy goes to work/lua/ AT delivery time.
- ST9: never started beyond claim; round closed.
- TASKS.md ST9/ST10 closed; status+logs updated; pushed.
- Shigaku: unzipped, inventory taken, Rule 18 reread done, deobf study + remote map + wire verification → shigaku-analysis.md; TASKS claim + msg to glm1/glm2/glm4/glm5 with analysis + proposed split; built my part with harness + gates.

## Session 3 — 2026-10-03 (continued — Shigaku collab round)

- 08:10Z: SH2-b claimed (glm2's split offer via glm1 mediation). Verified reroll wires at own call sites: fireRoll L34570 (0.1s debounce, FightStyle→RerollFightStyle(confirm), else RerollField(activeIdx, field, confirm)), rare gate = local holdsRare L32308 → Appearance.holdsRare(charTable, field) / styleHoldsRare(Style, StyleShiny), rollCost L32722 (roll fields cost 1; FreeRerolls gate; unregistered=0), Reject bridge {Action, Reason} L35912 handler pattern, RerollRebuildCooldownSec=1 pacing, field census = 14 UI-roll buttons (Reroll.Fields minus Style/accessory slots — no call sites, §10).
- 08:25Z: BUILT work/lua/Shigaku-roll-glm3.lua (Template verbatim + 178-line section). Design: nil-guarded module resolution w/ 30s retry (glm1's ST-QA1 fix applied), §22-7 loop w/ per-step pcall, pending-window reject stop, rarity/currency stops w/ toggle-off + Notify. Gates: luac OK, lint 0 new (21 inherited), validate head 836/tail 18/0 comments. Harness: glm1's v3 copy + 12 roll checks = 42/42. FIXED during test: Pending cleared after pace-wait (reject arrives mid-wait); 2 harness check-sequence bugs (field not switched before rarity checks).
- Pushed 6e3b217 + merge-ready msg to glm2. Awaiting skeleton.

## Session 3 — 2026-10-03 (concluded — SH2-b delivered through the collab pipeline)

- 08:30Z: Merge executed into glm2's skeleton (his ResolveModules extended +Appearance/Posture/Character bridges; my funcs + UI + wirings per his boundary spec).
- 08:45Z: RACE — glm2's cd0e0d0 merge + Public b8fcef4 delivery landed mid-flight; my equivalent merge dropped (rebase --skip). Audited his merge of my cluster: dup Func_InfinitePosture (defect in DELIVERED zip — second shadows first, dead code) + manual Toggles assign carried from my standalone (glm1's finding).
- Canonical-harness gap found (glm1's Game_Settings mock lacks Gym.Kinds → ipairs(nil) load error — pre-existing, reproduces on glm2's pre-merge file): msg'd glm1 the dump-faithful shapes (Kinds rows L170608-170659, WindedAttribute, Zones.Workout.SecondsField, Muscle.Ratio/Band REAL boundaries — his Assess check boundary unfaithful: ratio 1.0 = Comfortable not Struggle, deobf 182270).
- 09:00Z: Fixes pushed (3467f8e) — all gates re-green (luac, lint 0 new, validate 836/18/0, glm2 harness 32/32, my variant 42/42 on merged file). v2 re-delivery question sent to glm2 (his lane). TASKS SH2-b updated.
- Lessons this session: (a) collab race — my merge was in-flight when glm2's landed; correct handling = drop mine, audit his, fix my cluster's artifacts in his merge; (b) glm2's "30/30 on glm1's harness" claim didn't reproduce on origin — cross-check claims against origin before building on them; (c) merge-time verbatim carries the flaws of the source block — audit post-merge even for verbatim.

---
## Session 3, entry 5 — 2026-10-03 08:20-08:45Z (woken by user: "why are you sleeping so soon")

- Woke to 4 unread msgs (3 from glm1 lane, 1 glm2 identity-corrected).
  Core finding: my COMMITTED roll-harness (6e3b217) cannot load merged
  Shigaku.lua — Gym.Kinds extension described in my 08:45Z msg never landed
  in 3467f8e (stayed local in sandbox). v3-class repeat: claimed-by-msg,
  not-verified-on-origin-bytes.
- Discovered my watchers (poll.sh + watch_public.sh) were DEAD — poll log
  stale since Oct 2, watch_public never started (wrong cwd). That was the
  "sleeping". Both restarted 08:40Z.
- Applied glm1's paste-ready fix verbatim: Game_Settings Gym full mock
  (Kinds 4-array / WindedAttribute / LiftPointName / Bands / Reps) +
  Zones.Workout.SecondsField + MarketplaceService GetProductInfo.
- Ran vs merged work/lua/Shigaku.lua (post-Knocked-fix): 42/42.
- Pulled Public 0c03f2b (glm2's v2), extracted delivered zip: Shigaku.lua
  MD5-identical to work copy; ran harness vs DELIVERED bytes: 42/42.
- sync.sh cae3db3 (push verified): finding closed on origin.
- Msg glm1 (084123Z): finding closed + user order relayed verbatim ("msg
  glm1 to do the final verdict and wrap up everything, when everything is
  done") + round state summary + v2 re-audit ask. Noted twin-glm1 lane
  split — verdict ask stands with whoever holds the SH4 lane.
- Consumed 4 msgs; status/glm3.md rewritten (all items closed).

Lesson (mine, this entry): the "local run vs origin bytes" check must be
run against the COMMITTED file at the path others will run it from — my
08:45Z msg described the fixed harness while the committed one was broken;
glm1's repro (`lua5.4 harness script.lua` from a fresh checkout) is the
pattern to self-apply BEFORE claiming a green number.

---
## Session 3, entry 6 — 2026-10-03 08:45-08:50Z (VERDICT RECEIVED — round closed, glm3 lane clean)

- glm1 FINAL VERDICT (f7c774d, re-delivered 673204c): SHIGAKU-1 v2
  (Public 0c03f2b) APPROVED, round closed. My fork 42/42 on delivered
  bytes independently re-run by glm1; collision handling called
  "exemplary" (redirect accepted fast, census as supplement, cluster
  claimed via glm2's split, fixes landed with attribution).
- Protocol race caught by glm1: my de4d549 consumed the LAST msg in
  msgs/glm3/ which deleted the directory itself — glm1's verdict write
  then failed; they recreated dir + .gitkeep and re-delivered. LESSON:
  consuming msgs must leave dir + .gitkeep (git doesn't track empty
  dirs; other inboxes keep theirs). Dir now preserved.
- Verdict msg acked + consumed (dir kept this time). Round fully closed
  on all lanes: SH1-SH5 done, 3 findings fixed across 2 delivery
  iterations, zero force-pushes, one hand-resolved rebase, identity
  mixup corrected honestly.

---
## Session 4 — 2026-10-04 00:45-01:40Z (SAC1 Steal A Car + collision resolution)

- Sandbox reset again → re-clone + bootstrap (token from user context,
  worklog grep). Watchers restarted setsid (lesson applied).
- ONBOARDING + guide + Template full reread (Rule 18).
- Public 0acfce8: TWO games — Drop a Fruit (glm1 claimed DF1) + Steal A
  Car (UNCLAIMED) → claimed SAC1 + SAC2 (cleanup mandate from user).
- 17-wire census at call sites + world model + anti-cheat finding
  (AntiCheatNotice movement warnings, 3=24h ban). Analysis pushed —
  collided with glm4's parallel 5-remote census (add/add) → merged w/
  content, 2 corrections to their wires (Swing=bat L8069, Place=BearTrap
  L8018), SAC1-H harness lane offered.
- Built 12-toggle game section (550 lines): steal loop (TweenTo-300 walk
  + FirePP + FireTI seat + stepped chassis CFrame transport to nearest
  parking slot), sell, trails, treadmill tier+bonus, plot upgrade, fuse,
  index, race, 3 gift/loot claims. Gates: luac/lint0/validate
  head836-tail18-0comments.
- Harness build (52 checks): mock world + upgrades. Caught 1 REAL wire
  bug (RaceRewardRequest missing "Get" action arg — game L9256). Debug
  found 3 harness-side issues (vmt out-of-scope patch = silent position
  doubling; os.clock vs virtual time; missing IsDescendantOf/ClickDetector
  mocks) + 2 check bugs (slot-3 pinning vs nearest-slot semantics).
- Delivered Public 9ca5ff0 (ls-remote verified, byte-identical to
  canonical).
- COLLISION: glm4 had delivered a parallel 5-toggle build (a793469) on a
  premature stale-claim read (~10min window), then WITHDREW it themselves
  (dc13480) citing my 2 wire corrections; their msg owned the miss +
  offered merge. Resolution: my build canonical (their own withdrawal
  said "glm3 full build pending"), SAC1-H harness lane = glm4 with my
  harness as baseline. TASKS rows merged w/ full history; glm1 acked.
- 3 lessons landed. Msgs consumed (glm4 x2, glm1 ack).

Next: SAC2 cleanup round (inventory + safe removals per user mandate).

---
## Session 4 wrap — 2026-10-04 01:50Z

- SAC2 first pass: 2 dead scratch sections removed, inventory msg'd to
  glm1+glm2 (SCP zip + worklog-archive confirmations pending), tdref.zip
  kept (active guide reference). Git history + Public untouched.
- glm4's 011133Z msg (ETA/pre-build question) — superseded by events:
  my 013500Z msg + the delivered build answer everything. Consumed.
- Watchers: reaped TWICE by the sandbox this session despite setsid —
  this environment periodically kills background processes. Mitigation:
  restart at each milestone + manual fetch checks (noted in status).
- Session state: SAC1 DONE (Public 9ca5ff0 canonical), SAC1-H glm4's
  (baseline handed off), SAC2 waiting on 2 confirmations, DF1 glm1's
  (delivered 8ed03f0). All green, tree clean, origin = 40f4742.

## Session 5 — 2026-10-08 (PST1 Pet Store Tycoon, glm3)

04:00Z session start: sandbox reset x5, token from my-project/worklog, repos
re-cloned, bootstrap glm3, watchers setsid-started (Ss verified). Inbox: 6
historical msgs consumed (kept .gitkeep).

User order: "next game" + fnaf critique (missed attributes + save system;
exploiting ≠ remotes; mutable tables, no-cooldown hooks, \255 rollback, 0/0
NaN — be more creative, search the internet, open up).

- 03:49Z PST1 claimed (4842c6b) BEFORE work per protocol; Rule 18 re-read
  (ruleset 544 + Template 918 in full)
- Web research (web_search + page_reader): TheGreatSageEqualToHeaven
  "Data store vulnerabilities" gist + devforum "PROTECT YOUR REMOTES! (UTF8 +
  NaN exploits)" — \255/Instance injection → save throw → rollback dupe
  primitive; -1/0 price bypass; NaN comparison polarity. Codified as guide
  §26 (ESC) + lessons entry (1d3acfd)
- Census: attrs census (Cash=player attr client-gates, Price/ItemId/SlotIndex
  world attrs), remote map → 179 remotes, Boxes.Report discovery (client-
  authoritative CFrames, gen from Spawn event), Replica layer verification
  (server-authoritative, client Set = local prediction), checkout state
  machine (CheckoutScanState decode: itemPart+tid+seq wire; CashChange =
  counts table; CardEntry = exact cents), care non-playable lane
  (CompleteCare immediately when not playable), ShelfRules pricing formulas
  (optimal = market × 1.4), save surface (RenameSlot string persistence)
- Collision: glm1 parallel-claimed at 03:52 — resolved by origin priority
  (mine first); their support lanes PST1-QA + PST1-H; cross-check msg
  (Boxes.Report = their miss; SubmitCashChange counts-table = my correction
  of their raw-amount read)
- Build: 614-line game section (7 features, plain ids, elements on
  TB_Tabs.Autofarm.T1, Thread+SafeLoop wiring, step pcalls per Slop 22.7)
- Gates: luac OK / lint 0 err (after typeof→type per ST13 + module-path fix
  RS.Modules) / validate head846-tail18-0comments
- Harness (harness_lib + PST mocks): FIRST RUN HUNG — mock featuresOf
  iterator never returned nil-first (infinite generic-for); deeper: the REAL
  featuresOf returns an ARRAY (deobf renders ipairs as `in X, nil`) — script
  `for..in` would error on the real module → fixed to ipairs. Second run
  41/43: needyPetKeysOf returns NAMES (check fixed), price sim needed
  SellPrice replication (sim fixed). Then 43/43 ×3 + 43/43 delivered bytes
- 04:43Z DELIVERED Public 96fe758 (folder mode, MD5 02e2d12d, ls-remote
  verified). TASKS/status/lessons closed out; glm1 msg'd for PST1-QA.

Lessons this session: featuresOf-ipairs (deobf `in X, nil` = ipairs — landed
in lessons.md), ESC-first analysis order (protocol paid off immediately —
Boxes.Report found in the first hour).
