# RESEARCH-M7 — session 2 addendum (Lua §11 checks module)

Owner: main-agent (module M7). Scope: the client-side §11 checks module that
session 1 deferred (D-M7-10). Sources studied BEFORE code, per doc rules.

## Sources reviewed this session

| # | Source | Kind | What it pins for s2 |
|---|---|---|---|
| S1 | `obfuscator/vm/RUNTIME-M6.md` (glm1, pinned v1) | repo, normative | Entry table `{s, c, env, args, nargs, dbg}`; §4 integrity→derivation is ALREADY implemented at the container level (hash match + well-formed `s`/`c` ⇒ `K_0 = HKDF(c,…)`; anything off ⇒ decoy `K_0 = HKDF(bh,…)`; AEAD tag failures surface as generic `load failed`). Whole-file self-integrity is M13's `r` validation (FNV+DJB2+size). Runtime-source self-checksumming explicitly listed NOT-RUN/D2 — NOT M7's to re-implement. |
| S2 | `loader/sdk/library.lua`, `loader/init/handshake.lua` (glm1, M3) | repo, normative | Env shape (`request/json_encode/json_decode/os_time/random_bytes/file`); `common_headers` proof formula `method|path|ts|nonce|sha256(body)` HMAC-SHA256 hex; factory-chunk module style `return function(Crypto, Env) ... end`; Lua 5.1-syntax discipline. Heartbeat client DOES NOT EXIST in M3 (sdk = sync/status/check_key/cache; handshake = sync/init/payload) — the s2 module owns the minimal heartbeat POST. |
| S3 | `loader/sdk/env_executor.lua` (glm1, M3) | repo | UNC feature-detection pattern (resolve aliases, pcall everything, degrade to nil). `request`/`http_request`/`syn.request` alias probing is EXPECTED variance, not tamper (RESEARCH s1 #9). |
| S4 | `loader/stub/DECISIONS-M13.md` D-M13-6 | repo | Stub→init handoff: `entry = loadstring(data)(); entry(payload)` with `{api, script_id, build, t, s, r}` — the init entry function is where M7 checks mount (capture before handshake, run before payload/runtime, report on failure + silent no-load). |
| S5 | `api/src/auth.ts` heartbeat handler (s1, mine) | repo, normative | Tamper wire as landed: `{v:1, session_token, tamper?:{check≤64, detail≤128}}` → event `tamper` detail `client:<check>[:detail]`, recorded BEFORE the kill check, response = normal envelope. Proof headers required (x-ts/x-nonce/x-lv/x-proof over the same formula). Malformed tamper silently ignored. |
| S6 | RESEARCH-M7 session 1 findings #1, #9-#12 | prior work | Executor injects identity headers into the headers table during `request` (§1.2.9 observed); `newcclosure` re-wraps a closure to appear native (defeats naive tostring checks → identity-over-time instead); debug hooks inflate per-instruction cost by orders of magnitude (timing with median-of-samples + generous threshold, os.clock granularity ~15ms on Windows); §11 philosophy = signals not verdicts, silent failure, server-side correlation. |

## New findings (s2)

| # | Finding | Source | Consequence |
|---|---|---|---|
| S2-1 | Server-reproducible derivation CANNOT include an env digest. §11 "integrity checksums feed key derivation (10.2 item 9)" is implemented at the container level by M6 (S1): the inputs (container hash, build hash, `s`, constKey) are all server-known. An environment digest is client-only state; feeding it into payload/session keys would either (a) break the server's ability to derive the same key, or (b) if transmitted, be forgeable by a cheating client (doc §3: client code never trusted). | RUNTIME-M6 §4 + doc §3/§5.5 | Env-check integrity must feed DERIVATION-ADJACENT behavior only: the digest is exposed to the init for decoy-path variation and lands in tamper detail. Honest scope note in DECISIONS (D-M7-11), no fake claim of derivation binding. |
| S2-2 | `tostring(fn)` on Lua 5.1/5.4/Luau returns a stable address form (`function: 0x…` / `function: builtin: X`) for the same function object for its lifetime; `hookfunction`/`replaceclosure` swaps and `newcclosure` re-wraps produce a DIFFERENT function object (new address). Two-capture comparison (baseline at init vs re-capture at run) therefore detects post-baseline hooking even when the wrapper claims nativeness. | PUC Lua 5.4 manual §6.1 (tostring), Luau semantics [model knowledge], RESEARCH s1 #10 | Identity check = tostring equality over a pinned critical-function set, captured twice (t0 baseline + run), plus an immediate double-capture at t0 to catch active swapping. |
| S2-3 | The headers table the SDK passes to `Env.request` is the natural instrumentation surface: §1.2.9 (observed) shows executors ADD identity headers into it; an HTTP-spy wrapper typically also mutates/replaces entries (rewrite, add trace ids). Removals/rewrites of SDK-set keys are as strong a signal as additions. | doc §1.2.9 [repo, observed] | Header check: snapshot keys before the call; after the call, diff = (added − taught set) and (SDK-set keys removed/changed). First successful call TEACHES the executor's normal injection set (expected variance, S3); later unknown additions = signal. Case-fold keys (executor header casing varies). |
| S2-4 | A Lua-heavy fixed work unit (SHA-256 over a fixed buffer, ~10⁴ VM instructions) inflates ~10³× under a debug-hook single-stepper; real-world lag spikes are absorbed by median-of-N; os.clock granularity (~15ms Windows) is irrelevant at that inflation ratio. Threshold ≥20× median vs baseline is generous to low-end devices while still catching single-stepping. | RESEARCH s1 #11 [model knowledge] | Timing check = median of 5 samples of sha256(constant 64B) vs baseline median of 9; failure only at ≥20×. |
| S2-5 | Global-set consistency must be tolerance-typed: executors legitimately differ (UNC feature detection, S3), so the check compares the SAME machine to ITSELF over time (baseline snapshot vs run snapshot: types + identity strings of a pinned global list + executor identity + version string), not against a hardcoded "clean" profile. | S3 + doc §11 "environment consistency" | Env check = baseline-vs-run self comparison; cross-executor server-side correlation stays in abuse scores (D-M7-7). |
| S2-6 | Test environment: lua5.4 + luac5.4 available in the fleet sandbox (M3's run.lua pattern); M3's tests/run.lua is glm1-owned — s2 tests live in a separate `tests/m7_checks_test.lua` runner following the same conventions (check(name, got, want), mock Env). Parse gate `luac5.4 -p` mirrors RUNTIME-M6 §1's gate. | repo | Module + tests land under `loader/checks/` + `tests/m7_checks_test.lua`; no edits to glm1-owned files. |

## NOT-RUN / honest limits (s2)

- No real-executor validation (sandbox has no Roblox executor) — module is
  validated on lua5.4 with mock environments per S2-6; UNC variance is handled
  by feature-detection + self-over-time comparison, but real-executor quirks
  (e.g. exotic header casing, `tostring` on wrapped C functions) can only be
  observed in the field.
- No container carriers (still CCP-M7, glm6 has not ruled — no msgs as of
  this session).
