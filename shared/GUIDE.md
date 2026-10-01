# GUIDE.md — new GLM instance quickstart (read this first, ~5 min)

You are a GLM session joining the SavedFolder collaboration. Goal: be
productive in 10 minutes without reading 500 KB of history cold.

## 0. Environment (2 min)

```sh
sh shared/tools/bootstrap.sh <yourname>   # clones/pulls both repos, checks lua5.4, prints state
```

Sandbox resets wipe `/home/z` clones and `/tmp` — **GitHub is the only
persistent state**. If something is missing, re-run bootstrap. The git token
comes from the user in chat; it is never written into any repo file.
Run `shared/tools/poll.sh <yourname>` in the background to watch for messages
(every 30 s: pull + report new `msgs/<you>/*.md` to `/tmp/<you>.msgs.log`).

## 1. Reading order (the 10-minute ramp)

1. `shared/PROMPT.md` — group rules (short, binding).
2. `TASKS.md` — who owns what. **Claim before you work, mark done when finished.**
3. `status/*.md` (everyone's current state) + unread `msgs/<you>/`.
4. `shared/lessons.md` — paid-for mistakes (each one cost a session real time).
5. This guide's §2-§3.
6. Only if your task is script work: `work/lua/GLM_SCRIPTING_RULES.md`
   (the 24-section guide — Rule 18: re-read it + the template before EVERY game),
   `work/lua/TASK_SOURCE.md` (which games are done/closed/open).

Skip `work/lua/worklog.md` (474 KB) unless you need deep history — the lessons
file is its distillate.

## 2. How this project works (the Lua pipeline)

We build Roblox automation scripts (Linoria UI, Luau, zero comments,
template-verbatim) from game zips the user uploads to their other repo
`github.com/caotuanthanh147/Public`. One "game task" is:

```
new zip in Public repo
  → sh shared/tools/newgame.sh <zip>          # extract, verify structure, scaffold
  → study deobf + dump (verify EVERY remote signature at client call sites)
  → build work/lua/<Game>.lua on work/lua/Template.lua (canonical 891-line)
  → mock harness (start from shared/tools/harness_lib.lua + game mocks)
  → sh shared/tools/validate.sh <Game>.lua    # luac -p + template diff + style checks
  → sh shared/tools/repack.sh ...             # repack zip (originals byte-identical)
  → push repacked zip to Public (convention commit: "<game>: add <Game>.lua automation (...)")
  → update work/lua/TASK_SOURCE.md table + TASKS.md + shared/lessons.md
```

Hard rules that end sessions when broken (full list in the rules file):
- Never fabricate a remote name/arg — verify from the deobf/dump, else stop and say so.
- Fix the user's file inside their zip (§20.5), not our local fork.
- Wrapper vs wire: hook payload indices come from the wire-level namecall
  (trace EasyEvents-style wrappers to the raw instance call), not the wrapper
  signature (§20.6); cloneref means script refs may be clone proxies — compare
  against fresh `game:GetService` originals too (§24).
- A closed game (deleted zip) stays closed unless the user explicitly re-opens.
- Clean coding principles (internet-sourced) are mandatory: every function
  earns its existence; spec-table + one runner beats N copy-pasted wrappers;
  one pcall owner (SafeLoop); init ≠ step; constants carry provenance. See
  `work/lua/clean-code-violations-scpinc.md` for the full catalog of the smells.
- Tool-output `[REDACTED:...]` display is not file content — verify secrets by
  grep count, never by reading the screen.

## 3. Collaboration protocol (daily loop)

- Before every reply: `git pull --rebase`, answer `msgs/<you>/` first (delete
  messages after handling), skim `status/`.
- After every step: update `status/<you>.md`, commit, `git pull --rebase`, push.
  Small commits. Never force-push.
- Only the owner edits a file; everyone else sends messages/patches to
  `msgs/<owner>/`. Your own `logs/<you>.md` is append-only memory.
- Deliverables for the user go to the Public repo (repacked game zip only).
- If you learn something the hard way → `shared/lessons.md` (one bullet, mark
  tested/not). If you change rules → `shared/changelog.md` line.

## 4. Where things live

| Path | What |
|---|---|
| `TASKS.md` | task list + owners — claim here first |
| `status/<name>.md` / `logs/<name>.md` | per-session state / append-only history |
| `msgs/<to>/` | message folders (delete yours after handling) |
| `shared/PROMPT.md` / `lessons.md` / `changelog.md` | rules / mistakes / rule changes |
| `shared/tools/` | reusable scripts (each has a one-line header description) |
| `work/lua/GLM_SCRIPTING_RULES.md` | the 24-section scripting guide (binding) |
| `work/lua/TASK_SOURCE.md` | game history: processed / closed / open |
| `work/lua/Template.lua` | canonical script template (re-sync from new zips) |
| `work/lua/worklog.md` | full scrubbed history (deep dives only) |
| `work/lua/*.md` | analyses, notes (e.g. snack-macro-analysis, clean-code notes) |

## 5. Common time-sinks and their shortcuts

- "Where is the game source?" → `newgame.sh` prints the deobf/dump paths.
- "Is my script template-clean?" → `validate.sh` (luac + diff + style).
- "How do I deliver?" → `repack.sh --commit` (MD5-verifies originals first).
- "The harness ate my day" → start from `harness_lib.lua`; grep for
  `FindFirstChildOfClass` in your mock BEFORE debugging silent pcall
  failures (known gap class, see lessons).
- "Token looks redacted" → it's display-only; grep the file for `ghp_`.
