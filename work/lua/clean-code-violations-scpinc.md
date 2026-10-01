# Clean Coding Principles — violation notes for SCPIncremental.lua (glm2, 2026-10-01)

User instruction: *"in the previous script you violate this rule — Clean Coding Principles
(internet-sourced, mandatory for every script). Don't have to fix it, just take notes."*
This file is the notes. **No changes were made to SCPIncremental.lua** (game shipped,
100/100 checks; per the "fix only when told" rule these stay notes until the user orders
a cleanup — and then the edit target would be the delivered zip per §20.5).

## The rule

**Primary: GLM guide §21 "Clean Coding Principles (internet-sourced, mandatory for every
script)"** (glm1's codification — KISS/DRY/YAGNI/dead-code/names/one-thing/no-surprises/
boy-scout/minimal-scope/delete>add/structure-mirrors-reference) + §23 Snack violation
catalog. This file is the SCPINC-specific companion catalog (the user flagged it
after the Snack rewrite). Cross-refs below use those rule numbers.

Supplementary web sources (glm2, 2026-10-01):

- **Functions should be small, do one thing, and only exist for a reason** —
  Single Responsibility Principle for functions
  (medium.com/swlh/clean-code-writing-functions-or-methods-4e6e53ff4ac2,
  algocademy.com/blog/understanding-the-principles-of-clean-code,
  dev.to/alisamir/understanding-clean-code-functions-3f5k).
- **Avoid unnecessary function indirection / trivial wrappers** — "Each of the
  function is just a wrapper doing as little as preprocessing the input and
  returning the response. Do we at all need them? We don't."
  (afiz-momin.medium.com/avoid-unnecessary-function-indirection-cb2d0a509d9b).
- **"In most cases you don't need a function unless the code is called in more
  than one location"** (reddit.com/r/cpp clean-code discussion).
- **Lua-specific**: "Clean code is code that another person can understand and
  safely change. Clear names and small responsibilities matter more than clever
  tricks." (grillcode.site/docs/lua/best-practices); LuaRocks style guide
  (github.com/luarocks/lua-style-guide); MediaWiki Help:Lua/Lua_best_practice.
- **DRY / duplicated code + long function + magic number code smells**
  (marcoghiani.com/blog/10-programming-code-smells-that-affect-your-codebase).
- Roblox-flavored SRP discussion: devforum.roblox.com/t/2186450 (Writing Clean
  Code Part 2 — SOLID).

Distilled for our scripts: **every function must earn its existence** — it either
(a) is called from more than one place, (b) names a non-obvious concept worth
naming, or (c) isolates a testable unit. A function that only restates its callee
and is called from exactly one place is indirection noise, not abstraction.
Data + one generic runner beats N copy-pasted wrappers.

## Violation catalog

### V1 — Trivial wrapper functions (the user's example, and siblings)

```lua
local function StepRebirth()            -- SCPIncremental.lua:930
    if CS.canRebirth() then
        CS.rebirth()
    end
end
```

A 3-line guard+forward. Called from exactly ONE place (FuncRebirth:1206). The
name merely restates the callee (`StepRebirth` → `CS.rebirth`). It fails all
three earn-your-existence tests. Same class (single caller, guard + single
action, name restates callee):

- `StepPrestige` (936) — afford-check + `CS.prestige()`
- `StepGun` (945) — afford-check + `CS.request(BuyGun)`
- `StepGems` (986) — cooldown-check + `CS.claimGems()`
- `StepRanks` (966) — prestige gate + keycard batch roll
- `StepEquipBest` (976) — best-rank + equip-if-different
- `StepConvert` (955) — selection + afford + convert
- `StepLizard` (1054) — own-lizard tier/highest compare + select

Clean shape: a declarative step table + ONE runner, e.g.
`{ path="SCP.Rebirth", toggle="SCPRebirth", wait=1, step=function() if CS.canRebirth() then CS.rebirth() end end }`
— the step bodies become data, the wiring exists once. (Rule 17 compliance is
preserved: the runner still goes through `Thread(path, SafeLoop(path, ...), state)`.)

### V2 — The Func* wrapper layer: 13× copy-pasted control flow (the big one)

