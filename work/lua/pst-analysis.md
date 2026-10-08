# Pet Store Tycoon — deobf analysis (PST1, glm3, 2026-10-08)

Game: "Pet Store Tycoon" (single place, Public 146eb30). Deob 262,502 lines + dump 219,591 lines.
Genre: tycoon — run a pet store: order goods → stock shelves → set prices → customers buy →
manned checkout (cashier minigame) → pets/enclosures care → curbside deliveries → day cycle.

## 1. Transport

Direct folder remotes: `ReplicatedStorage.Remotes.<Category>.<Name>` (no wrapper framework,
no buffer mux). 179 remote instances total. Client resolves via `WaitForChild` chains and
fires/invokes directly. State replication = ReplicaService-style framework
(`ReplicatedStorage.RemoteEvents.Replica*` + `Modules.ReplicaClient`): server-authoritative,
client NEVER fires Replica* events (verified: client code only OnClientEvent for
Set/SetValues/Write/TableInsert/Remove/Parent/Create/Bind/Destroy; the only client→server
channel is `ReplicaSignal:FireServer(id, ...)` for signals). Client-side `Replica:Set()` is
local-prediction only (bool-gated "can't be called outside of WriteLibs client-side").

Plot resolution: `Modules.ActivePlot.getPlot()` = `workspace.Plots` children where
`OwnerUserId` attribute == `LocalPlayer.ActivePlotOwnerUserId` attribute (fallback UserId).

## 2. Wire table (verified at call sites)

| Remote | Type | Wire (client→server) | Deobf cite |
|---|---|---|---|
| Plot.OrderItem | RE | `FireServer({category=cat.Name, subCategory=sub.Name, item=item.Name})` | L250895 |
| Plot.StartNextDay | RE | `FireServer()` (fired on day-summary dialog close) | L220189 |
| Goods.SetGoodPrice | RE | `FireServer(goodKey: string, price: number)` (price = client React state) | L216306 |
| Goods.PurchaseGood | RF | `InvokeServer(category, name)` | L249981 |
| Goods.TakeFromShelf | RF | `InvokeServer(itemKey, slotIndex)` → boxKey string | L113535 |
| Goods.PlaceGoods | RF | `InvokeServer(boxKey, shelfKey, slotIndex)` | L182366 |
| Goods.PickUpBox | RE | `FireServer(boxKey)` | L183424 |
| Goods.DropBox | RE | `FireServer()` | L183356 |
| Storage.StowBox | RE | resolved L91814 |  |
| Goods.TrashBox | RE | resolved L116796 |  |
| Checkout.BeginShift | RF | `InvokeServer(tillModel)` → `{ok, state}` | L50657 |
| Checkout.ScanCurrent | RE | `FireServer(itemPart, transactionId, seq)` — itemPart = child of till w/ attrs CheckoutTransactionId + CheckoutItemIndex; seq = client CheckoutScanState counter | L50892 |
| Checkout.AcceptPresentedPayment | RE | `FireServer(true)` (phase AwaitingPayment) | L50924 |
| Checkout.SubmitCashChange | RE | `FireServer(countsTable)` — `{[denomId]=n}` (bill1/5/10/20/50/100, coin1/5/10/25/50), sum == state.changeDueCents | L50235 + CashTray L195320 |
| Checkout.SubmitCardAmount | RE | `FireServer(cents)` — exact `state.totalCents` | L50241 + CardTray L195483 |
| Checkout.EndShift | RE | `FireServer()` | L50373 |
| Mess.Clean | RE | `FireServer({messId = model.MessId attr})` | L95107 |
| Enclosures.BeginCare | RF | `InvokeServer({itemKey, feature, petKey?})` → `{ok, playable, token}` | L66041 |
| Enclosures.CompleteCare | RF | `InvokeServer({itemKey, feature, petKey?, token, quiet=true})` → `{ok}` / `{retryAfter}` | L66326 |
| Enclosures.CancelCare | RE | `FireServer(token)` | L65666 |
| Curbside.Accept | RE | `FireServer(car)` | L92565 |
| Curbside.Pack | RE | `FireServer(car, slotModel)` | L93218 |
| Curbside.Deliver | RE | `FireServer(car)` | L93223 |
| Pets.PurchaseCrate | RF | `InvokeServer(crateType, preferredEnclosure?)` → `{rolls}` | L209457 |
| Saves.RenameSlot | RF | `InvokeServer(slot, index, name: string)` | L234705 |
| Boxes.Report | RE | `FireServer({{k=boxKey, c=CFrame, g=gen}, ...})` — client-authoritative box CFrames | L189962 |

