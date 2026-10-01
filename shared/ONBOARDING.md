# ONBOARDING — new GLM instance? Start here (10 minutes flat)

You are a GLM instance joining a small AI team building Roblox automation scripts
(Linoria/Fluent UI, Luau, executor-side). glm1 is the senior instance. This file
gets you from cold start to productive without rediscovering anything.

## Minute 0–3 — environment

```sh
sh "$SF_DIR/shared/tools/bootstrap.sh"        # idempotent, ~10s
. ~/.lua54-env.sh                              # lua5.4 + luac5.4 on PATH
sh "$SF_DIR/shared/tools/poll.sh glm3" &       # your name; watch msgs
sh "$SF_DIR/shared/tools/watch_public.sh glm3" &  # watch game zips
```
Default clone paths: `$HOME/SavedFolder` and `$HOME/Public` (override with
`SF_DIR` / `PUBLIC_DIR` env vars — every tool honors them). bootstrap.sh
installs portable Lua 5.4.7 (survives /tmp wipes — never compile
from source again), clones both repos, and wires the push token silently.
If the sandbox was reset and SavedFolder itself is gone:
`git clone https://github.com/caotuanthanh147/SavedFolder.git ~/SavedFolder` first.

## Minute 3–8 — mandatory reading, this order

1. `shared/PROMPT.md` — group rules (short; overrides everything else).
2. THIS file (you are here).
3. `TASKS.md` — who owns what. Claim in the Owner column BEFORE starting work.
4. `work/lua/GLM_SCRIPTING_RULES.md` — the discipline guide, **head to toe,
   every session, before any operation** (this is a hard rule, not a suggestion;
   past incidents were all "skipped the reread" incidents).
5. `work/lua/TASK_SOURCE.md` — game history + per-game workflow notes.
6. `shared/lessons.md` — tested traps (cloneref, wire-level payloads, zip
   conventions, token redaction). ~100 lines, all paid for with real bugs.
7. Latest entries in `logs/*.md`, all `status/*.md`, your `msgs/<you>/` inbox
   (handle + delete messages addressed to you).

## The two repos

- **SavedFolder** (this repo): shared memory. Everything except deliverables.
- **github.com/caotuanthanh147/Public**: the user's repo. Game zips arrive
  there; ONLY finished deliverables go back (repacked game zip with the script
  inside, at the root, commit message `"<game>: ..."`, originals byte-identical
  — use `shared/tools/repack_zip.py`, it MD5-verifies for you).
- A game is OPEN while its zip exists at the Public root; the user CLOSES games
  by deleting the zip. Never resume a closed game without an explicit order in chat.
- IM file attachments are unreliable; the repos are authoritative.

## Standard pipeline (per game/fix)

1. Reread the guide head-to-toe (Rule 19). `git -C ~/Public pull`.
2. New zip → unzip to a scratch dir; note the 3 usual sources: your previous
   `<Game>.lua` (if a fix), the game's `[Deob].lua` dumps, `game_dump.txt`.
3. EVERY remote/payload/tag/attribute claim must be verified from the dump with
   `shared/tools/deobf_search.py` (`remote NAME`, `fn LINE`, `find`, `tags`,
   `attrs`) — never from memory, never invented.
4. Build/fix inside the game section of the canonical `work/lua/Template.lua`
   scaffold. The reference script's FEATURE SET defines scope — a remote
   existing ≠ a feature (Rule 23).
5. Mock harness in real Lua 5.4 (copy the kit from `work/lua/snack_harness.lua`,
   see `shared/HARNESS_KIT.md`). Green harness only proves the harness's
   protocol model — cross-check the model against the deobf call site.
6. Gates before delivery, ALL must pass:
   - `luac5.4 -p FILE` clean
   - `python3 shared/tools/lua_lint.py --from <gameSectionStart> FILE` → 0 errors
   - template diff = ONLY your intended regions (game section, SaveManager
     folder path, reference-mandated tab/window extensions)
   - harness suite green
   - `python3 shared/tools/repack_zip.py` → [VERIFIED]
7. Push to Public. Update: TASK_SOURCE table, TASKS.md, your status/ + logs/,
   shared/lessons.md if you learned something testable, changelog row.
8. Tell the user in chat what was delivered + known residual risks.

## Working as a group

- `msgs/<to>/<from>-<UTCtimestamp>.md` — short, one topic. The recipient
  deletes it after handling. Check your inbox before + after any long operation.
- Update `status/<you>.md` after EVERY step (Doing / Done this round / Stuck on
  / Files changed). Append-only entry per session in `logs/<you>.md`.
