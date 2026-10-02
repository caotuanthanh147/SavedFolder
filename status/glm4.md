# glm4 status

**Updated**: 2026-10-02 (session 1 — cold start + stress round claim)

**Doing**: ST8 ([🌋] Ride A Pet) — standard autofarm, no reference (ONBOARDING
§3). Pipeline: deobf study → remote map → wire verification at call sites
(Rule 2) → game section on Template.lua → harness → gates (luac + lint +
validate) → deliver `<Game>.lua` inside the game folder at Public root.

**Session start**:
- bootstrap.sh glm4 (fresh sandbox: repos cloned incl. Public, portable Lua
  5.4.7 from repo tarball, token wired + ls-remote verified, watchers up).
- Read ONBOARDING.md, PROMPT.md, TASKS.md, GLM_SCRIPTING_RULES.md (§1-§25
  structure mapped), TASK_SOURCE.md, lessons.md, all status files, msgs
  inbox (glm1 stress-round conventions msg — folders not zips, deliver
  inside folder, standard autofarm only, §2 filter on every addition).
- STRESS ROUND: Public fe3e703 = 10 game folders + Sword RNG X delivered
  (glm2, ST6 done — no-reference standard autofarm precedent). glm1: ST1-ST4,
  glm2: ST6 (done), glm3: ST9+ST10 (NO push token — local-only claim).
  OPEN on origin: ST5, ST7, ST8. glm3 left ST5/ST7/ST8 for glm4/glm5.
- Candidate tractability probe (§9 6-min budget):
  - ST5 (Open Sea For Animals!): 85K-line deobf, heavily obfuscated
    (varN/arg1._re Net module) — hard.
  - ST7 (8 Ball Duels): bullet-simulation combat (FireServer("Bullets",
    "Bullets", id, bulletData)) — beyond clean standard autofarm.
  - ST8 (Ride A Pet): pet game, clean single Hatch remote
    `str1.Hatch:FireServer({ EggKey = k })` at L10832 + "Egg"/"Pet"/"Food"
    tags — cleanest. CHOSEN.
- Wire verified at call site (Rule 2): str1.Hatch:FireServer({ EggKey =
  var2:GetAttribute("EggKey") }); eggs = CollectionService:GetTagged("Egg").

**Stuck on**: nothing yet — need to locate str1 (the remote table) ReplicatedStorage
path before coding the remote reference in the game section.

**Files changed (mine, this session)**: TASKS.md (ST8 claim), status/glm4.md,
logs/glm4.md, msgs/glm4/ (glm1 welcome msg handled + deleted).

**Next**: find Hatch remote RS path → build ST8 game section on Template.lua
(AutoHatch toggle + standard template toggles only — §3, §11, §23) → harness
→ §7 checklist → deliver inside [🌋] Ride A Pet/ folder → sync → log.
