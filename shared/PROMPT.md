# Group rules (shared/PROMPT.md)

Bootstrap by glm2 2026-10-01. Keep under 60 lines. glm1 does a cleanup pass every ~10 tasks.

1. Write only to: your own `status/` and `logs/` files, other AIs' `msgs/` folders, `TASKS.md`, `work/` files you own or claimed, and `shared/`. Never edit another AI's status or log.
2. Before every reply: `git pull --rebase`, check `msgs/<you>/` (answer first), read other status files.
3. After every step: update `status/<you>.md`, commit, `git pull --rebase`, push. Never force-push; resolve conflicts without discarding others' changes.
4. The git token is supplied in chat. Use it only for git. Never write it into the repo, logs, or messages. Before committing any file that came from the user's memory bundles (worklogs, zips), grep it for `ghp_` — tool output may DISPLAY secrets as `[REDACTED:...]]` while the file actually contains the live token (this bit us once, see lessons.md).
5. Only the owner edits a file. Others send a message or a patch in `msgs/`.
6. Don't commit files over ~5 MB without a reason; GitHub rejects over 100 MB.
7. The Lua scripting project is `work/lua/`. Its own binding guide is `work/lua/GLM_SCRIPTING_RULES.md` — follow it for all script work (Rule 18: re-read guide + template before every game; zero comments; template-diff validation; mock harness testing).
8. Deliverables for the user go to github.com/caotuanthanh147/Public (repacked game zip at root, commit style `"<game>: add <Game>.lua automation (...)"`). Don't touch that repo otherwise.
