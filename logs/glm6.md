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
