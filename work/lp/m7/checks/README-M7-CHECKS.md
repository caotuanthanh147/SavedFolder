# M7 §11 checks module — `loader/checks/env_checks.lua`

Owner: main-agent (module M7, session 2). Status: **pinned, v1**.

The client-side §11 environment/integrity checks: identity-over-time on the
pinned critical-function set, §1.2.9 header-table instrumentation watch,
timing sanity vs a per-machine baseline, and environment self-consistency.
All checks are **signals, never verdicts** (doc §11): failures are reported
to the server as `tamper` events on the heartbeat (D-M7-6) and the caller
loads nothing — silently, with no explanatory message.

Design pins live in `SavedFolder/work/lp/m7/DECISIONS-M7-S2.md`
(D-M7-11..18); evidence in `RESEARCH-M7-S2.md`. Tests:
`tests/m7_checks_test.lua` (lua5.4, 40 checks) + `luac5.4 -p` parse gate.

## API

```lua
-- M3 loader style: the factory chunk binds Crypto + Env.
local Checks = assert(loadfile("loader/checks/env_checks.lua"))(Crypto, Env)

local checks = Checks.new({
        script_id = "<32-hex>",
        base_url = "https://api.example.com",  -- no trailing slash
        proof_key = "<per-script proof key>",  -- same key as the SDK
        lv = "<loader version string>",
})

checks:capture()   -- once, at init start (before the first request)
-- ... SDK/handshake calls run normally here ...
local failures = checks:run()   -- before payload fetch / runtime entry
if #failures > 0 then
        checks:report(session_token, failures[1])  -- first, pinned order
        return nil  -- silent no-load: NO message, NO error text (§11)
end
```

- **`Checks.new`** immediately wraps `Env.request` with the header watch.
  Every module built on the SAME Env table afterwards (the SDK, the
  handshake) is instrumented automatically — no other wiring.
- **`capture()`** — baseline: function identities (double-captured; active
  swapping during capture is itself recorded), environment fields
  (executor identity, version, `syn` presence), timing median of 9 samples
  of sha256 over a fixed 64-byte work unit. Idempotent.
- **`run()`** — re-captures and compares; merges header failures observed
  since the last `run()`. Read-once: a second `run()` starts a fresh
  window. Returns `{ {check=..., detail=...}, ... }`. Never raises, never
  prints. Without a prior `capture()`, only header failures are reported
  (no baseline = no comparison; a check that cannot run is not a signal).
- **`digest()`** — sha256 hex over the sorted baseline identity lines.
  Deterministic per environment. For decoy-path variation and tamper
  detail. **Not** a key-derivation input: the server cannot recompute a
  client environment digest, and a transmitted one is forgeable (doc §3).
  The §11 "integrity checksums feed key derivation" requirement (§10.2
  item 9) is implemented at the container level by M6 (RUNTIME-M6 §4).
- **`report(session_token, failure)`** — POST `/auth/<script_id>/heartbeat`
  `{v:1, session_token, tamper:{check, detail}}` with the same proof-header
  formula as `loader/sdk/library.lua`. Response read only for transport
  success; never acted on (§11 silence). `false` when no session token
  (the server wire requires one) or no `Env.request`.

## Check names (failure `check` values)

| check | fires when |
|---|---|
| `identity.changed` | a pinned critical function's object identity differs from baseline (post-baseline hooking / `newcclosure` re-wrap / late UNC-global install / active swap during capture) |
| `env.changed` | executor identity, version, or `syn` presence differs from baseline |
| `headers.injected` | a request completed with a post-call header-table addition outside the taught executor set |
| `headers.modified` | an SDK-set header was removed or its value changed mid-call |
| `timing.inflated` | median work-unit time ≥ 20× the baseline median (single-stepping / debug-hook overhead) |

## Integration contract (for M3/M13 owners)

The stub→init handoff (D-M13-6) already gives the init everything needed:
`entry(payload)` with `{api, script_id, build, t, s, r}`. Recommended init
flow (msg'd to glm1/M13 owner):

1. Build `Env` (M3 `env_executor.lua`), `Crypto` (M3 `loader/crypto`).
2. `checks = Checks.new(...)` — wraps `Env.request`.
3. `checks:capture()`.
4. Run the handshake (`sync` teaches the executor's header-injection set on
   its first completed call; `init`/`payload` run under the watch).
5. `failures = checks:run()` — before fetching the payload / entering the
   VM runtime. On failure: `checks:report(session.session_token,
   failures[1])`, then return generic failure (no explanatory text).
6. On success, `checks:digest()` may vary decoy-path selection.

## Honest limits (NOT-RUN / by design)

- No real-executor validation yet (fleet sandbox has no Roblox executor);
  UNC variance handled by feature detection + self-over-time comparison.
- A spy installed BEFORE `Checks.new` with consistent behavior defeats the
  identity/env checks by construction — the backstop is server-side
  correlation (abuse scores, D-M7-7), per doc §3 "client code is never
  trusted". Timing and header checks still apply.
- Timing uses `Env.clock` when present, else `os.clock`; without a
  sub-second clock the timing check degrades to off (not a signal).
- Container-byte watermark carriers remain CCP-M7 (glm6) — not in v1.
