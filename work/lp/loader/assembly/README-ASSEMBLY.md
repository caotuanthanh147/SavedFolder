# loader/assembly — M3 session 3: the assembled init build generator

Owner: glm1 (module M3). doc.md §8 steps 6–10, §13 layer table,
D-M13-6 (stub→init entry contract), README-M7-CHECKS.md (checks mount),
RUNTIME-M6 v1.1 (containerless runtime + entry `b`/`c`/`s`).

## What it builds

`assembleInit({ runtimeSource, config, loaderRoot })` → ONE self-contained
init source. The chunk returns the **stub entry fn** (D-M13-6):

```lua
local entry = (loadstring or load)(init_bytes, "=lp-init")()
entry({ api, script_id, build, t, s, r })   -- the stub's payload
```

Spliced inside (all as escaped long-string literals, instantiated in the
loader's factory-chunk convention — `chunk()` → factory → factory(deps)):

| piece | source | lane |
|---|---|---|
| crypto bundle (11 modules) | `loader/crypto/*.lua` | M3 |
| executor env (feature-detected) | `loader/sdk/env_executor.lua` | M3 (+`Env.clock`) |
| §11 checks | `loader/checks/env_checks.lua` | M7 |
| handshake client | `loader/init/handshake.lua` | M3 |
| entry glue (the flow) | `loader/init/entry.lua` | M3 s3 (new) |
| VM runtime | M6 emitted source, **containerless mode** | M6 v1.1 |

Baked per-script config: `script_id`, `base_url` (fallback), `proof_key`
(raw bytes — M1's spam filter, not a trust anchor), `verify_pk` (public
Ed25519 key), `lv`, `key_path`. Per doc §13 the init is PUBLIC STATIC
content: no script code, no session secrets — the constKey NEVER lands
in the build (it arrives per session via the M1 payload wire).

## The entry flow (entry.lua)

1. `Env = env_factory()` — request/json/random/clock/file feature-detected
   from the host. No request ⇒ silent generic failure.
2. `Checks.new({...})` (M7) — wraps `Env.request`; everything after is
   instrumented. `checks:capture()` before the first request.
3. Handshake `sync()` (time offset + node list) — the first completed
   call teaches the executor's header-injection set.
4. `hs.init(key, place, game, user)` — key from the **SDK key cache
   file** (`lp/<script_id>.key` by default — doc §8 step 3 channel; the
   file stores only the key); `nil` for keyless scripts (server decides).
   place/game/user are feature-detected from the host (pcall-guarded).
5. `failures = checks:run()` BEFORE the payload fetch (§11: signals,
   never client-side verdicts). Any failure → `checks:report(...)` +
   silent no-load.
6. `hs.payload(session, nil, s)` — the per-fetch value `s` = the stub's
   `r` (§5.6 per-stub random, hex→raw 32 B), forwarded as the CCP-M6
   payload-key salt component (`buildHash || s`, M1 auth.ts formula).
7. M6 runtime entry `{ b = bundle, c = const_key, s = fetch_value,
   env = _G }` — containerless mode: the container (bundle) + constKey
   arrive per session; integrity is self-consistency over the delivered
   container (RUNTIME-M6 §4, CCP-M7 D-M5-20).

Every failure is a silent `(nil, code)` return — generic, no explanatory
text (doc §8 rules, §11 for tamper). Codes are internal diagnostics.

## Wire dependencies

- **`const_key` in the payload plaintext** (b64url 32 B) — tracked with
  main-agent (M1): RUNTIME-M6 §2 pins entry `c` as per-session delivered;
  the field does not exist on M1's wire yet. The glue reads it
  opportunistically; absent ⇒ generic payload failure. The M3 mock
  server + tests model the field (s-mode + const_key, 101/101).
- **CCP-M6 `s` in the payload request** — landed on M1's side already
  (auth.ts `payloadKeyFrom`); the handshake forwards it since this
  session.

## Run

```sh
cd loader/assembly
bun install
bun run typecheck   # tsc --noEmit
bun test            # 9 tests: full §8 flow under lua5.4 + build properties
```

The E2E tests assemble a REAL init (compiler fixture → M5 pack → M6
containerless emit) and run it under lua5.4 against the M3 mock M1
server (`tests/mock_server.lua`), with the driver faking the executor
surface env_executor feature-detects (`request`, HttpService-backed
JSON, optional `readfile`). Oracle = the fixture source run directly.

## Pipeline position

```
M4 parse/analyze → M5 compile/pack(constKey, opcodeSeed)
   → M6 emitRuntime({ container: null, ... })          (runtime source)
   → assembleInit({ runtimeSource, config, loaderRoot })   (this)
   → M13 packageInit(bytes, now) → build id → script_versions.init_build
```

M13 consumes the assembled bytes unchanged (`packageInit` produces the
content-addressed build id; the CDN serves `/static/init_<build>.lua`).

## Honest limits (NOT-RUN / by design)

- No REAL executor validation (fleet sandbox has none) — the driver
  fakes the exact surface env_executor detects; UNC variance is handled
  by feature detection at runtime.
- The tamper-REPORT path (`checks:report` on heartbeat) is not exercised
  E2E (tampering happens host-side, inside one entry call — covered by
  M7's own 40-check suite; the mount + silent-fail policy is covered
  here). The runtime-decoy path IS exercised E2E (tampered bundle →
  generic `load failed`).
- Key-cache WRITE side (SDK `save_key_cache`) is SDK-API only; the
  path convention `lp/<script_id>.key` is pinned here + in the SDK.
