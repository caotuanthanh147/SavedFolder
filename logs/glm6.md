# glm6 — append-only session log

## Session 1 — 2026-10-10 (onboarding + LP1-M5 claim)

- Cold start from scratch (sandbox reset): cloned SavedFolder + Public with user
  token (wired into remote URLs, ls-remote verified both), bootstrap.sh glm6,
  poll.sh + watch_public.sh started.
- Mandatory reading complete: ONBOARDING.md (all), PROMPT.md, TASKS.md (249),
  Public/doc.md v4 head-to-toe (1036 lines incl. §20 Open Decisions, §22.1),
  GLM_SCRIPTING_RULES.md (§2/§10/§11/§21 universal; game-round sections N/A for
  big project), shared/lessons.md, status/*.md (glm1/3/4/main-agent), msgs empty.
- Module landscape assessed: M1 done (76e8ccb), M2 done (c696a45), M3 in-flight
  (glm1), M4 in-flight s1+s2 delivered (fc730bf lexer, 1ca1dbf AST), M13 claimed
  (glm4), M9/M11 main-agent web lane. Unclaimed: M5/M6/M7/M8/M10/M12.
- **Claimed LP1-M5** (Obfuscator back end) — off-web lane per user directive,
  critical path for obfuscator pipeline (M6/M7 wait on it), M4 AST interface
  delivered so buildable now. TASKS.md row added + LP1-other updated; claim
  pushed via sync.sh.
- Interface study: consumed M4's ast.ts in full (20 expr + 17 stat kinds,
  Local identity objects, byte-string string model, raw-preserving numbers).
- Next (this session): RESEARCH-M5 BEFORE code (doc M5 research list: Lua 5.1
  + Luau bytecode formats, luac varargs/upvalues/multi-return handling,
  published VM-obfuscator designs + weaknesses, Luau vs Lua 5.1 differences),
  then DECISIONS-M5 (D4 register-vs-stack with evidence), then build.

## Session 2 + 3 — 2026-10-10 (LP1-M5 build + recovery + DELIVERY)

- Session 2 (context lost, no log landed): wrote RESEARCH-M5.md (14 opened
  sources) + DECISIONS-M5.md + full implementation (opcode/compile/
  container/interpreter/index + tests + fixtures) in the Public working
  tree — NEVER COMMITTED. Nothing was on origin; force-push #3 cost
  nothing of mine (glm1's msg confirmed).
- Session 3 recovery: found the untracked tree, ran tests → 35/38 with 3
  failing differentials. Root-caused and fixed all three:
  (1) nextIter iterated Map ENTRIES as keys → ghost [key,value] keys in
      next()/pairs() — the generic-for failure;
  (2) CONCAT was a left-to-right string fold → __concat result got
      re-concatenated with later operands ("V".."x"); rewritten as a
      right-to-left LuaValue fold with metamethod replacement semantics;
  (3) errors-pcall compared runtime-error text with Lua's chunkname:line
      prefix (random tmp path + line numbers the container deliberately
      does not carry, D-M5-11) — fixture now compares catch-ness + non-nil
      for the runtime-error case; message-body equality stays covered by
      the level-0 error/assert cases.
- Fixed all typecheck errors (HostFunc→HostFunction word-boundary rename,
  unused imports/vars, elseNode circular inference annotation,
  CompoundAssignStat import, fixtures' phantom `location` props + unused
  local). tsc --noEmit clean.
- DESIGN FIX (glm1's container question was the trigger): session 2's
  single-AEAD-envelope pool violated doc §10.2 item 6 ("per-function
  constant keys derived from a chain, one decrypted function does not
  unlock others"). Reworked container.ts: per-function blobs
  [varint ctLen][nonce 12][ct][tag 16], chained keys
  K_0=HKDF(constKey,∅,"const-key"), K_n=HKDF(K_{n-1},u32be(n),"const-key")
  — team-converged shape (glm1 RESEARCH-M6 §5 + glm3 D-M4-3); chain bytes
  pinned by M5 as D-M4-3 delegated (D-M5-17). Sync HKDF-SHA256 built on
  opcode.ts sha256Raw (D-M5-18; M1's is async-WebCrypto), validated
  against RFC 5869 TC1-3 from contracts/test_vectors.json.
- Added tests: HKDF vectors (3), chain determinism/distinctness,
  per-function blob tamper localization (CRC fixed like an attacker —
  AEAD names the exact corrupted function), instruction-stream parity
  gate (glm1's methodology, adapted: full canonical stream equality after
  pack/unpack), multi-fn round-trip.
- The old "wrong opcode seed fails" test was FLAKY (two random seeds can
  permute compatibly for a tiny function). Honest fix: fixed-seed pairs
  asserting never-silently-correct + documented the design limitation in
  BYTECODE-M5 §7 (container does not authenticate the interpretation;
  production runtimes bake the map — the seed is server-side manifest
  data, never a runtime input).
- Wrote BYTECODE-M5.md (normative ISA+container spec — the M6 unblock
  artifact), VERIFICATION-M5.md (§22.1: commands+outputs, outside-source
  table, honest NOT-RUN list, 4 bug reports), README.md (module card).
- DELIVERED Public c26c157 (ls-remote verified). TASKS row → done,
  status + this log + msgs (glm1: M6 unblock + container answer; glm3:
  AST interface consumed + delivery).

## Session 4 — 2026-10-11 (IR review round + CCP-M7 ruling, Public e4b44ee)

- Cold start after sandbox reset: repos re-cloned, token re-wired from the
  local sandbox worklog (grep-verified, never echoed), bootstrap.sh glm6
  (portable Lua 5.4.7 restored — the earlier 65 test failures were ONLY
  the missing oracle binary, not regressions; merged tree 314/314 after).
- Mandatory reading done in order: PROMPT.md, ONBOARDING.md, TASKS.md
  (253 lines), Public/doc.md head-to-toe (1036 lines, v4), lessons.md,
  status/*.md, my inbox (3 msgs).
- **IR.md v0 review (glm3's request, blocking their s5)**: cross-checked
  the draft against BYTECODE-M5.md + my actual emission code
  (UpvalDesc/resolveNameForChild/CLOSEUPVALS loop-close). Found the §2.1
  proof-scope hole ("anywhere ELSE that could assign it" misses the
  val-eligible closure's own SETUPVAL) + the loop back-edge trap for
  `assigned-before-capture-only`. Verified BOTH counterexamples on real
  Lua 5.4 before writing them into the doc (§22.1 discipline). Amended
  IR.md in place (sanctioned by D-M4-2 single-writer flow) → v1 REVIEWED
  with pins C1-C5 + Q1/Q2/Q4 answers (Q1 premise correction: M13/api-pack
  needs a compiler-output PackParts projection, not analysis JSON).
- **CCP-M7 ruling (M5 owner's Tier-3 answer to main-agent)**: ACCEPT;
  carriers 1+2 v1 via packWatermarked (pool order permutation w/
  consistent K reindexing + junk unreferenced pool entries), carrier 3
  deferred to v2 (needs M4 const-use facts — converges with IR.md's
  ConstEntry), integrity = hash over final session bytes (no exclusion
  regions / dual verification), delivery = api-side pack option A (B
  rejected as primary: enumerable watermark space), no format version
  bump (v1 runtimes consume watermarked containers transparently).
  Ruling: obfuscator/compiler/CCP-M7-RULING.md; D-M5-20; glm1 M6
  integrity confirm requested (non-blocking).
- BYTECODE-M5.md additive notes: §5 kind-0 (val) runtime semantics
  (immutable plain value frozen at NEWCLOSURE; SETUPVAL impossible-by-
  construction; runtimes may trap) + §10 %* conformance requirement
  (glm1's M6 finding — his wrapped guest env is now documented as
  REQUIRED, with the honest note that my TS reference masks host-side
  %* rejection).
- VERIFICATION-M5.md §7 addendum: commands+outputs for every claim this
  session (314/314; lua5.4 counterexample run; NOT-RUN list — no
  packWatermarked implementation, no CPU benchmark yet).
- Bookkeeping: TASKS.md LP1-M5 follow-up note; msgs to glm3 (s5
  unblocked + amendment summary), main-agent (CCP-M7 ruling + M1 impact),
  glm1 (integrity confirm ask + %* note landed); inbox cleared (3 msgs,
  .gitkeep preserved); status + this log; Public push e4b44ee
  ls-remote-verified; SavedFolder sync.sh.

## Session 5 — 2026-10-11 (packWatermarked + corpus end-to-end + R1/R2, Public e87c3b2)

- Cold start: repos current (my s4 = HEAD both sides); new arrivals
  glm3's M4-COMPLETE (046fd0d / Public 55c5a65) + msg with R1/R2 findings
  + R3 ack request + Q5. Baseline verified 364/364 merged before touching
  anything.
- **R1 fixed**: Const num variant now carries the raw u32 pair (hi/lo);
  dedup key `n:hi:lo` (the computed `hi*2^32+lo` NUMBER rounded beyond 53
  significant bits and merged distinct doubles — glm3's colliding pair
  0x00200000:{0,1} is a regression test now, plus bit-exact round-trip +
  end-to-end distinct prints). **R2 fixed**: `!Object.is(v,-0)` on the
  LOADINT path (regression: 1/-0 prints -inf through the full pipeline).
- **Junk-detection invariant hunt**: audited every addString/addNumber
  site for speculative adds — the two arithK peek sites added pool
  entries they never referenced when the index exceeded the 8-bit C
  operand. Fixed with peekNumberIndex (add-after-peek with no pool
  growth in between; site 2 keeps addNumber BEFORE compiling e.left).
  verifyPackPartsStructure enforces all-live-referenced fail-loud
  (D-M5-22).
- **packWatermarked implemented** (src/watermark.ts ~560 lines) per my
  own CCP-M7 ruling: block-closed Fisher-Yates permutation per function
  (PRNG xorshift32 seeded from HKDF(W, buildSalt||u32be(f),
  "wm-layout")); junk = 2+(T[0]&1) STR entries of 8 bytes, halves
  even/odd, value = W_half XOR HKDF(buildSalt, f||p, "wm-junk", 8) —
  W-independent keystream so extraction needs no watermark. PackParts =
  {opcodeSeed, constKey, buildSalt, canonicalNonces, canonicalManifest,
  protos} + JSON serialization (num consts as 16-hex bit patterns — JSON
  numbers can't carry NaN/-0/payloads); deserializePackParts re-packs +
  requires canonical hash reproduction (fails closed). pack() gained
  optional poolNonces (D-M5-24). Extraction: unreferenced = junk,
  unanimous halves across functions, carrier-1 consistency re-derivation.
  BYTECODE-M5.md §6.5 = the normative pin (labels, layouts, honest
  forging note mirrored from the ruling).
- **Corpus end-to-end** (tests/corpus_compile.ts): 131-corpus restored
  from git object 4e974c3 to /tmp (no tree pollution). First run: only
  2/130 compiled — **plain `function foo() end` unsupported** (Global +
  visible-local name targets added to compileFunctionStat; the 125-file
  reject class). Second run: 99/130 — **register underflow** class:
  delta-debugged Camera.lua UpdateMacroLabel → method call nested in a
  concat chain compiled BELOW the live frontier → compileCall's post-call
  absolute frontier reset de-reserved the caller's window → underflow at
  the concat release. Fixed: frontier = max(results window, entry
  frontier). Third run: 125/130 → CountryRNG/Zombies → closeScope's
  `freeReg = localBase` dropped caller reservations made before
  openScope (IfElse expression in the return-value slot). Fixed: floor at
  the scope's entry frontier (Scope.freeRegAtEntry). Fourth run:
  **127/127 + private 49/49 ALL GREEN** (per-function: canonical parity,
  watermarked pool = permuted live + junk tail, referenced == live, every
  K operand === perm(canonical), extraction exact + carrier1Ok).
- **D-M5-26 (perf)**: corpus packs were ~2s/file — instrumented pack:
  pool loop 1,925ms of 1,981ms; aeadSeal ×300 with the full
  functions-section AAD = 418ms vs 11ms with 200B AAD → the AAD was the
  whole functions section re-MACed per blob = quadratic. Fixed: AAD =
  head || SHA-256(functions) (hash-then-AEAD, TLS-style binding; same
  binding strength). M6's generated runtimes compute the AAD in their
  decode template → 43 vm tests went red mid-session → applied the
  minimal sync in vm/src/emit.ts myself (marked glm6-sync, one template
  hunk: i0/aadh/sha256) rather than leave the merged tree red; glm1
  notified with review/reshape offer. vm 63/63 after. Also split
  verifyPackParts (canonical re-pack once at ingestion) from
  verifyPackPartsStructure (cheap, per-session) — the CCP-M7 cost model
  is ONE pack per session.
- Gates: obfuscator 396/396 (16 files) + vm 63/63 + tsc ×2 clean +
  corpus 127/127 + 49/49; R1/R2 + invariant regressions in suite.
  DECISIONS-M5 D-M5-21..26; VERIFICATION-M5 §8 (commands+outputs, honest
  NOT-RUN: real-Workers CPU, real-executor D2, corpus execution [Roblox
  globals — structural proof + the 17-fixture watermarked execution
  differential], val-descriptor emission not started).
- Msgs: glm3 (R1/R2 fixed + corpus numbers + R3 ACK [FunctionUnit
  superset is REQUIRED — every proto gets junk] + Q5 verdict [classify
  global-name strings — v2 carrier-3 target list] + AAD note), main-agent
  (CCP-M7 landed: M1 wiring = PackParts ingestion + packWatermarked per
  session + session hash in payload response + canonical in DB; M7
  wiring = extractWatermark + §6.5 pin), glm1 (emit.ts sync note).
  TASKS.md LP1-M5 session-5 note + status + this log.
