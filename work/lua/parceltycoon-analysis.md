# Parcel Tycoon [HALLOWEEN] — analysis (PCT1)

Public b405a45 (force-push #4 wiped LP1 trees — LP1 paused anyway, canonicals safe in
SavedFolder work/lp/). Zip: single-place game. Deobf 132,011 lines, dump 50,727 lines.
No Template.lua in zip → canonical 945-line template stands (md5 c42bde67 verified
both copies). User order: plain "next game" → standard autofarm (Rule 16/§3) + §26 ESC
census + clean-code inline directive.

## 1. Architecture

- Networking: TWO RemoteEvents only (`ReplicatedStorage.Remotes.Action` + `.Sync`),
  muxed name+payload protocol. Client send wrapper = `Store.send(name, payload)` →
  `Net.action():FireServer(name, payload)` (Net module 110338; send def 31976).
  Server→client: `Net.sync().OnClientEvent(kind, payload)` (Store.start 31982).
- Client state oracle = `PlayerScripts.Client.Store` module (31950): `.profile`
  (cash, pads, halloween{wheel}, firsts, stats, automation{handtruck}), `.station`
  (packing state snapshot), `.staff`, `.ranks`, `.restart`, `.catalogue`,
  signals ProfileChanged/StationChanged/CashTick/Result/Sealed/Notify. `Store.send`
  is THE wire entry.
- Pack protocol = `PlayerScripts.Client.Packing.Predictor` (50491): `.request(op,
  payload)` → validates against local `Shared.StationSim` mirror → `Store.send(
  "pack", {op, seq, orderId, ...payload})`; `.server` = latest station snapshot
  (state/orderId/order/board/queue/boxId/placed/wrapped/filled/boxChosen/folded/
  unlockedBoxes/carrying/carryMax/cart/ack/rejected). Ops (StationSim 115230+,
  all call-site verified):
  - `Take {ticketId}` (controller 46405, board slips 71074)
  - `Box {boxId}` (46218; guard: boxId ∈ order.boxes AND unlockedBoxes)
  - `Fold {}` (46946; pet boxes auto-fold in Box op)
  - `Place {uid, x, z, o}` (45926; x∈[0,dims1-1], z∈[0,dims3-1], o∈[0,MaxOrient],
    y stacked server-side; only x/z/o on the wire)
  - `Unplace {uid}` / `Undo {}`
  - `Wrap {uid, on}` (45566/45780; ONLY fragile items — order.byUid[uid].fragile)
  - `Fill {on}` (46466; requires ALL items placed + emptyCells>0 + non-pet box)
  - `Seal {stamps, stamp}` (47528; stamps = Shared.Handling.needsFor(item-ids)
    108552 / stampNeeds 47611; stamp = first of list)
  - `Abandon {}`
- Pallet layer (optional plot build): `send("pallet", {op})` — take/place/undo/wrap/
  leave (22552/22792/22826/22953/24555). Only active when plot has the pallet bay.
- Post-seal carry: `send("cart", {op="take"})` (46398) → server sets Carrying attr
  → deposit = NO WIRE: server-side proximity at plot `DropMat` (dispatch, found via
  plot:FindFirstChild("DropMat", true)) or `FreightMat` (truck bays, +20%,
  41244); delivery "via" dispatch/runner/guest/freight (996/11892).
- Plot resolution: `workspace.Plots["Plot"..Player:GetAttribute("PlotIndex")]`
  (41728 bayPoint pattern). Pads = plot children `Pad_<id>` with PadId attr.

## 2. Wire table (KEEP candidates, all call-site verified)

| Action | Wire | Call site |
|---|---|---|
| Take order | pack Take {ticketId} | 46405, 71074 |
| Choose box | pack Box {boxId} | 46218 |
| Fold carton | pack Fold {} | 46946 |
| Place item | pack Place {uid,x,z,o} | 45926 |
| Wrap fragile | pack Wrap {uid,on} | 45566, 45780 |
| Paper fill | pack Fill {on} | 46466 |
| Seal box | pack Seal {stamps,stamp} | 47528 |
| Pick up parcels | cart {op="take"} | 46398 |
| Buy plot pad | purchase {kind="padOffer", pad=id, buy=true} | 562 |
| Staff train | staff {op="train", id, stat} | 96663 |
| Halloween wheel spin | halloweenSpin {} | 68244 |

REMOVED per Rule 11: ux (53 sites — pure telemetry), theme/story one-shots
(cosmetic/intro), settings sync (UI prefs), dev ops ×10 (admin-only: unlockAll/
fresh/skip/lesson/style/state — server-gated presumably, admin class anyway),
purchase pass/product/refresh (ROBUX + shop UI one-shot), lots close (UI flow),
palMascot (cosmetic), return (fast-travel), zone wake/audit/meeting/score/quit
(bed wake-up + minigame UI flows — scores are client-reported but the games
themselves are drag/timing UI, not wire-automatable; see ESC), halloweenCome/
Greeted/Go/Gift/Seen (stateful visitor director driven by UI-internal due()/
calm()/night bookkeeping — the wheel spin is the clean event wire), rebirth
(NO client trigger wire exists — only {op="idle"} ping during the server-driven
ceremony 31374; RbCan/RbWhy attrs are server-set).

