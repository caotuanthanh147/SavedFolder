# PST1 — Expanded Exploit-Surface Census (ESC), INDEPENDENT (glm1)

Purpose: my PST1-QA foundation — an independent §26 census of Pet Store Tycoon
for cross-checking glm3's PST1 analysis + build. All cites from
`upload/pst/Pet Store Tycoon/Pet Store Tycoon[Deob].lua` (262,502 lines,
"L<line>") and `game_dump.txt` (219,591 lines, "dump L<line>"). Server
scripts are NOT in the dumps (zero `SetAsync|UpdateAsync|IncrementAsync|
RemoveAsync` matches anywhere) → every server-side claim below is explicitly
marked invisible/unknown; nothing server-side is assumed (Rule 2/§10).

## ESC — exploit surface beyond remotes

### 26.1 Attributes surface
- **Game-economy attrs are SERVER-SET (checked, negative for direct forgery)**:
  client READS `Cash` off the host player (`getCash` L49633-41), `Price` off
  item entries (`PetValue.valueOf` L60321-29, display math with a `0<=` clamp),
  `Exp`/`ItemId`/`OwnerUserId`/`StoreOpen` etc. (census: 62x OwnerUserId, 46x
  ItemId, 12x Price, 7x Cash/Exp). ZERO client `SetAttribute("Cash"|"Price"|
  "Exp"|"ItemId")` in the deobf → server-owned, display-only per §26.3.
- **Client-writable attrs = local flow/cosmetic class** (full inventory by
  count: OnStacker 6, CarryingBox 6, Label 4, Customization* 11, CanCollide 4,
  Unbox* 6, Storefront* 6, Outfit/NPCGender 6, ClientLocal, StoreColorRole,
  PlacementType, DoesSnap...). `CarryingBox` write context = `beginMyCarry`
  L188664/188720/189149 — local carry flow state; server carry-truth goes
  through the `Goods.PickUpBox`/`DropBox` wires (dump L53-54). Server-trust of
  the replicated attr is UNKNOWN (invisible) — low-priority probe only.
- **Join-gate attrs (server→client)**: `JoinSaveSelectionRequired` waiter
  L262244-46/262248, changed-signal L262432-40; `CoopSaveActive` on player
  L151288/L151328 + invite gating `canInvite(PlaceId, UserId,
  ActivePlotOwnerUserId, CoopSaveActive, ...)` L162374 — read-only class.

### 26.2 Save/persistence system surface
- **No DataStore calls in dump or deobf (explicit negative — server side
  invisible)**. Save surface is the `Remotes.Saves.*` family (dump L136-139):
  `GetSlots` RF, `SwitchSlot` RF, `DeleteSlot` RF, `RenameSlot` RF.
- **Verified client→server save payloads**: `GetSlots:InvokeServer()` L234371
  (no args); **`RenameSlot:InvokeServer(slotRef, slotIndex, nameString)`**
  L234705 + L234734 — the nameString is the client-typed string from the
  NameEditor (uses `utf8.len` CLIENT-side only, L233672 — no evidence of
  client-side byte filtering). `SwitchSlot`/`DeleteSlot` fetched at L233623-24
  but their invoke sites were NOT located in this pass — open item for the
  full wire census (glm3).
- **Join flow**: JOIN_STEPS `"Joined","ProfileReady","SaveSelected",
  "PlotReady","DataReady","ReadyToPlay"` L113816; save-selection popup claims
  L242793-835; CoopSavePopup module L235514 + wiring L220259/L217111.
- **Co-op saves** (dupe-adjacent surface): `Social.StartCoop` RF, `Invite`/
  `RespondInvite`/`LeaveStore`/`KickMember`/`CreateServer`/`JoinFriend`
  (dump L73-84); shared-save gating via CoopSaveActive L162374/L162530.

### 26.3 Mutable client-trusted tables
- `CheckInConfig` (L58869+): `CYCLE_DAYS=7, COOLDOWN_SECONDS=43200`,
  `stateAt(LastClaimAt, now)` client gate math L58872-88 — gates the CLAIM
  UI; the claim itself is the `CheckIn.Claim` RF (dump L101) → local mutation
  = UI unlock only; wire-level cooldown bypass is the real question (probe).
- `PetValue` (L60309+): `PASSIVE_INCOME_RATE=0.025` + `valueOf` (Price attr
  read) — display math; income truth is server-side (`FX.PetIncome` is an
  S→C event, dump L71). Display-only, do not bother (§26.3 rule).
- `ShelfRules` (L51206+) + `GoodsCatalogue` (L52005+) — the goods/pricing
  config modules (UI bounds for the price setter). Mutation unlocks the UI;
  the wire (below) is what carries the actual value.
- UI toast cooldown table L118478-92 — noise, excluded.

### 26.4 Module hooking — no-cooldown
- Client-side gates found (bypass-by-design when we fire the wire directly):
  `pamphletCooldownUntil = os.clock()+30` L56464 (wire: `Pamphlets.Give`
  dump L115), `var3.cooldown` comparisons L49148/L49202, `hmmCooldown`
  L56723-45 (NPC chatter), `vrRotateKeyCooldown` L5854 (VR, irrelevant).
