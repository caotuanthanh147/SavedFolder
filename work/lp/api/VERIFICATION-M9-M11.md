# VERIFICATION-M9-M11 — §22.1 transcript

Author: main-agent. Date: 2026-10-10. Environment: sandbox (bun 1.3.14, node 24.21.0, next 16.4.0). All commands run in the delivered working tree.

## Module M9 (free-key flow) — tests

Command: `cd api && bun test` (full suite incl. M1 regression)

```
163 pass
 0 fail
764 expect() calls
Ran 163 tests across 13 files. [6.93s]
```

New M9/M11 test files (external-source derivation):
- `test/freekey.test.ts` — 15 tests; oracle = doc.md §14 clauses (each §14.3/§14.5 verification rule maps to a test) + cross-module check via the REAL `handleCheckKey` (the claimed free key validates KEY_VALID through M1's handler).
- `test/totp.test.ts` — 11 tests; oracle = RFC 6238 Appendix B Table 1 official vectors (8-digit SHA1, T=59/1111111109/1111111111/1234567890/2000000000/20000000000) + RFC 4648 base32.

Covered failure paths: token replay, skipped steps, fast completion (< min_seconds), wrong step secret, cooldown re-entry (same fingerprint), multi-account (same IP, different HWID → distinct fingerprints allowed, identical fingerprint blocked), IP-switch mid-flow (fingerprint mismatch), double claim, unknown slug, per-IP start limit (6th start in a minute), malformed checkpoint config (SERVER_ERROR), timing-mode provider link, envelope x-sig verification on /free responses.

NOT-RUN list (honest limits): real Linkvertise/Lootlabs server-side verification (needs creator accounts — owner-only); real Workers deployment; real Discord OAuth exchange (needs app credentials — routes are wired and state-checked, runtime-gated); load numbers.

## Typecheck

Command: `cd api && bunx tsc --noEmit` (excludes index.ts/durable.ts, Workers-only types, unchanged from M1)

```
(no output — exit 0)
```

## Module M11 (dashboard) — lint + runtime

Command: `cd <sandbox root> && bun run lint`

```
$ eslint
(exit 0)
```

Command: `bun run dev` (next dev, Turbopack) + curl/browser session:

```
GET /                     → 200 (page renders: shell, nav, footer)
GET /api/dash/info        → 200 {dev_mode, project, free limits}
GET /api/gw/sync          → 200 {"st":…,"nodes":[…],"colo":"DASH"}          (real M1 endpoint)
GET /api/gw/admin/analytics/overview → 200 {keys_active:4,…}               (real M1 endpoint)
GET /api/gw/admin/keys    → 200 rows[…]                                    (CCP-2 endpoint)
GET /api/gw/admin/scripts → 200 rows[…] (versions, game routing)
GET /api/gw/admin/audit   → 200 entries[…]
POST /api/gw/free/start   → 200 KEY_VALID {token, step 1/2, url with embedded secret}
POST /api/gw/free/step    → 200 KEY_VALID (after 8s min time) / BAD_REQUEST (before min time — bypass logged)
POST /api/gw/free/claim   → 200 KEY_VALID {key: YURI-…, tier: free}
POST /api/dash/validate-key → 200 KEY_VALID "The provided key is valid."   (real check_key round trip, server-signed proof)
```

Browser (agent-browser) end-to-end session on /:
- Overview renders live analytics cards, node list, protocol versions.
- Keys: 5 seeded rows render; "Create keys" dialog → 3 keys created → plaintext shown once (`3 plaintext keys: YURI-GFMAQ-…`); validate widget POST /api/dash/validate-key → 200 (network log).
- Free-key flow: start → early completion attempt rejected (server min-time) → real completion after timer → checkpoint 2 → claim → `CLAIMED: YURI-NRCKH-ZQZ44-SLGOO-ONBXW-FAMOQF`.
- Audit log: `free-flow claim audited ✓` (create_key action with free-flow actor visible).
- Settings: TOTP enroll → secret + otpauth URI displayed; dev admin token visible only in dev mode.
- Screenshots: /tmp/dash-final.png, /tmp/dash-validate.png (session artifacts).

Sandbox reaper caveat (environmental, not app): the sandbox kills the dev server BETWEEN tool invocations, so browser flows were verified in single-invocation batches; each batch restarted the server. Within every batch the app behaved deterministically.

## Commands to reproduce

```
cd api && bun test && bunx tsc --noEmit
cd dashboard && bun install && bun run lint && bun run dev
# then: open http://localhost:3000/ — Overview renders; Keys create;
# Free-key flow: Start → wait timer → Complete ×2 → Claim → validate the key in Keys.
```

## M11 session 3 (polish & power round) — verification addendum

Scope: dashboard UX/features only — zero api/ code changes (suite baseline unchanged, 212/212 from M10 session).

New in this session:
- Dark mode via next-themes (class strategy, system default, CSS-only icon swap — no hydration state).
- Command palette (Ctrl/Cmd+K): all 12 views + theme action; arrow-key navigation, Enter to run, filters as you type.
- Overview charts (hand-rolled SVG, zero chart deps): 14-day stacked activity bar chart bucketed client-side from GET /admin/audit?limit=200 (series: keys/payments/free flow/security, hover tooltips), tier-distribution donut from /admin/keys, sparklines per stat card, validation-health meter.
- CSV export (RFC 4180 escaping, BOM for Excel): Keys (current filters), Audit (current filters), Payments orders.
- Key detail dialog: click any key row → full field set + inline revoke/reset-hwid actions.
- Toast feedback (sonner) on every mutation: key create/revoke/reset-hwid, product save, webhook sim outcome, reconcile verdict, CSV exports, clipboard copies.
- Styling: shimmer skeleton loaders, view transition animation, pulse-dot live indicators, gradient stat-card headers, tier/status dot badges, empty states with icons, custom scrollbars, focus-visible rings, reduced-motion support, copy-to-clipboard on key ids.
- New UI primitives: tooltip.tsx (self-contained TooltipProvider wrapper — fixes Radix "must be used within TooltipProvider"), kbd.tsx.
- Demo-seed enrichment (idempotent, actor marker "seed-history"): ~77 audit rows across 14 days, 41 ok/5 fail/1 tamper events in the 24h window, 8 extra keys spread across tiers/days — makes the charts render data on first load.

Lint: 0 problems. React-hooks purity ruleset clean (no setState-in-effect, no Date.now() in render — chart "now" = server /sync timestamp).

Browser verification (agent-browser, self-healing batches):
- All 12 views render with data; navigation exercised THROUGH the command palette itself (12/12 palette navigations correct).
- Theme toggle: html.dark class flips, computed bg/fg verified (near-black bg / near-white fg / 10%-white borders in dark).
- Palette: "paym"+Enter → Payments; "keys"+Enter → Keys; "audit"+Enter → Audit log.
- Key detail dialog: row click → full dialog (id, tier, status, note, hwid, discord, roblox, created/expires/first/last use, created_by).
- CSV export: toast "CSV exported — 9 key rows (current filters)".
- Create key: toast "Created 1 key" + plaintext-once card.
- Webhook simulator regression (real M10 chain): signed → HTTP 200 (issued) toast; tampered → HTTP 400 (invalid_signature) toast.
- Console after fixes: zero errors (the two early "Module not found kbd/tooltip" entries were mid-session HMR noise, absent on fresh load).

Bugs found and fixed this session:
1. Radix tooltip without provider crashed the whole app (white screen, "This page couldn't load") — fixed by making the ui/tooltip.tsx Tooltip self-contained (wraps its own TooltipProvider).
2. React-hooks purity: mounted-state pattern in ThemeToggle → replaced with CSS dark:/hidden icon swap; palette state resets moved from useEffect into the onOpenChange handler; Overview Date.now() → server sync.st.
3. Seed enrichment race: initial fire-and-forget async IIFE in the sync seed function → converted to awaited loop.

NOT-RUN (honest list): keyboard-only a11y walkthrough beyond palette nav; mobile-viewport pass (nav collapse manually checked only); CSV re-import round-trip; long-poll under load.

## M11 session 4 (observability round) — verification addendum

Scope: dashboard UX/observability. api/ module code untouched; one dashboard-owned route changed (simulate-webhook propagates the inner webhook HTTP status — the dash harness route, not module code). Suite baseline unchanged.

QA-found bugs fixed this session (browser-verified before/after):
1. Command palette matching: "freekey" could not find "Free-key flow" (plain substring vs hyphenated labels) → normalized matching (strip non-alphanumerics from query and haystack). Walk went 10/12 → 12/12.
2. ScrollArea never constrained height (pre-existing since first delivery): root max-h-96 resolved but viewport height:100% → auto (percentage heights don't resolve against max-height parents) → tables rendered full-height and the page scrolled instead. Fixed: viewport gets max-h-[inherit]; root gets overflow-hidden.
3. Table's own overflow-x-auto wrapper was the nearest scroll container, defeating sticky theads → wrapper de-scrolled (views own the scroll div now: max-h-* overflow-auto). Sticky thead verified: scrollTop=300/3429, clientHeight=384, thead offset 0.0px (pinned).
4. Tampered webhook simulator masked its inner 400 as HTTP 200 in the request log → dash route now propagates the inner status; inspector entry reads POST /api/dash/simulate-webhook 400 and the header error badge shows 1.

New features:
- Live API request inspector (⌘I / Ctrl+I, header button, palette command "Open API request inspector"): right slide-over with per-request method/path/status/latency/age, live stats strip (logged/ok/errors/avg), hide-GET-polls filter, clear, cap 80, in-flight footer. ALL dashboard→server traffic instrumented (gw() + dash routes: validate-key, simulate-webhook, totp, info).
- Top progress bar while requests are in flight (gradient sweep, reduced-motion safe).
- Users view: row click → user detail dialog (identity stats + "Their keys" list with tier/status badges; client-side join so roblox identities resolve too — server-side q only matches discord).
- Shared badge atoms (badges.tsx) for tier/status reused across Keys + Users.

Styling: sticky table headers with inset border shadow + uppercase micro-label column heads across all 9 table views; Payments tabs switched to the animated line-variant underline; tables now truly scroll internally (max-h respected) with pinned headers.

Browser verification: 12/12 palette walk (incl. previously-broken freekey/nodes); user dialog (identity 203040 → 2 keys, 42 execs, key list renders); inspector (61+ entries live, stats strip, filter → 0 shown for all-GET log, error badge after tampered webhook); sticky header math above; console clean after fresh reload (HMR reload warnings during edits only).

NOT-RUN: real keyboard a11y audit beyond palette/inspector shortcuts; inspector under >80 rapid requests (ring cap logic unit-reasoned, not stress-tested).

## M11 session 5 (M7 leak-tools round) — verification addendum

Scope: dashboard M7 surface (Leak tools view + Users Risk column + Sessions trace) driving the REAL M7 endpoints (module code in api/src/leak.ts + auth.ts changes per DECISIONS-M7). api suite 212→229 (test/m7.test.ts, all green); tsc clean; lint 0.

QA-found bugs fixed this session (browser-verified before/after):
1. Command palette stale query (pre-existing, real user-facing bug): reopening via Ctrl/⌘-K or the header button left the previous query in the input — Radix onOpenChange(true) never fires for prop-driven opens, so the reset never ran; the accumulated filter made Enter a no-op and stranded navigation (repro: type "keys", Enter, reopen — input still read "keys"). Fixed structurally: parent keys the palette by an open-session counter so every open remounts with clean state (close does not bump → exit animations preserved). Verified: type→navigate→reopen shows empty input; 13/13 palette walk; toggle-close/reopen cycles.
2. react-hooks/set-state-in-effect blocked the naive reset-in-effect fix → the session-key remount pattern is the lint-clean structural fix (same pattern reused for the leak-trace prefill).

New features:
- Leak tools view (doc §16 page list now complete): tolerant-artifact textarea → POST /admin/leak/lookup → extraction-source badge + watermark card (copy) + key card (tier/status/identity/note/expiry/revoke state) + score badge + sessions table + recent events; "Run revoke chain" behind a confirmation dialog with hwid/ip checkboxes + false-positive warning; executed-state alert; idempotency surfaced.
- "Craft demo leak (real handshake)" dev route: mints a key through the REAL admin API + runs a REAL auth-init handshake server-side (X25519+HKDF+AEAD client in the route) → returns a deliberately messy dump so the free-text extraction class is proven in-browser end to end.
- Users view Risk column: /admin/abuse-scores joined through the key list per identity (worst active key band; clean rows muted). User detail dialog gains a per-key Risk column.
- Sessions view: watermark cells copyable + fingerprint trace button → jumps to Leak tools with the watermark prefilled (key-remount prefill, no set-state-from-props).
- Audit view: admin.leak.* actions render a distinct fingerprint destructive badge.
- seedAbuseDemo: idempotent seed (own marker) — active key with 3 client tamper reports + HWID churn → WATCH · 18 renders on first load.

Browser verification: craft → extract (messy text, sealed-ref class) → revoke chain (dialog → confirm → revoked + toast) → Blacklist view shows both leak:<watermark> rows → Audit shows admin.leak.revoke; trace flow Sessions→Leak tools prefilled→extract (watermark-id class) → revoked key card; Users WATCH · 18 row; zero JS errors; 13/13 palette walk; webhook chain regression still signed-200/tampered-400; sticky headers still pinned (thTopVsScroller 0 at scrollTop 300); CSV export still toasts.

NOT-RUN: real keyboard a11y audit beyond the palette/inspector/trace shortcuts; leak workflow against a production-sized sessions table (limit 200 on abuse-scores, top-N on lookup sessions list — indexed queries, but no load test).