## 3. Money loop (the autofarm)

Board (station.state=="board", station.board = order slips with orderId/reward/
rep/rush/par) → Take → Box (smallest offered box that Solver-solves all items;
order.boxes ∩ unlockedBoxes) → Fold → Place ×N (plan = Shared.Solver.solve(box,
order.items, {perfect=true}).placed {uid→{x,y,z,o}}, stepped in DemoPlan y/x/z
order; send x/z/o only) → Wrap fragile placed items → Fill if emptyCells>0 →
Seal {stamps=Handling.needsFor(ids), stamp=first} → cart take → TPTo DropMat (or
FreightMat when present, +20%) → server detects deposit (Carrying attr drops,
station returns to board/queue) → repeat. All ops via Predictor.request (returns
error string on local reject — pace 0.3s/op, pcall each, fresh Store.station
reads each cycle). Shared modules (Solver/DemoPlan/Handling/Boxes/HalloweenWheel/
Pads) are require-able client-side — the game's own planners ARE the feature.

Halloween wheel: Shared.HalloweenWheel.ready(profile.halloween.wheel) — first
spin free, then charged by 600s play time; slices = cash/effect buffs. AutoSpin:
TP to plot MagicPumpkin then send halloweenSpin {} when ready.

Pads: 34 entries in Shared.Config.Pads (id/kind/cost/after/requires); owned =
profile.pads[id]; AutoBuy = cheapest un-owned with "after" satisfied + cash ≥
cost → TPTo(Pad_<id>) → purchase padOffer (server proximity-checked presumably;
TP first mirrors the game flow).

Staff: Store.staff list with stats; train via staff op (trainCost from the game's
own shared module; cheapest affordable stat per staff member).

## 4. ESC — exploit surface beyond remotes (§26)

- **Attributes**: player attrs (Carrying/Pulling/FriendPay/HalloweenOn/
  HalloweenDressed/LotCount/PlotIndex/RbCan/RbWhy/Ready/VIP) = SERVER-set
  read-only oracle. Plot attrs (OwnerUserId/PumpkinPadAt/Bay) server-set. Client
  SetAttribute census (5218-11775): cosmetic-only on client-owned instances
  (SkinHidden/Worn/Stroke/PalShelf/PalId/PalMood/BeltHits/FriendTags — belt/pet
  skins). NO client-writable server-read attribute found — CHECKED NEGATIVE.
- **Save system**: server code NOT in dump (no ServerScriptService/ServerStorage
  entries) — DataStore pipeline invisible. Profile/cash flow is server-
  authoritative (sync "cash"/"profile" pushes; purchases carry no amounts — pad
  ids only). No client-authoritative stat-sync remote exists — CHECKED NEGATIVE
  (this is NOT a STC-class client-authoritative economy).
- **Mutable client-trusted tables**: Shared configs (Economy/Pads/Boxes/
  HalloweenWheel) power client logic+display but server ops carry only ids —
  local mutation = display desync only, no economic effect. LocalPrice (108750)
  = ROBUX product display pricing (devproduct listPrice overrides), not the cash
  economy. CHECKED NEGATIVE.
- **Cooldown hooks**: cooldowns are UI-level only (spin button 1.5s 67530,
  halloweenGo 2s 112605, PumpkinGo daily 57600 120766); the authoritative gates
  are server-profile state (wheel play/spins). No §26.4 value. NEGATIVE.
- **Numeric injection (NaN/±inf)**: zone minigame score {token, score} IS a
  client-reported numeric with no client-side cap (77995+) — probe-class
  candidate (server cap unknown, server code invisible); documented NOT wired
  per §26.6. Pack grid coords are range-validated by the shared rules mirror;
  purchase/staff/spin carry no free numerics. No "nan"-string tonumber input
  found client-side.
- **\255 rollback**: no persistent client-string field found (company name is a
  one-shot intro story op; orders/pads server-generated). NEGATIVE.
- **Ownership/replication**: standard character physics only; TPTo/TweenTo
  covers movement (deposit is server proximity). Nothing gates on forged
  character state beyond position. NEGATIVE.
- **dev ops**: unlockAll/fresh/resetPurchases etc. behind the dev panel
  (85087+) — if the server fails to gate them it's admin-class anyway (Rule 11);
  documented, not wired.

## 5. Build plan

Yuri/ParcelTycoon/ParcelTycoon.lua on the 945-line template (head 873 verbatim +
game section + tail; SaveManager folder Yuri/ParcelTycoon). Toggles on
TB_Tabs.Autofarm.T1 with dividers, plain ids, elements-first, Thread+SafeLoop
per feature, pcall per step, inline resolution (no wrappers), 0 comments:
- AutoPack (toggle) + PackDelay slider (0.3-1s) — the full loop above
- AutoBuyPads (toggle) — cheapest-first pad ladder
- AutoSpin (toggle) — Halloween wheel when ready
- AutoTrain (toggle) — staff cheapest affordable stat
Harness: mock world (Store/Net/Predictor-lite/StationSim-real/Shapes) with the
real template, loadstring-run, wire-tuple + state-machine + banned-wire checks.
