# HARNESS KIT — mock-harness primitives for Lua 5.4 game-section testing

The most complete, battle-tested harness is **`work/lua/snack_harness.lua`**
(1,625 lines, 157 checks: Round 83 / Lobby 52 / AFK 22, including a cloneref
simulation that fails on regression). SCP Incremental's is
`work/lua/scpinc_harness.lua` (100 checks). Copy the snack one as your starting
point — every primitive below exists there and is proven.

## Why real Lua 5.4 (not Luau)

The game section must run in our portable Lua 5.4 (`bootstrap.sh`). Luau-only
globals don't exist there, so harnesses SHIM exactly the delta:
`unpack`, `table.clone`, `string.split`, `math.round`, `typeof`, `task.*`,
`game`/`workspace`/`Instance` globals. If your script needs a shim the kit
lacks, ADD the shim to the harness — never "fix" the script to be
harness-friendly (in-game it runs under Luau where those globals are real).

## Primitive inventory (snack_harness.lua line refs)

| primitive | line | what it mocks |
|---|---|---|
| `check(name, cond)` | 4 | assert-with-tally; final PASS/FAIL summary |
| `pumpAll(n)` / `trackCo` | 23-70 | task scheduler: tracks spawned coroutines, pumps n cycles — Roblox task.spawn/delay semantics |
| `v3(x,y,z)` / `cf(pos)` | 71-107 | Vector3 / CFrame-lite with the members scripts touch |
| `makeSignal(name)` | 108 | RBXScriptSignal: Connect/Fire/Wait |
| `makeInst(name, className)` | 126 | Instance mock: children LIST (same-named siblings!), attrs + changed signals, FindFirstChild/WhichIsA/OfClass, GetDescendants, IsDescendantOf, Clone/Destroy, PivotTo/GetBoundingBox |
| `mockRemote(name, className)` | 242 | RemoteEvent/RemoteFunction: FireServer/InvokeServer counted per remote, OnClientEvent/OnServerEvent signals, **InvokeServer returns canned server responses and applies mock server state** (e.g. bumps tower Level — that's how post-original reads are tested) |
| `requireShim` / `makeModule` | 344-377 | ModuleTree/require for ReplicatedFramework modules |
| `makeToggle/Option/Label/Groupbox` + Tab mock | 378-460 | Linoria/Fluent UI: AddToggle/AddDropdown/AddSlider/AddInput/AddButton/AddLabel/AddDivider, Values map for multi-dropdowns, OnChanged dispatch via task.spawn (coroutine semantics — direct dispatch deadlocks a busy main loop) |
| `__namecall` chain | — | hookmetamethod simulation: install BEFORE script load, chain originals, `nargs[1] = self` (wire-level indexing!) |
| cloneref proxy | — | script's `game:GetService` returns a proxy with CLONED remotes; game-side calls use originals — capture must go through OrigRemotes or the test fails (proves guide §24) |
| virtual clock | — | os.clock override so poll timeouts resolve in pumped cycles, not real seconds |
| JSON codec | — | readfile/writefile roundtrip for macro save/load tests |

## Hard-won harness rules (all cost real bugs — lessons.md has the stories)

1. **Reset world state between test phases** (towers, attrs, saved files) —
   fast SafeInvoke lets later phases loop many iterations per pump and reuse state.
2. **Mock every method the script calls**, including `FindFirstChildOfClass` —
   a missing method silently error'd inside pcalls for whole sessions.
3. **Model the WIRE, not the wrapper**: the deobf wrapper (EasyEvents etc.)
   resolves the remote and forwards only varargs → hook sees `(self, payload)`.
   A harness that models the wrapper signature stays green while the game
   captures nothing (the Snack bug). Trace the wrapper to the raw call first.
4. **InvokeServer with a done-flag** (not poll-until-timeout) when the mock
   server can answer immediately — otherwise tests burn virtual time.
5. Multi-dropdown Values map keyed by the EXACT option strings the script sets.
6. `SetValue` handlers dispatch via `task.spawn`, or a direct OnChanged call
   inside a busy Func loop hangs the main thread forever.
7. Assert on FIRE COUNTS + argument shapes (what actually went over the wire),
   not on internal script state.

## Runner pattern

```sh
cp ~/Public/<game>.zip . && unzip -o <game>.zip -d g && cp g/<game>/<Game>.lua /tmp/sut.lua
. ~/.lua54-env.sh
lua5.4 snack_harness.lua Round   # phase args let you debug one suite
```
Keep harness files versioned in `work/lua/` — the next session inherits the kit.
