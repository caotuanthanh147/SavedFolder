# VERIFICATION-M7 — session 2 addendum (Lua §11 checks module)

Owner: main-agent (module M7). Verification of the `loader/checks/env_checks.lua`
delivery against DECISIONS-M7-S2 (D-M7-11..18). Suite: `lua5.4
tests/m7_checks_test.lua` from the repo root + `luac5.4 -p` parse gate +
glm1's M3 suite regression + the M11 dashboard browser QA.

## §22.1 transcript-equivalent evidence

| # | Claim (decision) | Verification | Result |
|---|---|---|---|
| 1 | Factory-chunk module, Lua 5.1-syntax (D-M7-12) | `luac5.4 -p loader/checks/env_checks.lua` | PARSE OK (RUNTIME-M6 §1 gate style) |
| 2 | Clean run reports nothing (D-M7-13) | `m7_checks_test.lua` "clean run has 0 failures" + digest 64-hex | PASS |
| 3 | Identity-over-time detects post-baseline swaps (D-M7-13a) | `_G.loadstring` replaced after capture → `identity.changed/loadstring`, exactly 1 failure; restored global + re-run → 0 (read-once proven) | PASS |
| 4 | Late UNC-global install detected | `_G.hookfunction = fn` after capture → `identity.changed/hookfunction` | PASS |
| 5 | Active-swapping double-catch (capture-time) | `setmetatable(_G, {__index = fresh-closure})` before capture → baseline anomaly surfaced by `run()` as `identity.changed` | PASS |
| 6 | Header teach-then-diff (D-M7-13b/D-M7-14) | executor header on every call → taught, never a failure; unknown `X-Spy-Trace` on call 3 → `headers.injected` | PASS |
| 7 | SDK-header rewrite detected | mid-call `x-proof` overwrite → `headers.modified` | PASS |
| 8 | Header recasing is NOT a signal (legit executor variance) | `x-lv` → `X-LV` same value → 0 failures | PASS |
| 9 | Header dedup within window + read-once across runs | 3 spy calls → exactly 1 `headers.injected` row; second `run()` → 0 | PASS |
| 10 | Timing ≥20× threshold (D-M7-13c) | fake clock 100× baseline → `timing.inflated`; 19× → passes | PASS |
| 11 | Env consistency (D-M7-13d) | `_G.syn` table appearing late → `env.changed/syn`; `identify_executor()` returning a different string → `env.changed/executor` | PASS |
| 12 | Digest determinism + sensitivity (D-M7-17) | two instances, same env → identical digest; `loadstring` swapped before capture → different digest | PASS |
| 13 | Report wire = D-M7-6/D-M7-15 | mock server: path `/auth/<sid>/heartbeat`, body `{v:1, session_token, tamper:{check,detail}}`, `x-proof` recomputed with the library.lua formula matches, `x-lv` present, delivered=true on 200 | PASS |
| 14 | Report silence | server 500 → delivered=false, no raise, the call was still made; empty session_token → no-op, zero requests | PASS |
| 15 | Degrade paths (D-M7-12) | no `Env.request`: capture/run work, report returns false | PASS |
| 16 | §11 module silence | print-counting stub across the whole suite → 0 module prints | PASS |
| 17 | run() before capture | no baseline → only header failures (none) → `{}`; digest `""` | PASS |
| 18 | glm1-owned files untouched | `git status` in Public: only `loader/checks/` (new), `tests/m7_checks_test.lua` (new), dashboard tree + VERIFICATION/README files | PASS |
| 19 | M3 suite regression | `lua5.4 tests/run.lua` → 95 passed, 0 failed | PASS |
| 20 | api/ suite regression (server side untouched) | `bun test` in Public/api → 229 pass / 0 fail | PASS |
| 21 | Dashboard §11 pipeline demo (D-M7-6 end-to-end) | browser: Leak tools → §11 card → fire `headers.injected` → heartbeat answered `KEY_VALID` (silent), `tamper_event_recorded=true`; "Correlate in extractor" → lookup shows `tamper client:headers.injected:demo:x-spy-trace` event + abuse-score badge `clean · 5` (1 tamper × weight 5, D-M7-7) | PASS |
| 22 | Demo repeatability regression FIXED | root cause: the previous session's revoke-chain demo had blacklisted the shared demo IP (198.51.100.77), breaking every later mint+init (KEY_BLACKLISTED) — craft-leak-artifact was already broken before this session's changes; fix = fresh TEST-NET-2 ip + hwid per demo invocation in BOTH dev routes | PASS (curl 200 + full JSON; craft route restored) |

## Dashboard QA this session (regression sweep)

13/13 views render with data; palette open/typed-nav/reopen-empty (stale-query
fix intact — note: synthetic `.value` assignment does not penetrate React
controlled inputs; use real keystrokes); Ctrl+K opens; webhook chain signed
200 + key issued / tampered 400 (inner-status propagation intact); inspector
log + error badge; dark-mode class + computed bg; sticky theads pinned at
scrollTop 300; zero console errors after full sweep. New: print command in
palette → PDF via headless print pipeline (letterhead + timestamp, header/
nav/footer/toasts hidden, scroll containers expanded, rows unbroken across
pages — verified via pdftotext/pdfinfo text extraction); Sessions + Blacklist
CSV export buttons; tabular-nums on all table cells (font-variant-numeric
verified computed).

## NOT-RUN / honest limits

- No real-executor run (sandbox has none) — UNC behavior validated via mocks
  and feature-detection discipline only (RESEARCH-M7-S2 limits).
- Print pipeline verified via Chromium headless PDF (agent-browser `pdf`);
  physical printers / Safari print quirks not exercised.
- Container-byte watermark carriers remain CCP-M7 (glm6; no ruling msgs as
  of this session — re-checked before delivery).
