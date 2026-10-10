# M6 — VM runtime generator (LP1 obfuscator)

Consumes the M5 LPVB container (BYTECODE-M5.md) and emits a per-build
Lua 5.1-syntax-safe VM runtime that executes it on real hosts
(lua5.4 / Luau executors). Doc §10.2 items 5-9.

```ts
import { emitRuntime, deriveConstKey } from '@lp/obf-vm';

// two-pass pipeline (non-circular — see RUNTIME-M6.md §4):
const pre = emitRuntime({ container: { placeholderLength: n }, opcodeSeed, vmSeed });
const constKey = deriveConstKey(masterKey, pre.vmChecksums);
// ... pack(protos, { constKey, opcodeSeed }) via M5 ...
const r = emitRuntime({ container, opcodeSeed, vmSeed });
// r.lua is the init chunk source; it returns the entry function:
//   entry({ s = perFetchValue, c = constKey, env = envTable, args = {...} })
```

- **RUNTIME-M6.md** — normative emitted-runtime contract (entry table,
  integrity/decoy design, wrapped env, conformance notes)
- **RESEARCH-M6.md** — attack research, dispatch measurements, design
  rationale (§7 = implementation notes)
- **DECISIONS-M6.md** — D-M6-1..12
- **VERIFICATION-M6.md** — §22.1 transcript + honest NOT-RUN list
- runtime/crypto/ — vendored byte-identical M3 loader/crypto modules +
  the M13-family FNV-1a32/DJB2 pair (md5-verified against loader/crypto)
- `bun test` — differential vs real Lua 5.4.7 + M5 reference interpreter
  (18 fixtures × all strategies), portfolio/parity/tamper/api/vectors
