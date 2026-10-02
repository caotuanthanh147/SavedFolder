# worklog — SUMMARY (full history archived)

Team: glm1 + glm2, Roblox automation scripting (Linoria UI, Luau, executor-side).
**Entry point: `shared/ONBOARDING.md`** (cold start, reading order, tool table).
Full session history (2026-09-25 → 2026-10-02, 1980 lines): `work/lua/worklog-archive-20261002.md`.

## Current state (2026-10-02, stress round in progress)

- **STRESS ROUND LIVE**: 10 game folders at Public root (ST1-ST10). Deliveries
  land as `<Game>/<Game>.lua` inside each folder (no zip repack).
- Delivered: ST1 Anime Breaker (glm1), ST6 Sword RNG X (glm2, +expanded),
  ST8 Ride A Pet (glm4 — Auto Hatch via Remotes.Game.Hatch:FireServer{EggKey},
  harness 9/9, Public da10db7), ST9/ST10 (glm3 — Restaurant Tycoon 3 e88e651
  + Pets Universe).
- Open: ST5 (glm2, doing), ST7 (8 Ball Duels, open), ST2/ST3/ST4 (glm1 doing).
- User signal: "too little features" (relayed glm2 5fb30cb) — fuller feature
  sets now preferred (verify 2-3 core remotes per game, not just 1).

## Milestones (details in the archive + TASKS.md)

- 2026-09-25/26: Alliance TD macro hook post-mortem → guide §20 (namecall-only
  primary hook, original-first pattern, executor logs = ground truth).
- 2026-10-01: Snack double 0-capture bug (cloneref OrigRemotes §24 + wire
  payload indexing §20.6) + AutoQueue GameJoinPad fix; harness 157/157.
- 2026-10-01: T6 toolchain round (both instances, parallel) → ONBOARDING,
  SEARCH, HARNESS_KIT, bootstrap/deobf_search/repack/validate/lint/watch/selftest.
- 2026-10-02: T7 fresh-session dogfood (glm2, 4 frictions fixed, selftest.sh);
  T8 trim+speed round (glm1: env-var paths, sync.sh, worklog trims).
- 2026-10-02: silent-push-failure incident closed (2026-10-01 SCP+snack
  pushes never landed; recovered; sync.sh now verifies every push).

## Session rules (full versions in ONBOARDING.md + the guide)

1. Reread `work/lua/GLM_SCRIPTING_RULES.md` head-to-toe first, every session.
2. Check the Public repo for new uploads before anything (guide Rule 19).
3. Claim tasks in TASKS.md before starting; msg the other glm on overlap.
4. Per protocol step: `sh shared/tools/sync.sh "<msg>"` (commit → rebase →
   push → verifies the remote moved).
5. After ANY shared-tool edit: `sh shared/tools/selftest.sh` (10 checks).
6. Never fabricate remotes/payloads — verify from the deobf (deobf_search.py).
7. Deliveries: repack.sh (MD5-verifies originals), commit `"<game>: ..."`,
   zip at the Public root. Token NEVER enters this repo (local worklog only).
