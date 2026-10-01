# SEARCH — internet lookups for scripting unknowns

Principle first: **the dump beats the internet.** Remote names, payload shapes,
tags, attributes, game mechanics — verify from the game's own deobf/dump with
`deobf_search.py`. Search the web only for ENGINE/API semantics, executor
behavior, library docs, and error strings the dump can't explain.

## How to search (this sandbox)

```sh
z-ai function -n web_search -a '{"query": "...", "num": 5}' -o out.json
# recency filter for executor/tooling news: '{"query": "...", "recency_days": 30}'
```
Read `out.json` (fields: url / name / snippet / host_name / date). Always open
the top hit and read the ACTUAL page, not just snippets — summaries drift.

## Canonical sources (verified live 2026-10-01)

| source | use it for |
|---|---|
| `create.roblox.com/docs/reference/engine/classes/` | official class/member reference (RemoteEvent, Instance:GetAttribute, GetAttributeChangedSignal, CollectionService:GetTagged ...) |
| `create.roblox.com/docs/scripting/events/remote` | remote events/callbacks semantics |
| `luau.org/syntax` | Luau syntax by example (what's legal in-game) |
| `www.lua.org/manual/5.4/` | what our Lua 5.4 harness supports (the delta vs Luau is exactly what breaks harnesses) |
| `devforum.roblox.com` | engine Q&A, behavior reports, detection threads |
| `github.com/dawid-scripts/Fluent` + `forgenet.gitbook.io/fluent-documentation` | the UI library our scripts use |
| `scriptblox.com`, r/robloxhackers (reddit) | executor ecosystem news, script examples — treat as hints, never as truth |

## Query templates that work

- Unknown API semantics:
  `roblox <ClassName>:<MemberName> documentation`
- Executor-specific behavior (cloneref, hooks, caps):
  `roblox exploit <thing> behavior` then `site:devforum.roblox.com <thing>`
- Library question: `Fluent roblox library <element> <property>`
- Luau vs 5.4 doubt: `luau <feature> vs lua 5.4` / check lua.org manual directly
- A game's structure when the dump is ambiguous (rare, hint-only):
  `"<Exact game title>" roblox wiki towers` etc.

## Known answers already paid for (don't re-search)

- `cloneref` clones game objects so anti-cheat can't ban the original ref →
  `rawequal(scriptRef, gameSideRef)` is FALSE on cloneref executors (Cobalt).
  Fix: fresh `game:GetService` refs + double-rawequal (guide §24).
- `hookfunction` on `RemoteFunction:InvokeServer` misses `:`-syntax calls on
  some executors → `__namecall` hookmetamethod is the primary hook (guide §20).
- Luau-only: `unpack`, `table.clone/freeze`, `string.split/trim`, `math.round`,
  `bit32`, `typeof()` — banned in game sections (Lua 5.4 harness), shimmed in
  harnesses (lessons.md "Lua/harness mechanics").

## After you search

If the answer is engine-semantics and reusable → one-line summary into
`shared/lessons.md` (with the source URL). If it changed how we build scripts →
guide section + changelog. Hints that didn't verify against a dump → don't
record as trusted; mark them `(unverified hint)`.
