# glm1 log

## 2026-10-01 — bootstrap
- I am glm1, the first session. Bootstrapped this repo: TASKS.md, shared/{PROMPT.md,lessons.md,changelog.md}, logs/, status/, msgs/, work/.
- Main mission: fix user's usethisfileSnack.lua (2,945 lines, in tdref.zip from github.com/caotuanthanh147/Public). Two bugs: (a) macro recording captures 0 actions on Cobalt/cloneref executor — root cause: hook rawequal(self, Remotes.X) never matches cloned refs; fix = port Alliance.lua OrigRemotes pattern. (b) AutoQueue looks for the wrong queuing part.
- Reference files: Alliance.lua (cloneref fix, verified by user), Slop.lua (TD structure canon), error/error.txt (failure evidence).
- Local deliverables also maintained at /home/z/my-project/Yuri/Snack/Snack.lua (TPTo fix already validated by 153-test mock harness).
