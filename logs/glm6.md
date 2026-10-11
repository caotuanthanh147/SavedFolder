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

- **Addendum (same session, Public 008320a)**: handled the 4 msgs that
  landed mid-session (glm1 corpus-finding == my own fix — replied with the
  full bug list; glm1 CCP-M7 co-sign: their v1.1 containerless+b-mode
  landed AND flagged two M1-impact items — implemented sessionConstKey
  support (D-M5-27: fresh per-session pool key option, extractor constKey
  override for session-key trial; default per-version for direct
  extraction), confirmed PackParts already pins opcodeSeed; glm1 m6-v1.1
  FYI + glm3 M12 FYI consumed). Follow-up msg to main-agent
  (sessionconstkey wiring). Suites after addendum: obf 418/418 + vm
  84/84 + tsc ×2 + private corpus 49/49 re-run. Inbox cleared.

## Session 6 — 2026-10-11 ~06:50–07:30Z (str-encoding finding: root cause + fail-loud guard + gates re-green)

- Cold start (sandbox reset): re-cloned SavedFolder + Public, bootstrap glm6,
  watchers on. Read TASKS.md head-to-toe + ONBOARDING (again, per §5) +
  PROMPT + inbox (3 unread) + all status/.
- Inbox: (1) glm1 M6-s2 msg — SECOND M5 finding "container str encoding
  lossy >0xFF" (26/130 files, --wm EXPECTED-RED until my fix) + AAD sync
  owner-ACCEPTED + 4 trivial tsc fixes he'd already made in my tree;
  (2) glm4 sweep — compiler tsc 4 errors (same 4 glm1 fixed) + root-tsc
  miss mechanism (root tsconfig excludes compiler/); (3) glm3 Q5 landed
  (globalName classifier — additive, nothing needed).
- Evidence-first investigation (BEFORE code): read container.ts str paths
  (appendConst charCodeAt&0xFF; unpack fromCharCode) + watermark.ts junk
  carrier + M6 emit.ts pool decode template (byte-transparent pt:sub) +
  M4 lexer header. KEY FACT: M4's contract is the BYTE-STRING model
  (latin1 char-per-byte — src/index.ts header; my corpus runner reads
  latin1; the lexer expands \u{} to UTF-8 bytes). Wrote a repro (deleted
  after evidence capture): same file — latin1 read → const = e2 80 94 →
  round-trip byte-exact → interpreter stdout BYTE-EQUAL to real Lua 5.4;
  utf8 read (glm1's corpus-e2e.ts L122) → const = ONE code unit 2014 →
  truncated. Conclusion: container correct per contract; root cause = his
  runner's input decode. BEFORE-state reproduced exactly: --wm 26 MISMATCH
  (all "extraction failed post-pack"), exit 1.
- Fix (D-M5-28; Lua 5.4 manual §2.1 opened via curl — strings = byte
  sequences, 8-bit clean, encoding-agnostic): (a) container.ts appendConst
  FAIL-LOUD on code units >0xFF (no silent &0xFF; D-M5-22 posture);
  (b) corpus-e2e.ts L122 latin1 read + L56 latin1 write (marked, glm1's
  file, notified); (c) differential.test.ts + watermark.test.ts oracles
  byte-exact (spawnSync encoding:'buffer' + toString('latin1'));
  (d) fixtures.ts: byte-strings-unicode fixture (raw em-dash/emoji/CJK/
  bullet + \xFF/\x80 escapes + concat + #; AST consts hold UTF-8 BYTE
  sequences — caught my own fixture bug twice: who-var c3a7 bytes, missing
  print wrapper); (e) watermark.test.ts: 3 byte-string-contract tests
  (pack throws on text consts plain+watermarked; high-byte pools round-trip
  byte-exact + watermark lockstep).
- Docs: BYTECODE-M5 §1 normative byte-string pin + §11 changelog; RESEARCH
  #15-17 (manual + contract + repro); DECISIONS D-M5-28 (4 options, UTF-8
  rejected with evidence); VERIFICATION §9 (commands+outputs, honest
  NOT-RUN incl. runner stdout string-compare strictness note for glm1).
- Gates: compiler 83/83 (+4) + root 462/462 + vm 113/113 + tsc ×3 (all
  three tsconfigs, glm4's lesson applied) + corpus-e2e plain 0 MISMATCH +
  --wm 0 MISMATCH exit 0 (26 → 0 — EXPECTED-RED dropped).
- DELIVERED Public a23c636 (pull --rebase on clean d153caf, push, ls-remote
  verified). SavedFolder: TASKS LP1-M5 row s6 note + status + this log +
  msgs (glm1 root-cause+evidence+gate-green+drop-EXPECTED-RED; glm4 tsc
  ack-verified-green; glm3 Q5 ack + byte-string-pin FYI). Inbox cleared.

Stage: LP1-M5 s6 complete. Next lane: val-descriptor emission (M4
analysis.ts const-plan consumption), then real-Workers CPU, then v2
carrier 3 (Q5 globalName list).
