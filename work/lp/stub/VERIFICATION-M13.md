# VERIFICATION-M13 — §22.1 verification transcript

Per doc.md §22.1: every claim has the command and output attached; tests
derive from outside sources (RFC/draft vectors, BigInt ground truth, an
independent Lua harness) rather than restating the implementation; the
NOT-RUN list is explicit. All commands were run on the delivered bytes in
`loader/stub/` after the final edit (2026-10-10, session glm4-1).

## Environment

- bun 1.x test runner, TypeScript 5.9 (`tsc --noEmit`)
- Lua 5.4.7 portable (`~/.lua54/bin/lua5.4`, `luac5.4`) as the plain-Lua
  stand-in for executor Luau (syntax gate + behavioral harness)

## 1. Test suite (bun)

```
$ cd loader/stub && bun test
42 pass / 0 fail / 179 expect() calls / 5 files [86ms]
```

Coverage by file:
- `test/hashes.test.ts` — FNV-1a 32-bit KATs from draft-eastlake-fnv
  (all four published vectors, the 4th built as raw bytes since
  TextEncoder re-encodes >0x7F code points); mul32 vs BigInt sweep;
  DJB2 vs an independent BigInt formulation; NUL/binary safety.
- `test/initpack.test.ts` — determinism, content-sensitivity
  (different content → different build id), sha256 cross-check vs
  crypto.subtle, build-id format gate (rejects traversal/uppercase/short).
- `test/generator.test.ts` — per-fetch uniqueness (body, stub id, random),
  determinism under injected randomness, header contract (no-store),
  embedded-value spot checks, unsafe-number rejection, escapeLuaString,
  no-goto / no-Luau-only-syntax sweep over the rendered body.
- `test/routes.test.ts` — /loaders unique-per-fetch + no-store; 404/400/500
  paths all no-store; /static exact bytes + immutable headers; edge-cache
  hit/miss accounting (blob read once, second request from cache);
  malformed build/script ids rejected.
- `test/lua-harness.test.ts` — drives `lua/harness.lua` end-to-end (below)
  plus `luac5.4 -p` syntax gate and a negative test (stale expected hashes
  → stub refuses to run the init, exit 1).

## 2. Type check

```
$ bun run typecheck   # tsc --noEmit
(clean, no output)
```

## 3. No-goto sweep (doc.md hard rule)

```
$ rg -n "goto" src/ lua/
(no matches)
```

## 4. Lua syntax gate (generated stub is plain valid Lua)

```
$ <generate a stub via generateStub>
$ luac5.4 -p stub.lua
OK (exit 0)
```

## 5. Executor-environment behavioral harness (lua5.4, standalone)

Simulates the UNC executor surface (request/readfile/writefile/isfile/
isfolder/makefolder/bit32/loadstring) over a real temp dir; runs the actual
generated stub; asserts outcomes. Outside-source properties tested: UNC
response shape (Potassium request docs), readfile-errors-on-missing (Solara
docs), isfile-absent fallback via pcall(readfile) (Infinite Yield pattern).

```
$ lua5.4 lua/harness.lua <scenario> stub1.lua stub2.lua init.lua <tmpdir>
scenario fresh:          0 failure(s)   download→validate→cache→run, payload passthrough
scenario cache-hit:      0 failure(s)   second stub run: no re-download, init runs from cache
scenario corrupt-cache:  0 failure(s)   same-size byte flip detected (dual hash), repaired
scenario truncated-cache:0 failure(s)   size mismatch detected, repaired
scenario no-bit32:       0 failure(s)   DJB2+size path validates; tamper still detected
scenario write-fail:     0 failure(s)   init runs without cache, no failure shown
scenario download-fail:  0 failure(s)   generic failure, nothing loaded/cached
scenario bad-body:       0 failure(s)   tampered 200-body rejected before loadstring
scenario no-request:     0 failure(s)   clean generic failure
scenario no-loadstring:  0 failure(s)   clean generic failure
(all exit 0)
```

Full per-assertion transcript of the `fresh` scenario (13/13 ok) is in the
session log; each line checks one property (single download, init ran once,
no failure message, payload field-by-field vs the stub's own embedded
constants, cache file written byte-identical, URL targets /static/init_).

## 6. Cross-implementation evidence (doc §9)

TS (generation side) and Lua (stub side) compute FNV-1a/DJB2/length over
the same init bytes: the Lua stub validates the file using expected values
produced by the TS generator — every green scenario above is a successful
TS→Lua cross-check, and the stale-hash negative test fails closed.

## NOT-RUN list (honest limits, §22.1)

- **Real-executor runs** (Synapse/Potassium/Solara/Delta/…): not run — no
  executor in this sandbox. The §22.1 real-environment table (stub cache
  first/second run, corrupted cache, no-write-permission, per-executor FS
  availability matrix, request() header injection) is the human test for
  this module; the lua harness mirrors the documented semantics.
- **Real Cloudflare edge**: `caches.default` behavior verified against docs
  only; the MapCache test double models match/put. Real-Workers smoke test
  is M1/M12's deployment lane.
- **Luau runtime** (as opposed to lua5.4): syntax gate proves plain-Lua
  5.1-family compatibility; Luau-specific runtime behavior (bit32 present)
  is modeled by the harness shim, not a real Luau.
- **Performance on real executors**: benchmark numbers in RESEARCH-M13 are
  lua5.4 evidence only.
- **M3's real init script**: not yet delivered by glm1 — the harness runs a
  mock init honoring the D-M13-6 entry-function contract (msg'd to glm1).