- Protocol step = edit → `sh shared/tools/sync.sh "<message>"`. It commits,
  pulls --rebase (absorbs the other glm's parallel work), pushes, and VERIFIES
  the remote actually moved — silent push failures lost us a full delivery day
  once. NEVER force-push. On an "AA conflict" in shared files (lessons/TASKS):
  merge content, don't pick sides.
- Token: comes from the user in chat or lives in the local sandbox worklog.
  NEVER write it into this repo, logs, or messages. Tool output redacts
  `ghp_…` at DISPLAY time only — grep for it in the file instead of eyeballing.

## Tool index (all in shared/tools/, all battle-tested)

glm1's set (2026-10-01) + glm2's set (same day, parallel) — unified:

| tool | what it saves you |
|---|---|
| `bootstrap.sh [name]` | cold environment in ~10s: repos + portable Lua 5.4.7 + token + session skeleton + state report (glm1+glm2 unified) |
| `deobf_search.py` | dump archaeology: remote map / payload shapes (`fn LINE`!) / blocks / tags / attrs — arg order tolerant (`FILE CMD` or `CMD FILE`) |
| `newgame.sh <zip>` | new-game scaffold: extract, structure check, deobf/dump inventory, Rule-18 checklist |
| `validate.sh <script>` | luac -p + template-diff measurement + style checks (glm2) |
| `lua_lint.py --from/--to` | mechanical violations scoped to your game section (glm1) |
| `repack_zip.py` / `repack.sh` | delivery repack with per-entry MD5 verification (two flavors: python API vs `--commit` push wrapper) |
| `sync.sh "<msg>"` | the ONE command per protocol step: commit → pull --rebase → push → **verify remote moved** (~6s vs ~45s manual, and it can't silently fail) |
| `watch_public.sh [--once]` | auto-detects new/closed game zips (T3); `--once` = single cycle (spot-check/testing) |
| `selftest.sh` | 10-check kit smoke test (~5s): run it after ANY tool edit — newgame space-paths, deobf arg orders, repack MD5, watch --once, harness 12/12 |
| `poll.sh` | SavedFolder msgs/pull loop |
| `harness_lib.lua` | generic harness prelude (scheduler/Instance/Signal/Linoria/SaveManager + Luau shims, 12-check smoke suite) — start every harness here (glm2) |
| `lua54.tar.gz` | the portable Lua itself (GitHub-persisted — survives full sandbox resets) |

## Clean coding (mandatory since the SCPINC review)

Every function earns its existence; spec-table + one runner beats N copy-pasted
wrappers; one pcall owner (SafeLoop); init ≠ step; constants carry provenance.
Full smell catalog with §21/§23 mappings: `work/lua/clean-code-violations-scpinc.md`.

## Where things live

| Path | What |
|---|---|
| `TASKS.md` | task list + owners — claim here first |
| `status/<name>.md` / `logs/<name>.md` | per-session state / append-only history |
| `msgs/<to>/` | message folders (delete yours after handling) |
| `shared/PROMPT.md` / `lessons.md` / `changelog.md` | rules / tested mistakes / rule changes |
| `shared/tools/` + this file's kin | reusable scripts (one-line header each) |
| `work/lua/GLM_SCRIPTING_RULES.md` | the scripting guide (binding, §1-§25) |
| `work/lua/TASK_SOURCE.md` | game history: processed / closed / open |
| `work/lua/Template.lua` | canonical script template (re-sync from new zips) |
| `work/lua/*.md` | analyses + notes (snack-macro, clean-code, …) |
| `work/lua/worklog.md` | 50-line summary + pointer; FULL history in `work/lua/worklog-archive-*.md` (deep dives only — lessons.md is the distillate) |

## Time-sinks → shortcuts

- "Where is the game source?" → `newgame.sh` prints deobf/dump paths.
- "Is my script template-clean?" → `validate.sh` + `lua_lint.py --from/--to`.
- "What does the game send on the wire?" → `deobf_search.py fn <call-site line>`.
- "How do I deliver?" → `repack_zip.py` (MD5-verifies originals; exits non-zero on any mismatch).
- "The harness ate my day" → start from `harness_lib.lua` (or snack_harness.lua for
  Linoria+cloneref-sim completeness); grep your mock for missing methods BEFORE
  debugging silent pcall failures (known gap class, see lessons).
- "Token looks redacted" → display-only; grep the file for `ghp_`.
- "Did my push actually land?" → it's built into `sync.sh`; manually:
  `git ls-remote origin HEAD` vs `git rev-parse HEAD`.

Stuck on something the dump can't answer? → `shared/SEARCH.md`.
Building a harness? → `shared/HARNESS_KIT.md`.
Just edited a shared tool? → `sh shared/tools/selftest.sh` (10 checks, all green = ship it).
(The old `shared/GUIDE.md` quickstart was folded into this file 2026-10-01 and
the pointer deleted 2026-10-02 — this file is the only onboarding doc.)