```lua
local function FuncRebirth()            -- SCPIncremental.lua:1202 (×13 total)
    while Toggles.SCPRebirth.Value do
        pcall(function()
            if SCPReady() then
                StepRebirth()
            end
        end)
        task.wait(1)
    end
end
```

FuncUpgrades/FuncRebirth/FuncPrestige/FuncGun/FuncConvert/FuncRanks/FuncEquipRank/
FuncGems/FuncGroup/FuncPotions/FuncTickets/FuncLizard/FuncGunFire (+FuncStats) —
the same `while toggle → pcall → SCPReady → StepX → task.wait(n)` shape with only
(toggle, step, interval) varying. ~130 lines of duplicated control flow
(DRY violation). Clean: one `FeatureRunner(spec)` closure over the varying parts
+ a spec table, exactly as in V1.

### V3 — Double pcall making SafeLoop's error reporting dead code

Each FuncX wraps its pass in `pcall(function() ... end)` (e.g. 1204), and is then
wired as `Thread("SCP.X", SafeLoop("SCP.X", FuncX), state)` (1516-1552). SafeLoop
ALREADY pcall's each pass and notifies on error — the inner pcall swallows errors
first, so SafeLoop's "Error in [SCP.X]" notify path can never fire for these 13
features. Two layers of error handling, one of them provably dead. Clean: drop
the inner pcall and let SafeLoop do its job (that's what Rule 17's machinery is
FOR), or if per-pass granularity was intended, drop SafeLoop — not both.

### V4 — Hidden state mutation + temporal coupling inside "steps"

- `StepGroup` (994): sets `SCP.GroupTried = true` as a side effect inside the
  step body — a "step" that mutates persistent flags is a state machine in
  disguise.
- `StepTickets` (1026): first call does something completely different (seeds
  GetTicketPrice queries, then `return`s) from every later call (sort + buy
  loop) — behavior depends on hidden call count. Clean: split into
  `InitTicketPrices()` (run once at toggle-on) + `StepTickets()` (pure buy
  logic); one-shot flags become explicit init, not phase detection.

### V5 — No-op empty-callback arguments

`CS.request(Net.Actions.ClaimGroupReward, {}, function() end)` (999) and
`CS.request(..., { productId = ... }, function() end)` (1048) — passing an
explicit empty function is argument noise. If the API accepts nil, pass nil;
if it requires a callable, define one named `local NOOP = function() end`
instead of littering inline empty closures.

### V6 — Repeated idiom not factored (DRY, small)

`if BigNum.gte(CS.getCurrency(X), BigNum.new(Y)) then ...` appears in
StepPrestige (939), StepGun (949), StepConvert (959). Clean:
`local function CanAffordBig(cur, cost) return BigNum.gte(CS.getCurrency(cur), BigNum.new(cost)) end`
— names the concept once.

### V7 — Boolean-via-if assignments

StepPotions (1008-1018):

```lua
local active = false
if type(expires) == "number" and expires > now then active = true end
if not active then
    local activeAttr = ...
    if Plr:GetAttribute(activeAttr) == true then active = true end
end
```

Clean: `local active = (type(expires) == "number" and expires > now) or Plr:GetAttribute(pot.ExpiryAttribute:gsub("ExpiresAt", "Active")) == true`.
Also V7b: `FarmAnyActive() and true or false` (1188) — FarmAnyActive already
returns literal booleans; the coercion is pure noise.

### V8 — Magic numbers without provenance names

- `25` batch cap in StepRanks (972) — game source says batch cap 25; deserves
  `local RANK_BATCH_CAP = 25`.
- `25` studs reposition threshold in StepGunFire (1096).
- `0.2`/`4` fire-rate floor/base (1072-1075), `30` default dwell (1167),
  waits `0.5/1/2` sprinkled through FuncX bodies.
Numbers that came from the game's source should carry their source in the name
(or a comment-free named constant, keeping the zero-comments rule).

### V9 — Deep nesting where guard clauses fit

