# LP1 obfuscator demo — single-file protected artifact

This folder is the runnable proof of the LP1 obfuscation pipeline
(M4 front end → M5 bytecode compiler → M6 VM runtime generator).

## Run it in game

1. Open `lp1-demo.obf.lua` (58 KB, comment-free, Lua 5.1-syntax-safe).
2. Paste its whole content into your executor in ANY Roblox game and
   execute.
3. Expected: an in-game notification titled **"LP1 VM"** ("Obfuscated
   script is running"), and console output (`print`s) like:

   ```
   ==============================================
     LP1 PROTECTION DEMO - guest program running
   ==============================================
   fib(22)=17711 gcd(1071,462)=21
   primes<=60: 2,3,5,7,...,59
   upper=LP-1-VM-OBFUSCATION
   ...
   ==============================================
     ROBLOX ENVIRONMENT DETECTED
   ==============================================
   player=<your name> display=<display name>
   workspace children=<n>
   placeId=<id>
   notification=true
   tick 1/3 - still running
   tick 2/3 - still running
   tick 3/3 - still running
   ==============================================
     DEMO OK - every section completed
   ==============================================
   ```

The same file run under plain `lua5.4` prints the identical trace with
the console branch instead (that is the differential oracle the
pipeline is verified against — byte-equal, all dispatch strategies).

## What it exercises

Recursion, integer/float math, string library, concat, closures with
exclusive and SHARED upvalues, metatables (`__add`/`__index`/
`__tostring`), method calls, varargs + `select`, `pcall`/`error`,
table sort/concat, Roblox `game:GetService`, `SetCore` notification,
`task.wait` loops — all executing INSIDE the per-build VM interpreter,
on constants decrypted lazily from the embedded AEAD container.

## Files

- `lp1-demo.lua` — the guest SOURCE (plain Lua 5.1-syntax; dual-path:
  Roblox-visible output vs deterministic lua5.4 console trace).
- `lp1-demo.obf.lua` — the protected artifact (embedded container;
  built with seed `lp1-demo-001`, closure dispatch; reproducible).
- `../tools/obfuscate.ts` — the builder CLI.

## Build your own

```
cd obfuscator/vm
bun run tools/obfuscate.ts demo/lp1-demo.lua my.obf.lua --seed my-seed
# options: --dispatch chain|tree|closure   --wm <32 hex chars>
```

`--seed` makes the build reproducible (same seed + same source →
byte-identical artifact). `--wm` packs a WATERMARKED container (CCP-M7
leak tracing — `extractWatermark` recovers your 16-byte watermark from
a stolen copy). Determinism, tamper posture (ciphertext flip or wrong
key → generic `load failed`, zero output), and byte-equality vs the
source under real lua5.4.7 are all gate-tested.

## Notes

- This embedded shape is the ONE-ARTIFACT form (runtime + container
  together, RUNTIME-M6 §1). The platform's deployment shape stays
  containerless (per-session container over the M1 wire, doc §8 step
  10) — same pipeline, different assembly.
- Guest scripts should avoid 2+ CALL expressions inside one `..`
  concat chain until the M5 `compileCall` arg-window fix lands (finding
  msg'd to glm6 2026-10-11; this demo hoists such calls to locals).
