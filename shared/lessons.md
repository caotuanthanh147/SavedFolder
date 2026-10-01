# Lessons (shared/lessons.md)

Append what worked / failed / what to do differently. Mark "trusted" only after testing. Cap ~100 lines.

## Delivery & environment

- **Tool-output secret redaction is display-only** (tested: oldglm worklog grep `ghp_` count = 2 while the same lines displayed as `[REDACTED:github_token]`). A "redacted" token in a displayed file may still be live in the file itself. Verify with `grep -c` or use it via shell variable without echoing. The 2026-10-01 SCPINC session lost push ability to exactly this trap.
- **Repo delivery convention** (tested across snack/camera/towerinc commits): push the REPACKED game zip (originals byte-identical + new/updated `<Game>.lua` inside) to the Public repo root; commit message `"<game>: ..."`. Never push loose files there.
- **User closes games by deleting their zip** from the Public repo. A missing zip is not an error; TASK_SOURCE.md's table is the record. Do not resume a closed game unless the user re-opens it (explicit fix order in chat beats inference; fresh error logs alone are only a signal).
- **IM-gateway file attachments are unreliable**. The GitHub repo is the authoritative channel.

## Roblox hooking

- **Hook payload indices come from the WIRE-level namecall, not the wrapper** (tested: Snack fix 2026-10-01, harness 157/157 after correcting the model): Snack's `EasyEvents:InvokeServer(name, payload)` resolves the named remote and forwards ONLY the payload (`ensureRemote(name):InvokeServer(payload)`), so the __namecall hook sees `(self, payload)` — payload at `nargs[2]`. The Slop-ported `SnapshotCall` read `nargs[3]` → captured nothing in-game while the mock harness (which modeled the wrapper signature) stayed green. Trace the wrapper module to the raw instance call in the deobf before coding ANY hook arg indexing.
- **A green mock harness only validates the harness's protocol model.** Cross-check the model against the deobf call site — or the harness will happily pass on a protocol that never happens in-game.
- **cloneref executors (Cobalt) break rawequal(self, ScriptRef) hook gating** (tested: Alliance verified by user; Snack harness now simulates it): the script's Services-metatable refs are clones, while the game-side namecall `self` is the original → single-rawequal gate never matches → 0 captures despite a healthy "hook installed" log. Fix: OrigRemotes table filled from a FRESH `game:GetService("ReplicatedStorage")` (bypasses the cloneref'd Services cache) + double-rawequal check (OrigRemotes first, then script refs). Harness pattern: make cloneref return a proxy RS for the script, keep originals for game-side calls.
- **hookfunction on RemoteFunction:InvokeServer does not intercept `:`-syntax calls** on some executors; `__namecall` hookmetamethod is the only reliable primary hook. "hook installed" != "hook fires". Supplementary hookfunction must target the ORIGINAL's method (OrigRemotes.X.InvokeServer) and dedupe via a namecall-seen marker (NCSeen).
- **Original-first capture + post-state reads**: snapshot AFTER `originalNamecall(...)` sees server-mutated state (mock server bumps tower Level during the original call). For "resulting level" semantics read post-state WITHOUT `+1`; for pre-state semantics snapshot before the original. Snack Upgrade LVL = resulting level (tier index + replay skip level) — post-read, no +1.

## Lua/harness mechanics

- **Lua 5.4 vs Luau**: `unpack`/`table.clone`/`string.split` are Luau-only — harness must shim; scripts must not depend on them (GLM rules).
- **Shared.Labels = {} must be initialized first** in every game section (TowerInc crash class — whole section dies at first SafeLabel).
- **Fast SafeInvoke changes test timing** (tested: Snack harness 2026-10-01): replacing a poll-until-timeout invoke (2 virtual sec/iteration) with a done-flag invoke lets loops complete MANY iterations per pump — tests that reused state across phases (towers left at max level) silently broke. Reset world state between test phases.
- **Mock instances need every method the script calls** — `FindFirstChildOfClass` was missing from the mock Inst and every GetCharacter() call silently error'd inside pcalls for sessions (only surfaced when a test finally asserted on a TP position). Grep the script for `:FindFirstChildOfClass(` etc. when extending mocks.
- **Tool display can eat `[m` character pairs** — `slotByName[model.Name]` displays as `slotByNameodel.Name]` in tool output while the file bytes are correct. Verify suspicious "corruption" with `rg`/`od` on the raw file before "fixing" it.