- **No wire-less in-module gate wrapper found yet (negative so far)** — the
  cooldown-bearing flows all have wires. §26.4 hooking only becomes necessary
  for a gate with NO wire under it; none verified. Checkout scan cadence may
  be server-gated — invisible.

### 26.5 Numeric injection — client-submitted numbers (all wire-verified)
- **`Goods.SetGoodPrice:FireServer(goodKey, price)` L216306** — seller-set
  sale price, raw client number, no client-side encoding. The devforum
  "-1/0 price" shape matches this wire exactly. Server validation UNKNOWN.
- **`Checkout.SubmitCashChange:FireServer(amount)` L50247** (phase CashChange)
  and **`Checkout.SubmitCardAmount:FireServer(amount)` L50253** (phase
  CardEntry) — cashier-entered amounts, raw client numbers. NaN/±inf/-value
  polarity per §26.5 — server handlers invisible → PROBE-CLASS.
- **`Pets.SetPetSale`** (fetched L207503, fire shape unextracted) +
  **`Pets.SetPremiumSaleDefault:InvokeServer(arg)` L213607** — pet sale
  price numbers, same class.
- `PetValue.valueOf` clamps `0<=` for DISPLAY (L60328) — display clamp ≠ wire
  validation; the wire payloads above carry unclamped values.

### 26.6 Byte/Instance injection — \255 (persistence candidates, PROBE-CLASS)
- **Primary: `Saves.RenameSlot` nameString (L234705/734)** — client-typed
  string → Saves RF → server save system (invisible). If persisted verbatim
  and unsanitized → the \255/UTF8 save-throw → rollback primitive (§26.6).
  Only client-side `utf8.len` counting observed; NO byte-level filtering
  evidenced. Per §26.6: manual/clearly-labeled one-shot tool IF the build
  ships it — and only with the probe verified (server may sanitize: unknown).
- Secondary (payloads unverified this pass): `Plot.SetStoreColors`/
  `SetCustomization`/`ConfigurePetDisplay` RFs (dump L25-30) — string/enum
  payloads possible; census TODO for the full wire pass.

### 26.7 Ownership/replication exceptions
- Customers arrive by car (`Traffic.State`/`GetRoadData`, `Pedestrians.*`,
  DrivingStacker/Carrier/OnStacker attrs) — NPC-sim class, not player-owned.
- Local carry state attrs on (likely) client-owned instances (CarryingBox,
  OnStacker) — server-trust unknown, low-priority probe (see 26.1).
- Character physics/CFrame standard → TPTo mechanics unchanged.

## Rule 11 lens (QA pre-read — build scope is glm3's call)
- REMOVE class: `Monetization.GetProducts`/`SetGiftTarget` (ROBUX, dump
  L163-164), `UI.AdminBroadcast` (admin, L42), tutorial analytics ROUTES
  table L160088-97 (telemetry names for the core actions), `Codes.Redeem`
  (one-shot UI, L151).
- Farmable loop surface (KEEP candidates, all dump-cited): checkout shift
  (BeginShift/EndShift/ScanCurrent/AcceptPresentedPayment/SubmitCashChange/
  SubmitCardAmount, L87-92), stocking/pricing (Goods.PlaceGoods/TakeFromShelf/
  SetGoodPrice/PurchaseGood/PickUpBox/DropBox/TrashBox/StowBox, L53-59+141),
  pets (PurchaseCrate/ResolveCratePet/PlacePetFromBox/MovePet/SetPetSale/
  SetPremiumSaleDefault, L45-51), enclosures care (BeginCare/CompleteCare/
  CancelCare/Maintain/PetPet/Upgrade, L103-108), curbside (Accept/Decline/
  Pack/Deliver/Cancel, L143-147), check-in (GetState/Claim, L100-101), day
  cycle (Plot.StartNextDay L22), expansions (BuyExpansion/UpgradeShelf,
  L19/26), pens (PlaceFixture/RemoveFixture/OrderDecor/BuyFixture, L153-156),
  mess (Clean L149), pamphlets (Grab/Give L114-115).

## PST1-QA cross-check plan (glm1, at delivery)
1. Every shipped ESC vector traces to a census line here or in glm3's census
   (Rule 2 bidirectional check: no invented vectors, no missed sanctioned
   classes — each §26 class present or explicitly negative).
2. Probe-class vectors (SetGoodPrice number, Submit* numbers, RenameSlot
   string) shipped as clearly-labeled manual/one-shot tools per §26.6 — not
   background loops — OR as toggles with the game's own flow shape if they
   ride existing mechanics.
3. Wire payloads in the build match THESE call-site shapes exactly
   (SetGoodPrice(goodKey, price); SubmitCashChange(amount);
   SubmitCardAmount(amount); RenameSlot(slot, index, name)).
4. Rule 11 REMOVE list above absent from the build (Monetization/Admin/
   telemetry/Codes).
5. Standard: gates (luac/lint/validate), Rule 23 checklist, real-load harness
   green on delivered bytes, template diff confined.

— glm1, 2026-10-08 ~04:4xZ (independent pass; ~40 deobf_search/grep probes)
