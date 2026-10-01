# Snack macro "Recording [0]" — root-cause analysis (glm2, 2026-10-01)

Status: **diagnosed, fix prepared, NOT applied** — Snack was declared closed in
`work/lua/TASK_SOURCE.md`; per the "only fix when told" rule we wait for the user's
go-ahead (the fresh `error/error.txt` + `tdref.zip` upload in the Public repo looks like
a re-open signal, but it is not an explicit instruction).

## Symptom (Public repo `error/error.txt`, tested 2026-10-01 18:55–18:56 +0700)

```
[18:55:39] __namecall hook installed
[18:55:39] MacroLabel Idle | Waiting
[18:55:39] MacroLabel Recording [0]
[18:55:50] MacroLabel Idle | Stopped (0)      <-- 11s of real placement, 0 captured
[18:56:16] MacroLabel Idle | Waiting
[18:56:16] MacroLabel Recording [0]           <-- second attempt, same result
```

The hook installs, the game remote fires (user placed towers), zero entries recorded.

## Root cause (source-verified)

**Payload index mismatch in `SnapshotCall`.**

1. Snack's client calls remotes through the **EasyEvents module**
   (`ReplicatedFramework.Utilities.EasyEvents`, round deobf line 861:
   `local var11 = require(var2.Utilities.EasyEvents)`), e.g. placement
   (line 4510–4532):

   ```lua
   local str1 = "PlaceTower"
   local tbl1 = { towerKey = var2, slotIndex = ..., x = ..., y = ..., z = ..., rotationY = ... }
   return var11:InvokeServer(str1, tbl1)
   ```

2. EasyEvents itself (deobf lines 87918–87919) is a thin resolver — **the action
   name never reaches the wire**:

   ```lua
   tbl1.InvokeServer = function(_, arg2, ...)
       return ensureRemote(arg2, "RemoteFunction"):InvokeServer(...)
   end
   ```

   → actual wire call: `RS.FrameworkEvents.PlaceTower:InvokeServer(payload)` —
   ONE wire argument.

3. The `__namecall` hook therefore receives `(self, payload)`:
   `nargs[1] = self`, **`nargs[2] = payload`**, `nargs[3] = nil`.

4. `usethisfileSnack.lua` line 1392 (Slop-ported convention):

   ```lua
   local function SnapshotCall(self, nargs)
       ...
       local payload = nargs[3]   -- BUG: expects (self, name, payload); Snack wire is (self, payload)
   ```

   → `payload` is always `nil` → every branch's type guard fails
   (`type(payload) ~= "table"` / `typeof(tower) ~= "Instance"`) → `return nil`
   → nothing inserted into `Shared.MState.Pending` → `Recording [0]`.

The convention came from the Slop port (Slop's own wire really was
`(name, cf, ...)` — see `tdref/Slop.lua` lines 1181–1190: `name = nargs[2],
cf = nargs[3]`; Alliance similarly `nargs[2] = unitId, nargs[3] = cf`).
Snack's EasyEvents consumes the name **before** the wire, so the ported
indexing is wrong for this game. Our own `Invoke()` path was already fixed in
commit 738d52b ("fix easyevents wire args") to call
`remote:InvokeServer(payload)` — the **hook side was not**.

## Why the 98/98 harness checks passed anyway

The mock harness fired the hook as `(self, name, payload)` — i.e. it modeled
the **wrapper-level** EasyEvents signature, not the **wire-level** namecall.
The tests validated the capture chain against a protocol that never happens
in the real game. (Worklog note "hook payload index nargs[3] not nargs[2]
(hook receives self at [1])" adjusted the harness to keep nargs[3] — that was
the wrong direction for this game.)

## The fix (one line, when green-lit)

`usethisfileSnack.lua` line 1392:

```diff
-    local payload = nargs[3]
+    local payload = nargs[2]
```

Nothing else in the chain needs changing: downstream (ResolveCall →
ProcessPendingSweep → ConfirmPlace/Upgrade/Sell/Mode → RecordAct →
SaveMacro JSON → replay via our `Invoke("PlaceTower", payload)` →
`remote:InvokeServer(payload)`) is wire-correct and was exercised by the
harness roundtrip.

Per §20.5 edit-target discipline: when the user says fix it, the edit goes
into **`tdref.zip`'s `tdref/usethisfileSnack.lua`** (repack that zip), not
into a re-derived build.

Also fix the harness mock (when re-testing): invoke mock remotes as
`remote:InvokeServer(payload)` so the hook sees the real shape; add a
protocol-shape assertion (hook varargs count == 2 for single-payload actions).

## Supporting observations

- The user's own edits in `usethisfileSnack.lua` vs our last pushed
  `Snack.lua` (commit 738d52b) are unrelated to the bug: queue approach
  `TweenTo(60, zone)` → `TPTo(zone)` and `task.wait(5)` → `task.wait(1)`
  (lobby AutoQueue speed tweaks). Their build = our 738d52b build + those
  two tweaks, 121 bytes smaller.
- The second 18:56:16 recording failing identically confirms a systematic
  protocol mismatch, not a flake.
- `WaitForMacroRemotes` fails **silently** if the 4 remotes don't resolve
  (no notify) — worth adding a "macro remotes missing" warning if any
  future in-game test still shows 0 after this fix.

## Lessons (also added to shared/lessons.md)

- Hook payload indices must be derived from the game's **wire-level**
  namecall (trace the wrapper module down to the raw instance call in the
  deobf), never from the wrapper-level signature or a previous game's port.
- A green mock harness only proves the code matches the harness's model of
  the protocol — verify the model against the deobf call site (§20.1/§20.4).
