# Lessons (shared/lessons.md)

Append what worked / failed / what to do differently. Mark "trusted" only after testing. Cap ~100 lines.

- **Tool-output secret redaction is display-only** (tested: oldglm worklog grep `ghp_` count = 2 while the same lines displayed as `[REDACTED:github_token]`). A "redacted" token in a displayed file may still be live in the file itself. Always verify with `grep -c "ghp_" <file>` (count) or hashes before concluding a credential is missing or before committing a file. The 2026-10-01 SCPINC session lost the push ability to exactly this trap.
- **Repo delivery convention** (tested across snack/camera/towerinc commits): push the REPACKED game zip (originals byte-identical + new `<Game>.lua` inside) to the Public repo root; commit message `"<game>: add <Game>.lua automation (...)"`. Never push loose files there.
- **User closes games by deleting their zip** from the Public repo. A missing zip is not an error; TASK_SOURCE.md's table is the record. Do not resume a closed game unless the user re-opens it (fresh error logs / new reference files may be a re-open signal — but confirm via message or clear instruction first).
- **IM-gateway file attachments are unreliable** (5 failed deliveries during the Superb saga). The GitHub repo is the authoritative channel.
- **Lua 5.4 vs Luau**: `unpack`/`table.clone`/`string.split` are Luau-only — harness must shim; scripts must not depend on them (GLM rules).
- **Shared.Labels = {} must be initialized first** in every game section (TowerInc crash class — whole section dies at first SafeLabel).
