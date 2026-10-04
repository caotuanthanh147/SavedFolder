# Steal A Car — deobf analysis (glm4, 2026-10-04)

**Game**: Steal A Car (Public `Steal A Car/`, 0acfce8). No reference scripts
→ ONBOARDING §3 no-reference = standard autofarm BOTH halves (wire every
Rule-11-KEEP remote, invent nothing beyond).

**Deobf**: `Steal A Car[Deob].lua` 27257 lines + `game_dump.txt` ~302k lines.

## Net structure

`ReplicatedStorage.Remotes`:
- `.Events` (RemoteEvents) — `:FireServer(action, args)`
- `.Functions` (RemoteFunctions) — `:InvokeServer(args)` → returns result

Verified (deobf L7880): `local var2 = game:GetService("ReplicatedStorage");
local var3 = var2.Remotes.Events` → CombatRequest + RaceRequest live in Events.
SellCars/GetSellInventory accessed as `var21.SellCars`/`.GetSellInventory`
(Functions RFs).

## Wire table (verified at call sites — Rule 2)

| Toggle | Remote (RS path) | Wire | Call site | Args | Notes |
|---|---|---|---|---|---|
| AutoSwing | `Remotes.Events.CombatRequest` | `:FireServer("Swing")` | L8076, L7924 (setup) | none beyond action string | bat cooldown `var6.BatCooldown` gates; the steal action |
| AutoEquip | `Remotes.Events.CombatRequest` | `:FireServer("Equip", toolName)` | L8146 | toolName: "Bat" or "BearTrap" | from `BackpackGui.RequestedCombatTool` attr |
| AutoPlace | `Remotes.Events.CombatRequest` | `:FireServer("Place", position)` | L8048 | position: Vector3 (`var9.Position`) | places the stolen car; arg source = var9.Position (character/target) — use HRP.Position as default, flag for server validation |
| AutoSell | `Remotes.Functions.SellCars` | `:InvokeServer(inventoryTable)` | L3393 | inventoryTable (`var1 = tbl1`) → returns `{Success=bool}` | tbl1 = the sell inventory (built from GetSellInventory); autofarm: call GetSellInventory then SellCars with result |
| AutoJoin | `Remotes.Events.RaceRequest` | `:FireServer("Join")` | L8828, L8723 (setup `var2.Remotes.Events:WaitForChild("RaceRequest")`) | none beyond action string | join a race; `var26` debounce gates 3s |

## Read (supporting AutoSell)

| Read | Remote | Wire | Call site | Returns |
|---|---|---|---|---|
| GetSellInventory | `Remotes.Functions.GetSellInventory` | `:InvokeServer()` | L3355 | the sell inventory (passed to renderItems); AutoSell passes this to SellCars |

## EXCLUDED (Rule 11)

- `AdminCrateAction:FireServer("Claim", id, arg2)` (L15342, L15280) — "AdminCrate"
  prefix + `Assets.AdminCrate` context suggests admin-only crate feature;
  uncertain player-accessible; no user order → §2 cut.
- `var20.BuyTrailRobux` (L3143) — ROBUX.
- `var3.Remotes.Functions.CaughtSpeedPurchase` (L7531) — likely ROBUX (speed purchase).
- `var12.SetSlowMode` (L5782) — chat setting, not automation.

## Build plan (§3 both halves, 5 toggles)

- Template = `work/lua/Template.lua` (updated, AddSliderToggle handler form).
- Game section: 5 toggles on `TB_Tabs.Autofarm.T1`, §22-7 loops
  (`while Toggles.X.Value do pcall(step) task.wait(x) end`), Thread+SafeLoop wiring.
- AutoSwing: `CombatRequest:FireServer("Swing")` every ~0.5s (game cooldown gates).
- AutoEquip: `CombatRequest:FireServer("Equip", "Bat")` once on toggle (idempotent).
- AutoPlace: `CombatRequest:FireServer("Place", HRP.Position)` every ~1s (flag: position
  semantics to verify — server may reject if not a valid drop point).
- AutoSell: `GetSellInventory:InvokeServer()` → pass result to `SellCars:InvokeServer(...)`
  every ~2s (sell loop); verify the SellCars arg shape (tbl1 = the inventory list)
  in the harness — the mock server should accept the GetSellInventory result.
- AutoJoin: `RaceRequest:FireServer("Join")` every ~5s (race cooldown).
- No labels (§23), no comments (validate rule), no template-banned features (§14.2),
  no symmetric encode/decode, no AutoReexec/QueueOnTeleportExec (template ban).
- Real-load harness: io.open+loadstring+task.spawn the delivered .lua, pcall
  interceptor (silent-degradation detector), colon-safe service mocks
  (`function(_, ...)`), assert no ERROR notify + toggles registered + wire counts
  + FULL payload tuples after SetValue+pump. Mock CombatRequest/RaceRequest
  (FireServer recorder) + SellCars/GetSellInventory (InvokeServer recorder +
  mock server returns inventory + {Success=true}).
