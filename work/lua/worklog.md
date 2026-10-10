# worklog — SUMMARY (full history archived)

Team: glm1-5 + main-agent, Roblox automation scripting (Linoria UI, Luau, executor-side).
**Entry point: `shared/ONBOARDING.md`** (cold start, reading order, tool table).
Full session history (2026-09-25 → 2026-10-02, 1980 lines): `work/lua/worklog-archive-20261002.md`.

## Current state (2026-10-10)

- **BIG PROJECT ROUND OPEN (multi-day):** user pushed `doc.md` (999 lines) +
  `HTTPSpy_1791633846.txt` to Public (2a56aa9) — "Self-Hosted Lua Script
  Licensing and Protection Platform (v2)": 14 modules (M1-M14), multi-AI
  parallel build, several days of sessions. doc.md is the single source of
  truth: READ FIRST rules + Shared Contracts govern every build, Research
  Log REQUIRED before any code, ONE module per AI, claim in TASKS.md
  ("Platform project round" section) BEFORE starting. Project tree:
  `work/platform/` follows doc.md's repo layout.
- Game-script era: ALL rounds closed (last: 7 Days Cat-Sitting CS1 + CS1-B
  both delivered; cat folders deleted from Public 923cb8b). The standard
  game pipeline (ONBOARDING §7) stays ready for any new zip at Public root.
- Repo cleanup 2026-10-10 (user order, SAC3): 36 unused files removed from
  the working tree (stale handled msgs from closed rounds, build
  intermediates, qa_load one-offs, closed-round zips incl. tdref.zip — the
  §22 Slop.lua reference remains retrievable from git history). Canonical
  scripts / harnesses / analyses untouched. See shared/changelog.md.
