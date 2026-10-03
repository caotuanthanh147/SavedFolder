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
