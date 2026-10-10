# VERIFICATION-M7 — Anti-tamper, watermarking, leak tools (session 1)

Owner: main-agent (module M7 claim 178d3ed). Session 1 scope per DECISIONS-M7
D-M7-10. Format follows doc §22.1: what actually ran, and the honest NOT-RUN
list.

## What ran (all in this session, 2026-10-10)

### Automated (bun test, Public/api tree)

- **Suite: 229/229** (212 baseline + 17 new in `test/m7.test.ts`), `tsc --noEmit` clean. The 212 baseline passing unchanged is itself the backward-compat proof for the CCP-M6 salt change (every existing auth test runs the no-`s` path against the new derivation).
- `test/m7.test.ts` coverage:
  - **CCP-M6 salt (D-M7-4)**: absent `s` → legacy salt, legacy client decrypts (byte-compat); present `s` (24B) → new salt, deriving client decrypts and reads `build_hash`; wrong `s` → AEAD open fails (per-fetch replay uselessness); `s` > 64 decoded bytes → signed BAD_REQUEST envelope.
  - **Tamper ingestion (D-M7-6)**: heartbeat with `tamper {check, detail}` records event `tamper` / `client:<check>:<detail>` while the response stays a normal KEY_VALID envelope; malformed tamper (no check) silently ignored (no event, still KEY_VALID); tamper on a revoked-key session still records BEFORE the kill check fires (dying-session signals survive).
  - **Leak workflow (D-M7-8)** — full chain through the REAL router: auth init (real X25519 handshake in the test client) → extraction from (a) the clean sealed payload_ref, (b) the same ref embedded in a messy multi-line log/JSON dump ("survives reformatting"), (c) a session token, (d) a raw watermark id; no-watermark input → 404 `no_watermark`; reseller token → 403; revoke chain: key revoked + hwid AND ip blacklist rows with `leak:<watermark>` reason + session `expires_at` killed + `admin.leak.revoke` audit row + `leak` event row — every side effect asserted against the DB; idempotency: second revoke reports `already_revoked`, no duplicate blacklist rows; `blacklist_hwid: false` skips exactly the hwid row.
  - **Abuse scores (D-M7-7)**: weights and math end-to-end — dirty key built via REAL heartbeats (2 client tamper reports) + real HWID churn (reset + rebind to a second device) + a server-side lockout event → tamper_7d=3, distinct_hwids_30d=2, churn=1, lockouts=1, score=19, band=watch; clean key (single legit binding) scores 0; ordering highest-first; reseller → 403.

### Browser (agent-browser, sandbox dashboard against the same router in-process)

- Full M7 demo chain on the REAL store: "Craft demo leak" (dev route: real admin-key mint + real auth-init handshake server-side, messy dump assembled) → paste → "Extract & correlate" → watermark recovered from the messy text via the sealed-ref class → key/session/identity cards + CLEAN score badge → "Run revoke chain" → confirm dialog (hwid/ip checkboxes) → revoked state + toast; Blacklist view shows the two `leak:<watermark>` rows; Audit view shows `admin.leak.revoke`.
- Cross-view trace: Sessions view watermark cells are copyable and carry a fingerprint button → jumps to Leak tools with the watermark prefilled (key-remount prefill) → extract works from the raw watermark id class.
- Users view Risk column renders the seed abuse demo as `WATCH · 18` with clean rows muted.
- Zero JS console errors across the walk.

## Honest NOT-RUN list

- **Real leaked dumps from production** — there is no production traffic; all artifacts were produced by the real handshake paths above. The extractor's free-text scan is tested against synthetic-but-messy input only.
- **Lua-side §11 checks (D-M7-5)** — the client module (native-identity over time, header-table injection detection, timing sanity, env consistency) is DESIGNED and pinned but not implemented this session; it needs the M6 runtime-template integration study (RUNTIME-M6 §1-4) to embed checks without becoming a detectable branch. Session 2.
- **Container-byte watermark carriers (D-M7-2/D-M7-9)** — const-pool order, junk patterns, identifier fragments are build-side (M5 owns the const-key chains and the build hash pins the runtime's decoy logic); filed as CCP-M7 to glm6. The extractor's container-class hooks land when BYTECODE-M5 vNext pins the format.
- **M3 client side of CCP-M6** — glm1 lands `handshake.lua` on the ruling notice (this document + DECISIONS D-M7-4 constitute the ACCEPT ruling; formula adopted verbatim).
- **Notify delivery** — `leak` events + audit rows are written for the M8 lane; the actual admin-channel Discord message is glm4's bot (their TASKS row lists `/leak lookup` as M7-dependent — the endpoints exist now).
- **Abuse-score weight tuning** — weights are pinned as v1 constants (D-M7-7); no calibration data exists (no production traffic).

## Bugs found + fixed during this session

1. **Command palette stale-query bug** (pre-existing, found in QA walk): reopening the palette via shortcut/header left the previous query in the input (Radix `onOpenChange(true)` only fires for user-driven opens, not prop-driven), so the filter went stale, Enter became a no-op, and navigation stranded. Fixed structurally: the parent keys the palette by an open-session counter, so every open remounts with a clean query (exit animations preserved — close does not bump). Toggle sequences and the exact repro (type → navigate → reopen) verified in-browser.
2. **Test-harness key-binding misconception** (test bug): assumed a key could bind multiple HWIDs in one session set; reality is one binding per key (HWID_MISMATCH deny). The abuse-score "distinct HWIDs" signal is legitimately produced by reset+rebind churn — test rewritten to drive real churn through `UPDATE ... hwid_hash = NULL` + a fresh handshake, matching the deployed semantics.
3. **Abuse-score double counting** (formula bug, caught by the test): lockout events are type `tamper` with detail `invalid-key-lockout`, so they counted in BOTH `tamper_7d` and `lockouts_7d`. Fixed: `tamper_7d` counts only `client:%` details.
4. **Abuse-score first-binding penalty** (formula bug, caught by the test): raw `COUNT(DISTINCT hwid_hash)` scored every normally-bound key +3. Fixed: churn = max(distinct − 1, 0); the response reports both raw and churn.