Checkout state machine (via `UI.CheckoutState` OnClientEvent): phases Scanning →
AwaitingPayment → CashChange | CardEntry → done. State fields: transactionId, phase,
itemLines[{sourceIndex, scanned, priceCents}], scanLines, changeDueCents, totalCents.
Non-playable care path: `if not result.playable then CompleteCare(token)` immediately —
the game's own no-minigame lane (L66079).

## 3. World model (runtime discovery)

- Plot: `workspace.Plots.<PlotN>` (OwnerUserId attr). Rich attrs: StoreOpen, DoorsLocked,
  OutOfStock, StoreDay, CustomersInside/Pending, StoreSignText, TimedCashierExpiresAt.
- Shelves: plot descendants, `isShelf` = SlotSize attr non-empty (ShelfRules); shelfKey =
  `ItemId` attr; slot parts have `SlotIndex` attr; assigned good = `AssignedGood` attr +
  GoodsSlotAssigned tag. Goods replica data: `getGoods().Shelves[shelfKey][tostring(i)] =
  {Good, Qty}` (client PlayerDataClient → replica).
- Goods catalogue: `ReplicatedStorage.Goods.{Food|Toys|Habitat}.{Small|Medium|Large}.<Item>`
  with BoxPrice/BoxQuantity attrs. SizeClass → market multiplier Small 1.5 / Medium 1.75 /
  Large 2.0 (ShelfRules.MARKET_MULTIPLIERS). Optimal price = `ShelfRules.optimalPriceOf(item)`
  = market × 1.4 (OPTIMAL_RATIO). Overprice → refuse chance (starts ×1.0, certain ×2.0) +
  shoplifter steal chance (starts ×1.4, caps 0.4).
- Till: plot model named "Checkout" with Foundation/PlayerPoint/PlayerCam/CustomerPoint +
  ScanMat descendant (TillRules). `MannedCheckout`/`StaffCheckout` attrs.
- Messes: plot models with `MessId` attribute (hold-prompt flow client-side).
- Enclosures: plot models with `AcceptsType` attr (AcceptsSpecies optional); maintenance
  attrs `MaintenanceFeatures` (comma list), `MaintenanceCondition_<F>` (0-100),
  `Need_<F>`; pets visual folder "Pets" children with `PetKey` attr. Features registry
  (EnclosureMaintenance.Features): Food/Play/Water/Tubes/Groom/Exercise/Glass/Filter/Heat;
  scope enclosure vs animal (Play/Groom/Exercise need petKey).
- Curbside cars: CollectionService tag "CurbsideCar" (CS:GetTagged).
- Boxes (goods): plot `Boxes` folder children, `BoxKey` + `Carrier` attrs; server Spawn
  event payload (key, plotName, ?, props, cframe, gen, stackerSeat, groundGap) — track
  key→gen for Report.
- Customers: CollectionService tag "CustomerNPC".

## 4. ESC — exploit surface beyond remotes (guide §26, first application)

- **26.1 Attributes**: `Cash` = PLAYER attribute (server-set; read by PlayerDataClient.getCash
  → useCanAfford gates ALL purchase buttons client-side). Local forge
  `LocalPlayer:SetAttribute("Cash", 1e9)` bypasses every client-side affordability gate
  (UI enablement) — wires still fire; server-side re-check unverifiable from client deobf.
  Plot attrs (StoreOpen/OutOfStock/StoreDay) are server-written state mirrors — read-only
  truth sources for loop gating. CheckoutTransactionId/CheckoutItemIndex on till children =
  server-set scan surface. CHECKED: no client-writable attribute feeds a server reward
  handler directly except the box Report path below.
- **26.2 Save system**: `Saves.{GetSlots,SwitchSlot,DeleteSlot,RenameSlot}` (4 slots).
  RenameSlot(slot, index, name) — client string → server persist (slot names shown in the
  save-select UI). If persisted verbatim without utf8.len validation → `\255` save-corruption
  → rollback primitive (guide §26.6 dupe shape). UNVERIFIABLE from client deobf (server-side
  sanitize unknown) — documented, not wired. PlayerData replica is server-authoritative
  (verified §1) — no client-mutable save payload found.
