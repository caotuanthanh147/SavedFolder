# VERIFICATION — M3 session 3 (init entry assembly), 2026-10-11

Owner: glm1. All commands run on the delivered Public tree
(fresh state at delivery commit), lua5.4.7 on PATH.

## Command/output evidence (§22.1)

```
cd loader/assembly
bun install          # 5 packages
bun run typecheck    # tsc --noEmit — clean
bun test             # 9 pass, 0 fail, 20 expect() calls [7.03s]
```

```
cd <repo root>
lua5.4 tests/run.lua             # M3 suite: 101 passed, 0 failed
lua5.4 tests/m7_checks_test.lua  # M7 regression: 40 passed, 0 failed
cd loader/stub && bun test       # M13 regression: 42 pass, 0 fail
```

```
cd obfuscator                     # untouched by this delivery (M6 v1.1 same session)
bun test                          # 385 pass, 0 fail (364 + 21 M6 v1.1)
```

## What the 9 assembly tests prove

E2E (real lua5.4, M3 mock M1, M6 containerless runtime, M4/M5-built
fixture container):

1. **keyless happy path** × 3 fixtures — stub payload → checks mount →
   sync/init → checks:run → payload (CCP-M6 s-salt + const_key wire) →
   VM runtime → stdout **byte-equal to the fixture oracle**.
2. **keyed happy path** — cache file → key → init body (KEYCHANNEL
   marker = the server saw the cached key) + oracle output.
3. **wrong cached key** → silent `(nil, "auth")`.
4. **tampered bundle bytes** → runtime self-consistency decoy → generic
   `load failed`.
5. **payload without const_key** → `(nil, "payload")` — the M1 wire
   field dependency, exercised explicitly.

Build-level: determinism (same runtime + config → identical bytes),
constKey-bytes-absent (no session secrets in a public artifact),
luac5.4 -p parse gate, config validation.

## M3 suite additions (95 → 101)

- s-mode payload succeeds; server sees `body.s` (CCP-M6 salt formula)
- const_key decoded to 32 B raw
- no-s legacy fallback still works
- oversize s rejected client-side
- (mock server: keyless mode + s/const_key support; run.lua: +6 checks)

## Bugs found and fixed during this session (all regression-tested)

1. **Double-call bug class (2 hits)**: factory-chunk modules are
   `chunk() → factory → factory(deps)`; the first wrapper called the
   chunk directly with deps (`chunk(deps)` ignores them and returns the
   factory). Hit in the assembled wrapper (`L(GLUE)(P)` → needed
   `L(GLUE)()(P)`) AND in the entry glue's module section (every module
   + Env/Checks/Handshake instantiation). Symptom: "attempt to index a
   function value". Fixed with the `mod()` helper + a wrapper comment.
2. **Test-side same bug** (driver module loading + MockServer/Signer).
3. **Test-only signer pk divergence**: baking RFC 8032 TV1's PUBLIC key
   while the mock signs with tests/ed25519_sign.lua, whose
   secret_to_public derives a different (self-consistent) pk — bundle_sig
   could never verify. Fixed by baking the signer's actual pk. NOTE:
   this is a TEST-ONLY helper property; the SHIPPED loader verifies and
   is RFC-vector-tested (M3 suite).
4. **Keyed-test assertion order**: guest output prints during the entry
   call, the KEYCHANNEL marker after — `startsWith` was wrong.

## NOT-RUN / honest limits

See README-ASSEMBLY.md ("Honest limits"): no real executor; the
tamper-REPORT path is M7-suite-covered, not E2E here (host-side
interception inside a single entry call); key-cache write side is
SDK-API only.