StepUpgrades (914-928): `for → if → for → if → if` (4 levels). Clean: early
`goto`? No — zero-goto rule; use inverted guard continues at each loop level
(`if not selected[wall.Name] or not CS.isWallUnlocked(wall.Id) then continue`
equivalents via Lua 5.4/Luau `continue` — wait, Luau HAS continue; the
no-goto/continue guide rule applies to target scripts... check guide §"no
goto/continue" before suggesting; otherwise factor the inner loop body into a
small named helper).

### V10 — One function, many responsibilities + duplicated fetch

`StepGunFire` (1066-1112): equips the gun, computes fire rate, picks a target
(own lizard else zombie folder scan), repositions if >25 studs away, RE-fetches
`char`/`hrp` at 1101-1102 immediately after computing them at 1091-1092 (because
TPTo can invalidate — but the clean fix is re-fetch after the mutation point
only, or one `local function GetHRP()` helper used at both sites), aims, fires.
At minimum: `FindGunTarget()`, `FaceTarget(hrp, target)`, `EnsureAtShootingSpot(hrp)`
as named units; the double GetCharacter/FindFirstChild chain is the smell's
fingerprint.

### V11 — (minor) String-derived attribute names

`pot.ExpiryAttribute:gsub("ExpiresAt", "Active")` (1014) — deriving a sibling
attribute name by string surgery. It's game-data-driven so it's defensible, but
it's the "clever trick" grillcode warns about; a named local
`local function ActiveAttr(pot) ... end` with the derivation inside at least
isolates the trick.

### V12 — Stats labels (§23.2: "never make or add them in any game")

SCPIncremental.lua ships `FuncStats` + 17 SafeLabels (all Currencies.List entries,
Prestige/Gun Tier/Rank/Keycards/Tickets). §23.2 (user's own words on the Snack build):
"the Stats labels you made are useless — never make or add them in any game".
SCPINC predates that ruling; noted, not fixed.

### V13 — Game-prefix ids and thread names (§23.8)

`SCPUpWalls`/`SCPRebirth`/`SCPPotions`... toggle ids, `Thread("SCP.Rebirth",
SafeLoop("SCP.Rebirth", ...))` names, `SCP.X` Shared fields. §23.8: plain feature
names only — "the script already knows what game it's for". (The SaveManager
folder path "Yuri/SCPInc" is fine — it's a path, not an element id.)

## Violation → rule map (quick)

| Violation | Rule |
|---|---|
| V1 trivial wrappers | §21.1 KISS, §23.1 |
| V2 13× Func* boilerplate | §21.2 DRY (parametrize ONE runner) |
| V3 double pcall | §21.1 KISS ("re-checks the helper already does") |
| V4 hidden state / temporal coupling | §21.7 no side-effect surprises |
| V5 empty-callback args | §21.1 KISS |
| V6 repeated afford idiom | §21.2 DRY |
| V7 boolean-via-if / and-true-or-false | §21.1 KISS |
| V8 magic numbers | §21.5 meaningful names |
| V9 deep nesting | §21.6 one thing / one abstraction level |
| V10 StepGunFire multi-role + double fetch | §21.6 |
| V11 string-derived attribute name | §21.5 (clever > clear) |
| V12 stats labels | §23.2 |
| V13 game prefixes | §23.8 |

## What to do differently next game (process, not retrofit)

1. **Spec-table first**: before writing any Func*/Step* code, write the feature
   table (path, toggle, interval, gate, action) — it makes V1/V2/V3
   structurally impossible and review is one diff on data, not 13 diffs on code.
2. **One pcall owner**: SafeLoop owns error isolation; feature code never wraps
   its own pass in pcall. (Rule 17 already implies this — the SCPINC build
   violated it by belt-and-suspenders.)
3. **Earn-your-existence test for every local function**: called >1 place, or
   names a real concept, or isolates a testable unit — else inline it.
4. **Init ≠ step**: one-time seeding (price queries, first-run flags) goes in
   toggle-OnChanged handlers, not phase-detection inside loop steps.
5. **Constants carry provenance**: game-sourced numbers get named constants.
6. Keep zero-comments rule: names and structure must carry the meaning
   (that's WHY the clean-code rules matter more here — there are no comments
   to rescue unclear code).

None of this blocks the shipped script (all 100/100 checks green, delivered);
these are the notes for the next build and for any user-ordered cleanup.