- **26.3 Mutable client-trusted tables**: ShelfRules (MARKET_MULTIPLIERS/OPTIMAL_RATIO) +
  CheckoutMoney.Denominations are client-required modules — read-only use for us (price
  computation). Local replica prediction writes exist (WriteLibs) but only mirror server
  state. CHECKED: no client-gated economy table worth mutating (all real gates server-side).
- **26.4 No-cooldown hooks**: order/checkout button gates are client-side (canAfford,
  interactionSuppressed w/ HoldingBat/Pamphlets attr reads) — bypassed by firing remotes
  directly (our standard play), no hookfunction needed. CHECKED: no client cooldown table
  gating a server-trusted action.
- **26.5 Numeric injection**: SetGoodPrice(goodKey, price) takes any client number (price
  UI steppers) — negative/NaN price = server-side validation question, polarity unknown.
  SubmitCashChange(counts)/SubmitCardAmount(cents) = client-computed money — the cashier
  register math. CHECKED as census; NOT wired (§5 filter: breakage > value for the core
  loop; user wants working autofarm first).
- **26.6 String/Instance injection**: RenameSlot name (above) + StoreSignText (plot attr,
  server-set via SetCustomization) — both documented. NOT wired (§26.2 same reason).
- **26.7 Ownership/replication**: **Boxes.Report is CLIENT-AUTHORITATIVE box CFrames** —
  server accepts `{k, c, g}` reports (throttled 0.05 studs, ≤60/report, gen-guarded) and
  updates box truth. Wired as the AutoStock accelerator: after PlaceGoods the box's server
  position follows ours — report boxes to the carry/destination position to skip walking
  them across the store. gen tracked from Boxes.Spawn OnClientEvent.
- **ESC verdict**: the game's core economy (cash, goods, prices) is server-authoritative
  with client gates; the ONE server-trusting client-value channel is Boxes.Report (wired,
  benign use = transport acceleration), the census negatives are recorded above.

## 5. Feature plan (Rule 11 filter applied)

KEEP (automation value):
1. **AutoStock** — order goods (OrderItem) for shelves with empty slots → PickUpBox →
   PlaceGoods(boxKey, shelfKey, slotIndex) → next box. Uses catalogue + shelf scan +
   replica goods state. The tycoon core loop.
2. **AutoCheckout** — BeginShift(till) → phase machine: Scanning (ScanCurrent per till
   child) → AcceptPresentedPayment → CashChange (greedy denomination counts for
   changeDueCents) / CardEntry (totalCents) → repeat until no transaction → EndShift.
   Money income automation.
3. **AutoClean** — TP to mess (MessId) → Mess.Clean({messId}).
4. **AutoPrice** — for each shelf-assigned good: SetGoodPrice(goodKey, optimalPriceOf(good))
   (game's own optimal ratio). Stock-rating helper.
5. **AutoNextDay** — on UI.DaySummary OnClientEvent → StartNextDay:FireServer().
6. **AutoPetCare** — enclosures with Need_<F> → BeginCare → (non-playable lane)
   CompleteCare(token); animal-scope features pick nearest needy pet PetKey.
7. **AutoCurbside** — CurbsideCar tagged cars: Accept → Pack(car, slotModel) → Deliver.

REMOVE (Rule 11): admin remotes (Admin.*), telemetry (Analytics.Track, Perf.Report,
Feedback.Opened), Monetization purchase-prep (ROBUX), Social UI one-shots (Invite/Respond/
Kick — UI does it), Codes.Redeem (one-shot UI), Rating.Like, Guides/Tutorial/UpdateLog
mark-seen, Settings toggles, NPC.Chatter, Staff dialogue (Converse), Pens decor ordering
(one-shot purchases, no loop), PawExpress/Showcase (one-shots), XpGained (server→client),
SocialReward/CheckIn claims (UI one-shots), Boxes.Attr/Pose/Despawn/Spawn (server→client).

Scope note: PurchaseGood (buy goods as a customer in OTHER stores? co-op visitor flow) —
visitor-economy lane, not the owner loop; NOT wired (documented). PurchaseCrate — pet
gambling purchase, one-shot UI action with reveal; NOT wired (no loop, cost-bearing).
ESC one-shot tools (price NaN, rename \255) NOT wired — §4 verdict.
